class_name Turn180Move
extends Move

# Q: spin to face the other way. The original's TdMove_180Turn.
#
# Q WORKS ALMOST EVERYWHERE -- anywhere the legs are not tied up, like a 180
# while walking, or a 90 while wall running. The entry lives in MoveManager,
# gated by MoveConfig.allows_turn, so this move has to make sense from the
# ground as well as off a wall.
#
# ONE RULE COVERS BOTH WALL CASES, and the two different angles the owner named
# fall out of it rather than being written down: on a wall, turn to face along
# the wall's NORMAL, i.e. squarely away from it.
#
#   * wall running   you were facing ALONG the wall, so that is a quarter turn
#   * wall climbing  you were facing INTO it, so that is a half turn
#
# Off a wall there is no normal to face, and a half turn is the only thing Q
# can mean.
#
# THE HANG IS ONLY A WALL THING. DisableMovementTime -- a real field across the
# original's move library that this project had never implemented -- freezes
# the body so the turn becomes a decision point: kick off, or drop. On the
# ground there is nothing to kick off and nothing to decide, so a ground turn
# simply carries its momentum through the spin.

## Below this a body is not "going forward", it is drifting: a standing jump
## has a few centimetres a second of its own. Not a speed gate -- any real
## forward jump clears it many times over.
const FORWARD_TRAVEL_M_S := 0.5

var _elapsed: float = 0.0
var _turn_from: float = 0.0
var _turn_to: float = 0.0
## The wall's outward normal, or ZERO when this turn did not come off a wall.
## Decides everything that differs between the two cases: the angle, the hang,
## and whether space does anything.
var _normal: Vector3 = Vector3.ZERO
## The scripted facing already handed to the camera, so each tick reports only
## its own slice of the turn rather than the whole of it so far.
var _placed: float = 0.0
## Space pressed while the body is still coming round. HELD, not acted on.
##
## [ME:CONFIRMED] The original PRE-BUFFERS this: pressing space before the
## view has finished turning still fires the jump the instant the turn
## completes. Acted on immediately instead, a kick taken mid-turn would leave
## along a facing halfway between where you were and where you were going --
## and since the whole point of the turn is to choose a direction, that is
## the one outcome nobody wants.
var _kick_armed: bool = false
## The wall was AHEAD: this is a climb's turn, and it leaves by the
## original's TdMove_WallClimb180TurnJump rather than its wall kick.
var _from_climb: bool = false
## The horizontal velocity the turn began with. A ground turn bleeds this to
## nothing across slowdown_time rather than dropping it on the spot; a turn in
## mid-air keeps it.
var _entry_velocity: Vector3 = Vector3.ZERO
## Whether this turn was taken in mid-air, off no wall.
var _in_air: bool = false

## Whichever wall the body is on, checked on the entry tick while the body is
## still facing the way it was -- a moment later it has come round and neither
## probe can see anything.
##
## Both probes, because the two moves that lead here find their walls with
## different ones: a climb is on the wall AHEAD, a run is on one BESIDE.
## Deliberately does NOT go through approach_direction(). That reports where
## the body is HEADING, and by the time Q is pressed part-way up a climb the
## answer is nowhere -- the wall took the run-up's momentum on contact and the
## climb's friction finished it off. A turn asked for at exactly the moment it
## is most useful would then find no wall and fall out of the air.
##
## The rays do not need a heading anyway: they fire along the body's own facing.
## Only `incidence` is measured against a heading, and nothing here reads it.
func _find_wall() -> Vector3:
	_from_climb = false
	if player.probes == null:
		return Vector3.ZERO
	var facing: Vector3 = -player.global_transform.basis.z
	facing.y = 0.0
	var ahead: Dictionary = player.probes.wall_ahead_query(facing.normalized())
	if ahead["valid"]:
		_from_climb = true
		return ahead["normal"]
	var beside: Dictionary = player.probes.wall_query(facing.normalized())
	if beside["valid"]:
		return beside["normal"]
	return Vector3.ZERO

func on_a_wall() -> bool:
	return _normal != Vector3.ZERO

func enter(_previous: StringName) -> void:
	_elapsed = 0.0
	_kick_armed = false
	_in_air = false
	_entry_velocity = Vector3(player.velocity.x, 0.0, player.velocity.z)
	_normal = _find_wall()
	_normal.y = 0.0

	_turn_from = player.rotation.y
	_placed = _turn_from
	# ALWAYS CLOCKWISE, AND ALWAYS EXACTLY HALF A TURN.
	#
	# [ME:CONFIRMED] Faith only ever turns right in the original.
	# Godot's yaw grows counter-clockwise seen from above, so clockwise is the
	# negative direction.
	#
	# DO NOT turn toward whichever side the entry lean favours instead of
	# always clockwise -- that makes the direction a function of the entry
	# angle, and leaves it a coin flip on float noise for the head-on
	# approach the move is mostly used for.
	#
	# Half a turn EXACTLY, rather than turning to square up with the wall: come
	# in crooked and you leave crooked, which is what the original does and what
	# the name of the move says. The kick that follows is square regardless --
	# it reads the wall's own normal, not the facing.
	_turn_to = _turn_from - PI
	if on_a_wall():
		_normal = _normal.normalized()
		# Frozen outright rather than decayed. DisableMovementTime makes the
		# body not subject to gravity; a body still carrying its climb would
		# leave the window before it ended.
		player.velocity = Vector3.ZERO
		player.set_grounded(false)
	else:
		# [ME:CONFIRMED] A ground turn does not keep the whole speed budget. It
		# keeps enough for about 19 km/h -- consistent with being able to get
		# back to 18-19 quickly and then accelerate at ordinary running pace
		# beyond it.
		var ceiling: float = SpeedEnergy.energy_for_speed(config.pawn, cfg.speed_keep_ceiling)
		player.speed_energy.energy = minf(player.speed_energy.energy, ceiling)
		player.set_grounded(player.is_on_floor())
		# Turned round in the air while travelling the way it WAS facing: the
		# flight ends on the body's back. See Player.pending_back_landing.
		#
		# "In the air" is the MOVE it came from, not this tick's floor test: a
		# walking body is off the floor for a tick at every kerb and stair
		# nosing, and a Q pressed on one of those put it on its back.
		var was_facing := Vector3(-sin(_turn_from), 0.0, -cos(_turn_from))
		var flying: bool = player.move_manager != null and player.move_manager.move_for(_previous) is AirborneMove
		_in_air = flying and not player.grounded
		if _in_air and _entry_velocity.dot(was_facing) > FORWARD_TRAVEL_M_S:
			player.pending_back_landing = true
		# [ME:INFERRED] from play: after a turn in mid-air the keys do nothing
		# until touchdown, as in an uncontrolled fall or a soft landing. The
		# flight keeps what it had. See Player.air_turn_locked.
		if _in_air:
			player.air_turn_locked = true

func physics_update(delta: float, _input: MoveInput) -> StringName:
	_elapsed += delta
	_advance_turn(delta)

	if on_a_wall():
		# [ME:CONFIRMED 04] TdMove_WallKick, folded in here rather than kept as
		# its own state -- see Turn180Config's own note on why.
		#
		# ARMED HERE, FIRED BELOW. The press is remembered rather than acted on,
		# so a player who presses space while the body is still coming round
		# leaves at the facing the turn was FOR rather than at some halfway
		# angle. See _kick_armed.
		if player.consume_buffered_jump():
			_kick_armed = true
		if _kick_armed and _turn_finished():
			if _from_climb:
				player.velocity = _normal * cfg.climb_jump_push_away_speed
				player.velocity.y = sqrt(2.0 * config.pawn.gravity * cfg.climb_jump_off_z_height)
			else:
				player.velocity = _normal * cfg.wall_kick_speed_out
				player.velocity.y = cfg.wall_kick_speed_up
			player.move_and_slide()
			player.set_grounded(player.is_on_floor())
			return JUMP
		player.set_grounded(false)
		if cfg.no_gravity_for_the_whole_turn and not _turn_finished():
			# Held in place: no gravity, no input, no drift.
			#
			# [ME:CONFIRMED] The hang lasts for the whole ANIMATION -- there is
			# almost no falling during the wall-climb turn -- not for
			# DisableMovementTime. DO NOT read DisableMovementTime as covering
			# the whole hang: that field names how long input is disabled and
			# says nothing about gravity. See Turn180Config.
			return KEEP
		# The freeze is over but the OPPORTUNITY is not. These were one number
		# to begin with. DO NOT collapse them back into one by enlarging
		# DisableMovementTime (a confirmed original value) -- the kick window
		# must stay open long enough to reliably chain a kick after Q, which
		# the freeze alone is too short for. Gravity comes back here; the kick
		# stays available until kick_window. See Turn180Config for why
		# splitting them is the fix.
		player.velocity.y -= config.pawn.gravity * cfg.falling_gravity_scale * delta
		player.move_and_slide()
		player.set_grounded(player.is_on_floor())
		if player.grounded:
			return WALKING
		if _elapsed >= cfg.kick_window:
			return FALLING
		return KEEP

	# On the ground, or in the air off no wall at all.
	#
	# [ME:INFERRED] THE BODY DOES NOT STOP DEAD. Speed bleeds to nothing across
	# slowdown_time, so the old direction's momentum is still carrying you while
	# you come round, matching how the original feels. DO NOT keep the
	# momentum outright instead of bleeding it -- what makes Q pressable is
	# that the stop is GRADUAL, not that there is none.
	#
	# IN THE AIR THERE IS NOTHING TO BLEED IT INTO. The bleed is feet on the
	# floor; a turn in mid-air keeps its flight whole, which is what makes a
	# jump-and-turn a way to land facing back the way you came.
	var remaining: float = 1.0 if _in_air \
		else 1.0 - clampf(_elapsed / maxf(cfg.slowdown_time, 0.001), 0.0, 1.0)
	player.velocity.x = _entry_velocity.x * remaining
	player.velocity.z = _entry_velocity.z * remaining
	player.velocity.y -= config.pawn.gravity * delta
	var arriving: Vector3 = player.velocity
	player.move_and_slide()
	# A TURN IN THE AIR THAT TOUCHES DOWN MID-SPIN IS STILL A LANDING, and
	# FallingMove is what settles one -- the fall's height, its damage, the
	# back landing. Handled here instead it skipped all of it: a drop past
	# hard_landing_height, turned late, cost nothing.
	#
	# The spin is finished on the spot rather than cut, and the body is NOT
	# declared grounded: that would re-base the fall counter before the landing
	# reads it. The velocity the floor took is handed back so the landing
	# still sees what it arrived with.
	if _in_air and player.is_on_floor():
		_elapsed = maxf(_elapsed, _duration())
		_advance_turn(0.0)
		player.velocity = arriving
		player.set_grounded(false)
		return FALLING
	player.set_grounded(player.is_on_floor())
	if not _turn_finished():
		return KEEP
	return WALKING if player.grounded else FALLING

## Carries the body a slice of the way round, and tells the camera how far it
## moved.
##
## By absolute progress through turn_time rather than a per-tick rate, so the
## turn lands on exactly the target and the camera is handed a series of small
## even deltas instead of one lump. See docs/camera-authority.md: the body is
## being moved BY A SCRIPT, so the eye trails it and eases in.
## How long this turn takes. [ME:CONFIRMED] Two measured figures, not one: a
## ground turn is 0.3 s and a wall turn 0.5 s.
func _duration() -> float:
	return cfg.wall_turn_time if on_a_wall() else cfg.turn_time

## Whether the body has finished coming round. The armed kick waits for this,
## and so does the wall turn's gravity.
func _turn_finished() -> bool:
	return _elapsed >= _duration()

func _advance_turn(_delta: float) -> void:
	var progress: float = clampf(_elapsed / maxf(_duration(), 0.001), 0.0, 1.0)
	var wanted: float = lerpf(_turn_from, _turn_to, progress)
	var moved: float = wanted - _placed
	_placed = wanted
	if player.camera_rig != null:
		# THE FAN TRAVELS WITH THE TURN, and the body is left to apply_look to
		# place. DO NOT also write player.rotation.y here -- this move's look
		# clamp is an absolute-yaw one, so apply_look pins the body to
		# reference + offset EVERY tick, using a reference captured when the
		# turn began. Two writers, once a tick, pulling opposite ways, is what
		# makes the camera visibly twitch left and right during a wall-climb
		# turn.
		#
		# Moving the reference instead makes them agree: apply_look places the
		# body at the scripted facing plus whatever the player's own mouse has
		# added, which is exactly right. assist = 1 because a scripted BODY turn
		# is one the view goes with -- what softens it is the eye's lag below,
		# not holding the fan back.
		player.camera_rig.shift_yaw_reference(wanted, 1.0)
		player.camera_rig.absorb_body_yaw(moved)
		if progress >= 1.0:
			# THE LAST SLICE HAS TO BE PLACED HERE. Every other tick's placement
			# is done by apply_look on the FOLLOWING tick, which is fine while
			# the move is still running -- but the tick the turn completes is
			# also the tick it hands off, and the move it hands to has no look
			# clamp, so that following placement never happens. The turn ended
			# one tick's worth short of its target: ten degrees, at a 0.3 s
			# ground turn.
			#
			# Placed at the target PLUS whatever the player's own mouse has
			# added, which is what apply_look would have put there.
			var offset: float = float(player.camera_rig.look_debug()["relative_yaw"])
			player.rotation.y = wanted + offset
	else:
		# No rig to place the body: drive it directly. Tests with a stub player
		# take this path.
		player.rotation.y = wanted
	# THE MODEL TURNS WITH THE BODY. It otherwise chases the body only while a
	# key asks it to move, and not at all in third person with none held -- a
	# turn in mid-air with the keys let go left it facing the old way.
	player.pin_visual_yaw(wanted)
	# The turn is SCRIPTED, so it is not a mouse swing and must not be billed
	# as one. Without this, spinning while holding W flips the wish direction
	# through half a circle and the turn tax charges for the whole thing --
	# which would make Q the most expensive key on the board.
	player.forgive_turn()
