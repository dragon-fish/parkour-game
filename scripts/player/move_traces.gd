class_name MoveTraces
extends RefCounted

# The original's TdMove trace and ledge natives, ported. [ME:CONFIRMED
# emulated N4 §3] FindLedgeEx, FindLedge, FindAutoMoveLedge (the hand-plant
# search) and CalculateRelativeExtent were run as machine code under an
# emulator and compared case by case with the reference these functions are
# transcribed from; MovementTrace and its variants are read.
#
# Every extent is a half-size BOX that is never rotated -- the original's
# extent traces sweep an axis-aligned box -- given in Godot axes (x, height,
# z). Heights are measured from Location, the cylinder's centre, which is
# global_position here.
#
# Quirks kept, and DO NOT fix them: the hand-plant search's two side pairs can
# never pass (they need MoveNormal.Z >= 0.98 and <= 0.2 at once); a pair whose
# ledges run across the wall ends the WHOLE search; FindLedgeEx ignores a box
# that starts inside something.

const UU := 0.01

## TdPhysicsMove config. [ME:CONFIRMED DefaultPawnMovement.ini
## [TdGame.TdPhysicsMove]] The hand-plant probe: a box HandPlantExtentCheckWidth
## wide and 2 x HandPlantExtentCheckHeight tall, its centre HandPlantCheckHeight
## above the default cylinder's feet, swept HandPlantCheckDistance ahead.
const HAND_PLANT_EXTENT_CHECK_HEIGHT := 80.0 * UU
const HAND_PLANT_EXTENT_CHECK_WIDTH := 10.0 * UU
const HAND_PLANT_CHECK_DISTANCE := 200.0 * UU
const HAND_PLANT_CHECK_HEIGHT := 112.0 * UU
## The side pairs of the multi search stand this far either side of the body.
const HAND_PLANT_SIDE_OFFSET := 30.0 * UU
## TdPawn.LedgeFindDepth: how far past the wall face the top is looked for.
const LEDGE_FIND_DEPTH := 4.0 * UU
## 2 (sqrt 2 - 1): how much further than its half-width a square box reaches
## along a diagonal. Shared by every finder (DAT_01cf47f8).
const CORNER := 0.8284270167350769

## The thinnest box half-extent a sweep is given, 0.05 uu.
const MIN_EXTENT := 0.05 * UU

## LedgeHitInfo's result values.
const LEDGE_NONE := 0
const LEDGE_WALL := 1
const LEDGE_TOP := 2

var pawn

func _init(owner_pawn) -> void:
	pawn = owner_pawn

# --- traces ---------------------------------------------------------------------

## UTdMove::MovementTraceImpl. A swept box (or a line for a zero extent)
## against the world, never the pawn. Returns {hit, time, location, normal,
## actor}; location is the box centre where it stopped. A trace that starts
## inside something hits at time 0, as the engine reports it.
func trace(end: Vector3, start: Vector3, extent: Vector3 = Vector3.ZERO) -> Dictionary:
	if extent == Vector3.ZERO:
		return _line(end, start)
	# A flat box (one zero axis) is a sheet the engine sweeps; a shape needs
	# some thickness.
	var sweep_extent: Vector3 = extent.max(Vector3.ONE * MIN_EXTENT)
	var hit: Dictionary = pawn.phys.box_trace(end, start, sweep_extent)
	# A blocked sweep whose rest query names nothing (a start inside geometry
	# among them) is still a hit.
	return {"hit": hit["collider"] != null or float(hit["time"]) < 1.0, "time": hit["time"],
		"location": hit["position"], "normal": hit["normal"], "actor": hit["collider"]}

func _line(end: Vector3, start: Vector3) -> Dictionary:
	var space: PhysicsDirectSpaceState3D = pawn.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(start, end)
	query.exclude = [pawn.get_rid()]
	query.hit_from_inside = true
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return {"hit": false, "time": 1.0, "location": end, "normal": Vector3.ZERO, "actor": null}
	var length: float = (end - start).length()
	var position: Vector3 = hit["position"]
	var time: float = (position - start).length() / length if length > 0.0 else 0.0
	return {"hit": true, "time": time, "location": position, "normal": hit["normal"],
		"actor": hit["collider"]}

## TdMove.MovementTrace(out HitLocation, out HitNormal, End, Start, Extent).
## The flags only choose between a closest and an any hit, which a single
## sweep does not distinguish.
func movement_trace(end: Vector3, start: Vector3, extent: Vector3 = Vector3.ZERO) -> Dictionary:
	return trace(end, start, extent)

## TdMove.MovementTraceForBlocking.
func movement_trace_for_blocking(end: Vector3, start: Vector3, extent: Vector3 = Vector3.ZERO) -> bool:
	return trace(end, start, extent)["hit"]

## TdMove.GetMovementExclusionVolume. This project has no exclusion volumes:
## always none.
func get_movement_exclusion_volume(_location: Vector3) -> Object:
	return null

## Actor.bExludeHandMoves / bExludeFootMoves of a hit. This project marks both
## at once, with Probes.NO_INTERACTION_GROUP.
static func excludes_hand_moves(actor: Object) -> bool:
	return Probes.is_inert(actor)

static func excludes_foot_moves(actor: Object) -> bool:
	return Probes.is_inert(actor)

# --- the box-corner reach -----------------------------------------------------------

## (1 + 0.828427 m sqrt(1 - m^2)) * extent, m = max(|n.x|, |n.y|) of the
## normal's flat direction: how far a square box's centre stands off a wall it
## touches, exact at 0 and 45 degrees.
static func box_reach(normal: Vector3, extent: float) -> float:
	var n: Vector3 = PawnPhysics.safe_normal_2d(normal)
	var m: float = maxf(absf(n.x), absf(n.z))
	return (1.0 + CORNER * m * sqrt(1.0 - minf(m * m, 1.0))) * extent

## UTdMove::CalculateRelativeExtent. [ME:CONFIRMED emulated N4 §3.1] The extra
## reach past `base_extent` of a square box facing MoveNormal, or facing away
## from the pawn when there is no MoveNormal.
func calculate_relative_extent(base_extent: float) -> float:
	var d: Vector3 = PawnPhysics.safe_normal_2d(pawn.move_normal)
	if d.length() <= 1e-4 * UU:
		d = -PawnPhysics.safe_normal_2d(pawn.facing())
	var m: float = maxf(absf(d.x), absf(d.z))
	return sqrt(1.0 - minf(m * m, 1.0)) * m * base_extent * CORNER

# --- ledges ---------------------------------------------------------------------

static func _no_ledge() -> Dictionary:
	return {"result": LEDGE_NONE, "ledge_location": Vector3.ZERO, "ledge_normal": Vector3.ZERO,
		"move_normal": Vector3.ZERO, "move_actor": null, "feet_excluded": false,
		"hands_excluded": false}

## FillLedgeHit. The actor and its exclusion bits are those of `last`, the
## LAST trace made: the natives share one FCheckResult, which a miss leaves
## naming no actor. So a top's actor is the top's, and a wall whose down trace
## found nothing has none. MoveNormal is the wall sweep's.
func _ledge_hit(result: int, location: Vector3, ledge_normal: Vector3, wall: Dictionary,
		last: Dictionary) -> Dictionary:
	var actor: Object = last["actor"] if last["hit"] else null
	return {"result": result, "ledge_location": location, "ledge_normal": ledge_normal,
		"move_normal": wall["normal"], "move_actor": actor,
		"feet_excluded": excludes_foot_moves(actor), "hands_excluded": excludes_hand_moves(actor)}

## The point on the wall face under the box's centre, and the down trace's two
## ends LedgeFindDepth past it.
static func _ledge_point(start: Vector3, end: Vector3, extent: Vector3, wall: Dictionary) -> Array:
	var d2: Vector3 = PawnPhysics.safe_normal_2d(PawnPhysics.safe_normal(end - start))
	var n: Vector3 = PawnPhysics.safe_normal_2d(wall["normal"])
	var reach: float = box_reach(n, extent.x)
	var c: float = absf(n.dot(d2))
	if c > 0.0:
		reach /= c
	var wall_location: Vector3 = wall["location"]
	var p: Vector3 = wall_location + d2 * reach
	p.y = wall_location.y
	var s3 := Vector3(p.x - n.x * LEDGE_FIND_DEPTH, p.y + extent.y, p.z - n.z * LEDGE_FIND_DEPTH)
	var e3: Vector3 = s3 - Vector3.UP * (2.0 * extent.y)
	return [p, s3, e3]

## UTdMove::FindLedgeEx. [ME:CONFIRMED emulated N4 §3.2] 0 nothing (or the
## box's own height is obstructed), 1 a wall with no top within the box's
## height, 2 a top surface within it.
func find_ledge_ex(start: Vector3, end: Vector3, extent: Vector3) -> Dictionary:
	var lift := Vector3.UP * (extent.y - 1.0 * UU)
	var own := trace(start + lift, start - lift, Vector3(extent.x, 1.0 * UU, extent.z))
	if own["hit"] and float(own["time"]) > 0.0:
		return _no_ledge()
	var wall: Dictionary = trace(end, start, extent)
	if not wall["hit"] or float(wall["time"]) <= 0.0:
		return _no_ledge()
	var points: Array = _ledge_point(start, end, extent, wall)
	var p: Vector3 = points[0]
	var s3: Vector3 = points[1]
	var e3: Vector3 = points[2]
	var wall_location: Vector3 = wall["location"]
	var last_y: float = wall_location.y
	var top: Dictionary = trace(e3, s3)
	if top["hit"]:
		last_y = (top["location"] as Vector3).y
		if float(top["time"]) > 0.0:
			return _ledge_hit(LEDGE_TOP, Vector3(p.x, last_y, p.z), top["normal"], wall, top)
		# Started inside: once more from halfway down.
		top = trace(e3, Vector3(s3.x, p.y, s3.z))
		if not top["hit"]:
			return _no_ledge()
		last_y = (top["location"] as Vector3).y
		if float(top["time"]) > 0.0:
			return _ledge_hit(LEDGE_TOP, Vector3(p.x, last_y, p.z), top["normal"], wall, top)
	return _ledge_hit(LEDGE_WALL, Vector3(p.x, last_y, p.z), wall["normal"], wall, top)

## UTdMove::FindLedge. [ME:CONFIRMED emulated N4 §3.3] FindLedgeEx without the
## start check and with a single down trace: a top or nothing.
func find_ledge(start: Vector3, end: Vector3, extent: Vector3) -> Dictionary:
	var wall: Dictionary = trace(end, start, extent)
	if not wall["hit"] or float(wall["time"]) <= 0.0:
		return _no_ledge()
	var points: Array = _ledge_point(start, end, extent, wall)
	var p: Vector3 = points[0]
	var top: Dictionary = trace(points[2], points[1])
	if top["hit"] and float(top["time"]) > 0.0:
		return _ledge_hit(LEDGE_WALL, Vector3(p.x, (top["location"] as Vector3).y, p.z),
			top["normal"], wall, top)
	return _no_ledge()

## UTdPhysicsMove's hand-plant search (FUN_012053a0). [ME:CONFIRMED emulated
## N4 §3.4] Two boxes HandPlantExtentCheckWidth wide, standing 2 (R - W/2)
## apart across the facing, swept `distance` ahead at hand height; both must
## agree on a flat, parallel ledge (or wall) across the wall normal. Returns the
## ledge dictionary of find_ledge_ex() with the pair's midpoint, and on success
## writes MovementActor and the exclusion bits to the pawn, as the original.
##
## `facing` is Vector(Pawn.Rotation); `edge_in_vel_dir` is
## bCheckForEdgeInVelDir, which adds the velocity's vertical direction to the
## sweep without normalising it again.
func find_auto_move_ledge(location: Vector3, facing: Vector3, distance: float, multi: bool,
		edge_in_vel_dir: bool) -> Dictionary:
	var d2: Vector3 = PawnPhysics.safe_normal_2d(facing)
	var dir: Vector3 = d2
	if edge_in_vel_dir:
		dir.y += PawnPhysics.safe_normal(pawn.velocity).y
	var extent := Vector3(HAND_PLANT_EXTENT_CHECK_WIDTH * 0.5, HAND_PLANT_EXTENT_CHECK_HEIGHT,
		HAND_PLANT_EXTENT_CHECK_WIDTH * 0.5)
	# Facing x Z in the original: the pawn's left.
	var side: Vector3 = UE.cross(d2, Vector3.UP)
	var off: float = pawn.collision_radius() - extent.x
	var hand_height: float = HAND_PLANT_CHECK_HEIGHT - pawn.default_collision_half_height()
	for i in (3 if multi else 1):
		var base: Vector3 = location
		if i == 1:
			base = location - side * HAND_PLANT_SIDE_OFFSET
		elif i == 2:
			base = location + side * HAND_PLANT_SIDE_OFFSET
		var a: Vector3 = base - side * off
		a.y = base.y + hand_height
		var h1: Dictionary = find_ledge_ex(a, a + dir * distance, extent)
		var r1: int = h1["result"]
		if r1 == LEDGE_NONE:
			continue
		var n1: Vector3 = h1["move_normal"]
		if i >= 1 and n1.y < 0.98:
			continue
		if n1.y > 0.2:
			continue
		if pawn.illegal_ledge_timer > 0.0 and pawn.illegal_ledge_normal.dot(n1) > 0.98:
			continue
		if (r1 == LEDGE_TOP and h1["hands_excluded"]) or (r1 == LEDGE_WALL and h1["feet_excluded"]):
			continue
		# The original ends the search here when an exclusion volume at the
		# ledge excludes the move (and for a wall reads the generic Actor bit,
		# not the volume's own foot flag). This project has no such volumes.
		var volume: Object = get_movement_exclusion_volume(h1["ledge_location"])
		var b: Vector3 = base + side * off
		b.y = a.y
		var h2: Dictionary = find_ledge_ex(b, b + dir * distance, extent)
		if h2["result"] != r1:
			continue
		var l1: Vector3 = h1["ledge_location"]
		var l2: Vector3 = h2["ledge_location"]
		var ln1: Vector3 = h1["ledge_normal"]
		var ln2: Vector3 = h2["ledge_normal"]
		var n2: Vector3 = h2["move_normal"]
		var dl: Vector3 = PawnPhysics.safe_normal(l2 - l1)
		if absf(dl.dot(ln1)) > 0.25:
			return _no_ledge()
		if n2.y <= 0.2 and absf(ln1.dot(ln2)) >= 0.99 and absf(n2.dot(n1)) >= 0.95 \
				and absf(PawnPhysics.safe_normal_2d(n1).dot(PawnPhysics.safe_normal_2d(dl))) <= 0.25:
			var found: Dictionary = h1.duplicate()
			found["ledge_location"] = (l1 + l2) * 0.5
			pawn.movement_actor = h1["move_actor"]
			pawn.movement_exclusion_volume = volume
			pawn.found_ledge_excludes_hand_moves = h1["hands_excluded"]
			pawn.found_ledge_excludes_foot_moves = h1["feet_excluded"]
			return found
	return _no_ledge()
