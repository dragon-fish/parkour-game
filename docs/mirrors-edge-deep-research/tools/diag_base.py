import sys, collections
sys.stdout.reconfigure(encoding='utf-8')
from mapdump import MapReader

mr = MapReader(sys.argv[1])
pkg = mr.pkg


def ref(v):
    return v[1] if (isinstance(v, tuple) and len(v) == 2 and v[0] == 'obj') else None


print("=== 每个 TdTutorialStart 的 Base（它站在什么上面）===")
kinds = collections.Counter()
for i, e in enumerate(pkg.exports):
    if pkg.class_of(e) != 'TdTutorialStart':
        continue
    pr, _ = mr.props(i + 1)
    if not pr:
        continue
    loc = pr.get('Location')
    sy = loc[2] / 100 if loc else None
    b = ref(pr.get('Base'))
    if b is None:
        kinds['<无 Base>'] += 1
        print("  %-22s y=%6.2f   Base = 无" % (e['name'], sy or -1))
        continue
    if b > 0:
        be = pkg.exports[b - 1]
        bcls = pkg.class_of(be)
        kinds[bcls] += 1
        bpr, _ = mr.props(b)
        bloc = bpr.get('Location') if bpr else None
        # follow to the mesh
        mesh = '-'
        if bpr:
            ci = ref(bpr.get('StaticMeshComponent'))
            if ci and ci > 0:
                cpr, _ = mr.props(ci)
                if cpr:
                    mi = ref(cpr.get('StaticMesh'))
                    if mi and mi > 0:
                        mesh = pkg.exports[mi - 1]['name']
        print("  %-22s y=%6.2f   Base -> #%-6d %-26s %-22s mesh=%s"
              % (e['name'], sy or -1, b, be['name'][:26], bcls, mesh))
    else:
        imp = pkg.imports[-b - 1]
        kinds['import:' + imp['class']] += 1
        print("  %-22s y=%6.2f   Base -> [import] %s.%s"
              % (e['name'], sy or -1, imp['package'], imp['name']))

print("\nBase 指向的类型统计:", dict(kinds))
