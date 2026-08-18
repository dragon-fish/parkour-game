class_name TestAcceptanceChecklist
extends TestCase

# The research's own checklist (10 §10.4), reduced to what a headless test can
# actually decide. Whether it FEELS right is not in here and cannot be.

func test_1_top_speed_needs_more_than_five_seconds_of_running() -> void:
	var pawn := PawnConfig.new()
	var energy := SpeedEnergy.new(pawn)
	for i in 300:
		energy.accumulate(1.0 / 60.0, SpeedEnergy.SPRINT)
	check(energy.cap() < pawn.ground_speed - 0.05, \
		"five seconds of running already reached top speed")

func test_2_air_speed_is_effectively_uncapped_and_air_control_is_tiny() -> void:
	var pawn := PawnConfig.new()
	check_greater(pawn.air_speed, pawn.ground_speed * 3.0, "air speed is capped near ground speed")
	check(pawn.accel_rate * pawn.air_control < 2.0, "air control is not almost nothing")

func test_3_turning_has_a_continuous_cost() -> void:
	var pawn := PawnConfig.new()
	var energy := SpeedEnergy.new(pawn)
	energy.energy = 7.0
	energy.spend_turn(deg_to_rad(5.0))
	check(energy.energy < 7.0, "a small turn was free")

func test_5_a_key_move_spans_at_least_three_times() -> void:
	var cfg := MovementConfig.new().wallrun_jump
	var worst := cfg.wall_running_push_away_speed_noob
	var best := worst + cfg.wall_running_push_away_speed_pro_add
	check_greater(best / worst, 3.0, "no key move has a 3x execution gradient")

func test_6_landing_is_judged_on_a_resettable_counter() -> void:
	var tracker := FallTracker.new()
	tracker.reset(10.0)
	tracker.update(1.0 / 60.0, -5.0, 10.0)
	tracker.update(1.0 / 60.0, -5.0, 6.0)
	check_greater(tracker.fall_height, 3.0, "the counter did not measure the drop")
	tracker.reset(6.0)
	check_approx(tracker.fall_height, 0.0, 0.0001, "the counter is not resettable")

func test_8_moves_declare_their_own_camera_constraints() -> void:
	var config := MovementConfig.new()
	check(config.wall_run.constrain_look, "wall running declares no look constraint")
	check(config.slide.constrain_look, "sliding declares no look constraint")
	check(not config.walking.constrain_look, "walking wrongly constrains the look")

func test_10_a_flat_jump_hangs_for_about_four_fifths_of_a_second() -> void:
	# Repinned from 1.40 s. That figure came from the CONFIGURED gravity (800)
	# and TdPawn's BaseJumpZ (560); frame-level measurement of 22 jumps puts the
	# effective pair at (1600, 630), giving 0.7875 s. See 02 §2.4.
	var pawn := PawnConfig.new()
	var hang: float = 2.0 * pawn.base_jump_z / pawn.gravity
	check_approx(hang, 0.7875, 0.02, "flat-jump hang time is not the measured 0.79 s")
	var apex: float = pawn.base_jump_z * pawn.base_jump_z / (2.0 * pawn.gravity)
	check(apex < pawn.skill_roll_landing_height, \
		"the jump apex reaches the roll threshold, so every jump costs speed")

## The BEHAVIOURAL half of test_8 above, and the one branch where the whole
## point of an ABSOLUTE yaw constraint shows up. tests/test_camera_constraints.gd
## covers the pitch clamp thoroughly but never drives the yaw fan, and a pitch
## test cannot see this bug at all: with a RELATIVE reference (the body's own
## current yaw, re-read every call) the clamp still clamps -- each individual
## step is inside the fan -- so the view simply walks the fan along with the
## player and ends up facing anywhere at all. Asserting merely "it stopped
## somewhere" would pass against exactly that.
##
## So this drives the yaw well PAST the fan edge in one direction and asserts
## the body ends up at the edge measured from the facing captured AT CONSTRAINT
## TIME (04 §4.1 bUseAbsoluteYawConstraint = True) -- not 90 degrees past
## wherever it drifted to.
func test_8b_an_absolute_yaw_fan_stays_pinned_to_the_facing_the_move_began_with() -> void:
	var scene: PackedScene = load("res://scenes/player/player.tscn")
	var player: Player = scene.instantiate()
	tree.root.add_child(player)
	var config := MovementConfig.new()
	player.setup(config, ScriptedInputSource.new())
	var rig: CameraRig = player.camera_rig
	rig.setup(config)
	await step(1)

	# A deliberately non-zero starting facing, so "pinned to the reference"
	# and "pinned to zero" cannot look the same.
	var reference := deg_to_rad(30.0)
	player.rotation.y = reference
	rig.set_look_constraint(Vector3(-PI, -deg_to_rad(90.0), -PI), \
		Vector3(PI, deg_to_rad(90.0), PI), true)

	# Same-direction yaw input, well past the fan: 400 calls at this delta is
	# several full turns' worth of mouse movement, so nothing here depends on
	# the exact sensitivity.
	for i in 400:
		rig.apply_look(Vector2(-100.0, 0.0), player)

	# -look_delta.x * sensitivity, so a NEGATIVE look_delta.x yaws POSITIVE:
	# the body should sit exactly at reference + 90 degrees.
	var expected := reference + deg_to_rad(90.0)
	check_approx(player.rotation.y, expected, 0.001, \
		"the absolute yaw fan did not stop at 90 degrees from the facing captured when the constraint began")

	# And the same in the other direction, from the SAME reference -- a fan
	# that drifted would put this edge somewhere else entirely.
	for i in 800:
		rig.apply_look(Vector2(100.0, 0.0), player)
	check_approx(player.rotation.y, reference - deg_to_rad(90.0), 0.001, \
		"the far edge of the fan is not symmetric about the captured facing")

	player.queue_free()
	await step(1)
