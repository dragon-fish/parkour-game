class_name FallUncontrolledMove
extends PhysicsMove

# The original's TdMove_FallingUncontrolled, the death fall, ported.
# [ME:CONFIRMED decompile N5 §7]
#
# Entered by the TdPhysicsMove PrePhysics of a move with
# bCheckExitToUncontrolledFalling once the body is FallingUncontrolledHeight
# below where it started to fall. PHYS_Falling under the PlayerDying
# controller (no acceleration at all) with one automatic transition, the soft
# landing. StartMove puts the pawn into its UncontrolledFall state
# (Player.go_into_uncontrolled_fall()): move and look input ignored, every
# move but Landing and SoftLanding refused. The landing is the state's own
# (Player._uncontrolled_fall_landed()): the falling damage -- the whole bar,
# a death fall -- then Landing, which a dead body does not get.
#
# Everything else here is this project's presentation of the death: the eye
# lifted off the head bone, the screen draining with the speed, the optional
# ragdoll, and the death handed to DeathSequence (died_from_fall) on the tick
# it is known.

func _init() -> void:
	super._init()
	pawn_physics = PHYS_FALLING
	controller_state = CS_PLAYER_DYING
	check_for_soft_landing = true

func is_ported() -> bool:
	return true

func can_do_move() -> bool:
	return td_can_do_move()

## What counts as the ragdoll having arrived: the hips stop after dropping,
## or barely drift for a second, or six seconds pass. PROJECT-DEFINED.
const RAGDOLL_FALLING_SPEED := 4.0
const RAGDOLL_IMPACT_SPEED := 0.5
const RAGDOLL_DRIFT_WINDOW := 1.0
const RAGDOLL_DRIFT_DISTANCE := 0.5
const RAGDOLL_TIMEOUT := 6.0

var _ragdoll_elapsed: float = 0.0
var _ragdoll_dropping: bool = false
var _drift_from: Vector3 = Vector3.ZERO
var _drift_since: float = 0.0
## The death has been handed to DeathSequence. Once, and only once: this is a
## terminal state for a fall that kills.
var _declared: bool = false

func enter(_previous: StringName) -> void:
	player.go_into_uncontrolled_fall()
	# A back landing armed before control was lost does not survive it.
	player.pending_back_landing = false
	_ragdoll_elapsed = 0.0
	_ragdoll_dropping = false
	_declared = false
	_drift_from = Vector3.ZERO
	_drift_since = 0.0
	# The first-person eye rides the head bone of a body falling flat; lift it
	# clear, as the death's own lift does. Not from outside.
	if player.camera_rig != null and not player.camera_rig.in_third_person():
		player.camera_rig.set_death_lift(config.camera.fall_uncontrolled_eye_lift)
	# The ragdoll, when the project turns it on, takes the body the moment
	# control is lost; the capsule then stops where it is (PHYS_None), because
	# the ragdoll's bodies hang off it and every metre it travelled would drag
	# them.
	if player.ragdoll_enabled and player.ragdoll != null and player.body != null \
			and player.ragdoll.build(player.find_skeleton()):
		var throw := Vector3(randf_range(-1.0, 1.0), randf_range(0.2, 0.8),
				randf_range(-1.0, 1.0)).normalized() * randf_range(3.0, 7.0)
		player.ragdoll.start(throw + player.velocity * 0.5, player.get_rid())

## The death, when the landing the UncontrolledFall state handles has emptied
## the bar. Called by Player._uncontrolled_fall_landed() after the damage.
func landed_uncontrolled() -> void:
	if player.health != null and player.health.is_dead():
		_declare()

func _declare() -> void:
	if _declared:
		return
	_declared = true
	player.set_dying(true)
	player.died_from_fall.emit()

func pre_physics(delta: float) -> void:
	super.pre_physics(delta)
	# While a ragdoll runs the capsule stays where it is.
	if player.ragdoll != null and player.ragdoll.is_simulating():
		player.velocity = Vector3.ZERO
		if player.physics != PHYS_NONE:
			player.set_physics(PHYS_NONE)
	_drive_screen_effects()

## The ragdoll's own arrival, for a body the capsule no longer carries.
func tick_move(delta: float) -> void:
	super.tick_move(delta)
	if player.ragdoll == null or not player.ragdoll.is_simulating() or _declared:
		return
	_ragdoll_elapsed += delta
	var falling: float = player.ragdoll.hips_fall_speed()
	if falling >= RAGDOLL_FALLING_SPEED:
		_ragdoll_dropping = true
	var hips: Vector3 = player.ragdoll.hips_position()
	if _drift_since <= 0.0 or hips.distance_to(_drift_from) > RAGDOLL_DRIFT_DISTANCE:
		_drift_from = hips
		_drift_since = _ragdoll_elapsed
	var drifted_little: bool = _ragdoll_elapsed - _drift_since >= RAGDOLL_DRIFT_WINDOW
	var struck: bool = _ragdoll_dropping and falling <= RAGDOLL_IMPACT_SPEED
	if not (struck or drifted_little or _ragdoll_elapsed >= RAGDOLL_TIMEOUT):
		return
	# The ragdoll never lands, so the death fall's damage is taken here.
	player.take_damage(config.pawn.fatal_fall_damage, Health.Cause.FALL)
	_declare()

## The descent drains and blurs the screen with the downward speed.
## PROJECT-DEFINED presentation (FallUncontrolledConfig.blur_scale).
func _drive_screen_effects() -> void:
	if player.screen_effects == null or _declared:
		return
	var falling: float = -player.velocity.y
	if player.ragdoll != null and player.ragdoll.is_simulating():
		falling = player.ragdoll.hips_fall_speed()
	var intensity: float = clampf(falling / maxf(config.pawn.terminal_velocity, 0.001), 0.0, 1.0)
	player.screen_effects.set_desaturation(intensity)
	player.screen_effects.set_blur(intensity * cfg.blur_scale)

## TdMove_FallingUncontrolled.StopMove, and the presentation given back: the
## ragdoll stopped, the eye lift and the screen cleared, and a death that was
## never declared un-flagged (a noclip toggle leaves this way).
func exit() -> void:
	if player.ragdoll != null:
		player.ragdoll.stop()
	if player.camera_rig != null:
		player.camera_rig.set_death_lift(0.0)
	if not _declared:
		player.set_dying(false)
	if player.screen_effects != null:
		player.screen_effects.set_desaturation(0.0)
		player.screen_effects.set_blur(0.0)
