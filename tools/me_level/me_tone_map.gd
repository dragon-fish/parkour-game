@tool
extends CompositorEffect

# Mirror's Edge's eye adaptation and tone mapping on the HDR frame, after the
# transparent pass and before Godot's own tone mapper, which is left linear at
# exposure 1 (me_environment.gd). Three compute passes, as the original's:
#   - one step a frame of the luminance average (me_tone_map_downsample.glsl);
#   - the exposure, adapted from last frame's (me_tone_map_exposure.glsl);
#   - the tone curve, grading, gamma and the 16-segment curves (me_tone_map.glsl).
# The shaders are the owner's modded ones, ported; the constants are what the
# game feeds them, read out of the binary (_local/me-re/findings/TM1.md).
#
# The fields below are the level's post process settings as the original
# resolves them -- world defaults plus the PC modifier, or the volume the
# camera is in -- and me_environment.gd writes them every frame.

const DOWNSAMPLE_SHADER := preload("res://tools/me_level/me_tone_map_downsample.glsl")
const EXPOSURE_SHADER := preload("res://tools/me_level/me_tone_map_exposure.glsl")
const TONE_MAP_SHADER := preload("res://tools/me_level/me_tone_map.glsl")

## [ME:CONFIRMED TM1] the luminance chain's levels after the view.
const CHAIN := [512, 128, 32, 8, 2, 1]
## [ME:CONFIRMED TM1 0x012d37e0] the caps the exposure pass puts on the speeds.
const SPEED_UP_CAP := 2.5
const SPEED_DOWN_CAP := 3.0
## [ME:CONFIRMED TM1 0x012d64e0] the luminance weights of the desaturation term.
const DESATURATION_WEIGHTS := Vector3(0.30, 0.59, 0.11)
## [ME:CONFIRMED TM1 reset] both exposure buffers start at 0.5 (TdClearPixelShader),
## exposure 32, which the first pass clamps to twice ExposureHigh.
const RESET_EXPOSURE := 0.5

var shadows := Vector3.ZERO
var highlights := Vector3.ONE
var midtones := Vector3.ONE
var desaturation := 0.0
var exposure_manual := 1.0
var exposure_speed_up := 3.5
var exposure_speed_down := 4.5
var exposure_high := 1.65
var exposure_low := 0.85
## Curves.Ms and Curves.Bs, 16 segments of (r, g, b).
var curve_m := PackedVector3Array()
var curve_b := PackedVector3Array()
## [ME:CONFIRMED TM1] the player's Brightness slider sets DisplayGamma to
## Brightness / 10 * 1.5 + 1.25: 2.0 at the default of 5, not the ini's 2.2.
var display_gamma := 2.0
## [ME:CONFIRMED TM1] Contrast / 10 * 0.6 + 0.7: 1.0 at the default of 5.
var contrast := 1.0
## The seconds the exposure adapts over this frame. [ME:INFERRED] the
## original's is the render thread's lag behind the game thread, about a
## frame; the frame's own delta stands in for it.
var delta := 1.0 / 60.0

var _rd: RenderingDevice
var _sampler: RID
var _pipelines := {}
var _shaders := {}
var _levels: Array[RID] = []
var _exposure: Array[RID] = []
var _parameters: RID
var _frame := 0
var _flip := 0
var _reset := true


func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	RenderingServer.call_on_render_thread(_create)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _rd != null:
		var owned: Array = []
		owned.append_array(_levels)
		owned.append_array(_exposure)
		owned.append_array([_parameters, _sampler])
		owned.append_array(_shaders.values())
		for rid: RID in owned:
			if rid.is_valid():
				_rd.free_rid(rid)


func _create() -> void:
	_rd = RenderingServer.get_rendering_device()
	if _rd == null:
		return
	for key: String in ["downsample", "exposure", "tone_map"]:
		var file: RDShaderFile = {"downsample": DOWNSAMPLE_SHADER, "exposure": EXPOSURE_SHADER,
				"tone_map": TONE_MAP_SHADER}[key]
		var shader := _rd.shader_create_from_spirv(file.get_spirv())
		_shaders[key] = shader
		_pipelines[key] = _rd.compute_pipeline_create(shader)
	var state := RDSamplerState.new()
	state.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	_sampler = _rd.sampler_create(state)
	for size: int in CHAIN:
		_levels.append(_image(size, RenderingDevice.DATA_FORMAT_R16G16B16A16_UNORM, PackedByteArray()))
	var start := PackedByteArray()
	start.resize(2)
	start.encode_u16(0, roundi(RESET_EXPOSURE * 65535.0))
	for k in 2:
		_exposure.append(_image(1, RenderingDevice.DATA_FORMAT_R16_UNORM, start))
	var bytes := PackedByteArray()
	bytes.resize(PARAMETER_BYTES)
	_parameters = _rd.uniform_buffer_create(PARAMETER_BYTES, bytes)


const PARAMETER_BYTES := 16 * 6 + 16 * 32


func _image(size: int, format: RenderingDevice.DataFormat, data: PackedByteArray) -> RID:
	var view := RDTextureFormat.new()
	view.width = size
	view.height = size
	view.format = format
	view.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT \
			| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	return _rd.texture_create(view, RDTextureView.new(), [data] if not data.is_empty() else [])


func _render_callback(_type: int, render_data: RenderData) -> void:
	if _rd == null or _pipelines.is_empty() or curve_m.size() != 16 or curve_b.size() != 16:
		return
	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	if buffers == null:
		return
	var size := buffers.get_internal_size()
	if size.x == 0 or size.y == 0:
		return
	var color := buffers.get_color_layer(0)
	_advance_average(color, size)
	_adapt()
	_rd.buffer_update(_parameters, 0, PARAMETER_BYTES, _parameter_bytes())
	var set := _uniform_set("tone_map", [_image_uniform(0, color), _image_uniform(1, _exposure[_flip]),
			_buffer_uniform(2, _parameters)])
	var list := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(list, _pipelines["tone_map"])
	_rd.compute_list_bind_uniform_set(list, set, 0)
	var push := PackedInt32Array([size.x, size.y, 0, 0]).to_byte_array()
	_rd.compute_list_set_push_constant(list, push, push.size())
	_rd.compute_list_dispatch(list, ceili(size.x / 8.0), ceili(size.y / 8.0), 1)
	_rd.compute_list_end()


## [ME:CONFIRMED TM1 0x012d64e0] one step of the chain a frame on a 7-frame
## cycle (0: view -> 512, 1: idle, 2..6: the rest), the whole chain at once on
## a reset. The exposure reads whatever the last level holds: an average that
## changes every 7 frames and is 6 frames old when it does.
func _advance_average(color: RID, size: Vector2i) -> void:
	var steps: Array[int] = []
	if _reset:
		steps = [0, 1, 2, 3, 4, 5]
	else:
		var phase := _frame % 7
		if phase == 0:
			steps = [0]
		elif phase >= 2:
			steps = [phase - 1]
	_frame += 1
	for step in steps:
		var source: RID = color if step == 0 else _levels[step - 1]
		var source_size: Vector2i = size if step == 0 else Vector2i(CHAIN[step - 1], CHAIN[step - 1])
		var target_size: int = CHAIN[step]
		var taps := clampi(roundi(float(source_size.x) / target_size), 1, 4)
		var set := _uniform_set("downsample", [_sampler_uniform(0, source), _image_uniform(1, _levels[step])])
		var list := _rd.compute_list_begin()
		_rd.compute_list_bind_compute_pipeline(list, _pipelines["downsample"])
		_rd.compute_list_bind_uniform_set(list, set, 0)
		var push := PackedInt32Array([source_size.x, source_size.y, target_size, target_size, taps, 0, 0, 0]).to_byte_array()
		_rd.compute_list_set_push_constant(list, push, push.size())
		_rd.compute_list_dispatch(list, ceili(target_size / 8.0), ceili(target_size / 8.0), 1)
		_rd.compute_list_end()


## [ME:CONFIRMED TM1 0x012d37e0] ExposureSettings = (Manual, dt * min(SpeedUp,
## 2.5), Low, High), MaxDeltaDown = dt * min(SpeedDown, 3); the pass reads one
## ping-pong buffer and writes the other, which the tone mapping then reads.
func _adapt() -> void:
	var previous: RID = _exposure[_flip]
	_flip = 1 - _flip
	var set := _uniform_set("exposure", [_image_uniform(0, _levels[CHAIN.size() - 1]),
			_image_uniform(1, previous), _image_uniform(2, _exposure[_flip])])
	var list := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(list, _pipelines["exposure"])
	_rd.compute_list_bind_uniform_set(list, set, 0)
	var push := PackedFloat32Array([exposure_manual, delta * minf(exposure_speed_up, SPEED_UP_CAP),
			exposure_low, exposure_high, delta * minf(exposure_speed_down, SPEED_DOWN_CAP), 0.0, 0.0, 0.0]).to_byte_array()
	_rd.compute_list_set_push_constant(list, push, push.size())
	_rd.compute_list_dispatch(list, 1, 1, 1)
	_rd.compute_list_end()
	_reset = false


func _parameter_bytes() -> PackedByteArray:
	var inverse := Vector3(1.0 / highlights.x, 1.0 / highlights.y, 1.0 / highlights.z)
	var values := PackedFloat32Array([
		inverse.x, inverse.y, inverse.z, 0.0,
		shadows.x * inverse.x, shadows.y * inverse.y, shadows.z * inverse.z, 1.0 - desaturation,
		midtones.x, midtones.y, midtones.z, 0.0,
		DESATURATION_WEIGHTS.x * desaturation, DESATURATION_WEIGHTS.y * desaturation, DESATURATION_WEIGHTS.z * desaturation, 0.0,
		# No camera fade: ColorScale 1, OverlayColor 0.
		1.0, 1.0, 1.0, 1.0 / display_gamma,
		0.0, 0.0, 0.0, 0.0,
	])
	var segments := build_curves(curve_m, curve_b, contrast)
	var k := PackedFloat32Array()
	var m := PackedFloat32Array()
	for i in 16:
		# [ME:CONFIRMED TM1] texel 15 repeats segment 14.
		var s: int = mini(i, 14)
		var slope: Vector3 = segments[0][s]
		var offset: Vector3 = segments[1][s]
		k.append_array([slope.x, offset.x, slope.y, offset.y])
		m.append_array([slope.z, offset.z, 0.0, 0.0])
	values.append_array(k)
	values.append_array(m)
	return values.to_byte_array()


## The curve segments as the render thread builds them from Curves.Ms/Bs:
## [ME:CONFIRMED TM1 0x12d7320, emulated] M = Ms + (Contrast - 1), B = Bs,
## then a monotonic clamp that keeps a running maximum of the segments' START
## values only. Returns [slopes, offsets], 16 each.
static func build_curves(ms: PackedVector3Array, bs: PackedVector3Array, contrast_value: float) -> Array:
	var c := contrast_value - 1.0
	var slopes := PackedVector3Array()
	var offsets := PackedVector3Array()
	for i in 16:
		slopes.append(ms[i] + Vector3(c, c, c))
		offsets.append(bs[i])
	var run := Vector3.ZERO
	var step := 1.0 / 15.0
	for i in 16:
		var x0 := i * step
		var x1 := (i + 1) * step
		var slope := slopes[i]
		var offset := offsets[i]
		for ch in 3:
			var y0 := x0 * slope[ch] + offset[ch]
			var y1 := x1 * slope[ch] + offset[ch]
			run[ch] = maxf(run[ch], y0)
			var r: float = run[ch]
			if r > y0 and r > y1:
				slope[ch] = 0.0
				offset[ch] = r
			elif r > y0:
				slope[ch] = (y1 - r) / (x1 - x0)
				offset[ch] = r - slope[ch] * x0
			elif r > y1:
				slope[ch] = (y0 - r) / (x0 - x1)
				offset[ch] = r - slope[ch] * x1
		slopes[i] = slope
		offsets[i] = offset
	return [slopes, offsets]


func _uniform_set(shader: String, uniforms: Array) -> RID:
	return UniformSetCacheRD.get_cache(_shaders[shader], 0, uniforms)


static func _image_uniform(binding: int, image: RID) -> RDUniform:
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform.binding = binding
	uniform.add_id(image)
	return uniform


func _sampler_uniform(binding: int, texture: RID) -> RDUniform:
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	uniform.binding = binding
	uniform.add_id(_sampler)
	uniform.add_id(texture)
	return uniform


static func _buffer_uniform(binding: int, buffer: RID) -> RDUniform:
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	uniform.binding = binding
	uniform.add_id(buffer)
	return uniform
