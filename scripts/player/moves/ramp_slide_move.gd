class_name RampSlideMove
extends Move

# The seated slide down a marked chute (TdMove_RumpSlide). The body is a
# passenger: half gravity pulls it along the surface, A and D nudge it across,
# nothing the player does stops it before the chute does.
#
# Entered by WalkingMove and by an airborne landing when the surface the body
# just touched is in Probes.UNCONTROLLED_SLIDE_GROUP (Player.touched_chute()).
# Exits to Falling when contact is lost for longer than contact_grace, or to
# Walking when the surface under the body flattens past min_slide_floor_z.
#
# PHYS_Falling in the original, with the surface removing the component of
# the velocity into it: done here by hand rather than through
# move_and_slide()'s floor handling, because a chute steeper than
# floor_max_angle is a WALL to Godot and a gentler one is a floor that
# floor_stop_on_slope would hold the body on.

var _normal: Vector3 = Vector3.UP
var _lost_contact: float = 0.0


func enter(_previous: StringName) -> void:
	var chute: Dictionary = player.touched_chute()
	_normal = chute.get("normal", Vector3.UP)
	_lost_contact = 0.0
	# Sitting down costs most of the arriving speed; what is left runs down
	# the chute, not into it.
	var kept: Vector3 = player.velocity * (1.0 - config.ramp_slide.initial_speed_loss)
	player.velocity = _along_surface(kept)
	# The body faces down the chute, and the look fan closes round that.
	var down := _downhill()
	if down.length_squared() > 0.0001:
		player.rotation.y = atan2(-down.x, -down.z)
	player.set_capsule_height(config.ramp_slide.capsule_height)
	player.set_body_folded(true)


func exit() -> void:
	player.set_body_folded(false)
	player.request_standing_capsule()


func physics_update(delta: float, input: MoveInput) -> StringName:
	var cfg_slide: RampSlideConfig = config.ramp_slide
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
	var along: Vector3 = player.velocity
	player.velocity = along - _normal * config.pawn.floor_snap_speed
	player.move_and_slide()
	player.velocity = _along_surface(player.velocity)

	var chute: Dictionary = player.touched_chute()
	if chute.is_empty():
		_lost_contact += delta
		player.set_grounded(false)
		if _lost_contact >= cfg_slide.contact_grace:
			return FALLING
		return KEEP
	_lost_contact = 0.0
	_normal = chute["normal"]
	# Seated on the chute, the model lies along it.
	player.body_tilt_normal = _normal
	# A surface, so the fall counter resets: the chute's end is where the
	# fall begins, not its top.
	player.set_grounded(true)
	if _normal.y >= cfg_slide.min_slide_floor_z:
		return WALKING
	return KEEP


## `v` with its component into the surface removed; a velocity leaving the
## surface is left alone.
func _along_surface(v: Vector3) -> Vector3:
	var into: float = v.dot(_normal)
	return v - _normal * into if into < 0.0 else v


## Unit vector down the surface, in the plane of it.
func _downhill() -> Vector3:
	var down: Vector3 = Vector3.DOWN - _normal * Vector3.DOWN.dot(_normal)
	return down.normalized() if down.length_squared() > 0.0001 else Vector3.ZERO
