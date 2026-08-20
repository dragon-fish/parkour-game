class_name ParkourTest
extends GutTest

# Base class for this project's tests. Everything comes from GUT -- asserts,
# doubles, the runner, filtering -- except how a test advances the physics
# server, which is the one thing that has to be exact here.
#
# WHY NOT wait_physics_frames(). GUT's own waiter ends on the frame AFTER the
# count is reached (addons/gut/awaiter.gd: `_elapsed_frames > _wait_physics_frames`),
# so wait_physics_frames(1) advances two frames. Most suites never notice. This
# one does: its tests are physics measurements, and several drive the tick loop
# one frame at a time -- `for i in 430: await step(1)` becomes 860 frames of
# acceleration, which is enough to saturate the speed-energy budget and make a
# test comparing two consecutive ticks read 0 against 0.
#
# The migration to GUT measured exactly that: 11 tests failed on frame counts
# alone, every one of them a timing assertion rather than a logic error.
func step(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame
