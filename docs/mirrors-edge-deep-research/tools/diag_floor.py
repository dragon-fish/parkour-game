import sys, json
sys.stdout.reconfigure(encoding='utf-8')

data = json.load(open(sys.argv[1], encoding='utf-8'))
boxes = data['boxes']
spawns = data.get('spawns', [])

print("=== 每个出生点正下方 6m 内有没有可站立的盒子 ===")
missing = 0
for s in spawns:
    sx, sy, sz = s['pos']
    under = []
    for b in boxes:
        bx, by, bz = b['pos']
        hx, hy, hz = [v / 2 for v in b['size']]
        if abs(sx - bx) > hx or abs(sz - bz) > hz:
            continue                      # 水平不覆盖
        top = by + hy
        if sy - 6.0 <= top <= sy + 0.5:
            under.append((top, b))
    under.sort(key=lambda t: -t[0])
    if under:
        top, b = under[0]
        print("  %-22s y=%6.2f  <- %-30s top=%6.2f  (共 %d 个)"
              % (s['name'], sy, b['mesh'][:30], top, len(under)))
    else:
        missing += 1
        print("  %-22s y=%6.2f  <- 【无地板】" % (s['name'], sy))
print("\n没有地板的出生点: %d / %d" % (missing, len(spawns)))

# 检查有多少盒子的 Y 明显低于活动区（可能被放错高度）
print("\n=== 水平在活动区内、但 Y < 20m 的盒子 ===")
low = [b for b in boxes
       if -95 <= b['pos'][0] <= 55 and 10 <= b['pos'][2] <= 90 and b['pos'][1] < 20]
print("  共 %d 个，最大的 10 个:" % len(low))
low.sort(key=lambda b: -max(b['size']))
for b in low[:10]:
    print("    %-32s %-22s pos=%s" % (b['mesh'][:32],
          'x'.join('%.1f' % v for v in b['size']), b['pos']))
