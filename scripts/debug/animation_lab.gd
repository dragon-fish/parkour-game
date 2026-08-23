class_name AnimationLab
extends Node3D

# A bench for hand-keying a clip against the path its move actually takes.
#
# ✅ THE OWNER: "你就做一个新场景，可以选择各种高度的墙，让角色以完美姿态触发各种
# VaultOver、Grab、GrabPullUp，我一个个手K，我每调一次你就自动保存一个 JSON."
#
# 🎯 THE PROBLEM IT SOLVES is that a clip and a scripted path are authored against
# nothing in particular and then asked to agree. A generic curve cannot follow an
# animation and an animation cannot follow a generic curve, so one of them has to
# be keyed against the other while both are visible -- and neither the Godot
# animation editor nor the game shows both.
#
# ⚠️ WHAT IS KEYED IS AN OFFSET, NOT THE CLIP. The packs are licensed and not in
# the repository, so nothing here writes to them. Player.body_clip_curves holds a
# per-clip offset that varies over the move's own normalised time, this bench
# authors it, and the JSON is where it lives.
#
# The moves are triggered the way the TESTS trigger them -- placed and started
# directly rather than run at -- because a bench that needs a good run-up is a
# bench that gives a different answer every time.

const NEWLINE := "\n"

const SAVE_PATH := "user://clip_curves.json"

## Wall tops, in metres. Spread across the bands the moves care about: under a
## step-up, through the hand-plant vaults, up to the tallest a grab can reach.
const WALL_HEIGHTS: Array[float] = [0.5, 0.9, 1.2, 1.5, 1.8, 2.2, 2.7]

## How far in front of a wall a vault is started from, and how fast.
const VAULT_STANDOFF := 1.2
## Upward speed on entry. See _start_vault().
const VAULT_RISE := 1.0
## Entry speed for a vault, adjustable because WHICH VARIANT MATCHES depends on
## it -- the table gates on momentum as well as height, so the same wall is a
## different move at a different pace. See SpeedVaultConfig.pick_variant().
const VAULT_SPEEDS: Array[float] = [1.5, 2.5, 3.5, 4.5, 5.5, 6.5, 7.2]

## The time-scale ladder. 0 is a full freeze, which is where keying happens.
const SPEEDS: Array[float] = [0.0, 0.02, 0.05, 0.1, 0.25, 0.5, 1.0]

const NUDGE := 0.01
const NUDGE_FAST := 0.05
const NUDGE_FINE := 0.002

const POSITION_KEYS := {
	KEY_I: Vector3(0.0, 0.0, -1.0),
	KEY_K: Vector3(0.0, 0.0, 1.0),
	KEY_J: Vector3(-1.0, 0.0, 0.0),
	KEY_L: Vector3(1.0, 0.0, 0.0),
	KEY_U: Vector3(0.0, -1.0, 0.0),
	KEY_O: Vector3(0.0, 1.0, 0.0),
}

@export var player: Player

var _walls: Array[StaticBody3D] = []
var _selected := 4
var _speed := SPEEDS.size() - 1
var _vault_speed := 4
var _label: Label
var _note := ""
## The offset being edited, before it is committed as a key.
var _live_position := Vector3.ZERO
var _live_rotation := Vector3.ZERO

func _ready() -> void:
	_build_walls()
	_build_label()
	_load()
	_note = "loaded %d clips from %s" % [
		player.body_clip_curves.size() if player != null else 0,
		ProjectSettings.globalize_path(SAVE_PATH)]

func _exit_tree() -> void:
	# Never leave the game frozen because a bench was closed mid-key.
	Engine.time_scale = 1.0

# --- the bench ------------------------------------------------------------------

func _build_walls() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.55, 0.5, 0.62)
	for i in WALL_HEIGHTS.size():
		var height: float = WALL_HEIGHTS[i]
		var body := StaticBody3D.new()
		body.name = "Wall_%02d" % int(height * 100.0)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		# DEEP ENOUGH TO STAND ON, so a pull-up has somewhere to arrive and a
		# vault-over has to be asked for rather than being the only option.
		box.size = Vector3(4.0, height, 3.0)
		shape.shape = box
		body.add_child(shape)
		var mesh := MeshInstance3D.new()
		var cube := BoxMesh.new()
		cube.size = box.size
		cube.material = material
		mesh.mesh = cube
		body.add_child(mesh)
		add_child(body)
		# Spaced well apart so a body placed at one cannot touch its neighbour,
		# and CENTRED, so the row fits the template floor's 60 m square.
		var span: float = float(WALL_HEIGHTS.size() - 1) * 0.5
		body.position = Vector3((float(i) - span) * 9.0, height * 0.5, 0.0)
		_walls.append(body)

func _build_label() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(16.0, 16.0)
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_label.add_theme_constant_override("outline_size", 4)
	layer.add_child(_label)

func _wall_top(index: int) -> Vector3:
	var wall: StaticBody3D = _walls[index]
	return Vector3(wall.position.x, WALL_HEIGHTS[index], wall.position.z - 1.5)

# --- triggering -------------------------------------------------------------------

## Hangs the body on the selected wall, exactly as the tests do: placed by
## IntoGrabMove.hanging_pose() and started directly. A bench that needed a run-up
## would answer differently every time it was asked.
func _start_grab() -> void:
	if player == null:
		return
	var top: Vector3 = _wall_top(_selected)
	var edge := top + Vector3(0.0, 0.0, -0.1)
	var query := {"valid": true, "edge": edge, "top": edge,
		"normal": Vector3.UP, "face_normal": Vector3(0.0, 0.0, 1.0)}
	player.velocity = Vector3.ZERO
	player.rotation.y = 0.0
	player.global_position = IntoGrabMove.hanging_pose(player, player.config, query)
	player.pending_ledge = query
	player.move_manager.start(Move.WALKING)
	player.move_manager.start(Move.GRAB)
	_note = "Grab on a %.2f m wall" % WALL_HEIGHTS[_selected]

func _start_pull_up() -> void:
	if player == null:
		return
	_start_grab()
	var grab := player.move_manager.move_for(Move.GRAB)
	if grab == null:
		return
	var forward := MoveInput.new()
	forward.move = Vector2(0.0, 1.0)
	grab.physics_update(0.0001, forward)
	_note = "GrabPullUp on a %.2f m wall" % WALL_HEIGHTS[_selected]

func _start_vault() -> void:
	if player == null:
		return
	var height: float = WALL_HEIGHTS[_selected]
	var top: Vector3 = _wall_top(_selected)
	player.rotation.y = 0.0
	player.global_position = Vector3(top.x,
		player.current_capsule_height() * 0.5, top.z + VAULT_STANDOFF)
	var speed: float = VAULT_SPEEDS[_vault_speed]
	# ⚠️ RISING, and the high rows will not match otherwise. vault_over_high and
	# vault_onto_high both gate on min_speed_z = 0.5 -- they are what you get
	# when you JUMP at something chest-high, not when you walk into it -- so a
	# bench that always entered level could never trigger them at all.
	player.velocity = Vector3(0.0, VAULT_RISE, -speed)
	var variant: Dictionary = player.config.speed_vault.pick_variant(
		height, true, VAULT_RISE, speed)
	if variant.is_empty():
		# LEFT STANDING, not left hanging: a refused trigger must not strand the
		# body in whatever the last move happened to be.
		player.move_manager.start(Move.WALKING)
		_note = "no variant matches %.2f m at %.1f m/s -- try - / = for speed" % [
			height, speed]
		return
	player.pending_vault_variant = variant
	player.pending_vault_rescue = false
	player.move_manager.start(Move.WALKING)
	player.move_manager.start(Move.SPEED_VAULT)
	_note = "%s on %.2f m at %.1f m/s" % [variant.get("name", "?"), height, speed]

# --- keying -----------------------------------------------------------------------

func _clip() -> StringName:
	if player == null:
		return Move.KEEP
	var animator := player.get_node_or_null("BodyRoot/CharacterAnimator") as CharacterAnimator
	return animator.current_clip if animator != null else Move.KEEP

func _nudge(delta_position: Vector3, delta_rotation: Vector3) -> void:
	var step := NUDGE
	if Input.is_key_pressed(KEY_SHIFT):
		step = NUDGE_FAST
	elif Input.is_key_pressed(KEY_CTRL):
		step = NUDGE_FINE
	_live_position += delta_position * step
	_live_rotation += delta_rotation * (step * 100.0)
	_commit()

## Writes the live offset in as a key at the current time, and saves.
##
## ⚠️ EVERY NUDGE IS A KEY, at the owner's request -- "我每调一次你就自动保存一个
## JSON". There is no separate commit step to forget, and no way to lose a
## session's work to a crash or a stray Escape.
func _commit() -> void:
	var clip: StringName = _clip()
	var at: float = player.scripted_progress()
	if clip == Move.KEEP or at < 0.0:
		_note = "nothing scripted is running -- start a move first"
		return
	var keys: Array = player.body_clip_curves.get(clip, [])
	var replaced := false
	for key in keys:
		if absf(float(key.get("t", -1.0)) - at) < 0.01:
			key["pos"] = _live_position
			key["rot"] = _live_rotation
			replaced = true
			break
	if not replaced:
		keys.append({"t": at, "pos": _live_position, "rot": _live_rotation})
		keys.sort_custom(func(a, b): return float(a["t"]) < float(b["t"]))
	player.body_clip_curves[clip] = keys
	_save()
	_note = "%s: %d keys (t=%.2f)" % [clip, keys.size(), at]

func _drop_key() -> void:
	var clip: StringName = _clip()
	var at: float = player.scripted_progress()
	if clip == Move.KEEP or not player.body_clip_curves.has(clip):
		return
	var keys: Array = player.body_clip_curves[clip]
	for i in keys.size():
		if absf(float(keys[i].get("t", -1.0)) - at) < 0.05:
			keys.remove_at(i)
			_save()
			_note = "%s: dropped a key, %d left" % [clip, keys.size()]
			return

# --- the file ---------------------------------------------------------------------

func _save() -> void:
	var out := {}
	for clip in player.body_clip_curves:
		var rows: Array = []
		for key in player.body_clip_curves[clip]:
			var pos: Vector3 = key.get("pos", Vector3.ZERO)
			var rot: Vector3 = key.get("rot", Vector3.ZERO)
			rows.append({"t": float(key.get("t", 0.0)),
				"pos": [pos.x, pos.y, pos.z], "rot": [rot.x, rot.y, rot.z]})
		out[String(clip)] = rows
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		_note = "could not write %s" % SAVE_PATH
		return
	file.store_string(JSON.stringify(out, "  "))
	file.close()

func _load() -> void:
	if player == null or not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return
	var loaded := {}
	for clip in parsed:
		var rows: Array = []
		for row in parsed[clip]:
			rows.append({"t": float(row.get("t", 0.0)),
				"pos": _to_vector(row.get("pos", [])),
				"rot": _to_vector(row.get("rot", []))})
		loaded[StringName(clip)] = rows
	player.body_clip_curves = loaded

func _to_vector(from) -> Vector3:
	if from is Array and from.size() >= 3:
		return Vector3(float(from[0]), float(from[1]), float(from[2]))
	return Vector3.ZERO

# --- input ------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := (event as InputEventKey).physical_keycode
	if key >= KEY_1 and key < KEY_1 + WALL_HEIGHTS.size():
		_selected = key - KEY_1
		_note = "wall %.2f m" % WALL_HEIGHTS[_selected]
		return
	match key:
		KEY_Z:
			_start_vault()
		KEY_X:
			_start_grab()
		KEY_C:
			_start_pull_up()
		KEY_MINUS:
			_vault_speed = maxi(_vault_speed - 1, 0)
			_note = "vault entry speed %.1f m/s" % VAULT_SPEEDS[_vault_speed]
		KEY_EQUAL:
			_vault_speed = mini(_vault_speed + 1, VAULT_SPEEDS.size() - 1)
			_note = "vault entry speed %.1f m/s" % VAULT_SPEEDS[_vault_speed]
		KEY_BRACKETLEFT:
			_speed = maxi(_speed - 1, 0)
			Engine.time_scale = SPEEDS[_speed]
		KEY_BRACKETRIGHT:
			_speed = mini(_speed + 1, SPEEDS.size() - 1)
			Engine.time_scale = SPEEDS[_speed]
		KEY_ENTER, KEY_KP_ENTER:
			_commit()
		KEY_BACKSPACE:
			_drop_key()
		KEY_DELETE:
			_live_position = Vector3.ZERO
			_live_rotation = Vector3.ZERO
			_commit()
		_:
			if POSITION_KEYS.has(key):
				_nudge(POSITION_KEYS[key], Vector3.ZERO)
			elif key == KEY_SEMICOLON:
				_nudge(Vector3.ZERO, Vector3(0.0, -1.0, 0.0))
			elif key == KEY_APOSTROPHE:
				_nudge(Vector3.ZERO, Vector3(0.0, 1.0, 0.0))

func _process(_delta: float) -> void:
	if _label == null or player == null:
		return
	var at: float = player.scripted_progress()
	var clip: StringName = _clip()
	_label.text = NEWLINE.join([
		"ANIMATION LAB   %s" % ProjectSettings.globalize_path(SAVE_PATH),
		"",
		"wall     %s" % _wall_row(),
		"clip     %s" % (String(clip) if clip != Move.KEEP else "-"),
		"time     %s" % ("%.3f" % at if at >= 0.0 else "- (no scripted move)"),
		"keys     %d" % _key_count(clip),
		"offset   (%+.3f, %+.3f, %+.3f)  yaw %+.1f" % [
			_live_position.x, _live_position.y, _live_position.z, _live_rotation.y],
		"speed    x%.2f      vault entry %.1f m/s" % [Engine.time_scale, VAULT_SPEEDS[_vault_speed]],
		"",
		"1-%d wall   Z vault   X grab   C pull-up" % WALL_HEIGHTS.size(),
		"[ ] time (0 = freeze)   - = vault speed   IJKL/UO nudge   ;' yaw",
		"Shift coarse   Ctrl fine   Enter key   Backspace drop   Del zero",
		"",
		_note,
	])


func _wall_row() -> String:
	var parts: Array[String] = []
	for i in WALL_HEIGHTS.size():
		var mark := ">%0.2f<" % WALL_HEIGHTS[i] if i == _selected else " %0.2f " % WALL_HEIGHTS[i]
		parts.append(mark)
	return "".join(parts)

func _key_count(clip: StringName) -> int:
	if clip == Move.KEEP or not player.body_clip_curves.has(clip):
		return 0
	return (player.body_clip_curves[clip] as Array).size()
