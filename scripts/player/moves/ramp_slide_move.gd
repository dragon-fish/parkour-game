class_name RampSlideMove
extends Move

# The seated slide down a marked chute (TdMove_RumpSlide). The body is a
# passenger: half gravity pulls it along the surface, A and D nudge it across,
# a jump leaves it, nothing else the player does stops it before the chute
# does.
#
# Entered by WalkingMove and by an airborne landing when the surface the body
# just touched is in Probes.UNCONTROLLED_SLIDE_GROUP (Player.touched_chute()).
# Exits with its momentum: to Walking the tick the body is on a floor that is
# not a chute, to Falling when it touches nothing for contact_grace, or to
# Jump on the buffered press. A chute that flattens out under
# min_slide_floor_z is a floor too.
#
# PHYS_Falling in the original, with the surface removing the component of
# the velocity into it: done here by hand rather than through
# move_and_slide()'s floor handling, because a chute steeper than
# floor_max_angle is a WALL to Godot and a gentler one is a floor that
# floor_stop_on_slope would hold the body on.

var _normal: Vector3 = Vector3.UP
var _lost_contact: float = 0.0
## Where the slide began, for the descent that decides how it lands.
var _start_y: float = 0.0
## Where the scripted turn toward the downhill has got the body to; the fan
## and the model follow it each tick.
var _placed: float = 0.0


func enter(_previous: StringName) -> void:
	var chute: Dictionary = player.touched_chute()
	_normal = chute.get("normal", Vector3.UP)
	_lost_contact = 0.0
	_start_y = player.global_position.y
	# Sitting down costs most of the arriving speed; what is left runs down
	# the chute, not into it.
	var kept: Vector3 = player.velocity * (1.0 - config.ramp_slide.initial_speed_loss)
	player.velocity = _along_surface(kept)
	# The body comes round to face down the chute over turn_in_time (see
	# _advance_turn), and the look fan travels with it.
	_placed = player.rotation.y
	# The capsule shortens like the slide's; the model is NOT folded down to
	# the shortened crown. [ME:CONFIRMED A1] RootOffset z = 20 uu: the seated
	# body sits 0.2 m low, not 0.9, and the eye rides the head bone of a
	# model lying along the chute, which is already as low as it should be.
	# Folded as well, the eye was under the chute's surface.
	player.set_capsule_height(config.ramp_slide.capsule_height)


func exit() -> void:
	player.request_standing_capsule()
	# The same stand-up as the slide's: for recovery_time the look clamp and
	# the model's yaw freeze outlive the move, and the slide's own redo gate
	# keeps a crouch press from buying another one at once.
	player.begin_slide_recovery()


func physics_update(delta: float, input: MoveInput) -> StringName:
	var cfg_slide: RampSlideConfig = config.ramp_slide
	_advance_turn(delta)
	# A jump leaves the chute: the same take-off as from the ground, from a
	# body that is on a surface. The chute's own downhill speed rides along.
	if player.consume_jump():
		player.velocity.y = config.pawn.base_jump_z
		player.velocity += player.jump_add_velocity(input)
		player.set_grounded(false)
		return JUMP

	# Half gravity, then the surface takes the component into itself: what
	# remains is the pull down the chute.
	player.velocity.y -= player.effective_gravity() * cfg_slide.gravity_modifier * delta
	player.velocity = _along_surface(player.velocity)
	# A nudge across the slide. Right of the downhill line, on the surface.
	var down := _downhill()
	var across := down.cross(_normal).normalized() if down.length_squared() > 0.0001 else Vector3.ZERO
	player.velocity += across * input.move.x * cfg_slide.side_control * delta
	if player.velocity.length() > cfg_slide.max_slide_speed:
		player.velocity = player.velocity.normalized() * cfg_slide.max_slide_speed
	# Pressed INTO the chute for the move, the way Walking presses into the
	# floor: a velocity exactly along the surface touches nothing, and a tick
	# that touches nothing reads as the chute having ended. Measured on the
	# Stormdrain chute: the slide let go every eight ticks and fell instead.
	# ONLY WHILE IN CONTACT, and only by surface_press_speed: the press has a
	# horizontal part, and once the body has run off the chute's foot onto the
	# floor below, nothing cancels it. At floor_snap_speed it braked the body
	# from 10 m/s to a standstill in four ticks, at the edge it should have
	# flown off.
	var along: Vector3 = player.velocity
	if _lost_contact == 0.0:
		player.velocity = along - _normal * cfg_slide.surface_press_speed
	player.move_and_slide()
	player.velocity = _along_surface(player.velocity)

	var chute: Dictionary = player.touched_chute()
	if chute.is_empty():
		# Run out onto a floor: the slide is over and the speed is the
		# runner's. Off the end into the air: a fall, once the seams have had
		# their chance.
		if player.is_on_floor():
			player.set_grounded(true)
			return _let_go()
		_lost_contact += delta
		player.set_grounded(false)
		if _lost_contact >= cfg_slide.contact_grace:
			return _let_go()
		return KEEP
	_lost_contact = 0.0
	_normal = chute["normal"]
	# Seated on the chute, the model lies along it.
	player.body_tilt_normal = _normal
	# A surface, so the fall counter resets: the chute's end is where the
	# fall begins, not its top.
	player.set_grounded(true)
	if _normal.y >= cfg_slide.min_slide_floor_z:
		return _let_go()
	return KEEP


## The slide is over, other than by a jump. A long descent lands hard: the
## body is handed to Falling with the hard landing armed, and the floor under
## it, if it is already on one, is landed on next tick. A short one is simply
## the runner's speed on whatever is there.
func _let_go() -> StringName:
	if _start_y - player.global_position.y >= config.ramp_slide.hard_landing_descent:
		player.arm_forced_hard_landing()
		player.set_grounded(false)
		return FALLING
	return WALKING if player.is_on_floor() else FALLING


## Swings the body, the look fan and the drawn model toward the downhill, at
## a rate that covers a half turn in turn_in_time. THE FAN MOVES, NOT THE
## BODY DIRECTLY: this move has an absolute yaw clamp, so apply_look rebuilds
## the body's yaw from reference plus the player's own offset every tick;
## a second writer here is what made the 180 turn twitch (Turn180Move).
## Recomputed every tick rather than captured once, because a chute bends.
func _advance_turn(delta: float) -> void:
	var down := _downhill()
	if down.length_squared() < 0.0001:
		return
	var target: float = atan2(-down.x, -down.z)
	var remaining: float = wrapf(target - _placed, -PI, PI)
	var step: float = PI / maxf(config.ramp_slide.turn_in_time, 0.001) * delta
	var wanted: float = wrapf(_placed + clampf(remaining, -step, step), -PI, PI)
	var moved: float = wrapf(wanted - _placed, -PI, PI)
	_placed = wanted
	if player.camera_rig != null:
		player.camera_rig.shift_yaw_reference(wanted, 1.0)
		player.camera_rig.absorb_body_yaw(moved)
	else:
		player.rotation.y = wanted
	# The model faces the chute's foot, not the way it arrived: the yaw
	# freeze holds whatever is pinned here.
	player.pin_visual_yaw(wanted)


## `v` with its component into the surface removed; a velocity leaving the
## surface is left alone.
func _along_surface(v: Vector3) -> Vector3:
	var into: float = v.dot(_normal)
	return v - _normal * into if into < 0.0 else v


## Unit vector down the surface, in the plane of it.
func _downhill() -> Vector3:
	var down: Vector3 = Vector3.DOWN - _normal * Vector3.DOWN.dot(_normal)
	return down.normalized() if down.length_squared() > 0.0001 else Vector3.ZERO
