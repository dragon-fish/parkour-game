class_name StumbleMove
extends PhysicsMove

# The original's TdMove_Stumble (on TdMove_StumbleBase), ported.
# [ME:CONFIRMED decompile]
#
# A hit that staggers: TdPawn.StumbleDamage records the hit here and hands
# MA_Stumble to the action table (Player.stumble_damage()) -- for the player,
# melee, shove and taser damage, and the barbed-wire volume's touch. From the
# ground the stumble plays StumbleFwd or GetHitStumbleBwd as root motion,
# which way decided by the damage type and the side the hit came from; in the
# air (the air row sets bInAir) it throws the body back at 300 uu/s and 80 up.
# PHYS_Falling by its CDO -- a stumble on the ground drops a hair and lands,
# and its own Landed does nothing -- with move and look input ignored and the
# uncontrolled-fall exit. GetHitStumbleBwd ends at 0.5 s (its OnTimer); the
# rest end with their animation. Hit again while stumbling, it starts over.
#
# The fall onto the back that a bot's melee can cause (PlayStumbleFall) needs
# the bot that decides it; this project has none, so it is never taken.

## TdMove_StumbleBase.EStumbleState.
enum StumbleState {
	HIT_NONE, HIT_MELEE_BACK, HIT_MELEE_BACK_HEAD, HIT_MELEE_FRONT_LEFT,
	HIT_MELEE_FRONT_RIGHT, HIT_MELEE_BARGE_FRONT, HIT_MELEE_CROUCH_FRONT,
	HIT_MELEE_SLIDE_FRONT, HIT_MELEE_WALLRUN_RIGHT, HIT_MELEE_WALLRUN_LEFT,
	HIT_MELEE_AIR_HEAD_FRONT, HIT_MELEE_AIR_BODY_FRONT, HIT_MELEE_VAULT_KICK,
	HIT_MELEE_SOCCER_KICK, HIT_BULLET_FRONT, HIT_BULLET_FRONT_HEAD, HIT_BULLET_BACK,
	HIT_SPECIAL_BULLET_FRONT, HIT_SPECIAL_BULLET_HEAD, HIT_SPECIAL_BULLET_BACK,
	HIT_BARBED_WIRE_FRONT,
}

## The original's damage types the stumble tells apart.
enum DamageType {
	OTHER, BARGE, BARBED_WIRE, MELEE, MELEE_LEFT, MELEE_RIGHT, SNIPER_BULLET, SHOVE,
	MELEE_VAULT_KICK, MELEE_AIR, MELEE_CROUCH, MELEE_SLIDE, MELEE_WALLRUN,
	MELEE_SOCCER_KICK, SHOTGUN, TASER, LOW_CALIBER_BULLET, HIGH_CALIBER_BULLET,
}

## The recorded hit (TdMove_StumbleBase's fields).
var damage_location: Vector3 = Vector3.ZERO
var instigator_location: Vector3 = Vector3.ZERO
var hit_damage_type: int = DamageType.OTHER
var stumble_state: int = StumbleState.HIT_NONE
## TdMove_Stumble.bInAir, set by the action table's air rows.
var in_air: bool = false

var _clip: RootMotionClip = null
var _facing: Vector3 = Vector3.FORWARD
var _anim_time: float = 0.0
var _anim_length: float = 0.0
## The animation playing ends the move on its own timer (GetHitStumbleBwd).
var _ends_on_timer: bool = false

## gethitleft, the stumble in the air: no root motion, 0.8 s.
const AIR_HIT_LENGTH := 0.8

func _init() -> void:
	super._init()
	pawn_physics = PHYS_FALLING
	check_exit_to_uncontrolled_falling = true
	disable_movement_time = -1.0
	disable_look_time = -1.0

func is_ported() -> bool:
	return true

func record_hit(damage_type: int, hit_location: Vector3, instigator: Vector3) -> void:
	hit_damage_type = damage_type
	damage_location = hit_location
	instigator_location = instigator

## TdMove_Stumble.CanDoMove: out of a crouch (or a crouched kick) with room to
## stand, always; never out of a move on the crouched collision; otherwise the
## base.
func can_do_move() -> bool:
	var state: StringName = player.move_manager.current_name
	if (state == CROUCH or state == MELEE_CROUCH) \
			and player.can_stand(player.collision_center() + Vector3.UP * 30.0 * UU):
		return true
	var current: Move = player.move_manager.current_move()
	if current != null and current.use_custom_collision:
		return false
	return td_can_do_move()

func enter(_previous: StringName) -> void:
	stumble_state = get_stumble_state()
	_play_stumble_animation()

func exit() -> void:
	in_air = false

## TdMove_StumbleBase.GetStumbleState.
func get_stumble_state() -> int:
	var feet: Vector3 = player.global_position - Vector3.UP * player.collision_half_height()
	var hit_height: float = damage_location.y - feet.y
	var hit_2d: Vector3 = PawnPhysics.safe_normal_2d(instigator_location - player.global_position)
	var hit_side: float = hit_2d.dot(player.facing())
	var high: bool = hit_height > 145.0 * UU
	match hit_damage_type:
		DamageType.BARGE:
			return StumbleState.HIT_MELEE_BARGE_FRONT if hit_side > 0.0 else StumbleState.HIT_MELEE_BACK
		DamageType.BARBED_WIRE:
			return StumbleState.HIT_MELEE_BACK if hit_side > 0.0 else StumbleState.HIT_BARBED_WIRE_FRONT
		DamageType.MELEE, DamageType.MELEE_LEFT, DamageType.MELEE_RIGHT, \
				DamageType.SNIPER_BULLET, DamageType.SHOVE:
			if hit_side > 0.0:
				return StumbleState.HIT_MELEE_FRONT_RIGHT if hit_damage_type == DamageType.MELEE_RIGHT \
					else StumbleState.HIT_MELEE_FRONT_LEFT
			return StumbleState.HIT_MELEE_BACK_HEAD if high else StumbleState.HIT_MELEE_BACK
		DamageType.MELEE_VAULT_KICK:
			return StumbleState.HIT_MELEE_VAULT_KICK
		DamageType.MELEE_AIR:
			if hit_side > 0.0:
				return StumbleState.HIT_MELEE_AIR_BODY_FRONT if hit_height < 100.0 * UU \
					else StumbleState.HIT_MELEE_AIR_HEAD_FRONT
			return StumbleState.HIT_MELEE_BACK_HEAD if hit_height > 100.0 * UU else StumbleState.HIT_MELEE_BACK
		DamageType.MELEE_CROUCH:
			if hit_side > 0.0:
				return StumbleState.HIT_MELEE_CROUCH_FRONT
			return StumbleState.HIT_MELEE_BACK_HEAD if high else StumbleState.HIT_MELEE_BACK
		DamageType.MELEE_SLIDE:
			if hit_side > 0.0:
				return StumbleState.HIT_MELEE_SLIDE_FRONT
			return StumbleState.HIT_MELEE_BACK_HEAD if high else StumbleState.HIT_MELEE_BACK
		DamageType.MELEE_WALLRUN:
			if hit_side > 0.0:
				# (Vector(Rotation) x (Instigator - Location)).Z > 0 in the
				# original's axes is the instigator on the pawn's right.
				var right: Vector3 = player.facing().cross(Vector3.UP)
				var on_right: bool = right.dot(instigator_location - player.global_position) > 0.0
				return StumbleState.HIT_MELEE_WALLRUN_LEFT if on_right else StumbleState.HIT_MELEE_WALLRUN_RIGHT
			return StumbleState.HIT_MELEE_BACK_HEAD if high else StumbleState.HIT_MELEE_BACK
		DamageType.MELEE_SOCCER_KICK:
			return StumbleState.HIT_MELEE_SOCCER_KICK
		DamageType.SHOTGUN, DamageType.TASER:
			if hit_side < 0.0:
				return StumbleState.HIT_SPECIAL_BULLET_BACK
			return StumbleState.HIT_SPECIAL_BULLET_HEAD if high else StumbleState.HIT_SPECIAL_BULLET_FRONT
		DamageType.LOW_CALIBER_BULLET, DamageType.HIGH_CALIBER_BULLET:
			return StumbleState.HIT_BULLET_BACK if hit_side < 0.0 else StumbleState.HIT_BULLET_FRONT
	return StumbleState.HIT_NONE

## TdMove_Stumble.PlayStumbleAnimation.
func _play_stumble_animation() -> void:
	_clip = null
	_anim_time = 0.0
	_anim_length = 0.0
	_ends_on_timer = false
	_facing = player.facing()
	match stumble_state:
		StumbleState.HIT_MELEE_FRONT_LEFT, StumbleState.HIT_MELEE_FRONT_RIGHT, \
				StumbleState.HIT_MELEE_BARGE_FRONT, StumbleState.HIT_MELEE_CROUCH_FRONT, \
				StumbleState.HIT_MELEE_WALLRUN_RIGHT, StumbleState.HIT_MELEE_WALLRUN_LEFT, \
				StumbleState.HIT_MELEE_SLIDE_FRONT, StumbleState.HIT_MELEE_AIR_HEAD_FRONT, \
				StumbleState.HIT_MELEE_AIR_BODY_FRONT, StumbleState.HIT_BARBED_WIRE_FRONT:
			if in_air:
				# No instigator to face: thrown back along the pawn's own
				# facing.
				var v: Vector3 = -player.facing() * 300.0 * UU
				v.y = 80.0 * UU
				player.velocity = v
				_anim_length = AIR_HIT_LENGTH
			else:
				player.use_root_motion(true)
				reset_camera_look(0.2)
				_clip = RootMotionClip.stumble_backward()
				_anim_length = _clip.length
				_ends_on_timer = true
				set_timer(0.5)
		StumbleState.HIT_MELEE_BACK, StumbleState.HIT_MELEE_BACK_HEAD:
			player.use_root_motion(true)
			_clip = RootMotionClip.stumble_forward()
			_anim_length = _clip.length
		_:
			player.move_manager.set_move(WALKING)

## TdMove_Stumble.OnTimer: GetHitStumbleBwd hands back at 0.5 s.
func on_timer() -> void:
	if _ends_on_timer:
		player.move_manager.set_move(WALKING)

## TdMove_Stumble.Landed: only the fall onto the back lands -- never here.
func landed(_normal: Vector3) -> void:
	pass

func pre_physics(delta: float) -> void:
	super.pre_physics(delta)
	if player.root_motion_active and _clip != null:
		player.root_motion_velocity = _clip.world_velocity(_anim_time, delta, _facing)

func tick_move(delta: float) -> void:
	super.tick_move(delta)
	_anim_time += delta
	if _anim_length > 0.0 and _anim_time >= _anim_length \
			and player.move_manager.current_move() == self:
		# OnCustomAnimEnd: Walking.
		player.move_manager.set_move(WALKING)
