class_name TestFallTracker
extends TestCase

# The counter the whole landing system reads instead of velocity.y. Getting
# this shape right is what makes the community's ventkick / drop-roll layer
# possible at all -- 03 §3.5 is explicit that reading the current frame's
# vertical speed can never produce those behaviours.

func _tracker() -> FallTracker:
	return FallTracker.new(PawnConfig.new())

func test_a_gentle_step_off_does_not_start_counting() -> void:
	# EnterToFallingZSpeed = -200 uu/s: the first fraction of a step-down is
	# deliberately not counted at all.
	var tracker := _tracker()
	tracker.update(1.0 / 60.0, -0.5, 10.0)
	tracker.update(1.0 / 60.0, -1.0, 9.99)
	check_approx(tracker.fall_height, 0.0, 0.0001, "counting started below the falling threshold")

func test_it_accumulates_height_lost_since_the_fall_began() -> void:
	var tracker := _tracker()
	tracker.update(1.0 / 60.0, -3.0, 10.0)
	tracker.update(1.0 / 60.0, -4.0, 8.0)
	tracker.update(1.0 / 60.0, -5.0, 6.0)
	check_approx(tracker.fall_height, 4.0, 0.0001, "did not accumulate the drop")

func test_it_measures_from_the_highest_point_not_the_first_sample() -> void:
	# A wall-jump chain rises after the counter has already armed. The drop
	# that matters is the one from the apex, not from wherever the counter
	# happened to start.
	var tracker := _tracker()
	tracker.update(1.0 / 60.0, -3.0, 10.0)
	tracker.update(1.0 / 60.0, 5.0, 14.0)
	tracker.update(1.0 / 60.0, -3.0, 11.0)
	check_approx(tracker.fall_height, 3.0, 0.0001, "measured from the first sample instead of the apex")

func test_reset_clears_the_counter() -> void:
	# Any ground contact resets it. This is the whole mechanism behind the
	# community's drop-roll: touch down, and the accumulated height is gone
	# before you step off the edge again.
	var tracker := _tracker()
	tracker.update(1.0 / 60.0, -3.0, 10.0)
	tracker.update(1.0 / 60.0, -6.0, 4.0)
	check_greater(tracker.fall_height, 5.0, "nothing accumulated to reset")
	tracker.reset()
	check_approx(tracker.fall_height, 0.0, 0.0001, "reset did not clear the counter")

func test_rising_alone_never_produces_a_fall() -> void:
	var tracker := _tracker()
	for i in 30:
		tracker.update(1.0 / 60.0, 5.0, 10.0 + i)
	check_approx(tracker.fall_height, 0.0, 0.0001, "climbing registered as a fall")
