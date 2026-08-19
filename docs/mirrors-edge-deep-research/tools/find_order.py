import sys, collections
sys.stdout.reconfigure(encoding='utf-8')
from mapdump import MapReader

mr = MapReader(sys.argv[1])
pkg = mr.pkg

# 1) do tutorial checkpoints carry readable names/tags?
print("=== TdTutorialCheckpoint 的可读标识 ===")
seen = collections.Counter()
rows = []
for i, e in enumerate(pkg.exports):
    if pkg.class_of(e) != 'TdTutorialCheckpoint':
        continue
    pr, _ = mr.props_inherited(i + 1)
    if not pr:
        continue
    loc = pr.get('Location')
    tag = pr.get('Tag')
    grp = pr.get('Group')
    for k in pr:
        seen[k] += 1
    if loc and (tag or grp):
        rows.append((str(tag), str(grp), loc))
print("属性出现频次:", dict(seen.most_common(14)))
print("带 Tag/Group 的: %d" % len(rows))
for t, g, l in rows[:25]:
    print("  Tag=%-30s Group=%-28s godot=(%7.1f,%7.1f,%7.1f)"
          % (t[:30], g[:28], l[0]/100, l[2]/100, -l[1]/100))

# 2) any object anywhere whose NAME contains EMC_
print("\n=== 名字里含 EMC_ 的对象 ===")
n = 0
for i, e in enumerate(pkg.exports):
    if 'emc' not in e['name'].lower():
        continue
    pr, _ = mr.props_inherited(i + 1)
    loc = pr.get('Location') if pr else None
    pos = "(%7.1f,%7.1f,%7.1f)" % (loc[0]/100, loc[2]/100, -loc[1]/100) if loc else "-"
    print("  %-40s %-26s %s" % (e['name'][:40], pkg.class_of(e), pos))
    n += 1
    if n >= 40:
        break
print("  共找到 %d 个（最多列 40）" % n)

# 3) names containing EMC_ in the NAME TABLE (may exist without an export)
hits = [nm for nm in pkg.names if 'emc' in nm.lower()]
print("\n名称表里含 EMC 的条目 (%d): %s" % (len(hits), hits[:40]))
