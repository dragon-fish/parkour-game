class_name MeCreditsScreen
extends Control

# 版权信息: the credits page, an in-menu overlay in the same family as
# MeSettingsMenu (pale wash, hairline panel, red skewed button). Pushed over
# the main menu's column by MainMenu and dismissed with 返回 or Esc.
#
# All wording lives in the CONTENT block below and nowhere else; the build code
# only lays it out.

signal closed

# ---------------------------------------------------------------------------
# CONTENT. Edit text here. BBCode is enabled in the body, so keep "[" and "]"
# out of the strings; the source link is wrapped in [url] by the layout code.
# ---------------------------------------------------------------------------

const TITLE := "版权信息"
const BACK_TEXT := "返回"

const BACKGROUND := "一个用 Godot 4.7 制作的跑酷原型，以《镜之边缘》(Mirror's Edge, 2008) 为参照，移动手感依据对原版的逆向分析与逐帧实测一比一还原，而不是凭记忆调出来的。"
const AUTHOR := "dragon-fish"
const SOURCE_URL := "https://github.com/dragon-fish/parkour-game"
const LICENCE := "GNU AGPL v3（AGPL-3.0-only）"
const LICENCE_SCOPE := "此协议仅涵盖本项目自身的代码，不延伸至下列第三方内容。"
const MODEL_CREDIT := "角色模型：beriul（作者署名待补）"
const ANIMATION_CREDIT := "Quaternius《Universal Animation Library》1 与 2（https://quaternius.com/）"
const ADDONS_CREDIT := "内置插件（MIT）：GUT、godot-vrm、MToon shader，详见 NOTICE.md。"
const ME_NOTICE := "部分关卡与素材提取自《镜之边缘》(Mirror's Edge)，版权归 Electronic Arts / DICE 所有。本项目与 EA、DICE 无任何关联。"
const DISCLAIMER := "此构建版本仅供《镜之边缘》玩家圈子内交流学习使用，请勿用于商业用途或二次分发。"

## Section headings paired with their body lines, in display order. A body
## entry of SOURCE_URL is rendered as a clickable link.
const SECTIONS := [
	{"heading": "项目背景", "lines": [BACKGROUND]},
	{"heading": "作者", "lines": [AUTHOR]},
	{"heading": "源代码", "lines": [SOURCE_URL]},
	{"heading": "授权协议", "lines": [LICENCE, LICENCE_SCOPE]},
	{"heading": "第三方内容", "lines": [MODEL_CREDIT, ANIMATION_CREDIT, ADDONS_CREDIT]},
	{"heading": "《镜之边缘》相关", "lines": [ME_NOTICE]},
	{"heading": "声明", "lines": [DISCLAIMER]},
]

const _BODY_SIZE := 20
const _HEADING_SIZE := 22

var _back_button: Button
var _body: RichTextLabel

func _ready() -> void:
	theme = MeTheme.ui_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()

## Called by the host each time the page is shown.
func open() -> void:
	visible = true
	_body.get_parent().scroll_vertical = 0
	_back_button.grab_focus()

func close() -> void:
	visible = false
	closed.emit()

func _build_ui() -> void:
	var wash := ColorRect.new()
	wash.color = Color(0.93, 0.95, 0.98, 0.98)
	wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wash)

	# Anchored by fraction, not a fixed box: the panel must still fit at the
	# smallest window preset.
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", MeTheme.panel_style())
	panel.anchor_left = 0.1
	panel.anchor_right = 0.9
	panel.anchor_top = 0.08
	panel.anchor_bottom = 0.92
	panel.offset_left = 0.0
	panel.offset_right = 0.0
	panel.offset_top = 0.0
	panel.offset_bottom = 0.0
	add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	margin.add_child(column)

	var title := Label.new()
	title.text = TITLE
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(0.55, 0.62, 0.72))
	MeTheme.fit_shadow(title)
	column.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.scroll_active = false
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_font_size_override("normal_font_size", _BODY_SIZE)
	_body.add_theme_font_size_override("bold_font_size", _HEADING_SIZE)
	_body.add_theme_color_override("default_color", MeTheme.TEXT_BLUE)
	_body.text = _compose_bbcode()
	_body.meta_clicked.connect(_on_meta_clicked)
	scroll.add_child(_body)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(buttons)
	_back_button = Button.new()
	_back_button.text = BACK_TEXT
	_back_button.custom_minimum_size = Vector2(120.0, 44.0)
	_back_button.add_theme_stylebox_override("normal", MeTheme.button_style(MeTheme.BRAND_RED))
	_back_button.add_theme_stylebox_override("hover", MeTheme.button_style(MeTheme.BRAND_RED.lightened(0.12)))
	_back_button.add_theme_stylebox_override("pressed", MeTheme.button_style(MeTheme.BRAND_RED.darkened(0.12)))
	_back_button.add_theme_stylebox_override("focus", MeTheme.button_style(MeTheme.BRAND_RED.lightened(0.12)))
	_back_button.add_theme_color_override("font_color", Color.WHITE)
	_back_button.add_theme_color_override("font_hover_color", Color.WHITE)
	_back_button.add_theme_color_override("font_pressed_color", Color.WHITE)
	_back_button.add_theme_color_override("font_focus_color", Color.WHITE)
	MeTheme.fit_shadow(_back_button)
	_back_button.pressed.connect(close)
	buttons.add_child(_back_button)

func _compose_bbcode() -> String:
	var out := ""
	for section in SECTIONS:
		out += "[b][color=#%s]%s[/color][/b]\n" % [MeTheme.BRAND_RED.to_html(false), section["heading"]]
		for line: String in section["lines"]:
			if line == SOURCE_URL:
				out += "[url=%s]%s[/url]\n" % [SOURCE_URL, SOURCE_URL]
			else:
				out += line + "\n"
		out += "\n"
	return out.strip_edges()

func _on_meta_clicked(meta: Variant) -> void:
	OS.shell_open(str(meta))

func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventKey and (event as InputEventKey).pressed \
			and not (event as InputEventKey).echo \
			and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
