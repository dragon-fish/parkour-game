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
	# THE CLIP TUNER IS BUILT HERE, rather than being wired into main.tscn
	# separately: this layer is already the debug surface and already holds a
	# reference to the player, so it costs no scene change and no second export
	# to keep in step.
	#
	# AS A SIBLING, NOT A CHILD. It is a CanvasLayer of its own, and nesting it
	# under this one would hand it this layer's visibility -- so Tab, which
	# hides the readout, would take the tuner's own display with it. Deferred
	# because a parent is not accepting children while its own _ready() runs.
	var tuner := ClipOffsetTuner.new()
	tuner.name = "ClipOffsetTuner"
	tuner.player = player
	get_parent().add_child.call_deferred(tuner)
	# And the capsule outline, on the same terms and for the same reason: a
	# question about the collision shape cannot be answered by looking at the
	# model, because the two deliberately do not move together.
	var capsule := CapsuleDebug.new()
	capsule.name = "CapsuleDebug"
	capsule.player = player
	get_parent().add_child.call_deferred(capsule)

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
		"speed      h %.2f  v %.2f m/s"
			% [player.horizontal_speed(), player.velocity.y],
		# ABSOLUTE, world-space: the body's own facing and the eye's own pitch,
		# with no constraint arithmetic in between. The `look` line below is
		# all relative to whatever centre a clamp declared, so when the two
		# disagree it is the clamp's own reference that is wrong.
		"at         (%.1f, %.1f, %.1f)  yaw %+.0f  pitch %+.0f" % [pos.x, pos.y, pos.z,
			rad_to_deg(player.rotation.y),
			rad_to_deg(player.camera_rig.rotation.x) if player.camera_rig != null else 0.0],
		"grounded   %s" % ("yes" if player.grounded else "no"),
		# ✅ The owner, from a screenshot: "how much higher than the capsule is
		# the eye?" Answered as numbers rather than by measuring pixels, and
		# both quoted above the SOLES -- which stay put whatever the capsule
		# does, since the fold moves one end of the collision shape, not the
		# body. A span of 0.90-1.80 is a body with its legs tucked; 0.00-0.90
		# is one crouching.
		"eye        %.2f m above soles   (capsule spans %.2f - %.2f)"
			% [_eye_above_soles(), _capsule_span().x, _capsule_span().y],
		# ✅ The owner narrowed it to three paths: a vault that drives through to
		# Walking drops the model, while one that exits into Falling -- and a
		# grab-up -- do not, with the capsule looking right in all three. The
		# drop is DERIVED from the capsule, so it can read zero while the fold
		# is declared, and no amount of looking at the body says which. This
		# line is the difference between the two.
		"fold       %s  drop %.2f m" % ["declared" if player.body_folded() else "off",
			player.body_fold_drop()],
		# WHERE THE MODEL'S ROOT IS, against where the mount alone would put it.
		# The eye line above reports the HEAD BONE, which is this plus the pose
		# -- and a vault's pose can raise the head half a metre by itself. When
		# the two disagree it is the pose, and no amount of moving the root
		# fixes a pose.
		"model      y %+.2f  (mount %+.2f  fold %.2f  lift %.2f  clip %+.2f)"
			% [player.body_root_debug()["y"], player.body_root_debug()["mount_y"],
			player.body_root_debug()["drop"], player.body_root_debug()["lift"],
			player.body_root_debug()["clip_y"]],
		"capsule    %.2f / %.2f m%s" % [player.current_capsule_height(),
			player.standing_height(),
			"  FOLDED" if player.current_capsule_height() < player.standing_height() - 0.01 else ""],
		"last land  %.2f m/s" % player.last_landing_speed,
		# The two speed layers, side by side. A cap far below the curve's own
		# ceiling means the turn tax has been eating energy; a speed far below
		# the cap means something else is holding the body back.
		"energy     %.2f  -> cap %.2f m/s" % [player.speed_energy.energy, player.speed_cap()],
		"wall side  %s" % _wall_side_text(),
		"wall ahead %s" % _wall_ahead_text(),
		"look       %s" % _look_text(),
		"step grace %s" % ("open" if player.in_step_grace() else "-"),
		# Only while hanging, where it is the only thing that can explain a
		# shimmy that will not go: four different refusals, one identical
		# nothing happening.
		"shimmy     %s" % _shimmy_text(),
		"fps        %d" % Engine.get_frames_per_second(),
		# ⚠️ COMMENTED OUT, not deleted. ✅ The owner: "the step decisions can
		# go for now, that part is basically stable." It is the readout that
		# settled how a body climbs a plank, and the day it is wrong again it
		# is two lines away rather than a rewrite.
		#"step decisions",
		#"\n".join(player.step_decisions) if not player.step_decisions.is_empty()
		#	else "  (none yet)",
		"transitions",
		"
".join(_transitions) if not _transitions.is_empty() else "  (none yet)",
		"",
		"Tab HUD  F9 clip tuner  F10 capsule  R reset  K die  T noclip%s" 			% ("  [ON]" if player.noclip else ""),
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
	var heading: Vector3 = player.approach_direction()
	if heading == Vector3.ZERO:
		return "-"
	var hit: Dictionary = player.probes.wall_ahead_query(heading)
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
	# The RATE, not the height: the height is a constant, and what a run-up
	# actually buys is getting there faster.
	var rate: float = WallClimbMove.rise_speed(player.horizontal_speed(), cfg, player.config.pawn)
	return "%-11s %4.1f deg of %.0f   +%.2f m at %.1f m/s" % [verdict, angle, allowed,
		cfg.climb_height, rate]

## Yaw relative to the constraint's own centre, and the pitch floor in force --
## the two numbers that say whether a clamp is doing what it was asked to.
func _look_text() -> String:
	if player.camera_rig == null:
		return "-"
	var d: Dictionary = player.camera_rig.look_debug()
	if not d["constrained"]:
		return "free  pitch %+.0f" % rad_to_deg(d["pitch"])
	return "yaw %+.0f  floor %+.0f  pitch %+.0f" % [rad_to_deg(d["relative_yaw"]), 		rad_to_deg(d["pitch_floor"]), rad_to_deg(d["pitch"])]

## The first-person eye, measured from the soles. The rig's own origin IS that
## eye -- the Camera3D child is what pulls back for third person -- so this
## reads the same in both views.
func _eye_above_soles() -> float:
	var soles: float = player.global_position.y - player.standing_height() * 0.5
	if player.camera_rig != null:
		return player.camera_rig.global_position.y - soles
	return player.config.camera.eye_height + player.standing_height() * 0.5

## Where the collision capsule starts and ends, from the soles. Which END moves
## is the whole of what the fold's anchor decides: ANCHOR_FEET brings the top
## down, ANCHOR_HEAD lifts the bottom -- so a span of 0.90 to 1.80 is a body
## with its legs tucked, and 0.00 to 0.90 is one crouching.
func _capsule_span() -> Vector2:
	var shape_node := player.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node == null:
		return Vector2.ZERO
	var capsule := shape_node.shape as CapsuleShape3D
	if capsule == null:
		return Vector2.ZERO
	var soles: float = player.global_position.y - player.standing_height() * 0.5
	var centre: float = shape_node.global_position.y - soles
	return Vector2(centre - capsule.height * 0.5, centre + capsule.height * 0.5)

func _wall_side_text() -> String:
	match player.wall_side:
		-1: return "left"
		1: return "right"
		_: return "none"

## What the shimmy last decided, or "-" when nothing is hanging.
func _shimmy_text() -> String:
	if player == null or player.move_manager == null:
		return "-"
	if player.move_manager.current_name != Move.GRAB:
		return "-"
	var grab = player.move_manager.move_for(Move.GRAB)
	if grab == null or not grab.has_method("shimmy_report"):
		return "-"
	return grab.shimmy_report()
