class_name TestUncontrolledFall
extends TestCase

# ✅ MEASURED (03 §3.1): falling past 10 m in the original does not calculate
# landing damage -- it takes control away at the moment the line is crossed.
# TdMove_FallingUncontrolled's ControllerState is literally PlayerDying, and
# the owner's in-game test confirms a roll cannot save it: the blackout, the
# flailing animation and the wind noise are the death PLAYING OUT, not a
# warning that death is near.
#
# The distinction matters for feel, not bookkeeping. Scoring damage on impact
# leaves the player with agency the whole way down; taking control on the way
# down means the outcome is settled in the air and the player can see it coming
# and do nothing about it.

func _player() -> Player:
	var player := Player.new()
	player.config = MovementConfig.new()
	player.fall_tracker = FallTracker.new()
	player.fall_tracker.reset(0.0)
	return player

func test_a_short_fall_leaves_the_player_in_control() -> void:
	var player := _player()
	player.fall_tracker.update(1.0 / 60.0, -10.0, -9.9)
	player.update_uncontrolled_fall()
	check(not player.uncontrolled_fall, "a 9.9 m fall took control away")
	player.free()

func test_crossing_the_threshold_takes_control_away() -> void:
	var player := _player()
	player.fall_tracker.update(1.0 / 60.0, -14.0, -10.1)
	player.update_uncontrolled_fall()
	check(player.uncontrolled_fall, "a 10.1 m fall left the player in control")
	player.free()

func test_the_threshold_is_the_configured_one() -> void:
	var player := _player()
	player.config.pawn.falling_uncontrolled_height = 4.0
	player.fall_tracker.update(1.0 / 60.0, -9.0, -4.1)
	player.update_uncontrolled_fall()
	check(player.uncontrolled_fall, "the check ignored the configured height")
	player.free()

func test_control_is_not_handed_back_by_climbing() -> void:
	# One-way door. Once the state is entered the outcome is settled, so a
	# wall kick or any other mid-air rescue that reduces the current depth
	# must not undo it -- otherwise the player could grab their way out of a
	# death the original considers already decided.
	var player := _player()
	player.fall_tracker.update(1.0 / 60.0, -14.0, -10.5)
	player.update_uncontrolled_fall()
	check(player.uncontrolled_fall, "test setup is wrong: never entered the state")
	player.fall_tracker.update(1.0 / 60.0, 6.0, -2.0)
	player.update_uncontrolled_fall()
	check(player.uncontrolled_fall, "climbing back up handed control back")
	player.free()

func test_landing_clears_it() -> void:
	# set_grounded() is the universal reset for fall bookkeeping; the death is
	# consumed by whoever is listening, and the next life starts clean.
	#
	# Needs the tree: set_grounded() reads global_position, which errors out on
	# a node that was never added (the other cases here are pure arithmetic and
	# deliberately stay out of it).
	var player := _player()
	tree.root.add_child(player)
	await step(1)
	player.fall_tracker.update(1.0 / 60.0, -14.0, -10.5)
	player.update_uncontrolled_fall()
	check(player.uncontrolled_fall, "test setup is wrong: never entered the state")
	player.set_grounded(true)
	check(not player.uncontrolled_fall, "ground contact did not clear the state")
	player.queue_free()
	await step(1)
