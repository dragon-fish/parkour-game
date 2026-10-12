extends ParkourTest

# PawnPhysics' pure functions are verbatim ports of native code. These cases
# are the outputs of the Python references that were checked case by case
# against the ORIGINAL MACHINE CODE under Ghidra's emulator
# (_local/me-re/verify/N1-ground_ref.py, N2-air_ref.py: 975 and 400 cases, no
# mismatch), on random inputs, converted to metres with UE's (x, y, z) as
# Godot's (x, z, y). A mismatch means the port no longer computes what the
# original computes -- not that a value needs re-tuning.

## The references round every operation to float32; the port computes in
## double. This is a few float32 ulps at these magnitudes.
const TOLERANCE := 0.0005

# walk_friction_modifier: [velocity, floor_normal, sliding, friction_modifier, expected]
const WALK_FRICTION_CASES := [
	[Vector3(-5.344860255419651, 0.0, 3.552865425208797), Vector3(-0.0, 1.0, -0.0), false, 0.15, 0.4],
	[Vector3(-3.69576900711339, 0.0, -6.603918993920555), Vector3(0.0, 1.0, 0.0), false, 0.15, 0.4],
	[Vector3(0.5390767390654458, 0.0, 5.026027636823771), Vector3(-0.5834779219285372, 0.7752543416347992, 0.24193846407371833), false, 0.15, 0.4],
	[Vector3(4.9184463849765745, 0.0, 5.092413122126161), Vector3(-0.43956703966345473, 0.7984657638885653, -0.41137968051346036), true, 0.1, 0.4006364941596985],
	[Vector3(-0.3564869614912813, 0.0, -1.1579437206580956), Vector3(-0.3031584922189797, 0.9480874559216381, -0.09604740766699893), false, 0.1, 0.4],
	[Vector3(4.584866918286624, 0.0, 2.2211718051072733), Vector3(-0.0, 1.0, 0.0), false, 0.15, 0.4],
	[Vector3(-3.5224571709777224, 0.0, -0.6368101079638646), Vector3(-0.0, 1.0, 0.0), false, 0.15, 0.4],
	[Vector3(3.3925959762936704, 0.0, 0.8795428138288981), Vector3(0.0, 1.0, 0.0), true, 1.0, 1.0],
	[Vector3(0.43157601491745723, 0.0, -0.8528664459697636), Vector3(-0.0, 1.0, -0.0), false, 1.0, 1.0],
	[Vector3(-4.010241218037298, 0.0, 6.013882317027988), Vector3(-0.16619616652429967, 0.985931870226676, 0.017809590224258508), false, 1.0, 0.91438227891922],
	[Vector3(-2.6807762623646876, 0.0, -2.0625938178874703), Vector3(0.0, 1.0, 0.0), false, 1.0, 1.0],
	[Vector3(1.548625831390416, 0.0, -0.1837322508725528), Vector3(0.36654414031360416, 0.9287633228192794, 0.05517321258955142), true, 1.0, 0.3565160632133484],
]
# calc_velocity: [velocity, acceleration, dt, friction, mobility, precise, expected_v, expected_a]
const CALC_VELOCITY_CASES := [
	[Vector3(0.6615146376088846, 0.0, 3.7641285259536943), Vector3(0.0, 0.0, 0.0), 0.016666666666666666, 8.0, 1.0, false, Vector3(0.5733126831054688, 0.0, 3.262244873046875), Vector3(0.0, 0.0, 0.0)],
	[Vector3(0.45613925701235203, 0.0, -1.4264816173690837), Vector3(54.16755617729664, 0.0, 62.57927522532106), 0.06355432981031243, 8.0, 1.0, false, Vector3(2.9884783935546877, 0.0, 1.598426971435547), Vector3(40.21017578125, 0.0, 46.4544482421875)],
	[Vector3(-3.9640003603861027, 0.0, -3.567192301093206), Vector3(34.566240316305795, 0.0, 65.72565573992705), 0.02141621450982409, 8.0, 0.2, false, Vector3(-1.087804718017578, 0.0, -0.9435467529296875), Vector3(5.719696044921875, 0.0, 10.87566162109375)],
	[Vector3(1.7961469025497823, 0.0, 0.014239545563801094), Vector3(0.0, 0.0, 0.0), 0.03333333333333333, 16.0, 0.6, false, Vector3(0.9290151214599609, 0.0, 0.007365072369575501), Vector3(0.0, 0.0, 0.0)],
	[Vector3(1.1209808307406586, 0.0, -2.697200726421032), Vector3(-1.077987865555034, 0.0, -85.9596156517333), 0.016666666666666666, 3.2, 1.0, false, Vector3(1.1021617126464844, 0.0, -3.7067352294921876), Vector3(-0.770435791015625, 0.0, -61.4351708984375)],
	[Vector3(-3.5604219734463296, 0.0, -7.322484877663258), Vector3(2.268802645281523, 0.0, 4.142518406246404), 0.016666666666666666, 16.0, 1.0, false, Vector3(-3.1452679443359375, 0.0, -6.47667236328125), Vector3(2.268802645281523, 0.0, 4.142518406246404)],
	[Vector3(1.8112174733395814, 0.0, 1.2886587033335617), Vector3(0.0, 0.0, 0.0), 0.016666666666666666, 1.04, 1.0, false, Vector3(1.779822998046875, 0.0, 1.2663219451904297), Vector3(0.0, 0.0, 0.0)],
	[Vector3(2.284868184981182, 0.0, -3.432622854585389), Vector3(-50.81834659072554, 0.0, -48.16971164695382), 0.016666666666666666, 3.2, 0.6, false, Vector3(1.826770935058594, 0.0, -3.836986083984375), Vector3(-26.75468017578125, 0.0, -25.360234375)],
	[Vector3(-2.3314067011728357, 0.0, -0.9075010195503941), Vector3(-88.76430932631094, 0.0, -6.946651225375016), 0.05, 1.04, 1.0, false, Vector3(-5.3819189453125, 0.0, -1.1424623107910157), Vector3(-61.25271484375, 0.0, -4.793607177734375)],
	[Vector3(4.293664876995457, 0.0, -6.681134777396304), Vector3(0.0, 0.0, 0.0), 0.016666666666666666, 8.0, 1.0, false, Vector3(3.7211761474609375, 0.0, -5.790316772460938), Vector3(0.0, 0.0, 0.0)],
	[Vector3(-0.8547603701476629, 0.0, -1.1167564025868424), Vector3(-47.81265077538858, 0.0, 23.334912971652653), 0.05, 8.0, 0.2, false, Vector3(-1.2431092834472657, 0.0, -0.7268281555175782), Vector3(-11.04300537109375, 0.0, 5.3895263671875)],
	[Vector3(-0.7067753787423743, 0.0, 6.547027710698851), Vector3(2.3256152130745833, 0.0, 1.0744613841601538), 0.027772369123748825, 1.04, 0.2, false, Vector3(-0.13989871025085449, 0.0, 1.4331881713867187), Vector3(2.3256152130745833, 0.0, 1.0744613841601538)],
	[Vector3(-0.10645789825172766, 0.0, -2.3965201447383415), Vector3(0.0, 0.0, 0.0), 0.009832074673672647, 3.2, 0.6, false, Vector3(-0.10310845375061035, 0.0, -2.321119079589844), Vector3(0.0, 0.0, 0.0)],
	[Vector3(-3.6019428324249856, 0.0, 2.52165656813939), Vector3(-54.777813392806905, 0.0, -29.68191134471799), 0.02548799786926754, 8.0, 1.0, true, Vector3(-4.998119506835938, 0.0, 1.7651239013671876), Vector3(-54.777813392806905, 0.0, -29.68191134471799)],
]
# falling_accel_bound: [velocity, acceleration, dt, expected]
const FALLING_BOUND_CASES := [
	[Vector3(2.6864514579612577, -0.3345803706790093, -3.0725978879383575), Vector3(4.937928628264514, -0.1768810793786423, 6.599986438200154), 0.016666666666666666, Vector3(0.9201609360524772, 0.0, 1.2298779824694115)],
	[Vector3(-7.985835967514224, -8.069478929372327, 8.558195989135662), Vector3(-0.7303043641558706, -2.1010612534108786, -14.505610934325068), 0.08524241472154924, Vector3(-0.0005028264941926702, 0.0, -0.009987350275059844)],
	[Vector3(-0.989620840071584, 0.09726043872047058, -0.16848960992188944), Vector3(-6.6810580605877545, -1.727906910233164, -11.969129754376212), 0.03333333333333333, Vector3(-0.7486468409508195, 0.0, -1.3412024110977283)],
	[Vector3(-9.661946504667107, 5.31587202999978, -2.8671951677983714), Vector3(2.086396139618148, -2.197885343938595, 1.2639384618769705), 0.062761301759623, Vector3(0.008552966725953964, 0.0, 0.0051813859328102875)],
	[Vector3(-0.0713539427229934, 1.0887500888761543, 0.023190153859876293), Vector3(10.166641733254718, -2.797426401566328, -2.7628914003086273), 0.028056555059657477, Vector3(2.341155356469336, 0.0, -0.6362334948833538)],
	[Vector3(-0.01240152321036229, -6.55642103740522, -0.017710899921336926), Vector3(7.801246972039201, 2.5908392595034253, -2.1259553589030746), 0.09928446804559439, Vector3(2.2436186983653448, 0.0, -0.6114193297841639)],
	[Vector3(-0.02821954744804733, -8.244921146840007, -0.009631190573557616), Vector3(-0.024773253884856693, 0.9969971162665945, -0.013631893444770185), 0.03333333333333333, Vector3(-0.024773253884856693, 0.0, -0.013631893444770185)],
	[Vector3(-7.654357625806438, 5.82198891551165, -0.3852054711295169), Vector3(6.753408133212397, 2.4780769397311597, -4.038090207597887), 0.03333333333333333, Vector3(0.008582743454895693, 0.0, -0.00513191141656256)],
	[Vector3(2.009712045121527, -6.0036724072406775, 11.463815471380519), Vector3(-0.2593006334319163, 1.3041879273627297, 13.393358868939636), 0.01230349968131674, Vector3(-0.00019356761324120585, 0.0, 0.009998126403437)],
	[Vector3(-0.022877857862005056, 1.6695426502750979, -0.03204663095577444), Vector3(-2.688346263145744, -1.4912093910812363, 8.06801684274554), 0.016666666666666666, Vector3(-1.6354626779975487, 0.0, 4.908199740730574)],
]
# compute_slide_vector: [delta, normal, time, expected]
const SLIDE_CASES := [
	[Vector3(-0.19761709693206073, -0.04024658762122556, 0.18495069854793664), Vector3(-0.47194077913864385, 0.0, 0.8816302518550562), 0.06691083336159019, Vector3(-0.07022840394898267, -0.0375536549035291, -0.04069739162264363)],
	[Vector3(0.17953526577571047, -0.18572422309793066, -0.0685406190352343), Vector3(0.6975614641505941, 0.0, -0.7165249498322298), 0.9032185248841801, Vector3(0.0037410242693896585, -0.017974664276157362, 0.007371865121484502)],
	[Vector3(-0.26340030033884726, 0.1322799620740709, -0.20485886720661525), Vector3(-0.47512537939644073, 0.04309600612595153, 0.8788621098382727), 0.7411482424320673, Vector3(-0.0759372903090872, 0.034240900673892724, -0.038682063757402164)],
	[Vector3(-0.1496348406422822, 0.16197457377405072, 0.0849154767112865), Vector3(-0.864577536104429, 0.43616872440582466, -0.24952460382453384), 0.8214250195629794, Vector3(0.0008889702797255834, 0.014995696659083457, 0.023132268565038323)],
	[Vector3(0.05243213147207811, -0.04750596449712838, -0.17798896040405474), Vector3(-0.13041325789688452, 0.3187262541341276, 0.9388322305344806), 0.05018519430760634, Vector3(0.026379643685826723, -0.045121868438069736, -0.00044984035737618465)],
	[Vector3(0.28729800898502833, -0.3803944609376429, 0.17458836498687738), Vector3(-0.9391598622465576, -0.2619540921121217, -0.22216841983221025), 0.9250674219906277, Vector3(0.006822635544227418, -0.03260560915938825, 0.009603647939011913)],
	[Vector3(-0.21883843285845436, -0.02558812674732437, -0.05154739544246173), Vector3(-0.8030248913140173, 0.0, 0.5959454873812794), 0.2076976015482169, Vector3(-0.07930610630760085, -0.02027353419379332, -0.11066040084555252)],
	[Vector3(0.23073998416854793, -0.33120872206257923, 0.025094261219492396), Vector3(0.9645716035371857, 0.0, 0.26382119257122255), 0.9339214783101742, Vector3(-0.0032618459749016887, -0.02188578272467161, -0.0034041743119975006)],
]

func test_walk_friction_modifier_matches_the_original() -> void:
	var p := PawnConfig.new()
	for c in WALK_FRICTION_CASES:
		var got: float = PawnPhysics.walk_friction_modifier(c[0], c[1], c[2], c[3], p)
		assert_almost_eq(got, float(c[4]), TOLERANCE, "walk friction for %s on %s" % [c[0], c[1]])

func test_calc_velocity_matches_the_original() -> void:
	var p := PawnConfig.new()
	for c in CALC_VELOCITY_CASES:
		var accel: Vector3 = c[1]
		var accel_dir: Vector3 = Vector3.ZERO if accel == Vector3.ZERO else accel.normalized()
		var r: Array = PawnPhysics.calc_velocity(c[0], accel, accel_dir, c[2], p.ground_speed, c[3],
			true, c[4], p.accel_rate, p.braking_friction_strength, false, c[5], false, Vector3.FORWARD)
		var v: Vector3 = r[0]
		var a: Vector3 = r[1]
		assert_true(v.distance_to(c[6]) < TOLERANCE, "velocity %s, wanted %s" % [v, c[6]])
		assert_true(a.distance_to(c[7]) < TOLERANCE, "acceleration %s, wanted %s" % [a, c[7]])

func test_falling_accel_bound_matches_the_original() -> void:
	var p := PawnConfig.new()
	for c in FALLING_BOUND_CASES:
		var got: Vector3 = PawnPhysics.falling_accel_bound(c[0], c[1], c[2], p.accel_rate,
			p.air_control, p.ground_speed)
		assert_true(got.distance_to(c[3]) < TOLERANCE, "bound %s, wanted %s" % [got, c[3]])

func test_compute_slide_vector_matches_the_original() -> void:
	for c in SLIDE_CASES:
		var got: Vector3 = PawnPhysics.compute_slide_vector(c[0], c[1], c[2])
		assert_true(got.distance_to(c[3]) < TOLERANCE * 0.01, "slide %s, wanted %s" % [got, c[3]])

## [ME:CONFIRMED emulated N1 §5.2] strict < at every threshold.
func test_walking_state_thresholds_are_strict() -> void:
	assert_eq(PawnPhysics.walking_state(0.0), PawnPhysics.WAS_IDLE)
	assert_eq(PawnPhysics.walking_state(0.05), PawnPhysics.WAS_SNEAK)
	assert_eq(PawnPhysics.walking_state(0.5), PawnPhysics.WAS_WALK)
	assert_eq(PawnPhysics.walking_state(2.6), PawnPhysics.WAS_JOG)
	assert_eq(PawnPhysics.walking_state(4.0), PawnPhysics.WAS_RUN)
	assert_eq(PawnPhysics.walking_state(6.3), PawnPhysics.WAS_SPRINT)
	assert_eq(PawnPhysics.walking_state(6.29), PawnPhysics.WAS_RUN)

## AActor::TwoWallAdjust: walls facing the same way slide along the second;
## walls facing each other send the body along their crease.
func test_two_wall_adjust_follows_the_crease() -> void:
	var desired := Vector3(0.0, 0.0, -1.0)
	var along: Vector3 = PawnPhysics.two_wall_adjust(desired, Vector3(0.3, 0.0, -1.0),
		Vector3(-1.0, 0.0, 0.0), Vector3(-0.6, 0.0, 0.8), 0.0)
	assert_almost_eq(along.x, 0.0, 1e-6, "slid into the second wall")
	assert_almost_eq(along.z, -1.0, 1e-6, "lost the motion along the second wall")
	var crease: Vector3 = PawnPhysics.two_wall_adjust(desired, Vector3(0.0, 0.0, -1.0),
		Vector3(0.7071, 0.0, 0.7071), Vector3(-0.7071, 0.0, 0.7071), 0.5)
	assert_almost_eq(crease.length(), 0.0, 1e-6, "walls meeting head on left motion along a horizontal crease")

## [ME:CONFIRMED decompile N2 §2, 0x0205684c] GPhysFallingDepth is held only
## while a falling move is under way: a frame of falling leaves it at rest.
func test_the_falling_depth_is_released_by_every_exit() -> void:
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(world)
	var player: Player = world["player"]
	player.global_position.y += 1.0
	player.move_manager.start(Move.FALLING)
	for i in 60:
		await step(1)
		assert_eq(player.phys._falling_depth, 0, "a falling move left its depth held")
	assert_eq(player.move_manager.current_name, Move.WALKING, "test setup: the fall never landed")
	TestWorld.teardown(world)
