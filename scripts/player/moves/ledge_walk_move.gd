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

## LedgeWalkConfig.body_yaw_offset_deg (90) only names the MAGNITUDE -- turn
## a quarter turn off the tangent. Which of the two directions perpendicular
## to the tangent that lands on depends on which way the curve's points were
## drawn, and offset_input()/yaw_of()'s shared convention (see their own
## notes) makes +90 land on -normal_at(tangent) and -90 on +normal_at(tangent).
## The authored convention that is SUPPOSED to decide is the node's own -Z
## pointing at the wall (InterestLine.front()) -- so pick whichever sign
## faces the body away from that, instead of trusting the curve's own
## direction to happen to agree with it. Without this, reversing a level
## author's two curve points silently turns the walk to face the wall.
func _yaw_offset(tangent: Vector3) -> float:
	var magnitude: float = cfg.get("body_yaw_offset_deg")
	var normal := Vector3(-tangent.z, 0.0, tangent.x)
	var wall: Vector3 = _line.front()
	# +magnitude faces -normal_at(tangent); that faces away from the wall
	# exactly when normal itself points TOWARD the wall (normal.dot(wall) > 0).
	return magnitude if normal.dot(wall) > 0.0 else -magnitude

## THE ONE ENTRY GATE, static so every entry site asks the same question before
## transitioning -- no enter-then-abort flutter. Mirrors LadderMove.catch_gate().
static func catch_gate(player: Player, line: InterestLine, snap_height: float) -> bool:
	if not player.line_ready(line):
		return false
	var feet: Vector3 = player.global_position
	feet.y = player.probes.feet_y()
	return LineWalkMove.foot_gate_at(line, feet, snap_height)

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
