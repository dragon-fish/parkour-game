class_name LadderMove
extends LineMove

# The original's TdMove_Ladder. [ME:INFERRED] Pipes and ladders are one
# mechanic with an authored FRONT (a ladder can only be entered from one
# side); entry is a frontal 180-degree fan (front half-space), open to
# airborne, grounded AND wallrunning bodies.
#
# PHYS_Flying, like the rest of the "along a line" family: the fade-in is a
# raw position write -- brushing geometry during the pull must not abort a
# catch the magnet exists to guarantee -- and only the steady climb
# afterward is collision-checked via slide_to(), because designers
# deliberately sink a ladder's ends into the floor and ceiling it passes
# through.

## Arc length along the line, metres. Read by the HUD/tests via
## climbing_offset().
var _offset: float = 0.0
## -1 (descending), 0 (still), +1 (ascending) -- what the last tick's W/S
## actually asked for; the animator picks Climb_Up/Down/Idle off it.
var _climb_dir: int = 0

## The top exit: a scripted carry off the top of the line onto a
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
## A fall stopped past hard_landing_height -- see HardCatch.
var _catch: HardCatch = HardCatch.new()
## Whether this tick's W/S is a climb the view is allowed to make -- held, and
## turned no further off the rungs than LadderConfig.climb_assist_angle_deg.
## Read by look_yaw_half_span(), which runs outside physics_update().
var _climb_wanted: bool = false

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
	_climb_wanted = false
	_aborted = not acquire_line(InterestLine.Kind.LADDER)
	if _aborted:
		return
	# Defensive, mirroring acquire_line()'s own reasoning: every entry site
	# (AirborneMove, WalkingMove, WallRunMove) already asks
	# front_side_allows() itself BEFORE ever transitioning here, so there is
	# no enter-then-abort flutter in practice -- this only guards the line
	# having moved (or the body having drifted) between that gate and this
	# tick.
	if not LadderMove.front_side_allows(_line, player.global_position, cfg.back_slack):
		_aborted = true
		return
	_catch.arm(player)
	# _offset tracks the HANDS' grip on the line, not the capsule centre --
	# see LadderConfig.hand_height.
	_offset = _line.closest_offset(player.global_position + Vector3.UP * cfg.hand_height)
	_climb_dir = 0
	# The body faces the ladder -- i.e. looks toward -front, the wall side.
	var f: Vector3 = _line.front()
	_target_yaw = atan2(f.x, f.z)
	player.velocity = Vector3.ZERO
	_fade = 0.0
	begin_approach()
	_entry_yaw = player.rotation.y
	_fan_centred = false

## THE ONE ENTRY GATE, static so AirborneMove/WalkingMove/WallRunMove ask
## the SAME question before ever transitioning (no enter-then-abort
## flutter). Three conditions, in order:
##   1. cooldown + latch (line_ready -- the latch's own push-toward bypass
##      lives there);
##   2. the ladder's front half-space;
##   3. the PLAYER's front 180 degrees -- [ME:INFERRED] a ladder outside the
##      player's view (roughly the forward 180 degrees) does not trigger
##      entry, no backing in.
## A body that passes 1-2 but fails 3 SPENDS the line's passive chance
## (Player.latch_line): turning around later must not auto-enter; walking
## back toward the rungs re-arms it through the bypass.
static func catch_gate(player: Player, line: InterestLine) -> bool:
	if not player.line_ready(line):
		return false
	if not front_side_allows(line, player.global_position, player.config.ladder.back_slack):
		return false
	if _faces_line(player, line):
		return true
	player.latch_line(line)
	return false

## Whether the line sits in the player's forward 180 degrees, judged on the
## camera look when there is one and the body facing otherwise.
static func _faces_line(player: Player, line: InterestLine) -> bool:
	var look: Vector3 = -player.global_transform.basis.z
	if player.camera_rig != null and player.camera_rig.camera != null:
		look = -player.camera_rig.camera.global_transform.basis.z
	look.y = 0.0
	if look.length_squared() < 0.0001:
		return true
	var at: Vector3 = line.sample(line.closest_offset(player.global_position))["position"]
	var toward := Vector3(at.x - player.global_position.x, 0.0, at.z - player.global_position.z)
	if toward.length_squared() < 0.0001:
		return true
	return look.normalized().dot(toward.normalized()) > 0.0

## The ladder's own front half-space -- see the spec's front 180-degree fan
## -- moved `back_slack` metres behind the line (LadderConfig.back_slack).
static func front_side_allows(line: InterestLine, body_pos: Vector3, back_slack: float) -> bool:
	var at: Vector3 = line.sample(line.closest_offset(body_pos))["position"]
	var to_body: Vector3 = body_pos - at
	to_body.y = 0.0
	return to_body.dot(line.front()) > -back_slack

func physics_update(delta: float, input: MoveInput) -> StringName:
	if _aborted or not is_instance_valid(_line):
		return FALLING
	# [ME:INFERRED] from play: a ladder counts as the run stopping dead. The
	# budget bleeds to nothing on the same curve every other loss uses, so a
	# catch let go of at once keeps a little and a climb keeps none.
	player.follow_speed(0.0, delta)
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
	# THE LOCKOUT IS THE PLAYER HAVING NO INPUT, expressed the way
	# FallUncontrolledMove expresses the same thing (it hands
	# apply_air_physics a bare Vector3.ZERO rather than reading a flag off
	# Player): a fresh MoveInput is neutral, so the crouch release, the whole
	# jump chain, the top exit and the climb itself are all refused at once
	# without any of them growing a gate of their own. The magnet fade and
	# slide_to() below still run, so the body finishes arriving at the hang
	# pose and then stays glued to it.
	if _catch.tick(player, delta):
		input = MoveInput.new()
	if input.crouch_pressed:
		# [ME:INFERRED] one press of a key corresponds to exactly one action
		# -- the same press that lets go must not also survive in the roll
		# buffer to fire a skill roll at whatever the fall turns out to be.
		player.consume_roll()
		return FALLING
	# The jump-off chain and the top exit both land here, ahead of the plain
	# climb below.
	if input.jump_pressed:
		# The scan only runs while a direction is actually HELD ([ME:INFERRED]
		# the spec's own rule). Plain space facing the ladder, with no A/D/S
		# down, is a no-op -- it must fall straight through to the look-jump
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
				return _launch_at(target)
		var turned: float = absf(wrapf(_camera_yaw() - _target_yaw, -PI, PI))
		if turned > deg_to_rad(cfg.jump_angle_deg):
			# GrabMove's shape verbatim: the look, nothing projected
			# out -- the into-wall component IS the vault tech (grab_move.gd
			# _launch_direction's own warning applies here unchanged).
			player.velocity = _look_direction() * cfg.jump_speed
			player.consume_roll()
			return FALLING
		# Facing the ladder, no target: the press is IGNORED ([ME:INFERRED]
		# A/D + space does not trigger a jump when there is no other ladder
		# to snap to).

	# W/S from here down is the CLIMB, and a view turned past the assist
	# angle refuses it -- top exit and bottom release included, since both are
	# the climb running out of rungs. The jump-off scan above reads the raw
	# keys on purpose: S+space aims straight back, which is exactly where a
	# refused climb is looking.
	_climb_wanted = absf(input.move.y) > 0.1 \
		and _turned_from_rungs() <= deg_to_rad(cfg.climb_assist_angle_deg)
	var climb: float = input.move.y if _climb_wanted else 0.0

	# The top exit MUST sit AFTER the jump chain above and BEFORE
	# the ordinary climb below -- PROTECTED INVARIANT #3: space
	# at the very top (a turned camera or a snap target) still beats the
	# scripted exit, exactly the way it does at every other height on the
	# line. Reaching here at all already means jump_pressed either was not
	# held or refused to fire above.
	if _offset >= _line.length() - 0.01 and climb > 0.0:
		var deck: Dictionary = _probe_top_deck()
		if deck.get("valid", false):
			return _begin_top_exit(deck["position"])
		# No deck within reach: W does nothing at the top. Falls through
		# to the ordinary climb below, which simply re-clamps _offset to
		# the value it already has.

	# Bottom-end release (spec section on climbing: at the bottom end, still
	# holding S releases the grip and the body falls normally). No
	# consume_roll() here, unlike the crouch-release above -- this is a held
	# key crossing the bottom, not a discrete press, so there is no buffered
	# roll press to guard against re-firing.
	if _offset <= 0.01 and climb < 0.0:
		return FALLING

	_climb_dir = int(signf(climb))
	_offset = clampf(_offset + climb * cfg.climb_speed * delta, 0.0, _line.length())
	var s: Dictionary = _line.sample(_offset)
	var hang: Vector3 = s["position"] - Vector3.UP * cfg.hand_height \
		+ _line.front() * cfg.stand_off
	_fade += delta
	var _over := approach_seconds(hang)
	if _fade < _over:
		# The magnet's own pull stays a direct write, not collision-checked
		# -- see this file's header note.
		var t: float = _fade / _over
		player.global_position = _entry_pos.lerp(hang, t)
		_turn_body_to(lerp_angle(_entry_yaw, _target_yaw, t))
	else:
		var hit: KinematicCollision3D = slide_to(hang)
		if hit != null:
			# Descending into the floor IS the bottom -- the next tick lands
			# and grounds normally.
			if climb < 0.0 and hit.get_normal().y > 0.5:
				return FALLING
			# A ceiling (or anything else in the way): stay on the ladder
			# rather than fight the geometry. Re-derive _offset from where
			# the body actually ended up, so the next tick's climb continues
			# from the true, blocked position instead of the one that just
			# got refused.
			_offset = _line.closest_offset(player.global_position
			+ Vector3.UP * cfg.hand_height - _line.front() * cfg.stand_off)
		if not _fan_centred:
			_centre_fan()
	return KEEP

func exit() -> void:
	# until_exit: a ladder is ground-enterable, so a released body can just
	# STAND in the volume -- the latch stops the auto re-grab, and pushing
	# toward the rungs ([ME:INFERRED] the original's own rule, including a
	# save-yourself glitch) lifts it. See Player.line_ready().
	note_left(cfg.same_line_redo_time, true)
	# Unconditional, mirroring GrabMove.exit()'s own reset of the same field:
	# asking for the clip's hip-lift back when it was never cancelled costs
	# nothing, and a carry cut short by something else grabbing the body
	# still needs the gate released.
	player.set_clip_lift_cancelled(false)
	_catch.clear(player)

## THE CLIMB ASSIST, and narrowing the fan is the whole of it -- GrabMove's
## shimmy assist, for the same reason: CameraRig eases a fan edge in to meet a
## view outside it, so the view walks back to the rungs at the camera's own
## rate. Let go and the wide fan returns with the view left where it was
## brought. The top exit's carry keeps whatever the W that started it asked.
func look_yaw_half_span() -> float:
	if _climb_wanted:
		return deg_to_rad(cfg.climb_look_yaw_deg)
	return NAN

## How far the view has turned off the rungs, radians: 0 facing them, PI with
## the back to them. The body's yaw IS the view's here -- the absolute-yaw
## clamp rebuilds it every tick from the fan -- and _target_yaw is the facing
## squared to the ladder.
func _turned_from_rungs() -> float:
	return absf(wrapf(player.rotation.y - _target_yaw, -PI, PI))

## Arc length along the line, metres. Read by the HUD and by tests.
func climbing_offset() -> float:
	return _offset

## Whether the top-exit scripted carry is under way. Exposed for the
## same reason GrabMove.is_mantling() is: CharacterAnimator asks from outside
## rather than LadderMove pushing an event in.
## F12's scripted-path overlay duck-types this (scripted_path_debug.gd). The
## carry is composed, not inherited, so path_debug() and sample() MUST
## delegate to `_top_exit` below or the overlay's is-a assumption leaves the
## carry invisible to it. Shows the leg currently playing.
func path_debug() -> Dictionary:
	return _top_exit.path_debug() if _top_exiting else {}

func sample(t: float) -> Vector3:
	return _top_exit.sample(t)

func climb_direction() -> int:
	return _climb_dir

## The scripted-fit hook (CharacterAnimator._scripted_fit): during the top
## exit the carry IS a scripted phase, so ClimbUp_1m stretches to end
## exactly when the carry does, whatever top_exit_time is set to. Zero
## outside the phase -- no fit.
func scripted_duration() -> float:
	return _top_exit.scripted_duration() if _top_exiting else 0.0

func is_top_exiting() -> bool:
	return _top_exiting

## Which ladder a directional jump-off (AD+space) would snap to instead of
## just launching off this one, or null when there is nothing to snap to.
##
## Direction lives entirely in the LADDER's own frame -- no aiming needed --
## side -1/+1 run along front x up, side 0 means straight back off the
## ladder. No camera read anywhere in here.
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
	# gives dir = (-X) * (-1) = +X, the climber's LEFT. DO NOT flip the sign
	# to `* -float(side)` -- that sends A (side -1) to -X instead, the
	# climber's RIGHT, inverting the mapping. See tests/test_ladder_move.gd
	# for the geometry behind this.
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

## Where a jump off the ladder launches: along the view, never flatter than
## LadderConfig.jump_min_pitch_deg -- GrabMove._launch_direction() and its
## reasons, into-wall component included. The same speedrun glitch this move's
## jump_angle_deg threshold opens the door to (turning just past 45 degrees
## throws the body at the ladder's own geometry) depends on it here too.
func _look_direction() -> Vector3:
	var look: Vector3 = Vector3.ZERO
	if player.camera_rig != null and player.camera_rig.camera != null:
		look = -player.camera_rig.camera.global_transform.basis.z
	return GrabMove.launch_along(look, [-player.global_transform.basis.z, -_line.front()],
		cfg.jump_min_pitch_deg)

# --- The top exit ----------------------------------------------------------

## How far above the candidate landing the deck probe starts, metres.
const TOP_DECK_PROBE_LIFT := 0.5
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
## Candidate = top + (-front()) * top_exit_reach, ray from half a metre
## above it, downward. Valid only on a near-flat surface
## (normal.y > TOP_DECK_NORMAL_MIN) with room for a standing body --
## player.fits_standing_at(), the same shapecast GrabMove's own mantle gate
## asks of its landing.
## NEAR TO FAR, first standable point wins. DO NOT collapse this scan back
## to a single fixed-distance candidate -- a single top_exit_reach behind
## the top visibly sends the player too far back from the deck. A cap
## block or small step on the lip is landed ON when the capsule fits there
## -- a < step's worth of rise IS the walkway -- and stepped past otherwise.
const TOP_DECK_SCAN_START := 0.35
const TOP_DECK_SCAN_STEP := 0.15

func _probe_top_deck() -> Dictionary:
	var top: Vector3 = _line.sample(_line.length())["position"]
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	if space == null:
		return {}
	var d: float = TOP_DECK_SCAN_START
	while d <= cfg.top_exit_reach + 0.001:
		var found: Dictionary = _standable_at(space, top - _line.front() * d)
		if found.get("valid", false):
			return found
		d += TOP_DECK_SCAN_STEP
	return {}

func _standable_at(space: PhysicsDirectSpaceState3D, candidate: Vector3) -> Dictionary:
	var from: Vector3 = candidate + Vector3.UP * TOP_DECK_PROBE_LIFT
	var to: Vector3 = candidate - Vector3.UP * cfg.top_exit_max_drop
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
	# A BEZIER, like every scripted carry (sample()'s one rule): the apex is
	# lifted top_exit_apex_lift above the landing so the capsule arcs OVER
	# the deck lip instead of cutting its corner and clipping through it.
	# The solved control height puts the curve's true peak exactly there.
	_top_exit.begin(player.global_position, landing, cfg.top_exit_time,
		landing.y + cfg.top_exit_apex_lift, cfg.top_exit_control_bias)
	_top_exiting = true
	# The carry plays ClimbUp_1m (CharacterAnimator._route()'s
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
