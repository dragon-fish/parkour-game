"""Reference reading of ATdPawn::GetWalkAcceleration / GetSprintAcceleration (MirrorsEdge.exe
0x012b57f0 / 0x012bd920) and the AccelCurve builder (0x012c2db0), checked against the original
machine code under Ghidra's emulator.

    uv run --no-project --python 3.12 accel_ref.py gen <spec_out> <n_cases> <seed>
    uv run --no-project --python 3.12 accel_ref.py check <spec> <emu_out>
"""
import math, random, struct, sys

# TdPawn CDO [ME:CONFIRMED TdPawn defaultproperties]
SPEED_CURVE = [(0.0, 0.0), (0.4, 400.0), (1.0, 520.0), (3.5, 650.0), (7.0, 720.0)]
P = dict(SpeedMaxBaseVelocity=400.0, SpeedMinBaseVelocity=10.0,
         SpeedStrafeVelocityAccelerationFactor=10.0, SpeedWalkVelocityAccelerationFactor=7.0,
         SpeedSprintVelocityAccelerationFactor=30.0, SpeedEnergyDecelerationTime=3.0,
         SpeedEnergyDecelerationExponent=0.5, SpeedTurnDecelerationFactor=10.0, GroundSpeed=720.0)
OFF = dict(Physics=0x68, PhysicsVolume=0xe4, Rotation=0xf4, Velocity=0x100, GroundSpeed=0x264,
           SpeedMaxBaseVelocity=0x6b4, SpeedMinBaseVelocity=0x6b8,
           SpeedStrafeVelocityAccelerationFactor=0x6bc, SpeedWalkVelocityAccelerationFactor=0x6c0,
           SpeedSprintVelocityAccelerationFactor=0x6c4, SpeedEnergyDecelerationTime=0x6c8,
           SpeedEnergyDecelerationExponent=0x6cc, SpeedTurnDecelerationFactor=0x6d0,
           AccelCurve_LightWeapon=0x6d4, SpeedSprintEnergy=0x6f4, MyWeapon=0x8f4)
GSIN = 0x02028088
VOLUME, CURVE = 0x11000000, 0x12000000
WALK, SPRINT = 0x012b57f0, 0x012bd920


def f32(x):
    return struct.unpack('<f', struct.pack('<f', x))[0]


def eval_linear(points, x):
    """FInterpCurve<float>::Eval for CIM_Linear points (what AddPoint creates)."""
    if not points:
        return 0.0
    if len(points) < 2 or x <= points[0][0]:
        return points[0][1]
    if x >= points[-1][0]:
        return points[-1][1]
    for i in range(1, len(points)):
        if x < points[i][0]:
            d = points[i][0] - points[i - 1][0]
            if d <= 0:
                return points[i - 1][1]
            a = (x - points[i - 1][0]) / d
            return points[i - 1][1] + (points[i][1] - points[i - 1][1]) * a
    return points[-1][1]


def build_accel_curve(speed_curve, steps=10):
    """0x012c2db0: invert speed(t) by sampling, then forward-difference speed over 0.5/steps s."""
    t_max, v_max = speed_curve[-1][0], speed_curve[-1][1]
    n = len(speed_curve) * 10
    inverse = []
    for j in range(n + 1):
        t = f32(j * t_max / n)
        add_point(inverse, f32(eval_linear(speed_curve, t)), t)
    h = 0.5 / steps
    out = []
    for i in range(steps + 1):
        s = f32(i * v_max / steps)
        t = eval_linear(inverse, s)
        add_point(out, s, f32((eval_linear(speed_curve, t + h) - eval_linear(speed_curve, t)) * (1.0 / h)))
    return out


def add_point(points, in_val, out_val):
    """FInterpCurve::AddPoint keeps points sorted by InVal; equal keys go after existing ones."""
    i = 0
    while i < len(points) and points[i][0] <= in_val:
        i += 1
    points.insert(i, (in_val, out_val))


ACCEL_CURVE = build_accel_curve(SPEED_CURVE)


def axes(yaw):
    """FRotationMatrix(Rotation) X and Y rows, pitch = roll = 0, through the 16384-entry sine table."""
    s = math.sin(((yaw >> 2) & 0x3fff) * 2 * math.pi / 16384)
    c = math.sin((((yaw + 0x4000) >> 2) & 0x3fff) * 2 * math.pi / 16384)
    return (c, s, 0.0), (-s, c, 0.0)


def safe_normal(v):
    sq = v[0] * v[0] + v[1] * v[1] + v[2] * v[2]
    if sq == 1.0:
        return v
    if sq < 1e-8:
        return (0.0, 0.0, 0.0)
    k = 1.0 / math.sqrt(sq)
    return (v[0] * k, v[1] * k, v[2] * k)


def rnd(v):
    return tuple(math.floor(x * 10.0 + 0.5) * 0.1 for x in v)


def walk(case):
    X, Y = axes(case['yaw'])
    V, E = case['vel'], case['energy']
    fwd, strafe, dt = case['fwd'], case['strafe'], case['dt']
    d = safe_normal(tuple(X[k] * fwd + Y[k] * strafe for k in range(3)))
    if all(abs(c) < 1e-4 for c in d):
        return (0.0, 0.0, 0.0), 0.0
    if E > 0:
        base = min(max(d[0] * X[0] + d[1] * X[1] + d[2] * X[2], 0.0), f32(0.9))
        E -= (P['GroundSpeed'] - P['SpeedMaxBaseVelocity']) * (1 - base ** P['SpeedEnergyDecelerationExponent']) \
            / P['SpeedEnergyDecelerationTime'] * dt
        E = max(E, 0.0)
    top = P['SpeedMaxBaseVelocity'] - P['SpeedMinBaseVelocity'] + E
    want_x = (d[0] * X[0] + d[1] * X[1] + d[2] * X[2]) * P['SpeedMinBaseVelocity'] + top * fwd
    want_y = (d[0] * Y[0] + d[1] * Y[1] + d[2] * Y[2]) * P['SpeedMinBaseVelocity'] + top * strafe
    vx = V[0] * X[0] + V[1] * X[1] + V[2] * X[2]
    vy = V[0] * Y[0] + V[1] * Y[1] + V[2] * Y[2]
    kw, ks = P['SpeedWalkVelocityAccelerationFactor'], P['SpeedStrafeVelocityAccelerationFactor']
    a = [X[k] * (want_x - vx) * kw + Y[k] * (want_y - vy) * ks for k in range(3)]
    if case['physics'] != 2:
        a = [a[k] + V[k] * case['friction'] * 0.1 for k in range(3)]
    return rnd(a), E


def sprint(case):
    X, Y = axes(case['yaw'])
    V = case['vel']
    fwd, strafe, dt, turn = case['fwd'], case['strafe'], case['dt'], case['turn']
    speed = math.sqrt(V[0] * V[0] + V[1] * V[1])
    d = safe_normal(tuple(X[k] * fwd + Y[k] * strafe for k in range(3)))
    if all(abs(c) < 1e-4 for c in d):
        return (0.0, 0.0, 0.0), 0.0
    E = max(speed - P['SpeedMaxBaseVelocity'], 0.0)
    acc = eval_linear(ACCEL_CURVE, speed)
    a = [d[k] * acc for k in range(3)]
    if case['physics'] != 2:
        diff = (d[0] * speed - V[0], d[1] * speed - V[1])
        n = math.sqrt(diff[0] ** 2 + diff[1] ** 2)
        steer = min(P['SpeedSprintVelocityAccelerationFactor'] * n, n / dt)
        dn = safe_normal((diff[0], diff[1], 0.0))
        a = [a[k] + dn[k] * steer + V[k] * case['friction'] * 0.1 for k in range(3)]
    T = P['SpeedTurnDecelerationFactor']
    a = [a[k] - V[k] * T * abs(turn) / 32768.0 for k in range(3)]
    return rnd(a), E


def gen(path, n, seed):
    rng = random.Random(seed)
    with open(path, 'w') as f:
        for fn_name, fn in (('walk', WALK), ('sprint', SPRINT)):
            f.write(f'func {fn:#x}\n')
            for i in range(n):
                c = dict(yaw=rng.randrange(0, 65536), vel=(rng.uniform(-750, 750), rng.uniform(-750, 750), rng.uniform(-300, 300)),
                         fwd=rng.choice([1.0, 0.0, -1.0, rng.uniform(-1, 1)]), strafe=rng.choice([0.0, 1.0, -1.0, rng.uniform(-1, 1)]),
                         dt=rng.choice([1 / 60, 1 / 30, rng.uniform(0.005, 0.05)]), turn=rng.choice([0, rng.randrange(-3000, 3000)]),
                         physics=rng.choice([1, 1, 2]), friction=8.0, energy=rng.choice([0.0, rng.uniform(0, 320)]))
                c = {k: (tuple(f32(x) for x in v) if isinstance(v, tuple) else (f32(v) if isinstance(v, float) else v)) for k, v in c.items()}
                f.write(f'case {fn_name}{i}\n# {c!r}\n')
                f.write(f'sintable {GSIN:#x}\n')
                f.write(f'thisb {OFF["Physics"]:#x} {c["physics"]}\n')
                f.write(f'ptr {OFF["PhysicsVolume"]:#x} {VOLUME:#x}\n')
                f.write(f'f32 {VOLUME + 0x20c:#x} {c["friction"]!r}\n')
                f.write(f'thisi {OFF["Rotation"] + 4:#x} {c["yaw"]}\n')
                for k in range(3):
                    f.write(f'thisf {OFF["Velocity"] + 4 * k:#x} {c["vel"][k]!r}\n')
                for k, v in P.items():
                    f.write(f'thisf {OFF[k]:#x} {v!r}\n')
                f.write(f'thisf {OFF["SpeedSprintEnergy"]:#x} {c["energy"]!r}\n')
                f.write(f'ptr {OFF["AccelCurve_LightWeapon"]:#x} {CURVE:#x}\n')
                f.write(f'thisi {OFF["AccelCurve_LightWeapon"] + 4:#x} {len(ACCEL_CURVE)}\n')
                f.write(f'thisi {OFF["AccelCurve_LightWeapon"] + 8:#x} {len(ACCEL_CURVE)}\n')
                for j, (iv, ov) in enumerate(ACCEL_CURVE):
                    f.write(f'f32 {CURVE + 20 * j:#x} {iv!r}\nf32 {CURVE + 20 * j + 4:#x} {ov!r}\n')
                f.write('arg out\n')
                f.write(f'arg f32 {c["fwd"]!r}\narg f32 {c["strafe"]!r}\narg i32 {c["turn"]}\narg f32 {c["dt"]!r}\n')
                f.write(f'read out3\nread thisf {OFF["SpeedSprintEnergy"]:#x}\nend\n')


def check(spec, emu_out):
    cases = {}
    name = None
    for line in open(spec):
        if line.startswith('case '):
            name = line.split()[1]
        elif line.startswith('# ') and name:
            cases[name] = eval(line[2:])
    worst, bad = 0.0, 0
    for line in open(emu_out):
        nm, rest = line.split(' ', 1)
        if 'STOPPED' in rest:
            print('EMU', nm, rest.strip()); bad += 1; continue
        got = tuple(float(x) for x in rest.split('out=(')[1].split(')')[0].split(','))
        got_e = float(rest.split('=')[-1])
        want, want_e = (walk if nm.startswith('walk') else sprint)(cases[nm])
        err = max(abs(g - w) for g, w in zip(got, want))
        err_e = abs(got_e - want_e)
        worst = max(worst, err)
        if err > 0.11 or err_e > 1e-2:
            bad += 1
            if bad <= 12:
                print('MISMATCH', nm, 'got', got, got_e, 'want', want, want_e)
    print(f'{len(cases)} cases, {bad} mismatches, worst accel error {worst:.4f}')


if __name__ == '__main__':
    if sys.argv[1] == 'gen':
        gen(sys.argv[2], int(sys.argv[3]), int(sys.argv[4]))
    else:
        check(sys.argv[2], sys.argv[3])
