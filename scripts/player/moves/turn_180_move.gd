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

var _elapsed: float = 0.0
## Half a turn clockwise, exactly -- see HalfTurn. Not squared up with the
## wall: come in crooked and you leave crooked, which is what the original does
## and what the name of the move says. The kick that follows is square
## regardless -- it reads the wall's own normal, not the facing.
var _turn: HalfTurn = HalfTurn.new()
## The wall's outward normal, or ZERO when this turn did not come off a wall.
## Decides everything that differs between the two cases: the angle, the hang,
## and whether space does anything.
var _normal: Vector3 = Vector3.ZERO
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
## nothing across slowdown_time rather than dropping it on the spot.
var _entry_velocity: Vector3 = Vector3.ZERO

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
##
## Static, because MoveManager asks it too: a Q in mid-air with a wall to turn
## on is this move's, and one with none is Turn180InAirMove's.
##
## Returns {"normal": the wall's outward normal or ZERO, "ahead": whether it
## was the wall ahead}.
static func find_wall(player) -> Dictionary:
	var none := {"normal": Vector3.ZERO, "ahead": false}
	if player.probes == null:
		return none
	var facing: Vector3 = -player.global_transform.basis.z
	facing.y = 0.0
	var ahead: Dictionary = player.probes.wall_ahead_query(facing.normalized())
	if ahead["valid"]:
		return {"normal": ahead["normal"], "ahead": true}
	var beside: Dictionary = player.probes.wall_query(facing.normalized())
	if beside["valid"]:
		return {"normal": beside["normal"], "ahead": false}
	return none

func on_a_wall() -> bool:
	return _normal != Vector3.ZERO

func enter(_previous: StringName) -> void:
	_elapsed = 0.0
	_kick_armed = false
	_entry_velocity = Vector3(player.velocity.x, 0.0, player.velocity.z)
	var wall: Dictionary = Turn180Move.find_wall(player)
	_normal = wall["normal"]
	_from_climb = wall["ahead"]
	_normal.y = 0.0

	_turn.begin(player.rotation.y)
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

func physics_update(delta: float, _input: MoveInput) -> StringName:
	_elapsed += delta
	_turn.advance(player, _elapsed / maxf(_duration(), 0.001))

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

	# On the ground. A turn in the air off no wall is Turn180InAirMove's.
	#
	# [ME:INFERRED] THE BODY DOES NOT STOP DEAD. Speed bleeds to nothing across
	# slowdown_time, so the old direction's momentum is still carrying you while
	# you come round, matching how the original feels. DO NOT keep the
	# momentum outright instead of bleeding it -- what makes Q pressable is
	# that the stop is GRADUAL, not that there is none.
	var remaining: float = 1.0 - clampf(_elapsed / maxf(cfg.slowdown_time, 0.001), 0.0, 1.0)
	player.velocity.x = _entry_velocity.x * remaining
	player.velocity.z = _entry_velocity.z * remaining
	player.velocity.y -= config.pawn.gravity * delta
	player.move_and_slide()
	player.set_grounded(player.is_on_floor())
	if not _turn_finished():
		return KEEP
	return WALKING if player.grounded else FALLING

## How long this turn takes. [ME:CONFIRMED] Two measured figures, not one: a
## ground turn is 0.3 s and a wall turn 0.5 s.
func _duration() -> float:
	return cfg.wall_turn_time if on_a_wall() else cfg.turn_time

## Whether the body has finished coming round. The armed kick waits for this,
## and so does the wall turn's gravity.
func _turn_finished() -> bool:
	return _elapsed >= _duration()
