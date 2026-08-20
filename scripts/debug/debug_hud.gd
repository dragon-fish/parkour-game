class_name DebugHud
extends CanvasLayer

# Tab-toggled readout of everything needed to judge whether a tuning change
# did what was intended.

@export var player: Player

var _label: Label

## Most recent transitions, newest last, as pre-formatted lines. Kept short
## because the point is "what just happened", not a session log -- if a move
## you are hunting has scrolled off, it happened long enough ago that the HUD
## is the wrong tool.
var _transitions: PackedStringArray = PackedStringArray()
var _watching: MoveManager = null
var _clock: float = 0.0

const TRANSITION_LINES := 8

func _ready() -> void:
	_label = Label.new()
	_label.position = Vector2(16.0, 16.0)
	_label.add_theme_color_override("font_color", Color(0.9, 1.0, 0.9))
	_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	_label.add_theme_constant_override("outline_size", 4)
	add_child(_label)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_TAB:
			visible = not visible

## Subscribed lazily rather than in _ready(): move_manager does not exist
## until Player.setup() runs, and the arena builds the HUD alongside the
## player rather than after it.
func _watch(manager: MoveManager) -> void:
	if _watching == manager:
		return
	if _watching != null and _watching.move_changed.is_connected(_on_move_changed):
		_watching.move_changed.disconnect(_on_move_changed)
	_watching = manager
	manager.move_changed.connect(_on_move_changed)

func _on_move_changed(from: StringName, to: StringName) -> void:
	# A restart reports an empty `from` (MoveManager.start()), which would
	# print as a bare arrow.
	var origin: String = String(from) if from != &"" else "(start)"
	_transitions.append("%6.2f  %s -> %s" % [_clock, origin, String(to)])
	while _transitions.size() > TRANSITION_LINES:
		_transitions.remove_at(0)

func _process(delta: float) -> void:
	_clock += delta
	if not visible or player == null or player.move_manager == null:
		return
	_watch(player.move_manager)
	var pos := player.global_position
	_label.text = "\n".join([
		# "move", not "state": this has shown the active MOVE's name since the
		# Move/MoveManager rework -- MoveManager.current_name IS a move name
		# (Walking / Falling / WallRun / Grab / SpeedVault / Slide), and there
		# is no separate state machine left for it to be reporting.
		"move       %s" % player.move_manager.current_name,
		"speed h    %.2f m/s" % player.horizontal_speed(),
		"speed v    %.2f m/s" % player.velocity.y,
		"position   (%.1f, %.1f, %.1f)" % [pos.x, pos.y, pos.z],
		"grounded   %s" % ("yes" if player.grounded else "no"),
		"last land  %.2f m/s" % player.last_landing_speed,
		# The two speed layers, side by side. A cap far below the curve's own
		# ceiling means the turn tax has been eating energy; a speed far below
		# the cap means something else is holding the body back.
		"energy     %.2f  -> cap %.2f m/s" % [player.speed_energy.energy, player.speed_cap()],
		"wall side  %s" % _wall_side_text(),
		"step grace %s" % ("open" if player.in_step_grace() else "-"),
		"fps        %d" % Engine.get_frames_per_second(),
		"",
		"step decisions",
		"
".join(player.step_decisions) if not player.step_decisions.is_empty() 			else "  (none yet)",
		"",
		"transitions",
		"
".join(_transitions) if not _transitions.is_empty() else "  (none yet)",
		"",
		"Tab HUD   F1 tuning   R reset   Esc release mouse",
	])

func _wall_side_text() -> String:
	match player.wall_side:
		-1: return "left"
		1: return "right"
		_: return "none"
