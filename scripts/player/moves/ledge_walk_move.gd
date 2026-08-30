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

# --- third-person camera arc --------------------------------------------------
#
# Owner's own call, not a claim about the original: the camera normally sits
# opposite the view direction, which puts it inside the wall the body's back
# is against. CameraRig.set_ledge_camera_arc() clamps the bearing instead;
# this is only where that gets fed every tick and cleared on exit. BalanceMove
# does not call this, so its forced first person is untouched.

func physics_update(delta: float, input: MoveInput) -> StringName:
	var next := super.physics_update(delta, input)
	if next == KEEP and player.camera_rig != null:
		player.camera_rig.set_ledge_camera_arc(
			player.visual_yaw(), deg_to_rad(cfg.get("camera_arc_deg")) * 0.5)
	return next

func exit() -> void:
	super.exit()
	if player.camera_rig != null:
		player.camera_rig.clear_ledge_camera_arc()

# --- A/D: screen-relative, latched on press -----------------------------------
#
# The arc above keeps third person watching from the front more or less the
# whole time, and CameraRig never re-aims the camera at the body -- it only
# translates -- so from that side a body-relative D (the body's own right,
# which is what project_input() already returns and is all BalanceMove ever
# wants) reads backwards on screen the way it never did watched from behind.
#
# NOT a live angle check -- the owner rejected that: a camera hovering near
# the switch-over point would make A/D flutter. The meaning is resolved once,
# the instant a lateral key goes down, and held until release; turning the
# camera mid-press changes nothing. This is also why no hysteresis dial is
# needed -- the latch already removes the flutter a live threshold would need
# one to fix.

## True while a lateral key is being held, so a fresh press (0 -> nonzero) can
## be told apart from a continued hold.
var _lateral_held: bool = false
## +1: D means the body's own right, project_input()'s own reading, unchanged.
## -1: flipped. Resolved once per press by _resolve_lateral_flip().
var _lateral_flip: float = 1.0

func _adjust_along(along: float, input: MoveInput) -> float:
	_update_lateral_latch(input)
	_update_look_assist_latch(input)
	var assist: float = _ws_assist_sign * input.move.y if _ws_assist_engaged else 0.0
	return along * _lateral_flip + assist

func _update_lateral_latch(input: MoveInput) -> void:
	var held: bool = absf(input.move.x) > 0.0001
	if held and not _lateral_held:
		_lateral_flip = _resolve_lateral_flip()
	elif not held:
		_lateral_flip = 1.0
	_lateral_held = held

## Resolved from where the third-person camera actually sits, not merely from
## being in third person: the arc clamp above keeps it within the body's own
## front hemisphere (never past +-90 degrees of Player.visual_yaw()) for the
## whole time this move owns the camera, so any third-person framing here
## reads flipped. First person has no separate camera position at all -- the
## eye IS the view -- so there is nothing to flip.
func _resolve_lateral_flip() -> float:
	if player.camera_rig == null or player.camera_rig.camera == null \
			or not player.camera_rig.in_third_person():
		return 1.0
	var to_camera: Vector3 = player.camera_rig.camera.global_transform.origin \
		- player.global_position
	to_camera.y = 0.0
	if to_camera.length_squared() < 0.0001:
		return 1.0
	var front_yaw: float = player.visual_yaw()
	var front := Vector3(-sin(front_yaw), 0.0, -cos(front_yaw))
	return -1.0 if to_camera.normalized().dot(front) > 0.0 else 1.0

# --- W/S: camera-assisted, latched the same way -------------------------------
#
# Owner: looking well off the ledge and holding W should carry a body along
# it the way A/D already do, so a third-person player can steer with the
# camera instead of the keyboard. Same latch shape as A/D above and for the
# same reason: turning the view while W is held must not make the travel
# direction jump mid-stride.

## Same shape as _lateral_held, for W/S.
var _ws_held: bool = false
## Whether this press engaged the assist at all, and which way along the
## CURRENT tangent it drives -- both frozen at the moment the key went down.
var _ws_assist_engaged: bool = false
var _ws_assist_sign: float = 0.0

func _update_look_assist_latch(input: MoveInput) -> void:
	var held: bool = absf(input.move.y) > 0.0001
	if held and not _ws_held:
		_resolve_look_assist()
	elif not held:
		_ws_assist_engaged = false
	_ws_held = held

## Gated on how far the VIEW has turned off the body's own FROZEN facing
## (Player.visual_yaw() -- what the player actually sees the model doing, NOT
## _walk_yaw, which drifts along a curved line and would gate on a direction
## the player cannot see). Below the threshold this press never engages,
## however far the view turns later -- resolved once, like the A/D flip
## above, and for the same reason.
##
## The SIGN, once engaged, comes from the CURRENT tangent (_walk_yaw) instead:
## that is the direction _offset_along actually advances in, and a reading
## taken off the frozen facing would push travel a fixed +-90 degrees away
## from where the line is really heading.
func _resolve_look_assist() -> void:
	var view_forward: Vector3 = -player.global_transform.basis.z
	if player.camera_rig != null and player.camera_rig.camera != null:
		view_forward = -player.camera_rig.camera.global_transform.basis.z
	view_forward.y = 0.0
	if view_forward.length_squared() < 0.0001:
		_ws_assist_engaged = false
		return
	view_forward = view_forward.normalized()
	var front_yaw: float = player.visual_yaw()
	var front := Vector3(-sin(front_yaw), 0.0, -cos(front_yaw))
	var deviation: float = front.signed_angle_to(view_forward, Vector3.UP)
	if absf(deviation) <= deg_to_rad(cfg.get("look_assist_angle_deg")):
		_ws_assist_engaged = false
		return
	var tangent := Vector3(-sin(_walk_yaw), 0.0, -cos(_walk_yaw))
	_ws_assist_sign = signf(view_forward.dot(tangent))
	_ws_assist_engaged = _ws_assist_sign != 0.0
