class_name Turn180Move
extends Move

# Q part-way up a wall kick: spin to face back the way you came, hang there for
# a moment, and either kick off the wall or drop.
#
# The hang is the point. DisableMovementTime is a real field in the original's
# move library and this project had never implemented the mechanic; without it
# the turn is a flourish performed on the way down, and with it the turn is a
# decision point -- the body genuinely stops, and the player chooses.

var _elapsed: float = 0.0
var _turn_from: float = 0.0
var _turn_to: float = 0.0
## The wall's outward normal, handed over by WallClimbMove: by the time the
## body has come round, the wall is behind it and no forward probe can see it.
var _normal: Vector3 = Vector3.ZERO

func enter(_previous: StringName) -> void:
	_elapsed = 0.0
	player.set_grounded(false)
	_normal = player.pending_wall_normal
	# Frozen outright rather than decayed. "Not subject to gravity" is the
	# owner's description and DisableMovementTime is the field; a body still
	# carrying its climb would leave the window before the window ended.
	player.velocity = Vector3.ZERO
	_turn_from = player.rotation.y
	_turn_to = _turn_from + PI

func exit() -> void:
	player.pending_wall_normal = Vector3.ZERO

func physics_update(delta: float, input: MoveInput) -> StringName:
	_elapsed += delta
	player.set_grounded(false)

	# Turned by absolute progress through turn_time rather than by a per-tick
	# rate, so the turn lands on exactly PI and the camera is handed a series
	# of small, even deltas instead of one lump. See docs/camera-authority.md:
	# the body is being moved BY A SCRIPT, so the eye trails it and eases in.
	var progress: float = clampf(_elapsed / maxf(cfg.turn_time, 0.001), 0.0, 1.0)
	var wanted: float = lerpf(_turn_from, _turn_to, progress)
	var before: float = player.rotation.y
	player.rotation.y = wanted
	if player.camera_rig != null:
		player.camera_rig.absorb_body_yaw(wanted - before)
	if progress >= 1.0 and player.camera_rig != null:
		# The fan the look clamp is measured against belongs to the direction
		# the body ENDED facing, not the one it was facing when Q was pressed.
		# Without this every turn leaves the view's ±90 degrees centred half a
		# revolution away from where the player is looking.
		player.camera_rig.recentre_yaw_reference(_turn_to)

	# Space, any time in the window. ✅ TdMove_WallKick.
	if player.consume_buffered_jump():
		# Out along the wall's normal, which is now BEHIND the body -- the
		# player has turned to face away from the wall, and kicking off it
		# throws them forward, in the direction they are now looking.
		var out: Vector3 = _normal
		out.y = 0.0
		if out.length_squared() > 0.0001:
			player.velocity = out.normalized() * cfg.wall_kick_speed_out
		player.velocity.y = cfg.wall_kick_speed_up
		player.move_and_slide()
		player.set_grounded(player.is_on_floor())
		return JUMP

	if _elapsed >= cfg.disable_movement_time:
		# Window spent without a kick. The body was already stopped, so this
		# is simply gravity being handed back.
		return FALLING
	# Held in place for the whole window: no gravity, no input, no drift.
	return KEEP
