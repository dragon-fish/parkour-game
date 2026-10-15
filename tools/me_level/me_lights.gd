@tool
extends Node3D

# Parent of an extracted level's lights. Each light keeps the original's baked
# brightness in meta "me_brightness"; its energy is that times energy_scale,
# or modern_energy_scale under modern lighting.
#
# Under classic and hybrid lighting (SettingsStore.LIGHTING_MODES) these light
# only what moves -- the player's body, movers, rigid bodies -- the static world
# being drawn from its bake, lamps and all (hybrid takes only the sun out of
# it), and the frame is exposed by the original's eye adaptation. energy_scale
# was judged against lit walls under the older fixed exposure, not for that:
# re-judge it against the body beside a baked wall (modern_energy_scale's
# measurement says the bake's own units want about 1). Under modern lighting
# they light the world too.
#
# energy_scale IS A DIAL, NOT A CONVERSION. The original is baked with Beast and there is no
# known mapping from its brightness to Godot energy. Judged against the
# owner's screenshots of the original (.private/docs/me-reference-shots)
# together with me_environment.gd's EXPOSURE: at exposure 1.0, 16 matched
# Stormdrain's pillar hall and overexposed its lift corridor and 8 left the
# hall too dark; 12 was right, and 17 at exposure 0.7 reads the same indoors.
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
const Common := preload("res://tools/me_level/me_level_common.gd")
# On a light whose package is not in the level: it stays dark whoever asks.
const ABSENT_META := &"me_absent"

@export var energy_scale: float = 17.0:
	set(value):
		energy_scale = value
		_apply()
## Godot energy per unit of BakerBrightness under modern lighting
## (SettingsStore.LIGHTING_MODES), where the frame is in the bake's units and
## exposed by the original's eye adaptation, as the sun's energy is its
## BakerBrightness. Measured against the bake's irradiance in the tutorial's
## lamp-lit corridor and storeroom (white albedo, lamps alone): at 1, with
## Godot's own falloff, the lamps light them 1.06 and 0.78 times as the bake
## does; at energy_scale's 35 they were 25 times over, which no exposure the
## original's limits allow could bring down. With omni_attenuation 0 (UE3's
## falloff has no inverse distance) they were 2 to 4 times over. A dial.
@export var modern_energy_scale: float = 1.0:
	set(value):
		modern_energy_scale = value
		_apply()

## Shared by every lights node: the budget is per frame, not per node, or a
## chapter's seven sections would each spend it.
static var _budget_frame := -1
static var _budget_left := 0

var _dark: Array[Light3D] = []
## The lighting the level is drawn with (SettingsStore.LIGHTING_MODES).
var _lighting := "classic"

func _ready() -> void:
	_apply()
	if Engine.is_editor_hint():
		return
	SettingsStore.follow_lighting(self)
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
			light.visible = not light.get_meta(ABSENT_META, false)
		_budget_left -= 1
	if _dark.is_empty():
		remove_from_group(Arena.WARMING)
		set_process(false)

# PackagePresence's way in: a package arriving mid-level brings its lights on
# through the same budget as the load did, and one leaving takes them out at
# once. Through here rather than `visible`, which _process() also writes.
func set_present(light: Light3D, on: bool) -> void:
	light.set_meta(ABSENT_META, not on)
	if not on:
		light.visible = false
	elif not light.visible and not _dark.has(light):
		_dark.append(light)
		set_process(true)


## Classic and hybrid: the baked world takes no lamp, its light is in the
## bake. Modern: every lamp but one that lights only what moves lights the
## world too.
func use_lighting(mode: String) -> void:
	_lighting = mode
	for light in get_children():
		if light is Light3D and not light.get_meta(Common.CHARACTER_ONLY_META, false):
			if mode == "modern":
				light.light_cull_mask |= Common.BAKED_LAYER
			else:
				light.light_cull_mask &= ~Common.BAKED_LAYER
	_apply()


func _apply() -> void:
	if not is_inside_tree():
		return
	for light in get_children():
		if light is Light3D and light.has_meta("me_brightness"):
			var scale := modern_energy_scale if _lighting == "modern" else energy_scale
			light.light_energy = float(light.get_meta("me_brightness")) * scale
