import sys, collections
sys.stdout.reconfigure(encoding='utf-8')
from mapdump import MapReader

SKIP = ('particlemodule', 'seqact', 'seqevt', 'seqvar', 'seqcond', 'distribution',
        'materialexpression', 'soundnode', 'texture', 'material', 'component',
        'package', 'staticmesh', 'font', 'uistate', 'uiaction', 'interpgroup',
        'interptrack', 'animnode', 'animset', 'skeletalmesh', 'physicalmaterial',
        'shadow', 'lightmap', 'rb_', 'level', 'world', 'class', 'function')

mr = MapReader(sys.argv[1])
pkg = mr.pkg

rows = collections.defaultdict(lambda: [0, 0, None])   # class -> [total, with_loc, sample]
for i, e in enumerate(pkg.exports):
    c = pkg.class_of(e)
    cl = c.lower()
    if any(k in cl for k in SKIP):
        continue
    pr, _ = mr.props(i + 1)
    rows[c][0] += 1
    if pr and 'Location' in pr:
        rows[c][1] += 1
        if rows[c][2] is None:
            l = pr['Location']
            rows[c][2] = (l[0] / 100, l[2] / 100, -l[1] / 100)

print("%-38s %6s %8s  %s" % ("类", "总数", "带坐标", "样例 godot_m"))
print("-" * 82)
for c, (tot, loc, s) in sorted(rows.items(), key=lambda kv: -kv[1][1]):
    if loc == 0:
        continue
    print("%-38s %6d %8d  (%7.1f,%7.1f,%7.1f)" % (c, tot, loc, s[0], s[1], s[2]))

noloc = [(c, v[0]) for c, v in rows.items() if v[1] == 0 and v[0] >= 3]
print("\n无坐标但数量可观的类（可能是数据容器）:")
for c, n in sorted(noloc, key=lambda kv: -kv[1])[:15]:
    print("  %-40s %d" % (c, n))
