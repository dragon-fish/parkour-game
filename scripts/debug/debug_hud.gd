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

const TRANSITION_LINES := 6

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
		# ABSOLUTE, world-space: the body's own facing and the eye's own pitch,
		# with no constraint arithmetic in between. The `look` line below is
		# all relative to whatever centre a clamp declared, so when the two
		# disagree it is the clamp's own reference that is wrong.
		"facing     yaw %+.0f  pitch %+.0f" % [rad_to_deg(player.rotation.y), 			rad_to_deg(player.camera_rig.rotation.x) if player.camera_rig != null else 0.0],
		"grounded   %s" % ("yes" if player.grounded else "no"),
		"last land  %.2f m/s" % player.last_landing_speed,
		# The two speed layers, side by side. A cap far below the curve's own
		# ceiling means the turn tax has been eating energy; a speed far below
		# the cap means something else is holding the body back.
		"energy     %.2f  -> cap %.2f m/s" % [player.speed_energy.energy, player.speed_cap()],
		"wall side  %s" % _wall_side_text(),
		"wall ahead %s" % _wall_ahead_text(),
		"look       %s" % _look_text(),
		"step grace %s" % ("open" if player.in_step_grace() else "-"),
		"fps        %d" % Engine.get_frames_per_second(),
		"step decisions",
		"
".join(player.step_decisions) if not player.step_decisions.is_empty() 			else "  (none yet)",
		"transitions",
		"
".join(_transitions) if not _transitions.is_empty() else "  (none yet)",
		"",
		"Tab HUD  F1 tuning  R reset  K die  T noclip%s" 			% ("  [ON]" if player.noclip else ""),
		"Esc release mouse  click to return" 			+ ("   noclip: WASD fly  Space up  Shift down" if player.noclip else ""),
	])

## What the forward wall probe sees, in the same words the markers use colour
## for: whether there is a wall, whether it is tall enough to kick up, how
## square the approach is against the 33 degree threshold, and what the current
## run-up would buy in height. The markers answer "where"; this answers "by how
## much", which is the half you cannot read off a coloured ball.
func _wall_ahead_text() -> String:
	if player.probes == null:
		return "-"
	var heading := Vector3(player.velocity.x, 0.0, player.velocity.z)
	if heading.length_squared() < 0.0001:
		heading = -player.global_transform.basis.z
		heading.y = 0.0
	var hit: Dictionary = player.probes.wall_ahead_query(heading.normalized())
	if not hit.get("valid", false):
		return "-"
	var cfg: WallClimbConfig = player.config.wall_climb
	var verdict := "climb"
	if not bool(hit["tall_enough"]):
		verdict = "too short"
	elif float(hit["incidence"]) > cfg.vertical_start_angle:
		verdict = "too oblique"
	var angle: float = rad_to_deg(float(hit["incidence"]))
	var allowed: float = rad_to_deg(cfg.vertical_start_angle)
	var worth: float = WallClimbMove.climb_height(player.horizontal_speed(), player.velocity.y, cfg)
	return "%-11s %4.1f deg of %.0f   +%.2f m" % [verdict, angle, allowed, worth]

## Yaw relative to the constraint's own centre, and the pitch floor in force --
## the two numbers that say whether a clamp is doing what it was asked to.
func _look_text() -> String:
	if player.camera_rig == null:
		return "-"
	var d: Dictionary = player.camera_rig.look_debug()
	if not d["constrained"]:
		return "free  pitch %+.0f" % rad_to_deg(d["pitch"])
	return "yaw %+.0f  floor %+.0f  pitch %+.0f" % [rad_to_deg(d["relative_yaw"]), 		rad_to_deg(d["pitch_floor"]), rad_to_deg(d["pitch"])]

func _wall_side_text() -> String:
	match player.wall_side:
		-1: return "left"
		1: return "right"
		_: return "none"
