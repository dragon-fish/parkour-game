extends ParkourTest

# The counter the whole landing system reads instead of velocity.y. Getting
# this shape right is what makes the community's ventkick / drop-roll layer
# possible at all -- 03 §3.5 is explicit that reading the current frame's
# vertical speed can never produce those behaviours.
#
# ✅ The ORIGIN of the measurement is settled by the original's own level design
# (03 §3.1): fall height counts from where the feet left the ground, not from
# the arc's apex. Rewritten from an apex-tracking version -- see
# test_a_jump_that_lands_where_it_started_is_not_a_fall() for what that model
# got wrong.

func _tracker(ground_y: float = 0.0) -> FallTracker:
	var tracker := FallTracker.new()
	tracker.reset(ground_y)
	return tracker

func test_it_measures_the_drop_below_the_launch_point() -> void:
	var tracker := _tracker(10.0)
	tracker.update(1.0 / 60.0, -3.0, 8.0)
	assert_almost_eq(tracker.fall_height, 2.0, 0.0001, "did not measure the drop")
	tracker.update(1.0 / 60.0, -5.0, 6.0)
	assert_almost_eq(tracker.fall_height, 4.0, 0.0001, "did not follow the descent")

func test_a_jump_that_lands_where_it_started_is_not_a_fall() -> void:
	# The case the previous apex-based implementation got wrong. Jumping in
	# place rose 1.24 m and came back down; measured from the apex that scored
	# as a 1.1 m fall, and every ledge jumped off was scored 1.24 m deeper than
	# it is. That error is what would have made the original's shipped 9.5 m
	# drop read as 10.74 m -- past the 10 m death line -- on a route that is
	# actually safe.
	var tracker := _tracker(10.0)
	tracker.update(1.0 / 60.0, 6.3, 10.6)
	tracker.update(1.0 / 60.0, 0.0, 11.24)
	tracker.update(1.0 / 60.0, -6.3, 10.6)
	tracker.update(1.0 / 60.0, -6.3, 10.0)
	assert_almost_eq(tracker.fall_height, 0.0, 0.0001, "a flat jump registered as a fall")

func test_rising_above_the_launch_point_never_produces_a_fall() -> void:
	var tracker := _tracker(10.0)
	for i in 30:
		tracker.update(1.0 / 60.0, 5.0, 10.0 + i)
	assert_almost_eq(tracker.fall_height, 0.0, 0.0001, "climbing registered as a fall")

func test_a_wall_jump_chain_is_measured_from_the_original_launch() -> void:
	# Rising mid-flight does not re-baseline the counter: the original keeps
	# SZ at the point the feet left the ground until they touch down again, so
	# a chain that climbs and then falls back past its start is scored from the
	# start, not from the peak it reached along the way.
	var tracker := _tracker(10.0)
	tracker.update(1.0 / 60.0, -3.0, 9.0)
	tracker.update(1.0 / 60.0, 5.0, 14.0)
	tracker.update(1.0 / 60.0, -3.0, 7.0)
	assert_almost_eq(tracker.fall_height, 3.0, 0.0001, "the mid-air rise re-baselined the counter")

func test_it_tracks_the_current_depth_rather_than_the_deepest_seen() -> void:
	# What matters is the depth at the moment of touchdown, so a body that is
	# pushed back up (a wall jump taken low) owes only what it is down by then.
	var tracker := _tracker(10.0)
	tracker.update(1.0 / 60.0, -8.0, 4.0)
	assert_almost_eq(tracker.fall_height, 6.0, 0.0001, "did not follow the descent")
	tracker.update(1.0 / 60.0, 6.0, 8.0)
	assert_almost_eq(tracker.fall_height, 2.0, 0.0001, "kept charging for height already regained")

func test_reset_rebaselines_to_the_new_ground() -> void:
	# Any ground contact resets it. This is the whole mechanism behind the
	# community's drop-roll: touch down, and the accumulated height is gone
	# before you step off the edge again.
	var tracker := _tracker(10.0)
	tracker.update(1.0 / 60.0, -6.0, 4.0)
	assert_gt(tracker.fall_height, 5.0, "nothing accumulated to reset")
	tracker.reset(4.0)
	assert_almost_eq(tracker.fall_height, 0.0, 0.0001, "reset did not clear the counter")
	tracker.update(1.0 / 60.0, -3.0, 3.0)
	assert_almost_eq(tracker.fall_height, 1.0, 0.0001, "reset did not rebaseline to the new ground")
