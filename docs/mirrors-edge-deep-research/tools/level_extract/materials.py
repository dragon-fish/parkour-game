"""Bake a material's DiffuseColor and opacity to a small image by evaluating a
subset of its expression graph on the CPU.

Why evaluate instead of taking "the diffuse texture": the original packs data
into channels and tints with parameters. The skyscrapers' _D texture is R and G
detail plus a B glass mask, averaged and multiplied by a DiffuseColor parameter;
drawn as-is it is a yellow and blue stripe. Nodes that cannot be evaluated here
(cube maps, pixel depth, fresnel) contribute a neutral 0.5.

Mips are read inline from the package up to the configured size. A map
package's copy of a texture keeps only mips up to 64 px inline and flags the
rest as stored elsewhere; there is no texture cache file in the install, and
the full mips are in the shared .upk of the same name (packages.texture_sources).
"""
import base64
import collections
import math
import struct
import zlib

import numpy as np
from lzallright import LZOCompressor

import packages as pk
from common import ExtractError

CHUNK_TAG = 0x9E2A83C1
# A parameter-driven coordinate that is not a TextureCoordinate node (panners,
# math on UVs) cannot be baked; the bake uses UV set 0 at tiling 1 for it.
PLAIN_COORDINATE = (0, 1.0, 1.0)
# Past this mean share of its colour coming from a cube map, a surface is lit by
# the cube (ambient), not reflecting it: see MaterialBaker._mirror().
MIRROR_AMBIENT_SHARE = 0.9


class MaterialBaker:
    def __init__(self, packages, max_px, report):
        self.packages = packages
        self.max_px = max_px
        self.stats = collections.Counter()
        report['materials'] = self.stats
        self._pixels = {}

    # -------------------------------------------------------------- lookup

    def resolve(self, mr, ref):
        """(reader, export index) of an object reference, crossing packages."""
        if ref > 0:
            return mr, ref
        if ref < 0:
            try:
                root, path = pk.import_path(mr.pkg, -ref - 1)
            except ExtractError:
                self.stats['import_under_export'] += 1
                return None, None
            shared = self.packages.shared_reader(root)
            target = pk.find_export(shared, path) if shared else None
            if target:
                return shared, target
        return None, None

    # ------------------------------------------------------------ textures

    def texture(self, mr, ref):
        tr, ti = self.resolve(mr, ref)
        if not tr or tr.pkg.class_of(tr.pkg.exports[ti - 1]) != 'Texture2D':
            return None
        key = (tr.label, ti)
        if key not in self._pixels:
            self._pixels[key] = self._decode(tr, ti)
            self.stats['texture_ok' if self._pixels[key] is not None else 'texture_unusable'] += 1
        return self._pixels[key]

    def _decode(self, tr, ti, follow=True):
        props, native = tr.props(ti)
        fmt = str((props or {}).get('Format'))
        if fmt not in ('PF_DXT1', 'PF_DXT3', 'PF_DXT5'):
            return None
        d = tr.d
        source_size = struct.unpack_from('<i', d, native + 8)[0]
        p = native + 16 + max(source_size, 0)
        mips = struct.unpack_from('<i', d, p)[0]
        p += 4
        best = None
        stripped = False
        for _ in range(mips):
            flags, count, disk, _offset = struct.unpack_from('<4i', d, p)
            p += 16
            start = p
            inline = not (flags & 1)
            if inline:
                p += disk
            w, h = struct.unpack_from('<2i', d, p)
            p += 8
            if inline and disk > 0 and max(w, h) <= self.max_px and (best is None or w > best[0]):
                best = (w, h, start, disk, flags, count)
            elif not inline and max(w, h) <= self.max_px:
                stripped = True
        if stripped and follow:
            # A map package's copy, its larger mips left out: the shared
            # package of the same name has them (PackageSet.texture_sources).
            for source, si in self.packages.texture_sources(tr.pkg.exports[ti - 1]['name']):
                pixels = self._decode(source, si, follow=False)
                if pixels is not None and (best is None or pixels.shape[0] > best[1] or pixels.shape[1] > best[0]):
                    self.stats['texture_from_shared_package'] += 1
                    return pixels
        if not best:
            return None
        w, h, start, disk, flags, count = best
        raw = d[start:start + disk]
        if flags & 0x10:
            raw = unchunk(raw)
        if len(raw) != count:
            raise ExtractError('%s: mip is %d bytes, expected %d' % (tr.label, len(raw), count))
        return decode_dxt(raw, w, h, 'PF_DXT5' if fmt == 'PF_DXT3' else fmt)

    # ---------------------------------------------------------------- bake

    def bake(self, mr, idx):
        """{'width', 'height', 'png' (base64 RGBA PNG), 'uv_set', 'tiling'} or None."""
        params = {}
        root_reader, root = self._collect_params(mr, idx, params)
        if not root_reader:
            self.stats['no_root_material'] += 1
            return None
        # Two passes. The first finds which coordinate the image is baked in; the
        # second evaluates again with every sample on another coordinate reduced
        # to its average colour. Baking a whole-road dirt map (UV set 0, tiling
        # 1) into asphalt space (UV set 1) repeated the map in every tile.
        coord = None
        for _ in range(2):
            ev = Evaluator(self, root_reader, params, coord)
            ins = ev.inputs(root)
            diffuse = ins.get('DiffuseColor') or ins.get('EmissiveColor')
            if not diffuse or diffuse['expr'] <= 0:
                self.stats['no_diffuse_input'] += 1
                return None
            try:
                color = ev.value(diffuse, np.full(3, 0.5))
                opacity = ins.get('OpacityMask') or ins.get('Opacity')
                alpha = ev.value(opacity, np.ones(1)) if opacity else np.ones(1)
            except (IndexError, ValueError) as error:
                self.stats['evaluation_error ' + type(error).__name__] += 1
                return None
            explicit = [c for has, c in ev.coords if has]
            chosen = explicit[0] if explicit else (ev.coords[0][1] if ev.coords else PLAIN_COORDINATE)
            if coord is not None or len({c for _, c in ev.coords}) <= 1:
                break
            coord = chosen
            self.stats['mixed_coordinates'] += 1
        for cls, n in ev.unsupported.items():
            self.stats['unsupported ' + cls] += n
        shape = ev.shape or (4, 4)
        color = color[..., :3] if color.shape[-1] >= 3 else np.repeat(color[..., :1], 3, -1)
        color = np.broadcast_to(color, shape + (3,)) if color.ndim == 1 else resize(color, shape)
        alpha = alpha[..., :1]
        alpha = np.broadcast_to(alpha, shape + (1,)) if alpha.ndim == 1 else resize(alpha, shape)
        rgba = np.clip(np.concatenate([color, alpha], -1), 0.0, 1.0)
        coord = chosen
        if coord[0] == 'computed':
            self.stats['computed_coordinates'] += 1
            coord = PLAIN_COORDINATE
        self.stats['baked'] += 1
        out = {'width': shape[1], 'height': shape[0], 'png': png_base64(rgba),
               'uv_set': int(coord[0]), 'tiling': [float(coord[1]), float(coord[2])]}
        # How the surface shines, for the builder. The original reflects the sky
        # through a cube map sampled into one of the root inputs (a glass
        # facade's EmissiveColor, typically); the bake above reads that sample
        # as a flat 0.5, so which inputs reach one is recorded here instead.
        reflection = sorted(n for n, link in ins.items() if link and link['expr'] > 0 and ev.reaches_cube(link['expr']))
        if reflection:
            out['reflection'] = reflection
            self.stats['reflective'] += 1
            mirror = self._mirror(root_reader, root, params, ev.coordinate_filter, shape)
            if mirror is not None:
                albedo, share, emissive_sheen = mirror
                rgba = np.concatenate([albedo, rgba[..., 3:]], -1)
                out['png'] = png_base64(rgba)
                # The share every pixel has is a sheen over the whole surface,
                # what rises above it is a mirror in part of it. One would cost
                # the other its sunlit shading if both were drawn metallic.
                floor = float(share.min())
                out['sheen'] = round(max(floor, emissive_sheen), 4)
                metallic = share - floor
                if metallic.max() >= 0.05:
                    out['metallic_png'] = png_base64(metallic[..., None])
                self.stats['mirrored'] += 1
        for key, name in (('specular', 'SpecularColor'), ('specular_power', 'SpecularPower')):
            link = ins.get(name)
            if link and link['expr'] > 0:
                try:
                    out[key] = round(float(np.mean(ev.value(link, np.ones(1))[..., :3])), 4)
                except (IndexError, ValueError):
                    pass
        if 'specular_power' in out:
            # Blinn-Phong exponent to GGX roughness, the usual sqrt(2 / (n + 2)).
            out['roughness'] = round(math.sqrt(2.0 / (max(out['specular_power'], 0.0) + 2.0)), 4)
        return out

    def _mirror(self, mr, root, params, coordinate, shape):
        """(albedo HxWx3, mirror share HxW, sheen share) where a cube map puts
        the sky into the surface, or None.

        Evaluated with the cube at 0 and at 1: what changes is the part of the
        colour that comes from the sky. Through DiffuseColor that is a masked
        mirror (a facade's windows) and becomes metallic per pixel; through
        EmissiveColor it is a wet or polished sheen added over the whole
        surface (a stormdrain floor, a pipe) and becomes a clearcoat only --
        drawn metallic, the airlock floor was a mirror showing the sky indoors.
        A surface whose diffuse comes from the cube almost everywhere is using
        it as ambient light, not as a mirror: no mirror there."""
        colours = {}
        for cube in (0.0, 1.0):
            ev = Evaluator(self, mr, params, coordinate)
            ev.cube = cube
            ins = ev.inputs(root)
            for key in ('DiffuseColor', 'EmissiveColor'):
                link = ins.get(key)
                v = np.zeros(3)
                if link and link['expr'] > 0:
                    try:
                        v = ev.value(link, np.zeros(3))
                    except (IndexError, ValueError):
                        return None
                v = v[..., :3] if v.shape[-1] >= 3 else np.repeat(v[..., :1], 3, -1)
                colours[(key, cube)] = np.broadcast_to(v, shape + (3,)) if v.ndim == 1 else resize(v, shape)
        diffuse = colours[('DiffuseColor', 0.0)]
        mirror_sky = colours[('DiffuseColor', 1.0)] - diffuse
        sheen_sky = colours[('EmissiveColor', 1.0)] - colours[('EmissiveColor', 0.0)]
        albedo = np.clip(diffuse + mirror_sky, 0.0, 1.0)
        brightness = np.maximum(albedo.mean(-1), 1e-3)
        mirror = np.clip(np.abs(mirror_sky).mean(-1) / brightness, 0.0, 1.0)
        if mirror.mean() > MIRROR_AMBIENT_SHARE:
            mirror = np.zeros_like(mirror)
        sheen = float(np.clip(np.abs(sheen_sky).mean(-1) / brightness, 0.0, 1.0).mean())
        if mirror.max() < 0.05 and sheen < 0.01:
            return None
        return albedo, mirror, sheen

    def _collect_params(self, mr, idx, params, depth=0):
        """Walk MaterialInstanceConstant parents collecting overrides, nearest
        first; returns the root Material."""
        pkg = mr.pkg
        if pkg.class_of(pkg.exports[idx - 1]) == 'Material':
            return mr, idx
        for (n, _typ, _extra, q, sz, _arr) in expression_chain(mr, idx):
            if n not in ('VectorParameterValues', 'ScalarParameterValues', 'TextureParameterValues'):
                continue
            count = struct.unpack_from('<i', mr.d, q)[0]
            p, end = q + 4, q + sz
            for _ in range(count):
                _ok, tags, p = mr._chain(p, end)
                entry = {t[0]: t for t in tags}
                if 'ParameterName' not in entry or 'ParameterValue' not in entry:
                    continue
                name = mr.nm(struct.unpack_from('<i', mr.d, entry['ParameterName'][3])[0])
                vq = entry['ParameterValue'][3]
                if n == 'VectorParameterValues':
                    value = np.array(struct.unpack_from('<4f', mr.d, vq))
                elif n == 'ScalarParameterValues':
                    value = struct.unpack_from('<f', mr.d, vq)[0]
                else:
                    value = (mr, struct.unpack_from('<i', mr.d, vq)[0])
                params.setdefault(name, value)
        parent = {n: mr._value(t, x, q, s) for (n, t, x, q, s, _a) in expression_chain(mr, idx)}.get('Parent')
        if not isinstance(parent, tuple) or depth > 8:
            return None, None
        pr, pi = self.resolve(mr, parent[1])
        return self._collect_params(pr, pi, params, depth + 1) if pr else (None, None)


class Evaluator:
    """Expression graph of one root Material, evaluated per pixel with numpy.

    Values are arrays whose last axis is the channel count (1-4); a constant
    has no spatial axes and broadcasts. The first texture sample fixes the
    image size; later samples are resampled onto it.
    """

    def __init__(self, baker, mr, params, coordinate=None):
        self.baker = baker
        self.coordinate_filter = coordinate
        self.mr = mr
        self.params = params
        self.shape = None
        self.coords = []
        self.unsupported = collections.Counter()
        # A cube map sample's value, or None to count it unsupported (0.5).
        self.cube = None

    def inputs(self, idx):
        return {n: _link(self.mr, q, sz) for (n, _typ, extra, q, sz, _arr) in expression_chain(self.mr, idx)
                if extra and ('ExpressionInput' in extra or 'MaterialInput' in extra)}

    def reaches_cube(self, idx, depth=0, seen=None):
        """Whether a cube map sample feeds expression `idx`."""
        seen = set() if seen is None else seen
        if idx in seen or depth > 32:
            return False
        seen.add(idx)
        pkg = self.mr.pkg
        cls = pkg.class_of(pkg.exports[idx - 1])
        if 'Cube' in cls:
            return True
        if cls == 'MaterialExpressionTextureSample':
            ref = (self.props(idx).get('Texture') or (None, 0))[1]
            if ref and self.mr.pkg.resolve(ref) and 'Cube' in str(self._class_of_ref(ref)):
                return True
        return any(self.reaches_cube(link['expr'], depth + 1, seen)
                   for link in self.inputs(idx).values() if link and link['expr'] > 0)

    def _is_cube_sample(self, idx, cls, props):
        if 'Cube' in cls:
            return True
        if cls == 'MaterialExpressionTextureSample':
            ref = (props.get('Texture') or (None, 0))[1]
            return bool(ref) and 'Cube' in str(self._class_of_ref(ref))
        return False

    def _class_of_ref(self, ref):
        pkg = self.mr.pkg
        if ref > 0:
            return pkg.class_of(pkg.exports[ref - 1])
        return pkg.imports[-ref - 1].get('class', '')

    def props(self, idx):
        return {name: self.mr._value(typ, extra, q, sz) for (name, typ, extra, q, sz, _arr) in expression_chain(self.mr, idx)}

    def value(self, link, default):
        if not link or link['expr'] <= 0:
            return default
        v = self.node(link['expr'])
        if link['mask'] is not None:
            if max(link['mask']) >= v.shape[-1]:
                # A missing alpha reads as 1; missing colour channels repeat the last.
                pad = [np.ones(v.shape[:-1] + (1,)) if k == 3 else v[..., -1:] for k in range(v.shape[-1], 4)]
                v = np.concatenate([v] + pad, -1)
            v = v[..., link['mask']]
        return v

    def node(self, idx):
        mr = self.mr
        cls = mr.pkg.class_of(mr.pkg.exports[idx - 1])
        props = self.props(idx)
        ins = self.inputs(idx)
        one, zero = np.ones(1), np.zeros(1)
        name = props.get('ParameterName')
        if self.cube is not None and self._is_cube_sample(idx, cls, props):
            return np.full(4, self.cube)
        if cls in ('MaterialExpressionTextureSample', 'MaterialExpressionTextureSampleParameter2D'):
            reader, ref = mr, (props.get('Texture') or (None, 0))[1]
            if isinstance(self.params.get(name), tuple):
                reader, ref = self.params[name]
            link = ins.get('Coordinates')
            self.coords.append((bool(link and link['expr'] > 0), self.coordinate(link)))
            pixels = self.baker.texture(reader, ref)
            if pixels is None:
                return np.full(4, 0.5)
            if self.coordinate_filter is not None and self.coords[-1][1] != self.coordinate_filter:
                return pixels.mean(axis=(0, 1))
            if self.shape is None:
                self.shape = pixels.shape[:2]
            return resize(pixels, self.shape)
        if cls == 'MaterialExpressionConstant':
            return np.array([props.get('R', 0.0)])
        if cls == 'MaterialExpressionConstant2Vector':
            return np.array([props.get('R', 0.0), props.get('G', 0.0)])
        if cls in ('MaterialExpressionConstant3Vector', 'MaterialExpressionConstant4Vector'):
            c = _linear_color(mr, idx, 'Constant')
            c = c if c is not None else np.zeros(4)
            return c[:3] if cls.endswith('3Vector') else c
        if cls == 'MaterialExpressionVectorParameter':
            v = self.params.get(name)
            if isinstance(v, np.ndarray):
                return v
            c = _linear_color(mr, idx, 'DefaultValue')
            return c if c is not None else np.zeros(4)
        if cls == 'MaterialExpressionScalarParameter':
            v = self.params.get(name)
            return np.array([v if isinstance(v, float) else props.get('DefaultValue', 0.0)])
        if cls in ('MaterialExpressionAdd', 'MaterialExpressionSubtract',
                   'MaterialExpressionMultiply', 'MaterialExpressionDivide'):
            neutral = one if cls in ('MaterialExpressionMultiply', 'MaterialExpressionDivide') else zero
            a, b = match(self.value(ins.get('A'), neutral), self.value(ins.get('B'), neutral))
            if cls == 'MaterialExpressionAdd':
                return a + b
            if cls == 'MaterialExpressionSubtract':
                return a - b
            if cls == 'MaterialExpressionMultiply':
                return a * b
            return a / np.where(b == 0, 1, b)
        if cls == 'MaterialExpressionLinearInterpolate':
            a, b = match(self.value(ins.get('A'), zero), self.value(ins.get('B'), one))
            t = self.value(ins.get('Alpha'), np.array([0.5]))[..., :1]
            a, t = match(a, t)
            b, t = match(b, t)
            return a + (b - a) * t
        if cls == 'MaterialExpressionConstantClamp':
            return np.clip(self.value(ins.get('Input'), zero), props.get('Min', 0.0), props.get('Max', 1.0))
        if cls == 'MaterialExpressionClamp':
            v = self.value(ins.get('Input'), zero)
            lo, hi = self.value(ins.get('Min'), zero)[..., :1], self.value(ins.get('Max'), one)[..., :1]
            v, lo = match(v, lo)
            v, hi = match(v, hi)
            return np.clip(v, lo, hi)
        if cls == 'MaterialExpressionOneMinus':
            return 1 - self.value(ins.get('Input'), zero)
        if cls == 'MaterialExpressionComponentMask':
            v = self.value(ins.get('Input'), np.zeros(4))
            keep = [k for k, c in enumerate('RGBA') if props.get(c) and k < v.shape[-1]]
            return v[..., keep] if keep else v
        if cls == 'MaterialExpressionAppendVector':
            a, b = broadcast_space(self.value(ins.get('A'), zero), self.value(ins.get('B'), zero))
            return np.concatenate([a, b], -1)
        if cls == 'MaterialExpressionDesaturation':
            v = self.value(ins.get('Input'), np.zeros(3))
            base = v[..., :3] if v.shape[-1] >= 3 else v
            gray = base.mean(-1, keepdims=True)
            pct = self.value(ins.get('Percent'), one)[..., :1]
            base, gray = match(base, gray)
            base, pct = match(base, pct)
            return base + (gray - base) * pct
        if cls == 'MaterialExpressionPower':
            base = np.clip(self.value(ins.get('Base'), one), 0, None)
            base, exponent = match(base, self.value(ins.get('Exponent'), one)[..., :1])
            return base ** exponent
        if cls in ('MaterialExpressionStaticSwitchParameter', 'MaterialExpressionStaticSwitch'):
            on = props.get('DefaultValue', False)
            return self.value(ins.get('A') if on else ins.get('B'), zero)
        self.unsupported[cls] += 1
        return np.array([0.5])

    def coordinate(self, link):
        """(uv set, u tiling, v tiling) feeding a sample, through static switches."""
        if not link or link['expr'] <= 0:
            return PLAIN_COORDINATE
        idx = link['expr']
        for _ in range(8):
            cls = self.mr.pkg.class_of(self.mr.pkg.exports[idx - 1])
            props = self.props(idx)
            if cls == 'MaterialExpressionTextureCoordinate':
                return (props.get('CoordinateIndex', 0), props.get('UTiling', 1.0), props.get('VTiling', 1.0))
            if not cls.startswith('MaterialExpressionStaticSwitch'):
                return ('computed', 1.0, 1.0)
            nxt = self.inputs(idx).get('A' if props.get('DefaultValue', False) else 'B')
            if not nxt or nxt['expr'] <= 0:
                return PLAIN_COORDINATE
            idx = nxt['expr']
        return ('computed', 1.0, 1.0)


def expression_chain(mr, idx):
    """Tagged properties of a material or expression node, read from the start
    of the object. DO NOT use MapReader.chain_of() here: it keeps the LONGEST
    chain found at any offset, and a Multiply whose A input is a five-field
    ExpressionInput struct then reads as that struct, losing A and B."""
    export = mr.pkg.exports[idx - 1]
    end = export['offset'] + export['size']
    for offset in (4, 0):
        ok, chain, _native = mr._chain(export['offset'] + offset, end)
        if ok and chain:
            return chain
    return mr.chain_of(idx)[0]


def _link(mr, q, sz):
    """An ExpressionInput is itself tagged: Expression plus MaskR/G/B/A flags."""
    _ok, tags, _ = mr._chain(q, q + sz)
    out = {'expr': 0, 'mask': None}
    masks = []
    for (tn, _tt, _tx, tq, _tsz, _ta) in tags:
        v = struct.unpack_from('<i', mr.d, tq)[0]
        if tn == 'Expression':
            out['expr'] = v
        elif tn in ('MaskR', 'MaskG', 'MaskB', 'MaskA') and v:
            masks.append('RGBA'.index(tn[-1]))
    out['mask'] = masks or None
    return out


def _linear_color(mr, idx, name):
    for (n, _typ, extra, q, sz, _arr) in expression_chain(mr, idx):
        if n == name and extra == 'LinearColor' and sz == 16:
            return np.array(struct.unpack_from('<4f', mr.d, q))
    return None


def match(a, b):
    return broadcast_space(*broadcast_channels(a, b))


def broadcast_channels(a, b):
    ca, cb = a.shape[-1], b.shape[-1]
    if ca == cb:
        return a, b
    if ca == 1:
        return np.repeat(a, cb, -1), b
    if cb == 1:
        return a, np.repeat(b, ca, -1)
    n = min(ca, cb)
    return a[..., :n], b[..., :n]


def broadcast_space(a, b):
    if a.ndim == b.ndim:
        if a.ndim == 3 and a.shape[:2] != b.shape[:2]:
            b = resize(b, a.shape[:2])
        return a, b
    if a.ndim == 3:
        return a, np.broadcast_to(b, a.shape[:2] + b.shape[-1:])
    return np.broadcast_to(a, b.shape[:2] + a.shape[-1:]), b


def png_base64(pixels):
    """A float image (h, w, 1 | 3 | 4) in 0..1 as a base64 PNG string.

    PNG, not raw bytes: a bake is mostly flat colour and compresses 5 to 20
    times, which is what keeps materials.json readable by the Godot side once
    the bakes are 256 or 512 px. Stdlib only: IHDR, one filter-0 IDAT, IEND.
    """
    h, w, channels = pixels.shape
    colour_type = {1: 0, 3: 2, 4: 6}[channels]
    rows = (pixels * 255 + 0.5).astype(np.uint8)
    raw = b''.join(b'\x00' + rows[y].tobytes() for y in range(h))

    def chunk(kind, body):
        return struct.pack('>I', len(body)) + kind + body + struct.pack('>I', zlib.crc32(kind + body) & 0xFFFFFFFF)

    png = (b'\x89PNG\r\n\x1a\n'
           + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, colour_type, 0, 0, 0))
           + chunk(b'IDAT', zlib.compress(raw, 9))
           + chunk(b'IEND', b''))
    return base64.b64encode(png).decode('ascii')


def resize(img, shape):
    h, w = shape
    if img.shape[:2] == (h, w):
        return img
    return img[np.arange(h) * img.shape[0] // h][:, np.arange(w) * img.shape[1] // w]


def unchunk(raw):
    tag, _block, _csize, usize = struct.unpack_from('<4I', raw, 0)
    if tag != CHUNK_TAG:
        raise ExtractError('compressed mip without a chunk tag')
    p, blocks, total = 16, [], 0
    while total < usize:
        bc, bu = struct.unpack_from('<2I', raw, p)
        p += 8
        blocks.append((bc, bu))
        total += bu
    out = b''
    for bc, bu in blocks:
        out += LZOCompressor.decompress(raw[p:p + bc], bu)
        p += bc
    return out


def decode_dxt(data, w, h, fmt):
    bw, bh = max(1, (w + 3) // 4), max(1, (h + 3) // 4)
    step = 8 if fmt == 'PF_DXT1' else 16
    blocks = np.frombuffer(data[:bw * bh * step], dtype=np.uint8).reshape(bh * bw, step)
    color = blocks[:, step - 8:]
    c0 = color[:, 0].astype(np.uint16) | (color[:, 1].astype(np.uint16) << 8)
    c1 = color[:, 2].astype(np.uint16) | (color[:, 3].astype(np.uint16) << 8)

    def rgb(c):
        return np.stack([((c >> 11) & 31) * 255 / 31, ((c >> 5) & 63) * 255 / 63, (c & 31) * 255 / 31], -1)
    p0, p1 = rgb(c0), rgb(c1)
    four = (c0 > c1) | (fmt != 'PF_DXT1')
    p2 = np.where(four[:, None], (2 * p0 + p1) / 3, (p0 + p1) / 2)
    p3 = np.where(four[:, None], (p0 + 2 * p1) / 3, 0)
    palette = np.stack([p0, p1, p2, p3], 1)
    bits = color[:, 4:8].astype(np.uint32)
    index = bits[:, 0] | (bits[:, 1] << 8) | (bits[:, 2] << 16) | (bits[:, 3] << 24)
    sel = np.stack([(index >> (2 * k)) & 3 for k in range(16)], 1)
    px = np.take_along_axis(palette, sel[:, :, None].repeat(3, 2), 1)
    if fmt == 'PF_DXT1':
        alpha = np.where((~four[:, None]) & (sel == 3), 0.0, 255.0)
    else:
        a0, a1 = blocks[:, 0].astype(float), blocks[:, 1].astype(float)
        abits = np.zeros(len(blocks), dtype=np.uint64)
        for k in range(6):
            abits |= blocks[:, 2 + k].astype(np.uint64) << np.uint64(8 * k)
        asel = np.stack([(abits >> np.uint64(3 * k)) & np.uint64(7) for k in range(16)], 1).astype(int)
        table = np.zeros((len(blocks), 8))
        table[:, 0], table[:, 1] = a0, a1
        big = a0 > a1
        for k in range(2, 8):
            table[:, k] = np.where(big, ((8 - k) * a0 + (k - 1) * a1) / 7, 0)
        for k in range(2, 6):
            table[:, k] = np.where(big, table[:, k], ((6 - k) * a0 + (k - 1) * a1) / 5)
        table[:, 6] = np.where(big, table[:, 6], 0)
        table[:, 7] = np.where(big, table[:, 7], 255)
        alpha = np.take_along_axis(table, asel, 1)
    rgba = np.concatenate([px, alpha[:, :, None]], -1).reshape(bh, bw, 4, 4, 4).transpose(0, 2, 1, 3, 4)
    return rgba.reshape(bh * 4, bw * 4, 4)[:h, :w] / 255.0
