extends TestCase

## Builds a world with a box obstacle `depth` metres deep (default 1.0, matching
## the original brief geometry) and `height` metres tall, `distance`-ish ahead
## of the player, then arms sprint-forward input. `cfg` lets callers exercise a
## non-default MovementConfig (e.g. a loosened vault_max_height) without
## duplicating the whole setup.
func _running_at_obstacle(height: float, cfg: MovementConfig = null, depth: float = 1.0) -> Dictionary:
	if cfg == null:
		cfg = MovementConfig.new()
	var world := TestWorld.build(tree, cfg)
	await step(1)
	TestWorld.place(world)
	await step(15)

	var obstacle := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8.0, height, depth)
	shape.shape = box
	obstacle.add_child(shape)
	tree.root.add_child(obstacle)
	await step(1)
	obstacle.global_position = Vector3(0.0, height * 0.5, -8.0)
	await step(1)

	world["input"].state.move = Vector2(0.0, 1.0)
	world["input"].state.sprint_held = true
	world["obstacle"] = obstacle
	world["obstacle_depth"] = depth
	return world

func test_running_into_a_low_obstacle_vaults_it() -> void:
	await step(1)
	var world := await _running_at_obstacle(1.0)
	var player: Player = world["player"]

	var vaulted := false
	for i in 300:
		await step(1)
		if player.state_machine.current_name == &"Vault":
			vaulted = true
			break
	check(vaulted, "running into a waist-high obstacle should start a vault")

	world["obstacle"].queue_free()
	TestWorld.teardown(world)
	await step(1)

func test_a_vault_clears_the_obstacles_far_face() -> void:
	await step(1)
	var world := await _running_at_obstacle(1.0)
	var player: Player = world["player"]
	var obstacle: StaticBody3D = world["obstacle"]
	var depth: float = world["obstacle_depth"]

	for i in 400:
		await step(1)
		if player.state_machine.current_name == &"Vault":
			break
	for i in 400:
		await step(1)
		if player.state_machine.current_name != &"Vault":
			break

	# Let GroundState carry the player forward under its own momentum for a
	# beat after the hand-off. ScriptedMove's own arc only promises to land
	# somewhere "known-clear" (see its class comment) -- not already past the
	# obstacle's full footprint the instant the scripted portion ends, which,
	# measured immediately on hand-off, can still read a few tens of
	# centimetres short of the far face depending on exactly where the
	# approach happened to sample the obstacle's top. "The vault clears the
	# obstacle" is a claim about the completed manoeuvre, so give the
	# following run its due before judging it.
	await step(30)

	# The player runs toward -Z, so the obstacle's FAR face -- the one that
	# actually has to be cleared -- sits on the -Z side of its centre, at
	# centre.z - depth/2. Asserting against the centre (as this test used to)
	# passes even while the player is still standing on the obstacle's OWN top
	# surface, inside its footprint, on a margin as thin as the box is deep;
	# widening the box would silently break the intended behaviour without the
	# assertion ever noticing. Computed from `depth` rather than a literal so
	# it stays correct regardless of how deep the obstacle is.
	var far_face_z: float = obstacle.global_position.z - depth * 0.5
	check(player.global_position.z < far_face_z, \
		"the vault should leave the player past the obstacle's far face (z=%f), got z=%f" \
		% [far_face_z, player.global_position.z])

	obstacle.queue_free()
	TestWorld.teardown(world)
	await step(1)

func test_a_vault_keeps_most_of_the_approach_speed() -> void:
	await step(1)
	var world := await _running_at_obstacle(1.0)
	var player: Player = world["player"]

	var approach := 0.0
	for i in 400:
		await step(1)
		if player.state_machine.current_name == &"Vault":
			break
		approach = player.horizontal_speed()
	for i in 400:
		await step(1)
		if player.state_machine.current_name != &"Vault":
			break

	# Vaulting is a shortcut, not a speed bump — it must not cost more than a
	# plain landing would.
	check_greater(player.horizontal_speed(), approach * 0.5, \
		"vaulting bled too much speed (%f from %f)" % [player.horizontal_speed(), approach])

	world["obstacle"].queue_free()
	TestWorld.teardown(world)
	await step(1)

func test_a_wall_is_not_vaulted() -> void:
	await step(1)
	var world := await _running_at_obstacle(3.0)
	var player: Player = world["player"]

	# Accumulate a single bool rather than asserting once per tick: the
	# outcome this test cares about is "never, across the whole run", which is
	# one fact, not 300 of them.
	var ever_vaulted := false
	for i in 300:
		await step(1)
		if player.state_machine.current_name == &"Vault":
			ever_vaulted = true
			break
	check(not ever_vaulted, "a 3 m wall must never be vaulted")

	world["obstacle"].queue_free()
	TestWorld.teardown(world)
	await step(1)

func test_an_obstacle_over_the_height_limit_is_not_vaulted() -> void:
	await step(1)
	# Chosen to sit strictly between vault_max_height (1.3 default) and the
	# world height of VaultHigh's chest-level probe ray (0.9 m feet offset +
	# 0.45 m rig offset = 1.35 m -- see tools/build_player_scene.gd), so this
	# obstacle clears the chest ray outright and only the height gate inside
	# Probes.vault_query() can reject it. Unlike test_a_wall_is_not_vaulted's
	# 3 m wall -- which VaultHigh.is_colliding() rejects before
	# vault_max_height is ever consulted in probes.gd's vault_query() -- this
	# is the case that actually exercises the height bound.
	var over_limit_height := 1.325

	var world := await _running_at_obstacle(over_limit_height)
	var player: Player = world["player"]
	var vaulted := false
	for i in 300:
		await step(1)
		if player.state_machine.current_name == &"Vault":
			vaulted = true
			break
	check(not vaulted, \
		"an obstacle taller than vault_max_height must not be vaulted, even though it clears the chest-height probe")
	world["obstacle"].queue_free()
	TestWorld.teardown(world)
	await step(1)

	# Prove the height gate -- and not some other rejection -- is what bit
	# above: raise vault_max_height past this SAME obstacle's height, and the
	# very same geometry must now vault. If this half did not flip, the check
	# above would have been passing for the wrong reason (this is what the
	# original test_a_wall_is_not_vaulted's 3 m wall could never prove, since
	# no config change could ever make VaultHigh stop colliding with it).
	var loosened := MovementConfig.new()
	loosened.vault_max_height = over_limit_height + 0.2
	world = await _running_at_obstacle(over_limit_height, loosened)
	player = world["player"]
	vaulted = false
	for i in 300:
		await step(1)
		if player.state_machine.current_name == &"Vault":
			vaulted = true
			break
	check(vaulted, \
		"raising vault_max_height past this obstacle's height must make it vaultable")
	world["obstacle"].queue_free()
	TestWorld.teardown(world)
	await step(1)

## A vault is the fastest the player ever moves, and the FOV widening is the
## cue that says so. It used to say the opposite: the camera was fed
## horizontal_speed(), and a scripted move deliberately zeroes velocity for its
## whole duration (it drives global_position directly and never calls
## move_and_slide), so the FOV read 0 m/s and lerped back toward fov_base
## throughout — a slow-down cue delivered at the exact moment of the burst.
##
## Player.travel_speed() measures the body's actual displacement instead, which
## is true in every state, scripted or not. Note the residual: ScriptedMove's
## arc is deliberately EASE-OUT, so the last few ticks of a vault genuinely are
## slow and the FOV genuinely eases back over them. That is the manoeuvre
## finishing, not a lie about it, and it is bounded — hence a floor on the
## MINIMUM below rather than a demand that the FOV hold flat.
func test_the_fov_does_not_collapse_during_a_vault() -> void:
	await step(1)
	var cfg := MovementConfig.new()
	var world := await _running_at_obstacle(1.0, cfg)
	var player: Player = world["player"]
	var rig: CameraRig = player.camera_rig
	check(rig != null, "precondition: the test player needs a camera rig")

	var approach := 0.0
	for i in 400:
		await step(1)
		if player.state_machine.current_name == &"Vault":
			break
		approach = player.travel_speed()
	check(player.state_machine.current_name == &"Vault", "precondition: the obstacle should have been vaulted")
	check_greater(approach, cfg.vault_min_speed, "precondition: the approach should be a real run-up")

	var lowest_fov := INF
	var fastest_travel := 0.0
	var velocity_ever_nonzero := false
	for i in 400:
		await step(1)
		if player.state_machine.current_name != &"Vault":
			break
		lowest_fov = minf(lowest_fov, rig.camera.fov)
		fastest_travel = maxf(fastest_travel, player.travel_speed())
		if player.horizontal_speed() > 0.001:
			velocity_ever_nonzero = true

	# The premise: velocity really is zero for the whole scripted move, so
	# anything reading it would have had nothing but 0 m/s to go on.
	check(not velocity_ever_nonzero, \
		"precondition: a scripted move should report zero velocity throughout — if it does not, this test is no longer exercising the case it was written for")
	check_greater(fastest_travel, approach * 0.8, \
		"the body's measured travel during the vault (%f) fell well below the approach speed (%f)" \
		% [fastest_travel, approach])

	# Fed velocity, the FOV decays from near fov_max to about fov_base + 2 over
	# the vault's ~19 ticks (measured). Fed real travel it stays in the top half
	# of the range until the ease-out tail.
	var floor_fov: float = cfg.fov_base + 0.35 * (cfg.fov_max - cfg.fov_base)
	check_greater(lowest_fov, floor_fov, \
		"the FOV fell to %f during the vault, below %f — the camera is being told the player slowed down at the moment they are moving fastest" \
		% [lowest_fov, floor_fov])

	world["obstacle"].queue_free()
	TestWorld.teardown(world)
	await step(1)

func test_a_vault_over_a_thin_obstacle_does_not_falsely_declare_grounded() -> void:
	await step(1)
	# A THIN obstacle: vault_exit_forward (0.6 m default) alone comfortably
	# overshoots this obstacle's whole footprint, so wherever within it the
	# surface probe's "top" sample happens to land, the computed landing point
	# ends up well past the far edge -- floating at the obstacle's TOP height
	# (landing.y is pinned to that, not to the real floor) with nothing
	# beneath it until the real floor, roughly the obstacle's height below. A
	# wide obstacle can accidentally still land the player standing on its own
	# top surface, which is grounded-safe by coincidence, not by any check --
	# this is the geometry that actually exposes an unverified completion.
	#
	# 0.3 m, not thinner: Probes.vault_query()'s downward ray samples once per
	# physics tick at a FIXED forward offset that moves with the player, so at
	# sprint speed (~9 m/s / 60 Hz ~= 0.15 m per tick) an obstacle much
	# thinner than one tick's travel can be stepped clean over between two
	# samples and never register a hit at all -- a sampling-resolution
	# artifact of this test, not the bug under test. 0.3 m gives a
	# comfortable multi-tick margin while staying well under
	# vault_exit_forward (0.6 m), so the overshoot past the far edge is still
	# real and still lands the player over open air.
	var thin_depth := 0.3
	var world := await _running_at_obstacle(1.0, null, thin_depth)
	var player: Player = world["player"]

	var vaulted := false
	for i in 400:
		await step(1)
		if player.state_machine.current_name == &"Vault":
			vaulted = true
			break
	check(vaulted, "precondition: a thin waist-high obstacle should still be vaultable")

	var grounded_on_handoff := true
	for i in 400:
		await step(1)
		if player.state_machine.current_name != &"Vault":
			# The very tick the vault hands off to Ground, the landing has not
			# been verified against real geometry (no move_and_slide has run
			# for it yet) -- it must not claim to be grounded regardless.
			grounded_on_handoff = player.grounded
			break
	check(not grounded_on_handoff, \
		"the vault declared the player grounded before GroundState's own move_and_slide() verified it")

	world["obstacle"].queue_free()
	TestWorld.teardown(world)
	await step(1)
