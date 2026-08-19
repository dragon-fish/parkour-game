import sys, math, collections, struct
sys.stdout.reconfigure(encoding='utf-8')
from mapdump import MapReader

mr = MapReader(sys.argv[1])
pkg = mr.pkg


def ref_index(v):
    return v[1] if (isinstance(v, tuple) and len(v) == 2 and v[0] == 'obj' and v[1] > 0) else None


# how many actors reference each mesh
users = collections.Counter()
for i, e in enumerate(pkg.exports):
    if pkg.class_of(e) != 'StaticMeshActor':
        continue
    pr, _ = mr.props(i + 1)
    if not pr:
        continue
    ci = ref_index(pr.get('StaticMeshComponent'))
    if not ci:
        continue
    cpr, _ = mr.props(ci)
    if not cpr:
        continue
    mi = ref_index(cpr.get('StaticMesh'))
    if mi:
        users[mi] += 1

good, bad = [], []
for i, e in enumerate(pkg.exports):
    if pkg.class_of(e) != 'StaticMesh':
        continue
    b = mr.bounds(i + 1)
    n = users.get(i + 1, 0)
    if not b:
        bad.append((e['name'], n, None)); continue
    ox, oy, oz, ex, ey, ez, r = b
    diag = math.sqrt(ex * ex + ey * ey + ez * ez)
    ok = (diag > 0 and 0.95 < r / diag < 1.05 and min(ex, ey, ez) >= 0
          and all(abs(x) < 1e6 for x in b))
    (good if ok else bad).append((e['name'], n, b))

print("包围盒校验：通过 %d，失败 %d" % (len(good), len(bad)))
lost = sum(n for _, n, _ in bad)
total = sum(n for _, n, _ in good) + lost
print("因校验失败而被丢弃的【摆放实例】: %d / %d (%.1f%%)"
      % (lost, total, 100.0 * lost / max(total, 1)))

bad.sort(key=lambda t: -t[1])
print("\n失败的网格（按被引用次数排序）:")
for name, n, b in bad[:20]:
    if b is None:
        print("  %-34s 引用 %4d 次   <解析失败>" % (name[:34], n))
    else:
        ox, oy, oz, ex, ey, ez, r = b
        diag = math.sqrt(ex * ex + ey * ey + ez * ez)
        print("  %-34s 引用 %4d 次   extent=(%.1f,%.1f,%.1f) r=%.1f diag=%.1f ratio=%.3f"
              % (name[:34], n, ex, ey, ez, r, diag, (r / diag) if diag else -1))
