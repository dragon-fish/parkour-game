class_name TestSpeedVaultMove
extends TestCase

# Task 14 fix round: SpeedVaultMove.enter()'s own clamp arithmetic
# (exit = clampf(entry + speed_addition, clamp_speed_min, clamp_speed_max))
# had nothing calling through it -- test_vault_variants.gd only ever asserted
# SpeedVaultConfig.pick_variant()'s speed_addition FIELD is positive, never
# that the clamp actually lets it through. Review found the sweet spot's own
# clamp_speed_max (7.2) is set exactly to PawnConfig.ground_speed, so an
# entry AT the speed cap gets the bonus added and then clamped straight back
# off -- a faithful transcription of the source (ClampSpeedMax = 720 =
# GroundSpeed there too), not a bug, but the opposite of what the only
# existing test (entry 6.0, just under the threshold) could ever have shown.
#
# Both tests below drive player.velocity and player.pending_vault_variant
# directly, then call MoveManager.start(SPEED_VAULT) -- the same hand-off
# WalkingMove/FallingMove perform on a real match -- so SpeedVaultMove.enter()
# runs for real, through the real formula, rather than being re-derived by
# hand in the test. The exit speed is only ever assigned to player.velocity
# when the scripted arc COMPLETES (ScriptedMove.advance() returning true
# inside physics_update(), not enter() itself, which zeroes velocity for the
# duration of the move) -- see the step loop below.

const TestWorld = preload("res://tests/world_fixture.gd")

## A thin, sweet-spot-height box positioned exactly like test_probes_vault.gd's
## own thin-box fixture (straddling SurfaceDown's fixed forward reach at world
## z = -1.4), so vault_query() reads it as vault_over = true and
## pick_variant() resolves to the "vault_over" row -- the one row that pays
## the +0.8 bonus.
func _world_with_sweet_spot_box() -> Dictionary:
	var world := TestWorld.build(tree, MovementConfig.new())
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 0.9, 0.4)
	shape.shape = box
	body.add_child(shape)
	tree.root.add_child(body)
	world["box"] = body
	world["box_at"] = Vector3(0.0, 0.45, -1.4)
	return world

## Sets player.velocity to `entry_speed` along -Z, resolves the real variant
## through SpeedVaultConfig.pick_variant() (the same call WalkingMove makes),
## hands it to MoveManager.start(SPEED_VAULT), then steps until the scripted
## arc completes and the manager falls back to WALKING -- capturing
## player.velocity on that exact tick, before WalkingMove's own
## ground_accelerate() has had a chance to touch it (MoveManager only
## exit()/enter()s the incoming move that tick; the incoming move's own
## physics_update() does not run until the NEXT tick).
func _exit_speed_for(entry_speed: float) -> float:
	var world := _world_with_sweet_spot_box()
	await step(1)
	TestWorld.place(world)
	world["box"].global_position = world["box_at"]
	await step(30)

	var player: Player = world["player"]
	player.velocity = Vector3(0.0, 0.0, -entry_speed)

	var hit: Dictionary = player.probes.vault_query()
	check(hit["valid"], "the probe missed the sweet-spot box -- fixture is wrong")
	var variant: Dictionary = player.config.speed_vault.pick_variant( \
		hit["height"], hit["vault_over"], player.velocity.y, entry_speed)
	check(variant.get("name", "") == "vault_over", \
		"fixture did not resolve to vault_over -- got %s" % variant.get("name", "<none>"))

	player.pending_vault_variant = variant
	player.move_manager.start(Move.SPEED_VAULT)

	var exit_speed := 0.0
	var completed := false
	for i in 90:
		await step(1)
		if player.move_manager.current_name == Move.WALKING:
			exit_speed = player.velocity.length()
			completed = true
			break
	check(completed, "the vault never returned to Walking")

	world["box"].queue_free()
	TestWorld.teardown(world)
	await step(1)
	return exit_speed

func test_the_bonus_lands_at_a_mid_range_entry_speed() -> void:
	# Comfortably below where clamp_speed_max (7.2, == ground_speed) starts
	# eating the +0.8: 5.0 + 0.8 = 5.8, still well under 7.2.
	var exit_speed: float = await _exit_speed_for(5.0)
	check_approx(exit_speed, 5.8, 0.01, \
		"a mid-range entry did not receive the full +0.8 bonus")

func test_the_bonus_evaporates_at_the_speed_cap() -> void:
	# At entry == ground_speed, entry + 0.8 clamps straight back down to
	# ground_speed -- net gain exactly zero. This is what the review flagged:
	# the bonus recovers speed a player has LOST, it cannot grant speed past
	# their own ceiling, and no test before this one drove an entry this high.
	var ground_speed: float = MovementConfig.new().pawn.ground_speed
	var exit_speed: float = await _exit_speed_for(ground_speed)
	check_approx(exit_speed, ground_speed, 0.01, \
		"an entry at the speed cap kept some of the bonus instead of losing all of it")
