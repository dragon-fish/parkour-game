class_name SpeedVaultConfig
extends MoveConfig

# The original's TdMove_SpeedVault, CDO and DefaultPawnMovement.ini
# [TdGame.TdMove_SpeedVault]. [ME:CONFIRMED decompile] Metric. TdMove_VaultOver
# derives from it and its ini section is empty, so it reads these same values.
# What each value does is in SpeedVaultMove.

## VaultClearObjectHeight, 35 uu: how far over the ledge the vault-onto sweep
## runs.
@export var vault_clear_object_height: float = 0.35
## MaxTimeToLedge, 0.4 s: the hand plant must be this close at the approach
## speed (at least 300 uu/s).
@export var max_time_to_ledge: float = 0.4

## VaultTypes, in the ini's order -- the first row that admits the approach
## wins (UpdateActiveVaultType). Metric; a field the ini line leaves out takes
## the struct's default (MinMomentum / MaxMomentum -1 = unchecked, MinSpeedZ /
## MaxSpeedZ 0, VaultTimeUp 0, VaultTimeOver / VaultTimeDown 0.2, offsets 0).
## Offsets are (along the move, up) as the moves read them: HandplantOffset.Y /
## .Z and LedgeOffset.Y / .Z. Speeds are m/s; -1 stays the "unchecked" marker
## in uu/s, UNCHECKED here.
var vault_types: Array[Dictionary] = [
	_type(&"autostepuprightleg", true, 0, 48, -600, 0, -1, -1, 0.2, 100, 300, 0,
		0.0, 0.3, 0.2, Vector2(0, 5), Vector2(0, 90), false),
	_type(&"stepuprightleg88", true, 48, 148, 0, 700, -1, 200, 0.4, 200, 700, 0,
		0.0, 0.4, 0.25, Vector2(0, 0), Vector2(-20, 60), false),
	_type(&"vaultOnto", true, 64, 148, 0, 10000, -1, -1, 0.4, 400, 720, 80,
		0.0, 0.35, 0.3, Vector2(0, 5), Vector2(0, 25), false),
	_type(&"vaultOver", false, 64, 148, 0, 10000, -1, -1, 0.4, 400, 720, 80,
		0.0, 0.35, 0.3, Vector2(0, 5), Vector2(0, 25), false),
	_type(&"VaultOverHigh", false, 145, 192, 50, 10000, -1, -1, 0.4, 200, 400, 0,
		0.28, 0.3, 0.45, Vector2(-40, -69), Vector2(0, 5), true),
	_type(&"VaultOntoHigh", true, 145, 192, 50, 10000, -1, -1, 0.4, 200, 400, 0,
		0.27, 0.3, 0.6, Vector2(-65, -15), Vector2(0, 35), true),
]

## One VaultTypes row, given in the ini's units (uu, uu/s, s).
static func _type(anim: StringName, onto: bool, min_h: float, max_h: float,
		min_speed_z: float, max_speed_z: float, min_momentum: float, max_momentum: float,
		max_distance_time: float, clamp_min: float, clamp_max: float, speed_addition: float,
		time_up: float, time_over: float, time_down: float, handplant_offset: Vector2,
		ledge_offset: Vector2, reset_camera: bool) -> Dictionary:
	return {
		"anim": anim, "vault_onto": onto,
		"min_height": min_h * UU, "max_height": max_h * UU,
		"min_speed_z": min_speed_z * UU, "max_speed_z": max_speed_z * UU,
		"min_momentum": min_momentum * UU, "max_momentum": max_momentum * UU,
		"max_distance_time": max_distance_time,
		"clamp_speed_min": clamp_min * UU, "clamp_speed_max": clamp_max * UU,
		"speed_addition": speed_addition * UU,
		"vault_time_up": time_up, "vault_time_over": time_over, "vault_time_down": time_down,
		"handplant_offset": handplant_offset * UU, "ledge_offset": ledge_offset * UU,
		"reset_camera": reset_camera,
	}

const UU := 0.01
## The struct's -1 "unchecked" marker, in m/s.
const UNCHECKED := -1.0 * UU

# --- this project's probe -------------------------------------------------------
#
# Read by Probes.vault_query() (the debug overlay and the moves not yet ported),
# never by SpeedVaultMove.

## How far ahead of the body the probe reaches.
@export var vault_reach: float = 1.4
## How far past the obstacle's far face the probe looks for a floor.
@export var vault_over_probe_distance: float = 0.5
## The highest edge above the feet the probe considers.
@export var max_edge_above_feet: float = 1.89

## The tallest MaxHeight in the table.
func table_ceiling() -> float:
	var ceiling: float = 0.0
	for v in vault_types:
		ceiling = maxf(ceiling, v["max_height"])
	return ceiling

func _init() -> void:
	# This project's hook: the torus wrap waits while the move holds a world
	# position.
	holds_world_path = true
	# bConstrainLook, relative to the pawn: pitch -3000 .. 6000, yaw +-8000.
	constrain_look = true
	min_look_constraint = Vector3(-3000.0, -8000.0, -32768.0) / UE.UNITS_PER_RADIAN
	max_look_constraint = Vector3(6000.0, 8000.0, 32768.0) / UE.UNITS_PER_RADIAN
	# A drop behind the obstacle counts from its top. See
	# MoveConfig.fall_counts_from_exit.
	fall_counts_from_exit = true
