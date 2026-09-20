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
## +1 to face the curve's own tangent, -1 to face -tangent. Chosen once at
## entry (see _pick_direction_sign()) and held for the life of the move --
## _offset_along stays in the curve's own arc-length frame throughout
## (the line's start is still offset 0 regardless of which way the body
## walks), so this sign is what turns "arc length increasing" into "the
## body's own forward" everywhere that distinction matters: _walk_yaw,
## _yaw_offset()'s argument, and the arc-length delta below.
var _direction_sign: float = 1.0

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
	# MUST run before player.velocity is zeroed below -- _pick_direction_sign()'s
	# default override reads the live arrival velocity, and by the time this
	# function returns that velocity is gone.
	_direction_sign = _pick_direction_sign(s["tangent"])
	# NOT forced to face into the line when caught at an end. That was tried:
	# a body backing onto a beam faces off the line, the guard turned it round,
	# and the S it was still holding then walked it straight back off the end
	# -- a fall on the first tick, since the mesh under a beam carries no
	# collider, deliberately. The end guard in physics_update() is gated on the
	# input actually driving past the end, so a catch at an end facing outward
	# is safe on its own: nothing leaves until a key says so, and the key that
	# brought the body in keeps carrying it in. See BalanceMove's own
	# _pick_direction_sign() for how a backing body keeps its facing.
	var facing_tangent: Vector3 = s["tangent"] * _direction_sign
	_walk_yaw = LineWalkMove.yaw_of(facing_tangent)
	_target_yaw = _walk_yaw + deg_to_rad(_yaw_offset(facing_tangent))
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
	# JUMP IS REFUSED OUTRIGHT, not routed anywhere. A body standing on a pipe
	# or edging a ledge has no footing to launch from -- the owner's own call
	# for both members of this tier. The press is simply dropped: a fresh
	# MoveInput is built every tick, so nothing downstream inherits it, and no
	# roll is consumed because no press was spent.
	# CROUCH IS REFUSED TOO, for the same reason as jump above and one more:
	# crouch is Shift on this keyboard, which a player holds for all sorts of
	# reasons, and letting it drop the body off a beam or a ledge -- neither of
	# which has a collider under it to land back on -- turns a stray keypress
	# into a death. Walking off an end is how you leave; losing your balance is
	# how the beam throws you off.
	var s: Dictionary = _line.sample(_offset_along)
	var facing_tangent: Vector3 = s["tangent"] * _direction_sign
	_walk_yaw = LineWalkMove.yaw_of(facing_tangent)
	var projected := LineWalkMove.project_input(
		input.move, _walk_yaw, deg_to_rad(_yaw_offset(facing_tangent)))
	var along: float = _adjust_along(projected.x, input)
	var speed: float = config.pawn.ground_speed * cfg.speed_modifier
	# along is already "along the direction the body faces" (project_input's
	# own invariant, which _adjust_along()'s default identity preserves).
	# _offset_along, though, stays in the curve's RAW arc-length frame -- the
	# line's start is offset 0 no matter which way the body walks -- so
	# converting a facing-frame step into an arc-length delta needs the same
	# sign that turned the raw tangent into facing_tangent above.
	var signed_along: float = along * _direction_sign
	_offset_along += signed_along * speed * delta
	_last_along = along
	note_travel(along)
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
	#
	# Checked against signed_along (the raw arc-length direction), NOT along:
	# on the reversed branch (_direction_sign < 0) walking toward offset 0 is
	# what the body's OWN forward drives, so gating on along here would let a
	# body walking off the reversed end's "far" side exit one tick early or
	# never.
	var at_end: bool = (_offset_along <= 0.0 and signed_along < 0.0) \
		or (_offset_along >= _line.length() and signed_along > 0.0)
	_offset_along = clampf(_offset_along, 0.0, _line.length())
	if at_end:
		return WALKING
	var next := lateral_update(delta, projected.y)
	if next != KEEP:
		return next
	var stand: Vector3 = _line.sample(_offset_along)["position"] \
		+ Vector3.UP * (player.standing_height() * 0.5 - drop_offset()) \
		+ lateral_offset() * _normal_at(_walk_yaw)
	_fade += delta
	if _fade < fade_in_time():
		var t: float = _fade / fade_in_time()
		player.global_position = _entry_pos.lerp(stand, t)
		_turn_body_to(lerp_angle(_entry_yaw, _target_yaw, t))
	else:
		_slide_along_geometry(stand)
		if not _fan_centred:
			_centre_fan()
	return KEEP

## Moves the body toward `stand` and, if something blocks the way, spends the
## rest of the step SLIDING ALONG that surface rather than stopping at it.
##
## The capsule is wider than the ledges it walks. Its radius is 0.4 m; a ledge
## authored with the line down its centre puts the wall nearer than that, so
## every tick the capsule is pushed back out of the wall and every tick `stand`
## asks it to move diagonally: back toward the line AND along it. A bare
## move_and_collide() stops the whole motion at the first contact, which is
## immediate, and the along component goes with it. Measured on the debug
## course: the body crawls while _offset_along runs ahead, then keeps
## catching up after every key is released (reads as inertia), and the move
## exits with the feet still 0.9 m short of the line's end. One extra slide
## of the remainder along the contact plane is what turns a wall the body is
## leaning on back into something it can walk beside.
func _slide_along_geometry(stand: Vector3) -> void:
	if passes_through_geometry():
		# The LINE is the path, and the level author drew it: where it runs
		# through a gap too narrow for the capsule, the body goes through
		# anyway. The original squeezes a runner along a ledge and between two
		# walls this way, and a capsule 0.8 m across cannot do it otherwise.
		player.global_position = stand
		return
	var hit: KinematicCollision3D = slide_to(stand)
	if hit == null:
		return
	var remainder: Vector3 = hit.get_remainder().slide(hit.get_normal())
	if remainder.length_squared() > 0.000001:
		player.move_and_collide(remainder)

## The timed cooldown is armed ONLY when the body left by falling. A walk-off
## at an end is covered by the release latch alone (Player.line_ready(): the
## line re-catches when the body walks back IN along it, and not otherwise),
## and a timer on top of that was lethal: turn round inside it and the next
## step lands on a line that refuses you and a mesh that carries no
## collider. Nothing to guard there. The fall is different -- the body is
## still inside the volume, airborne, for the first ticks of the shove, and
## the timer is what stops the catch gate taking it straight back.
func exit() -> void:
	note_left(redo_cooldown(), true)

## Both cooldowns -- the line's own (note_left() above) and MoveManager's
## redo timer on the move -- take this same answer, so a walk-off arms
## neither and a fall arms both.
func redo_cooldown() -> float:
	return cfg.redo_move_time if _left_by_falling() else 0.0

## Whether this exit is the body being thrown off rather than walking off.
## The base tier cannot fall; BalanceMove's shove overrides this.
func _left_by_falling() -> bool:
	return false

## Arc length along the line, metres. Read by the HUD and by tests.
func line_offset() -> float:
	return _offset_along

## Hook for a subclass that has lateral state of its own (BalanceMove's
## pendulum). Returns a move name to leave, or KEEP. The base tier has none.
func lateral_update(_delta: float, _lateral_input: float) -> StringName:
	return KEEP

## Hook for a subclass that reinterprets project_input()'s own along reading
## before it drives _offset_along and note_travel(). Default is the identity
## -- the base tier and BalanceMove both take it unmodified. LedgeWalkMove
## overrides this for its screen-relative A/D latch and its camera-assisted
## W/S; see its own note for why those live there and not here.
func _adjust_along(along: float, _input: MoveInput) -> float:
	return along

## Which way along `tangent` (the line's own, un-flipped) the body should
## face: +1 keeps the curve's authored direction, -1 reverses it. Called once
## at entry, before player.velocity is zeroed -- see enter()'s own note.
##
## Base tier never reverses. LedgeWalkMove keeps this default: its two
## possible facings are already resolved by _yaw_offset()'s own wall-relative
## sign (InterestLine.front()), a property of the LINE, not of how the player
## walked up to it, so there is nothing here for it to decide. BalanceMove
## overrides this -- see its own note for which arrival signal it reads.
func _pick_direction_sign(_tangent: Vector3) -> float:
	return 1.0

## Whether the body follows its line THROUGH whatever stands in the way.
## A beam is walked in the open and has geometry to respect; a ledge is not
## (LedgeWalkMove overrides this).
func passes_through_geometry() -> bool:
	return false

## How far off the line's centreline the body currently stands, metres.
func lateral_offset() -> float:
	return 0.0

## How far BELOW the line the body currently stands, metres, positive down.
## The base tier stands on its line; BalanceMove's shove drops off it.
func drop_offset() -> float:
	return 0.0

## Hook for a subclass that needs to know which way along the line the last tick
## travelled. LedgeWalkMove picks its sidestep clip off this; a beam does not
## care, since Walk is the clip either way.
## Test seam: sets what travelling() reports without running a physics tick.
func note_travel_for_test(along: float) -> void:
	_last_along = along
	note_travel(along)

## Whether the body actually moved along the line last tick. Read by
## CharacterAnimator: a beam standing still must not keep playing a walk cycle.
func travelling() -> bool:
	return absf(_last_along) > 0.1

## Signed travel from the last tick, in the body's own frame. Recorded for
## travelling() above; subclasses that need the direction override note_travel.
var _last_along: float = 0.0

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

# --- the capsule is not turned by this tier ----------------------------------
#
# The rest of the "along a line" family swings the collision body onto its line,
# and rightly: a hand or both hands are on the thing, so the whole body has to
# follow it. STANDING on a line is not that. The feet are what is on it, the
# shoulders are free, and the player is looking around with a mouse the whole
# time -- turning the capsule under them fights the one input they are actively
# using. Entering snapped the view a quarter turn, leaving snapped it back, and
# the snap on the way out could drop the body back inside the volume it had just
# walked out of.
#
# Only the MODEL is pinned, which is what freeze_visual_yaw already means
# everywhere else in this project: the capsule goes where the view goes, the
# model holds its own heading. Nothing else in this tier reads the capsule's yaw
# -- project_input() works in the LINE's frame, and the entry gate is a height
# test -- so letting it float costs nothing.

func _turn_body_to(yaw: float) -> void:
	player.pin_visual_yaw(yaw)

func _centre_fan() -> void:
	_fan_centred = true
	# The yaw fan still belongs to the line, so the reference is still handed
	# over; it is only the capsule that is left alone.
	if player.camera_rig != null:
		player.camera_rig.recentre_yaw_reference(_target_yaw)
	player.pin_visual_yaw(_target_yaw)
