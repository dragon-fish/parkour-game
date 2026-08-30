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

## Which branch _yaw_offset() picked THIS tick: +1 when the body's right
## coincides with +tangent (magnitude landed on +90), -1 when it landed on
## -90 and the body's right is -tangent instead. note_travel() needs this to
## turn a line-frame reading into a body-frame one -- see its own comment.
var _facing_sign: float = 1.0

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
	var signed: float = magnitude if normal.dot(wall) > 0.0 else -magnitude
	_facing_sign = signf(signed)
	return signed

## THE ONE ENTRY GATE, static so every entry site asks the same question before
## transitioning -- no enter-then-abort flutter. Mirrors LadderMove.catch_gate().
static func catch_gate(player: Player, line: InterestLine, snap_height: float) -> bool:
	if not player.line_ready(line):
		return false
	var feet: Vector3 = player.global_position
	feet.y = player.probes.feet_y()
	return LineWalkMove.foot_gate_at(line, feet, snap_height)

## -1 (a step to the body's left), 0 (still), +1 (a step to the body's right)
## -- IN THE BODY'S FRAME, not the line's. CharacterAnimator picks
## Walk_L/Walk_R off it.
var _shuffle_dir: int = 0

func shuffle_direction() -> int:
	return _shuffle_dir

## `along` arrives in the LINE's frame (positive toward the line's end -- see
## project_input()'s own note), but that only reads as a step to the body's
## right when _yaw_offset() picked +90; on the -90 branch the body's right is
## -tangent, so the same positive `along` is a step to the LEFT. Multiplying
## by `_facing_sign`, cached from this tick's _yaw_offset() call (always made
## before note_travel(), see LineWalkMove.physics_update()), converts to the
## body's frame before the sign reaches CharacterAnimator. Skipping this
## mirrors the sidestep clip on whichever ledges a level author's curve point
## order happens to make _yaw_offset() pick -90 for.
##
## Deadzoned so a body that has stopped, or is only correcting a fraction of a
## metre near the deadzone in LineWalkMove.physics_update(), does not flicker
## between Walk_L and Walk_R on float noise -- the same reasoning
## CharacterAnimator._travel_angle() applies to its own dead zone.
func note_travel(along: float) -> void:
	var lateral: float = along * _facing_sign
	_shuffle_dir = int(signf(lateral)) if absf(lateral) > 0.1 else 0
