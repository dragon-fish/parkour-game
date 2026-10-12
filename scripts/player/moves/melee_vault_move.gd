class_name MeleeVaultMove
extends MeleeBaseMove

# The original's TdMove_MeleeVault, ported without combat. [ME:CONFIRMED
# decompile script TdMove_MeleeVault]
#
# UNREACHABLE in the shipped game, as here: nothing in the scripts calls
# SetVaultProperties or sets MOVE_MeleeVault, and no native SetMove names it
# (N4 §2.4). Ported so the move exists as the original has it: a PLM_Jump
# flight to VaultEndPosition taking VaultTimeDown, the kick 0.3 s in, and on
# arrival the stored velocity handed back on walking physics.

## The original's 1P sequence length, seconds. [ME:CONFIRMED anims]

var vault_end_position: Vector3 = Vector3.ZERO
var vault_time_down: float = 0.0
var saved_velocity: Vector3 = Vector3.ZERO

func _init() -> void:
	super._init()
	movement_group = MG_ONE_HAND_BUSY
	pawn_physics = PHYS_FLYING
	disable_look_time = -1.0
	# [ME:CONFIRMED decompile] bDisableFaceRotation.
	disable_face_rotation = true

func set_vault_properties(end_position: Vector3, time_down: float, velocity: Vector3) -> void:
	vault_end_position = end_position
	vault_time_down = time_down
	saved_velocity = velocity

func enter(previous: StringName) -> void:
	super.enter(previous)
	player.set_grounded(false)
	var to: Vector3 = vault_end_position - player.global_position
	set_precise_location(vault_end_position,
		Vector2(to.x, to.z).length() / maxf(vault_time_down, 1e-6), PLM_JUMP)
	set_timer(0.3)

func reached_precise_location() -> void:
	_set_stored_velocity()

## SetStoredVelocity: walking physics again, with the stored speed and no
## downward speed. The controller's AccelerationTime (0.2) is not ported.
func _set_stored_velocity() -> void:
	if not hit_detection:
		return
	player.set_physics(PHYS_WALKING)
	saved_velocity.y = maxf(0.0, player.velocity.y)
	player.velocity = saved_velocity
	player.acceleration = PawnPhysics.safe_normal(saved_velocity)

func on_timer() -> void:
	play_move_anim(&"MeleeVaultOver", 1.0, 0.1, 0.1)
	hit_detection = true

func on_custom_anim_end(_anim_name: StringName) -> void:
	player.move_manager.set_move(WALKING)
	var walking: Move = player.move_manager.move_for(WALKING)
	if walking != null:
		walking.reset_camera_look(0.6)
