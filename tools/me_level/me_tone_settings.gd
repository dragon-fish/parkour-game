@tool
extends Resource

# What the original's tone mapping pass is fed in one place of a level: the
# world's settings, or a PostProcessVolume's inside its brush. Resolved by the
# extractor (environment.tone_map): struct defaults, the PC modifier and the
# curves' 16 stored segments. me_environment.gd blends between them as the
# camera moves and hands the result to me_tone_map.gd.

@export var shadows := Vector3.ZERO
@export var highlights := Vector3.ONE
@export var midtones := Vector3.ONE
@export var desaturation := 0.0
@export var exposure_manual := 1.0
@export var exposure_speed_up := 3.5
@export var exposure_speed_down := 4.5
@export var exposure_high := 1.65
@export var exposure_low := 0.85
## Seconds a change of settings blends over.
@export var interpolation_s := 1.0
## Curves.Ms and Curves.Bs: 16 segments of (r, g, b).
@export var curve_m := PackedVector3Array()
@export var curve_b := PackedVector3Array()


static func from_manifest(data: Dictionary) -> Resource:
	var out: Resource = load("res://tools/me_level/me_tone_settings.gd").new()
	for key in ["shadows", "highlights", "midtones"]:
		out.set(key, Vector3(data[key][0], data[key][1], data[key][2]))
	for key in ["desaturation", "exposure_manual", "exposure_speed_up", "exposure_speed_down",
			"exposure_high", "exposure_low", "interpolation_s"]:
		out.set(key, float(data[key]))
	for key in ["curve_m", "curve_b"]:
		var values := PackedVector3Array()
		for v: Array in data[key]:
			values.append(Vector3(v[0], v[1], v[2]))
		out.set(key, values)
	return out


## This toward `target` by `fade`, every value -- the curves and the five
## exposure values included, as the original's LocalPlayer blends them.
##
## DO NOT write the curves in place (`curve_m[i] = ...`). Resource.duplicate()
## hands the copy the SAME packed arrays as the original, so the blended copy
## and the world settings it was duplicated from share their curves: blending
## into the tutorial's corridor wrote the volume's identity curves into the
## world's, and the street stayed ungraded, without its blue, ever after.
func blend_toward(target: Resource, fade: float) -> void:
	shadows = shadows.lerp(target.shadows, fade)
	highlights = highlights.lerp(target.highlights, fade)
	midtones = midtones.lerp(target.midtones, fade)
	for key in ["desaturation", "exposure_manual", "exposure_speed_up", "exposure_speed_down",
			"exposure_high", "exposure_low"]:
		set(key, lerpf(get(key), target.get(key), fade))
	curve_m = _lerp_curve(curve_m, target.curve_m, fade)
	curve_b = _lerp_curve(curve_b, target.curve_b, fade)


static func _lerp_curve(from: PackedVector3Array, to: PackedVector3Array, fade: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in mini(from.size(), to.size()):
		out.append(from[i].lerp(to[i], fade))
	return out


## The values onto the tone mapping effect.
func apply(effect: CompositorEffect) -> void:
	for key in ["shadows", "highlights", "midtones", "desaturation", "exposure_manual", "exposure_speed_up",
			"exposure_speed_down", "exposure_high", "exposure_low"]:
		effect.set(key, get(key))
	effect.set("curve_m", curve_m.duplicate())
	effect.set("curve_b", curve_b.duplicate())
