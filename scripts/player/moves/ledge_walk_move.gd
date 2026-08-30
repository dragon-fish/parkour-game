class_name LedgeWalkMove
extends LineWalkMove

# The original's TdMove_LedgeWalk: shuffling a narrow ledge with your back to
# the wall at a tenth of walking speed.
#
# IT IS THIS SHORT ON PURPOSE. The CDO carries no balance fields at all, so
# there is nothing to fall off and nothing to correct -- every difference from
# BalanceMove is declared in LedgeWalkConfig rather than written here. See that
# file's own header.

func kind() -> InterestLine.Kind:
	return InterestLine.Kind.LEDGE_WALK

## THE ONE ENTRY GATE, static so every entry site asks the same question before
## transitioning -- no enter-then-abort flutter. Mirrors LadderMove.catch_gate().
static func catch_gate(player: Player, line: InterestLine, snap_height: float) -> bool:
	if not player.line_ready(line):
		return false
	return LineWalkMove.foot_gate_at(line, player.global_position, snap_height)

## -1 (toward the line's start), 0 (still), +1 (toward its end) -- what the last
## tick's input actually asked for. CharacterAnimator picks Walk_L/Walk_R off it.
var _shuffle_dir: int = 0

func shuffle_direction() -> int:
	return _shuffle_dir

## Deadzoned so a body that has stopped, or is only correcting a fraction of a
## metre near the deadzone in LineWalkMove.physics_update(), does not flicker
## between Walk_L and Walk_R on float noise -- the same reasoning
## CharacterAnimator._travel_angle() applies to its own dead zone.
func note_travel(along: float) -> void:
	_shuffle_dir = int(signf(along)) if absf(along) > 0.1 else 0
