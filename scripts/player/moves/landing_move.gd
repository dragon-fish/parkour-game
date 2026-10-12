class_name LandingMove
extends Move

# The original's TdMove_Landing, ported. [ME:CONFIRMED decompile 15.6, 15.7]
#
# EVERY landing comes through here, not only the hard one: TdMove.Landed sets
# Landing, and Landing.StartMove decides on the spot -- a skill roll, a
# landing on the back, a soft object, a hard landing, or an ordinary one. The
# ordinary one caps the horizontal speed (SubtractLandingSpeed) and sets
# Walking (or Crouch, without room to stand) from inside StartMove, so it
# lasts no time at all; only the hard landing and the soft object hold the
# body, with move and look input ignored, until the landing animation ends.
#
# It is a plain TdMove: no physics of its own. The body keeps the falling
# physics until processLanded hands it to walking.
#
# A level's stagger (MoveManager) is this project's own and still lands here
# for its lockout.

## TdMove_Landing.bForceLandBack, set by a stumble.
var force_land_back: bool = false
## TdMove_Landing.bLastLandingWasOnSoftObject: IsLandingOnSoftObject() sets it
## from the falling damage check, before the move's own Landed runs.
var last_landing_was_on_soft_object: bool = false

## Which branch this landing took, for the presentation and the tests.
enum Kind { NONE, NORMAL, HARD, SOFT_OBJECT, BACKWARDS, SKILL_ROLL, STAGGER }
var kind: int = Kind.NONE

var _elapsed: float = 0.0
## How long the body is held, for the landings that hold it. The original's
## is the landing animation's length; this project's is LandingConfig's.
var _hold: float = 0.0
## What the lockout tints the screen.
var _tint: Color = Color.BLACK

func is_ported() -> bool:
	return true

## TdMove_Landing.CanDoMove: not from Balance or a SkillRoll.
func can_do_move() -> bool:
	var state: StringName = player.move_manager.current_name
	if state == BALANCE or state == SKILL_ROLL:
		return false
	return td_can_do_move()

## TdMove_Landing.StartMove.
func enter(previous: StringName) -> void:
	_elapsed = 0.0
	_hold = 0.0
	kind = Kind.NONE
	_tint = cfg.tint_color
	if player.pending_stagger:
		_stagger()
		return
	var came_from_180_in_air: bool = previous == TURN_180_IN_AIR
	var falling_height: float = player.enter_falling_height - player.global_position.y
	var hard: bool = falling_height >= config.pawn.hard_landing_height
	var soft_surface: bool = hard and last_landing_was_on_soft_object
	var v_dir: Vector3 = player.velocity.normalized() if player.velocity.length_squared() > 0.0 else Vector3.ZERO
	var heading_dot_velocity: float = player.facing().dot(v_dir)
	var skill_roll: bool = not soft_surface and falling_height >= config.pawn.skill_roll_landing_height \
		and player.can_skill_roll()
	var soft_landing: Move = player.move_manager.move_for(SOFT_LANDING)
	var moving_backwards: bool = (heading_dot_velocity < -0.3 \
			and PawnPhysics.walking_state(player.horizontal_speed()) >= PawnPhysics.WAS_RUN) \
		or came_from_180_in_air \
		or (previous == SOFT_LANDING and soft_landing != null and soft_landing.has_method("is_moving_backwards") \
			and soft_landing.is_moving_backwards())
	player.last_landing_rolled = skill_roll and not moving_backwards
	if skill_roll and not moving_backwards:
		kind = Kind.SKILL_ROLL
		# SetMove(MOVE_SkillRoll) without bCheckCanDo [ME:CONFIRMED decompile]:
		# SkillRoll's CanDoMove is not asked; only SetMove itself may refuse.
		player.move_manager.set_move(SKILL_ROLL)
	elif came_from_180_in_air or previous == LAY_ON_GROUND or (hard and moving_backwards) \
			or (last_landing_was_on_soft_object and moving_backwards) or force_land_back:
		_land_backwards(hard)
	elif soft_surface:
		_land_on_soft_object()
	elif hard and (not player.uncontrolled_slide or (previous == RAMP_SLIDE and _rump_slide_touched_fall_height())):
		_land_hard()
	else:
		_land_normal()
		_end_landing()
	force_land_back = false
	last_landing_was_on_soft_object = false

## RumpSlide.bTouchedFallHeightVolume: a hard landing out of a rump slide is
## hard only after the slide touched a fall-height volume.
## [ME:CONFIRMED decompile N2 §4]
func _rump_slide_touched_fall_height() -> bool:
	var rump = player.move_manager.move_for(RAMP_SLIDE)
	return rump != null and rump.touched_fall_height

## TdMove_Landing.SubtractLandingSpeed. [ME:CONFIRMED decompile 15.6] After a
## jump's fall (or a coil, or an air kick), the horizontal speed is capped at
## PreJumpMomentum - LandingSpeedReduction. Kept as the original has it: a
## take-off slower than LandingSpeedReduction makes the cap negative, which
## turns the landing velocity round.
func subtract_landing_speed() -> void:
	var falling: Move = player.move_manager.move_for(FALLING)
	var old: StringName = player.old_movement_state
	var from_jump_fall: bool = old == FALLING and falling != null \
		and (falling.previous_move == JUMP or falling.previous_move == MELEE_AIR)
	if not (from_jump_fall or old == COIL or old == MELEE_AIR):
		return
	var jump: Move = player.move_manager.move_for(JUMP)
	if jump == null:
		return
	var cap: float = jump.pre_jump_momentum - cfg.landing_speed_reduction
	if cap < player.horizontal_speed():
		var flat := Vector3(player.velocity.x, 0.0, player.velocity.z)
		flat = flat.normalized() * cap if flat.length_squared() > 0.0 else Vector3.ZERO
		player.velocity = Vector3(flat.x, player.velocity.y, flat.z)

## TdMove_Landing.LandNormal: holding forward on a human-controlled landing
## forces the walking acceleration to its maximum for one frame; every
## landing but a vault's caps the speed.
func _land_normal() -> void:
	kind = Kind.NORMAL
	if player.move_action_hint == MAH_UP:
		player.force_max_accel_one_frame = true
	if player.old_movement_state != SPEED_VAULT:
		subtract_landing_speed()

## TdMove_Landing.EndLanding: Walking when a standing body fits, Crouch
## otherwise.
func _end_landing() -> void:
	if player.can_stand(player.collision_center()):
		player.move_manager.set_move(WALKING)
	else:
		player.move_manager.set_move(CROUCH)

## TdMove_Landing.LandHard: no input at all, no speed, until the animation
## ends.
func _land_hard() -> void:
	kind = Kind.HARD
	_hold_body(cfg.lockout_time)

## TdMove_Landing.LandOnSoftObject: the same hold, on a soft-landing surface.
func _land_on_soft_object() -> void:
	kind = Kind.SOFT_OBJECT
	_hold_body(cfg.lockout_time)

## TdMove_Landing.LandBackwards: onto the back.
func _land_backwards(hard: bool) -> void:
	kind = Kind.BACKWARDS
	# The hard landing's red, carried by LayOnGround: this project's
	# presentation of the damage TakeFallingDamage has just taken.
	if hard:
		player.pending_stagger_tint = cfg.tint_color
	player.velocity = Vector3.ZERO
	player.acceleration = Vector3.ZERO
	player.move_manager.set_move(LAY_ON_GROUND)

func _hold_body(seconds: float) -> void:
	_hold = seconds
	player.set_ignore_move_input(-1.0)
	player.set_ignore_look_input(-1.0)
	player.velocity = Vector3.ZERO
	player.acceleration = Vector3.ZERO
	player.request_standing_capsule()
	_drive_effects(1.0)

## A level's stagger: a knock-down that keeps part of the speed, and the same
## lockout as a hard landing. This project's own.
func _stagger() -> void:
	kind = Kind.STAGGER
	player.pending_stagger = false
	if player.pending_stagger_tint.a > 0.0:
		_tint = player.pending_stagger_tint
	player.pending_stagger_tint = Color(0.0, 0.0, 0.0, 0.0)
	player.velocity.x *= cfg.stagger_keep_ratio
	player.velocity.z *= cfg.stagger_keep_ratio
	player.velocity.y = minf(player.velocity.y, 0.0)
	_hold_body(cfg.lockout_time)

## The hold's end stands in for the landing animation's OnCustomAnimEnd, which
## sets Walking.
func tick_move(delta: float) -> void:
	super.tick_move(delta)
	if _hold <= 0.0:
		return
	_elapsed += delta
	var t: float = clampf(_elapsed / maxf(_hold, 0.0001), 0.0, 1.0)
	_drive_effects(1.0 - t)
	if t >= 1.0:
		player.move_manager.set_move(WALKING)

func exit() -> void:
	if _hold > 0.0:
		_drive_effects(0.0)
		# The lockout is the thing that knows when it is over, so the stagger
		# immunity starts here rather than where the stagger was chosen.
		player.arm_stagger_immunity()

## Whether this landing holds the body (a hard landing, a soft object, a
## stagger) rather than handing it straight on.
func is_holding() -> bool:
	return _hold > 0.0

## The lockout's presentation, at `severity`: 1 at the impact and 0 by the
## time it lets go. This project's; the original's is the animation.
func _drive_effects(severity: float) -> void:
	if player.camera_rig != null:
		player.camera_rig.set_crouch_amount(severity)
		player.camera_rig.set_landing_pitch_offset(cfg.camera_pitch_offset * severity)
	if player.screen_effects != null:
		player.screen_effects.set_tint(_tint, severity)
