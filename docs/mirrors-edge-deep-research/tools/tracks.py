import sys, struct, collections
sys.stdout.reconfigure(encoding='utf-8')
from mapdump import MapReader

mr = MapReader(sys.argv[1])
pkg = mr.pkg
d = mr.d

# tutorial order taken from DefaultGame.ini's ObjectiveMappings
ORDER = [
    'EMC_ButtonTest', 'EMC_JumpTimingOne', 'EMC_SlideOne', 'EMC_JumpTimingTwo',
    'EMC_VaultOver', 'EMC_HorizontalWallrun', 'EMC_SpeedVault', 'EMC_Barge',
    'EMC_BalanceWalk',
    'EMC_VerticalWallrun', 'EMC_Swing', 'EMC_Climb', 'EMC_Turn180',
    'EMC_JumpToGrab', 'EMC_LedgeWalk',
    'EMC_ZipLine', 'EMC_SoftLanding',
    'EMC_CoilJump', 'EMC_BackToStart', 'EMC_SpringBoard',
    'EMC_MeleeAttack', 'EMC_LowMeleeAttack', 'EMC_JumpKickAttack', 'EMC_SlideKickAttack',
    'EMC_RearDisarm', 'EMC_FrontDisarm', 'EMC_FrontalDisarmRT',
]


def raw_entries(idx):
    """Re-run offset calibration and keep each tag's value position."""
    e = pkg.exports[idx - 1]
    base, end = e['offset'], e['offset'] + e['size']
    best = None
    for off in range(0, min(96, e['size']), 4):
        ok, pr, nat = mr._chain(base + off, end)
        if ok and (best is None or len(pr) > len(best)):
            best = pr
    return best or []


tracks = collections.defaultdict(list)
for i, ex in enumerate(pkg.exports):
    if pkg.class_of(ex) != 'TdTutorialCheckpoint':
        continue
    pr, _ = mr.props_inherited(i + 1)
    loc = pr.get('Location') if pr else None
    for (name, typ, extra, q, sz, arr) in raw_entries(i + 1):
        if name != 'BelongToTracks' or typ != 'ArrayProperty':
            continue
        cnt = struct.unpack_from('<i', d, q)[0]
        if cnt <= 0 or cnt > 64:
            continue
        for k in range(cnt):
            p = q + 4 + k * 8
            if p + 8 > q + sz:
                break
            nm = mr.nm(struct.unpack_from('<i', d, p)[0])
            if nm and loc:
                tracks[nm].append((loc[0] / 100, loc[2] / 100, -loc[1] / 100))

print("解析出的教程段落: %d 个\n" % len(tracks))
print("%-4s %-24s %-5s %s" % ("序", "段落", "点数", "中心 (Godot m)"))
print("-" * 68)
for n, key in enumerate(ORDER, 1):
    pts = tracks.get(key)
    if not pts:
        print("%-4d %-24s %-5s -" % (n, key, 0))
        continue
    cx = sum(p[0] for p in pts) / len(pts)
    cy = sum(p[1] for p in pts) / len(pts)
    cz = sum(p[2] for p in pts) / len(pts)
    print("%-4d %-24s %-5d (%7.1f, %6.1f, %7.1f)" % (n, key, len(pts), cx, cy, cz))

extra_keys = [k for k in tracks if k not in ORDER]
if extra_keys:
    print("\n不在 ObjectiveMappings 顺序表里的段落:")
    for k in extra_keys:
        pts = tracks[k]
        cx = sum(p[0] for p in pts) / len(pts)
        cy = sum(p[1] for p in pts) / len(pts)
        cz = sum(p[2] for p in pts) / len(pts)
        print("     %-24s %-4d (%7.1f, %6.1f, %7.1f)" % (k, len(pts), cx, cy, cz))
