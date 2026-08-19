"""Find the correct tagged-property start offset for a class of exports."""
import sys, struct, collections
sys.stdout.reconfigure(encoding='utf-8')
from ue3parse import Package

pkg = Package(sys.argv[1])
target = sys.argv[2]
d = pkg.d

def nm(i):
    return pkg.name(i) if 0 <= i < pkg.name_count else None

def try_parse(start, end):
    """Return (ok, ntags, endpos, names) for a tag chain beginning at `start`."""
    p, names = start, []
    for _ in range(200):
        if p + 8 > end:
            return (False, len(names), p, names)
        nidx, nnum = struct.unpack_from('<2i', d, p)
        name = nm(nidx)
        if name is None or nnum != 0:
            return (False, len(names), p, names)
        if name == 'None':
            return (True, len(names), p + 8, names)
        if p + 24 > end:
            return (False, len(names), p, names)
        tidx, tnum = struct.unpack_from('<2i', d, p + 8)
        typ = nm(tidx)
        if typ is None or not typ.endswith('Property'):
            return (False, len(names), p, names)
        sz, arr = struct.unpack_from('<2i', d, p + 16)
        if sz < 0 or sz > 1 << 20 or arr < 0 or arr > 4096:
            return (False, len(names), p, names)
        q = p + 24
        if typ == 'StructProperty':
            q += 8
        if typ == 'BoolProperty':
            p = q + 4
        else:
            p = q + sz
        names.append((name, typ, sz))
    return (False, len(names), p, names)

votes = collections.Counter()
examples = {}
count = 0
for i, e in enumerate(pkg.exports):
    if pkg.class_of(e) != target:
        continue
    count += 1
    base, end = e['offset'], e['offset'] + e['size']
    best = None
    for off in range(0, min(80, e['size']), 4):
        ok, n, endpos, names = try_parse(base + off, end)
        if ok and (best is None or n > best[1]):
            best = (off, n, endpos, names)
    if best:
        votes[best[0]] += 1
        if best[0] not in examples and best[1] > 0:
            examples[best[0]] = (e['name'], e['size'], best)
    else:
        votes[-1] += 1
    if count >= 400:
        break

print("类型 %s：检查 %d 个导出" % (target, count))
print("\n最佳起始偏移分布（-1 = 完全解析失败）:")
for off, n in votes.most_common(10):
    print("  offset=%-4d  %d 个" % (off, n))
print("\n各偏移下的样例:")
for off in sorted(examples):
    nme, size, (o, n, endpos, names) = examples[off]
    print("\n  offset=%d  %s (size=%d, %d 个属性, 结束于 +%d)"
          % (off, nme, size, n, endpos - (endpos - o) + 0))
    for (pn, pt, ps) in names[:12]:
        print("      %-28s %-20s size=%d" % (pn, pt, ps))
