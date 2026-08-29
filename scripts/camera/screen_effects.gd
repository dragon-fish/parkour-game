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
## 1.0 is the picture untouched. Below one dims, above one lifts.
var brightness: float = 1.0
## Pivoted on mid grey, so raising it does not also raise the average.
var contrast: float = 1.0
## How strongly the edge of the screen is closing in, 0 for not at all.
var vignette_amount: float = 0.0
## How far in from the corner it reaches.
var vignette_width: float = 0.45

# Cached in GDScript, same as the three floats above, so a set_tint() call
# made before _ready() (e.g. right after ScreenEffects.new(), before
# add_child()) is not silently dropped. Without this the colour had no home
# to live in until the material existed, _push() never resent it (it only
# ever pushed the three floats), and the shader default (red) would win
# forever with no error anywhere.
var _tint_color: Color = Color(1.0, 0.0, 0.0, 1.0)
## Cached for the same reason _tint_color is: a value set before _ready() has
## nowhere else to live until the material exists.
var _vignette_color: Color = Color.BLACK

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

## Read-only accessor for _tint_color, mirroring how tint_amount/desaturation/
## blur are exposed as plain vars -- tests assert against this rather than
## reading the uniform back (see the other three: this layer's test coverage
## is scoped to the GDScript members, not the shader/uniform chain).
func tint_color() -> Color:
	return _tint_color

func set_tint(color: Color, amount: float) -> void:
	_tint_color = color
	tint_amount = clampf(amount, 0.0, 1.0)
	_push()

func set_desaturation(amount: float) -> void:
	desaturation = clampf(amount, 0.0, 1.0)
	_push()

func set_blur(amount: float) -> void:
	blur = clampf(amount, 0.0, 1.0)
	_push()

## The grade. Dimming and steepening together is what unconsciousness looks
## like: the picture loses its light without losing its shape, which reading
## the two knobs separately would not give.
func set_grade(brightness_scale: float, contrast_scale: float) -> void:
	brightness = clampf(brightness_scale, 0.0, 2.0)
	contrast = clampf(contrast_scale, 0.0, 3.0)
	_push()

## Read-only accessor for _vignette_color, same stance as tint_color().
func vignette_color() -> Color:
	return _vignette_color

func set_vignette(color: Color, amount: float, width: float = 0.45) -> void:
	_vignette_color = color
	vignette_amount = clampf(amount, 0.0, 1.0)
	vignette_width = clampf(width, 0.05, 1.0)
	_push()

func _push() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("tint_color", _tint_color)
	_material.set_shader_parameter("tint_amount", tint_amount)
	_material.set_shader_parameter("desaturation", desaturation)
	_material.set_shader_parameter("blur", blur)
	_material.set_shader_parameter("brightness", brightness)
	_material.set_shader_parameter("contrast", contrast)
	_material.set_shader_parameter("vignette_color", _vignette_color)
	_material.set_shader_parameter("vignette_amount", vignette_amount)
	_material.set_shader_parameter("vignette_width", vignette_width)
