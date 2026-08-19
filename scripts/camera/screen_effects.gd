class_name ScreenEffects
extends CanvasLayer

# A full-screen shader owned by the PLAYER, not the level: these effects
# describe what happened to the body, so they must survive a level change and
# must not fight the level's own WorldEnvironment for the same knobs.
#
# Deliberately stateless in time. A caller sets a number; fading in and out is
# the caller's business. See spec §6.

const SHADER := preload("res://shaders/screen_effects.gdshader")

var tint_amount: float = 0.0
var desaturation: float = 0.0
var blur: float = 0.0

var _rect: ColorRect
var _material: ShaderMaterial

func _ready() -> void:
	layer = 100
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_rect = ColorRect.new()
	_rect.material = _material
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)
	_push()

func set_tint(color: Color, amount: float) -> void:
	tint_amount = clampf(amount, 0.0, 1.0)
	if _material != null:
		_material.set_shader_parameter("tint_color", color)
	_push()

func set_desaturation(amount: float) -> void:
	desaturation = clampf(amount, 0.0, 1.0)
	_push()

func set_blur(amount: float) -> void:
	blur = clampf(amount, 0.0, 1.0)
	_push()

func clear() -> void:
	tint_amount = 0.0
	desaturation = 0.0
	blur = 0.0
	_push()

func _push() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("tint_amount", tint_amount)
	_material.set_shader_parameter("desaturation", desaturation)
	_material.set_shader_parameter("blur", blur)
