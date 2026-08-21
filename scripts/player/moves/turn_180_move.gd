class_name Turn180Move
extends Move

# Q: spin to face the other way. The original's TdMove_180Turn.
#
# Started life as a wall-climb exit and nothing else. THE OWNER CORRECTED THE
# SCOPE: "Q works almost everywhere -- anywhere the legs are not tied up, like
# a 180 while walking, or a 90 while wall running." So the entry lives in
# MoveManager now, gated by MoveConfig.allows_turn, and this move has to make
# sense from the ground as well as off a wall.
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
var _turn_from: float = 0.0
var _turn_to: float = 0.0
## The wall's outward normal, or ZERO when this turn did not come off a wall.
## Decides everything that differs between the two cases: the angle, the hang,
## and whether space does anything.
var _normal: Vector3 = Vector3.ZERO
var _recentred: bool = false

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
	if player.probes == null:
		return Vector3.ZERO
	var facing: Vector3 = -player.global_transform.basis.z
	facing.y = 0.0
	var ahead: Dictionary = player.probes.wall_ahead_query(facing.normalized())
	if ahead["valid"]:
		return ahead["normal"]
	var beside: Dictionary = player.probes.wall_query(facing.normalized())
	if beside["valid"]:
		return beside["normal"]
	return Vector3.ZERO

func on_a_wall() -> bool:
	return _normal != Vector3.ZERO

func enter(_previous: StringName) -> void:
	_elapsed = 0.0
	_recentred = false
	_normal = _find_wall()
	_normal.y = 0.0

	_turn_from = player.rotation.y
	if on_a_wall():
		_normal = _normal.normalized()
		# atan2(x, z) rather than (x, -z): the body's forward is -Z, so facing
		# ALONG a vector means yaw = atan2(v.x, v.z) is wrong by half a turn
		# and this is the form that is not.
		_turn_to = atan2(_normal.x, _normal.z) + PI
		# Frozen outright rather than decayed. "Not subject to gravity" is the
		# owner's own description and DisableMovementTime is the field; a body
		# still carrying its climb would leave the window before it ended.
		player.velocity = Vector3.ZERO
		player.set_grounded(false)
	else:
		_turn_to = _turn_from + PI
		# Momentum is kept. Turning on the spot while running is how the turn
		# is used on the ground, and stopping the body dead would make it a
		# move nobody would ever press.
		player.set_grounded(player.is_on_floor())

func physics_update(delta: float, _input: MoveInput) -> StringName:
	_elapsed += delta
	_advance_turn(delta)

	if on_a_wall():
		# ✅ TdMove_WallKick, folded in -- see Turn180Config's own note on why
		# it is not a state of its own.
		if player.consume_buffered_jump():
			player.velocity = _normal * cfg.wall_kick_speed_out
			player.velocity.y = cfg.wall_kick_speed_up
			player.move_and_slide()
			player.set_grounded(player.is_on_floor())
			return JUMP
		player.set_grounded(false)
		if _elapsed < cfg.disable_movement_time:
			# Held in place: no gravity, no input, no drift.
			return KEEP
		# The freeze is over but the OPPORTUNITY is not. These were one number
		# to begin with, and the owner reported the result exactly: "the window
		# is too short, Q has to be followed by space immediately or you slide
		# off." Gravity comes back here; the kick stays available until
		# kick_window. See Turn180Config for why splitting them is the honest
		# fix rather than simply enlarging DisableMovementTime, which is a
		# confirmed value.
		player.velocity.y -= config.pawn.gravity * cfg.falling_gravity_scale * delta
		player.move_and_slide()
		player.set_grounded(player.is_on_floor())
		if player.grounded:
			return WALKING
		if _elapsed >= cfg.kick_window:
			return FALLING
		return KEEP

	# On the ground, or in the air off no wall at all: carry on as normal while
	# the body comes round, and hand back once it has.
	player.velocity.y -= config.pawn.gravity * delta
	player.move_and_slide()
	player.set_grounded(player.is_on_floor())
	if _elapsed < cfg.turn_time:
		return KEEP
	return WALKING if player.grounded else FALLING

## Carries the body a slice of the way round, and tells the camera how far it
## moved.
##
## By absolute progress through turn_time rather than a per-tick rate, so the
## turn lands on exactly the target and the camera is handed a series of small
## even deltas instead of one lump. See docs/camera-authority.md: the body is
## being moved BY A SCRIPT, so the eye trails it and eases in.
func _advance_turn(_delta: float) -> void:
	var progress: float = clampf(_elapsed / maxf(cfg.turn_time, 0.001), 0.0, 1.0)
	var before: float = player.rotation.y
	player.rotation.y = lerpf(_turn_from, _turn_to, progress)
	if player.camera_rig != null:
		player.camera_rig.absorb_body_yaw(player.rotation.y - before)
	# The turn is SCRIPTED, so it is not a mouse swing and must not be billed
	# as one. Without this, spinning while holding W flips the wish direction
	# through half a circle and the turn tax charges for the whole thing --
	# which would make Q the most expensive key on the board.
	player.forgive_turn()
	if progress >= 1.0 and not _recentred and player.camera_rig != null:
		# The fan the look clamp is measured against belongs to the direction
		# the body ENDED facing, not the one it was facing when Q was pressed.
		# Once only: recentring every tick would re-derive the running total
		# from the body each frame, which is exactly what the clamp's own
		# accumulator exists to avoid.
		_recentred = true
		player.camera_rig.recentre_yaw_reference(_turn_to)
