class_name FallTracker
extends RefCounted

# Accumulated fall height since the last ground contact -- the quantity the
# original's landing system actually judges on (03 §3.1, 10.1 mechanic 5).
#
# WHY NOT velocity.y: 03 §3.5 traces an entire layer of community technique
# (ventkick, kickglitch, drop-roll, fall-break kick) to this being a
# RESETTABLE COUNTER rather than an instantaneous reading. Anything that
# produces a ground-contact event zeroes it, and that emergent behaviour is
# unreachable if the landing reads the current frame's vertical speed.
#
# Deliberately RefCounted and fed plain floats: it owns no node and does no
# queries, so it can be tested without a physics world.

var fall_height: float = 0.0

var _pawn: PawnConfig
var _falling: bool = false
var _apex_y: float = 0.0

func _init(pawn: PawnConfig) -> void:
	_pawn = pawn

func reset() -> void:
	fall_height = 0.0
	_falling = false

## `vertical_velocity` and `world_y` are read straight from the body. Arming
## on the velocity threshold rather than on "y decreased" is what reproduces
## EnterToFallingZSpeed: the first few centimetres of stepping off a kerb are
## deliberately not counted.
func update(_delta: float, vertical_velocity: float, world_y: float) -> void:
	if not _falling:
		if vertical_velocity > _pawn.enter_to_falling_z_speed:
			return
		_falling = true
		_apex_y = world_y
	# Track the APEX, not the arming point: a wall-jump chain keeps rising
	# after the counter has armed, and the drop that matters is measured from
	# the highest point actually reached.
	_apex_y = maxf(_apex_y, world_y)
	fall_height = maxf(fall_height, _apex_y - world_y)
