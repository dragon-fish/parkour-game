class_name HalfTurn
extends RefCounted

# Half a turn clockwise, carried out by a script: the Q turn on the ground and
# off a wall (Turn180Move), and the one in mid-air (Turn180InAirMove).
#
# ALWAYS CLOCKWISE, AND ALWAYS EXACTLY HALF A TURN. [ME:CONFIRMED] Faith only
# ever turns right in the original. Godot's yaw grows counter-clockwise seen
# from above, so clockwise is the negative direction. DO NOT turn toward
# whichever side the entry lean favours instead -- that makes the direction a
# function of the entry angle, and leaves it a coin flip on float noise for the
# head-on approach the move is mostly used for.
#
# By absolute progress rather than a per-tick rate, so the turn lands on
# exactly the target.
#
# The turn is a root rotation, and the view goes with it the original's way:
# every frame the pawn turns, the view's yaw is set to the pawn's
# (Player.turn_by_root_rotation()); between those frames the move's own
# UpdateViewRotation holds the view inside its constraint about the pawn.
#
# `player` is untyped for the reason Move.player is.

var from: float = 0.0
var to: float = 0.0
## The facing already placed, so a frame that does not move the turn on does
## not count as one that turned the pawn.
var _placed: float = 0.0

func begin(yaw: float) -> void:
	from = yaw
	to = yaw - PI
	_placed = yaw

## Places the turn `progress` (0 to 1) of the way round.
func advance(player, progress: float) -> void:
	progress = clampf(progress, 0.0, 1.0)
	var wanted: float = lerpf(from, to, progress)
	if is_equal_approx(wanted, _placed):
		return
	_placed = wanted
	player.turn_by_root_rotation(UE.yaw_units(wanted))
