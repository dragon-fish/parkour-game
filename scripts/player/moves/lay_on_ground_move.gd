class_name LayOnGroundMove
extends Move

# [ME:CONFIRMED A1] TdMove_LayOnGround: down on the back, then up. See
# LayOnGroundConfig for where it comes from and why it is not LandingMove.
#
# TWO PHASES IN ONE MOVE. Getting up has exactly one way in -- from lying
# down -- so a state of its own would be a name nothing else could ask for.
#
# [ME:COMMUNITY] the body stays down until the player asks: jump, or forward.
# DO NOT put this on a timer -- being able to stay down is the point of the
# original's back landing (it aims from there), and a get-up that starts on
# its own reads as the character acting without being told.

var _elapsed: float = 0.0
var _rising: bool = false
## The blow's own tint when a blow put the body here (MoveManager leaves the
## stagger's pending for this move), transparent otherwise.
var _tint: Color = Color(0.0, 0.0, 0.0, 0.0)

## Read by CharacterAnimator: the get-up is a different clip from going down.
func is_rising() -> bool:
	return _rising

func enter(_previous: StringName) -> void:
	_elapsed = 0.0
	_rising = false
	_tint = player.pending_stagger_tint
	player.pending_stagger_tint = Color(0.0, 0.0, 0.0, 0.0)
	player.velocity.y = minf(player.velocity.y, 0.0)
	player.set_capsule_height(config.lay_on_ground.capsule_height)
	# From the engine, not assumed: a script can knock a body down in mid-air.
	player.set_grounded(player.is_on_floor())
	_drive_camera(1.0)

func physics_update(delta: float, input: MoveInput) -> StringName:
	_elapsed += delta
	if _rising:
		player.velocity.x = 0.0
		player.velocity.z = 0.0
	else:
		var horizontal := Vector3(player.velocity.x, 0.0, player.velocity.z)
		# [ME:CONFIRMED A1] bAvoidLedges False: nothing here holds the body
		# back from an edge, it slides off and falls lying down.
		horizontal = horizontal.move_toward(Vector3.ZERO, config.lay_on_ground.slide_deceleration * delta)
		player.velocity.x = horizontal.x
		player.velocity.z = horizontal.z
	if player.grounded:
		player.velocity.y = -config.pawn.floor_snap_speed
	else:
		player.velocity.y -= player.effective_gravity() * delta
		player.velocity.y = maxf(player.velocity.y, -config.pawn.terminal_velocity)
	player.move_and_slide()
	player.set_grounded(player.is_on_floor())

	if _rising:
		var t: float = clampf(_elapsed / maxf(config.lay_on_ground.get_up_time, 0.0001), 0.0, 1.0)
		_drive_camera(1.0 - t)
		if t >= 1.0:
			return WALKING
		return KEEP

	_drive_camera(1.0)
	_drive_tint(1.0 - clampf(_elapsed / maxf(config.lay_on_ground.min_down_time, 0.0001), 0.0, 1.0))
	var asked: bool = input.jump_pressed or input.move.y > 0.5
	if asked and player.grounded and _elapsed >= config.lay_on_ground.min_down_time:
		# The press got the body up; it must not also be the first jump of
		# the walk that follows.
		player.consume_buffered_jump()
		# No room to stand is room to crouch: the capsule is already the
		# crouch's own height. Same hand-off as the slide's.
		if not player.has_headroom():
			return CROUCH
		_rising = true
		_elapsed = 0.0
	return KEEP

func exit() -> void:
	_drive_camera(0.0)
	_drive_tint(0.0)
	player.request_standing_capsule()
	# A body that has just got up is not knocked straight back down by the
	# hazard it is still standing in. Same window as the hard landing's.
	player.arm_stagger_immunity()

## The eye goes down with the body and comes back up across the get-up.
## Written every tick for LandingMove's reason: Player.update_effects() leaves
## the crouch amount alone while this move is current.
func _drive_camera(down: float) -> void:
	if player.camera_rig != null:
		player.camera_rig.set_crouch_amount(down)

## Fades across the time the body may not yet get up: by then the blow is over.
func _drive_tint(severity: float) -> void:
	if _tint.a > 0.0 and player.screen_effects != null:
		player.screen_effects.set_tint(_tint, severity)
