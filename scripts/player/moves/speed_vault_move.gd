class_name SpeedVaultMove
extends PhysicsMove

# The original's TdMove_SpeedVault, ported -- and TdMove_VaultOver, which
# derives from it without a line of its own: the player registers this class
# twice, as SpeedVault (8) and VaultOver (9). [ME:CONFIRMED decompile script
# TdMove_SpeedVault.uc]
#
# Only VaultOver is reachable: CheckAutoMoves asks it once the hand-plant
# search has found a top (after AutoStepUp, which always refuses), and
# GrabTransfer asks it for a transfer Up. Nothing sets MOVE_SpeedVaulting.
#
# CanDoMove does the whole planning: where the vault ends (onto the top, over
# it, or over it into a fall), which VaultTypes row the approach matches, and
# the speed it leaves with. The move itself is up to four timed legs, each a
# precise location, with collision off and no root motion:
#   0 (VaultTimeUp > 0 only): fly to the hand plant at |d| / VaultTimeUp
#   1: the body is put on its target, then a jump arc to the ledge's offset
#      point at |d|2D / VaultTimeOver
#   2: put on it again, then the arc (or, ending in a fall, PLM_Fall) to the
#      end at |d|2D / VaultTimeDown
#   3: onto -> Walking, over -> Landing, either with the saved speed (its
#      vertical part never negative); falling over -> Falling, the velocity
#      kept in direction and given the saved speed.
#
# Quirks kept: the row loop lets row 0 (autostepuprightleg) through whatever
# the onto/over plan; integer truncation of every speed and distance the script
# casts to int; a transfer from a hang (MovementState Grab) always takes row 3,
# vaultOver, and skips the vertical speed test.

## The planning's results, as the original's fields.
var active_vault_type: int = -1
var vault_end_position: Vector3 = Vector3.ZERO
var over_end_location: Vector3 = Vector3.ZERO
var onto_end_location: Vector3 = Vector3.ZERO
var saved_velocity: Vector3 = Vector3.ZERO
var start_to_handplant: Vector3 = Vector3.ZERO
var vault_state: int = 0
var move_direction: Vector3 = Vector3.ZERO
var hand_location: Vector3 = Vector3.ZERO
var target_location: Vector3 = Vector3.ZERO
var vault_onto: bool = false
var end_move_falling: bool = false
var end_move_in_melee: bool = false
var vault_speed: float = 0.0
var handplant_height: float = 0.0

func _init() -> void:
	super._init()
	pawn_physics = PHYS_FLYING
	disable_collision = true
	disable_face_rotation = true
	disable_movement_time = -1.0
	disable_look_time = -1.0

func is_ported() -> bool:
	return true

## TdMove_SpeedVault.HandleDeath: a vault with no room to stand where it
## is survives with one point.
func handle_death(damage: float) -> float:
	if not player.can_stand(player.collision_center(), true):
		return player.health.hp - 1.0
	return damage

func uses_view_rotation() -> bool:
	return true

func _vault_cfg() -> SpeedVaultConfig:
	return cfg as SpeedVaultConfig

## The active VaultTypes row.
func vault_type() -> Dictionary:
	var types: Array[Dictionary] = _vault_cfg().vault_types
	return types[active_vault_type] if active_vault_type >= 0 and active_vault_type < types.size() else {}

## int(x) on a value in uu: truncation toward zero, in metres.
static func uu_int(x: float) -> float:
	return float(int(x / UU)) * UU

## TdMove_SpeedVault.UpdateActiveVaultType.
func update_active_vault_type(time_to_hand_plant: float) -> int:
	var momentum: float = player.horizontal_speed()
	if player.movement_state == GRAB:
		return 3
	var types: Array[Dictionary] = _vault_cfg().vault_types
	var vz: float = player.velocity.y
	var unchecked: float = SpeedVaultConfig.UNCHECKED
	for idx in types.size():
		var t: Dictionary = types[idx]
		if handplant_height < t["min_height"] or handplant_height > t["max_height"]:
			continue
		if t["vault_onto"] != vault_onto and idx != 0:
			continue
		if t["min_momentum"] != unchecked and momentum < t["min_momentum"]:
			continue
		if t["max_momentum"] != unchecked and momentum > t["max_momentum"]:
			continue
		if t["min_speed_z"] != unchecked and vz < t["min_speed_z"]:
			continue
		if t["max_speed_z"] != unchecked and vz > t["max_speed_z"]:
			continue
		if time_to_hand_plant > t["max_distance_time"]:
			continue
		return idx
	return -1

## TdMove_SpeedVault.CanDoMove: the plan.
func can_do_move() -> bool:
	vault_onto = false
	end_move_falling = false
	if not td_can_do_move() or not player.found_ledge:
		return false
	var state: StringName = player.movement_state
	if state == VAULT_OVER or state == SPEED_VAULT:
		return false
	if state == WALL_CLIMB:
		var climb = player.move_manager.move_for(WALL_CLIMB)
		if climb != null and climb.performed_double_jump:
			return false
	var ref: Vector3 = player.global_position
	if state == GRAB:
		var transfer = player.move_manager.move_for(GRAB_TRANSFER)
		if transfer != null:
			ref = transfer.transfer_location
	if player.found_ledge_excludes_hand_moves or MoveTraces.excludes_hand_moves(player.movement_actor):
		return false
	if player.move_action_hint != MAH_UP and state != GRAB:
		return false
	if player.move_ledge_normal.y < 0.3:
		return false
	var view: Vector3 = UE.rot_dir(player.controller_pitch_units(), UE.yaw_units(player.rotation.y))
	if view.dot(player.move_normal) > -0.2:
		return false
	var ledge: Vector3 = player.move_ledge_location
	start_to_handplant = ledge - ref
	handplant_height = ledge.y - ref.y + player.collision_half_height()
	saved_velocity = Vector3(player.velocity.x, 0.0, player.velocity.z)
	var floor_velocity: float = Vector2(saved_velocity.x, saved_velocity.z).length()
	var time_to_hand_plant: float = Vector2(start_to_handplant.x, start_to_handplant.z).length() \
		/ maxf(uu_int(floor_velocity), 300.0 * UU)
	if time_to_hand_plant > _vault_cfg().max_time_to_ledge:
		return false
	hand_location = ledge - UE.cross(player.move_normal, player.move_ledge_normal) * 20.0 * UU
	move_direction = PawnPhysics.safe_normal(Vector3(start_to_handplant.x, 0.0, start_to_handplant.z))
	vault_end_position = ledge + move_direction * maxf(48.0 * UU, uu_int(floor_velocity * 0.3))
	vault_end_position.y = ref.y
	if not check_collision(ledge, ref, floor_velocity):
		return false
	active_vault_type = update_active_vault_type(time_to_hand_plant)
	if active_vault_type == -1:
		return false
	var t: Dictionary = vault_type()
	if not vault_onto and t["vault_onto"]:
		vault_end_position = onto_end_location
		vault_onto = t["vault_onto"]
	floor_velocity = clampf(uu_int(floor_velocity + t["speed_addition"]),
		uu_int(t["clamp_speed_min"]), uu_int(t["clamp_speed_max"]))
	saved_velocity = PawnPhysics.safe_normal(saved_velocity) * floor_velocity
	if vault_onto:
		var end_z: float = vault_end_position.y
		var reach: float = Vector2(vault_end_position.x - ledge.x, vault_end_position.z - ledge.z).length()
		vault_end_position = ledge + move_direction * minf(uu_int(reach),
			maxf(48.0 * UU, uu_int(floor_velocity * t["vault_time_down"])))
		vault_end_position.y = end_z
	if state != GRAB and (player.velocity.y < t["min_speed_z"] or player.velocity.y > t["max_speed_z"]):
		return false
	return true

## TdMove_SpeedVault.FindValidOntoEndLocation: a box 1.4 R wide and H tall,
## VaultClearObjectHeight over the ledge, swept toward the planned end; what
## it hits is the top's far side, which must leave 32 uu (64 above 48 uu of
## hand plant) of top to stand on.
func find_valid_onto_end_location(ledge: Vector3) -> bool:
	var r: float = player.collision_radius()
	var h: float = player.collision_half_height()
	var extent := Vector3(r * 1.4, h * 0.5, r * 1.4)
	var start: Vector3 = ledge
	start.y = ledge.y + _vault_cfg().vault_clear_object_height + extent.y
	var end: Vector3 = vault_end_position
	end.y = start.y
	onto_end_location = end
	var hit: Dictionary = player.traces.movement_trace(end, start, extent)
	if hit["hit"]:
		var at: Vector3 = hit["location"] + move_direction * extent.x
		var ledge_width: float = (at - ledge).dot(move_direction)
		if ledge_width <= extent.x + 1.0 * UU:
			var small: Dictionary = player.traces.movement_trace(end, start, Vector3.ONE * 10.0 * UU)
			at = small["location"] + move_direction * 10.0 * UU
			ledge_width = (at - ledge).dot(move_direction)
		var needed: float = (32.0 if handplant_height <= 48.0 * UU else 64.0) * UU
		if ledge_width < needed:
			return false
		onto_end_location = at - move_direction * r
	onto_end_location.y = ledge.y + h
	return true

## TdMove_SpeedVault.FindValidOverEndLocation: 0 a vault over, 1 nothing to
## vault over, 2 the far side too deep. Swept from the far end BACK toward the
## ledge, 48 uu below it.
func find_valid_over_end_location(ledge: Vector3, max_ledge_width: float) -> int:
	var extent: Vector3 = player.collision_extent()
	extent.y = 48.0 * UU
	var start: Vector3 = vault_end_position
	start.y = ledge.y - extent.y
	var end: Vector3 = ledge
	end.y = start.y
	over_end_location = start
	var hit: Dictionary = player.traces.movement_trace(end, start, extent)
	if not hit["hit"]:
		return 1
	var at: Vector3 = hit["location"]
	if Vector2(at.x - ledge.x, at.z - ledge.z).length() < max_ledge_width:
		over_end_location = vault_end_position
		return 0
	over_end_location = at
	if max_ledge_width < 80.0 * UU:
		return 2
	# The box's reach along the wall normal, against the WORLD's X axis -- the
	# box is axis-aligned.
	var axis_align: float = acos(absf(player.move_normal.dot(Vector3(1.0, 0.0, 0.0)))) * 4.0 / PI
	axis_align = 1.0 + axis_align * 0.414
	start = at - (axis_align * extent.x + 48.0 * UU) * move_direction
	hit = player.traces.movement_trace(end, start, extent)
	if not hit["hit"]:
		return 2
	end = vault_end_position
	start = hit["location"]
	end.y = start.y
	hit = player.traces.movement_trace(end, start, extent)
	if not hit["hit"]:
		return 2
	over_end_location = hit["location"] - move_direction * 16.0 * UU
	return 0

## TdMove_SpeedVault.FindVaultFloor: an 8 uu thick body box dropped at the
## end, from 32 uu over the ledge to 32 uu below it (onto) or 240 (over).
## Returns the floor's height, or NAN.
func find_vault_floor(ledge: Vector3, wanted_end: Vector3) -> float:
	var extent: Vector3 = player.collision_extent()
	extent.y = 8.0 * UU
	var start: Vector3 = wanted_end
	start.y = ledge.y + 32.0 * UU
	var end: Vector3 = wanted_end
	end.y = ledge.y - (32.0 if vault_onto else 240.0) * UU
	var hit: Dictionary = player.traces.movement_trace(end, start, extent)
	if not hit["hit"]:
		return NAN
	return (hit["location"] as Vector3).y - extent.y

## TdMove_SpeedVault.CheckCollision.
func check_collision(ledge: Vector3, _ref: Vector3, floor_velocity: float) -> bool:
	if not find_valid_onto_end_location(ledge):
		return false
	var temp_z: float = vault_end_position.y
	vault_end_position = onto_end_location
	vault_end_position.y = temp_z
	temp_z = onto_end_location.y
	var reach: float = Vector2(onto_end_location.x - ledge.x, onto_end_location.z - ledge.z).length()
	onto_end_location = ledge + move_direction * minf(uu_int(reach), 160.0 * UU)
	onto_end_location.y = temp_z
	var max_ledge_width: float = clampf(floor_velocity * 0.2, 60.0 * UU, 180.0 * UU)
	if find_valid_over_end_location(ledge, max_ledge_width) != 0:
		vault_onto = true
	vault_end_position = onto_end_location if vault_onto else over_end_location
	var floor_z: float = find_vault_floor(ledge, vault_end_position)
	if not is_nan(floor_z):
		vault_onto = floor_z > ledge.y - 64.0 * UU
		vault_end_position.y = floor_z + player.collision_half_height()
	else:
		end_move_falling = not vault_onto
	return player.can_stand(vault_end_position)

## TdMove_SpeedVault.StartMove.
func enter(_previous: StringName) -> void:
	disable_face_rotation = true
	end_move_in_melee = false
	player.velocity = Vector3.ZERO
	var t: Dictionary = vault_type()
	if t["reset_camera"]:
		reset_camera_look(0.2)
	vault_state = 0 if t["vault_time_up"] > 0.0 else 1
	target_location = player.global_position
	play_slot_anim(t["anim"], 1.0, 0.15, 0.2)
	# This project's presentation: the legs carry the body, so the clip on
	# the model must not add its own hip lift on top (Player.set_clip_lift_cancelled()).
	player.set_clip_lift_cancelled(true)
	update_vault_movement()

## TdMove_SpeedVault.StopMove has nothing of the original's to undo; the
## presentation hands back what it borrowed.
func exit() -> void:
	player.set_clip_lift_cancelled(false)
	if player.camera_rig != null:
		player.camera_rig.set_vault_roll(0.0)

func on_timer() -> void:
	update_vault_movement()

## After the physics: the camera's bank through the vault. This project's
## presentation. A slight bank, peaking in the middle and gone by the end --
## sin() rather than a ramp, so a vault never hands a tilted horizon to what
## comes next. LEANS ONE WAY, ALWAYS: a vault is a one-handed plant, the same
## hand every time. NOT FOR A STEP-UP, which has no hand in it (the same reason
## it plays StepUp rather than SafetyVault).
func tick_move(delta: float) -> void:
	super.tick_move(delta)
	if player.camera_rig == null or player.move_manager.current_move() != self:
		return
	var roll: float = 0.0
	if not is_step_up():
		roll = sin(PI * vault_progress()) * deg_to_rad(config.camera.vault_roll_deg)
	player.camera_rig.set_vault_roll(roll)

## How far through its legs the vault is, 0 .. 1, on the row's own times.
func vault_progress() -> float:
	var t: Dictionary = vault_type()
	if t.is_empty():
		return 0.0
	var total: float = float(t["vault_time_up"]) + float(t["vault_time_over"]) + float(t["vault_time_down"])
	return clampf(move_active_time / maxf(total, 0.001), 0.0, 1.0)

## The scripted-path hook Player.scripted_progress() reads: the clip offsets'
## eye follow and the hand-keyed clip curves run on it.
func path_debug() -> Dictionary:
	return {"progress": vault_progress()}

## TdMove_SpeedVault.UpdateVaultMovement: one leg per call.
func update_vault_movement() -> void:
	var t: Dictionary = vault_type()
	var ledge: Vector3 = player.move_ledge_location
	match vault_state:
		0:
			var offset: Vector2 = t["handplant_offset"]
			target_location = ledge + Vector3.UP * offset.y + move_direction * offset.x
			vault_speed = (target_location - player.global_position).length() / t["vault_time_up"]
			set_precise_location(target_location, vault_speed, PLM_FLY)
			set_timer(t["vault_time_up"])
			vault_state = 1
		1:
			player.global_position = target_location
			player.velocity = Vector3.ZERO
			var offset: Vector2 = t["ledge_offset"]
			target_location = ledge + Vector3.UP * offset.y + move_direction * offset.x
			var d: Vector3 = target_location - player.global_position
			vault_speed = Vector2(d.x, d.z).length() / t["vault_time_over"]
			set_precise_location(target_location, vault_speed, PLM_JUMP)
			player.stop_ignore_look_input()
			set_timer(t["vault_time_over"])
			vault_state = 2
		2:
			player.global_position = target_location
			player.velocity = Vector3.ZERO
			if end_move_falling:
				player.set_physics(PHYS_FALLING)
			var d: Vector3 = vault_end_position - player.global_position
			var speed: float = Vector2(d.x, d.z).length() / t["vault_time_down"]
			set_precise_location(vault_end_position, speed, PLM_FALL if end_move_falling else PLM_JUMP)
			vault_state = 3
			saved_velocity = move_direction * speed
			disable_face_rotation = false
			player.face_rotation_time_left = 0.4
			set_timer(t["vault_time_down"])
		_:
			use_precise_location = false
			if vault_onto or not end_move_falling:
				player.move_manager.set_move(WALKING if vault_onto else LANDING)
				saved_velocity.y = maxf(0.0, player.velocity.y)
				player.velocity = saved_velocity
				# Normal(V) is 1 uu/s^2 long in the original: UU here, not 1 m/s^2.
				player.acceleration = PawnPhysics.safe_normal(saved_velocity) * UU
				player.set_acceleration_time(0.2)
			else:
				player.velocity = PawnPhysics.safe_normal(player.velocity) \
					* Vector2(saved_velocity.x, saved_velocity.z).length()
				# Normal(V) is 1 uu/s^2 long in the original: UU here, not 1 m/s^2.
				player.acceleration = PawnPhysics.safe_normal(saved_velocity) * UU
				player.set_acceleration_time(0.2)
				player.move_manager.set_move(FALLING)

func failed_to_reach_precise_location() -> void:
	if vault_state == 3:
		update_vault_movement()

## TdMove_SpeedVault.HandleMoveAction: a melee press is remembered (every row
## has bMeleePossible). Nothing in the player's moves reads it.
func handle_move_action(action: int) -> void:
	if action == MA_MELEE:
		end_move_in_melee = true

## For the animation: the row's sequence, the vault-onto plan and whether the
## row is one of the two step-ups (no hand on the top).
func vault_anim() -> StringName:
	var t: Dictionary = vault_type()
	return t["anim"] if not t.is_empty() else &""

func is_step_up() -> bool:
	return active_vault_type == 0 or active_vault_type == 1

## For the animation: the vault's legs, which the pack's clip is fitted to.
func scripted_duration() -> float:
	var t: Dictionary = vault_type()
	if t.is_empty():
		return 0.0
	return t["vault_time_up"] + t["vault_time_over"] + t["vault_time_down"]
