import sys, json, collections
sys.stdout.reconfigure(encoding='utf-8')
from mapdump import MapReader

mr = MapReader(sys.argv[1])
pkg = mr.pkg

print("=== 含 start / spawn / player 的类 ===")
hist = collections.Counter(pkg.class_of(e) for e in pkg.exports)
for cls, n in sorted(hist.items()):
    if any(k in cls.lower() for k in ('start', 'spawn', 'player')):
        print("  %-34s %d" % (cls, n))

print("\n=== 它们的坐标 ===")
for i, e in enumerate(pkg.exports):
    c = pkg.class_of(e)
    cl = c.lower()
    if not any(k in cl for k in ('start', 'spawn')) or cl.startswith(('particlemodule', 'seq')):
        continue
    pr, _ = mr.props(i + 1)
    loc = pr.get('Location') if pr else None
    rot = pr.get('Rotation') if pr else None
    if loc:
        print("  %-26s %-26s godot_m=(%7.1f,%7.1f,%7.1f) yaw=%s"
              % (c, e['name'], loc[0]/100, loc[2]/100, -loc[1]/100,
                 round(rot[1] * 360 / 65536, 1) if rot else '-'))
    else:
        print("  %-26s %-26s (无 Location)" % (c, e['name']))

# 验证旧过滤条件下那栋楼是否会被保留
if len(sys.argv) > 2:
    data = json.load(open(sys.argv[2], encoding='utf-8'))
    boxes = data['boxes'] if isinstance(data, dict) else data
    print("\n=== 旧过滤（MAX=300, MIN=0.1）下，最大的 8 个盒子 ===")
    keep = [b for b in boxes if max(b['size']) <= 300 and min(b['size']) >= 0.1]
    keep.sort(key=lambda b: -max(b['size']))
    print("保留 %d / %d" % (len(keep), len(boxes)))
    for b in keep[:8]:
        print("  %-32s size=%-22s pos=%s"
              % (b['mesh'][:32], 'x'.join('%.1f' % v for v in b['size']), b['pos']))
    for name in ('S_R_05_03_F', 'S_C_02_02_F'):
        got = [b for b in keep if b['mesh'] == name]
        print("  -> %s 在保留集合中: %s" % (name, '是（%d 个）' % len(got) if got else '否'))
