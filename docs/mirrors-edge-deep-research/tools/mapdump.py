"""Self-calibrating UE3 export property reader + level placement extractor."""
import sys, struct
from ue3parse import Package


class MapReader:
    def __init__(self, path):
        self.pkg = Package(path)
        self.d = self.pkg.d

    def nm(self, i):
        return self.pkg.name(i) if 0 <= i < self.pkg.name_count else None

    def _chain(self, start, end):
        """Parse a tag chain. Returns (ok, props, native_start)."""
        d, p, props = self.d, start, []
        for _ in range(200):
            if p + 8 > end:
                return (False, props, p)
            nidx, nnum = struct.unpack_from('<2i', d, p)
            name = self.nm(nidx)
            if name is None or nnum != 0:
                return (False, props, p)
            if name == 'None':
                return (True, props, p + 8)
            if p + 24 > end:
                return (False, props, p)
            tidx, _ = struct.unpack_from('<2i', d, p + 8)
            typ = self.nm(tidx)
            if typ is None or not typ.endswith('Property'):
                return (False, props, p)
            sz, arr = struct.unpack_from('<2i', d, p + 16)
            if sz < 0 or sz > (1 << 20) or arr < 0 or arr > 4096:
                return (False, props, p)
            q = p + 24
            extra = None
            if typ == 'StructProperty':
                extra = self.nm(struct.unpack_from('<i', d, q)[0]); q += 8
            if typ == 'BoolProperty':
                props.append((name, typ, extra, q, 4, arr)); p = q + 4
            else:
                props.append((name, typ, extra, q, sz, arr)); p = q + sz
        return (False, props, p)

    def chain_of(self, idx):
        """Calibrated raw tag chain of export #idx (1-based):
        [(name, type, struct_name, value_offset, size, array_index), ...].
        The offsets let a caller decode payloads props() leaves as 'raw'
        (arrays, nested structs) without re-deriving the calibration."""
        e = self.pkg.exports[idx - 1]
        base, end = e['offset'], e['offset'] + e['size']
        best = None
        for off in range(0, min(96, e['size']), 4):
            ok, pr, nat = self._chain(base + off, end)
            if ok and (best is None or len(pr) > len(best[0])):
                best = (pr, nat)
        return best or ([], None)

    def props(self, idx):
        """Self-calibrating property read of export #idx (1-based).
        Returns (dict, native_start) or (None, None)."""
        pr, nat = self.chain_of(idx)
        best = (pr, nat) if pr or nat is not None else None
        if best is None:
            return (None, None)
        out = {}
        for (name, typ, extra, q, sz, arr) in best[0]:
            out[name] = self._value(typ, extra, q, sz)
        return (out, best[1])

    def _value(self, typ, extra, q, sz):
        d = self.d
        if typ == 'FloatProperty' and sz == 4:
            return struct.unpack_from('<f', d, q)[0]
        if typ == 'IntProperty' and sz == 4:
            return struct.unpack_from('<i', d, q)[0]
        if typ == 'BoolProperty':
            return bool(struct.unpack_from('<i', d, q)[0])
        if typ == 'ObjectProperty' and sz == 4:
            return ('obj', struct.unpack_from('<i', d, q)[0])
        if typ == 'NameProperty' and sz == 8:
            return self.nm(struct.unpack_from('<i', d, q)[0])
        if typ == 'ByteProperty' and sz == 8:
            return self.nm(struct.unpack_from('<i', d, q)[0])
        if typ == 'StructProperty' and extra == 'Vector' and sz == 12:
            return struct.unpack_from('<3f', d, q)
        if typ == 'StructProperty' and extra == 'Rotator' and sz == 12:
            return struct.unpack_from('<3i', d, q)
        return ('raw', typ, extra, sz)

    def props_inherited(self, idx, depth=8):
        """Properties with UE3 archetype inheritance resolved.

        Cooked packages serialize an object as a DELTA against its archetype:
        only values that differ are written. A level's StaticMeshComponent
        therefore often carries nothing but a lightmap reference, while the
        StaticMesh it draws lives on the archetype it was instanced from.
        Reading only the instance loses the mesh -- and with it every rooftop
        the player stands on.

        Walk archetype -> ... -> instance and overlay, so nearer values win.
        """
        chain, cur = [], idx
        for _ in range(depth):
            if cur <= 0 or cur > len(self.pkg.exports):
                break
            chain.append(cur)
            cur = self.pkg.exports[cur - 1]['archetype']
        merged, native = {}, None
        for i in reversed(chain):            # archetype first, instance last
            pr, nat = self.props(i)
            if pr:
                merged.update(pr)
            if i == idx:
                native = nat
        return (merged or None), native

    def bounds(self, idx):
        """FBoxSphereBounds right after a StaticMesh's tagged properties."""
        pr, nat = self.props(idx)
        if nat is None:
            return None
        d = self.d
        e = self.pkg.exports[idx - 1]
        if nat + 28 > e['offset'] + e['size']:
            return None
        ox, oy, oz, ex, ey, ez, r = struct.unpack_from('<7f', d, nat)
        return (ox, oy, oz, ex, ey, ez, r)
