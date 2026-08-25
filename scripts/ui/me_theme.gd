class_name MeTheme
extends RefCounted

# Mirror's Edge-styled UI factory: brand colors plus the two shared
# ShaderMaterial/StyleBox builders the menu scenes are composed from. Every
# member here is static and stateless -- this class is never instantiated,
# it just hands callers a fresh Resource each time.

const BRAND_RED := Color("#e90100")
const TEXT_BLUE := Color("#2d557e")
const BACKDROP := Color(0.90, 0.93, 0.97, 0.72)

## ✅ THE OWNER's Photoshop spec for UI text shadow (2026-08-26): multiply
## black at 35%, angle 135°, distance 4 px, spread 0, size 0 -- i.e. a HARD
## shadow offset (+2.83, +2.83), no blur (the style rule agrees). Multiply
## blend is approximated by plain alpha black, indistinguishable on our
## light surfaces.
const TEXT_SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.35)
const TEXT_SHADOW_OFFSET := 3

static var _ui_theme: Theme = null

## The one Theme every menu-family root wears: default font shadow for all
## Labels (and Buttons' text). Cached -- one instance serves everything.
static func ui_theme() -> Theme:
	if _ui_theme == null:
		_ui_theme = Theme.new()
		for cls in ["Label", "Button"]:
			_ui_theme.set_color("font_shadow_color", cls, TEXT_SHADOW_COLOR)
			_ui_theme.set_constant("shadow_offset_x", cls, TEXT_SHADOW_OFFSET)
			_ui_theme.set_constant("shadow_offset_y", cls, TEXT_SHADOW_OFFSET)
			_ui_theme.set_constant("shadow_outline_size", cls, 0)
	return _ui_theme

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


# ---------------------------------------------------------------------------
# 现代化改良五件套 shapes shared between the main menu and the pause menu
# (main_menu.gd, pause_ui.gd) -- factored here once both screens needed the
# same corner metadata / paper grain / footer key-hint pieces, so neither
# file carries its own copy. Every builder below only constructs and returns
# the node; the caller still add_child()s it and owns its lifetime/visibility
# (pause_ui.gd's _set_shown() in particular has to flip these `visible`
# flags itself -- see its own comment for why).
# ---------------------------------------------------------------------------

const _PAPER_NOISE_SHADER := preload("res://scripts/ui/paper_noise.gdshader")

## One "+"-style corner metadata label -- the small typographic detail in
## each screen corner (main menu: three "+" plus the version string; pause:
## reused as-is, see pause_ui.gd's _build_corner_metadata()).
static func _themed(label: Label) -> Label:
	label.theme = ui_theme()
	return label

static func corner_label(text: String, anchor_x: float, anchor_y: float, offset: Vector2, right_aligned: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", TEXT_BLUE)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.anchor_left = anchor_x
	label.anchor_right = anchor_x
	label.anchor_top = anchor_y
	label.anchor_bottom = anchor_y
	label.size = Vector2(160.0, 24.0)
	label.position = offset - (Vector2(160.0, 0.0) if right_aligned else Vector2.ZERO)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if right_aligned else HORIZONTAL_ALIGNMENT_LEFT
	return _themed(label)

## A near-invisible paper-grain overlay (paper_noise.gdshader), full-rect and
## ready to add_child directly onto anything that covers the whole screen.
static func paper_noise_layer() -> ColorRect:
	var layer := ColorRect.new()
	layer.color = Color(1.0, 1.0, 1.0, 1.0)
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = _PAPER_NOISE_SHADER
	layer.material = material
	return layer

## Bottom-center footer key-hint label. Text is the caller's own truth (the
## main menu's "↑↓ 选择 · Enter 确认" and the pause menu's "Esc 继续 · Enter
## 确认" are different sentences, not the same one reused).
static func footer_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", TEXT_BLUE)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.anchor_left = 0.5
	label.anchor_right = 0.5
	label.anchor_top = 1.0
	label.anchor_bottom = 1.0
	label.position = Vector2(-160.0, -40.0)
	label.size = Vector2(320.0, 24.0)
	return _themed(label)
