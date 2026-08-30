class_name LineWalkMove
extends LineMove

# The half of the "along a line" family that stands ON the line, as opposed to
# the half that hangs UNDER it (zipline, swing) and the ladder's own vertical
# climb. 05 §5.6.5 draws exactly this line: a zipline hangs below and slides
# along, a bar hangs below and swings across, a beam STANDS ON TOP and walks
# along.
#
# Two subclasses: BalanceMove adds an inverted pendulum, LedgeWalkMove adds
# nothing at all. DO NOT collapse them into one move with a switch -- the ledge
# would then carry a whole pendulum pinned at zero, and this project answers
# every "can I go from X to Y" in exactly one place.

## Arc length along the line, metres.
var _offset_along: float = 0.0
## The line's own heading (plus the config's body_yaw_offset_deg): read fresh
## from the line's current tangent every physics_update, NEVER from the
## body's live rotation, which drifts with mouse look inside the look
## constraint. See project_input()'s own note on why that distinction matters.
var _walk_yaw: float = 0.0

## Which kind of line this move rides. Subclasses MUST override.
func kind() -> InterestLine.Kind:
	push_error("LineWalkMove subclass must declare its kind()")
	return InterestLine.Kind.BALANCE

## Input mapped onto the LINE rather than onto a key.
##
## Returns (along, lateral): the input direction projected on the line's own
## tangent, and on its horizontal normal. Everything about "a beam is W/S and a
## ledge is A/D" lives in body_yaw_offset -- a beam's shoulders are along the
## line so W projects fully and A/D project to nothing, a ledge's are across it
## so the same arithmetic hands travel to A/D. There is no branch anywhere.
##
## THE BASIS IS THE LINE'S, NOT THE BODY'S. Player.wish_direction() turns the
## input by the CURRENT body basis, and the body still yaws with the view inside
## the look constraint -- a glance 33 degrees off the beam would then multiply
## walking speed by cos(33). Reading line_yaw off the LINE's own tangent, fresh
## every tick, has no such drift.
static func project_input(move: Vector2, line_yaw: float, yaw_offset: float) -> Vector2:
	var body := Basis(Vector3.UP, line_yaw + yaw_offset)
	var world: Vector3 = body * Vector3(move.x, 0.0, -move.y)
	# `tangent` MUST equal the real +tangent (the direction _offset_along
	# grows in), and `normal` MUST equal tangent x UP (the line's RIGHT-hand
	# normal -- BalanceMove's own lean sign convention). Godot's forward is
	# local -Z, so reconstructing a direction from a yaw that FACES it takes
	# the negative sin/cos form below, matching yaw_of()'s facing convention;
	# reconstructing with the bare +sin/+cos form here (as if yaw_of used
	# atan2(x,z)) silently drives travel opposite to where the body ends up
	# facing. Do not "simplify" back to +sin/+cos without re-deriving against
	# yaw_of() first -- see tests/test_line_walk.gd's structural cases.
	var tangent := Vector3(-sin(line_yaw), 0.0, -cos(line_yaw))
	var normal := Vector3(-tangent.z, 0.0, tangent.x)
	return Vector2(world.dot(tangent), world.dot(normal))

## Yaw a body must have to FACE `tangent` -- the same facing convention
## LadderMove._camera_yaw() documents (facing d means yaw = atan2(-d.x,-d.z)).
## NOT atan2(d.x,d.z): that convention faces -d instead, which is what
## LadderMove's own _target_yaw deliberately exploits to face the wall
## ("looks toward -front") but would silently turn a beam-walker to face
## backwards along the direction W is about to drive _offset_along in.
static func yaw_of(tangent: Vector3) -> float:
	var flat := Vector3(tangent.x, 0.0, tangent.z)
	if flat.length_squared() < 0.0001:
		return 0.0
	flat = flat.normalized()
	return atan2(-flat.x, -flat.z)

## Whether the FEET are at the line's own height -- the extra condition every
## entry gate in this tier asks on top of the reach volume.
##
## `body_pos` MUST already be the feet position (Probes.feet_y(), not
## global_position): the capsule's centre sits standing_height * 0.5 above
## the feet at every stance, and this function has no way to correct for
## that on the caller's behalf. Passing the centre silently misses the gate
## by that same half-height on every flush approach -- see catch_gate() in
## BalanceMove/LedgeWalkMove for how the feet position is built.
##
## InterestLine's reach_radius is 0.6 m by default, which is wide enough to
## catch a body running PAST a beam at ground level. Balance is a state that
## takes control away and cannot be walked out of sideways, so a false catch
## costs far more than a missed one.
static func foot_gate_at(line: InterestLine, body_pos: Vector3, snap_height: float) -> bool:
	var at: Vector3 = line.sample(line.closest_offset(body_pos))["position"]
	return absf(body_pos.y - at.y) <= snap_height

func enter(_previous: StringName) -> void:
	# DECLARED, never inferred: a scripted move never calls move_and_slide(),
	# so MoveManager's grounded invariant is satisfied here and nowhere else.
	player.set_grounded(true)
	_aborted = not acquire_line(kind())
	if _aborted:
		return
	_offset_along = _line.closest_offset(player.global_position)
	var s: Dictionary = _line.sample(_offset_along)
	_walk_yaw = LineWalkMove.yaw_of(s["tangent"])
	_target_yaw = _walk_yaw + deg_to_rad(_yaw_offset(s["tangent"]))
	# The multiplier applies to the GroundSpeed constant, not to what was
	# carried in: arriving fast must not survive the step onto the line.
	player.velocity = Vector3.ZERO
	_fade = 0.0
	_entry_pos = player.global_position
	_entry_yaw = player.rotation.y
	_fan_centred = false

func physics_update(delta: float, input: MoveInput) -> StringName:
	if _aborted or not is_instance_valid(_line):
		return FALLING
	player.set_grounded(true)
	player.fall_tracker.reset(player.global_position.y)
	if input.jump_pressed:
		player.consume_roll()
		return FALLING
	if input.crouch_pressed:
		player.consume_roll()
		return FALLING
	var s: Dictionary = _line.sample(_offset_along)
	_walk_yaw = LineWalkMove.yaw_of(s["tangent"])
	var projected := LineWalkMove.project_input(
		input.move, _walk_yaw, deg_to_rad(_yaw_offset(s["tangent"])))
	var speed: float = config.pawn.ground_speed * cfg.speed_modifier
	_offset_along += projected.x * speed * delta
	note_travel(projected.x)
	# Walking off either end is how you leave: the line ran out, so the body is
	# simply standing on whatever is there.
	#
	# GATED ON THE INPUT HAVING ACTUALLY DRIVEN PAST THE END, mirroring
	# LadderMove's own bottom-end release (`_offset <= 0.01 and
	# input.move.y < 0.0`). closest_offset() clamps to [0, length], so a body
	# that CATCHES the line exactly at one end starts this move with
	# _offset_along already sitting on the boundary; without the input check,
	# the very first physics_update -- before any key has been pressed --
	# would see "at the boundary" and exit on the spot.
	var at_end: bool = (_offset_along <= 0.0 and projected.x < 0.0) \
		or (_offset_along >= _line.length() and projected.x > 0.0)
	_offset_along = clampf(_offset_along, 0.0, _line.length())
	if at_end:
		return WALKING
	var next := lateral_update(delta, projected.y)
	if next != KEEP:
		return next
	var stand: Vector3 = _line.sample(_offset_along)["position"] \
		+ Vector3.UP * (player.standing_height() * 0.5) \
		+ lateral_offset() * _normal_at(_walk_yaw)
	_fade += delta
	if _fade < fade_in_time():
		var t: float = _fade / fade_in_time()
		player.global_position = _entry_pos.lerp(stand, t)
		_turn_body_to(lerp_angle(_entry_yaw, _target_yaw, t))
	else:
		slide_to(stand)
		if not _fan_centred:
			_centre_fan()
	return KEEP

func exit() -> void:
	note_left(cfg.redo_move_time, true)

## Arc length along the line, metres. Read by the HUD and by tests.
func line_offset() -> float:
	return _offset_along

## Hook for a subclass that has lateral state of its own (BalanceMove's
## pendulum). Returns a move name to leave, or KEEP. The base tier has none.
func lateral_update(_delta: float, _lateral_input: float) -> StringName:
	return KEEP

## How far off the line's centreline the body currently stands, metres.
func lateral_offset() -> float:
	return 0.0

## Hook for a subclass that needs to know which way along the line the last tick
## travelled. LedgeWalkMove picks its sidestep clip off this; a beam does not
## care, since Walk is the clip either way.
func note_travel(_along: float) -> void:
	pass

## Signed degrees applied on top of the line's own facing (yaw_of(tangent))
## to get the body's target yaw. Base tier reads the magnitude straight off
## the config -- BalanceMove's is 0, so the sign never matters there. A
## subclass whose magnitude is ambiguous without more context (LEDGE_WALK:
## which of the two directions perpendicular to the tangent points away from
## the wall) overrides this and uses `tangent` to pick the sign.
func _yaw_offset(_tangent: Vector3) -> float:
	return cfg.get("body_yaw_offset_deg")

## Reads the DIAL, not a hardcoded number -- LadderConfig.fade_in_time (0.15),
## SwingConfig.fade_in_time (0.1) and ZiplineConfig.fade_in_time (0.1) are the
## same family knob; LedgeWalkConfig and BalanceConfig carry their own.
func fade_in_time() -> float:
	return cfg.get("fade_in_time")

func _normal_at(line_yaw: float) -> Vector3:
	var tangent := Vector3(-sin(line_yaw), 0.0, -cos(line_yaw))
	return Vector3(-tangent.z, 0.0, tangent.x)
