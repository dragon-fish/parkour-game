class_name LedgeWalkMove
extends LineWalkMove

# The original's TdMove_LedgeWalk: shuffling a narrow ledge at a tenth of
# walking speed, a hand on the wall.
#
# IT IS THIS SHORT ON PURPOSE. The CDO carries no balance fields at all, so
# there is nothing to fall off and nothing to correct -- every difference from
# BalanceMove is declared in LedgeWalkConfig rather than written here. See that
# file's own header.
#
# TWO FACINGS, AND THE VIEW DECIDES. [ME:CONFIRMED] the first game's LedgeWalk
# always faces AWAY from the wall; only Catalyst added the facing-the-wall
# variant. This project uses both, the owner's call: FIRST PERSON backs onto
# the wall -- an eye a hand's length from a wall, facing it, is unplayable --
# and THIRD PERSON faces it. A third-person player walks up to a ledge looking
# at the wall, and a model pinned with its back to that wall turned round on
# the spot the moment it was caught. Facing the wall also puts the ordinary
# third-person camera, which sits behind the view, on the open side of the
# ledge by itself: nothing has to hold it out of the wall, orbit it round the
# body or re-aim it, and every mechanism that once did exactly that is gone
# from here for good reason. Switching views mid-ledge turns the body round in
# place -- see _begin_turn().

func kind() -> InterestLine.Kind:
	return InterestLine.Kind.LEDGE_WALK

## Which way the body stands on this ledge: facing the wall (third person)
## or with its back to it (first person). Chosen at the catch and re-chosen
## by a turn whenever the view changes.
var _faces_wall: bool = false

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
## The authored convention that decides is the node's own -Z pointing at the
## wall (InterestLine.front()): the sign is picked to face the body away from
## that, or toward it when _faces_wall says so, instead of trusting the
## curve's own direction to happen to agree. Without this, reversing a level
## author's two curve points silently turns the walk round.
func _yaw_offset(tangent: Vector3) -> float:
	var magnitude: float = cfg.get("body_yaw_offset_deg")
	var normal := Vector3(-tangent.z, 0.0, tangent.x)
	var wall: Vector3 = _line.front()
	# +magnitude faces -normal_at(tangent); that faces away from the wall
	# exactly when normal itself points TOWARD the wall (normal.dot(wall) > 0).
	var away: float = magnitude if normal.dot(wall) > 0.0 else -magnitude
	var signed: float = -away if _faces_wall else away
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
## order happens to make _yaw_offset() pick -90 for -- and on every ledge
## walked facing the wall.
##
## Deadzoned so a body that has stopped, or is only correcting a fraction of a
## metre near the deadzone in LineWalkMove.physics_update(), does not flicker
## between Walk_L and Walk_R on float noise -- the same reasoning
## CharacterAnimator._travel_angle() applies to its own dead zone.
func note_travel(along: float) -> void:
	var lateral: float = along * _facing_sign
	_shuffle_dir = int(signf(lateral)) if absf(lateral) > 0.1 else 0
	if _shuffle_dir != 0:
		_last_shuffle = _shuffle_dir

## The last direction the body actually travelled, HELD after the key is
## released -- unlike _shuffle_dir, which falls back to 0 the moment the input
## does. Where the head keeps looking; see head_yaw_override().
var _last_shuffle: int = 0

func _adjust_along(along: float, input: MoveInput) -> float:
	_update_look_assist_latch(input)
	# NOTHING TRAVELS WHILE THE BODY IS TURNING ROUND. The feet are busy.
	if _turning:
		return 0.0
	var assist: float = _ws_assist_sign * input.move.y if _ws_assist_engaged else 0.0
	return along + assist

# --- W/S: camera-assisted, latched on press ----------------------------------
#
# Owner: looking well off the ledge and holding W should carry a body along
# it the way A/D already do, so a third-person player can steer with the
# camera instead of the keyboard. Latched on press: turning the view while W
# is held must not make the travel direction jump mid-stride. NOT a live
# angle check -- a camera hovering near the switch-over point would make it
# flutter -- and that latch is also why no hysteresis dial is needed.

## True while W/S is being held, so a fresh press (0 -> nonzero) can be told
## apart from a continued hold.
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

## Gated on how far the VIEW has turned off the ledge's own normal, either way
## along the line. Below the threshold this press never engages, however far
## the view turns later -- resolved once, for the reason above.
##
## THE VIEW IS WHEREVER THE CAMERA LOOKS, in both views. In first person the
## camera is the eye, so this is the body's own yaw. In third person the
## camera sits behind the view, looking past the body's back at the wall, and
## the rule is the ordinary third-person one: W goes where the camera is
## looking, projected onto the line. A camera looking straight at the wall
## sends W nowhere; one looking along the ledge walks the body that way.
##
## Measured against the normal AXIS rather than against either direction
## along it, so the same dial reads the same with the body facing the wall or
## backing onto it: 50 degrees off the normal puts sin(50) of the view along
## the tangent either way, and either way it engages.
##
## The SIGN, once engaged, comes from the CURRENT tangent (_walk_yaw): that is
## the direction _offset_along actually advances in, and a reading taken off
## the frozen facing would push travel a fixed +-90 degrees away from where
## the line is really heading.
func _resolve_look_assist() -> void:
	var view_forward: Vector3 = _view_forward()
	if view_forward.length_squared() < 0.0001:
		_ws_assist_engaged = false
		return
	var tangent := Vector3(-sin(_walk_yaw), 0.0, -cos(_walk_yaw))
	var along: float = view_forward.dot(tangent)
	if absf(along) <= sin(deg_to_rad(cfg.get("look_assist_angle_deg"))):
		_ws_assist_engaged = false
		return
	_ws_assist_sign = signf(along)
	_ws_assist_engaged = true

## The camera's own forward, flattened and unit length, or zero when there is
## no direction to read. Falls back to the body's yaw without a camera node --
## the same fallback LadderMove._faces_line() makes.
func _view_forward() -> Vector3:
	var forward: Vector3
	if player.camera_rig != null and player.camera_rig.camera != null:
		forward = -player.camera_rig.camera.global_transform.basis.z
	else:
		forward = -player.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return Vector3.ZERO
	return forward.normalized()

# --- the facing follows the view -----------------------------------------------

func enter(previous: StringName) -> void:
	# BEFORE super.enter(): that is where _target_yaw is built, through
	# _yaw_offset() above, which reads this.
	_faces_wall = _wants_to_face_wall()
	_turning = false
	# THE LATCHES START OVER AT EVERY CATCH. They are resolved on a fresh
	# press, and a key held straight through leaving one ledge and catching
	# the next is a fresh press as far as that ledge is concerned: left
	# unreset, W kept the SIGN it had on the previous ledge, which on the way
	# back in pointed off the end -- caught, ejected on the first tick,
	# caught again two ticks later for as long as the key stayed down.
	_ws_held = false
	_ws_assist_engaged = false
	_ws_assist_sign = 0.0
	_shuffle_dir = 0
	_last_shuffle = 0
	super.enter(previous)

func physics_update(delta: float, input: MoveInput) -> StringName:
	# is_instance_valid(): a line freed under a live move (a level going away)
	# still gets one more tick before super returns FALLING, and a view that
	# changed on that same tick must not reach for the line's wall.
	if not _aborted and is_instance_valid(_line) and not _turning \
			and _wants_to_face_wall() != _faces_wall:
		_begin_turn()
	var next := super.physics_update(delta, input)
	if next == KEEP and _turning:
		_advance_turn(delta)
	return next

func exit() -> void:
	super.exit()
	_turning = false

func faces_wall() -> bool:
	return _faces_wall

## The wider third-person fan -- see LedgeWalkConfig.third_person_look_yaw_deg.
## First person answers NAN and keeps the config's own confirmed number.
func look_yaw_half_span() -> float:
	if player.camera_rig == null or not player.camera_rig.in_third_person():
		return NAN
	return deg_to_rad(cfg.get("third_person_look_yaw_deg")) * 0.5

func _wants_to_face_wall() -> bool:
	return player.camera_rig != null and player.camera_rig.in_third_person()

## True from the tick a view change asks for the other facing until the body
## has turned round. Travel is refused for the duration (see _adjust_along())
## and CharacterAnimator plays turn_clip() fitted to the same window.
var _turning: bool = false
var _turn_elapsed: float = 0.0
## The model's yaw when the turn began, and which way round it goes: +1 turns
## LEFT (Godot's yaw grows counter-clockwise), -1 turns right.
var _turn_from: float = 0.0
var _turn_sign: float = -1.0

## Turns the body round on the spot, over LedgeWalkConfig.turn_time.
##
## THE CAPSULE DOES NOT MOVE. It is on the line either way; only the pinned
## model yaw and the look fan change. The fan is re-centred on the new facing
## at once and left to ease the view round on its own settle -- in first
## person that IS the turn the player sees, since the model is out of view
## from the eye; in third person the camera swings round behind the new
## facing the same way, and the turn clip on the model is what the player
## watches.
##
## TURNS TOWARD THE VIEW. The owner: a body that always turned right looked
## wrong whenever the player was looking left. The side the view is on when
## the turn begins is the side the face sweeps through -- looking left, the
## body turns left, and the view (which the fan eases to whichever of its
## edges is nearer) ends up on the new facing's right, so a third-person head
## left to follow the view keeps looking where the player was looking. Only a
## view dead ahead falls back to the side the body last travelled, on the
## leading foot; right when it has not travelled at all.
func _begin_turn() -> void:
	_faces_wall = not _faces_wall
	_turning = true
	_turn_elapsed = 0.0
	_turn_from = player.visual_yaw()
	# Read BEFORE the fan is re-centred below: that rewrites the running
	# total the view is measured by, not the body's yaw itself, but the yaw
	# is the honest reading either way and this is the moment it is honest
	# against the OLD facing.
	var view_off: float = wrapf(player.rotation.y - _turn_from, -PI, PI)
	if absf(view_off) > deg_to_rad(5.0):
		_turn_sign = 1.0 if view_off > 0.0 else -1.0
	else:
		_turn_sign = 1.0 if _last_shuffle < 0 else -1.0
	# A step that was to the body's right is to its LEFT once it has turned
	# round; the head keeps watching the same direction in the world.
	_last_shuffle = -_last_shuffle
	var facing_tangent := Vector3(-sin(_walk_yaw), 0.0, -cos(_walk_yaw))
	_target_yaw = _walk_yaw + deg_to_rad(_yaw_offset(facing_tangent))
	if player.camera_rig != null:
		player.camera_rig.recentre_yaw_reference(_target_yaw)

func _advance_turn(delta: float) -> void:
	_turn_elapsed += delta
	var t: float = clampf(_turn_elapsed / maxf(cfg.get("turn_time"), 0.001), 0.0, 1.0)
	if t >= 1.0:
		_turning = false
		player.pin_visual_yaw(_target_yaw)
		return
	player.pin_visual_yaw(wrapf(_turn_from + _turn_sign * PI * t, -PI, PI))

func is_turning() -> bool:
	return _turning

## The pack's own half turn, on the side the body is pivoting to. Read by
## CharacterAnimator while is_turning().
func turn_clip() -> StringName:
	return &"Turn180_L" if _turn_sign > 0.0 else &"Turn180_R"

## The scripted-fit hook (CharacterAnimator._scripted_fit): while turning, the
## clip is stretched or squeezed to end with the turn; 0 otherwise.
func scripted_duration() -> float:
	return cfg.get("turn_time") if _turning else 0.0

## Playback rate for whatever clip is on the body while this move runs, or 0
## to leave it to CharacterAnimator's own speed match. Duck-typed there, the
## same way _scripted_fit() is; see LedgeWalkConfig.shuffle_clip_scale. The
## turn clip is fitted, not scaled, so it answers 0 while turning.
func clip_time_scale() -> float:
	return 0.0 if _turning else cfg.get("shuffle_clip_scale")

# --- the head watches where the body is going ------------------------------

## Where the head should point, in radians off the model's own facing, or NAN
## when this move has nothing to say about it.
##
## REPLACES the view-following turn rather than adding to it. The owner: in
## third person the head should not track the camera at all -- it watches the
## direction of travel, and it KEEPS watching it after the keys are released.
## Only travelling the other way moves it.
##
## THIRD PERSON ONLY. In first person the camera follows a head node by
## position, so turning the head slides the eye sideways for no reason the
## player asked for. And not while turning round: the turn clip owns the
## whole body for that half second.
##
## Negated against _last_shuffle: that counts +1 for a step to the body's own
## right, and a yaw measured as "view minus model facing" counts positive to the
## LEFT.
func head_yaw_override() -> float:
	if _turning or player.camera_rig == null or not player.camera_rig.in_third_person():
		return NAN
	if _last_shuffle == 0:
		return NAN
	return -float(_last_shuffle) * deg_to_rad(cfg.get("head_turn_deg"))

## Where the head's pitch is held, in radians, or NAN when this move has
## nothing to say about it. Same terms as head_yaw_override() above: replaces
## the camera's pitch rather than adding to it, and third person only. See
## LedgeWalkConfig.head_pitch_deg.
func head_pitch_override() -> float:
	if _turning or player.camera_rig == null or not player.camera_rig.in_third_person():
		return NAN
	return deg_to_rad(cfg.get("head_pitch_deg"))

## [ME:INFERRED] from play: the original uses a ledge to squeeze a runner
## through a gap in a wall, which a capsule this wide cannot enter.
func passes_through_geometry() -> bool:
	return config.ledge_walk.pass_through_geometry
