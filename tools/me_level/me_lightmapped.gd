@tool
extends Node3D

# The root of a lightmapped geometry scene. Sets every lightmapped instance's
# lightmap parameters again once the scene is in the tree, from the values the
# scene file holds for it, and draws the baked world as the lighting setting
# asks (SettingsStore.LIGHTING_MODES).
#
# DO NOT remove the parameter pass while the shader takes them as instance
# uniforms. Loaded from a scene file, Godot 4.7 leaves a share of the instances
# drawing with the uniforms' defaults instead of their own -- the whole atlas
# instead of their rectangle: in the tutorial a lit construction tent drew
# black -- and setting the same values once more puts it right. Here rather
# than at build time because the build's values are the right ones; it is the
# load that loses them.
#
# CLASSIC draws what the scene file holds: the lightmapped materials. MODERN
# draws each baked surface with its plain material, the one the mesh library
# lights live (Common.MODERN_MATERIALS_META), and Runner Vision goes back to
# its overlay, which is lit the same way. A switch of override materials, not
# a shader branch: the plain materials are what a level without a bake was
# always drawn with -- mirroring masks, clear coat, the albedo factor and the
# baker tint -- and a lit branch of the lightmap shader would have to grow
# every one of them again. Both sets are in the generated scene; nothing is
# built when the level runs.

const Common := preload("res://tools/me_level/me_level_common.gd")
const PARAMETERS: Array[StringName] = [&"lightmap_uv_scale_bias", &"lightmap_scale_0",
		&"lightmap_scale_1", &"lightmap_scale_2", &"lightmap_vertex_offset"]

## The lighting this scene is drawn with now.
var lighting := "classic"

## Baked instance -> [classic override per surface].
var _classic := {}
var _painted_in_material: Array[Node] = []


func _ready() -> void:
	for node in find_children("*", "GeometryInstance3D", true, false):
		var instance := node as GeometryInstance3D
		_reset_parameters(instance)
		if instance is MeshInstance3D and instance.layers & Common.BAKED_LAYER:
			var own: Array = []
			for surface in (instance as MeshInstance3D).get_surface_override_material_count():
				own.append((instance as MeshInstance3D).get_surface_override_material(surface))
			_classic[instance] = own
	for node in find_children("*", "Node3D", true, false):
		if node is RunnerVisionTarget and (node as RunnerVisionTarget).paint_in_material:
			_painted_in_material.append(node)
	if Engine.is_editor_hint():
		return
	SettingsStore.follow_lighting(self)


func use_lighting(mode: String) -> void:
	if mode == lighting:
		return
	lighting = mode
	var modern := mode == "modern"
	for key in _classic:
		if not is_instance_valid(key):
			continue
		var instance := key as MeshInstance3D
		var classic: Array = _classic[instance]
		var plain: Array = instance.get_meta(Common.MODERN_MATERIALS_META, [])
		for surface in classic.size():
			var material: Material = classic[surface]
			if modern:
				material = plain[surface] if surface < plain.size() else null
			instance.set_surface_override_material(surface, material)
		if not modern:
			_reset_parameters(instance)
	for target in _painted_in_material:
		if is_instance_valid(target):
			(target as RunnerVisionTarget).paint_in_material = not modern


func _reset_parameters(instance: GeometryInstance3D) -> void:
	for parameter in PARAMETERS:
		var value: Variant = instance.get_instance_shader_parameter(parameter)
		if value != null:
			instance.set_instance_shader_parameter(parameter, value)
