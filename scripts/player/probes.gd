class_name Probes
extends Node3D

# Environment queries for the parkour states. Every height in the returned
# dictionaries is a WORLD y, while every configured height is measured from
# the player's feet — the conversion happens here so the states never have to
# think about the capsule's origin offset.

# Template for a "nothing found" result. NEVER return this dictionary
# directly -- it is a `const`, so it is read-only (is_read_only() == true) AND
# every caller of vault_query()/ledge_query() that gets a miss would receive
# the SAME shared instance. A future state that tries to mutate its result
# (e.g. `result["top"] = something`) would hit a read-only error instead of a
# normal bug. Use _no_hit() below, which duplicates it, instead.
const NO_HIT := {"valid": false, "top": Vector3.ZERO, "edge": Vector3.ZERO, "normal": Vector3.UP}

func _no_hit() -> Dictionary:
	return NO_HIT.duplicate()

# Floor noise guard: force_raycast_update() on a ray whose origin sits
# essentially AT a walkable surface (e.g. the floor itself, or -- after
# hit_from_inside -- a ray reporting its own origin) can report a height a
# fraction of a millimetre off zero in either direction, purely from physics
# solver noise. Measured directly: two floor-level hits during testing came
# back as height -0.0002 and -0.0005 rather than an exact 0.0. Without an
# epsilon, `height <= 0.0` treats the positive-noise case as a valid vaultable
# surface -- i.e. the floor under the player's own feet can register as an
# obstacle. 0.02 m is comfortably above any noise observed and comfortably
# below the shortest obstacle this rig can even see (see VaultLow's own
# height limit, documented in the generator).
const MIN_HEIGHT_EPSILON := 0.02

## Smallest upward component a surface normal may have and still count as a top
## to stand on rather than a wall to bounce off (~45 degrees). Named once
## because both queries apply it and a hardcoded literal in each is two places
## for the same decision to drift apart.
const MIN_WALKABLE_NORMAL_Y := 0.7

## Largest vertical component a side-ray hit's normal may have and still count
## as a wall to run along (~17 degrees off vertical). Well below
## MIN_WALKABLE_NORMAL_Y's ~45 degrees on purpose: this gate excludes a floor
## or a shallow ramp a side ray could graze, not merely "too steep to walk on".
const MAX_WALL_NORMAL_Y := 0.3

## SurfaceDown's origin is placed this far ABOVE the tallest surface the config
## says is reachable. Without headroom the ray starts level with the very ledge
## it is supposed to find and hit_from_inside reports its own origin instead.
const SURFACE_ORIGIN_MARGIN := 0.3

## ...and it reaches this far BELOW the feet, so a surface at exactly foot level
## still registers (and is then rejected by MIN_HEIGHT_EPSILON, on its height,
## rather than by the ray silently not reaching it).
const SURFACE_UNDERSHOOT := 0.1

# Looked up live via _ensure_rays() rather than cached in @onready vars: @onready
# resolves on Probes' own _ready(), but TestWorld.build() (and player.tscn's
# real instantiation path) calls Player.setup() -> Probes.setup() on the same
# tick the node enters the tree, before that _ready() has necessarily run.
# Caching here would leave these null the first time setup() touches them.
var _vault_low: RayCast3D
var _vault_high: RayCast3D
var _surface: RayCast3D
var _wall_left: RayCast3D
var _wall_right: RayCast3D

var _config: MovementConfig
var _foot_offset: float = 0.9

func _ensure_rays() -> void:
	if _vault_low == null:
		_vault_low = get_node("VaultLow")
	if _vault_high == null:
		_vault_high = get_node("VaultHigh")
	if _surface == null:
		_surface = get_node("SurfaceDown")
	if _wall_left == null:
		_wall_left = get_node("WallLeft")
	if _wall_right == null:
		_wall_right = get_node("WallRight")

## NOTE: this deliberately assigns NO ray geometry. Every ray's length and
## position is derived from the live config at query time instead (see
## _aim_forward() and _query_surface() below), because the F1 tuning panel
## writes straight into that same config object while the game runs. Anything
## baked in here would be a snapshot of the config as it was on the tick the
## player spawned: dragging vault_reach or ledge_reach would move only whatever
## still read the config live, and the queries would silently desynchronise
## from each other -- a slider that half-works, which is worse for the human
## tuning the game than one that does nothing.
func setup(cfg: MovementConfig, foot_offset: float) -> void:
	_ensure_rays()
	_config = cfg
	_foot_offset = foot_offset

func _feet_y() -> float:
	return global_position.y - _foot_offset

## Points a forward ray at the given reach and fires it. Rays point along -Z,
## which is the body's forward.
##
## Both queries share VaultHigh but need DIFFERENT reaches from it, so it is
## aimed per query rather than pinned once. It used to be pinned to
## max(vault_reach, ledge_reach), which handed the ledge configuration control
## over the vault's chest-clearance test: raise ledge_reach above vault_reach
## and VaultHigh starts finding obstacles that are none of vault_query()'s
## business, every one of which makes it return "this is a wall" and suppresses
## the vault entirely.
func _aim_forward(ray: RayCast3D, reach: float) -> void:
	ray.target_position = Vector3(0.0, 0.0, -reach)
	ray.force_raycast_update()

## Points SurfaceDown at the given forward reach and fires it. Shared by both
## queries, which need different reaches from the same ray: a vaultable
## obstacle sitting between ledge_reach and vault_reach would pass both forward
## rays (each using its own correct reach) but a downward ray fixed short at
## ledge_reach would land on bare floor past the obstacle's near edge and miss
## its top surface entirely.
##
## The ray's VERTICAL geometry is derived from the configured height limits
## rather than baked, so the panel cannot drive ledge_max_height past what the
## ray can see and leave the knob silently dead: it starts SURFACE_ORIGIN_MARGIN
## above the tallest reachable top and ends SURFACE_UNDERSHOOT below the feet.
## At the shipped defaults (ledge_max_height 2.8, foot offset 0.9) this
## reproduces exactly the values that used to be hardcoded here -- origin +2.2,
## length 3.2 -- so this is a re-derivation of the committed rig, not a retune
## of it.
func _query_surface(reach: float) -> void:
	var tallest_reachable: float = maxf(_config.ledge_max_height, _config.vault_max_height)
	var origin_y: float = tallest_reachable - _foot_offset + SURFACE_ORIGIN_MARGIN
	_surface.position = Vector3(0.0, origin_y, -reach)
	_surface.target_position = Vector3(0.0, -(origin_y + _foot_offset + SURFACE_UNDERSHOOT), 0.0)
	_surface.force_raycast_update()

## An obstacle low enough to vault: blocked at shin height, clear at chest
## height, with a walkable top within vault_max_height of the feet.
func vault_query() -> Dictionary:
	if _config == null:
		return _no_hit()
	_ensure_rays()
	# BOTH forward rays at vault_reach: the chest-clearance test is part of the
	# vault question and must be asked at the vault's own distance. See
	# _aim_forward().
	_aim_forward(_vault_low, _config.vault_reach)
	_aim_forward(_vault_high, _config.vault_reach)
	if not _vault_low.is_colliding():
		return _no_hit()
	if _vault_high.is_colliding():
		return _no_hit()

	_query_surface(_config.vault_reach)
	if not _surface.is_colliding():
		return _no_hit()
	var top: Vector3 = _surface.get_collision_point()
	var normal: Vector3 = _surface.get_collision_normal()
	# A DEGENERATE (zero-length) normal, not a shallow one, is what
	# hit_from_inside reports when SurfaceDown's own origin starts inside
	# solid geometry -- there is no real surface to read a slope from.
	# Rejecting on normal.y here (0.0 < MIN_WALKABLE_NORMAL_Y) would reject for
	# the wrong reason: the height check below already rejects it correctly,
	# because _query_surface() places this ray's origin SURFACE_ORIGIN_MARGIN
	# above the tallest reachable top by construction.
	# Measured: this case reports the ray's own origin as the collision point
	# with normal (0,0,0), never a shallow-but-nonzero slope normal.
	if normal != Vector3.ZERO and normal.y < MIN_WALKABLE_NORMAL_Y:
		return _no_hit()
	var height := top.y - _feet_y()
	# MIN_HEIGHT_EPSILON, not 0.0: see its declaration for the floor-noise
	# case this guards against.
	if height <= MIN_HEIGHT_EPSILON or height > _config.vault_max_height:
		return _no_hit()
	return {"valid": true, "top": top, "edge": top, "normal": normal}

## A ledge high enough to hang from but still within reach.
func ledge_query() -> Dictionary:
	if _config == null:
		return _no_hit()
	_ensure_rays()
	_aim_forward(_vault_high, _config.ledge_reach)
	if not _vault_high.is_colliding():
		return _no_hit()

	_query_surface(_config.ledge_reach)
	if not _surface.is_colliding():
		return _no_hit()
	var edge: Vector3 = _surface.get_collision_point()
	var normal: Vector3 = _surface.get_collision_normal()
	# See the matching comment in vault_query(): a zero-length normal means
	# SurfaceDown started inside solid geometry (hit_from_inside), not that it
	# found a steep, unwalkable slope. Let the height check below reject it --
	# _query_surface() places this ray's origin SURFACE_ORIGIN_MARGIN above
	# ledge_max_height by construction, so any wall tall enough to swallow it is
	# correctly rejected there instead.
	if normal != Vector3.ZERO and normal.y < MIN_WALKABLE_NORMAL_Y:
		return _no_hit()
	var height := edge.y - _feet_y()
	# height <= MIN_HEIGHT_EPSILON, not just < ledge_min_height: guards the
	# same floor-noise case as vault_query() (see MIN_HEIGHT_EPSILON's
	# declaration) before the real ledge_min_height gate below it.
	if height <= MIN_HEIGHT_EPSILON or height < _config.ledge_min_height \
			or height > _config.ledge_max_height:
		return _no_hit()
	return {"valid": true, "top": edge, "edge": edge, "normal": normal}

## Points a side ray at the given reach and fires it. Aimed live from the
## config on every call, same as _aim_forward() above and for the same
## reason: baking wall_reach into the ray once (e.g. in setup()) would freeze
## it at whatever the config held on the tick the player spawned, and the F1
## panel's wall_reach slider would silently stop doing anything the moment
## setup() had already run.
func _aim_side(ray: RayCast3D, side_sign: float, reach: float) -> void:
	ray.target_position = Vector3(side_sign * reach, 0.0, 0.0)
	ray.force_raycast_update()

## A wall close enough on either side to run along. `side` is -1 for a wall on
## the player's left and +1 for one on the right; the normal points AWAY from
## the wall surface, i.e. back toward the player.
func wall_query() -> Dictionary:
	if _config == null:
		return {"valid": false, "normal": Vector3.ZERO, "side": 0}
	_ensure_rays()

	_aim_side(_wall_left, -1.0, _config.wall_reach)
	if _wall_left.is_colliding():
		var normal: Vector3 = _wall_left.get_collision_normal()
		# Only a near-vertical surface counts as a wall -- MAX_WALL_NORMAL_Y is
		# a stricter gate than vault/ledge's MIN_WALKABLE_NORMAL_Y (which admits
		# anything up to ~45 degrees): a wall to run along must be close to
		# vertical, not merely "too steep to stand on".
		if absf(normal.y) < MAX_WALL_NORMAL_Y:
			return {"valid": true, "normal": normal, "side": -1}

	_aim_side(_wall_right, 1.0, _config.wall_reach)
	if _wall_right.is_colliding():
		var normal: Vector3 = _wall_right.get_collision_normal()
		if absf(normal.y) < MAX_WALL_NORMAL_Y:
			return {"valid": true, "normal": normal, "side": 1}

	return {"valid": false, "normal": Vector3.ZERO, "side": 0}
