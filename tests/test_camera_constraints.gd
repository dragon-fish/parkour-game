extends ParkourTest

func _rig() -> CameraRig:
	var scene: PackedScene = load("res://scenes/player/player.tscn")
	var player: Player = scene.instantiate()
	get_tree().root.add_child(player)
	var config := MovementConfig.new()
	player.setup(config, ScriptedInputSource.new())
	player.camera_rig.setup(config)
	return player.camera_rig

func test_an_unconstrained_move_uses_the_default_pitch_limit() -> void:
	var rig := _rig()
	await step(1)
	rig.clear_look_constraint()
	for i in 200:
		rig.apply_look(Vector2(0.0, -100.0), rig.get_parent())
	assert_true(rig.rotation.x <= deg_to_rad(89.1), "pitch escaped the default limit")
	assert_gt(rig.rotation.x, deg_to_rad(88.0), "pitch did not reach the default limit")
	rig.get_parent().queue_free()
	await step(1)

func test_a_constrained_move_clamps_pitch_harder() -> void:
	# WallRun clamps to +-71.4 degrees, which is where "you cannot look back
	# while on a wall" comes from -- an input constraint, not an animation.
	var rig := _rig()
	await step(1)
	rig.set_look_constraint(Vector3(-deg_to_rad(71.4), -PI, -PI), \
		Vector3(deg_to_rad(71.4), PI, PI), false)
	for i in 200:
		rig.apply_look(Vector2(0.0, -100.0), rig.get_parent())
	assert_true(rig.rotation.x <= deg_to_rad(71.5), "pitch escaped the move's own limit")
	assert_gt(rig.rotation.x, deg_to_rad(70.0), "pitch did not reach the move's own limit")
	rig.get_parent().queue_free()
	await step(1)

func test_leaving_a_constrained_move_restores_the_default_limit() -> void:
	var rig := _rig()
	await step(1)
	rig.set_look_constraint(Vector3(-deg_to_rad(20.0), -PI, -PI), \
		Vector3(deg_to_rad(20.0), PI, PI), false)
	for i in 100:
		rig.apply_look(Vector2(0.0, -100.0), rig.get_parent())
	rig.clear_look_constraint()
	for i in 200:
		rig.apply_look(Vector2(0.0, -100.0), rig.get_parent())
	assert_gt(rig.rotation.x, deg_to_rad(80.0), "the clamp stayed applied after clearing")
	rig.get_parent().queue_free()
	await step(1)

func test_a_left_wall_rolls_the_camera_clockwise() -> void:
	# OWNER-REPORTED, and the reason this changes: the previous code
	# deliberately rolled the view TOWARD the wall (its own comment and its
	# archived test both said so), which reads as backwards in play.
	# Clockwise from the player's own viewpoint is a NEGATIVE rotation.z --
	# positive z takes +X toward +Y, i.e. counter-clockwise when viewed from
	# behind the camera.
	var rig := _rig()
	await step(1)
	rig.set_wall_side(-1)
	for i in 60:
		rig.update_effects(1.0 / 60.0, 5.0, false)
	assert_true(rig.rotation.z < -0.01, "a left wall did not roll the camera clockwise")
	rig.get_parent().queue_free()
	await step(1)

func test_the_two_wall_sides_roll_opposite_ways() -> void:
	var rig := _rig()
	await step(1)
	rig.set_wall_side(-1)
	for i in 60:
		rig.update_effects(1.0 / 60.0, 5.0, false)
	var left := rig.rotation.z
	rig.set_wall_side(1)
	for i in 120:
		rig.update_effects(1.0 / 60.0, 5.0, false)
	var right := rig.rotation.z
	assert_true(left * right < 0.0, "the two wall sides rolled the same way")
	rig.get_parent().queue_free()
	await step(1)

func test_entering_the_landing_lockout_does_not_snap_the_pitch() -> void:
	# B2 REGRESSION. LandingConfig used to clamp PITCH to +-0.2 as well as yaw,
	# and unlike yaw the pitch half of a look constraint is genuinely absolute
	# (apply_look() folds it into the global limit with maxf/minf) while
	# CameraRig._pitch is never eased into a new range on entry. A player
	# looking down the drop they are about to land badly from -- exactly the
	# player this move exists for -- had the view SNAP up to -0.2 rad on the
	# lockout's first tick, and LandingMove's own downward sink then played out
	# from that jumped-to position instead of from where they were looking.
	#
	# Reads the SHIPPED LandingConfig rather than literals, so it is the real
	# constraint under test. Verified to go red with min/max_look_constraint.x
	# put back to -+0.2: the pitch jumps by ~1.35 rad on the first call.
	var rig := _rig()
	await step(1)
	var landing: LandingConfig = MovementConfig.new().landing

	# Look steeply down first, with no constraint in force -- the fall this
	# lockout follows.
	rig.clear_look_constraint()
	for i in 200:
		rig.apply_look(Vector2(0.0, 100.0), rig.get_parent())
	var before: float = rig.rotation.x
	assert_true(before < -deg_to_rad(80.0), \
		"test setup is wrong: the view is not steeply enough down (%f rad)" % before)

	rig.set_look_constraint(landing.min_look_constraint, landing.max_look_constraint, \
		landing.absolute_yaw_constraint)
	# A single tick with NO further look input: any movement at all here is the
	# constraint itself yanking the view, not the player.
	rig.apply_look(Vector2.ZERO, rig.get_parent())
	assert_almost_eq(rig.rotation.x, before, 0.0001, \
		"entering the landing lockout snapped the view pitch")

	rig.get_parent().queue_free()
	await step(1)

func test_the_landing_sink_cannot_push_the_view_past_vertical() -> void:
	# The other half of B2. Widening Landing's pitch clamp to the global limit
	# left the COMBINED angle -- _pitch minus LandingMove's downward sink --
	# unbounded, because apply_look() only ever clamped _pitch on its own. A
	# player already looking almost straight down when they land, which is the
	# natural thing to be doing at the end of the drop this move exists for,
	# had the sink carry the view past vertical and roll the horizon over for
	# the whole two-second lockout.
	#
	# Verified to go red without the clamp in update_effects(): rotation.x
	# reaches about -1.90 rad, roughly 20 degrees beyond straight down.
	var rig := _rig()
	await step(1)
	var landing: LandingConfig = MovementConfig.new().landing
	var limit := deg_to_rad(89.0)

	rig.clear_look_constraint()
	for i in 200:
		rig.apply_look(Vector2(0.0, 100.0), rig.get_parent())
	rig.set_look_constraint(landing.min_look_constraint, landing.max_look_constraint, \
		landing.absolute_yaw_constraint)

	# The deepest sink LandingMove ever asks for, at severity 1.0.
	rig.set_landing_pitch_offset(landing.camera_pitch_offset)
	rig.update_effects(1.0 / 60.0, 0.0, true)
	assert_true(absf(rig.rotation.x) <= limit + 0.0001, \
		"the landing sink pushed the view past vertical (%f rad)" % rig.rotation.x)

	rig.get_parent().queue_free()
	await step(1)

func test_the_eye_eases_over_a_sudden_step_instead_of_jumping_with_it() -> void:
	# try_step_up() moves the body in jumps, and between them move_and_slide()
	# and the floor snap pull it back down -- so a stair is climbed as a rapid
	# series of ups and downs. An offset pushed once per step-up only knows
	# about the ups, and the camera shook its way up every staircase.
	#
	# The eye follows the body's HEIGHT instead, which is indifferent to how
	# jagged the body's path is.
	var rig := _rig()
	await step(1)
	var body := rig.get_parent() as Node3D
	var cfg := MovementConfig.new()
	var delta := 1.0 / 60.0

	# Settle, so the eye is sitting exactly on the body's height.
	for i in 30:
		rig.update_effects(delta, 0.0, true)
	var eye_before: float = body.global_position.y + rig.position.y

	# One stair, applied to the body in a single frame the way a step-up does.
	body.global_position.y += 0.3
	rig.update_effects(delta, 0.0, true)
	var eye_after: float = body.global_position.y + rig.position.y
	assert_true(eye_after - eye_before < 0.1, 		"the eye jumped %.3f m with the body instead of easing" % (eye_after - eye_before))

	# ...and catches up shortly afterwards rather than lagging forever.
	for i in 60:
		rig.update_effects(delta, 0.0, true)
	var eye_settled: float = body.global_position.y + rig.position.y
	assert_almost_eq(eye_settled - eye_before, 0.3, 0.02, 		"the eye never caught up with the body after the step")

	rig.get_parent().queue_free()
	await step(1)

func test_a_fall_is_not_smoothed() -> void:
	# The same follow must NOT soften a real drop: watching the ground come up
	# is the point of falling, and a camera that lags behind the body would
	# take the speed out of it.
	var rig := _rig()
	await step(1)
	var body := rig.get_parent() as Node3D
	var delta := 1.0 / 60.0
	for i in 30:
		rig.update_effects(delta, 0.0, true)
	var eye_before: float = body.global_position.y + rig.position.y

	body.global_position.y -= 2.0
	rig.update_effects(delta, 0.0, false)   # airborne
	var eye_after: float = body.global_position.y + rig.position.y
	assert_almost_eq(eye_before - eye_after, 2.0, 0.01, 		"a 2 m drop was smoothed away by the step follow")

	rig.get_parent().queue_free()
	await step(1)

func test_a_fast_flick_cannot_walk_through_an_absolute_yaw_fan() -> void:
	# Reported from play while hanging: swing the mouse hard enough and the
	# view turns a full circle, straight through a 170 degree fan.
	#
	# The relative angle used to be re-derived each frame and wrapped into
	# [-PI, PI]. Swing 200 degrees in one tick and the wrap reports -160 --
	# inside the fan -- so the clamp passes it. The faster the mouse, the
	# easier the fence is to climb. Accumulating the total cannot be fooled
	# that way.
	var rig := _rig()
	await step(1)
	var body := rig.get_parent() as Node3D
	var cfg := MovementConfig.new()

	var fan := deg_to_rad(170.0)
	rig.set_look_constraint(Vector3(-PI, -fan, -PI), Vector3(PI, fan, PI), true)
	var start_yaw: float = body.rotation.y

	# What breaks is the PATH, not the final position: the clamp keeps the
	# result inside the fan either way. Under the wrap, a flick past the far
	# edge reappears at the near one, so repeated flicks the SAME way round
	# jump back and forth across the fan -- which is what reads as spinning
	# freely. Pinned at the edge, repeating the input changes nothing.
	# 175 degrees per flick, just past the 170 degree fan. Sized exactly,
	# because the failure needs the wrapped total to land back INSIDE the fan:
	# the first flick clamps to +170, the second reaches 345 and wraps to -15,
	# and the view has jumped clean across. Anything much larger wraps to a
	# value outside the fan again and clamps to the same edge by luck.
	var per_flick: float = deg_to_rad(175.0) / cfg.camera.mouse_sensitivity
	rig.apply_look(Vector2(-per_flick, 0.0), body)
	var settled: float = body.rotation.y
	assert_almost_eq(settled - start_yaw, fan, 0.001, \
		"test setup is wrong: the first flick did not park at the fan edge")
	rig.apply_look(Vector2(-per_flick, 0.0), body)
	assert_almost_eq(body.rotation.y, settled, 0.0001, \
		"another flick the same way jumped the view across the fan (%.1f -> %.1f degrees)" \
			% [rad_to_deg(settled - start_yaw), rad_to_deg(body.rotation.y - start_yaw)])

	var turned: float = absf(body.rotation.y - start_yaw)
	assert_true(turned <= fan + 0.01, \
		"the view ended %.1f degrees round a %.1f degree fan" \
			% [rad_to_deg(turned), rad_to_deg(fan)])

	rig.get_parent().queue_free()
	await step(1)

func _hanging_rig() -> Array:
	# A rig wearing the hang's own clamp, so these test the shipped values
	# rather than literals.
	var rig := _rig()
	await step(1)
	var grab: GrabConfig = MovementConfig.new().grab
	rig.set_look_constraint(grab.min_look_constraint, grab.max_look_constraint, \
		grab.absolute_yaw_constraint, grab.pitch_relaxes_with_yaw, \
		grab.pitch_min_turned_away, grab.pitch_relax_yaw_threshold, \
		grab.pitch_recover_speed)
	return [rig, rig.get_parent() as Node3D, grab]

func test_a_two_handed_hang_cannot_look_down() -> void:
	# Facing the wall, both hands are on the ledge and there is nothing below
	# to look at. The floor holds until the player has turned far enough to be
	# holding on with one hand.
	var parts: Array = await _hanging_rig()
	var rig: CameraRig = parts[0]
	var body: Node3D = parts[1]
	var delta := 1.0 / 60.0

	for i in 60:
		rig.apply_look(Vector2(0.0, 100.0), body, delta)   # drag the view down
	assert_almost_eq(rig.rotation.x, 0.0, 0.01, \
		"a two-handed hang looked down (%.1f degrees)" % rad_to_deg(rig.rotation.x))

	rig.get_parent().queue_free()
	await step(1)

func test_turning_past_the_threshold_lets_the_view_look_down() -> void:
	# Turned far enough round, the hold is one-handed and the drop below is
	# what the player needs to see before letting go.
	var parts: Array = await _hanging_rig()
	var rig: CameraRig = parts[0]
	var body: Node3D = parts[1]
	var grab: GrabConfig = parts[2]
	var delta := 1.0 / 60.0

	# Turn to the far edge of the fan, well past the 90 degree threshold.
	for i in 60:
		rig.apply_look(Vector2(-200.0, 0.0), body, delta)
	for i in 60:
		rig.apply_look(Vector2(0.0, 100.0), body, delta)
	assert_true(rig.rotation.x < -deg_to_rad(30.0), \
		"turned fully away, the view still could not look down (%.1f degrees)" \
			% rad_to_deg(rig.rotation.x))

	rig.get_parent().queue_free()
	await step(1)

func test_turning_back_pushes_the_view_up_rather_than_snapping_it() -> void:
	# The floor rises out from under a view that is already below it. Clamping
	# would put the view at level in a single frame; it should be pushed.
	var parts: Array = await _hanging_rig()
	var rig: CameraRig = parts[0]
	var body: Node3D = parts[1]
	var grab: GrabConfig = parts[2]
	var delta := 1.0 / 60.0

	for i in 60:
		rig.apply_look(Vector2(-200.0, 0.0), body, delta)
	for i in 60:
		rig.apply_look(Vector2(0.0, 100.0), body, delta)
	var looked_down: float = rig.rotation.x
	assert_true(looked_down < -deg_to_rad(30.0), "test setup: never looked down")

	# Turn back toward the wall in ONE tick, so the floor jumps up under the
	# view. Sized off the SHIPPED threshold so it lands inside it: turning back
	# only part of the way leaves the view still past the switch, where the
	# floor has not risen and there is nothing to test.
	var sens: float = MovementConfig.new().camera.mouse_sensitivity
	var back: float = deg_to_rad(170.0) - grab.pitch_relax_yaw_threshold + deg_to_rad(20.0)
	# yaw_delta is -look_delta.x * sensitivity, so a POSITIVE x turns back.
	rig.apply_look(Vector2(back / sens, 0.0), body, delta)
	assert_true(rig.rotation.x < looked_down + deg_to_rad(20.0), \
		"the view snapped back up instead of being pushed (%.1f -> %.1f degrees)" \
			% [rad_to_deg(looked_down), rad_to_deg(rig.rotation.x)])

	# ...and does get there, given a moment.
	for i in 60:
		rig.apply_look(Vector2.ZERO, body, delta)
	assert_almost_eq(rig.rotation.x, 0.0, 0.02, \
		"the view never came back up to level (%.1f degrees)" % rad_to_deg(rig.rotation.x))

	rig.get_parent().queue_free()
	await step(1)

# --- a scripted turn is always ridden ------------------------------------------

func test_a_corner_never_leaves_the_view_behind_the_body() -> void:
	# 📌 TWO ATTEMPTS AT AN EXCEPTION FOR THIRD PERSON ENDED HERE, and the second
	# one worked exactly as designed. Holding the camera still through a
	# ninety-degree ledge corner is unplayable anyway:
	#
	# ✅ The owner, after playing it: "还是得让视角跟着转角转，否则几乎总是会触发超过
	# 45° 锁定横爬，会让玩家困惑."
	#
	# The player steers the BODY with the camera. A view left a quarter-turn off
	# the wall means their next mouse movement turns the body away from it --
	# straight into the one-handed lock, which refuses the shimmy they were
	# trying to continue. The eye's facing during a hang is an INPUT to the move,
	# not a viewing preference, and that is the thing this pins.
	for third in [true, false]:
		var rig := _rig()
		rig.third_person = third
		rig.absorb_body_yaw(deg_to_rad(90.0))
		assert_almost_eq(absf(rig._scripted_yaw_lag),
			rig._config.camera.scripted_yaw_max_lag, 0.01,
			"third_person=%s absorbed %.2f rad of a corner"
			% [third, absf(rig._scripted_yaw_lag)])

# --- balance lean: roll and FOV squeeze ---------------------------------------

func test_third_person_softens_the_balance_roll() -> void:
	# The horizon tipping IS the feedback in first person -- outside the body,
	# the same roll tips the whole world around a character who is already
	# visibly leaning, which reads as nausea rather than information.
	var rig := _rig()
	await step(1)
	rig.set_balance_lean(deg_to_rad(12.0), 0.0)
	for i in 10:
		rig.update_effects(1.0 / 60.0, 0.0, true)
	var first_person_roll := absf(rig.rotation.z)

	rig.third_person = true
	for i in 10:
		rig.update_effects(1.0 / 60.0, 0.0, true)
	var third_person_roll := absf(rig.rotation.z)

	assert_lt(third_person_roll, first_person_roll,
		"an outside view tilting with the body is nauseating, not informative")
	# A scale accidentally left at 0.0 would also satisfy the comparison above
	# by deleting the third-person cue outright -- pin that some roll survives.
	assert_gt(third_person_roll, 0.0,
		"third person lost the balance roll entirely rather than softening it")
	rig.get_parent().queue_free()
	await step(1)

func test_the_squeeze_closes_the_fov_rather_than_opening_it() -> void:
	# The speed-driven FOV opens the view as horizontal speed rises; the balance
	# squeeze must close it instead, or fear-of-heights tension would read as
	# the opposite of what it is meant to.
	var rig := _rig()
	await step(1)
	rig.set_balance_lean(0.0, 0.0)
	for i in 10:
		rig.update_effects(1.0 / 60.0, 0.0, true)
	var calm := rig.camera.fov

	rig.set_balance_lean(0.0, 10.0)
	for i in 10:
		rig.update_effects(1.0 / 60.0, 0.0, true)
	assert_lt(rig.camera.fov, calm,
		"the speed-driven FOV opens with speed; this must close against it")
	rig.get_parent().queue_free()
	await step(1)

func test_a_sustained_lean_settles_instead_of_walking_past_the_camera_floor() -> void:
	# REGRESSION: subtracting the squeeze into the same field the speed lerp
	# reads back next frame compounds every tick it stays applied: held across
	# many ticks it converges toward speed_fov - squeeze/lerp_rate -- with the
	# shipped fov_lerp_speed, past Camera3D's 1-degree floor, where set_fov()
	# silently rejects the write. The squeeze must settle at a bounded offset
	# from the speed-driven value instead.
	var rig := _rig()
	await step(1)
	var squeeze_deg: float = BalanceConfig.new().fov_squeeze_deg
	rig.set_balance_lean(0.0, 0.0)
	for i in 10:
		rig.update_effects(1.0 / 60.0, 0.0, true)
	var speed_fov := rig.camera.fov

	rig.set_balance_lean(0.0, squeeze_deg)
	for i in 120:
		rig.update_effects(1.0 / 60.0, 0.0, true)
	assert_almost_eq(rig.camera.fov, speed_fov - squeeze_deg, 0.5,
		"a sustained lean drove the FOV past the intended squeeze depth")
	rig.get_parent().queue_free()
	await step(1)
