@tool
extends Node3D

# Parent of an extracted level's lights. Each light keeps the original's baked
# brightness in meta "me_brightness"; its energy is that times energy_scale.
#
# A DIAL, NOT A CONVERSION. The original is baked with Beast and there is no
# known mapping from its brightness to Godot energy; the default was picked by
# eye in the Stormdrain pillar hall. Override it on the instanced geometry in
# the level's shell, so rebuilding the geometry does not reset it.

@export var energy_scale: float = 16.0:
	set(value):
		energy_scale = value
		_apply()

func _ready() -> void:
	_apply()

func _apply() -> void:
	if not is_inside_tree():
		return
	for light in get_children():
		if light is Light3D and light.has_meta("me_brightness"):
			light.light_energy = float(light.get_meta("me_brightness")) * energy_scale
