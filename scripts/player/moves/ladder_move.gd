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

func enter(_previous: StringName) -> void:
	player.set_grounded(false)
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

## Arc length along the line, metres. Read by the HUD and by tests.
func climbing_offset() -> float:
	return _offset
