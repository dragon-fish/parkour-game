class_name TestWallrunJump
extends TestCase

# The 4.3x skill gradient, tested as pure arithmetic. 04 §4.4 is explicit
# that the interpolation input is not named in the data; the reading here --
# how squarely the view faces the wall at the moment of the jump -- comes
# from the community's own repeated instruction to "face the wall you are
# running on before jumping", which is the behaviour the gradient has to
# reproduce.

const TestWorld = preload("res://tests/world_fixture.gd")

func _cfg() -> WallrunJumpConfig:
	return MovementConfig.new().wallrun_jump

func test_the_confirmed_endpoints_are_in_place() -> void:
	var cfg := _cfg()
	check_approx(cfg.wall_running_push_away_speed_noob, 1.2, 0.0001, "Noob endpoint is wrong")
	check_approx(cfg.wall_running_push_away_speed_pro_add, 4.0, 0.0001, "ProAdd endpoint is wrong")
	check_approx(cfg.wall_running_jump_off_z_height_forward, 1.0, 0.0001, "base rise height is wrong")
	check_approx(cfg.wall_running_jump_off_z_height_max_add_turned, 0.6, 0.0001, "rise bonus is wrong")

func test_the_worst_execution_gets_the_noob_push() -> void:
	# Looking straight AWAY from the wall.
	var normal := Vector3(1.0, 0.0, 0.0)
	var push := WallRunMove.wall_jump_push_away(normal, normal, _cfg())
	check_approx(push, 1.2, 0.001, "looking away from the wall did not give the Noob push")

func test_the_best_execution_gets_the_full_gradient() -> void:
	# Looking straight INTO the wall.
	var normal := Vector3(1.0, 0.0, 0.0)
	var push := WallRunMove.wall_jump_push_away(-normal, normal, _cfg())
	check_approx(push, 5.2, 0.001, "facing the wall did not give the full push")

func test_the_gradient_spans_more_than_four_times() -> void:
	# 10.1 mechanic 4 states the criterion as a ratio: a key move must have a
	# 3x-or-better spread between worst and best execution, or new players and
	# experts are playing the same game.
	var normal := Vector3(1.0, 0.0, 0.0)
	var worst := WallRunMove.wall_jump_push_away(normal, normal, _cfg())
	var best := WallRunMove.wall_jump_push_away(-normal, normal, _cfg())
	check_greater(best / worst, 4.0, "the gradient is narrower than 4x")

func test_the_gradient_is_continuous_not_stepped() -> void:
	var normal := Vector3(1.0, 0.0, 0.0)
	var previous := WallRunMove.wall_jump_push_away(normal, normal, _cfg())
	for i in range(1, 11):
		var angle: float = PI * float(i) / 10.0
		var look := normal.rotated(Vector3.UP, angle)
		var push := WallRunMove.wall_jump_push_away(look, normal, _cfg())
		check_greater(push + 0.0001, previous, "the gradient went backwards at step %d" % i)
		previous = push

func test_the_rise_is_a_height_converted_to_a_speed() -> void:
	# JumpOffZHeight is a HEIGHT in the original, not a velocity -- 1.0 m at
	# worst, 1.6 m at best. The speeds those correspond to depend on gravity,
	# so this reads gravity from the config rather than hard-coding it: pinning
	# the number instead of the RELATIONSHIP is what made this test fail when
	# gravity was corrected from 8.0 to the measured 16.0, even though the
	# behaviour under test never changed.
	var pawn := PawnConfig.new()
	var normal := Vector3(1.0, 0.0, 0.0)
	var worst := WallRunMove.wall_jump_rise_velocity(normal, normal, _cfg(), pawn)
	var best := WallRunMove.wall_jump_rise_velocity(-normal, normal, _cfg(), pawn)
	check_approx(worst, sqrt(2.0 * pawn.gravity * 1.0), 0.001, "worst-case rise is not 1.0 m worth")
	check_approx(best, sqrt(2.0 * pawn.gravity * 1.6), 0.001, "best-case rise is not 1.6 m worth")

## End-to-end regression guard for the gravity choice in
## wall_jump_rise_velocity(): every test above is pure arithmetic, calling
## the static functions directly -- nothing drives a live Player/WallRunMove
## through a real attach -> jump -> fall sequence under real physics. The
## PREVIOUS task in this batch shipped a gravity mismatch of exactly this
## shape (wall-run attach lift, wrong gravity scale); this is the same class
## of bug, just at the opposite end (this task's own code comment on
## wall_jump_rise_velocity() explains why PLAIN gravity is the right choice
## here, not wall_gravity_scale). Fixture pattern (wall pose, settle, lift,
## strafe-attach) mirrors tests/test_wall_run_entry.gd's own
## _attach_to_wall(), reproduced here rather than shared -- that helper lives
## on a sibling TestCase instance.
##
## Deliberately NOT the literal worst-execution endpoint (quality exactly 0,
## look == normal): confirmed directly while writing this test that a LIVE
## rotated player cannot reach it without also breaking the wall attachment
## needed to jump from at all. Probes is an UNROTATED child of the same body
## CameraRig.apply_look() turns directly (body.rotate_y()), so the wall-
## detection side rays (WallLeft/WallRight) are rigidly LOCAL to the
## player's own forward axis; their reach toward the wall's near face
## shrinks with cos(turn angle from the attach tangent) and hits exactly
## zero at quality's true 0/1 endpoints (a 90-degree turn) -- the same turn
## that would prove the extreme quality also switches off the very rays
## keeping the player on the wall, so consume_buffered_jump() never gets a
## tick to fire on. Tested instead at the UNROTATED heading (forward along
## the strafe-attach's own tangent), which is quality EXACTLY 0.5 by
## construction (forward ⊥ normal) -- height 1.3 m, ~4.5607 m/s -- still a
## real Player, real WallRunMove, real FallingMove gravity and the same
## config plumbing; only the specific point read off the gradient differs
## from what was asked, and expected values are computed by calling the SAME
## pure functions under test rather than hand-transcribed, so this proves
## the WIRING (right args, right gravity) rather than re-deriving the
## numbers.
func test_a_live_wall_jump_matches_the_gradient_functions_under_real_gravity() -> void:
	var cfg := MovementConfig.new()
	var world := TestWorld.build(tree, cfg)
	await step(1)
	TestWorld.place(world)
	await step(30)
	var player: Player = world["player"]
	check(player.move_manager.current_name == Move.WALKING, \
		"test setup is wrong: player did not settle onto the floor before the drop")

	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, 6.0, 1.0)
	shape.shape = box
	wall.add_child(shape)
	tree.root.add_child(wall)
	# Same pose test_wall_run_entry.gd's own fixture uses: near face at
	# x = 0.45 (thickness 1.0 halved from center 0.95), the midpoint of the
	# only window that both clears the capsule (radius 0.4) and stays inside
	# the probe's own reach (wall_running_forward_check_distance, 0.5).
	wall.global_position = Vector3(0.95, 3.0, 0.0)
	wall.rotation = Vector3(0.0, PI * 0.5, 0.0)

	player.global_position.y += 0.5
	await step(1)
	check(player.move_manager.current_name == Move.FALLING, \
		"test setup is wrong: the up-teleport did not send the player airborne")

	# Heading parallel to the wall's face -- a STRAFE-style approach, same as
	# _measure_wall_ticks()'s own entry.
	player.velocity = Vector3(0.0, player.velocity.y, -7.0)
	await step(1)
	check(player.move_manager.current_name == Move.WALL_RUN, \
		"test setup is wrong: the player never attached to the wall")

	var look: Vector3 = -player.global_transform.basis.z
	var normal := Vector3(-1.0, 0.0, 0.0)
	var expected_quality: float = WallRunMove.wall_jump_quality(look, normal)
	check_approx(expected_quality, 0.5, 0.0001, \
		"test setup is wrong: the unrotated attach heading is not the expected quality-0.5 point")
	var expected_launch: float = WallRunMove.wall_jump_rise_velocity(look, normal, cfg.wallrun_jump, cfg.pawn)
	var expected_height: float = cfg.wallrun_jump.wall_running_jump_off_z_height_forward \
		+ cfg.wallrun_jump.wall_running_jump_off_z_height_max_add_turned * expected_quality
	var jump_y: float = player.global_position.y

	world["input"].press_jump()
	await step(1)
	check(player.move_manager.current_name == Move.FALLING, \
		"the buffered jump did not fire the wall-jump branch")
	check_approx(player.velocity.y, expected_launch, 0.01, \
		"live launch speed does not match wall_jump_rise_velocity()'s own prediction (%f expected)" % expected_launch)

	# Track the apex across real, integrated physics ticks -- gravity applied
	# every tick by FallingMove, not the pure function's own single sqrt().
	var apex_y: float = jump_y
	for i in range(200):
		await step(1)
		apex_y = maxf(apex_y, player.global_position.y)
		if player.velocity.y < 0.0:
			break
	# Tolerance covers the integrator's own bias, not sloppiness. Semi-implicit
	# Euler applies a full tick of gravity before the position update, so a
	# discretely integrated arc overshoots the closed-form apex by roughly
	# v0 * dt / 2. At the measured gravity that is 6.45 / 120 = 0.054 m, which is
	# why 0.05 stopped passing the moment gravity was corrected from 8.0: launch
	# speed grows as sqrt(gravity), and so does this bias. 0.08 keeps ~50% headroom
	# over the computed bias without hiding a regression.
	var integrator_bias: float = expected_launch / (2.0 * Engine.physics_ticks_per_second)
	check_greater(0.08, integrator_bias, "integrator bias outgrew the tolerance")
	check_approx(apex_y - jump_y, expected_height, 0.08, \
		"the live wall jump's measured apex does not match the predicted %f m rise" % expected_height)

	wall.queue_free()
	TestWorld.teardown(world)
	await step(1)
