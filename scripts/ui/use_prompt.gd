class_name UsePrompt
extends Control

## The ring beside the crosshair that fills while the player stands in a
## UseZone. One per game, found or made by shared(); UseZones only report
## progress to it.
##
## Filling: white. Done: green, two blinks, a short hold, then a slow fade.
## Abandoned before done: a quick fade.

const RADIUS := 14.0
const WIDTH := 3.0
## Right of the crosshair, so it never sits on what the player aims at.
const OFFSET := Vector2(38.0, 0.0)
const DONE_COLOR := Color(0.35, 1.0, 0.45)
const BLINK_TIME := 0.12
const HOLD_TIME := 0.35
const FADE_TIME := 0.8
const ABANDON_FADE_TIME := 0.2

var progress: float = 0.0:
	set(value):
		progress = clampf(value, 0.0, 1.0)
		queue_redraw()
var ring_color := Color.WHITE:
	set(value):
		ring_color = value
		queue_redraw()
var _tween: Tween = null


static func shared(tree: SceneTree) -> UsePrompt:
	var existing := tree.root.get_node_or_null("UsePromptLayer")
	if existing != null:
		return existing.get_node("UsePrompt") as UsePrompt
	var layer := CanvasLayer.new()
	layer.name = "UsePromptLayer"
	layer.layer = 50
	tree.root.add_child(layer)
	var prompt := UsePrompt.new()
	prompt.name = "UsePrompt"
	layer.add_child(prompt)
	# AFTER add_child and with offsets: a bare set_anchors_preset() on a
	# parented Control leaves it 0x0 in the corner.
	prompt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt.modulate.a = 0.0
	return prompt


## Called every frame the player stands in a zone.
func fill(amount: float) -> void:
	_stop_tween()
	ring_color = Color.WHITE
	modulate.a = 1.0
	progress = amount


func complete() -> void:
	_stop_tween()
	progress = 1.0
	ring_color = DONE_COLOR
	modulate.a = 1.0
	_tween = create_tween()
	for i in 2:
		_tween.tween_property(self, "modulate:a", 0.15, BLINK_TIME)
		_tween.tween_property(self, "modulate:a", 1.0, BLINK_TIME)
	_tween.tween_interval(HOLD_TIME)
	_tween.tween_property(self, "modulate:a", 0.0, FADE_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func abandon() -> void:
	if ring_color == DONE_COLOR:
		return
	_stop_tween()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 0.0, ABANDON_FADE_TIME)


func _stop_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


func _draw() -> void:
	var centre := size * 0.5 + OFFSET
	draw_arc(centre, RADIUS, 0.0, TAU, 48, Color(1.0, 1.0, 1.0, 0.2), WIDTH, true)
	if progress > 0.0:
		draw_arc(centre, RADIUS, -PI * 0.5, -PI * 0.5 + TAU * progress, 48, ring_color, WIDTH, true)
