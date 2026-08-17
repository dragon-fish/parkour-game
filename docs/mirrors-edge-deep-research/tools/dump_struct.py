"""Recursively dump a tagged UE3 property tree (structs + arrays) from a CDO."""
import sys, struct, os
sys.stdout.reconfigure(encoding='utf-8')
from ue3parse import Package

pkg = Package(sys.argv[1])
obj = sys.argv[2]
only = sys.argv[3] if len(sys.argv) > 3 else None

d = pkg.d
def nm(i):
    return pkg.name(i) if 0 <= i < pkg.name_count else '<%d>' % i


def parse_tags(pos, end, depth, label=None):
    ind = '  ' * depth
    while pos < end:
        nidx, nnum = struct.unpack_from('<2i', d, pos)
        name = nm(nidx)
        if name == 'None':
            return pos + 8
        tidx, _ = struct.unpack_from('<2i', d, pos + 8)
        typ = nm(tidx)
        sz, arr = struct.unpack_from('<2i', d, pos + 16)
        q = pos + 24
        extra = ''
        if typ == 'StructProperty':
            extra = nm(struct.unpack_from('<i', d, q)[0]); q += 8
        if typ == 'BoolProperty':
            v = struct.unpack_from('<i', d, q)[0]
            emit(ind, name, arr, 'bool', bool(v)); pos = q + 4; continue
        show = (only is None) or (label is not None) or (only in name)
        if typ == 'FloatProperty' and sz == 4:
            if show: emit(ind, name, arr, 'float', struct.unpack_from('<f', d, q)[0])
        elif typ == 'IntProperty' and sz == 4:
            if show: emit(ind, name, arr, 'int', struct.unpack_from('<i', d, q)[0])
        elif typ == 'ByteProperty' and sz == 8:
            if show: emit(ind, name, arr, 'enum', nm(struct.unpack_from('<i', d, q)[0]))
        elif typ == 'ByteProperty' and sz == 1:
            if show: emit(ind, name, arr, 'byte', d[q])
        elif typ == 'NameProperty' and sz == 8:
            if show: emit(ind, name, arr, 'name', nm(struct.unpack_from('<i', d, q)[0]))
        elif typ == 'ObjectProperty' and sz == 4:
            if show: emit(ind, name, arr, 'obj', pkg.resolve(struct.unpack_from('<i', d, q)[0]))
        elif typ == 'StructProperty':
            if show:
                print("%s%s : %s {" % (ind, name + (('[%d]' % arr) if arr else ''), extra))
                parse_tags(q, q + sz, depth + 1, label=extra)
                print("%s}" % ind)
        elif typ == 'ArrayProperty':
            cnt = struct.unpack_from('<i', d, q)[0]
            if show:
                print("%s%s : array[%d] {" % (ind, name, cnt))
                body, bend = q + 4, q + sz
                if cnt and (sz - 4) == cnt * 4:
                    vals = struct.unpack_from('<%df' % cnt, d, body)
                    print("  %s%s" % (ind, ', '.join('%g' % v for v in vals)))
                else:
                    p2 = body
                    for k in range(cnt):
                        if p2 >= bend: break
                        print("  %s[%d] {" % (ind, k))
                        p2 = parse_tags(p2, bend, depth + 2, label='elem')
                        print("  %s}" % ind)
                print("%s}" % ind)
        pos = q + sz
    return pos


def emit(ind, name, arr, kind, val):
    print("%s%-42s %s" % (ind, name + (('[%d]' % arr) if arr else ''), val))


e = pkg.exports[int(obj[1:]) - 1] if obj.startswith('#') \
    else next(x for x in pkg.exports if x['name'] == obj)
parse_tags(e['offset'] + 4, e['offset'] + e['size'], 0)
