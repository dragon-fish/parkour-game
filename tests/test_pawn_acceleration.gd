extends ParkourTest

# PawnAcceleration is a verbatim port of two native functions. These cases are
# the ORIGINAL MACHINE CODE's own outputs: inputs drawn at random, run through
# MirrorsEdge.exe's GetWalkAcceleration / GetSprintAcceleration under Ghidra's
# emulator (docs/mirrors-edge-deep-research/tools/verify/accel_ref.py), converted
# to metres. A mismatch means the port no longer computes what the original
# computes -- not that a value needs re-tuning.

## The original rounds to 0.1 uu/s^2 = 0.001 m/s^2; one step either way is the
## same answer reached through float instead of x87 arithmetic.
const TOLERANCE := 0.0011

# [name, kind, velocity, forward, right, falling, energy_in, aForward, aStrafe,
#  aTurn, dt, expected acceleration, expected energy]
const CASES := [
	["walk0", "walk", Vector3(6.7179803466796875, -2.7102813720703125, -1.5776475524902345), Vector3(-0.5996962259862088, 0.0, -0.8002277404201243), Vector3(0.8002277404201243, 0.0, -0.5996962259862088), false, 0.0, 1.0, 0.0, 0, 0.01666666753590107, Vector3(-73.62, -2.168, -1.251), 0.0],
	["walk1", "walk", Vector3(0.7657087707519531, 0.39272216796875004, -6.61334228515625), Vector3(0.41782371582021244, 0.0, 0.9085281187163061), Vector3(-0.9085281187163061, 0.0, 0.41782371582021244), false, 0.0, 1.0, 0.15420590341091156, 0, 0.01666666753590107, Vector3(-8.082, 0.314, 73.346), 0.0],
	["walk4", "walk", Vector3(0.17899246215820314, -0.9476651763916015, -5.025568542480469), Vector3(0.08732553520619206, 0.0, 0.9961798285956969), Vector3(-0.9961798285956969, 0.0, 0.08732553520619206), true, 1.120570831298828, 0.8665404319763184, 0.0, -430, 0.039405688643455505, Vector3(-0.378, 0.0, 66.362), 1.11841385],
	["walk5", "walk", Vector3(-6.468555908203125, -1.3803643798828125, -6.096060180664063), Vector3(0.8521589016239198, 0.0, -0.5232831034756568), Vector3(0.5232831034756568, 0.0, 0.8521589016239198), true, 1.2345326232910157, 1.0, -1.0, 650, 0.034120798110961914, Vector3(62.556000000000004, 0.0, 1.253), 1.228742],
	["walk6", "walk", Vector3(6.609728393554688, 0.6655172729492188, -2.168038330078125), Vector3(0.9601094509757738, 0.0, 0.2796244662882666), Vector3(-0.2796244662882666, 0.0, 0.9601094509757738), false, 0.5323720932006836, 0.0, 1.0, 202, 0.03333333507180214, Vector3(-56.851000000000006, 0.532, 67.935), 0.49681652],
	["walk8", "walk", Vector3(-0.22555904388427736, -1.4235203552246094, 1.3368525695800781), Vector3(0.9885487357147632, 0.0, 0.15090194537097004), Vector3(-0.15090194537097004, 0.0, 0.9885487357147632), false, 2.8785055541992186, -0.9918127655982971, -1.0, 0, 0.047889407724142075, Vector3(-34.388000000000005, -1.139, -86.63700000000001), 2.8274234000000003],
	["sprint1", "sprint", Vector3(4.274133911132813, 2.488227996826172, 3.1282803344726564), Vector3(-0.9725843689347323, 0.0, -0.23255030703877494), Vector3(0.23255030703877494, 0.0, -0.9725843689347323), false, 0.0, 1.0, 0.0, -1775, 0.027404744178056717, Vector3(-283.095, 0.643, -130.335), 1.2966364],
	["sprint2", "sprint", Vector3(5.2752795410156255, -1.271621856689453, 2.889651184082031), Vector3(0.05710969465515806, 0.0, -0.9983679095285438), Vector3(0.9983679095285438, 0.0, 0.05710969465515806), false, 0.9600727844238282, -1.0, -0.2186310887336731, 1092, 0.01666666753590107, Vector3(-204.47400000000002, -0.594, 88.928), 2.01487],
	["sprint3", "sprint", Vector3(-0.9653118896484375, -1.60837646484375, -1.8450140380859374), Vector3(-0.24855616387879642, 0.0, 0.9686174855936976), Vector3(-0.9686174855936976, 0.0, -0.24855616387879642), false, 0.15181466102600097, -1.0, 1.0, 0, 0.01666666753590107, Vector3(-8.711000400000001, -1.287, -8.497), 0.0],
	["sprint5", "sprint", Vector3(-1.3572134399414062, 0.891218032836914, 0.013632148504257202), Vector3(0.32168155023295647, 0.0, 0.946847918221148), Vector3(-0.946847918221148, 0.0, 0.32168155023295647), true, 0.0, 0.0, 0.7596701979637146, 2116, 0.03333333507180214, Vector3(-8.592, -0.5760000200000001, 3.2080002000000003), 0.0],
	["sprint7", "sprint", Vector3(-1.3161058044433593, 0.3897095108032227, -6.597451171875), Vector3(-0.7122402339424455, 0.0, 0.7019357870586244), Vector3(-0.7019357870586244, 0.0, -0.7122402339424455), false, 0.0, 1.0, 0.0, 0, 0.03333333507180214, Vector3(-105.525, 0.312, 334.51800000000003), 2.7274432],
	["sprint20", "sprint", Vector3(1.6279449462890625, 1.5417581176757813, -1.0394548797607421), Vector3(0.8764396667957138, 0.0, 0.4815116929701899), Vector3(-0.4815116929701899, 0.0, 0.8764396667957138), true, 1.6664939880371095, 1.0, 1.0, 1670, 0.01666666753590107, Vector3(1.963, -0.7859999999999999, 10.132000000000001), 0.0],
]

func _params() -> PawnAcceleration.Params:
	var p := PawnAcceleration.Params.new()
	# [ME:CONFIRMED TdPawn defaultproperties] SpeedCurve_LightWeapon, metric.
	p.accel_curve = PawnAcceleration.build_accel_curve(PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(0.4, 4.0), Vector2(1.0, 5.2), Vector2(3.5, 6.5), Vector2(7.0, 7.2)]))
	return p

func test_the_port_reproduces_the_original_machine_code() -> void:
	var p := _params()
	for c in CASES:
		var s := PawnAcceleration.State.new()
		s.velocity = c[2]
		s.forward = c[3]
		s.right = c[4]
		s.falling = c[5]
		s.sprint_energy = c[6]
		var got: Vector3
		if c[1] == "walk":
			got = PawnAcceleration.walk(s, p, c[7], c[8], c[9], c[10])
		else:
			got = PawnAcceleration.sprint(s, p, c[7], c[8], c[9], c[10])
		var want: Vector3 = c[11]
		assert_true((got - want).abs().x <= TOLERANCE and (got - want).abs().y <= TOLERANCE \
			and (got - want).abs().z <= TOLERANCE, "%s: got %s, the original gives %s" % [c[0], got, want])
		assert_almost_eq(s.sprint_energy, c[12], 0.0002, "%s: SpeedSprintEnergy" % c[0])

func test_the_generated_accel_curve_matches_the_native_builder() -> void:
	# The builder's output for the CDO speed curve, as emulated: 11 points from
	# 0 to 7.2 m/s, flat 10 m/s^2 up to 2.88 m/s, nothing left at the top.
	var curve := _params().accel_curve
	assert_eq(curve.size(), 11)
	assert_almost_eq(curve[0].y, 10.0, 0.001)
	assert_almost_eq(curve[4].y, 10.0, 0.001)
	assert_almost_eq(curve[5].y, 6.748, 0.002)
	assert_almost_eq(curve[10].x, 7.2, 0.0001)
	assert_almost_eq(curve[10].y, 0.0, 0.0001)
