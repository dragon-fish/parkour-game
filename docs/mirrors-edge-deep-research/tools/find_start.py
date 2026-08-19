import sys, collections
sys.stdout.reconfigure(encoding='utf-8')
from mapdump import MapReader

mr = MapReader(sys.argv[1])
pkg = mr.pkg

KEYS = ('playerstart', 'checkpoint', 'startpoint', 'movenode', 'timer')
hits = collections.Counter()
found = []
for i, e in enumerate(pkg.exports):
    c = pkg.class_of(e)
    if not any(k in c.lower() for k in KEYS):
        continue
    hits[c] += 1
    pr, _ = mr.props(i + 1)
    loc = pr.get('Location') if pr else None
    if loc:
        found.append((c, e['name'], loc))

print("匹配的类:", dict(hits))
print("\n带 Location 的（前 20）:")
for c, n, loc in found[:20]:
    print("  %-26s %-30s uu=(%9.0f,%9.0f,%9.0f)  godot_m=(%7.1f,%7.1f,%7.1f)"
          % (c, n, loc[0], loc[1], loc[2], loc[0]/100, loc[2]/100, -loc[1]/100))
print("\n共 %d 个带坐标" % len(found))
