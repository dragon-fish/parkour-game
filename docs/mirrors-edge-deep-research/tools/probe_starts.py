import sys
sys.stdout.reconfigure(encoding='utf-8')
from mapdump import MapReader

mr = MapReader(sys.argv[1])
pkg = mr.pkg
target = sys.argv[2] if len(sys.argv) > 2 else 'TdTutorialStart'

rows = []
keys = set()
for i, e in enumerate(pkg.exports):
    if pkg.class_of(e) != target:
        continue
    pr, _ = mr.props(i + 1)
    if pr is None:
        continue
    keys.update(pr.keys())
    rows.append((e['name'], pr))

print("%s: %d 个，出现过的属性: %s\n" % (target, len(rows), sorted(keys)))
show = [k for k in sorted(keys) if k not in ('Location', 'Rotation')]
for name, pr in sorted(rows, key=lambda r: r[0]):
    loc = pr.get('Location')
    pos = "(%7.1f,%7.1f,%7.1f)" % (loc[0]/100, loc[2]/100, -loc[1]/100) if loc else "-"
    extra = "  ".join("%s=%s" % (k, pr[k]) for k in show if k in pr)
    print("  %-24s %s  %s" % (name, pos, extra))
