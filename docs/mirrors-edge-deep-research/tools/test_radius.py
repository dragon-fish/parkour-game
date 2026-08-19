import sys, json, math
sys.stdout.reconfigure(encoding='utf-8')

data = json.load(open(sys.argv[1], encoding='utf-8'))
boxes, path = data['boxes'], data['path']


def dist_to_path(b):
    """Min distance from any path point to the box's AABB (0 if inside)."""
    cx, cy, cz = b['pos']
    hx, hy, hz = b['size'][0] / 2, b['size'][1] / 2, b['size'][2] / 2
    best = 1e18
    for px, py, pz in path:
        dx = max(0.0, abs(px - cx) - hx)
        dy = max(0.0, abs(py - cy) - hy)
        dz = max(0.0, abs(pz - cz) - hz)
        d = dx * dx + dy * dy + dz * dz
        if d < best:
            best = d
            if best == 0.0:
                break
    return math.sqrt(best)


for b in boxes:
    b['_d'] = dist_to_path(b)

print("%-8s %-8s %-10s %s" % ("半径", "保留", "最大边长", "最大的三个盒子"))
for r in (5, 10, 15, 20, 30, 50, 100):
    keep = [b for b in boxes if b['_d'] <= r]
    if not keep:
        continue
    keep.sort(key=lambda b: -max(b['size']))
    top = ', '.join("%s(%.0fm)" % (b['mesh'][:22], max(b['size'])) for b in keep[:3])
    print("%-8s %-8d %-10.0f %s" % ("%dm" % r, len(keep), max(max(b['size']) for b in keep), top))

inside = [b for b in boxes if b['_d'] == 0.0]
print("\n路径直接落在其中/表面的盒子: %d 个" % len(inside))
inside.sort(key=lambda b: -max(b['size']))
for b in inside[:6]:
    print("  %-30s size=%-22s pos=%s" % (b['mesh'][:30],
          'x'.join('%.1f' % v for v in b['size']), b['pos']))
