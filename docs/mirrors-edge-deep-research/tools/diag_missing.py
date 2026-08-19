import sys, json, math, collections
sys.stdout.reconfigure(encoding='utf-8')

data = json.load(open(sys.argv[1], encoding='utf-8'))
boxes, path = data['boxes'], data['path']
spawns = [s['pos'] for s in data.get('spawns', [])]
anchors = path + spawns


def dist(b):
    cx, cy, cz = b['pos']
    hx, hy, hz = [s / 2 for s in b['size']]
    best = 1e18
    for px, py, pz in anchors:
        dx = max(0.0, abs(px - cx) - hx)
        dy = max(0.0, abs(py - cy) - hy)
        dz = max(0.0, abs(pz - cz) - hz)
        d = dx * dx + dy * dy + dz * dz
        if d < best:
            best = d
            if best == 0.0:
                break
    return math.sqrt(best)


# play area from the anchors
axs = [a[0] for a in anchors]; ays = [a[1] for a in anchors]; azs = [a[2] for a in anchors]
print("玩家活动范围 (m): X %.0f..%.0f  Y %.0f..%.0f  Z %.0f..%.0f"
      % (min(axs), max(axs), min(ays), max(ays), min(azs), max(azs)))

# where does each source file's geometry sit?
print("\n=== 按来源看坐标分布 ===")
bysrc = collections.defaultdict(list)
for b in boxes:
    bysrc[b['src']].append(b)
for src, bs in bysrc.items():
    xs = [b['pos'][0] for b in bs]; ys = [b['pos'][1] for b in bs]; zs = [b['pos'][2] for b in bs]
    near = sum(1 for b in bs if dist(b) <= 20)
    print("  %-22s n=%4d  X %7.0f..%-7.0f Y %6.0f..%-6.0f Z %7.0f..%-7.0f  路径20m内=%d"
          % (src, len(bs), min(xs), max(xs), min(ys), max(ys), min(zs), max(zs), near))

# how many sit suspiciously close to the origin (prefab-local giveaway)
print("\n=== 疑似 prefab 局部坐标（|pos| < 30m，而活动区在 Y 40+）===")
nearzero = [b for b in boxes if abs(b['pos'][0]) < 30 and abs(b['pos'][1]) < 30 and abs(b['pos'][2]) < 30]
print("  共 %d 个" % len(nearzero))
c = collections.Counter(b['src'] for b in nearzero)
print("  来源:", dict(c))
pf = sum(1 for b in nearzero if b['mesh'].startswith(('S_R_', 'S_Rooftop', 'S_C_')))
print("  其中屋顶/结构类网格: %d" % pf)

# rooftop-ish meshes: where are they?
print("\n=== 屋顶类网格的位置分布 ===")
KEY = ('rooftop', '_r_', 'roof', 'plug', 'floor', 'ground', 'walkway')
roofs = [b for b in boxes if any(k in b['mesh'].lower() for k in KEY)]
print("  匹配 %d 个" % len(roofs))
d0 = sum(1 for b in roofs if dist(b) <= 1)
d20 = sum(1 for b in roofs if dist(b) <= 20)
print("  距路径 <1m: %d    <20m: %d    其余: %d" % (d0, d20, len(roofs) - d20))
far = [b for b in roofs if dist(b) > 20]
far.sort(key=lambda b: -max(b['size']))
print("\n  离路径最远的屋顶类网格（前 10）:")
for b in far[:10]:
    print("    %-34s %-22s pos=%-30s d=%.0fm src=%s"
          % (b['mesh'][:34], 'x'.join('%.1f' % v for v in b['size']),
             str(b['pos']), dist(b), b['src']))
