class_name RespawnPreview
extends Object

# EDITOR-ONLY visual: a translucent capsule at the player's own size plus an
# arrow down -Z, showing where a respawned body stands and which way it
# faces. Built by the Checkpoint and SpawnPoint tool scripts; never given an
# owner, so it is not saved into the scene, and the game never builds it.
#
# `capsule_bottom_y` states the node's own semantic honestly: a Checkpoint
# respawns FEET AT THE ORIGIN (bottom 0), a SpawnPoint carries the older
# centre-at-origin convention (bottom -0.9) that every existing level's
# marker was placed under.

const NAME := "EditorPreview"

static func build(parent: Node3D, color: Color, capsule_bottom_y: float) -> void:
	if parent.has_node(NAME):
		return
	var root := Node3D.new()
	root.name = NAME

	var glass := StandardMaterial3D.new()
	glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(color, 0.35)

	var capsule := MeshInstance3D.new()
	var capsule_mesh := CapsuleMesh.new()
	capsule_mesh.radius = 0.3
	capsule_mesh.height = 1.8
	capsule.mesh = capsule_mesh
	capsule.material_override = glass
	capsule.position.y = capsule_bottom_y + 0.9
	root.add_child(capsule)

	var solid := StandardMaterial3D.new()
	solid.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	solid.albedo_color = Color(color, 0.9)

	# The arrow: shaft plus cone at chest height, pointing down -Z -- the
	# direction the body wakes up facing. Cylinders grow along +Y, so both
	# pieces are tipped -90 about X to lie along -Z.
	var chest: float = capsule_bottom_y + 1.0
	var shaft := MeshInstance3D.new()
	var shaft_mesh := CylinderMesh.new()
	shaft_mesh.top_radius = 0.04
	shaft_mesh.bottom_radius = 0.04
	shaft_mesh.height = 0.5
	shaft.mesh = shaft_mesh
	shaft.material_override = solid
	shaft.rotation_degrees.x = -90.0
	shaft.position = Vector3(0.0, chest, -0.55)
	root.add_child(shaft)

	var head := MeshInstance3D.new()
	var head_mesh := CylinderMesh.new()
	head_mesh.top_radius = 0.0
	head_mesh.bottom_radius = 0.12
	head_mesh.height = 0.25
	head.mesh = head_mesh
	head.material_override = solid
	head.rotation_degrees.x = -90.0
	head.position = Vector3(0.0, chest, -0.925)
	root.add_child(head)

	parent.add_child(root)
