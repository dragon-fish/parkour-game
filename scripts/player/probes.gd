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

## A wall beside the body, straight out along `direction`, within `reach`
## metres of the capsule's centre line -- {valid, point, normal, distance}.
##
## For the hand-on-wall touch: the point is the PERPENDICULAR foot of the
## capsule on the wall (a straight side ray IS that perpendicular whenever the
## wall is parallel to travel, and close enough everywhere else). Cast at
## shoulder height -- the capsule centre plus SIDE_TOUCH_SHOULDER -- because
## that is where an arm resting on a wall actually meets it.
const SIDE_TOUCH_SHOULDER := 0.4

func side_wall_query(direction: Vector3, reach: float) -> Dictionary:
	var origin: Vector3 = global_position + Vector3.UP * SIDE_TOUCH_SHOULDER
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() < 0.0001:
		return _no_hit()
	var params := PhysicsRayQueryParameters3D.create(
		origin, origin + flat.normalized() * reach)
	var parent := get_parent()
	if parent is CollisionObject3D:
		params.exclude = [(parent as CollisionObject3D).get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(params)
	if hit.is_empty():
		return _no_hit()
	var normal: Vector3 = hit["normal"]
	# Same wall-ness gate the run's side rays use: a floor or shallow ramp a
	# ray could graze is not a wall a palm rests on.
	if absf(normal.y) > MAX_WALL_NORMAL_Y:
		return _no_hit()
	return {"valid": true, "point": hit["position"], "normal": normal,
		"distance": origin.distance_to(hit["position"])}

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
#
# Used by ledge_query() only. vault_query() now floors at max_step_height
# instead -- see its own note there for why an epsilon was the wrong bound
# once a free step-up existed to handle everything below it.
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

## How far PAST the wall face ledge_query() plants its downward anchor probe.
##
## The two numbers in a ledge query mean different things and must not be the
## same number: ledge_find_distance (3.5 m) is how far ahead the forward ray
## may LOOK, while this is how far past whatever that ray actually FOUND the
## anchor sits. A raycast reports its first hit, so the forward ray is correct
## at any search radius; SurfaceDown is fired straight down from a fixed
## forward offset, so it is only ever correct if that offset tracks the real
## obstacle. Feeding it the search radius instead put the hang anchor (and,
## through GrabMove._edge, the mantle target) a flat 3.5 m ahead of the body
## regardless of where the wall stood.
##
## The value is bounded on both sides and 0.1 m sits between them:
##   * too SMALL and the ray grazes the face plane it is supposed to clear.
##     An exact tangency does not reliably register as a hit at all -- this
##     project has already been bitten by that once, when a test wall's near
##     face sat exactly at the probe reach (see tests/test_wall_run_entry.gd's
##     own note). 0.1 m is 5x MIN_HEIGHT_EPSILON's measured solver-noise
##     budget, so it is clear of noise as well as of tangency.
##   * too LARGE and it overshoots a thin lip: the anchor needs the ledge top
##     to be at least this deep, or the ray sails past the far face onto
##     whatever is behind and the grab is silently lost. 0.1 m asks for a
##     hand's width of ledge, which is less than any surface a body could
##     plausibly hang from and pull up onto.
##
## Deliberately NOT reused from SURFACE_UNDERSHOOT (also 0.1): that one is a
## VERTICAL reach allowance below the feet and answers a different question.
## Sharing the literal would tie two unrelated tolerances together.
const LEDGE_ANCHOR_MARGIN := 0.1

## Fractions of LEDGE_ANCHOR_MARGIN the ledge-top probe walks through when the
## first comes back empty. 1.0 FIRST, so geometry with nothing standing on it
## is probed exactly where it always was; the rest march toward the face, which
## is the barest part of any lip and the part the hands are actually on. See
## _top_beside() for the railing this exists for.
const INSET_LADDER := [1.0, 0.5, 0.25, 0.1]

## Height above the body's centre that the forward wall ray fires from, matching
## WallLeft/WallRight's own offset. ⚠️ PROJECT-DEFINED.
const WALL_AHEAD_CHEST_Y := 0.2

## How far above the SOLES a run's own contact ray fires.
##
## THE FEET ARE WHAT IS TOUCHING THE WALL. The owner caught this against the
## original: at the top of a wall run the eyes are well clear of the wall's own
## top edge and the run carries on regardless, because the contact point is down
## at the boots. Fired from the chest, as it was, a run ends the moment the
## wall's top passes 1.1 m above the soles -- a whole body-length of wall the
## original would still have been using.
##
## ⚠️ PROJECT-DEFINED, and small rather than zero: a ray fired exactly at the
## sole plane grazes the floor when a run ends at ground level.
const WALL_CONTACT_FOOT_MARGIN := 0.15

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
var _wall_ahead_low: RayCast3D
var _wall_ahead_high: RayCast3D

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
	if _wall_ahead_low == null:
		_wall_ahead_low = get_node("WallAheadLow")
	if _wall_ahead_high == null:
		_wall_ahead_high = get_node("WallAheadHigh")

## NOTE: this deliberately assigns NO ray geometry. Every ray's length and
## position is derived from the live config at query time instead (see
## _aim_forward() and _query_surface() below), because the F1 tuning panel
## writes straight into that same config object while the game runs. Anything
## baked in here would be a snapshot of the config as it was on the tick the
## player spawned: dragging vault_reach or ledge_find_distance would move only
## whatever still read the config live, and the queries would desynchronise
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
## max(vault_reach, ledge_find_distance), which handed the ledge configuration
## control over the vault's chest-clearance test: raise ledge_find_distance
## above vault_reach and VaultHigh starts finding obstacles that are none of
## vault_query()'s business, every one of which makes it return "this is a
## wall" and suppresses the vault entirely. That is no longer a hypothetical
## since ledge_find_distance moved to the confirmed 3.5 m: it now sits WELL
## past vault_reach (1.4 m) at the shipped defaults, so this per-query aiming
## is what keeps the vault working at all.
func _aim_forward(ray: RayCast3D, reach: float) -> void:
	ray.target_position = Vector3(0.0, 0.0, -reach)
	ray.force_raycast_update()

## Points SurfaceDown at the given forward offset and fires it. Shared by both
## queries, which ask for that offset in DIFFERENT ways, and the difference is
## load-bearing:
##   * vault_query() passes its own configured vault_reach -- a constant. That
##     is sound there because the vault's whole geometry (both forward rays,
##     the vault-over probe) is built around that same fixed distance, and
##     tests/test_probes_vault.gd's own fixtures are placed to straddle it.
##   * ledge_query() passes the distance to the face its forward ray actually
##     HIT, plus LEDGE_ANCHOR_MARGIN. It cannot pass its own configured
##     ledge_find_distance: unlike a raycast, this ray is planted at whatever
##     offset it is given and fired straight down, so a constant here would
##     report a "ledge" a fixed distance ahead of the body rather than the one
##     that was found. See LEDGE_ANCHOR_MARGIN for the full account.
##
## In both cases the point is the same: this ray must be aimed at the obstacle
## the ASKING query is asking about, never at some other distance that happens
## to be in the config.
##
## The ray's VERTICAL geometry is derived from the configured height limits
## rather than baked, so the panel cannot drive ledge_max_height past what the
## ray can see and leave the knob silently dead: it starts SURFACE_ORIGIN_MARGIN
## above the tallest reachable top and ends SURFACE_UNDERSHOOT below the feet.
## At the shipped defaults (ledge_max_height 2.8, foot offset 0.9) this
## reproduces exactly the values that used to be hardcoded here -- origin +2.2,
## length 3.2 -- so this is a re-derivation of the committed rig, not a retune
## of it.
## _query_surface(), but with the ray STOPPED just above the highest sample that
## hit rather than run all the way down to the feet.
##
## The column scan already knows roughly where the obstacle's top must be: it is
## above the highest sample that hit and below the first that did not. Ending
## the ray there stops it sailing past a thin obstacle's top and reporting the
## floor beyond, which is what made a chain-link fence invisible.
##
## `above` is a WORLD y.
func _query_surface_above(reach: float, above: float) -> void:
	var tallest_reachable: float = maxf(_config.grab.ledge_max_height, _config.speed_vault.table_ceiling())
	var origin_y: float = tallest_reachable - _foot_offset + SURFACE_ORIGIN_MARGIN
	_surface.position = Vector3(0.0, origin_y, -reach)
	var stop_at: float = above - MIN_HEIGHT_EPSILON
	var length: float = maxf((global_position.y + origin_y) - stop_at, 0.01)
	_surface.target_position = Vector3(0.0, -length, 0.0)
	_surface.force_raycast_update()

func _query_surface(reach: float) -> void:
	var tallest_reachable: float = maxf(_config.grab.ledge_max_height, _config.speed_vault.table_ceiling())
	var origin_y: float = tallest_reachable - _foot_offset + SURFACE_ORIGIN_MARGIN
	_surface.position = Vector3(0.0, origin_y, -reach)
	_surface.target_position = Vector3(0.0, -(origin_y + _foot_offset + SURFACE_UNDERSHOOT), 0.0)
	_surface.force_raycast_update()

## An obstacle low enough to vault: blocked at shin height by a genuinely
## unwalkable face (not a slope the player would just walk up), clear at
## chest height, with a walkable top within the vault table's own reach
## (SpeedVaultConfig.table_ceiling()) of the feet.
## Constants for the feet-to-eye column scan. See vault_query().
##
## ⚠️ PROJECT-DEFINED sample count. Six is enough that the coarsest gap between
## samples is about a hand's width on this body, which is finer than any
## obstacle edge the classification actually cares about, and cheap enough to
## fire every tick.
const COLUMN_SAMPLES := 6
## The lowest sample sits this far above the soles rather than at them, so the
## floor the player is standing on is never mistaken for an obstacle face.
const COLUMN_FLOOR_MARGIN := 0.1

## The ledge column is sampled FINER than the vault's, and the arithmetic is the
## reason rather than caution.
##
## What a vault looks for is the face of something solid, which spans a good
## part of the body's height. What a GRAB looks for can be the near edge of a
## flat platform -- a vertical strip only as tall as the plank is thick. Six
## samples over ledge_max_height is 0.56 m apart, and a 0.1 m edge falls
## straight between two of them. Measured: a flat suspended panel was invisible
## while the SAME panel tilted 20 degrees was found, purely because tilting it
## gave it a 0.68 m vertical profile to be hit.
##
## 14 samples is 0.2 m apart, which catches anything with a plausible plank's
## thickness. ⚠️ HONEST LIMIT: a plate thinner than that spacing can still slip
## through, and the fix for that would be a shapecast rather than more rays.
const LEDGE_COLUMN_SAMPLES := 14

func vault_query() -> Dictionary:
	if _config == null:
		return _no_hit()
	_ensure_rays()

	# A COLUMN OF FORWARD RAYS, FROM THE FEET TO THE EYE.
	#
	# This replaced a single shin-height ray, and the shin was the whole
	# problem. The owner could not vault a ventilation duct at all -- run at it
	# and you simply stop dead -- because a duct with open space beneath it has
	# NOTHING at shin height, so the old first gate refused the vault before
	# anything else was considered. Same for a chain-link fence.
	#
	# The column also expresses the classification rule directly rather than
	# needing a threshold bolted on beside it. The owner's account, confirmed
	# against the original with a stopwatch and a third-person camera (see
	# docs/feel-backlog.md 25-28): what decides the move is WHERE ON THE BODY
	# the obstacle's edge lands at contact, and what you can vault is what you
	# can get your hands on top of while jumping -- about eye height. So:
	#
	#   * the LOWEST sample that hits is where the face begins on the body
	#   * if the TOP sample -- at hand reach, 1.89 m above the feet -- still
	#     hits, the obstacle is not something to vault at all. It is a wall,
	#     and the grab probe's business.
	#
	# Measured from the FEET, and the feet move: the same duct is a vault when
	# met at the top of a jump and a wall when met from standing. That is not a
	# special case, it is what the frame predicts, and it is what the owner
	# observed as "with good jump timing even a taller obstacle vaults".
	var feet: float = _feet_y()
	# ✅ 1.89 m, measured twice from two different approaches. NOT the eye -- see
	# SpeedVaultConfig.max_edge_above_feet. A vault is a hands-on-top move, so
	# its ceiling is hand reach, which is a little above the head.
	var reach_ceiling: float = _config.speed_vault.max_edge_above_feet
	var reach: float = _config.speed_vault.vault_reach
	var lowest_face := Vector3.ZERO
	var lowest_normal := Vector3.ZERO
	var highest_hit_y: float = feet
	var found := false
	var blocked_at_reach := false
	for i in COLUMN_SAMPLES:
		var t: float = float(i) / float(COLUMN_SAMPLES - 1)
		var sample_y: float = lerpf(feet + COLUMN_FLOOR_MARGIN, feet + reach_ceiling, t)
		_vault_low.position.y = sample_y - global_position.y
		_aim_forward(_vault_low, reach)
		if not _vault_low.is_colliding():
			continue
		var normal: Vector3 = _vault_low.get_collision_normal()
		# A surface CharacterBody3D's own locomotion already climbs is a ramp,
		# not an obstacle face, and must never read as something to vault.
		# Measured on the arena's 18.4 degree UpRamp, whose shin-height normal
		# is (0, 0.949, 0.316): without this the ramp re-triggered a vault on
		# every step up it.
		if normal.y >= _config.pawn.walkable_floor_z:
			continue
		if i == COLUMN_SAMPLES - 1:
			blocked_at_reach = true
		highest_hit_y = maxf(highest_hit_y, sample_y)
		if not found:
			found = true
			lowest_face = _vault_low.get_collision_point()
			lowest_normal = normal
	if not found or blocked_at_reach:
		return _no_hit()

	var to_face := lowest_face - global_position
	var distance: float = Vector2(to_face.x, to_face.z).length()

	# PLANTED JUST PAST THE FACE THIS SCAN ACTUALLY FOUND, not at a fixed
	# vault_reach ahead. The fixed offset is what made this query go blind from
	# close up -- measured, it stopped reporting an obstacle about a metre out,
	# because the anchor sailed past it. See Move.touching() for the bug that
	# hid behind.
	# TWO TRIES, WITH A NARROWING FORWARD OFFSET.
	#
	# The anchor has to land ON the obstacle's top: too short and it grazes the
	# face plane it is meant to clear, too long and it sails past the far face
	# onto whatever is behind. LEDGE_ANCHOR_MARGIN (0.1) is tuned for the first
	# risk and loses to the second on anything THIN -- a chain-link fence is
	# 8 cm deep, so a 10 cm margin steps straight over it and finds the floor.
	#
	# Retrying at a smaller offset costs one raycast on the thin case and
	# nothing at all on every other, which is cheaper than a depth estimate
	# this rig has no way to make.
	var top: Vector3 = Vector3.ZERO
	var top_normal: Vector3 = Vector3.ZERO
	var landed := false
	# SMALLEST OFFSET FIRST. The anchor has to land ON the obstacle's top: too
	# short and it grazes the face plane it is meant to clear, too long and it
	# steps clean over anything thin. Trying the generous offset first meant a
	# 10 cm deep box was probed at 10 cm past its face -- exactly its own back
	# face -- and the thin case, which is the one that needs help, never reached
	# the retry.
	for margin in [LEDGE_ANCHOR_MARGIN * 0.3, LEDGE_ANCHOR_MARGIN]:
		_query_surface_above(distance + margin, highest_hit_y)
		if not _surface.is_colliding():
			continue
		var point: Vector3 = _surface.get_collision_point()
		# THE TOP MUST BE ABOVE THE HIGHEST SAMPLE THAT HIT, by construction:
		# the sample above it missed, so the surface lies between them.
		#
		# The margin is load-bearing rather than defensive. SurfaceDown has
		# hit_from_inside set, so a ray that ENDS inside the obstacle reports its
		# own endpoint as a surface -- and this ray is deliberately stopped just
		# below the highest hit, which is inside. Measured: a 0.8 m box reported
		# a "top" at 0.50, its own stop point, and the far-side probe then fired
		# from inside the box and found no lower ground. The owner saw that as a
		# thin box still being landed on instead of carried past.
		if point.y < highest_hit_y + MIN_HEIGHT_EPSILON:
			continue
		top = point
		top_normal = _surface.get_collision_normal()
		landed = true
		break
	if not landed:
		return _no_hit()
	var height := top.y - feet

	# NO LONGER A REFUSAL. Whether the top is walkable decides where the vault
	# LANDS -- over it, or on it -- and the owner settled that from play: a
	# fence and the cabinet beside it are the same height, and both report
	# VaultOver; the cabinet's wide top is simply where she ends up standing.
	# One axis for the family, another for the landing. Refusing the whole
	# vault on a top you cannot stand on is how a pipe became an invisible
	# wall.
	# FLATNESS ONLY. This says the top is not a slope; it says NOTHING about
	# whether the top is wide enough to stand on, which is a different question
	# and the one `vault_over` below answers. Confusing the two made every vault
	# land on the obstacle, because a fence's top is perfectly flat and merely
	# 8 cm deep.
	var standable: bool = top_normal == Vector3.ZERO 		or top_normal.y >= _config.pawn.walkable_floor_z

	if height <= _config.pawn.max_step_height or height > _config.speed_vault.table_ceiling():
		return _no_hit()
	var vault_over: bool = _query_vault_over(top)
	return {
		"valid": true, "top": top, "edge": top, "normal": top_normal,
		"height": height, "distance": distance, "vault_over": vault_over,
		"standable": standable,
		# WHERE THE FAR SIDE IS. A vault OVER lands here rather than on the
		# obstacle's own top -- measured, its peak sits 0.87 m BELOW that top
		# and the feet never clear it. See docs/feel-backlog.md 27.
		"far_point": _vault_over_point,
		"face_normal": lowest_normal,
		# WHERE THE OBSTACLE'S FACE IS, in world space. Returned so a move that
		# has committed can watch for CONTACT without re-querying -- see
		# Move.touching() and docs/contact-drives-movement.md.
		"face_point": lowest_face,
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
## it.
##
## Takes only `top`, not the obstacle top's own normal: an early draft of
## this signature carried it along for symmetry with the surface data
## vault_query() already has in hand, but there is no real check to spend it
## on -- vault_query() already rejected an unwalkable top before this is ever
## called, and the walkability that matters HERE is VaultOverDown's own hit
## normal, checked below. Dropped rather than kept as a decorative unused
## parameter.
## Where the far-side floor is, or ZERO if there is none low enough to vault
## onto. Written alongside _query_vault_over() rather than folded into it so the
## boolean's own call sites stay unchanged.
var _vault_over_point: Vector3 = Vector3.ZERO

func _query_vault_over(top: Vector3) -> bool:
	_vault_over_point = Vector3.ZERO
	var local_top: Vector3 = to_local(top)
	var origin_y: float = local_top.y + SURFACE_ORIGIN_MARGIN
	_vault_over.position = Vector3(local_top.x, origin_y, \
			local_top.z - _config.speed_vault.vault_over_probe_distance)
	# MEASURED DOWN FROM THE TOP, NOT FROM THE BODY.
	#
	# The length used to be built from the body's own foot offset, which quietly
	# assumed the top sits near the feet. Airborne it does not, and a vault is
	# committed in the air by definition -- so the ray stopped short of the far
	# side's floor and reported no lower ground, which refused to carry the
	# player past a thin obstacle. The owner saw it as a 0.1 m deep box still
	# being landed on rather than vaulted over.
	#
	# The question is "is there ground below this top", and the useful range for
	# it is a vault's own reach: anything further down is not a landing, it is a
	# drop. So the depth comes from the vault table, and the answer no longer
	# depends on where the body happened to be when it asked.
	var depth: float = _config.speed_vault.table_ceiling() + SURFACE_ORIGIN_MARGIN
	_vault_over.target_position = Vector3(0.0, -depth, 0.0)
	_vault_over.force_raycast_update()
	if not _vault_over.is_colliding():
		# NOTHING WITHIN A VAULT'S REACH IS STILL AN OVER, with no landing.
		#
		# ✅ The owner: a 2.2 m by 0.35 m wall put the player up on top of it to
		# take a step, which is absurd -- 0.35 m is not somewhere to stand. The
		# cause was this returning false and the variant table then falling
		# through to vault_onto.
		#
		# The two failures below are NOT the same thing, and the code already
		# tells them apart without having said so: a hit ABOVE the top means the
		# top is WIDE and the body would genuinely end up standing on it, while
		# NO HIT AT ALL means the probe is out past a thin obstacle's far face
		# with a drop beyond deeper than a vault reaches. One is somewhere to
		# stand; the other is a fence with a hole behind it.
		#
		# So this is an over with no far point, and the move lands the body past
		# the far face and lets it fall -- which is what happens to a person who
		# vaults a fence over a stairwell. It restores the axis this project set
		# out with: one question picks the FAMILY, another picks the LANDING.
		# See tests/test_probes_column_scan.gd's own note on that.
		return true
	if _vault_over.get_collision_normal().y < _config.pawn.walkable_floor_z:
		return false
	var landing: Vector3 = _vault_over.get_collision_point()
	if landing.y > top.y - MIN_HEIGHT_EPSILON:
		return false
	_vault_over_point = landing
	return true

## A ledge high enough to hang from but still within reach.
func ledge_query() -> Dictionary:
	if _config == null:
		return _no_hit()
	_ensure_rays()
	# A COLUMN, not one ray at chest height.
	#
	# Same failure the vault probe had, found the same way: the owner's route
	# grabs the near edge of a scaffold platform cantilevered off a wall, with
	# open space beneath it. A single chest-height ray passes straight under
	# such a thing and reports no face, so the ledge is invisible however
	# reachable it is. Measured: even a perfectly FLAT suspended panel came back
	# with no hit at all, which is why the tilt in the owner's first screenshot
	# turned out to be a red herring.
	#
	# Scanned up to ledge_max_height, unlike the vault's own column which stops
	# at hand reach. The two bound different things: a vault needs something the
	# hands can be planted ON, which the body's own size limits, while a grab
	# needs something they can REACH, which the jump limits. The owner put it
	# plainly on seeing this -- "so the original checks around the HANDS too,
	# not only the feet."
	#
	# SEARCH RADIUS is unchanged and still only that: a raycast reports its first
	# hit, so looking the confirmed 3.5 m ahead finds a wall at 1 m just as
	# correctly as one at 3 m.
	# ⚠️ EVERY BAND GETS A TURN, HIGHEST FIRST, and it used to be "the highest
	# hit wins" full stop -- one face, one down-probe, one height gate, and a
	# failure there failed the whole query.
	#
	# ✅ The owner, on a block with a smaller block built on top of it: "我对着这个
	# 障碍跳跃，它的 grab 判定点出现在高帽檐上而不是矮边缘，距离不够，什么都没抓住."
	# The cap presents a face too, it is higher, so it won -- and its top is out
	# of reach, so the gate rejected it and nothing else was ever tried. The
	# perfectly grabbable rim 1.5 m below it was never asked about.
	#
	# That is not a rare shape. Anything with a parapet, a plant box, a plinth
	# or another storey standing on it stacks two faces in this column, and the
	# lower one is the one the hands can reach.
	#
	# Highest first is still the PREFERENCE -- a higher grabbable ledge is more
	# progress than a lower one -- it is simply no longer the only candidate.
	# The suspended-platform case that "highest wins" was written for is
	# untouched: when only one band hits at all, it is both the highest and the
	# only one tried.
	#
	# Costs nothing on a plain wall, which is the common case: every band
	# reports the same face and the first one tried succeeds.
	for i in range(LEDGE_COLUMN_SAMPLES - 1, -1, -1):
		var t: float = float(i) / float(LEDGE_COLUMN_SAMPLES - 1)
		var sample_y: float = lerpf(_feet_y() + COLUMN_FLOOR_MARGIN,
			_feet_y() + _config.grab.ledge_max_height, t)
		_vault_high.position.y = sample_y - global_position.y
		_aim_forward(_vault_high, _config.grab.ledge_find_distance)
		if not _vault_high.is_colliding():
			continue
		var found: Dictionary = _ledge_from_face()
		if found.get("valid", false):
			return found
	return _no_hit()

## The ledge belonging to whatever `_vault_high` is currently touching, or a
## miss when that face carries nothing the hands can reach.
##
## Split out of ledge_query() so the column scan above can ask it once per band
## instead of once per query.
func _ledge_from_face() -> Dictionary:

	# ANCHOR, which is a different question -- see LEDGE_ANCHOR_MARGIN. The
	# down-probe is planted just past the face the forward ray ACTUALLY hit,
	# never at the search radius, because its hit is what the body ends up
	# hanging from and mantling to.
	#
	# Measured the same way vault_query() measures its own face distance (see
	# its `face_point` / `to_face` block, and the reasoning there about
	# measuring to the FACE rather than to the top surface SurfaceDown finds
	# further along) rather than by a second method of its own.
	var face_point: Vector3 = _vault_high.get_collision_point()
	var to_face := face_point - global_position
	var face_distance: float = Vector2(to_face.x, to_face.z).length()

	_query_surface(face_distance + LEDGE_ANCHOR_MARGIN)
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
	# height <= MIN_HEIGHT_EPSILON, not just < min_wall_height: guards the
	# same floor-noise case as vault_query() (see MIN_HEIGHT_EPSILON's
	# declaration) before the real min_wall_height gate below it.
	if height <= MIN_HEIGHT_EPSILON or height < _config.grab.min_wall_height \
			or height > _config.grab.ledge_max_height:
		return _no_hit()
	# THREE separate facts about the same ledge, and callers need different
	# ones:
	#   edge          a point on the ledge's TOP, where the body hangs from
	#   normal        that top surface's normal, i.e. roughly straight up
	#   face_normal   the WALL's normal, pointing back at the body
	#   face_distance how far the wall's face is, which `edge` does not say --
	#                 the top point sits behind the face by however deep the
	#                 obstacle is
	#
	# face_normal is what "square up to the wall" means. Facing the edge point
	# instead leaves the body skewed whenever the ledge was approached at an
	# angle, because the edge is off to one side of the wall it belongs to.
	return {"valid": true, "top": edge, "edge": edge, "normal": normal,
		"face_distance": face_distance, "face_point": face_point,
		# NOTE: whether a BODY would fit on top of this edge is deliberately not
		# answered here. That is a question about the body, not the geometry,
		# and Player.fits_standing_at() answers it with the shapecast that
		# already exists for exactly this.
		"face_normal": _vault_high.get_collision_normal()}

## Whether the ledge the player is hanging from continues `step` metres to one
## side, and where its top is if it does.
##
## A SEPARATE QUERY FROM ledge_query(), and it has to be. ledge_query() probes
## FORWARD from the body, and GrabMove.enter() already documents why that stops
## working the moment the grab completes: IntoGrab carries the body to the
## hanging pose, most of a body-length below the lip and 0.45 m back, and from
## there the forward ray no longer sees the edge it was carried to. Re-running
## it every shimmy tick would report "no ledge" while the player is visibly
## hanging from one.
##
## So this asks the question from ABOVE instead -- drop a ray onto where the
## hands are going and see whether the same top surface is still there. The
## anchor moves with the hands rather than with the body, which is also what
## makes it survive the player turning their head while they shimmy.
##
## Uses a direct space query rather than one of the persistent rays: those are
## children of the player and travel with it, while this one has to be fired
## from an arbitrary point out along the ledge. Same mask as SurfaceDown, read
## off it rather than restated, so the two cannot drift apart.
func ledge_beside(edge: Vector3, step: Vector3, outward: Vector3,
		margin: float, lift: float, tolerance: float) -> Dictionary:
	_ensure_rays()
	return _top_beside(edge + step, edge.y, outward, margin, lift, tolerance)

## The exposed top of a ledge near `target`, at `reference_y`, or a miss.
##
## ⚠️ TRIES MORE THAN ONE POINT, AND THAT IS THE WHOLE OF IT. A single probe a
## fixed LEDGE_ANCHOR_MARGIN inside the face assumes the strip it lands on is
## bare, and a railing standing on the ledge makes that false -- not by covering
## the ledge, but by occupying the one narrow column being asked about.
##
## ✅ THE OWNER'S WHITEBOX, where this was finally caught: two eaves of the same
## building, a fence on each, and the shimmy rounded their shared corner one way
## and refused the other. "从西边的屋檐可以去北边的屋檐，但是没办法爬回来."
## The two fences are set back by different amounts and the anchor lands 0.100 m
## in:
##
##   south eave   face z = 13.935    fence 13.974 .. 14.007    anchor 14.035  clear
##   west eave    face x = -6.048    fence -6.005 .. -5.943    anchor -5.948  INSIDE
##
## Three centimetres of level editing decides it. And the fences run from below
## the eave's own top right up past head height, so on the west eave that column
## is solid all the way: the probe begins inside it, and a ray that starts inside
## geometry reports nothing at all -- identical, from here, to "there is no ledge
## here".
##
## 📌 The margin point is tried FIRST, so anything without a railing on it
## behaves exactly as before. This is purely a fallback ladder.
func _top_beside(target: Vector3, reference_y: float, outward: Vector3,
		margin: float, lift: float, tolerance: float) -> Dictionary:
	var flat: Vector3 = outward
	flat.y = 0.0
	var has_face: bool = flat.length_squared() > 0.0001
	if has_face:
		flat = flat.normalized()
	# The face plane at this position: the anchor sits `margin` behind it.
	var face_plane: Vector3 = target + flat * margin if has_face else target
	var from := Vector3.ZERO
	var to := Vector3.ZERO
	for fraction in INSET_LADDER:
		var at: Vector3 = face_plane - flat * (margin * fraction) if has_face else target
		# THE SEGMENT TRAVELS WITH THE ANSWER, so a debug view draws the ray
		# actually fired rather than a second copy of the same arithmetic. On a
		# miss it is the LAST one tried, i.e. the closest to the face, which is
		# the interesting one to look at.
		from = at + Vector3.UP * lift
		to = at - Vector3.UP * tolerance
		var hit: Dictionary = _cast(from, to)
		if not hit.is_empty():
			# HEIGHT IS THE TEST, not merely "something is there". A ledge that
			# steps up or drops away is a different ledge, and shimmying onto it
			# would leave the hands at a height the hanging body was never
			# placed for.
			var found: Vector3 = hit["position"]
			if absf(found.y - reference_y) <= tolerance:
				return {"valid": true, "top": found, "edge": found,
					"normal": hit.get("normal", Vector3.UP), "from": from, "to": to}
		if not has_face:
			# Nothing to walk toward: one point is all there is to try.
			break
	return {"valid": false, "top": Vector3.ZERO, "edge": Vector3.ZERO,
		"normal": Vector3.UP, "from": from, "to": to}

## Whether the WALL FACE the hands hang from continues `step` metres to one
## side. `outward` is that face's normal, pointing away from the wall.
##
## ⚠️ A SEPARATE QUESTION FROM ledge_beside(), and leaving it unasked walks the
## hands off the outside corner of anything with depth. On a 6 m square block,
## hanging on the south face and travelling east, the TOP is still solidly under
## the probe well past the corner -- it is 6 m deep -- while the FACE the body
## is hanging from ended there. ledge_beside() alone therefore says "carry on"
## until the hands are over open air, diagonally off the corner.
##
## Fired BELOW the lip, because that is where a face is. Level with the anchor
## it would graze the top surface instead and report the ledge as its own wall.
func face_beside(edge: Vector3, step: Vector3, outward: Vector3,
		drop: float, margin: float) -> Dictionary:
	var flat: Vector3 = outward
	flat.y = 0.0
	if flat.length_squared() < 0.0001:
		return {"valid": false, "from": edge, "to": edge}
	flat = flat.normalized()
	var at: Vector3 = edge + step - Vector3.UP * drop
	# From clear of the face, inward. Starting ON the plane risks starting
	# INSIDE it, and a ray that begins inside geometry reports nothing at all.
	var from: Vector3 = at + flat * (margin + drop)
	var to: Vector3 = at - flat * margin
	return {"valid": not _cast(from, to).is_empty(), "from": from, "to": to}

## The face around an OUTSIDE corner: the one perpendicular to the face just
## left, found by looking back along the direction of travel from a point past
## the corner.
##
## Returns ledge_query()'s own shape -- `edge` on the new top, `normal` the new
## face's, pointing away from it -- or a miss when there is nothing to carry on
## along, which is the ordinary answer at the end of a free-standing wall.
func corner_beyond(edge: Vector3, along: Vector3, outward: Vector3,
		reach: float, drop: float, margin: float, tolerance: float) -> Dictionary:
	var travel: Vector3 = along
	travel.y = 0.0
	if travel.length_squared() < 0.0001:
		return _no_hit()
	travel = travel.normalized()
	# Past the corner and BELOW the lip, looking back the way we came. Past the
	# corner is open air, so the ray starts outside the geometry and the first
	# thing it can meet is the face being looked for.
	var from: Vector3 = edge + travel * reach - Vector3.UP * drop
	var to: Vector3 = from - travel * (reach * 2.0)
	var trace := {"from": from, "to": to}
	var hit: Dictionary = _cast(from, to)
	if hit.is_empty():
		return _corner_miss(trace)
	var normal: Vector3 = hit.get("normal", Vector3.ZERO)
	normal.y = 0.0
	if normal.length_squared() < 0.0001:
		return _corner_miss(trace)
	normal = normal.normalized()
	# A face still pointing the way the old one did is the SAME face, not a
	# corner -- the ray simply ran back along it, which is what happens on a
	# gentle bend. 0.5 is a 60 degree turn: clear of a right angle, clear of
	# surface noise.
	if normal.dot(outward) > 0.5:
		return _corner_miss(trace)
	var face_point: Vector3 = hit["position"]
	# margin INSIDE the top, the same offset ledge_query() anchors with, so the
	# two agree about where an edge is.
	var candidate: Vector3 = Vector3(face_point.x, edge.y, face_point.z) - normal * margin
	# Through the same ladder, for the same reason: the face round a corner is
	# as likely to carry a railing as the one just left, and on the owner's
	# whitebox both eaves had one.
	var top: Dictionary = _top_beside(candidate, edge.y, normal, margin,
			drop, tolerance)
	trace["top_from"] = top["from"]
	trace["top_to"] = top["to"]
	if not top.get("valid", false):
		return _corner_miss(trace)
	var found: Vector3 = top["edge"]
	var result := {"valid": true, "top": found, "edge": found, "normal": normal,
		"face_point": face_point, "face_normal": normal}
	result.merge(trace)
	return result

## A corner miss carrying whatever segments were fired before giving up, so the
## debug view can show WHICH of them came back empty.
func _corner_miss(trace: Dictionary) -> Dictionary:
	var result: Dictionary = _no_hit()
	result.merge(trace)
	return result

## What, if anything, is beside `from` within `distance` metres along
## `direction`. Empty when the way is clear.
##
## ⚠️ EXISTS BECAUSE fits_standing_at() CANNOT ANSWER THIS FROM A HANG, and the
## arithmetic says so outright rather than as a matter of taste. IntoGrabMove
## places the hanging body by where the EYE lands: eye_below_ledge (0.05) plus
## eye_height (0.76) is 0.81 m below the lip, so a 1.8 m capsule's crown sits
## 0.09 m ABOVE it. Sideways, ledge_back_offset is 0.45 m from the anchor and
## the anchor is LEDGE_ANCHOR_MARGIN (0.1 m) inside the top, leaving 0.35 m to
## the wall face against a radius of 0.4 -- an overlap of 0.05 m.
##
## So a hanging body is INSIDE the ledge it hangs from, on both axes, always.
## That is what hanging looks like: chest to the wall, head over the lip. Asking
## "would a standing capsule fit here" therefore answers NO at every hang
## position on every wall.
##
## A ray from the body CENTRE sideways asks the question that is actually being
## asked -- is there something beside me -- and cannot trip over the ledge,
## which is above it and in front of it rather than beside it.
##
## RETURNS THE HIT rather than a yes/no, because an INSIDE CORNER *is* this hit:
## the thing blocking the way sideways is the wall the shimmy has to turn onto,
## and its normal is the only thing that says which way to turn.
func side_hit(from: Vector3, direction: Vector3, distance: float) -> Dictionary:
	if direction.length_squared() < 0.0001 or distance <= 0.0:
		return {}
	return _cast(from, from + direction.normalized() * distance)

## One ray, on SurfaceDown's mask, ignoring the player's own body. The shimmy
## probes differ only in where they point, so the setup lives here once.
##
## A direct space query rather than one of the persistent rays: those are
## children of the player and travel with it, while these are fired from
## arbitrary points out along a ledge.
func _cast(from: Vector3, to: Vector3) -> Dictionary:
	var space := get_world_3d().direct_space_state
	if space == null:
		return {}
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = _surface.collision_mask if _surface != null else 1
	# ⚠️ hit_from_inside, AND WITHOUT IT THESE PROBES INVENT LEDGES. A Godot ray
	# that begins inside a shape and is NOT told this simply ignores that shape
	# and reports the next hit along -- so a probe fired down through a tall
	# block finds the top of whatever is buried underneath it and calls that a
	# ledge.
	#
	# ✅ The owner, hanging inside a wall: "我们的攀爬好像没考虑这种可攀附点被遮挡
	# 的情况." The arena's own shaft has a 2.7 m step with a 6.3 m block standing
	# on it, overlapping for 2.2 m of its length. ledge_query() refuses that
	# buried strip correctly -- SurfaceDown has always set this -- so the grab
	# was fine and the SHIMMY walked them in from the exposed rim beside it.
	#
	# Set here rather than at one call site because every probe in this family
	# wants the same honesty: a hit reported at the ray's own origin says "you
	# started inside something", which the height check then rejects, and the
	# inset ladder moves toward the face and tries again.
	query.hit_from_inside = true
	# The player's own capsule hangs BELOW the lip, so these rays should never
	# reach it -- but a thin ledge with the body pressed close is exactly the
	# case where "should never" stops being true, and a self-hit would read as
	# perfectly good geometry.
	var body := get_parent() as CollisionObject3D
	if body != null:
		query.exclude = [body.get_rid()]
	return space.intersect_ray(query)

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

## Nothing found by wall_ahead_query(). Shaped like a hit so callers can read
## every key unconditionally.
const NO_WALL_AHEAD := {"valid": false, "normal": Vector3.ZERO, "distance": INF, \
	"incidence": 0.0, "tall_enough": false}

## A wall DIRECTLY IN FRONT, tall enough to kick up.
##
## wall_query() cannot answer this and never could. Its two rays fire straight
## out to the player's left and right, so running head-on at a flat wall aims
## them ALONG the wall's face, where they hit nothing. Every wall this project
## has ever detected was beside the player, which is why wall running works and
## kicking straight up a wall was not merely unimplemented but unreachable.
##
## `heading` is the horizontal velocity direction as a unit vector, used only
## for `incidence` -- the rays themselves fire along the body's facing, matching
## _aim_forward()'s convention and wall_query()'s use of body-local rays.
##
## `tall_enough` is a separate key rather than folded into `valid` because the
## two failures want different answers from a caller: no wall at all means look
## elsewhere, while a wall too short to climb is one the vault and grab probes
## should get a look at.
func wall_ahead_query(heading: Vector3 = Vector3.ZERO) -> Dictionary:
	if _config == null:
		return NO_WALL_AHEAD.duplicate()
	_ensure_rays()
	var reach: float = _config.wall_climb.check_distance
	# Fired from chest height, matching WallLeft/WallRight's own 0.2 -- low
	# enough that a run-up sees the wall before the body touches it, high
	# enough to clear the ankle-height clutter a floor-level ray would snag on.
	_wall_ahead_low.position.y = WALL_AHEAD_CHEST_Y
	_aim_forward(_wall_ahead_low, reach)
	if not _wall_ahead_low.is_colliding():
		return NO_WALL_AHEAD.duplicate()
	var normal: Vector3 = _wall_ahead_low.get_collision_normal()
	# Same verticality gate wall_query() applies: a surface you can kick up
	# must be a wall, not a steep ramp you would simply run up.
	if absf(normal.y) >= MAX_WALL_NORMAL_Y:
		return NO_WALL_AHEAD.duplicate()
	var point: Vector3 = _wall_ahead_low.get_collision_point()
	var distance: float = Vector2(point.x - global_position.x, point.z - global_position.z).length()

	# ✅ MinWallHeight = 180 uu. Tested by firing a SECOND ray at that height:
	# if the wall is still there up top, it is tall enough to be worth kicking
	# up. Cheaper and more honest than measuring the wall's real height, which
	# a raycast cannot do anyway.
	_wall_ahead_high.position.y = _feet_y() - global_position.y + _config.wall_climb.min_wall_height
	_aim_forward(_wall_ahead_high, reach)
	var tall_enough: bool = _wall_ahead_high.is_colliding() \
		and absf(_wall_ahead_high.get_collision_normal().y) < MAX_WALL_NORMAL_Y

	return {"valid": true, "normal": normal, "distance": distance, \
		"incidence": _incidence(normal, heading), "tall_enough": tall_enough}

## The wall in a KNOWN world-space direction, whatever the body is facing.
##
## wall_query()'s two rays are rigidly local: they fire straight out to the
## body's left and right. That is fine for FINDING a wall, since a player who
## has not started a wall run yet is facing roughly the way they are going --
## but it is wrong for STAYING on one. Turning the view during a run swings
## both rays off the wall, the query comes back invalid, and the run ends.
## Measured in play as "you fall off the moment you stop looking forward",
## which the original does not do: there, the body completes the wall-run curve
## regardless of where the player is looking.
##
## So a run tracks its wall by the normal it already knows, in world space.
## `direction` is INTO the wall, i.e. the negated normal.
##
## Reuses WallLeft, which is safe by this file's own convention: every ray here
## is aimed from the live config at query time and owns its geometry for the
## duration of one call only (see setup()'s note on why nothing is baked).
func wall_tracked_query(direction: Vector3, reach: float) -> Dictionary:
	if _config == null or direction.length_squared() < 0.0001:
		return {"valid": false, "normal": Vector3.ZERO, "side": 0, "incidence": 0.0}
	_ensure_rays()
	# AT THE FEET, not the chest. See WALL_CONTACT_FOOT_MARGIN: this query is
	# what keeps a run ALIVE, and what keeps it alive is the boots being against
	# the wall. wall_query()'s own chest-height rays are right where they are --
	# they decide whether there is a wall worth STARTING on, and a kerb at ankle
	# height is not one.
	_wall_left.position.y = _feet_y() - global_position.y + WALL_CONTACT_FOOT_MARGIN
	# Into the ray's own local space: the direction is given in world terms and
	# target_position is not.
	var local: Vector3 = _wall_left.global_transform.basis.inverse() * direction.normalized()
	_wall_left.target_position = local * reach
	_wall_left.force_raycast_update()
	if not _wall_left.is_colliding():
		return {"valid": false, "normal": Vector3.ZERO, "side": 0, "incidence": 0.0}
	var normal: Vector3 = _wall_left.get_collision_normal()
	if absf(normal.y) >= MAX_WALL_NORMAL_Y:
		return {"valid": false, "normal": Vector3.ZERO, "side": 0, "incidence": 0.0}
	# NO SIDE. Deliberately, and this cost a debugging session: a side computed
	# from the body's current facing FLIPS when the player turns the view, and
	# `side` is what the look fan is mirrored by -- so the fan flips out from
	# under the view mid-turn and clamps it straight back to centre. Which side
	# of the RUN a wall is on is a property of the run, fixed when it attached,
	# and belongs to the move that attached rather than to a probe fired later.
	return {"valid": true, "normal": normal, "side": 0, "incidence": PI * 0.5}
