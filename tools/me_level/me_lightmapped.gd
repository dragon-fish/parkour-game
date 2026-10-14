@tool
extends Node3D

# The root of a lightmapped geometry scene. Sets every lightmapped instance's
# lightmap parameters again once the scene is in the tree, from the values the
# scene file holds for it.
#
# DO NOT remove this while the shader takes them as instance uniforms. Loaded
# from a scene file, Godot 4.7 leaves a share of the instances drawing with the
# uniforms' defaults instead of their own -- the whole atlas instead of their
# rectangle: in the tutorial a lit construction tent drew black -- and setting
# the same values once more puts it right. Here rather than at build time
# because the build's values are the right ones; it is the load that loses them.

const PARAMETERS: Array[StringName] = [&"lightmap_uv_scale_bias", &"lightmap_scale_0",
		&"lightmap_scale_1", &"lightmap_scale_2"]


func _ready() -> void:
	for node in find_children("*", "GeometryInstance3D", true, false):
		var instance := node as GeometryInstance3D
		for parameter in PARAMETERS:
			var value: Variant = instance.get_instance_shader_parameter(parameter)
			if value != null:
				instance.set_instance_shader_parameter(parameter, value)
