class_name Probes
extends Node3D

# Environment queries for the parkour states. Every height in the returned
# dictionaries is a WORLD y, while every configured height is measured from
# the player's feet — the conversion happens here so the states never have to
# think about the capsule's origin offset.

const NO_HIT := {"valid": false, "top": Vector3.ZERO, "edge": Vector3.ZERO, "normal": Vector3.UP}

# Looked up live via _ensure_rays() rather than cached in @onready vars: @onready
# resolves on Probes' own _ready(), but TestWorld.build() (and player.tscn's
# real instantiation path) calls Player.setup() -> Probes.setup() on the same
# tick the node enters the tree, before that _ready() has necessarily run.
# Caching here would leave these null the first time setup() touches them.
var _vault_low: RayCast3D
var _vault_high: RayCast3D
var _surface: RayCast3D

var _config: MovementConfig
var _foot_offset: float = 0.9

func _ensure_rays() -> void:
	if _vault_low == null:
		_vault_low = get_node("VaultLow")
	if _vault_high == null:
		_vault_high = get_node("VaultHigh")
	if _surface == null:
		_surface = get_node("SurfaceDown")

func setup(cfg: MovementConfig, foot_offset: float) -> void:
	_ensure_rays()
	_config = cfg
	_foot_offset = foot_offset
	# Apply the configured reaches to the rays, so vault_reach and ledge_reach
	# are genuinely tunable rather than decorative duplicates of a hardcoded
	# ray length. Rays point along -Z, which is the body's forward.
	_vault_low.target_position = Vector3(0.0, 0.0, -cfg.vault_reach)
	_vault_high.target_position = Vector3(0.0, 0.0, -maxf(cfg.vault_reach, cfg.ledge_reach))
	_surface.position = Vector3(0.0, _surface.position.y, -cfg.ledge_reach)

func _feet_y() -> float:
	return global_position.y - _foot_offset

## An obstacle low enough to vault: blocked at shin height, clear at chest
## height, with a walkable top within vault_max_height of the feet.
func vault_query() -> Dictionary:
	if _config == null:
		return NO_HIT
	_ensure_rays()
	_vault_low.force_raycast_update()
	_vault_high.force_raycast_update()
	if not _vault_low.is_colliding():
		return NO_HIT
	if _vault_high.is_colliding():
		return NO_HIT

	_surface.force_raycast_update()
	if not _surface.is_colliding():
		return NO_HIT
	var top: Vector3 = _surface.get_collision_point()
	var normal: Vector3 = _surface.get_collision_normal()
	if normal.y < 0.7:
		return NO_HIT
	var height := top.y - _feet_y()
	if height <= 0.0 or height > _config.vault_max_height:
		return NO_HIT
	return {"valid": true, "top": top, "edge": top, "normal": normal}

## A ledge high enough to hang from but still within reach.
func ledge_query() -> Dictionary:
	if _config == null:
		return NO_HIT
	_ensure_rays()
	_vault_high.force_raycast_update()
	if not _vault_high.is_colliding():
		return NO_HIT

	_surface.force_raycast_update()
	if not _surface.is_colliding():
		return NO_HIT
	var edge: Vector3 = _surface.get_collision_point()
	var normal: Vector3 = _surface.get_collision_normal()
	if normal.y < 0.7:
		return NO_HIT
	var height := edge.y - _feet_y()
	if height < _config.ledge_min_height or height > _config.ledge_max_height:
		return NO_HIT
	return {"valid": true, "top": edge, "edge": edge, "normal": normal}
