class_name GrowingSolid
extends Node3D

# The world builds itself in front of the player: an obstacle is drawn into
# existence rather than switched on. This class owns the TIMING of that; what
# it LOOKS like is deliberately separate.
#
# THE SHOW MAY START CRUDE, THE TIMING MAY NOT. A block made of boxes carries
# CubeSwarm children and comes apart into glowing cubes; anything else falls
# back to an alpha fade. Neither of them changes a line of the timing here.
# Doing it the other way round -- look first, timing after -- leaves the
# hardest part until the geometry is buried under art.
#
# COLLISION IS NOT THIS CLASS'S BUSINESS. Geometry is solid from the moment it
# exists until it is freed, and neither end of the animation touches that.
# Growth happens at the placement distance, which the timing contract keeps
# beyond the player's reach. Collapse does NOT: a lesson is passed by
# performing its move, so the player is standing at the block -- often on it --
# when it is told to leave, and it stays solid under him the whole way out.
# When it is finally freed he drops onto the plain, which is the fiction.
# DO NOT gate collision on progress. An earlier version did, which protected
# nothing and could seal a player inside a block that landed on him.

## How long the growth takes. Must satisfy the inequality above against
## TutorialObstacle.spawn_distance.
@export var grow_time: float = 1.2

## How long the collapse takes once it starts.
@export var collapse_time: float = 0.6

## The placement this belongs to. Pinned when growth starts. Optional: a
## fixed piece of scenery that grows has no anchor to pin.
@export var obstacle: TutorialObstacle

## 0 before growth, 1 once fully grown.
var progress: float = 0.0

signal grown
signal gone

enum Phase { DORMANT, GROWING, STANDING, COLLAPSING, DONE }

var _phase: int = Phase.DORMANT
var _elapsed: float = 0.0

# Gathered once: find_children() on every physics frame of a multi-second
# growth is wasted work over a set that cannot change after _ready().
var _geometry: Array[GeometryInstance3D] = []

# The block's cube swarms, if it has any. A block made of boxes takes itself
# apart into glowing cubes; anything else falls back to the alpha fade, which
# is what everything used before and what non-box geometry still gets.
var _swarms: Array[CubeSwarm] = []

func _ready() -> void:
	for node in find_children("*", "CubeSwarm", true, false):
		_swarms.append(node as CubeSwarm)
	for node in find_children("*", "GeometryInstance3D", true, false):
		# A CubeSwarm IS a GeometryInstance3D. It is driven by its own progress,
		# and driving its transparency as well would fade it out from under its
		# own animation.
		if node is CubeSwarm:
			continue
		_geometry.append(node as GeometryInstance3D)
	_apply_visual(0.0)

func _physics_process(delta: float) -> void:
	match _phase:
		Phase.GROWING:
			_elapsed += delta
			progress = clampf(_elapsed / maxf(grow_time, 0.001), 0.0, 1.0)
			_apply_visual(progress)
			if progress >= 1.0:
				_phase = Phase.STANDING
				grown.emit()
		Phase.COLLAPSING:
			_elapsed += delta
			var k: float = clampf(_elapsed / maxf(collapse_time, 0.001), 0.0, 1.0)
			_apply_visual(1.0 - k)
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

## Starts collapsing.
func collapse() -> void:
	if _phase == Phase.COLLAPSING or _phase == Phase.DONE:
		return
	_phase = Phase.COLLAPSING
	_elapsed = 0.0

## `k` is how much of the block EXISTS: 0 nothing, 1 whole. A swarm reads the
## complement -- how far it has dispersed -- which is what makes growth and
## collapse the same animation run in opposite directions.
##
## MVP for anything that is not a box: plain transparency. Nothing outside this
## function knows which of the two is in use.
func _apply_visual(k: float) -> void:
	for node in _geometry:
		node.transparency = clampf(1.0 - k, 0.0, 1.0)
	for swarm in _swarms:
		swarm.progress = 1.0 - clampf(k, 0.0, 1.0)
