class_name LineMove
extends Move

# Shared skeleton of the "along a line" family (zipline / swing / ladder):
# line acquisition, magnet fade bookkeeping, the turn-across-the-fade pair,
# per-line cooldown on the way out, and collision-checked placement for the
# members that ride NEAR level geometry. Subclasses own their physics.

var _line: InterestLine = null
var _fade: float = 0.0
var _entry_pos: Vector3 = Vector3.ZERO
var _entry_yaw: float = 0.0
var _target_yaw: float = 0.0
## Set the tick the fade ends, when the fan is centred on the cable. Guards a
## call that MUST happen once; see _centre_fan().
var _fan_centred: bool = false
var _aborted: bool = false

## Finds the nearest line of `kind` and stores it in `_line`. On failure sets
## `_aborted` (the entry gate already checked reachability; this only guards
## against the line vanishing between the gate and enter()) and returns
## false, so callers can `return` out of their own enter() unchanged.
func acquire_line(kind: InterestLine.Kind) -> bool:
	_aborted = false
	_line = player.nearest_interest_line(kind)
	if _line == null:
		_aborted = true
		return false
	return true

## Sets the body yaw, hands the camera the change so the eye trails the turn
## instead of being cut through it, and takes the model along.
##
## THE FADE-IN ONLY. Once the body is on the cable its yaw is the PLAYER's --
## see _centre_fan() for why this move must stop writing it.
func _turn_body_to(yaw: float) -> void:
	var before: float = player.rotation.y
	player.rotation.y = yaw
	if player.camera_rig != null:
		player.camera_rig.absorb_body_yaw(wrapf(yaw - before, -PI, PI))
	# ZiplineConfig freezes the visual yaw -- both hands are on the cable, so
	# the model must not swivel to follow the view -- and that freeze cancels
	# this turn degree for degree unless the model is told where to face. Same
	# arrangement GrabMove makes at a ledge corner; see Player.pin_visual_yaw().
	player.pin_visual_yaw(yaw)

## Ends the fade: squares the body up to the cable and centres the +-90 degree
## fan on it, so "look 90 degrees off" means 90 degrees off THE CABLE rather
## than off whatever heading the jump happened to arrive with.
##
## ⚠️ ONCE, AND THAT IS THE ENTIRE POINT. recentre_yaw_reference() re-derives
## how far the view has turned from the fan's centre out of the BODY's facing.
## Called every tick with a body this move had just written to the cable's yaw,
## that difference is zero every tick -- and what it zeroes is the mouse yaw
## apply_look() accumulated a few microseconds earlier, since Player runs the
## look before the moves. The ride could not be looked out of at all and the
## config's +-90 fan never applied to anything. WallRunMove guards the same
## call with its own _fan_centred flag, for the same reason.
##
## From here the body's yaw belongs to apply_look(), which rebuilds it every
## tick as fan centre plus the player's own accumulated turn, clamped to the
## fan. This move writes rotation.y no more.
func _centre_fan() -> void:
	_fan_centred = true
	# Not through _turn_body_to(): the fade has already brought the facing to
	# within a rounding error of the cable, so what is left is a snap to exact.
	var before: float = player.rotation.y
	player.rotation.y = _target_yaw
	if player.camera_rig != null:
		player.camera_rig.absorb_body_yaw(wrapf(_target_yaw - before, -PI, PI))
		player.camera_rig.recentre_yaw_reference(_target_yaw)
	player.pin_visual_yaw(_target_yaw)

## Releases the line's own re-catch cooldown. The SAME line refuses a
## re-catch for `redo_time` seconds; every other line stays open -- ✅ THE
## OWNER, measured in the original: release one rope, catch the next at once
## ("shift跳下挂上另一个绳子") -- so this lives on the line, not on the move
## name. Guarded: the line may have been freed between letting go and exit().
func note_left(redo_time: float) -> void:
	if is_instance_valid(_line):
		player.note_line_left(_line, redo_time)

## Moves the body toward `target` THROUGH the physics world instead of
## teleporting it there. Returns the collision if the way was blocked --
## ✅ the owner: designers deliberately sink line ends into walls, and a
## rider must bounce off geometry rather than pass into it.
func slide_to(target: Vector3) -> KinematicCollision3D:
	return player.move_and_collide(target - player.global_position)
