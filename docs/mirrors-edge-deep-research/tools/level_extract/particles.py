"""Placed particle emitters and the ParticleSystem templates they draw.

An `Emitter` actor is a placement like a mesh: a Location, a Rotation, a
DrawScale and a ParticleSystemComponent whose Template names a ParticleSystem,
almost always in a shared Effects package. A template is a list of emitters;
each emitter is a list of LOD levels, and each LOD level a RequiredModule, a
SpawnModule and a list of modules. Every module value is a distribution
object (constant, uniform, curve), and every one of those objects is cooked as
a DELTA against its archetype -- a subobject of the module's class default in
Engine.u -- so a value the template leaves at its default is not in the
template at all and has to be read off the class.

What this writes is the template as data: per LOD, the module list with each
distribution decoded and every spatial value already in Godot metres and axes.
Deciding what a module LOOKS like is the builder's (tools/me_level/
me_particles.gd); a module it does not know is carried here all the same and
counted there.
"""
import math
import struct

from common import UU, ExtractError, actor_scale, godot_basis, outer_class, point
import materials as material_bake
import packages as pk

EMITTER_CLASSES = ('Emitter',)
# [ME:INFERRED] drawn only with hardware PhysX: the group's name, and what is in
# it -- PX_* templates, PhysX versions of the vents. In the tutorial each of
# them stands where an ordinary VentSmoke emitter outside the group does.
PHYSX_ONLY_GROUP = 'PhysXOnly'
# Samples per curve over a particle's life, both ends included.
CURVE_SAMPLES = 33

# Which module fields are positions, velocities or accelerations in the
# emitter's space (converted by the level's axis map, uu -> m), and which are
# lengths that keep their own axes (a sprite's Size X is its width, not a
# direction in the world). Keyed by module class without the ParticleModule
# prefix. A field in neither stays in the original's units.
SPATIAL_FIELDS = {
    'Velocity': ('StartVelocity',),
    'Acceleration': ('Acceleration',),
    'AccelerationOverLifetime': ('AccelOverLife',),
    'Location': ('StartLocation',),
}
LENGTH_FIELDS = {
    'Size': ('StartSize',),
    'Velocity': ('StartVelocityRadial',),
}
# Arrays of four-byte elements say nothing of their element type; these are
# object references, those are floats. Any other such array is carried as ints.
OBJECT_ARRAYS = ('Emitters', 'LODLevels', 'Modules', 'SpawningModules', 'SpawnModules', 'UpdateModules',
                 'Expressions')
FLOAT_ARRAYS = ('LookupTable', 'LODDistances')
# Editor bookkeeping and the cooked lookup tables, never read by the builder.
SKIPPED_FIELDS = ('ModuleEditorColor', 'EmitterEditorColor', 'CurveEdSetup', 'bIsDirty', 'LookupTable',
                  'LookupTableNumElements', 'LookupTableChunkSize', 'LookupTableTimeScale',
                  'LookupTableStartTime', 'LookupTableNumElements', 'LODValidity', 'PeakActiveParticles',
                  'bCurveEdited', 'bEditable', 'ConvertedModules', 'EditorX', 'EditorY',
                  'bShouldResetPeakCounts', 'ThumbnailDistance', 'ThumbnailWarmup', 'ThumbnailImage',
                  'ThumbnailImageOutOfDate', 'bSpawnModule', 'bUpdateModule', 'LODDuplicate',
                  'IdenticalIgnoreProperties')


class Ref:
    """An object reference together with the package it is an index into."""
    __slots__ = ('reader', 'index')

    def __init__(self, reader, index):
        self.reader, self.index = reader, index

    def __eq__(self, other):
        return isinstance(other, Ref) and other.reader is self.reader and other.index == self.index

    def __hash__(self):
        return hash((id(self.reader), self.index))

    def __repr__(self):
        return 'Ref(%s, %d)' % (getattr(self.reader, 'label', '?'), self.index)


def resolve(packages, reader, index):
    """(reader, export index) of a reference, following an import into the
    shared package that exports it; (None, 0) for None or an unknown package."""
    if index > 0:
        return reader, index
    if index < 0:
        root, path = pk.import_path(reader.pkg, -index - 1)
        shared = packages.shared_reader(root)
        target = pk.find_export(shared, path) if shared else None
        if target:
            return shared, target
    return None, 0


def class_of(ref):
    return ref.reader.pkg.class_of(ref.reader.pkg.exports[ref.index - 1])


# ------------------------------------------------------------ tagged values

def _tags(reader, index):
    """The object's own tag chain, the widest one found: a module's first tag is
    often a RawDistribution struct whose inner chain is longer than the
    module's, and the longest chain is then the struct's."""
    return reader.chain_of(index, widest=True)[0]


def _value(packages, reader, name, typ, extra, q, sz):
    d = reader.d
    if typ == 'FloatProperty':
        return struct.unpack_from('<f', d, q)[0]
    if typ == 'IntProperty':
        return struct.unpack_from('<i', d, q)[0]
    if typ == 'BoolProperty':
        return bool(struct.unpack_from('<i', d, q)[0])
    if typ == 'ObjectProperty' or typ == 'ComponentProperty':
        index = struct.unpack_from('<i', d, q)[0]
        return Ref(reader, index) if index else None
    if typ == 'NameProperty':
        return reader.nm(struct.unpack_from('<i', d, q)[0])
    if typ == 'ByteProperty':
        return reader.nm(struct.unpack_from('<i', d, q)[0]) if sz == 8 else d[q]
    if typ == 'StrProperty':
        n = struct.unpack_from('<i', d, q)[0]
        return d[q + 4:q + 4 + max(n - 1, 0)].decode('latin-1') if n >= 0 else \
            d[q + 4:q + 4 - 2 * n - 2].decode('utf-16-le')
    if typ == 'StructProperty':
        if extra in ('Vector', 'Rotator') and sz == 12:
            return struct.unpack_from('<3f' if extra == 'Vector' else '<3i', d, q)
        if extra == 'Vector2D' and sz == 8:
            return struct.unpack_from('<2f', d, q)
        if extra == 'TwoVectors' and sz == 24:
            values = struct.unpack_from('<6f', d, q)
            return (values[:3], values[3:])
        if extra == 'Color' and sz == 4:
            b, g, r, a = d[q:q + 4]
            return (r / 255.0, g / 255.0, b / 255.0, a / 255.0)
        if extra == 'LinearColor' and sz == 16:
            return struct.unpack_from('<4f', d, q)
        ok, tags, _ = reader._chain(q, q + sz)
        if not ok:
            # A natively serialised struct (Guid, Matrix, Box...): nothing
            # here reads one.
            return ('raw', extra, sz)
        return {t[0]: _value(packages, reader, *t[:5]) for t in tags}
    if typ == 'ArrayProperty':
        count = struct.unpack_from('<i', d, q)[0]
        if count == 0:
            return []
        if count > 0 and sz == 4 + 4 * count:
            if name in FLOAT_ARRAYS:
                return list(struct.unpack_from('<%df' % count, d, q + 4))
            values = struct.unpack_from('<%di' % count, d, q + 4)
            if name in OBJECT_ARRAYS:
                return [Ref(reader, v) if v else None for v in values]
            return list(values)
        out, p, end = [], q + 4, q + sz
        for _ in range(count):
            ok, tags, p = reader._chain(p, end)
            if not ok:
                # Names, strings or native structs: nothing here reads one.
                return ('raw', typ, sz)
            out.append({t[0]: _value(packages, reader, *t[:5]) for t in tags})
        return out
    return ('raw', typ, sz)


def _class_default(packages, reader, index):
    """(reader, index) of the object an export with no archetype of its own is
    a delta against: its class's default object, or for a class default the
    one of the class above. (None, 0) at the top."""
    export = reader.pkg.exports[index - 1]
    name = export['name']
    if name.startswith('Default__'):
        class_reader, class_index = _class_export(packages, reader, name[len('Default__'):])
        if class_reader is None:
            return None, 0
        super_index = class_reader.pkg.exports[class_index - 1]['super_idx']
        if not super_index:
            return None, 0
        super_name = class_reader.pkg.resolve(super_index)
        owner, _ = resolve(packages, class_reader, super_index)
        if owner is None:
            return None, 0
        return owner, pk.find_export(owner, ['Default__' + super_name]) or 0
    class_ref = export['class_idx']
    if class_ref >= 0:
        # A class exported by the package itself: none of the effects are.
        return None, 0
    owner, _ = resolve(packages, reader, class_ref)
    if owner is None:
        return None, 0
    target = pk.find_export(owner, ['Default__' + reader.pkg.resolve(class_ref)])
    return (owner, target) if target else (None, 0)


def _class_export(packages, reader, class_name):
    target = pk.find_export(reader, [class_name])
    if target and reader.pkg.class_of(reader.pkg.exports[target - 1]) == 'Class':
        return reader, target
    return None, 0


def object_props(packages, reader, index, depth=0):
    """An object's properties with its whole archetype chain merged under them,
    each level read in its own package, nearer values winning. An export that
    records no archetype (every module and curve in the effects packages) is a
    delta against its class's default object in Engine.u, so a value the
    template leaves at its default reads as the class's here.

    A static array (MirrorFlags[3]) comes back as {element index: value},
    merged element by element."""
    if depth > 24:
        raise ExtractError('%s: archetype chain too deep at %d' % (reader.label, index))
    merged = {}
    archetype = reader.pkg.exports[index - 1]['archetype']
    parent_reader, parent = resolve(packages, reader, archetype) if archetype \
        else _class_default(packages, reader, index)
    if archetype and parent_reader is None:
        raise ExtractError('%s: archetype of %s not found' % (reader.label, reader.pkg.full_name(index)))
    if parent_reader is not None and parent:
        merged.update(object_props(packages, parent_reader, parent, depth + 1))
    for tag in _tags(reader, index):
        if tag[0] in SKIPPED_FIELDS:
            continue
        value = _value(packages, reader, *tag[:5])
        if tag[5] > 0 or isinstance(merged.get(tag[0]), StaticArray):
            elements = merged.get(tag[0])
            if isinstance(elements, StaticArray):
                elements = StaticArray(elements)
            else:
                # Element 0 reads like any single value until a later one shows
                # the property is an array.
                elements = StaticArray({0: elements} if tag[0] in merged else {})
            elements[tag[5]] = value
            value = elements
        merged[tag[0]] = value
    return merged


class StaticArray(dict):
    """The elements of a static array property a chain wrote, by index."""

    def as_list(self, default=None):
        return [self.get(i, default) for i in range(max(self) + 1)] if self else []


# ------------------------------------------------------------ distributions

# FInterpCurve: CIM_Linear is the enum's first value, so a point that writes no
# InterpMode is linear.
LINEAR_MODES = ('CIM_Linear', None)


def _curve_eval(points, t):
    """FInterpCurve::Eval: clamped to the end points outside them, constant,
    linear or Hermite inside by the LEAVING point's mode, tangents scaled by
    the segment's length. Values are tuples of equal length."""
    if not points:
        return None
    if t <= points[0]['in']:
        return points[0]['out']
    if t >= points[-1]['in']:
        return points[-1]['out']
    for a, b in zip(points, points[1:]):
        if a['in'] <= t < b['in']:
            span = b['in'] - a['in']
            if span <= 0.0:
                return b['out']
            alpha = (t - a['in']) / span
            if a['mode'] == 'CIM_Constant':
                return a['out']
            if a['mode'] in LINEAR_MODES:
                return tuple(x + (y - x) * alpha for x, y in zip(a['out'], b['out']))
            a2, a3 = alpha * alpha, alpha * alpha * alpha
            h00, h10, h01, h11 = 2 * a3 - 3 * a2 + 1, a3 - 2 * a2 + alpha, -2 * a3 + 3 * a2, a3 - a2
            return tuple(h00 * p0 + h10 * m0 * span + h01 * p1 + h11 * m1 * span
                         for p0, m0, p1, m1 in zip(a['out'], a['leave'], b['out'], b['arrive']))
    return points[-1]['out']


def _tuple(v, width):
    if isinstance(v, (int, float)):
        return (float(v),) * width
    if isinstance(v, dict):
        # Vector2D written as a tagged struct.
        return tuple(float(v.get(k, 0.0)) for k in ('X', 'Y', 'Z')[:width])
    if isinstance(v, tuple) and len(v) == 2 and isinstance(v[0], tuple):
        return tuple(v[0]) + tuple(v[1])
    return tuple(float(c) for c in v)


def _points(curve, width):
    out = []
    for p in (curve or {}).get('Points', []):
        out.append({'in': float(p.get('InVal', 0.0)), 'out': _tuple(p.get('OutVal', (0.0,) * width), width),
                    'arrive': _tuple(p.get('ArriveTangent', (0.0,) * width), width),
                    'leave': _tuple(p.get('LeaveTangent', (0.0,) * width), width),
                    'mode': p.get('InterpMode')})
    return out


# Locked axes: which component stands for which, as UE3's
# DistributionVector*.GetValue applies them.
LOCKED = {'EDVLF_XY': (0, 0, 2), 'EDVLF_XZ': (0, 1, 0), 'EDVLF_YZ': (0, 1, 1), 'EDVLF_XYZ': (0, 0, 0)}


def _lock(value, locked):
    if locked not in LOCKED or value is None:
        return value
    return tuple(value[i] for i in LOCKED[locked])


def distribution(packages, ref):
    """A distribution object as {'kind', ...}: constant, uniform, curve (with
    samples over [0, 1]) or uniform_curve (min and max samples). Vector values
    are three numbers in the ORIGINAL's units and axes; convert() maps them."""
    if ref is None or ref.index == 0:
        return None
    reader, index = resolve(packages, ref.reader, ref.index)
    if reader is None:
        raise ExtractError('%s: distribution not found' % ref.reader.label)
    ref = Ref(reader, index)
    cls = class_of(ref)
    props = object_props(packages, reader, index)
    vector = cls.startswith('DistributionVector')
    width = 3 if vector else 1
    # [ME:INFERRED UE3 DistributionVector*::GetValue] the lock applies whatever
    # bLockAxes says: it is LockedAxes that GetValue switches on.
    locked = props.get('LockedAxes') if vector and props.get('LockedAxes') not in (None, 'EDVLF_None') else None

    def one(v):
        return _lock(_tuple(v, width), locked)

    out = {'class': cls}
    if locked:
        out['locked'] = locked
    if cls.endswith('Constant'):
        out.update(kind='constant', value=list(one(props.get('Constant', (0.0,) * width))))
    elif cls.endswith('Uniform'):
        low, high = list(_tuple(props.get('Min', (0.0,) * width), width)), list(_tuple(props.get('Max', (0.0,) * width), width))
        if vector:
            # Mirroring replaces a component's Min before the lock is applied:
            # Same takes the Max, Mirror its negative.
            flags = props.get('MirrorFlags')
            flags = flags.as_list('EDVMF_Different') if isinstance(flags, StaticArray) else [flags] * 3
            for k, flag in enumerate(flags[:3]):
                if flag == 'EDVMF_Same':
                    low[k] = high[k]
                elif flag == 'EDVMF_Mirror':
                    low[k] = -high[k]
            if props.get('bUseExtremes'):
                out['use_extremes'] = True
        out.update(kind='uniform', min=list(_lock(tuple(low), locked)), max=list(_lock(tuple(high), locked)))
    elif cls.endswith('ConstantCurve'):
        points = _points(props.get('ConstantCurve'), width)
        out.update(kind='curve', points=[{'in': p['in'], 'out': list(one(p['out'])), 'mode': p['mode']}
                                         for p in points],
                   samples=[list(one(_curve_eval(points, i / (CURVE_SAMPLES - 1)))) for i in range(CURVE_SAMPLES)]
                   if points else [list(one((0.0,) * width))] * CURVE_SAMPLES)
    elif cls.endswith('UniformCurve'):
        points = _points(props.get('ConstantCurve'), 2 * width)
        samples = [_curve_eval(points, i / (CURVE_SAMPLES - 1)) for i in range(CURVE_SAMPLES)] if points else []
        out.update(kind='uniform_curve',
                   min=[list(one(s[:width])) for s in samples], max=[list(one(s[width:])) for s in samples])
    else:
        out.update(kind='unsupported', props=sorted(props))
    return out


def _distribution_field(packages, value):
    """A RawDistribution struct's distribution, or None for anything else."""
    if isinstance(value, dict) and isinstance(value.get('Distribution'), Ref):
        return distribution(packages, value['Distribution'])
    return None


# ------------------------------------------------------------ units

def _godot_vector(v, length_only=False):
    if length_only:
        return [c / UU for c in v]
    return list(point(v))


def convert(module_class, field, dist):
    """A distribution's values in Godot metres (and axes, when the field is a
    direction in the emitter's space)."""
    spatial = field in SPATIAL_FIELDS.get(module_class, ())
    length = field in LENGTH_FIELDS.get(module_class, ())
    if dist is None or not (spatial or length):
        return dist
    vector = dist['class'].startswith('DistributionVector')

    def conv(v):
        if not vector:
            return [c / UU for c in v]
        return _godot_vector(v, length_only=not spatial)

    out = dict(dist)
    for key in ('value', 'min', 'max'):
        if key in out and out[key] and isinstance(out[key][0], list):
            out[key] = [conv(v) for v in out[key]]
        elif key in out:
            out[key] = conv(out[key])
    if 'samples' in out:
        out['samples'] = [conv(v) for v in out['samples']]
    if 'points' in out:
        out['points'] = [dict(p, out=conv(p['out'])) for p in out['points']]
    return out


# ------------------------------------------------------------ modules

def module(packages, ref):
    """{'class': short class name, 'enabled', 'props': {...}} of one module,
    every distribution decoded and converted, other values as they are."""
    reader, index = resolve(packages, ref.reader, ref.index)
    ref = Ref(reader, index)
    cls = class_of(ref)
    short = cls[len('ParticleModule'):] if cls.startswith('ParticleModule') else cls
    props = object_props(packages, reader, index)
    out = {}
    for key, value in props.items():
        dist = _distribution_field(packages, value)
        if dist is not None:
            out[key] = convert(short, key, dist)
        elif isinstance(value, Ref):
            out[key] = _reference_name(value)
        elif isinstance(value, list):
            out[key] = [_plain(v) for v in value]
        else:
            out[key] = _plain(value)
    return {'class': short, 'enabled': bool(props.get('bEnabled', True)), 'props': out}


def _reference_name(ref):
    if ref is None or ref.index == 0:
        return None
    if ref.index > 0:
        return ref.reader.pkg.exports[ref.index - 1]['name']
    return ref.reader.pkg.imports[-ref.index - 1]['name']


def _plain(value):
    if isinstance(value, Ref):
        return _reference_name(value)
    if isinstance(value, StaticArray):
        return [_plain(v) for v in value.as_list()]
    if isinstance(value, dict):
        return {k: _plain(v) for k, v in value.items() if k not in SKIPPED_FIELDS}
    if isinstance(value, (list, tuple)):
        return [_plain(v) for v in value]
    if isinstance(value, float):
        return value if math.isfinite(value) else 0.0
    return value


# ------------------------------------------------------------ materials

def particle_material(packages, ref):
    """How a sprite material draws, read off its expression graph: blend mode,
    lighting, and for EmissiveColor and Opacity the product of factors each is
    -- a texture channel, the particle's colour or alpha, a constant -- under
    a DepthBiasedAlpha (soft edge against the scene) and a clamp. A graph with
    any other node is `supported: false`, and the builder leaves the LOD out.

    Also returns the textures it samples, as names, for textures()."""
    if ref is None or ref.index == 0:
        return None, []
    reader, index = resolve(packages, ref.reader, ref.index)
    if reader is None:
        return {'name': _reference_name(ref), 'supported': False}, []
    # A MaterialInstance draws its parent's graph with its own parameters;
    # none of the particle materials here is one, and parameters are not read.
    root_reader, root = reader, index
    for _ in range(16):
        cls = root_reader.pkg.class_of(root_reader.pkg.exports[root - 1])
        if cls == 'Material':
            break
        parent = object_props(packages, root_reader, root).get('Parent')
        if not isinstance(parent, Ref):
            return {'name': root_reader.pkg.exports[index - 1]['name'], 'supported': False}, []
        root_reader, root = resolve(packages, parent.reader, parent.index)
    props = object_props(packages, root_reader, root)
    name = reader.pkg.exports[index - 1]['name']
    out = {'name': name, 'blend': str(props.get('BlendMode', 'BLEND_Opaque')).replace('BLEND_', '').lower(),
           'unlit': props.get('LightingModel') == 'MLM_Unlit', 'two_sided': bool(props.get('TwoSided', False)),
           'supported': True}
    textures = []
    for slot, key in (('EmissiveColor', 'emissive'), ('Opacity', 'opacity')):
        link = props.get(slot)
        expr = link.get('Expression') if isinstance(link, dict) else None
        if not isinstance(expr, Ref):
            continue
        term = _term(packages, root_reader, expr.index, _mask(link), textures)
        if term is None:
            out['supported'] = False
        else:
            out[key] = term
    return out, textures


def _mask(link):
    channels = ''.join(c for c in 'RGBA' if link.get('Mask' + c))
    return channels or None


def _term(packages, reader, index, mask, textures, depth=0):
    """{'factors': [...], 'depth_fade'?, 'clamp'?} for the expression, or None."""
    if depth > 12 or index <= 0:
        return None
    cls = reader.pkg.class_of(reader.pkg.exports[index - 1])[len('MaterialExpression'):]
    props = object_props(packages, reader, index)

    def inner(key, wanted=None):
        link = props.get(key)
        expr = link.get('Expression') if isinstance(link, dict) else None
        if not isinstance(expr, Ref):
            return None
        return _term(packages, reader, expr.index, _mask(link) or wanted, textures, depth + 1)

    if cls == 'Multiply':
        a, b = inner('A', mask), inner('B', mask)
        if a is None or b is None or a.keys() - {'factors'} or b.keys() - {'factors'}:
            return None
        return {'factors': a['factors'] + b['factors']}
    if cls == 'VertexColor':
        return {'factors': [{'kind': 'particle_color', 'channels': mask or 'RGBA'}]}
    if cls in ('ParticleSubUV', 'TextureSample'):
        texture = props.get('Texture')
        texture_name = _reference_name(texture)
        if texture_name is None:
            return None
        textures.append(texture)
        return {'factors': [{'kind': 'texture', 'texture': texture_name, 'channels': mask or 'RGBA',
                             'sub_uv': cls == 'ParticleSubUV'}]}
    if cls == 'Constant':
        return {'factors': [{'kind': 'constant', 'value': float(props.get('R', 0.0))}]}
    if cls == 'DepthBiasedAlpha':
        alpha = inner('Alpha')
        bias = inner('Bias')
        if alpha is None or alpha.keys() - {'factors'}:
            return None
        bias_value = 0.0
        if bias is not None:
            if len(bias['factors']) != 1 or bias['factors'][0]['kind'] != 'constant':
                return None
            bias_value = bias['factors'][0]['value']
        return dict(alpha, depth_fade={'bias': bias_value, 'bias_scale': float(props.get('BiasScale', 1.0))})
    if cls == 'ConstantClamp':
        term = inner('Input', mask)
        if term is None or 'clamp' in term:
            return None
        return dict(term, clamp=[float(props.get('Min', 0.0)), float(props.get('Max', 1.0))])
    return None


def texture_bakes(baker, refs):
    """{texture name: {'width', 'height', 'png', 'srgb'}} of the textures a
    particle material samples, at the extraction's texture size, every channel
    kept: a smoke sheet's brightness and its opacity are two channels of one
    image."""
    out = {}
    for ref in refs:
        name = _reference_name(ref)
        if name in out:
            continue
        pixels = baker.texture(ref.reader, ref.index)
        if pixels is None:
            continue
        tr, ti = baker.resolve(ref.reader, ref.index)
        srgb = (tr.props(ti)[0] or {}).get('SRGB', True) is not False
        out[name] = {'width': int(pixels.shape[1]), 'height': int(pixels.shape[0]),
                     'png': material_bake.png_base64(pixels.clip(0.0, 1.0)), 'srgb': srgb}
    return out


# ------------------------------------------------------------ templates

class Templates:
    """Every ParticleSystem a level's emitters name, decoded once."""

    def __init__(self, packages, baker):
        self.packages = packages
        self.baker = baker
        self.systems = {}
        self.textures = {}
        self._paths = {}

    def textures_of(self, names):
        """The textures the named systems' materials sample, by name."""
        wanted = set()
        for name in names:
            for emitter in self.systems[name]['emitters']:
                for lod in emitter['lods']:
                    material = lod.get('material') or {}
                    for term in (material.get('emissive'), material.get('opacity')):
                        for factor in (term or {}).get('factors', []):
                            if factor['kind'] == 'texture':
                                wanted.add(factor['texture'])
        return {n: t for n, t in self.textures.items() if n in wanted}

    def get(self, ref):
        """The template's name in `systems`, decoding it the first time."""
        reader, index = resolve(self.packages, ref.reader, ref.index)
        if reader is None:
            raise ExtractError('%s: particle system %s not found' % (ref.reader.label, _reference_name(ref)))
        path = '%s.%s' % (reader.label, reader.pkg.full_name(index))
        if path in self._paths:
            return self._paths[path]
        # A map package cooks in a copy of every template it places (a forced
        # export, Edge_Pt2_Art.FX_LevelEffects.Effects.PS_...), so one template
        # arrives from several packages. Copies that decode the same are one
        # template; one that differs keeps its path as a suffix, as a mesh
        # variant does.
        system = self._system(reader, index)
        name = reader.pkg.exports[index - 1]['name']
        while name in self.systems and self.systems[name] != system:
            name = '%s@%s' % (reader.pkg.exports[index - 1]['name'], path.rsplit('.', 1)[0])
            if name in self.systems and self.systems[name] != system:
                raise ExtractError('two different particle systems at %s' % path)
        self.systems[name] = system
        self._paths[path] = name
        return name

    def _system(self, reader, index):
        props = object_props(self.packages, reader, index)
        distances = [d / UU for d in props.get('LODDistances') or [0.0]]
        emitters = []
        for ref in props.get('Emitters') or []:
            if ref is None:
                continue
            emitters.append(self._emitter(ref))
        return {'warmup': float(props.get('WarmupTime', 0.0)),
                'lod_distances_m': [round(d, 3) for d in distances],
                'lod_method': props.get('LODMethod'),
                'emitters': emitters}

    def _emitter(self, ref):
        reader, index = resolve(self.packages, ref.reader, ref.index)
        props = object_props(self.packages, reader, index)
        cls = reader.pkg.class_of(reader.pkg.exports[index - 1])
        lods = []
        for lod_ref in props.get('LODLevels') or []:
            if lod_ref is None:
                continue
            lods.append(self._lod(lod_ref))
        lods.sort(key=lambda lod: lod['level'])
        return {'name': props.get('EmitterName'), 'class': cls, 'lods': lods}

    def _lod(self, ref):
        reader, index = resolve(self.packages, ref.reader, ref.index)
        props = object_props(self.packages, reader, index)
        out = {'level': int(props.get('Level', 0)), 'enabled': bool(props.get('bEnabled', True))}
        for key, field in (('RequiredModule', 'required'), ('SpawnModule', 'spawn'), ('TypeDataModule', 'type_data')):
            value = props.get(key)
            if isinstance(value, Ref):
                out[field] = module(self.packages, value)
        out['modules'] = [module(self.packages, m) for m in props.get('Modules') or [] if m is not None]
        # module() names the material; the reference itself is wanted here.
        required = props.get('RequiredModule')
        material_ref = object_props(self.packages, *resolve(self.packages, required.reader, required.index)) \
            .get('Material') if isinstance(required, Ref) else None
        material = None
        if isinstance(material_ref, Ref):
            material, refs = particle_material(self.packages, material_ref)
            self.textures.update(texture_bakes(self.baker, [r for r in refs if _reference_name(r) not in self.textures]))
        out['material'] = material
        return out


# ------------------------------------------------------------ placements

def collect_emitters(packages, mr, templates, report):
    """Every Emitter actor placed in this package's level, in Godot space.

    Left out: the PhysXOnly group (see PHYSX_ONLY_GROUP) and an emitter with no
    template. Counted in the report either way."""
    pkg = mr.pkg
    counts = report['counts']
    out = []
    for i, e in enumerate(pkg.exports, 1):
        if pkg.class_of(e) not in EMITTER_CLASSES or outer_class(pkg, e) != 'Level':
            continue
        actor = object_props(packages, mr, i)
        if 'Location' not in actor:
            continue
        group = actor.get('Group')
        if group == PHYSX_ONLY_GROUP:
            counts['emitters_physx_only'] = counts.get('emitters_physx_only', 0) + 1
            continue
        component_ref = actor.get('ParticleSystemComponent')
        if not isinstance(component_ref, Ref):
            counts['emitters_without_component'] = counts.get('emitters_without_component', 0) + 1
            continue
        component = object_props(packages, *resolve(packages, component_ref.reader, component_ref.index))
        template = component.get('Template')
        if not isinstance(template, Ref):
            counts['emitters_without_template'] = counts.get('emitters_without_template', 0) + 1
            continue
        system = templates.get(template)
        # What it rides, as a placement says it; a Base never crosses a package.
        base = actor.get('Base')
        base_idx = base.index if isinstance(base, Ref) and base.reader is mr and base.index > 0 else None
        out.append({
            'name': e['name'], 'package': mr.label, 'template': system,
            'position': point(actor['Location']),
            'basis': godot_basis(actor.get('Rotation') or (0, 0, 0), actor_scale(actor)),
            'auto_activate': bool(component.get('bAutoActivate', True)),
            'hidden': bool(actor.get('bHidden', False) or component.get('HiddenGame', False)),
            'group': group,
            'base': '%s.%s' % (mr.label, pkg.exports[base_idx - 1]['name']) if base_idx else None,
        })
    counts['emitters'] = counts.get('emitters', 0) + len(out)
    return out
