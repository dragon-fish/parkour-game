class_name FallTracker
extends RefCounted

# How far below the last ground contact the body currently is, in metres --
# the quantity the original's landing system judges on (03 §3.1, 10.1 mechanic 5).
#
# WHY NOT velocity.y: 03 §3.5 traces an entire layer of community technique
# (ventkick, kickglitch, drop-roll, fall-break kick) to this being a
# RESETTABLE COUNTER rather than an instantaneous reading. Anything that
# produces a ground-contact event zeroes it, and that emergent behaviour is
# unreachable if the landing reads the current frame's vertical speed.
#
# [ME:CONFIRMED] The count starts where the feet LEFT THE GROUND, not at
# the arc's apex, and not at the moment the descent passes some speed. The
# original's debug HUD exposes exactly this as SZD (= Z - SZ, where SZ is the
# last launch height), and it begins moving the instant the player leaves the
# ground for any reason.
#
# The proof that it is the launch point and not the apex comes from the
# original's own level design: a shipped 9.5 m drop is JUMPED off, and jumping
# adds 1.24 m of rise. Measured from the apex that route would score 10.74 m,
# past the 10 m death threshold -- yet it is a safe, routine path. Only a
# launch-relative measurement lets it survive.
#
# DO NOT arm on a velocity threshold and track the apex instead of the launch
# point: that gives an ordinary jump in place a fake ~1.1 m "fall" on landing
# back at its own start height, and scores every ledge jumped off a full
# jump-height deeper than it really is.
#
# Deliberately RefCounted and fed plain floats: it owns no node and does no
# queries, so it can be tested without a physics world.

var fall_height: float = 0.0

var _launch_y: float = 0.0

## Re-baseline to a new ground height. Called from Player.set_grounded() on
## every ground contact, which is what makes the counter resettable.
func reset(ground_y: float) -> void:
	fall_height = 0.0
	_launch_y = ground_y

## `world_y` is read straight from the body. `vertical_velocity` is accepted
## but unused: the launch-relative measurement needs no speed gate, and the
## parameter is kept so callers (and the landing tests) keep reading like the
## physical description they are.
func update(_delta: float, _vertical_velocity: float, world_y: float) -> void:
	# CURRENT depth, not the deepest seen. What a landing charges for is how
	# far down the body is when it touches, so height regained mid-flight (a
	# wall jump taken low) is genuinely no longer owed.
	fall_height = maxf(0.0, _launch_y - world_y)
