import sys
sys.stdout.reconfigure(encoding='utf-8')
from mapdump import MapReader

mr = MapReader(sys.argv[1])
pkg = mr.pkg


def raw(v):
    return v[1] if (isinstance(v, tuple) and len(v) == 2 and v[0] == 'obj') else None


def describe(idx):
    e = pkg.exports[idx - 1]
    return "#%d %s (%s) arch=%d" % (idx, e['name'], pkg.class_of(e), e['archetype'])


def chain(idx, prop, depth=6):
    """Walk export -> archetype until `prop` is found."""
    cur = idx
    for d in range(depth):
        if cur <= 0:
            return None, "停在非导出索引 %d" % cur
        pr, _ = mr.props(cur)
        e = pkg.exports[cur - 1]
        got = pr.get(prop) if pr else None
        print("    %d层: %-46s props=%-4s %s=%s"
              % (d, describe(cur), len(pr) if pr else 0, prop, got))
        if got is not None:
            return got, None
        cur = e['archetype']
    return None, "超过深度"


for target in sys.argv[2:]:
    idx = int(target)
    e = pkg.exports[idx - 1]
    print("\n=== %s ===" % describe(idx))
    pr, _ = mr.props(idx)
    print("  actor 属性: %s" % (sorted(pr.keys()) if pr else None))
    ci = raw(pr.get('StaticMeshComponent')) if pr else None
    if ci is None:
        print("  沿 archetype 找 StaticMeshComponent:")
        ci, err = chain(idx, 'StaticMeshComponent')
        ci = raw(ci)
    if not ci or ci <= 0:
        print("  -> 仍拿不到组件")
        continue
    print("  组件 = %s" % describe(ci))
    print("  沿 archetype 找 StaticMesh:")
    mesh, err = chain(ci, 'StaticMesh')
    mi = raw(mesh)
    if mi and mi > 0:
        print("  ==> 网格 = %s" % describe(mi))
        b = mr.bounds(mi)
        print("      bounds = %s" % (tuple(round(v, 1) for v in b) if b else None))
    else:
        print("  ==> 失败: %s" % (err or mesh))
