class_name GrowingSolid
extends Node3D

# The world builds itself in front of the player: an obstacle is drawn into
# existence rather than switched on. This class owns the TIMING of that; what
# it LOOKS like is deliberately separate.
#
# THE SHOW MAY START CRUDE, THE TIMING MAY NOT. Today growth is an alpha fade
# and collapse is a fade out. The wireframe, the advancing cut plane, the lit
# seam and the feathers all come later, and none of them changes a line here.
# Doing it the other way round -- look first, timing after -- leaves the
# hardest part until the geometry is buried under art.
#
# COLLISION TURNS ON IN ONE STEP, AT THE END. Never let the collision surface
# follow the growth surface: that is another order of complexity, and it is
# unnecessary as long as the level keeps
#
#     grow_time * sprint speed < placement distance - margin
#
# so the player cannot reach a half-built obstacle in the first place.

## How long the growth takes. Must satisfy the inequality above against
## TutorialObstacle.spawn_distance.
@export var grow_time: float = 1.2

## How long the collapse takes once it starts.
@export var collapse_time: float = 0.6

## The thing that blocks. Disabled until growth completes, and again the
## moment collapse begins.
@export var body: CollisionObject3D

## The placement this belongs to. Pinned when growth starts. Optional: a
## fixed piece of scenery that grows has no anchor to pin.
@export var obstacle: TutorialObstacle

## 0 before growth, 1 once fully grown.
var progress: float = 0.0

## Whether it currently blocks.
var solid: bool = false

signal grown
signal gone

enum Phase { DORMANT, GROWING, STANDING, COLLAPSING, DONE }

var _phase: int = Phase.DORMANT
var _elapsed: float = 0.0

# Gathered once: find_children() on every physics frame of a multi-second
# growth is wasted work over a set that cannot change after _ready().
var _geometry: Array[GeometryInstance3D] = []

func _ready() -> void:
	for node in find_children("*", "GeometryInstance3D", true, false):
		_geometry.append(node as GeometryInstance3D)
	_apply_alpha(0.0)
	_set_solid(false)

func _physics_process(delta: float) -> void:
	match _phase:
		Phase.GROWING:
			_elapsed += delta
			progress = clampf(_elapsed / maxf(grow_time, 0.001), 0.0, 1.0)
			_apply_alpha(progress)
			if progress >= 1.0:
				_phase = Phase.STANDING
				_set_solid(true)
				grown.emit()
		Phase.COLLAPSING:
			_elapsed += delta
			var k: float = clampf(_elapsed / maxf(collapse_time, 0.001), 0.0, 1.0)
			_apply_alpha(1.0 - k)
			if k >= 1.0:
				_phase = Phase.DONE
				gone.emit()

## Starts growing, and pins the anchor -- growth beginning is exactly the
## moment the player can see it, which is what the lock is defined by.
func begin() -> void:
	if _phase != Phase.DORMANT:
		return
	_phase = Phase.GROWING
	_elapsed = 0.0
	if obstacle != null:
		obstacle.lock()

## Starts collapsing. Solidity is given up on the spot, not at the end: a
## player running through the space it is vacating is the reason it leaves.
func collapse() -> void:
	if _phase == Phase.COLLAPSING or _phase == Phase.DONE:
		return
	_phase = Phase.COLLAPSING
	_elapsed = 0.0
	_set_solid(false)

func _set_solid(on: bool) -> void:
	solid = on
	if body != null:
		body.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
		for child in body.get_children():
			if child is CollisionShape3D:
				# Deferred: the physics server may be mid-query while this
				# runs from _physics_process. A direct write can land inside
				# that query and corrupt it.
				child.set_deferred("disabled", not on)

## MVP: plain transparency. Replaced by the dissolve shader later; nothing
## outside this function knows which is in use.
func _apply_alpha(k: float) -> void:
	for node in _geometry:
		node.transparency = clampf(1.0 - k, 0.0, 1.0)
