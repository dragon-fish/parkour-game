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

## Largest vertical component a side-ray hit's normal may have and still count
## as a wall to run along (~17 degrees off vertical). Well below
## PawnConfig.walkable_floor_z's ~45 degrees on purpose: this gate
## excludes a floor or a shallow ramp a side ray could graze, not merely "too
## steep to walk on".
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
var _vault_over: RayCast3D
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
	if _vault_over == null:
		_vault_over = get_node("VaultOverDown")
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
	var tallest_reachable: float = maxf(_config.grab.ledge_max_height, _config.speed_vault.vault_max_height)
	var origin_y: float = tallest_reachable - _foot_offset + SURFACE_ORIGIN_MARGIN
	_surface.position = Vector3(0.0, origin_y, -reach)
	_surface.target_position = Vector3(0.0, -(origin_y + _foot_offset + SURFACE_UNDERSHOOT), 0.0)
	_surface.force_raycast_update()

## An obstacle low enough to vault: blocked at shin height by a genuinely
## unwalkable face (not a slope the player would just walk up), clear at
## chest height, with a walkable top within vault_max_height of the feet.
func vault_query() -> Dictionary:
	if _config == null:
		return _no_hit()
	_ensure_rays()
	# BOTH forward rays at vault_reach: the chest-clearance test is part of the
	# vault question and must be asked at the vault's own distance. See
	# _aim_forward().
	_aim_forward(_vault_low, _config.speed_vault.vault_reach)
	_aim_forward(_vault_high, _config.speed_vault.vault_reach)
	if not _vault_low.is_colliding():
		return _no_hit()

	# A shin-height hit whose surface is walkable (normal.y at or above
	# walkable_floor_z) is ground CharacterBody3D's own locomotion
	# already climbs -- a ramp, not an obstacle face -- and must never read as
	# something to vault. Without this, a plain climbable slope satisfies
	# every other gate below: the shin ray hits its rising surface, the chest
	# ray clears it (no realistic ramp angle blocks chest height), and its own
	# walkable top sits within vault_max_height of the feet. Measured directly
	# on the arena's 18.4 degree UpRamp: the shin ray reports normal
	# (0, 0.949, 0.316) -- comfortably above the threshold -- which is exactly
	# what used to re-trigger the vault on every step up it.
	#
	# Unlike SurfaceDown below, VaultLow has hit_from_inside left at its
	# default (false), so a hit here is always a genuine surface normal, never
	# the degenerate (0,0,0) that hit_from_inside can report -- no extra guard
	# is needed against that case.
	if _vault_low.get_collision_normal().y >= _config.pawn.walkable_floor_z:
		return _no_hit()

	if _vault_high.is_colliding():
		return _no_hit()

	_query_surface(_config.speed_vault.vault_reach)
	if not _surface.is_colliding():
		return _no_hit()
	var top: Vector3 = _surface.get_collision_point()
	var normal: Vector3 = _surface.get_collision_normal()
	# A DEGENERATE (zero-length) normal, not a shallow one, is what
	# hit_from_inside reports when SurfaceDown's own origin starts inside
	# solid geometry -- there is no real surface to read a slope from.
	# Rejecting on normal.y here (0.0 < walkable_floor_z) would reject for
	# the wrong reason: the height check below already rejects it correctly,
	# because _query_surface() places this ray's origin SURFACE_ORIGIN_MARGIN
	# above the tallest reachable top by construction.
	# Measured: this case reports the ray's own origin as the collision point
	# with normal (0,0,0), never a shallow-but-nonzero slope normal.
	if normal != Vector3.ZERO and normal.y < _config.pawn.walkable_floor_z:
		return _no_hit()
	var height := top.y - _feet_y()
	# MIN_HEIGHT_EPSILON, not 0.0: see its declaration for the floor-noise
	# case this guards against.
	if height <= MIN_HEIGHT_EPSILON or height > _config.speed_vault.vault_max_height:
		return _no_hit()

	# `height` itself is not a new measurement -- it is the same local this
	# function already computed and gated on above, now simply exposed.
	# ✅ Its role is confirmed (05 §5.7 axis 1, MinHeight/MaxHeight per variant:
	# 0/48/64/145 uu), but that axis is a set of per-variant THRESHOLDS this
	# quantity gets compared against, not a single source value of its own, so
	# there is no one "raw uu" to cite for the field itself. Every existing
	# caller of vault_query() was already recomputing this from `top` and its
	# own copy of the foot offset; returning it here removes that duplication.

	# Horizontal distance from the body origin to the obstacle face. The
	# lookahead in SpeedVaultMove divides this by horizontal speed, so it has
	# to be measured to the FACE (VaultLow's own hit), not to the top surface
	# SurfaceDown found further along the ray.
	#
	# Source: 05 §5.7 axis 5, MaxDistanceTime (0.2 / 0.4 s). ⚠️ The original
	# names that field "Distance" but stores a TIME; the research's own
	# inferred (not bytecode-confirmed) read is
	# time_to_ledge = distance / horizontal_speed, checked every frame against
	# that time budget. This field is that formula's NUMERATOR -- the raw
	# distance -- leaving the division, and which speed to divide by, to
	# whichever move reads it next.
	var face_point: Vector3 = _vault_low.get_collision_point()
	var to_face := face_point - global_position
	var distance: float = Vector2(to_face.x, to_face.z).length()

	# bVaultOnto is functionally the obstacle's thickness (05 §5.7 axis 2,
	# ✅ confirmed as a CONCEPT -- "true = vault up and stand on top, false =
	# vault through and keep running, functionally equivalent to the
	# obstacle's thickness/width, decided by TdPhysicsMove.bCheckForVaultOver's
	# probe"). ❓ The probe's own mechanics are not documented anywhere in the
	# research (no distance, no comparison rule survives in the decompile), so
	# everything below this point -- vault_over_probe_distance, where the ray
	# goes, and how its hit is judged -- is this project's own invention, not
	# a transcription.
	var vault_over: bool = _query_vault_over(top, normal)

	return {
		"valid": true, "top": top, "edge": top, "normal": normal,
		"height": height, "distance": distance, "vault_over": vault_over,
	}

## Fires VaultOverDown to tell "there is floor on the far side" (vault OVER)
## from "this thing is thick" (only its own top exists -- vault ONTO). Written
## parallel to _query_surface(): geometry is recomputed from the live config
## on every call, never baked (see setup()'s own note on why).
##
## `top` is _query_surface()'s own hit point for the CURRENT query, which
## sits at a FIXED forward distance (vault_reach) regardless of how deep the
## real obstacle is -- this rig has no ray dedicated to finding the actual far
## edge. VaultOverDown is placed vault_over_probe_distance further past that
## fixed point and fired down. For a thin obstacle, the fixed point already
## sits near its real far face, so a short additional probe clears it onto
## real floor. For a thick one, the same fixed point is still well inside the
## obstacle, so the probe lands on more of its OWN top -- at exactly the same
## height as `top`, not a lower, genuinely different surface. That is why the
## height check below requires the hit to be MEANINGFULLY below top.y (by
## MIN_HEIGHT_EPSILON, reusing its existing floor-noise budget rather than
## inventing a second tolerance for the same solver noise): an equal-height
## hit is the obstacle continuing under the probe, not a landing spot beyond
## it. `normal` (the obstacle top's own surface normal) is accepted to keep
## this call symmetric with the surface data vault_query() already has in
## hand, but is not needed by the check itself -- vault_query() already
## rejected an unwalkable top before this is ever called.
func _query_vault_over(top: Vector3, normal: Vector3) -> bool:
	var local_top: Vector3 = to_local(top)
	var origin_y: float = local_top.y + SURFACE_ORIGIN_MARGIN
	_vault_over.position = Vector3(local_top.x, origin_y, \
			local_top.z - _config.speed_vault.vault_over_probe_distance)
	_vault_over.target_position = Vector3(0.0, -(origin_y + _foot_offset + SURFACE_UNDERSHOOT), 0.0)
	_vault_over.force_raycast_update()
	if not _vault_over.is_colliding():
		return false
	if _vault_over.get_collision_normal().y < _config.pawn.walkable_floor_z:
		return false
	return _vault_over.get_collision_point().y <= top.y - MIN_HEIGHT_EPSILON

## A ledge high enough to hang from but still within reach.
func ledge_query() -> Dictionary:
	if _config == null:
		return _no_hit()
	_ensure_rays()
	_aim_forward(_vault_high, _config.grab.ledge_reach)
	if not _vault_high.is_colliding():
		return _no_hit()

	_query_surface(_config.grab.ledge_reach)
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
	if normal != Vector3.ZERO and normal.y < _config.pawn.walkable_floor_z:
		return _no_hit()
	var height := edge.y - _feet_y()
	# height <= MIN_HEIGHT_EPSILON, not just < ledge_min_height: guards the
	# same floor-noise case as vault_query() (see MIN_HEIGHT_EPSILON's
	# declaration) before the real ledge_min_height gate below it.
	if height <= MIN_HEIGHT_EPSILON or height < _config.grab.ledge_min_height \
			or height > _config.grab.ledge_max_height:
		return _no_hit()
	return {"valid": true, "top": edge, "edge": edge, "normal": normal}

## Points a side ray at the given reach and fires it. Aimed live from the
## config on every call, same as _aim_forward() above and for the same
## reason: baking the reach into the ray once (e.g. in setup()) would freeze
## it at whatever the config held on the tick the player spawned, and the F1
## panel's own slider would silently stop doing anything the moment setup()
## had already run.
func _aim_side(ray: RayCast3D, side_sign: float, reach: float) -> void:
	ray.target_position = Vector3(side_sign * reach, 0.0, 0.0)
	ray.force_raycast_update()

## Angle between the player's heading and the wall PLANE, in radians: 0 means
## running straight at the wall, PI/2 means running exactly parallel to it.
## `normal` points AWAY from the wall (back toward the player), so a head-on
## approach has heading ≈ -normal, i.e. heading.dot(normal) ≈ -1.
##
## Verified numerically rather than trusted from the source table's own field
## names (see this task's report): the original's own draft formula for this,
## asin(dot), does NOT reach 0 at head-on (asin(-1) is -PI/2). acos(-dot)
## does -- acos(1) = 0 at dot = -1 (head-on), acos(0) = PI/2 at dot = 0
## (perpendicular to normal, i.e. parallel to the wall's face).
##
## Source: 04 §4.1 -- the original branches hard on this (0-57 degrees takes
## the forward branch, 60+ takes the strafe branch; the three-degree gap
## between them is a deliberate hysteresis band that keeps a borderline
## approach from flickering).
func _incidence(normal: Vector3, heading: Vector3) -> float:
	return acos(clampf(-heading.dot(normal), -1.0, 1.0))

## A wall close enough on either side to run along. `side` is -1 for a wall on
## the player's left and +1 for one on the right; the normal points AWAY from
## the wall surface, i.e. back toward the player. `heading` is the player's
## horizontal velocity direction as a UNIT vector (Vector3.ZERO -- the
## default -- is a safe, neutral stand-in when there is no heading to measure;
## see _incidence()'s own note, it reads as "parallel").
func wall_query(heading: Vector3 = Vector3.ZERO) -> Dictionary:
	if _config == null:
		return {"valid": false, "normal": Vector3.ZERO, "side": 0, "incidence": 0.0}
	_ensure_rays()

	# Reads wall_running_forward_check_distance -- this project has only ONE
	# side-ray reach, not a distinct forward/strafe pair the way the original
	# does, so it borrows the forward field's value (0.5, replacing this
	# project's own former wall_reach of 0.75). See WallRunConfig's own note
	# on that field.
	var reach: float = _config.wall_run.wall_running_forward_check_distance
	_aim_side(_wall_left, -1.0, reach)
	if _wall_left.is_colliding():
		var normal: Vector3 = _wall_left.get_collision_normal()
		# Only a near-vertical surface counts as a wall -- MAX_WALL_NORMAL_Y is
		# a stricter gate than vault/ledge's walkable_floor_z (which admits
		# anything up to ~45 degrees): a wall to run along must be close to
		# vertical, not merely "too steep to stand on".
		if absf(normal.y) < MAX_WALL_NORMAL_Y:
			return {"valid": true, "normal": normal, "side": -1, \
				"incidence": _incidence(normal, heading)}

	_aim_side(_wall_right, 1.0, reach)
	if _wall_right.is_colliding():
		var normal: Vector3 = _wall_right.get_collision_normal()
		if absf(normal.y) < MAX_WALL_NORMAL_Y:
			return {"valid": true, "normal": normal, "side": 1, \
				"incidence": _incidence(normal, heading)}

	return {"valid": false, "normal": Vector3.ZERO, "side": 0, "incidence": 0.0}
