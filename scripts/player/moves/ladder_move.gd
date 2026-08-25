class_name LadderMove
extends LineMove

# The original's TdMove_Ladder. ✅ The owner: pipes and ladders are one
# mechanic with an authored FRONT ("梯子只有一面可以进入"); entry is a
# frontal 180-degree fan (front half-space), open to airborne, grounded AND
# wallrunning bodies.
#
# PHYS_Flying, like the rest of the "along a line" family: the fade-in is a
# raw position write (Task 3's ruling -- brushing geometry during the pull
# must not abort a catch the magnet exists to guarantee), and only the
# steady climb afterward is collision-checked via slide_to(), because
# designers deliberately sink a ladder's ends into the floor and ceiling it
# passes through.

## Arc length along the line, metres. Read by the HUD/tests via
## climbing_offset().
var _offset: float = 0.0

## Task 7's top exit: a scripted carry off the top of the line onto a
## standable deck behind it, driven by a COMPOSED ScriptedMove rather than an
## inherited one. LadderMove already extends LineMove for the family's shared
## skeleton (acquire_line/slide_to/note_left/...), and GDScript has no
## multiple inheritance -- ZiplineMove documents the same fork the other way
## (its own header: "NOT A ScriptedMove"). A bare instance, never added to
## the scene tree, is enough: begin()/advance()/sample() only ever touch
## `player`, which is handed across the moment the carry starts.
var _top_exit: ScriptedMove = ScriptedMove.new()
## True for the duration of the scripted carry. Checked FIRST in
## physics_update(), mirroring GrabMove's own _mantling gate: once the carry
## has begun, nothing below it -- crouch, jump, the ordinary climb -- may run
## until it completes. Input is committed the instant the carry starts.
var _top_exiting: bool = false

## PARENTED, not left loose: Move.gd's own _ready() sets _tick_travel (unused
## here, but calling super keeps this move honest about the base contract),
## and adding `_top_exit` as a child here is what gives it a lifetime tied to
## this move's own instead of leaking an un-freed Node every time a Player is
## torn down (tests build and tear down a fresh one per case).
func _ready() -> void:
	super._ready()
	add_child(_top_exit)

func enter(_previous: StringName) -> void:
	player.set_grounded(false)
	# Defensive, mirroring GrabMove's own `_mantling = false` reset in its
	# enter(): a completed carry already clears this on its way to WALKING,
	# so nothing today re-enters LADDER with it still true, but a fresh catch
	# has no business starting mid-carry either way.
	_top_exiting = false
	_aborted = not acquire_line(InterestLine.Kind.LADDER)
	if _aborted:
		return
	# Defensive, mirroring acquire_line()'s own reasoning: every entry site
	# (AirborneMove, WalkingMove, WallRunMove) already asks
	# front_side_allows() itself BEFORE ever transitioning here, so there is
	# no enter-then-abort flutter in practice -- this only guards the line
	# having moved (or the body having drifted) between that gate and this
	# tick.
	if not LadderMove.front_side_allows(_line, player.global_position):
		_aborted = true
		return
	_offset = _line.closest_offset(player.global_position)
	# The body faces the ladder -- i.e. looks toward -front, the wall side.
	var f: Vector3 = _line.front()
	_target_yaw = atan2(f.x, f.z)
	player.velocity = Vector3.ZERO
	_fade = 0.0
	_entry_pos = player.global_position
	_entry_yaw = player.rotation.y
	_fan_centred = false

## The frontal gate, static so AirborneMove/WalkingMove/WallRunMove ask the
## SAME question before ever transitioning (no enter-then-abort flutter).
static func front_side_allows(line: InterestLine, body_pos: Vector3) -> bool:
	var at: Vector3 = line.sample(line.closest_offset(body_pos))["position"]
	var to_body: Vector3 = body_pos - at
	to_body.y = 0.0
	return to_body.dot(line.front()) > 0.0

func physics_update(delta: float, input: MoveInput) -> StringName:
	if _aborted or not is_instance_valid(_line):
		return FALLING
	if _top_exiting:
		if _top_exit.advance(delta):
			_top_exiting = false
			# A carry, not a launch -- the body was set down, not thrown.
			# Deliberately NOT declared grounded here, matching GrabMove's own
			# mantle hand-off: the landing point came from a probe this move
			# trusts but never collision-checked against the capsule's actual
			# path, so WalkingMove's own next floor-snap tick is what first
			# verifies it for real (see WalkingMove.physics_update()'s note on
			# exactly this hand-off).
			player.velocity = Vector3.ZERO
			return WALKING
		return KEEP
	player.set_grounded(false)
	# The rungs support the body the way the ground does -- the fall the
	# landing charges for starts where the hands let go, same rule the rest
	# of the family settled on.
	player.fall_tracker.reset(player.global_position.y)
	if input.crouch_pressed:
		# ✅ THE OWNER: "在ME里按一次按键只对应一次动作" -- the same press
		# that lets go must not also survive in the roll buffer to fire a
		# skill roll at whatever the fall turns out to be.
		player.consume_roll()
		return FALLING
	# The jump-off chain (Task 5) and the top exit (Task 7) both land here,
	# ahead of the plain climb below.
	if input.jump_pressed:
		# The scan only runs while a direction is actually HELD (✅ the owner's
		# spec: "方向键按着"). Plain space facing the ladder, with no A/D/S
		# down, is 无操作 -- it must fall straight through to the look-jump
		# check below (and from there, most likely, to the ignore case) rather
		# than being read as an implicit "scan straight back" with side 0.
		var wants_scan: bool = absf(input.move.x) > 0.1 or input.move.y < -0.1
		if wants_scan:
			var side: int = 0
			if absf(input.move.x) > 0.1:
				side = 1 if input.move.x > 0.0 else -1
			# side stays 0 here only for the S-held, no-A/D case -- the
			# straight-back scan _scan_snap_target(0) already covers.
			var target: InterestLine = _scan_snap_target(side)
			if target != null:
				return _launch_at(target)  # Task 6
		var turned: float = absf(wrapf(_camera_yaw() - _target_yaw, -PI, PI))
		if turned > deg_to_rad(cfg.jump_angle_deg):
			# GrabMove's shape verbatim: the full 3D look, nothing projected
			# out -- the into-wall component IS the vault tech (grab_move.gd
			# _launch_direction's own warning applies here unchanged).
			player.velocity = _look_direction() * cfg.jump_speed
			player.consume_roll()
			return FALLING
		# Facing the ladder, no target: the press is IGNORED (✅ the owner:
		# "AD+空格如果没有其他梯子是不会触发跳的").

	# The top exit (Task 7). MUST sit AFTER the jump chain above and BEFORE
	# the ordinary climb below -- 🔒 protected technique, invariant #3: space
	# at the very top (a turned camera or a snap target) still beats the
	# scripted exit, exactly the way it does at every other height on the
	# line. Reaching here at all already means jump_pressed either was not
	# held or refused to fire above.
	if _offset >= _line.length() - 0.01 and input.move.y > 0.0:
		var deck: Dictionary = _probe_top_deck()
		if deck.get("valid", false):
			return _begin_top_exit(deck["position"])
		# No deck within reach: W does nothing at the top (✅ the owner).
		# Falls through to the ordinary climb below, which simply re-clamps
		# _offset to the value it already has.

	# Bottom-end release (spec §攀爬: "底端 + 仍按 S：松手，正常下落"). No
	# consume_roll() here, unlike the crouch-release above -- this is a held
	# key crossing the bottom, not a discrete press, so there is no buffered
	# roll press to guard against re-firing.
	if _offset <= 0.01 and input.move.y < 0.0:
		return FALLING

	_offset = clampf(_offset + input.move.y * cfg.climb_speed * delta, 0.0, _line.length())
	var s: Dictionary = _line.sample(_offset)
	var hang: Vector3 = s["position"] + _line.front() * cfg.stand_off
	_fade += delta
	if _fade < cfg.fade_in_time:
		# ✅ TASK 3'S RULING: the magnet's own pull stays a direct write, not
		# collision-checked -- see this file's header note.
		var t: float = _fade / cfg.fade_in_time
		player.global_position = _entry_pos.lerp(hang, t)
		_turn_body_to(lerp_angle(_entry_yaw, _target_yaw, t))
	else:
		var hit: KinematicCollision3D = slide_to(hang)
		if hit != null:
			# ✅ THE OWNER: descending into the floor IS the bottom -- the
			# next tick lands and grounds normally.
			if input.move.y < 0.0 and hit.get_normal().y > 0.5:
				return FALLING
			# A ceiling (or anything else in the way): stay on the ladder
			# rather than fight the geometry. Re-derive _offset from where
			# the body actually ended up, so the next tick's climb continues
			# from the true, blocked position instead of the one that just
			# got refused.
			_offset = _line.closest_offset(player.global_position - _line.front() * cfg.stand_off)
		if not _fan_centred:
			_centre_fan()
	return KEEP

func exit() -> void:
	note_left(cfg.same_line_redo_time)
	# Unconditional, mirroring GrabMove.exit()'s own reset of the same field:
	# asking for the clip's hip-lift back when it was never cancelled costs
	# nothing, and a carry cut short by something else grabbing the body
	# still needs the gate released.
	player.set_clip_lift_cancelled(false)

## Arc length along the line, metres. Read by the HUD and by tests.
func climbing_offset() -> float:
	return _offset

## Whether the top-exit scripted carry (Task 7) is under way. Exposed for the
## same reason GrabMove.is_mantling() is: CharacterAnimator asks from outside
## rather than LadderMove pushing an event in.
func is_top_exiting() -> bool:
	return _top_exiting

## Which ladder a directional jump-off (AD+space) would snap to instead of
## just launching off this one, or null when there is nothing to snap to.
##
## Direction lives entirely in the LADDER's own frame (✅ the owner: no
## aiming needed) -- side -1/+1 run along front x up, side 0 means straight
## back off the ladder. No camera read anywhere in here.
func _scan_snap_target(side: int) -> InterestLine:
	var f: Vector3 = _line.front()
	# side -1 (A) must scan toward the CLIMBER'S OWN LEFT, +1 (D) toward their
	# right. The climber FACES -f (see enter()'s own note), and for any
	# forward direction "left = UP.cross(forward)", so the climber's left is
	# UP.cross(-f) = -UP.cross(f) and their right is the negation of that,
	# UP.cross(f). dir(side) = UP.cross(f) * side therefore lands on the
	# climber's right at side +1 (D) and their left at side -1 (A), exactly
	# as wanted.
	#
	# Worked out concretely for a yaw-0 ladder (f = -Z, so the climber faces
	# +Z): UP.cross(f) = (0,1,0) x (0,0,-1) = (-1,0,0) = -X -- the climber's
	# RIGHT, confirmed against "forward.cross(up) = right" applied to their
	# own +Z facing: (0,0,1) x (0,1,0) = (-1,0,0), the same -X. So side=-1 (A)
	# gives dir = (-X) * (-1) = +X, the climber's LEFT. The previous
	# `* -float(side)` sent A to -X instead -- the climber's RIGHT, inverted.
	# See tests/test_ladder_move.gd's own Task 6 header for the geometry this
	# fixes.
	var dir: Vector3 = f if side == 0 else Vector3.UP.cross(f) * float(side)
	var best: InterestLine = null
	var best_d: float = cfg.snap_range
	for node in player.get_tree().get_nodes_in_group("interest_lines"):
		var line := node as InterestLine
		if line == null or line == _line or not player.line_ready(line):
			continue
		var at: Vector3 = line.sample(line.closest_offset(player.global_position))["position"]
		var to: Vector3 = at - player.global_position
		var d: float = to.length()
		if d > best_d or d < 0.001:
			continue
		if to.normalized().dot(dir) < cfg.snap_cone_dot:
			continue
		best_d = d
		best = line
	return best

## Flies the body onto `target` (a directional snap-jump). Ballistic through
## the target's own catch volume: given a fixed flight time, solve v0 so the
## arc passes the line's nearest point -- the target's own catch logic
## (AirborneMove's probes) does the rest, so this places NOTHING by hand.
func _launch_at(target: InterestLine) -> StringName:
	var at: Vector3 = target.sample(target.closest_offset(player.global_position))["position"]
	var t: float = cfg.snap_flight_time
	var g: float = player.effective_gravity()
	player.velocity = (at - player.global_position) / t + Vector3.UP * (0.5 * g * t)
	player.consume_roll()
	return FALLING

## Yaw of the camera's look direction, radians. Mirrors GrabMove's own camera
## read (grab_move.gd _launch_direction()): the rig's camera when there is
## one, falling back to the body's own facing when there is not (a stub
## player in a test, or no rig at all).
func _camera_yaw() -> float:
	var look: Vector3 = Vector3.ZERO
	if player.camera_rig != null and player.camera_rig.camera != null:
		look = -player.camera_rig.camera.global_transform.basis.z
	if look.length_squared() < 0.0001:
		look = -player.global_transform.basis.z
	if look.length_squared() < 0.0001:
		return _target_yaw
	# Facing direction d means yaw = atan2(-d.x, -d.z) -- same convention
	# _target_yaw above is built with (see InterestLine.front()'s callers).
	return atan2(-look.x, -look.z)

## Where a jump off the ladder launches: along the VIEW, wall included.
##
## ⚠️ COPIES GrabMove._launch_direction() ON PURPOSE, into-wall component and
## all -- see that function's own long comment for why nothing gets projected
## out of it. The same speedrun glitch this move's jump_angle_deg threshold
## opens the door to (turning just past 45 degrees throws the body at the
## ladder's own geometry) depends on the component surviving here too.
func _look_direction() -> Vector3:
	var look: Vector3 = Vector3.ZERO
	if player.camera_rig != null and player.camera_rig.camera != null:
		look = -player.camera_rig.camera.global_transform.basis.z
	if look.length_squared() < 0.0001:
		look = -player.global_transform.basis.z
	if look.length_squared() < 0.0001:
		return -_line.front()
	return look.normalized()

# --- Task 7: the top exit -------------------------------------------------

## How far above the candidate landing the deck probe starts, metres.
const TOP_DECK_PROBE_LIFT := 0.5
## How far below the candidate landing the probe still reaches, metres --
## clears a deck sitting a little off the line's own top height without
## reaching so far down it could find the ladder's own lower rungs instead.
const TOP_DECK_PROBE_DEPTH := 0.5
## Largest tilt a hit surface may have and still count as a deck to stand on.
## Same shape as every other "is this walkable" gate in the project (see
## Probes.walkable_floor_z and friends) -- a knob of its own rather than a
## shared constant, since this probe is not Probes' own and answers to no
## config field the panel exposes today.
const TOP_DECK_NORMAL_MIN := 0.7

## Where a top exit would carry the body, or an empty dictionary when there is
## nowhere to stand. Fired from `_line`'s own top point, offset
## `top_exit_reach` back along -front() -- the wall side, opposite the
## frontal entry fan -- straight down onto whatever is there.
##
## ✅ THE SPEC, verbatim: candidate = top + (-front()) * top_exit_reach, ray
## from half a metre above it, downward. Valid only on a near-flat surface
## (normal.y > TOP_DECK_NORMAL_MIN) with room for a standing body --
## player.fits_standing_at(), the same shapecast GrabMove's own mantle gate
## asks of its landing.
func _probe_top_deck() -> Dictionary:
	var top: Vector3 = _line.sample(_line.length())["position"]
	var candidate: Vector3 = top - _line.front() * cfg.top_exit_reach
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	if space == null:
		return {}
	var from: Vector3 = candidate + Vector3.UP * TOP_DECK_PROBE_LIFT
	var to: Vector3 = candidate - Vector3.UP * TOP_DECK_PROBE_DEPTH
	var query := PhysicsRayQueryParameters3D.create(from, to)
	# Same idioms Probes._cast() uses (see probes.gd): a ray that starts
	# inside a shape reports nothing at all without this, and the player's
	# own capsule must never be what the ray finds.
	query.hit_from_inside = true
	if player is CollisionObject3D:
		query.exclude = [(player as CollisionObject3D).get_rid()]
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return {}
	var normal: Vector3 = hit.get("normal", Vector3.ZERO)
	if normal.y <= TOP_DECK_NORMAL_MIN:
		return {}
	var position: Vector3 = hit["position"]
	if not player.fits_standing_at(position):
		return {}
	return {"valid": true, "position": position}

## Starts the scripted carry onto `deck_position` (a FEET point, the same
## shape _probe_top_deck() hands fits_standing_at()). The destination for the
## capsule's own CENTRE is standing_height() * 0.5 above it -- GrabMove's
## mantle destination, read the same way (grab_move.gd's own `top := _edge +
## Vector3(0, standing_height() * 0.5, 0)`), minus the extra forward push
## that move adds afterward: this probe already planted its candidate
## top_exit_reach past the line's top, so the landing needs no further shove.
func _begin_top_exit(deck_position: Vector3) -> StringName:
	var landing: Vector3 = deck_position + Vector3.UP * (player.standing_height() * 0.5)
	_top_exit.player = player
	_top_exit.begin(player.global_position, landing, cfg.top_exit_time)
	_top_exiting = true
	# ✅ THE SPEC: the carry plays ClimbUp_1m (CharacterAnimator._route()'s
	# Move.LADDER arm). The scripted arc already supplies the whole vertical
	# travel, so the clip's own baked hip-lift must not stack on top of it --
	# the SAME gate GrabMove arms right before `_mantling = true`
	# (grab_move.gd, next to its own ClimbUp_2m note). Released in exit().
	player.set_clip_lift_cancelled(true)
	return KEEP

## The fallback camera rise for a bare capsule with no head bone to follow --
## see ScriptedMove.camera_lift() for what this is and why it is a fallback
## only. Player._scripted_camera_lift() reads this by duck-typing
## (`move.has_method("camera_lift")`) off whatever move_for(current_name)
## returns, which for LADDER is this move itself, not the composed
## `_top_exit` -- so this delegates rather than being picked up for free the
## way GrabMove's own (inherited) camera_lift() is.
func camera_lift() -> float:
	return _top_exit.camera_lift() if _top_exiting else 0.0
