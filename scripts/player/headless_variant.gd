class_name HeadlessVariant
extends Node

# The VRM-style first-person mesh split, rebuilt at runtime for a body that
# ships as one mesh: every mesh fully skinned to the head moves to the
# THIRD-PERSON render layers, and a mesh that mixes head and body triangles
# gets a generated headless duplicate on the FIRST-PERSON layers while the
# original joins the full-head group. Cameras cull by those layers -- see
# CameraRig._apply_body_layers.
#
# ⚠️ A MESH THE CAMERA CULLS DOES NOT CAST A SHADOW EITHER. An earlier version
# of this header claimed the opposite ("lights cull by nothing, so in first
# person the full-head meshes still cast their shadow") and it was simply
# wrong: the owner reported the shadow "从脖子直接断开，连头型都没有" -- the
# headless twin was the only thing casting. Godot's documented "still casts
# shadows" case is about a LIGHT's cull mask, which is a different mask.
#
# So the head's silhouette needs an instance no camera culls: a third,
# never-drawn copy on SHADOW_CASTING_SETTING_SHADOWS_ONLY. That is exactly
# what godot-vrm does for VRM bodies (addons/vrm/vrm_utils.gd, the
# BothLayersWithShadow path, "(Shadow)" duplicate node) -- and the reason this
# bug came back on an FBX body after being fixed once for a VRM one is that
# the fix lives in the importer, not here. This file reproduced the layer
# split and not the shadow stand-in. ✅ The owner, originally: "应该用
# shadow only 而不是直接 disabled".
#
# Runs only under a Player (that is where the layer convention lives);
# anywhere else -- the menu silhouette, a gallery -- the body stays whole.
# Place as a child of the Skeleton3D whose meshes it splits.

@export var head_bone_name: String = "Head"
## A triangle is "head" when any of its vertices carries at least this much
## total weight on head-descendant bones.
const HEAD_WEIGHT := 0.5
## A whole mesh is "head" when at least this fraction of its vertices are.
const ALL_HEAD_FRACTION := 0.99

func _ready() -> void:
	var skeleton := get_parent() as Skeleton3D
	if skeleton == null:
		return
	var player: Node = get_parent()
	while player != null and not (player is Player):
		player = player.get_parent()
	if player == null or player.config == null:
		return
	var first: int = player.config.camera.first_person_body_layers
	var third: int = player.config.camera.third_person_body_layers

	var head_bones := _head_bone_set(skeleton)
	if head_bones.is_empty():
		return
	# Deferred: _ready fires while the skeleton is still setting up its
	# children, and add_sibling() during that window is refused.
	_run_split.call_deferred(skeleton, head_bones, first, third)

func _run_split(skeleton: Skeleton3D, head_bones: Dictionary, first: int, third: int) -> void:
	for child in skeleton.get_children().duplicate():
		if child is MeshInstance3D:
			_split(child, skeleton, head_bones, first, third)

func _head_bone_set(skeleton: Skeleton3D) -> Dictionary:
	var head := skeleton.find_bone(head_bone_name)
	if head < 0:
		return {}
	var out := {head: true}
	var grew := true
	while grew:
		grew = false
		for i in skeleton.get_bone_count():
			if out.has(i):
				continue
			if out.has(skeleton.get_bone_parent(i)):
				out[i] = true
				grew = true
	return out

func _split(mi: MeshInstance3D, skeleton: Skeleton3D, head_bones: Dictionary,
		first: int, third: int) -> void:
	if mi.mesh == null or mi.skin == null:
		return
	# Map the skin's bind slots (what ARRAY_BONES indexes) to skeleton bones.
	var bind_is_head := PackedByteArray()
	bind_is_head.resize(mi.skin.get_bind_count())
	for b in mi.skin.get_bind_count():
		var bone := mi.skin.get_bind_bone(b)
		if bone < 0:
			bone = skeleton.find_bone(mi.skin.get_bind_name(b))
		bind_is_head[b] = 1 if head_bones.has(bone) else 0

	var headless := ArrayMesh.new()
	var kept_any := false
	var dropped_any := false
	var total_verts := 0
	var head_verts := 0
	for s in mi.mesh.get_surface_count():
		var arrays := mi.mesh.surface_get_arrays(s)
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights = arrays[Mesh.ARRAY_WEIGHTS]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var vert_count: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		if bones.is_empty() or indices.is_empty() or vert_count == 0:
			continue
		var influences := bones.size() / vert_count
		var is_head := PackedByteArray()
		is_head.resize(vert_count)
		for v in vert_count:
			var w := 0.0
			for k in influences:
				if bind_is_head[bones[v * influences + k]] == 1:
					w += float(weights[v * influences + k])
			is_head[v] = 1 if w >= HEAD_WEIGHT else 0
			total_verts += 1
			head_verts += is_head[v]
		var kept := PackedInt32Array()
		for t in range(0, indices.size(), 3):
			if is_head[indices[t]] == 1 or is_head[indices[t + 1]] == 1 \
					or is_head[indices[t + 2]] == 1:
				dropped_any = true
				continue
			kept.append(indices[t])
			kept.append(indices[t + 1])
			kept.append(indices[t + 2])
		if kept.is_empty():
			continue
		arrays[Mesh.ARRAY_INDEX] = kept
		var flags := Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if influences == 8 else 0
		var before := headless.get_surface_count()
		headless.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
		if headless.get_surface_count() == before:
			continue
		var mat := mi.get_surface_override_material(s)
		if mat == null:
			mat = mi.mesh.surface_get_material(s)
		headless.surface_set_material(headless.get_surface_count() - 1, mat)
		kept_any = true

	if total_verts > 0 and float(head_verts) / float(total_verts) >= ALL_HEAD_FRACTION:
		# Entirely head -- a separate hair, face or horn mesh. Drawn only in
		# third person; its silhouette carries on in first person through the
		# stand-in, which is added BEFORE the layers move so it inherits the
		# ones the mesh arrived on.
		_add_shadow_stand_in(mi, skeleton)
		mi.layers = third
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return
	if not dropped_any or not kept_any:
		return  # no head triangles at all -- visible in both views as-is
	_add_shadow_stand_in(mi, skeleton)
	var twin := MeshInstance3D.new()
	twin.name = mi.name + "Headless"
	twin.mesh = headless
	twin.skin = mi.skin
	twin.layers = first
	# The twin is the one whose shadow was WRONG -- headless, cut at the neck.
	# The stand-in above already casts the whole body including the head, so
	# leaving this on would only add a second, truncated caster on top of it.
	twin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.add_sibling(twin)
	twin.skeleton = twin.get_path_to(skeleton)
	mi.layers = third
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## The never-drawn full-body copy that casts for BOTH views. SHADOWS_ONLY means
## no camera ever renders it, so the layers it keeps do not matter for what you
## see -- only for what gets into the shadow map, which is why it inherits the
## caller's ORIGINAL layers rather than either half of the split.
##
## Shares `mi.mesh` rather than copying it: this is a second instance of the
## same surfaces, not a second mesh.
func _add_shadow_stand_in(mi: MeshInstance3D, skeleton: Skeleton3D) -> void:
	var stand_in := MeshInstance3D.new()
	stand_in.name = mi.name + "Shadow"
	stand_in.mesh = mi.mesh
	stand_in.skin = mi.skin
	stand_in.layers = mi.layers
	stand_in.transform = mi.transform
	stand_in.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	mi.add_sibling(stand_in)
	# After add_sibling, same as the headless twin: the path is only resolvable
	# once the node is in the tree.
	stand_in.skeleton = stand_in.get_path_to(skeleton)
