extends ParkourTest

# Kicking straight up a wall (TdMove_WallClimb), the move the owner reported as
# missing. It was worse than missing: Probes had no ray that could see a wall
# in front of the player, so the state was unreachable by construction. These
# tests cover the probe, the entry angle that tells a climb from a wall run,
# and the speed-bought height that is the move's whole economy.

const TestWorld = preload("res://tests/world_fixture.gd")

## Freed after every test. Without this the walls pile up in the shared scene
## root and the NEXT test's run-up meets geometry it never placed -- which is
## how a clean per-file run and a broken full-suite run happen at once.
var _world: Dictionary = {}

func after_each() -> void:
	if _world.is_empty():
		return
	if _world.has("wall"):
		(_world["wall"] as Node).queue_free()
	TestWorld.teardown(_world)
	_world = {}


## A wall spanning x, facing the player who runs at it along -Z.
##
## `height` decides whether it is climbable at all: the probe's second ray
## fires at min_wall_height (1.8 m) above the feet, so a wall shorter than that
## reports tall_enough = false however solid its base is.
func _world_with_wall_ahead(height: float, yaw: float = 0.0) -> Dictionary:
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(world)
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, height, 1.0)
	shape.shape = box
	wall.add_child(shape)
	get_tree().root.add_child(wall)
	# Far face at z = -2.5, near face at z = -2.0, so a player standing at the
	# origin is 2.0 m clear of it -- outside the 0.6 m probe reach, and free to
	# be moved to whatever distance a given test wants.
	# Base resting ON the floor (whose top is y = 0), so `height` is the wall's
	# real height above the ground and a test can reason about it directly.
	wall.global_position = Vector3(0.0, height * 0.5, -2.5)
	wall.rotation = Vector3(0.0, yaw, 0.0)
	world["wall"] = wall
	_world = world
	return world

## Puts the player just inside probe range of the wall, airborne and rising,
## with the run-up speed and heading a climb would have been entered with.
func _prime(world: Dictionary, speed: float, rise: float, heading_yaw: float = 0.0) -> Player:
	var player: Player = world["player"]
	var heading := Vector3(sin(heading_yaw), 0.0, -cos(heading_yaw))
	player.global_position = Vector3(0.0, 1.5, -1.55)
	player.rotation.y = heading_yaw
	player.velocity = heading * speed
	player.velocity.y = rise
	return player

# --- the confirmed numbers ---------------------------------------------------

func test_the_confirmed_thresholds_are_in_place() -> void:
	var config := MovementConfig.new()
	assert_almost_eq(config.wall_climb.vertical_start_angle, deg_to_rad(33.0), 0.001, \
		"WallClimbingVerticalStartAngle is not 33 degrees")
	assert_almost_eq(config.wall_climb.min_wall_height, 1.8, 0.0001, \
		"MinWallHeight is not 180 uu")
	assert_almost_eq(config.wall_climb.horizontal_friction, 6.0, 0.0001, \
		"WallClimbingVerticalFriction is not 6.0")
	assert_almost_eq(config.wall_climb.max_drift, 1.2, 0.0001, \
		"WallClimbingMaxDistance2D is not 120 uu")
	assert_almost_eq(config.wall_climb.friction_modifier, 0.3, 0.0001, \
		"FrictionModifier is not 0.3")

func test_wall_climbing_gravity_is_exactly_half_of_the_projects_own() -> void:
	# WallClimbingGravity = 800 against this project's 1600. Expressed as a
	# scale rather than an absolute so it survives a retune of gravity -- this
	# pins the RELATIONSHIP, which is the part that was measured.
	var config := MovementConfig.new()
	assert_almost_eq(config.wall_climb.gravity_scale, 0.5, 0.0001, \
		"wall climbing gravity is not half of normal gravity")

func test_a_climb_can_still_become_a_grab_or_a_vault() -> void:
	# bCheckForGrab and bCheckForVaultOver are both set on TdMove_WallClimb.
	# This is what makes "kick up, catch the lip" one motion.
	var config := MovementConfig.new()
	assert_true(config.wall_climb.check_for_grab, "a climb cannot reach for a ledge")
	assert_true(config.wall_climb.check_for_vault_over, "a climb cannot turn into a vault")

# --- the height a climb is worth ---------------------------------------------

func test_a_standing_kick_climbs_nothing() -> void:
	# There is no base term anywhere in the CDO, and that is the design: the
	# climb is bought with speed and is worth nothing without it.
	var cfg := WallClimbConfig.new()
	assert_almost_eq(WallClimbMove.climb_height(0.0, 0.0, cfg), 0.0, 0.0001, \
		"a motionless kick was worth height")

func test_height_saturates_at_the_two_limits_added() -> void:
	var cfg := WallClimbConfig.new()
	var most := WallClimbMove.climb_height(99.0, 99.0, cfg)
	assert_almost_eq(most, cfg.run_speed_height + cfg.rise_speed_height, 0.0001, \
		"height did not saturate at 0.6 + 1.3 metres")

func test_only_rising_counts_toward_the_vertical_term() -> void:
	# Falling onto a wall buys nothing. This is what makes kicking EARLY in a
	# jump worth so much more than kicking at the apex, which is how the
	# original rewards the timing.
	var cfg := WallClimbConfig.new()
	var rising := WallClimbMove.climb_height(4.0, 3.2, cfg)
	var falling := WallClimbMove.climb_height(4.0, -3.2, cfg)
	var flat := WallClimbMove.climb_height(4.0, 0.0, cfg)
	assert_gt(rising, flat, "rising into the wall bought no extra height")
	assert_almost_eq(falling, flat, 0.0001, "falling into the wall was priced as rising")

func test_a_faster_run_up_buys_a_higher_climb() -> void:
	var cfg := WallClimbConfig.new()
	assert_gt(WallClimbMove.climb_height(6.5, 0.0, cfg), \
		WallClimbMove.climb_height(3.0, 0.0, cfg), "a faster run-up climbed no higher")

# --- the probe ---------------------------------------------------------------

func test_the_forward_probe_sees_a_wall_the_side_rays_cannot() -> void:
	# The bug behind the whole feature. Running head-on at a flat wall aims
	# WallLeft and WallRight ALONG its face, where they hit nothing.
	var world := await _world_with_wall_ahead(4.0)
	var player: Player = _prime(world, 6.0, 2.0)
	await step(1)
	var heading := Vector3(0.0, 0.0, -1.0)
	assert_false(player.probes.wall_query(heading)["valid"], \
		"the side rays found a head-on wall, so this test no longer proves anything")
	var ahead: Dictionary = player.probes.wall_ahead_query(heading)
	assert_true(ahead["valid"], "the forward probe did not see a wall right in front of it")
	assert_true(ahead["tall_enough"], "a 4 m wall did not read as tall enough")
	assert_almost_eq(float(ahead["incidence"]), 0.0, 0.05, "a head-on approach did not read as 0")

func test_a_wall_shorter_than_the_minimum_is_seen_but_refused() -> void:
	# Two different answers, deliberately: no wall means look elsewhere, while
	# a wall too short to climb is one the vault and grab probes should get.
	# 2 m of wall, met from the same airborne pose as every other probe test
	# here. That pose matters: a wall this size met from STANDING is a vault,
	# and the player is over it and gone before the probe is ever asked.
	#
	# The numbers that make this the case under test: feet at 0.6, so the chest
	# ray fires at 1.7 (inside the wall) and the height ray at 0.6 + 1.8 = 2.4
	# (over the top of it).
	var world := await _world_with_wall_ahead(2.0)
	var player: Player = _prime(world, 6.0, 2.0)
	await step(1)
	var ahead: Dictionary = player.probes.wall_ahead_query(Vector3(0.0, 0.0, -1.0))
	assert_true(ahead["valid"], "a 2 m wall was not seen at all")
	assert_false(ahead["tall_enough"], "a 2 m wall read as tall enough to kick up")

# --- entry -------------------------------------------------------------------

func test_running_head_on_into_a_tall_wall_starts_a_climb() -> void:
	var world := await _world_with_wall_ahead(4.0)
	var player: Player = _prime(world, 6.0, 2.0)
	player.move_manager.start(Move.JUMP)
	await step(2)
	assert_eq(player.move_manager.current_name, Move.WALL_CLIMB, \
		"a head-on run into a tall wall did not start a climb")

func test_a_glancing_approach_still_takes_the_wall_run() -> void:
	# 45 degrees is outside the climb's 33 and inside the wall run's 57. The
	# bands tile; this is the seam between the first two.
	var world := await _world_with_wall_ahead(4.0)
	var player: Player = _prime(world, 6.0, 2.0, deg_to_rad(45.0))
	await step(1)
	var ahead: Dictionary = player.probes.wall_ahead_query( \
		Vector3(player.velocity.x, 0.0, player.velocity.z).normalized())
	assert_gt(float(ahead["incidence"]), player.config.wall_climb.vertical_start_angle, \
		"a 45 degree approach fell inside the climb's own band")

func test_a_climb_rises_and_then_hands_back_to_falling() -> void:
	var world := await _world_with_wall_ahead(6.0)
	var player: Player = _prime(world, 6.0, 2.0)
	var started := player.global_position.y
	player.move_manager.start(Move.JUMP)
	await step(2)
	assert_eq(player.move_manager.current_name, Move.WALL_CLIMB, "the climb never started")
	# Long enough for any climb to be spent: the most one can ever be worth is
	# 1.9 m, which at half gravity takes well under a second to give back.
	for i in 90:
		await step(1)
		if player.move_manager.current_name != Move.WALL_CLIMB:
			break
	assert_ne(player.move_manager.current_name, Move.WALL_CLIMB, \
		"the climb never ended -- it should stop the moment it stops going up")
	assert_gt(player.global_position.y, started, "the climb gained no height at all")
