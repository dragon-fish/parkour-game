"""Dump UE3 tagged defaultproperties from Default__* export objects."""
import sys, struct
sys.stdout.reconfigure(encoding='utf-8')
from ue3parse import Package, Reader

pkg = Package(sys.argv[1])
patterns = [p.lower() for p in sys.argv[2:]]

BOOL_BYTES = int(__import__('os').environ.get('BOOL_BYTES', '4'))


def read_tags(data, start, depth=0):
    """Parse a tagged property list; return (list_of_props, end_pos) or (None, None)."""
    r = Reader(data, start)
    out = []
    for _ in range(4000):
        try:
            nidx = r.i32(); nnum = r.i32()
        except struct.error:
            return None, None
        name = pkg.name(nidx)
        if name == 'None':
            return out, r.p
        tidx = r.i32(); tnum = r.i32()
        typ = pkg.name(tidx)
        if not typ.endswith('Property') or nnum != 0:
            return None, None
        size = r.i32(); arr = r.i32()
        extra = None
        if typ == 'StructProperty':
            si = r.i32(); r.i32(); extra = pkg.name(si)
        elif typ == 'BoolProperty':
            val = r.u8() if BOOL_BYTES == 1 else r.i32()
            out.append((name, arr, typ, bool(val), None))
            continue
        vpos = r.p
        if size < 0 or vpos + size > len(data):
            return None, None
        val = None
        if typ == 'FloatProperty' and size == 4:
            val = struct.unpack_from('<f', data, vpos)[0]
        elif typ == 'IntProperty' and size == 4:
            val = struct.unpack_from('<i', data, vpos)[0]
        elif typ == 'ByteProperty' and size == 1:
            val = data[vpos]
        elif typ == 'ByteProperty' and size == 8:
            val = pkg.name(struct.unpack_from('<i', data, vpos)[0])
        elif typ == 'ObjectProperty' and size == 4:
            val = pkg.resolve(struct.unpack_from('<i', data, vpos)[0])
        elif typ == 'NameProperty' and size == 8:
            val = pkg.name(struct.unpack_from('<i', data, vpos)[0])
        elif typ == 'StructProperty' and extra in ('Vector', 'Rotator') and size == 12:
            val = struct.unpack_from('<3f', data, vpos) if extra == 'Vector' \
                else struct.unpack_from('<3i', data, vpos)
        elif typ == 'StructProperty' and extra == 'Vector2D' and size == 8:
            val = struct.unpack_from('<2f', data, vpos)
        out.append((name, arr, typ if extra is None else '%s<%s>' % (typ, extra), val, size))
        r.p = vpos + size
    return None, None


targets = []
for i, e in enumerate(pkg.exports):
    if e['name'].startswith('Default__'):
        cls = e['name'][len('Default__'):]
        if not patterns or any(p in cls.lower() for p in patterns):
            targets.append((i + 1, e, cls))

print("# Default__ objects matched: %d\n" % len(targets))
for idx, e, cls in targets:
    data = pkg.d
    props, end = None, None
    for skip in (4, 0, 8, 12):          # NetIndex / RF_HasStack variations
        props, end = read_tags(data, e['offset'] + skip)
        if props is not None:
            break
    print("## %s   (export #%d, %d bytes, skip=%s)" % (cls, idx, e['size'], skip))
    if props is None:
        print("   <unparsed>")
    else:
        for name, arr, typ, val, size in props:
            suffix = '[%d]' % arr if arr else ''
            shown = val if val is not None else '<%s, %s bytes>' % (typ, size)
            print("   %-46s %s" % (name + suffix, shown))
    print()
