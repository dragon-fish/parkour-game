@tool
class_name Headlight
extends Node3D

# A lamp on the front of something moving: the original hangs two of these on
# each train's head, 11.52 m ahead of it and 1.28 m either side of centre.
#
# WHAT IT IS FOR IS BEING SEEN FROM IN FRONT. The headlight is the second half
# of the warning the horn begins -- a pair of lights coming down a tunnel is
# how the player learns which way to get off the track. It is not there to
# light the tunnel, so the light's reach is short and the glow card does the
# work.
#
# A DIAL PANEL, NOT AN ASSEMBLER. The light and the card are real children in
# the scene file, editable and visible; this only pushes four numbers into
# them, so one node is the place to adjust a lamp rather than two.

## Colour of both the lamp and its glow.
@export var colour: Color = Color(1.0, 0.96, 0.88):
	set(value):
		colour = value
		_apply()
## Brightness of the point light.
@export var energy: float = 4.0:
	set(value):
		energy = value
		_apply()
## How far the point light reaches, metres. Short on purpose.
@export var reach: float = 12.0:
	set(value):
		reach = value
		_apply()
## Width of the glow card, metres. This is what carries at distance, so it is
## the dial to reach for when a train is not visible soon enough.
@export var glow_size: float = 1.6:
	set(value):
		glow_size = value
		_apply()


func _ready() -> void:
	_apply()


func _apply() -> void:
	if not is_inside_tree():
		return
	var lamp := get_node_or_null("Light") as OmniLight3D
	if lamp != null:
		lamp.light_color = colour
		lamp.light_energy = energy
		lamp.omni_range = reach
	var glow := get_node_or_null("Glow") as MeshInstance3D
	if glow == null:
		return
	var quad := glow.mesh as QuadMesh
	if quad != null:
		quad.size = Vector2(glow_size, glow_size)
	var material := glow.material_override as StandardMaterial3D
	if material != null:
		material.albedo_color = colour
