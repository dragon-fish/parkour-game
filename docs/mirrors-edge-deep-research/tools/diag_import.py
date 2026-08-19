import sys, collections
sys.stdout.reconfigure(encoding='utf-8')
from mapdump import MapReader

mr = MapReader(sys.argv[1])
pkg = mr.pkg


def raw(v):
    return v[1] if (isinstance(v, tuple) and len(v) == 2 and v[0] == 'obj') else None


def outer_chain(imp_idx):
    """Full dotted path of an import (negative index convention)."""
    parts = []
    cur = imp_idx
    for _ in range(8):
        if cur >= 0:
            break
        im = pkg.imports[-cur - 1]
        parts.append(im['name'])
        cur = im['outer']
    return '.'.join(reversed(parts))


local, imported, missing = 0, 0, 0
pkgs = collections.Counter()
samples = []
for i, e in enumerate(pkg.exports):
    if pkg.class_of(e) != 'StaticMeshActor':
        continue
    pr, _ = mr.props(i + 1)
    if not pr:
        missing += 1; continue
    ci = raw(pr.get('StaticMeshComponent'))
    if not ci or ci <= 0:
        missing += 1; continue
    cpr, _ = mr.props(ci)
    if not cpr:
        missing += 1; continue
    mi = raw(cpr.get('StaticMesh'))
    if mi is None:
        missing += 1
    elif mi > 0:
        local += 1
    else:
        imported += 1
        path = outer_chain(mi)
        root = path.split('.')[0] if path else '?'
        pkgs[root] += 1
        if len(samples) < 10:
            samples.append((e['name'], path))

print("StaticMeshActor 的网格引用来源:")
print("  本包内 (local export): %d" % local)
print("  跨包引用 (import):     %d   <- 这些之前被全部丢弃" % imported)
print("  完全没解析出来:        %d" % missing)

print("\n被引用的外部包 (top 15):")
for p, n in pkgs.most_common(15):
    print("  %-40s %d" % (p, n))

print("\n样例:")
for n, p in samples:
    print("  %-26s -> %s" % (n, p))
