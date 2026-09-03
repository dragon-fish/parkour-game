class_name MeOpeningPlate
extends Control

# The beat this game opens on, wherever it opens: the white mark held over a
# crouched red figure, and 「点击任意处开始」 breathing along the bottom until
# something is pressed.
#
# ONE COPY, TWO HOSTS, AND THAT IS THE POINT. The main menu opens on it and so
# does the tutorial's first shot. A player who has never finished the tutorial
# and one who has must see the SAME screen up to the press -- the fractions,
# the wording, the hold and the breath all identical. Two hand-tuned copies of
# one beat drift apart, and this one already did: a logo that appeared for a
# frame and vanished. DO NOT re-derive any of these values in another file.
#
# IT DRAWS THE MARK AND THE PROMPT AND NOTHING ELSE. What is behind them is the
# host's: the menu paints its own near-white ground, the tutorial shows the
# void the figure is standing in.
#
# It never takes input. Which press ends the beat is the host's question --
# the menu has an entrance to play and the tutorial has a body to stand up --
# so this only reports, through prompt_shown, whether the invitation is on
# screen yet.

## The mark itself. A const rather than an export because it is artwork, not a
## dial, and BootRouter reads it by name.
const LOGO_TEXTURE := "res://assets/ui/logo_mark_white.svg"

## Centre of the mark, as screen fractions, and how big it is drawn.
@export var logo_x_frac: float = 0.19
@export var logo_y_frac: float = 0.55
@export var logo_size_px: float = 220.0

## How long the mark is held alone before the invitation joins it.
@export var hold: float = 0.5
## How long the mark takes to leave once the press has landed.
@export var logo_fade_time: float = 0.4
## And the prompt, which goes faster: it is answering the press, not covering
## a move.
@export var prompt_fade_time: float = 0.2

## The invitation: where it sits, what it says, and half of one breath.
@export var prompt_y_frac: float = 0.86
@export var prompt_text: String = "点击任意处开始"
@export var prompt_font_size: int = 22
@export var prompt_breath: float = 1.1
## How far down the breath goes. Never to nothing -- a prompt that blinks out
## reads as a fault, one that dims reads as waiting.
@export var prompt_dim: float = 0.55

var logo: TextureRect
var prompt: Label

## True from the frame the invitation is on screen until the press is taken.
## The host gates its own input on this, so a press during the opening hold is
## ignored the same way on every screen.
var prompt_shown: bool = false

var _tweens: Array[Tween] = []

# Built in _ready(), which means already parented: see
# .claude/skills/godot-ui-layout-traps for why every preset call in here is
# set_anchors_and_offsets_preset and never set_anchors_preset.
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# A full-rect Control defaults to MOUSE_FILTER_STOP and would eat every
	# click before the host's _unhandled_input could see it -- which reads as
	# a game that only answers the keyboard.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = MeTheme.ui_theme()
	_build_logo()
	_build_prompt()

func _build_logo() -> void:
	logo = TextureRect.new()
	logo.name = "LogoMark"
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(LOGO_TEXTURE):
		logo.texture = load(LOGO_TEXTURE)
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.anchor_left = logo_x_frac
	logo.anchor_right = logo_x_frac
	logo.anchor_top = logo_y_frac
	logo.anchor_bottom = logo_y_frac
	logo.offset_left = -logo_size_px * 0.5
	logo.offset_right = logo_size_px * 0.5
	logo.offset_top = -logo_size_px * 0.5
	logo.offset_bottom = logo_size_px * 0.5
	add_child(logo)

func _build_prompt() -> void:
	prompt = Label.new()
	prompt.name = "ClickPrompt"
	prompt.text = prompt_text
	prompt.add_theme_font_size_override("font_size", prompt_font_size)
	# The over-anything spec, shared with this game's subtitles: see
	# MeTheme.dress_over_anything for why an outline and not a shadow.
	prompt.theme = MeTheme.ui_theme()
	MeTheme.dress_over_anything(prompt)
	prompt.anchor_left = 0.5
	prompt.anchor_right = 0.5
	prompt.anchor_top = prompt_y_frac
	prompt.anchor_bottom = prompt_y_frac
	prompt.position = Vector2(-100.0, 0.0)
	prompt.size = Vector2(200.0, 30.0)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.visible = false
	add_child(prompt)

## Starts the beat: the mark alone, then the invitation breathing under it.
func open() -> void:
	var pacing := _track(create_tween())
	pacing.tween_interval(hold)
	pacing.tween_callback(_show_prompt)

func _show_prompt() -> void:
	prompt_shown = true
	prompt.visible = true
	prompt.modulate.a = 0.0
	var breath := _track(create_tween())
	breath.set_loops()
	breath.tween_property(prompt, "modulate:a", 1.0, prompt_breath) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	breath.tween_property(prompt, "modulate:a", prompt_dim, prompt_breath) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

## The press landed: the invitation goes at once, the mark over the move that
## follows it.
func dismiss() -> void:
	prompt_shown = false
	_kill()
	var out := _track(create_tween())
	out.tween_property(prompt, "modulate:a", 0.0, prompt_fade_time)
	var mark := _track(create_tween())
	mark.tween_property(logo, "modulate:a", 0.0, logo_fade_time) \
		.set_ease(Tween.EASE_IN)

## Jumps to the finished state with nothing left running -- what a host calls
## when the player is in a hurry and skips the whole show.
func settle() -> void:
	_kill()
	prompt_shown = false
	if prompt != null:
		prompt.visible = false
	if logo != null:
		logo.modulate.a = 0.0

func _track(tween: Tween) -> Tween:
	_tweens.append(tween)
	return tween

func _kill() -> void:
	for tween in _tweens:
		if tween != null and tween.is_valid():
			tween.kill()
	_tweens.clear()
