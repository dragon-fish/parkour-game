import sys, struct
sys.stdout.reconfigure(encoding='utf-8')
from mapdump import MapReader

mr = MapReader(sys.argv[1])
pkg = mr.pkg
d = mr.d
want = sys.argv[2:] or ['S_C_02_02_F']


def entries(idx):
    """All calibrated tag entries with their value offsets."""
    e = pkg.exports[idx - 1]
    base, end = e['offset'], e['offset'] + e['size']
    best, best_off = None, None
    for off in range(0, min(96, e['size']), 4):
        ok, pr, nat = mr._chain(base + off, end)
        if ok and (best is None or len(pr) > len(best)):
            best, best_off = pr, off
    return best or [], best_off, e


for w in want:
    hit = None
    for i, e in enumerate(pkg.exports):
        if pkg.class_of(e) == 'RB_BodySetup' and str(pkg.resolve(e['outer_idx'])) == w:
            hit = i + 1
            break
    if hit is None:
        print("找不到 %s 的 RB_BodySetup" % w)
        continue
    props, off, e = entries(hit)
    print("\n=== %s 的 RB_BodySetup  #%d  size=%d  起始偏移=+%s ==="
          % (w, hit, e['size'], off))
    for (name, typ, extra, q, sz, arr) in props:
        head = ''
        if typ == 'ArrayProperty' and sz >= 4:
            cnt = struct.unpack_from('<i', d, q)[0]
            per = (sz - 4) / cnt if cnt else 0
            head = 'count=%d  每元素 %.1f 字节' % (cnt, per)
            if abs(per - 12) < 0.01 and cnt:
                v = struct.unpack_from('<3f', d, q + 4)
                head += '  首元素=(%.2f, %.2f, %.2f)' % v
            elif abs(per - 4) < 0.01 and cnt:
                head += '  首元素=%d' % struct.unpack_from('<i', d, q + 4)[0]
        elif typ == 'StructProperty':
            head = '<%s>' % extra
        print("  %-26s %-16s size=%-7d %s" % (name, typ, sz, head))
