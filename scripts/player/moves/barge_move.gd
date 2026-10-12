class_name BargeMove
extends PhysicsMove

# The original's TdMove_Barge, ported. [ME:CONFIRMED decompile script
# TdMove_Barge, N5 §20]
#
# Melee on the ground asks this before the punch: an interactable straight
# ahead -- within BargeMinTraceDistance, or half a second at the barge speed
# when running at it -- turns the press into a barge. Running at it faster than
# 250 uu/s it is the shoulder: the velocity set to min(500, |V.xy| + 200) and a
# PLM_Walk precise location half a second ahead, until the body meets the door
# and stops where it is; holding back before the impact aborts it. Slower it is
# a standing kick with the move input off for 0.6 s. Either way the animation's
# end is Walking.
#
# The shoulder deals its damage on the first thing it meets (HitWall or Bump),
# the kick on its animation's BargeHitNotify, 0.33 s in; both to everything the
# trace found. What counts as interactable (the original's bInteractable) is a
# collider in INTERACTABLE_GROUP.

const INTERACTABLE_GROUP := &"interactable"
## On a collider: the node that takes TdDmgType_Barge for it (hit_object()).
const BARGE_DAMAGE_META := &"barge_damage"
## MeleeKickObject's BargeHitNotify, seconds in. [ME:CONFIRMED anims]
const KICK_HIT_NOTIFY_TIME := 0.33
## The shoulder plays on the upper body, the kick on the full body.
## [ME:CONFIRMED anims/moves_to_anims.md]
const UPPER_BODY := CustomAnimSlot.CNT_UPPER_BODY

var has_dealt_damage: bool = false
var barge_with_hands: bool = false
## BargeActorList: what the trace found, [{collider, normal, position}].
var barge_actor_list: Array = []

func _init() -> void:
	super._init()
	movement_group = MG_NON_INTERACTIVE
	# [ME:CONFIRMED decompile] bDisableFaceRotation.
	disable_face_rotation = true

func is_ported() -> bool:
	return true

static func is_interactable(collider: Object) -> bool:
	return collider is Node and (collider as Node).is_in_group(INTERACTABLE_GROUP)

## HitObject: 100 of TdDmgType_Barge to `victim`, which in this project only a
## BreakableGlass's pane can take, through BARGE_DAMAGE_META. A KActor would
## also be pushed (ApplyImpulse); this project has no interactable KActors.
static func hit_object(player, victim: Object, _location: Vector3, _normal: Vector3) -> void:
	if not is_instance_valid(victim) or not (victim is Node) or not victim.has_meta(BARGE_DAMAGE_META):
		return
	var receiver = victim.get_meta(BARGE_DAMAGE_META)
	if is_instance_valid(receiver):
		receiver.take_barge_damage(player.velocity)

## Every interactable the trace found, as TdMove_Barge and the slide and
## crouch kicks deliver it: at its own hit location and normal.
static func hit_all(player, list: Array) -> void:
	for entry in list:
		if is_interactable(entry["collider"]):
			hit_object(player, entry["collider"], entry["position"], entry["normal"])

## CalcBargeDamage's trace: the first thing on the line from `start` to `end`,
## kept when it is interactable. A trigger that does not block is passed
## through by the original; a ray here never sees one.
static func calc_barge_targets(player, start: Vector3, end: Vector3, into: Array) -> void:
	var hit: Dictionary = player.phys.line_trace(start, end)
	if hit.is_empty() or not is_interactable(hit["collider"]):
		return
	var normal: Vector3 = hit["normal"]
	normal.y = 0.0
	into.append({"collider": hit["collider"], "normal": PawnPhysics.safe_normal(normal),
		"position": hit["position"]})

## FindBargeTarget as MeleeSlide and MeleeCrouch use it: straight ahead,
## `distance` metres from the pawn's centre.
static func find_barge_targets(player, distance: float) -> Array:
	var found: Array = []
	calc_barge_targets(player, player.global_position,
		player.global_position + player.facing() * distance, found)
	return found

func _barge_speed() -> float:
	return minf(cfg.max_speed, Vector2(player.velocity.x, player.velocity.z).length() + cfg.add_on_speed)

func _has_forward_velocity() -> bool:
	return player.facing().dot(PawnPhysics.safe_normal(player.velocity)) > 0.707

## TdMove_Barge.CanDoMove.
func can_do_move() -> bool:
	if not td_can_do_move():
		return false
	var distance: float = cfg.min_trace_distance
	if _has_forward_velocity():
		distance = maxf(cfg.min_trace_distance, _barge_speed() * cfg.trace_time)
	barge_actor_list.clear()
	calc_barge_targets(player, player.global_position,
		player.global_position + player.facing() * distance, barge_actor_list)
	return barge_actor_list.size() > 0

func enter(_previous: StringName) -> void:
	has_dealt_damage = false
	barge_with_hands = false
	start_bargin()

func start_bargin() -> void:
	var speed: float = Vector2(player.velocity.x, player.velocity.z).length()
	if speed > cfg.kick_threshold_speed and _has_forward_velocity():
		reset_camera_look(0.3)
		barge_with_hands = true
		var barge_speed: float = _barge_speed()
		player.velocity = PawnPhysics.safe_normal(player.velocity) * barge_speed
		set_precise_location(player.global_position + cfg.trace_time * player.velocity, barge_speed, PLM_WALK)
		var rate: float = 1.0
		for entry in barge_actor_list:
			if is_interactable(entry["collider"]):
				var to: Vector3 = entry["position"] - player.global_position
				var time_to_door: float = Vector2(to.x, to.z).length() / barge_speed
				rate = clampf(cfg.anim_time / maxf(time_to_door, 1e-6), 0.7, 1.3)
		play_slot_anim(&"BargeInLeft", rate, 0.2, 0.0, false, false, UPPER_BODY)
	else:
		reset_camera_look(0.2)
		play_slot_anim(&"MeleeKickObject", 1.0, 0.1, 0.1)
		player.set_ignore_move_input(0.6)

## Native PrePhysics: the base, then pulling back (hint Down) before the
## shoulder lands aborts it.
func pre_physics(delta: float) -> void:
	super.pre_physics(delta)
	if player.move_action_hint == MAH_DOWN and not has_dealt_damage and barge_with_hands:
		abort_barge()

func abort_barge() -> void:
	player.anim_slot.stop(0.5, UPPER_BODY)
	player.move_manager.set_move(WALKING)

func hit_wall(normal: Vector3, collider: Object) -> void:
	try_give_barge_damage(normal, collider)

func bump(normal: Vector3, collider: Object) -> void:
	try_give_barge_damage(normal, collider)

## TryGiveBargeDamage: the shoulder meets something, stops where it is, and
## deals the barge to what the trace found.
func try_give_barge_damage(_normal: Vector3, collider: Object) -> void:
	if not barge_with_hands:
		return
	if collider == null or has_dealt_damage:
		return
	has_dealt_damage = true
	set_precise_location(player.global_position, Vector2(player.velocity.x, player.velocity.z).length(), PLM_WALK)
	hit_all(player, barge_actor_list)
	play_slot_anim(&"BargeOutLeft", 1.0, 0.0, 0.2, false, false, UPPER_BODY)

## BargeHitNotify, the kick's: once.
func barge_hit_notify() -> void:
	if has_dealt_damage:
		return
	has_dealt_damage = true
	hit_all(player, barge_actor_list)

func on_custom_anim_end(_anim_name: StringName) -> void:
	player.anim_slot.stop(0.2, UPPER_BODY)
	player.move_manager.set_move(WALKING)

## The kick's BargeHitNotify, when the slot carried MeleeKickObject past it
## this frame.
func tick_move(delta: float) -> void:
	super.tick_move(delta)
	if is_current_custom_anim(&"MeleeKickObject"):
		var at: float = player.anim_slot.position_of(&"MeleeKickObject")
		if at >= KICK_HIT_NOTIFY_TIME and at - delta < KICK_HIT_NOTIFY_TIME:
			barge_hit_notify()

func exit() -> void:
	player.anim_slot.stop(0.2, UPPER_BODY)
	barge_actor_list.clear()
