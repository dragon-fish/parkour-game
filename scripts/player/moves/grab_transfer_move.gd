class_name GrabTransferMove
extends PhysicsMove

# The original's TdMove_GrabTransfer (MOVE_GrabTransfer 31): from a hang or a
# ladder to another ledge or ladder. [ME:CONFIRMED decompile script
# TdMove_GrabTransfer.uc; CheckContextMove 0x0120c1a0, LedgeTransfer
# 0x01208060, LadderTransfer 0x01208520 read, N5 §14]
#
# Jump while hanging or climbing, asked before the pull-up and the jump off.
# The stick says where: up (only up when hanging free), left, right, or -- with
# no direction -- where the view looks (a look 22.5 degrees up counts as up).
# A ladder that way is looked for first; then a ledge, by the hand-plant search
# from the hang: 260 uu sideways or along the view, or 60 uu up from two body
# heights higher. A ledge on the same wall is only taken going up, 1 .. 140 uu
# higher; going sideways it must be a turned wall. The flight is a straight
# PLM_Fly at max(distance / 0.55, 200) uu/s, after a 0.2 s turn unless going
# up; on arrival IntoGrab (which hangs at once) or IntoClimb takes over.
# Going up onto a ledge the body cannot hang from but can vault, the vault is
# the target.
#
# Kept: going up, the ladder search's direction is never set (stack contents in
# the original); here it finds nothing. The relative extent of the new hang
# point is measured against the OLD wall's normal.

enum Hint { NONE, LEFT, RIGHT, UP, DOWN }

var transfer_location: Vector3 = Vector3.ZERO
var transfer_normal: Vector3 = Vector3.ZERO
var transfer_look_at_location: Vector3 = Vector3.ZERO
var transfer_ledge_normal: Vector3 = Vector3.ZERO
var transfer_hint: int = Hint.NONE
var transfer_move: StringName = INTO_GRAB
## The ladder the transfer goes to, and the one being climbed.
var ladder: LadderVolume = null
var transfer_ladder: LadderVolume = null
var transfer_speed: float = 0.0
var transfer_distance: float = 0.0
var fit_for_grab: bool = false

func _init() -> void:
	super._init()
	pawn_physics = PHYS_FLYING
	controller_state = CS_PLAYER_WALKING
	disable_face_rotation = true
	disable_movement_time = -1.0
	disable_look_time = -1.0

func is_ported() -> bool:
	return true

func uses_view_rotation() -> bool:
	return true

func _transfer_cfg() -> GrabTransferConfig:
	return cfg as GrabTransferConfig

func _grab() -> GrabMove:
	return player.move_manager.move_for(GRAB) as GrabMove

## The view's rotator against the pawn's, (pitch, yaw).
func _view_delta() -> Vector2i:
	var pitch: int = UE.normalize_axis(player.controller_pitch_units())
	var yaw: int = UE.normalize_axis(UE.yaw_units(player.rotation.y) - UE.yaw_units(player.pawn_yaw))
	return Vector2i(pitch, yaw)

## TdMove_GrabTransfer.CanDoMove.
func can_do_move() -> bool:
	if not td_can_do_move():
		return false
	if not check_context_move():
		return false
	var r: float = player.default_collision_radius()
	var extent := Vector3(r, player.default_collision_half_height(), r)
	fit_for_grab = not player.traces.movement_trace_for_blocking(transfer_location, player.global_position, extent)
	if transfer_hint == Hint.UP:
		var to_vault: bool = check_reachable_vault_over()
		if not fit_for_grab:
			return to_vault
	if not fit_for_grab:
		return false
	return player.movement_state == GRAB or player.movement_state == CLIMB

## UTdMove_GrabTransfer::CheckContextMove.
func check_context_move() -> bool:
	transfer_hint = Hint.NONE
	var hint: int = _hint_of(player.move_action_hint)
	if hint != Hint.NONE and hint != Hint.DOWN:
		if player.movement_state == CLIMB and hint != Hint.UP:
			transfer_hint = hint
		elif not _grab().is_hanging_free():
			transfer_hint = hint
		elif hint == Hint.UP:
			transfer_hint = Hint.UP
	var yaw: int = _view_delta().y
	if (transfer_hint == Hint.UP and (yaw < -0x2000 or yaw > 0x2000)) \
			or (transfer_hint == Hint.LEFT and (yaw > 0x2000 or yaw < -0x4000)) \
			or (transfer_hint == Hint.RIGHT and (yaw < -0x2000 or yaw > 0x4000)):
		transfer_hint = Hint.NONE
	if ladder_transfer():
		transfer_move = INTO_CLIMB
		return true
	if ledge_transfer():
		transfer_move = INTO_GRAB
		return true
	return false

static func _hint_of(move_action_hint: int) -> int:
	match move_action_hint:
		MAH_LEFT:
			return Hint.LEFT
		MAH_RIGHT:
			return Hint.RIGHT
		MAH_UP:
			return Hint.UP
		MAH_DOWN:
			return Hint.DOWN
	return Hint.NONE

## UTdMove_GrabTransfer::LedgeTransfer.
func ledge_transfer() -> bool:
	var c: GrabTransferConfig = _transfer_cfg()
	var start: Vector3 = player.global_position
	var distance: float = c.allowed_2d_transfer_distance
	var view: Vector2i = _view_delta()
	if transfer_hint == Hint.NONE and view.x > 0x1000 and view.y >= -0x1fff and view.y < 0x2000:
		transfer_hint = Hint.UP
	var yaw: int = UE.yaw_units(player.pawn_yaw)
	if transfer_hint == Hint.UP:
		start.y += player.default_collision_half_height() * 2.0
		distance = player.default_collision_radius() * 2.0
	elif transfer_hint == Hint.LEFT:
		yaw -= 0x4000
	elif transfer_hint == Hint.RIGHT:
		yaw += 0x4000
	elif transfer_hint == Hint.NONE:
		yaw = UE.yaw_units(player.rotation.y)
	var hit: Dictionary = player.traces.find_auto_move_ledge(start, UE.yaw_dir(UE.normalize_axis(yaw)),
		distance, false, false)
	if hit["result"] != MoveTraces.LEDGE_TOP:
		player.found_ledge = false
		return false
	var l: Vector3 = hit["ledge_location"]
	var mn: Vector3 = hit["move_normal"]
	var same_wall: bool = player.move_normal.dot(mn) > 0.99
	if same_wall or transfer_hint == Hint.UP:
		if same_wall and transfer_hint != Hint.UP:
			return false
		var dz: float = l.y - player.move_ledge_location.y
		if dz > c.allowed_z_transfer_distance or dz < 1.0 * UU:
			return false
	var n2: Vector3 = PawnPhysics.safe_normal_2d(mn)
	var r: float = player.default_collision_radius()
	var k: float = player.traces.calculate_relative_extent(r) + r
	transfer_location = Vector3(l.x + n2.x * k, l.y - config.grab.grab_desired_ledge_offset_z, l.z + n2.z * k)
	transfer_look_at_location = l
	transfer_normal = n2
	transfer_ledge_normal = hit["ledge_normal"]
	player.found_ledge = true
	return true

## UTdMove_GrabTransfer::LadderTransfer: a ladder volume (not the one being
## climbed) along the way, the body's box swept from in front of it at hand
## height.
func ladder_transfer() -> bool:
	var c: GrabTransferConfig = _transfer_cfg()
	var d: Vector3
	match transfer_hint:
		Hint.RIGHT:
			d = PawnPhysics.safe_normal_2d(UE.cross(Vector3.UP, player.facing()))
		Hint.LEFT:
			d = -PawnPhysics.safe_normal_2d(UE.cross(Vector3.UP, player.facing()))
		Hint.NONE:
			# The CONTROLLER's Rotation.Vector(), not the pawn's: where the
			# view looks. [ME:CONFIRMED decompile 0x01208520]
			d = PawnPhysics.safe_normal_2d(UE.rot_dir(player.controller_pitch_units(),
				UE.yaw_units(player.rotation.y)))
		_:
			# Up: the original never writes the direction, and what its stack
			# slot holds then is whatever the script machine left there
			# [ME:UNKNOWN N7 §4]. Nothing deterministic to port: no ladder.
			d = Vector3.ZERO
	var r: float = player.collision_radius()
	var extent := Vector3(r, MoveTraces.HAND_PLANT_EXTENT_CHECK_HEIGHT, r)
	var start: Vector3 = player.global_position + d * MoveTraces.HAND_PLANT_EXTENT_CHECK_WIDTH * 2.0
	start.y += MoveTraces.HAND_PLANT_CHECK_HEIGHT - player.default_collision_half_height()
	var end: Vector3 = start + d * c.allowed_2d_transfer_distance
	transfer_ladder = null
	var climbing: LadderVolume = null
	if player.movement_state == CLIMB:
		climbing = (player.move_manager.move_for(CLIMB) as ClimbMove).ladder
	for line: InterestLine in player.movement_volumes_along(start, end, extent, InterestLine.Kind.LADDER):
		if climbing == null or climbing.line != line:
			transfer_ladder = LadderVolume.new(line)
	if transfer_ladder == null:
		return false
	var centre: Vector3 = transfer_ladder.center()
	transfer_look_at_location = Vector3(centre.x, start.y, centre.z)
	var step: int = mini(transfer_ladder.get_last_step(),
		maxi(0, transfer_ladder.get_closest_step(player.global_position.y)))
	transfer_location = transfer_ladder.get_ladder_location(step)
	transfer_normal = transfer_ladder.wall_normal()
	return true

## TdMove_GrabTransfer.CheckReachableVaultOver: with the transfer's ledge as
## the ledge, can VaultOver take it from here?
func check_reachable_vault_over() -> bool:
	var ledge_location: Vector3 = player.move_ledge_location
	player.move_ledge_location = transfer_look_at_location
	var start: Vector3 = player.global_position
	var end: Vector3 = start
	end.y = player.move_ledge_location.y + player.collision_half_height()
	# The sweep runs from the raised point DOWN to the body, as written.
	if player.traces.movement_trace_for_blocking(start, end, player.collision_extent()):
		return false
	if player.move_manager.can_do(VAULT_OVER):
		transfer_move = VAULT_OVER
		return true
	player.move_ledge_location = ledge_location
	return false

## TdMove_GrabTransfer.StartMove.
func enter(_previous: StringName) -> void:
	if not fit_for_grab and transfer_move == VAULT_OVER:
		player.collide_world = false
	player.anim_slot.stop(0.1)
	player.use_root_motion(false)
	player.use_root_rotation(false)
	disable_face_rotation = true
	transfer_distance = (transfer_location - player.global_position).length()
	player.move_location = transfer_location
	player.move_normal = transfer_normal
	player.move_ledge_location = transfer_look_at_location
	player.move_ledge_normal = transfer_ledge_normal
	transfer_speed = maxf(transfer_distance / 0.55, 200.0 * UU)
	if transfer_hint != Hint.UP:
		set_look_at_target_location(transfer_look_at_location, 0.2)
		play_slot_anim(&"HangTurnRightStart" if transfer_hint == Hint.RIGHT else &"HangTurnLeftStart",
			1.0, 0.2, 0.1)
		set_timer(0.2)
	else:
		on_timer()

## TdMove_GrabTransfer.StopMove.
func exit() -> void:
	player.gravity_modifier = 1.0
	player.collide_world = true
	ladder = null

func play_transfer_animation() -> void:
	player.gravity_modifier = 0.85
	if transfer_hint == Hint.UP:
		play_slot_anim(&"hangfreetransferup" if _grab().is_hanging_free() else &"hangtransferup", 1.0, 0.1, 0.1)
	else:
		play_slot_anim(&"HangTurnJump", 1.0, 0.2, 0.2)

## The flight: after the turn, or at once going up.
func on_timer() -> void:
	set_precise_location(transfer_location, transfer_speed, PLM_FLY)
	player.face_rotation_time_left = 0.5
	play_transfer_animation()
	if transfer_move != VAULT_OVER:
		set_look_at_target_location(transfer_look_at_location, 0.8)
	else:
		reset_camera_look(0.2)
	disable_face_rotation = false

## TdMove_GrabTransfer.ReachedPreciseLocation.
func reached_precise_location() -> void:
	player.velocity = Vector3.ZERO
	player.acceleration = Vector3.ZERO
	player.global_position = transfer_location
	if transfer_move == INTO_CLIMB:
		var into: IntoClimbMove = player.move_manager.move_for(INTO_CLIMB) as IntoClimbMove
		var climb: ClimbMove = player.move_manager.move_for(CLIMB) as ClimbMove
		into.ladder = transfer_ladder
		climb.ladder = transfer_ladder
		if into.can_do_move():
			player.move_manager.set_move(INTO_CLIMB)
			player.clear_active_movement_volume()
		else:
			into.ladder = null
			climb.ladder = null
			player.move_manager.set_move(FALLING)
	else:
		player.move_manager.set_move(transfer_move)

func failed_to_reach_precise_location() -> void:
	player.move_manager.set_move(FALLING)

func hit_wall(_normal: Vector3, _collider: Object) -> void:
	player.move_manager.set_move(FALLING)

## For the animation: the hands going up to a hold above (hangtransferup in
## the original), as opposed to a turn across to one beside.
func is_transfer_up() -> bool:
	return transfer_hint == Hint.UP

## The scripted-fit hook (CharacterAnimator._scripted_fit): going up, the
## flight's own length, so the clip lands the hands when the body arrives;
## 0 for the sideways transfer, which plays its turn at its authored rate.
func scripted_duration() -> float:
	if transfer_hint != Hint.UP or transfer_speed <= 0.0:
		return 0.0
	return transfer_distance / transfer_speed
