@tool
extends EditorPlugin

# Registers the respawn gizmos. This exists because a Checkpoint is an Area3D
# (it must be -- body_entered is its whole job) and nothing gives a bare
# Area3D a clickable presence in the viewport; the owner had to select them
# through the scene tree. A gizmo plugin is the same machinery that makes a
# Marker3D pickable, so both respawn nodes get it.

const Gizmos = preload("res://addons/respawn_gizmos/gizmo_plugin.gd")

var _gizmos: EditorNode3DGizmoPlugin = null

func _enter_tree() -> void:
	_gizmos = Gizmos.new()
	add_node_3d_gizmo_plugin(_gizmos)

func _exit_tree() -> void:
	remove_node_3d_gizmo_plugin(_gizmos)
	_gizmos = null
