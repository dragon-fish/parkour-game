class_name Toast
extends CanvasLayer

# The corner report: something HAPPENED -- a checkpoint saved, an objective
# met. THIS IS NOT A SUBTITLE. Subtitle (bottom centre) is the game TALKING to
# the player; anything that reads as a status line belongs here instead, and
# the split is the whole reason both exist.
#
# Lives on the PLAYER next to Crosshair and ScreenEffects, for the same reason
# those do: it reports what happened to this player, and must survive a level
# change.
#
# FIXED WIDTH AND HEIGHT, DELIBERATELY. A container that sizes itself to its
# text only knows its size after a layout pass, but every slot position here
# is needed the instant a line arrives -- and one frame of wrong geometry is a
# toast visibly sliding in from the wrong place. Long lines elide. A line that
# needs two rows is a subtitle, not a toast.

const MAX_STANDING := 3

## Project-defined feel values. FADE_IN/HOLD match Subtitle so the two layers
## agree on what a beat is; per-line hold is overridable, the fades are not.
const FADE_IN := 0.15
const HOLD := 2.0
const FADE_OUT := 0.5

const WIDTH := 340.0
const HEIGHT := 44.0
## Inset from the top-right corner.
const MARGIN := 24.0
## Between stacked toasts.
const GAP := 8.0
## How far past the right edge a toast begins and ends its travel.
const SLIDE := 48.0

## One entry per standing toast, oldest first. Named fields rather than a
## positional array because this grows: see naming-config-fields.
##   panel  PanelContainer, the red block
##   label  its Label, kept for texts()
##   age    seconds since it arrived, counted on delta
##   hold   how long THIS line stays lit, past the fade-in
##   tween  its current move/fade, killed before a new one starts
var _standing: Array[Dictionary] = []

func _ready() -> void:
	layer = 1
	get_viewport().size_changed.connect(_relayout)

func _process(delta: float) -> void:
	if _standing.is_empty():
		return
	var expired: Array[Dictionary] = []
	for entry in _standing:
		entry.age += delta
		if entry.age >= FADE_IN + entry.hold:
			expired.append(entry)
	if expired.is_empty():
		return
	for entry in expired:
		_standing.erase(entry)
		_dismiss(entry)
	_relayout()

## Puts one line in the corner. A fourth arrival evicts the oldest rather than
## queueing behind it -- a report nobody can see yet is a report that has
## already lost its moment.
func show_text(text: String, hold: float = HOLD) -> void:
	while _standing.size() >= MAX_STANDING:
		var oldest: Dictionary = _standing.pop_front()
		_dismiss(oldest)

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(WIDTH, HEIGHT)
	panel.size = Vector2(WIDTH, HEIGHT)
	panel.add_theme_stylebox_override("panel", _block())

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	panel.add_child(margin)

	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	# NOT MeTheme.dress_over_anything(): that spec is white-on-black-outline
	# for text with no background it can count on. This text has a solid red
	# block behind it, and an outline over a flat fill only muddies the glyphs.
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_font_size_override("font_size", 18)
	margin.add_child(label)

	var entry: Dictionary = {
		panel = panel,
		label = label,
		age = 0.0,
		hold = hold,
		tween = null,
	}
	_standing.append(entry)
	add_child(panel)

	panel.position = Vector2(_rest_x() + SLIDE, _slot_y(_standing.size() - 1))
	panel.modulate.a = 0.0
	_move(entry, panel.position.y, FADE_IN, 1.0, _rest_x())
	_relayout()

## How many toasts are standing. One that has begun sliding out is already
## gone by this count -- its moment is over even though its pixels linger.
func count() -> int:
	return _standing.size()

func texts() -> PackedStringArray:
	var out := PackedStringArray()
	for entry in _standing:
		out.append(entry.label.text)
	return out

## The y each standing toast is headed for, oldest first. Reported as targets
## rather than live positions so a caller reads the layout, not a frame of
## animation.
func slot_ys() -> Array[float]:
	var out: Array[float] = []
	for i in _standing.size():
		out.append(_slot_y(i))
	return out

func _block() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = MeTheme.BRAND_RED
	style.content_margin_top = 0.0
	style.content_margin_bottom = 0.0
	return style

func _rest_x() -> float:
	return get_viewport().get_visible_rect().size.x - WIDTH - MARGIN

func _slot_y(index: int) -> float:
	return MARGIN + float(index) * (HEIGHT + GAP)

## Slides everyone to the slot their index now names. Called on arrival, on
## expiry and on a window resize -- the three ways a slot can change owner.
func _relayout() -> void:
	for i in _standing.size():
		var entry: Dictionary = _standing[i]
		_move(entry, _slot_y(i), FADE_IN, 1.0, _rest_x())

## Out through the right edge, fading. The entry is already off _standing by
## the time this runs; the tween owns the node until it frees it.
func _dismiss(entry: Dictionary) -> void:
	var panel: PanelContainer = entry.panel
	if entry.tween != null:
		entry.tween.kill()
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(panel, "position:x", _rest_x() + SLIDE, FADE_OUT)
	tween.tween_property(panel, "modulate:a", 0.0, FADE_OUT)
	tween.chain().tween_callback(panel.queue_free)

func _move(entry: Dictionary, to_y: float, duration: float, alpha: float, to_x: float) -> void:
	var panel: PanelContainer = entry.panel
	if entry.tween != null:
		entry.tween.kill()
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(panel, "position", Vector2(to_x, to_y), duration)
	tween.tween_property(panel, "modulate:a", alpha, duration)
	entry.tween = tween
