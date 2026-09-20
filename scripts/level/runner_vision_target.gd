@tool
class_name RunnerVisionTarget
extends Node3D

# Something the runner is meant to see: drop this under a mesh and the mesh
# takes the red when the player is near enough, on the original's own timings.
#
# A CHILD NODE RATHER THAN A SCRIPT ON THE MESH. One target paints every
# MeshInstance3D under its parent -- a railing built from six pieces is one
# target, not six -- and the mesh keeps whatever script it already had.
#
# WHAT IT PAINTS, in order: `meshes` when set, otherwise every
# MeshInstance3D under the parent. An empty parent is a configuration warning
# rather than a silent no-op, because a target that paints nothing looks
# exactly like one whose distance is wrong.
#
# The numbers are the original's (docs/mirrors-edge-deep-research/14-信使视觉LOI.md):
# its LOI fields sit on the engine's own actor classes, so a level could tag
# any static mesh without the art knowing.

const OVERLAY := preload("res://shaders/runner_vision.gdshader")
## Group RunnerVision collects its targets from.
const GROUP := "runner_vision"

## Metres from the player at which this lights up.
## [ME:CONFIRMED] LOIDistance defaults to 1500 uu; levels set anything from
## the default up to 107 m for something across a plaza.
@export var distance_m: float = 15.0:
	set(value):
		distance_m = maxf(value, 0.0)
		update_configuration_warnings()
## Ignore height when measuring that distance. [ME:CONFIRMED] LOIUse2DDistance:
## a pipe two floors up is as near as the floor it hangs over.
@export var flat_distance: bool = false
## Seconds within range before it lights. [ME:CONFIRMED] LOIProximityDelay;
## the original's levels use 1 to 3 seconds.
@export var proximity_delay: float = 0.0
## Once lit, stays lit at least this long even if the player turns away.
## [ME:CONFIRMED] LOIMinDuration = 1.5.
@export var min_duration: float = 1.5
## The paint. [ME:CONFIRMED] the original's LOI_Color is (1.5, 0, 0) -- past
## white on purpose. A level of your own can say otherwise per target.
@export var paint: Color = Color(1.5, 0.0, 0.0)
## Painted in the editor at this strength, so a target can be placed and judged
## without running the level. Runtime ignores it.
@export_range(0.0, 1.0) var editor_preview: float = 0.0:
	set(value):
		editor_preview = value
		_apply(value)

## The meshes to paint. Empty: every MeshInstance3D under the parent.
@export var meshes: Array[NodePath] = []

## What to paint WITH, when the object deserves better than a flat coat: any
## material, drawn over the surface exactly as the built-in one is. A material
## that declares `instance uniform float strength` fades with the rest; one
## that does not simply appears and disappears with the target.
##
## THE FLAT COAT IS THE FALLBACK, not the intent. It costs nothing and works on
## any mesh, which is what a blockout needs; a finished object wants a material
## that keeps its own texture and only reddens it.
@export var overlay_material: Material = null:
	set(value):
		overlay_material = value
		_painted.clear()
		_apply(editor_preview if Engine.is_editor_hint() else _strength)

@export_group("Fade")
## [ME:CONFIRMED] DefaultLOI.ini: FadeInSpeed 1.0, FadeOutSpeed 4.0. SLOW IN,
## FAST OUT -- the hint arrives before the decision and is gone by the time the
## move is under way. Per second, so 1.0 is a second from nothing to painted.
@export var fade_in_speed: float = 1.0
@export var fade_out_speed: float = 4.0

var _strength: float = 0.0
var _near_for: float = 0.0
var _lit_for: float = 0.0
var _painted: Array[GeometryInstance3D] = []


func _ready() -> void:
	_collect()
	if Engine.is_editor_hint():
		_apply(editor_preview)
		return
	add_to_group(GROUP)
	_apply(0.0)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	_collect()
	if _painted.is_empty():
		warnings.append("Nothing to paint: put this under a MeshInstance3D, or fill in `meshes`.")
	return warnings


## Advances one tick against a player at `eye`. Returns the strength now, so a
## caller can tell whether anything is lit without reading state back.
func advance(delta: float, eye: Vector3) -> float:
	var offset := eye - global_position
	if flat_distance:
		offset.y = 0.0
	var near := offset.length() <= distance_m
	_near_for = _near_for + delta if near else 0.0
	var wanted := near and _near_for >= proximity_delay
	# Held on for min_duration once lit: a hint that blinks as the player
	# strafes past its edge is worse than one that stays a moment too long.
	# COUNTED FROM WHEN IT LIT, not from when the player left -- reset on
	# leaving, the hold restarted every tick and nothing ever faded out.
	_lit_for = _lit_for + delta if _strength > 0.0 else 0.0
	if _strength > 0.0 and _lit_for < min_duration:
		wanted = true
	var speed := fade_in_speed if wanted else -fade_out_speed
	var now := clampf(_strength + speed * delta, 0.0, 1.0)
	if now != _strength:
		_strength = now
		_apply(now)
	return _strength


func _collect() -> void:
	_painted.clear()
	if not meshes.is_empty():
		for path in meshes:
			var node := get_node_or_null(path) as GeometryInstance3D
			if node != null:
				_painted.append(node)
		return
	var parent := get_parent()
	if parent == null:
		return
	if parent is GeometryInstance3D:
		_painted.append(parent)
	for child in parent.find_children("*", "GeometryInstance3D", true, false):
		if child != self and not _painted.has(child):
			_painted.append(child)


func _apply(strength: float) -> void:
	for node in _painted:
		if not is_instance_valid(node):
			continue
		# Assigned once and shared: the overlay is one material for the whole
		# level, and the strength rides on the instance.
		if overlay_material != null:
			if node.material_overlay != overlay_material:
				node.material_overlay = overlay_material
		elif not _is_built_in(node.material_overlay):
			var material := ShaderMaterial.new()
			material.shader = OVERLAY
			node.material_overlay = material
		node.set_instance_shader_parameter("strength", strength)
		node.set_instance_shader_parameter("paint", Vector3(paint.r, paint.g, paint.b))


static func _is_built_in(material: Material) -> bool:
	return material is ShaderMaterial and (material as ShaderMaterial).shader == OVERLAY
