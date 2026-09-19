@tool
extends Node3D

# Parent of an extracted level's lights. Each light keeps the original's baked
# brightness in meta "me_brightness"; its energy is that times energy_scale.
#
# A DIAL, NOT A CONVERSION. The original is baked with Beast and there is no
# known mapping from its brightness to Godot energy. 12 was judged against the
# owner's screenshots of the original under me_environment.gd's fixed
# exposure: 16 matched Stormdrain's pillar hall and overexposed its lift
# corridor, 8 left the hall too dark.
# JUDGE IT IN THE GAME, not in the editor: the editor's preview environment
# auto-exposes, and a scale that looks right there (1) left every interior
# near black in play. Override it on the instanced geometry in the level's
# shell, so rebuilding the geometry does not reset it. DO NOT edit a light's
# energy instead: _apply() rewrites every one from its me_brightness whenever
# the scene is opened.
#
# LIT A FEW AT A TIME. Measured on Stormdrain's 1146 lights: drawn all at once
# they cost the first two frames 8.4 s and 4.0 s; switched on LIGHTS_PER_FRAME
# at a time they cost 0.64 s in all, no frame over 25 ms. The node sits in
# Arena.WARMING until its last light is on, which is what holds the loading
# curtain.

const LIGHTS_PER_FRAME := 32

@export var energy_scale: float = 12.0:
	set(value):
		energy_scale = value
		_apply()

## Shared by every lights node: the budget is per frame, not per node, or a
## chapter's seven sections would each spend it.
static var _budget_frame := -1
static var _budget_left := 0

var _dark: Array[Light3D] = []

func _ready() -> void:
	_apply()
	if Engine.is_editor_hint():
		return
	for light in get_children():
		if light is Light3D and light.visible:
			light.visible = false
			_dark.append(light)
	if _dark.is_empty():
		return
	add_to_group(Arena.WARMING)
	set_process(true)

func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or _dark.is_empty():
		set_process(false)
		return
	var frame := Engine.get_process_frames()
	if frame != _budget_frame:
		_budget_frame = frame
		_budget_left = LIGHTS_PER_FRAME
	while _budget_left > 0 and not _dark.is_empty():
		var light: Light3D = _dark.pop_back()
		if is_instance_valid(light):
			light.visible = true
		_budget_left -= 1
	if _dark.is_empty():
		remove_from_group(Arena.WARMING)
		set_process(false)

func _apply() -> void:
	if not is_inside_tree():
		return
	for light in get_children():
		if light is Light3D and light.has_meta("me_brightness"):
			light.light_energy = float(light.get_meta("me_brightness")) * energy_scale
