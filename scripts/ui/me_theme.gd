class_name MeTheme
extends RefCounted

# Mirror's Edge-styled UI factory: brand colors plus the two shared
# ShaderMaterial/StyleBox builders the menu scenes are composed from. Every
# member here is static and stateless -- this class is never instantiated,
# it just hands callers a fresh Resource each time.

const BRAND_RED := Color("#e90100")
const TEXT_BLUE := Color("#2d557e")
const BACKDROP := Color(0.90, 0.93, 0.97, 0.72)

const _EDGE_WAVE_SHADER := preload("res://scripts/ui/edge_wave.gdshader")
const _DOT_GRID_SHADER := preload("res://scripts/ui/dot_grid.gdshader")


## A skewed StyleBoxFlat for ME menu buttons/panels: a light parallelogram
## lean per the spec's "skew(0deg, -3deg)" reference. Godot's
## StyleBoxFlat.skew.x is a plain horizontal shear factor (dx per unit dy,
## see style_box_flat.cpp), so -3deg's tangent gives the same small lean the
## spec describes without pretending it is a literal CSS skew() angle pair.
## v1 stays a parallelogram -- the spec explicitly does not chase a true
## narrowing-right-edge trapezoid.
static func button_style(bg: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.skew = Vector2(tan(deg_to_rad(-3.0)), 0.0)
	return style


## ShaderMaterial wrapping edge_wave.gdshader with amplitude_px set. The
## remaining uniforms (frequency, speed, seeds, width_px) keep the shader's
## own defaults until the caller overrides them -- notably width_px, which
## the consuming Control is expected to sync to its own size.x (see the
## shader's AMPLITUDE UNITS comment).
static func wave_material(amplitude_px: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = _EDGE_WAVE_SHADER
	material.set_shader_parameter("amplitude_px", amplitude_px)
	return material


## ShaderMaterial wrapping dot_grid.gdshader for the main-menu floor. All
## uniforms keep the shader's own defaults; callers dial spacing/dot_size/
## speed/pulse/tint/base directly on the returned material as needed.
static func dot_grid_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = _DOT_GRID_SHADER
	return material
