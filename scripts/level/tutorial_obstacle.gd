class_name TutorialObstacle
extends Node3D

# Where one lesson's obstacle stands. Three rules, and the third is not
# negotiable:
#
#   PLACE   anchor = player position + facing * spawn_distance
#   FOLLOW  while growth has not started, re-place it as the player turns --
#           he never sees this happen, because it only happens out where
#           nothing is drawn yet
#   LOCK    the instant growth starts, the anchor is pinned for good
#
# WITHOUT THE LOCK the player turns his head and watches the obstacle drift
# through the void, and everything this level builds up about the world being
# a real place collapses in one shot.
#
# Standing still and spinning keeps it following forever and growth never
# starts -- that is correct. It only means the player is not running yet.

## The body this obstacle places itself in front of.
@export var player: Player

## How far ahead to stand. Must stay close enough that the growth show can be
## READ as the player closes the distance, and must NOT be pushed out beyond
## the collapse radius -- past that radius growth is invisible, which throws
## away the best-looking thing in the level. Tuning value.
@export var spawn_distance: float = 30.0

## Re-place once the player's facing has turned this far off the anchor.
@export var follow_angle_deg: float = 25.0

## Never stand this close to an obstacle in `avoid`.
@export var min_separation: float = 12.0

## Hard ceiling on how far the retry in _place() may push the obstacle out,
## metres. Must stay inside the level's collapse radius, same constraint
## spawn_distance's own doc states -- past that radius the growth show is
## invisible. A crowd of `avoid` obstacles can otherwise walk the retry's
## distance out arbitrarily far chasing separation (8 attempts * min_separation
## alone reaches 30 + 8*12 = 126 m against a design radius under 50 m); this is
## what stops it.
@export var max_spawn_distance: float = 45.0

## Obstacles that still exist and must not be overlapped -- typically the one
## currently collapsing.
var avoid: Array[TutorialObstacle] = []

## Where it stands. Equal to global_position; kept as its own name because
## "anchor" is what the placement rules talk about.
var anchor: Vector3:
	get:
		return global_position

## True once growth has begun. A locked obstacle never moves again.
var locked: bool = false

func _ready() -> void:
	_place()

func _physics_process(_delta: float) -> void:
	if locked or player == null:
		return
	var forward: Vector3 = _facing()
	var to_anchor: Vector3 = anchor - player.global_position
	to_anchor.y = 0.0
	if to_anchor.length() < 0.001:
		_place()
		return
	if forward.angle_to(to_anchor.normalized()) > deg_to_rad(follow_angle_deg):
		_place()

## Pins the anchor. Called when growth starts -- see GrowingSolid.
func lock() -> void:
	locked = true

## Moves with the world. TorusWrap shifts the player one period on a crossing;
## a locked obstacle must take the same step or it lands a period behind the
## body it was placed for.
func shift_by(offset: Vector3) -> void:
	global_position += offset

func _facing() -> Vector3:
	if player == null:
		return Vector3.FORWARD
	var forward: Vector3 = -player.global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.001:
		return Vector3.FORWARD
	return forward.normalized()

func _place() -> void:
	if player == null:
		return
	var base: Vector3 = player.global_position
	var forward: Vector3 = _facing()
	var distance: float = spawn_distance
	# Pushed further out until it clears everything still standing, capped at
	# max_spawn_distance so the retry can never carry the obstacle past the
	# distance the growth show can still be read from.
	for _attempt in 8:
		var candidate: Vector3 = base + forward * distance
		if not _too_close(candidate):
			global_position = candidate
			return
		if distance >= max_spawn_distance:
			break
		distance = minf(distance + min_separation, max_spawn_distance)
	global_position = base + forward * distance

func _too_close(candidate: Vector3) -> bool:
	for other in avoid:
		if is_instance_valid(other) and other.anchor.distance_to(candidate) < min_separation:
			return true
	return false
