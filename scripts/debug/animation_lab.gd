class_name AnimationLab
extends Node3D

# A dedicated editor for lining a clip up with the path its move takes.
#
# ✅ THE OWNER: "这个场景不是让我 wasd 在里面游玩的，它就是一个专属我们的动画编辑器...
# 里面有一个玩家角色，总是以程序生成的方式执行一段操作，我们直接把 0s-8s 的运动预处理
# 好，然后我可以随便拖动进度条或者用 AD 去往某一刻."
#
# 🎯 SO IT IS NOT A LEVEL. Nothing here is played: the body runs one scripted
# approach at one obstacle, the whole take is RECORDED, and afterwards A and D
# walk the recording. Keying a pose means seeing the same frame twice, and live
# play cannot give you that.
#
# ⚠️ THE RECORDING IS TRANSFORMS PLUS A CLIP TIME, not a pose. A pose is a pure
# function of (clip, time), so storing those two replays it exactly for a few
# hundred bytes -- and it makes scrubbing BACKWARDS free, which re-simulating
# never is.
#
# THE APPROACH IS UNIFORM ON PURPOSE. ✅ "假设这个玩家总是匀速并按住 W，然后就此模拟
# 运动轨迹." The velocity is written every frame rather than accelerated into, so
# a key made on one take describes a frame that still exists on the next. An
# approach that has to be driven is an approach that differs every time.
#
# THE GRID is the other half. ✅ "我可以任选障碍物高度...每刻度 0.25m，宽度也是从
# 0.1m-2m. 我保存的数据会对应每一种组合，实际游戏场景中总是寻找最接近的那一组偏移量去
# 应用." One curve per clip is not enough: the same animation plays against a sill
# and a parapet, a rail and a ledge, and it is wrong differently each time.

const NEWLINE := "\n"
const SAVE_PATH := "user://clip_curves.json"

## The obstacle grid. 0.25 m steps from the lowest thing any move reacts to up
## to the tallest a grab can reach; widths from a handrail to a wall.
const HEIGHT_STEP := 0.25
const HEIGHT_MIN := 0.25
const HEIGHT_MAX := 2.75
const WIDTHS: Array[float] = [0.1, 0.2, 0.3, 0.4, 0.6, 0.8, 1.0, 1.4, 2.0]

## Approach speeds. Which vault variant the table picks depends on momentum, so
## the same obstacle is a different move at a different pace.
const SPEEDS: Array[float] = [1.5, 2.5, 3.5, 4.5, 5.5, 6.5, 7.2]

## When to jump, in SECONDS BEFORE CONTACT rather than metres before it.
##
## ✅ THE OWNER, having guessed the state machine's own unit correctly: "如果是撞到
## 障碍物的相对时间就调整距离撞到障碍物多少秒起跳，程序自己计算跳跃." It is: the vault
## table gates on MaxDistanceTime, and SpeedVaultConfig.should_commit() asks
## whether the obstacle will be reached within that many seconds AT THE CURRENT
## SPEED. A distance would mean a different lead-in at every speed; a time is the
## same decision the game is already making.
##
## The first entry never jumps, which is how a walk-up step or a pull-up is
## recorded.
const JUMP_LEADS: Array[float] = [-1.0, 0.05, 0.10, 0.15, 0.20, 0.30, 0.45]

const TAKE_SECONDS := 8.0
const RUN_UP := 7.0

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

var _obstacle: StaticBody3D
var _height_index := 3
var _width_index := 3
var _speed_index := 4
var _lead_index := 3
var _frames: Array[Dictionary] = []
var _cursor := 0
var _recording := false
var _jumped := false
var _seen_scripted := false
var _source := ScriptedInputSource.new()
var _label: Label
var _note := ""
var _live_position := Vector3.ZERO
var _live_rotation := Vector3.ZERO
var _anim_player: AnimationPlayer
var _anim_tree: AnimationTree

func _ready() -> void:
	_build_ui()
	_load()
	call_deferred("_take")

func _exit_tree() -> void:
	Engine.time_scale = 1.0

func height() -> float:
	return HEIGHT_MIN + HEIGHT_STEP * float(_height_index)

func width() -> float:
	return WIDTHS[_width_index]

## The approach speed. The ladder is what the arrow keys step through; the spin
## box can name anything between its ends.
var _speed_override := -1.0

func speed() -> float:
	return _speed_override if _speed_override > 0.0 else SPEEDS[_speed_index]

func jump_lead() -> float:
	return JUMP_LEADS[_lead_index]

# --- the obstacle -------------------------------------------------------------

func _build_obstacle() -> void:
	if _obstacle != null:
		_obstacle.queue_free()
		_obstacle = null
	var body := StaticBody3D.new()
	body.name = "Obstacle"
	var size := Vector3(8.0, height(), width())
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.58, 0.45, 0.5)
	cube.material = material
	mesh.mesh = cube
	body.add_child(mesh)
	add_child(body)
	body.position = Vector3(0.0, height() * 0.5, 0.0)
	_obstacle = body

## The near face of the obstacle, which is what a time-to-contact is measured to.
func _face_z() -> float:
	return width() * 0.5

# --- the take -------------------------------------------------------------------

func _take() -> void:
	if player == null:
		return
	_build_obstacle()
	_frames.clear()
	_cursor = 0
	_jumped = false
	_seen_scripted = false
	_resolve_animation_nodes()
	if _anim_tree != null:
		_anim_tree.active = true
	player.input_source = _source
	_source.state = MoveInput.new()
	player.velocity = Vector3.ZERO
	player.rotation.y = 0.0
	player.global_position = Vector3(0.0, player.current_capsule_height() * 0.5,
		_face_z() + RUN_UP)
	player.move_manager.start(Move.WALKING)
	# STRAIGHT AT IT, holding forward, and nothing else.
	_source.state.move = Vector2(0.0, 1.0)
	_recording = true
	Engine.time_scale = 1.0
	_note = "recording %.2f x %.2f at %.1f m/s ..." % [height(), width(), speed()]

func _physics_process(_delta: float) -> void:
	if not _recording or player == null:
		return
	_drive()
	_frames.append({
		"position": player.global_position,
		"rotation": player.rotation,
		"clip": player._current_clip(),
		"clip_time": _clip_time(),
		"move": player.move_manager.current_name,
		"progress": player.scripted_progress(),
		"obstacle": Vector2(height(), width()),
	})
	if float(_frames.size()) / float(Engine.physics_ticks_per_second) >= TAKE_SECONDS:
		_finish()

## Holds the approach at a constant speed and presses jump on time.
##
## ⚠️ ONLY WHILE THE BODY OWNS ITSELF. A scripted move drives the position
## directly, so writing velocity through one would fight it -- and the whole
## point of the take is to watch what the move does, not to push it around.
func _drive() -> void:
	var scripted: bool = player.scripted_progress() >= 0.0
	if scripted:
		_seen_scripted = true
	elif _seen_scripted:
		# THE TAKE IS OVER. Left holding forward, the body runs the remaining
		# seconds straight off the edge of the floor and the tail of every
		# recording is an uncontrolled fall -- which is not what anyone came here
		# to key.
		_source.state.move = Vector2.ZERO
		return
	if not scripted and player.move_manager.current_name == Move.WALKING:
		player.velocity.x = 0.0
		player.velocity.z = -speed()
	if _jumped or jump_lead() < 0.0:
		return
	var to_face: float = player.global_position.z - _face_z()
	if to_face <= 0.0:
		return
	# TIME, not distance -- see JUMP_LEADS.
	if to_face / maxf(speed(), 0.001) <= jump_lead():
		_source.press_jump()
		_jumped = true

func _finish() -> void:
	_recording = false
	_source.state.move = Vector2.ZERO
	_source.release_jump()
	# HANDED OVER TO THE RECORDING. The live simulation stops dead so nothing
	# keeps writing the transform the scrub is about to own.
	Engine.time_scale = 0.0
	if _anim_tree != null:
		_anim_tree.active = false
	_cursor = _scripted_start()
	_scrub(0)
	_note = "%d frames -- A/D walks them" % _frames.size()

## The first frame of the scripted move, so a take opens on the interesting part
## rather than on seven metres of running.
func _scripted_start() -> int:
	for i in _frames.size():
		if float(_frames[i].get("progress", -1.0)) >= 0.0:
			return i
	return 0

func _resolve_animation_nodes() -> void:
	if player.body == null:
		return
	_anim_player = player.body.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var root := player.get_node_or_null("BodyRoot")
	if root == null:
		return
	for child in root.get_children():
		if child is AnimationTree:
			_anim_tree = child

func _clip_time() -> float:
	if _anim_player == null or not _anim_player.is_playing():
		return 0.0
	return _anim_player.current_animation_position

# --- scrubbing --------------------------------------------------------------------

func _scrub(by: int) -> void:
	if _frames.is_empty():
		return
	_cursor = clampi(_cursor + by, 0, _frames.size() - 1)
	var frame: Dictionary = _frames[_cursor]
	player.global_position = frame["position"]
	player.rotation = frame["rotation"]
	player.active_obstacle = frame.get("obstacle", Vector2(-1.0, 0.0))
	# THE POSE IS REPLAYED, not re-simulated: it is a pure function of the clip
	# and the time in it, both of which were recorded.
	var clip: StringName = frame.get("clip", Move.KEEP)
	if _anim_player != null and clip != Move.KEEP and _anim_player.has_animation(String(clip)):
		_anim_player.play(String(clip))
		_anim_player.seek(float(frame.get("clip_time", 0.0)), true)
	_live_position = Vector3.ZERO
	_live_rotation = Vector3.ZERO
	var keyed: Array = player.clip_curve_at(clip, float(frame.get("progress", -1.0)))
	if not keyed.is_empty():
		_live_position = keyed[0]
		_live_rotation = keyed[1]
	player.set_clip_offset_immediately(_live_position, _live_rotation)

func _frame_progress() -> float:
	if _frames.is_empty():
		return -1.0
	return float(_frames[_cursor].get("progress", -1.0))

func _frame_clip() -> StringName:
	if _frames.is_empty():
		return Move.KEEP
	return _frames[_cursor].get("clip", Move.KEEP)

# --- keying -----------------------------------------------------------------------

func _nudge(delta_position: Vector3, delta_rotation: Vector3) -> void:
	var step := NUDGE
	if Input.is_key_pressed(KEY_SHIFT):
		step = NUDGE_FAST
	elif Input.is_key_pressed(KEY_CTRL):
		step = NUDGE_FINE
	_live_position += delta_position * step
	_live_rotation += delta_rotation * (step * 100.0)
	player.set_clip_offset_immediately(_live_position, _live_rotation)
	_commit()

## Writes the live offset in at this frame's time, under this obstacle, and
## saves. ✅ "我每调一次你就自动保存一个 JSON" -- no commit step to forget, and no
## session lost to a stray Escape.
func _commit() -> void:
	var clip: StringName = _frame_clip()
	var at: float = _frame_progress()
	if clip == Move.KEEP or at < 0.0:
		_note = "this frame is not part of a scripted move"
		return
	var rows: Array = player.body_clip_curves.get(clip, [])
	var row: Dictionary = {}
	for candidate in rows:
		if absf(float(candidate.get("h", -1.0)) - height()) < 0.001 \
				and absf(float(candidate.get("w", -1.0)) - width()) < 0.001:
			row = candidate
			break
	if row.is_empty():
		row = {"h": height(), "w": width(), "keys": []}
		rows.append(row)
	var keys: Array = row["keys"]
	var replaced := false
	for key in keys:
		if absf(float(key.get("t", -1.0)) - at) < 0.005:
			key["pos"] = _live_position
			key["rot"] = _live_rotation
			replaced = true
			break
	if not replaced:
		keys.append({"t": at, "pos": _live_position, "rot": _live_rotation})
		keys.sort_custom(func(a, b): return float(a["t"]) < float(b["t"]))
	row["keys"] = keys
	player.body_clip_curves[clip] = rows
	_save()
	_note = "%s @ %.2f x %.2f : %d keys" % [clip, height(), width(), keys.size()]

func _drop_key() -> void:
	var clip: StringName = _frame_clip()
	var at: float = _frame_progress()
	if clip == Move.KEEP or not player.body_clip_curves.has(clip):
		return
	for row in player.body_clip_curves[clip]:
		if absf(float(row.get("h", -1.0)) - height()) > 0.001 \
				or absf(float(row.get("w", -1.0)) - width()) > 0.001:
			continue
		var keys: Array = row["keys"]
		for i in keys.size():
			if absf(float(keys[i].get("t", -1.0)) - at) < 0.03:
				keys.remove_at(i)
				_save()
				_note = "dropped a key, %d left" % keys.size()
				return

# --- the file ---------------------------------------------------------------------

func _save() -> void:
	var out := {}
	for clip in player.body_clip_curves:
		var rows: Array = []
		for row in player.body_clip_curves[clip]:
			var keys: Array = []
			for key in row.get("keys", []):
				var pos: Vector3 = key.get("pos", Vector3.ZERO)
				var rot: Vector3 = key.get("rot", Vector3.ZERO)
				keys.append({"t": float(key.get("t", 0.0)),
					"pos": [pos.x, pos.y, pos.z], "rot": [rot.x, rot.y, rot.z]})
			rows.append({"h": float(row.get("h", 0.0)),
				"w": float(row.get("w", 0.0)), "keys": keys})
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
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return
	var loaded := {}
	for clip in parsed:
		var rows: Array = []
		for row in parsed[clip]:
			var keys: Array = []
			for key in row.get("keys", []):
				keys.append({"t": float(key.get("t", 0.0)),
					"pos": _to_vector(key.get("pos", [])),
					"rot": _to_vector(key.get("rot", []))})
			rows.append({"h": float(row.get("h", 0.0)),
				"w": float(row.get("w", 0.0)), "keys": keys})
		loaded[StringName(clip)] = rows
	player.body_clip_curves = loaded

func _to_vector(from) -> Vector3:
	if from is Array and from.size() >= 3:
		return Vector3(float(from[0]), float(from[1]), float(from[2]))
	return Vector3.ZERO

# --- input ------------------------------------------------------------------------

func _handle(key: int) -> bool:
	match key:
		KEY_A:
			_scrub(-1)
		KEY_D:
			_scrub(1)
		KEY_Q:
			_scrub(-10)
		KEY_E:
			_scrub(10)
		KEY_W:
			_height_index = mini(_height_index + 1, _height_count() - 1)
			_take()
		KEY_S:
			_height_index = maxi(_height_index - 1, 0)
			_take()
		KEY_EQUAL:
			_width_index = mini(_width_index + 1, WIDTHS.size() - 1)
			_take()
		KEY_MINUS:
			_width_index = maxi(_width_index - 1, 0)
			_take()
		KEY_PERIOD:
			_speed_index = mini(_speed_index + 1, SPEEDS.size() - 1)
			_speed_override = -1.0
			_take()
		KEY_COMMA:
			_speed_index = maxi(_speed_index - 1, 0)
			_speed_override = -1.0
			_take()
		KEY_PAGEUP:
			_lead_index = mini(_lead_index + 1, JUMP_LEADS.size() - 1)
			_take()
		KEY_PAGEDOWN:
			_lead_index = maxi(_lead_index - 1, 0)
			_take()
		KEY_R:
			_take()
		KEY_ENTER, KEY_KP_ENTER:
			_commit()
		KEY_BACKSPACE:
			_drop_key()
		KEY_DELETE:
			_live_position = Vector3.ZERO
			_live_rotation = Vector3.ZERO
			player.set_clip_offset_immediately(Vector3.ZERO, Vector3.ZERO)
			_commit()
		_:
			if POSITION_KEYS.has(key):
				_nudge(POSITION_KEYS[key], Vector3.ZERO)
			elif key == KEY_SEMICOLON:
				_nudge(Vector3.ZERO, Vector3(0.0, -1.0, 0.0))
			elif key == KEY_APOSTROPHE:
				_nudge(Vector3.ZERO, Vector3(0.0, 1.0, 0.0))
			else:
				return false
	return true

func _height_count() -> int:
	return int(round((HEIGHT_MAX - HEIGHT_MIN) / HEIGHT_STEP)) + 1

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo or _recording:
		return
	if _handle((event as InputEventKey).physical_keycode):
		get_viewport().set_input_as_handled()

# --- the form ---------------------------------------------------------------------
#
# ✅ THE OWNER: "godot 做不了按钮滑块和输入框吗，我需要一个表单之类的东西，可以在里面
# 调参数和查看保存的数据，想象你在做一个网页版动画预览器，只不过画面是游戏引擎渲染而
# 不是 canvas."
#
# It can, and this is that. The keyboard shortcuts stay -- nudging is faster on
# IJKL than in a spin box -- but nothing REQUIRES them, and every value that
# used to be a hidden index is now a control you can read off the screen.

var _ui_syncing := false
var _timeline: HSlider
var _height_box: SpinBox
var _width_box: OptionButton
var _speed_box: SpinBox
var _lead_box: OptionButton
var _offset_boxes: Array[SpinBox] = []
var _yaw_box: SpinBox
var _key_list: ItemList
var _readout: Label
var _status: Label

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -400.0
	panel.custom_minimum_size = Vector2(400.0, 0.0)
	layer.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)

	column.add_child(_heading("OBSTACLE"))
	_height_box = _spin(column, "height (m)", HEIGHT_MIN, HEIGHT_MAX, HEIGHT_STEP, height())
	_height_box.value_changed.connect(func(v):
		if _ui_syncing: return
		_height_index = int(round((v - HEIGHT_MIN) / HEIGHT_STEP))
		_take())
	_width_box = _options(column, "depth (m)", WIDTHS.map(func(w): return "%.2f" % w), _width_index)
	_width_box.item_selected.connect(func(i):
		if _ui_syncing: return
		_width_index = i
		_take())

	column.add_child(_heading("APPROACH"))
	_speed_box = _spin(column, "speed (m/s)", SPEEDS[0], SPEEDS[SPEEDS.size() - 1], 0.1, speed())
	_speed_box.value_changed.connect(func(v):
		if _ui_syncing: return
		_speed_override = v
		_take())
	var leads: Array = []
	for lead in JUMP_LEADS:
		leads.append("never" if lead < 0.0 else "%.2f s before contact" % lead)
	_lead_box = _options(column, "jump", leads, _lead_index)
	_lead_box.item_selected.connect(func(i):
		if _ui_syncing: return
		_lead_index = i
		_take())
	var retake := Button.new()
	retake.text = "Re-record take  (R)"
	retake.pressed.connect(_take)
	column.add_child(retake)

	column.add_child(_heading("TIMELINE"))
	_timeline = HSlider.new()
	_timeline.min_value = 0.0
	_timeline.step = 1.0
	_timeline.custom_minimum_size = Vector2(0.0, 24.0)
	_timeline.value_changed.connect(func(v):
		if _ui_syncing: return
		_scrub(int(v) - _cursor))
	column.add_child(_timeline)
	var steps := HBoxContainer.new()
	for entry in [["|<", -100000], ["-10", -10], ["-1", -1], ["+1", 1], ["+10", 10], [">|", 100000]]:
		var button := Button.new()
		button.text = entry[0]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var by: int = entry[1]
		button.pressed.connect(func(): _scrub(by))
		steps.add_child(button)
	column.add_child(steps)
	var to_move := Button.new()
	to_move.text = "jump to the scripted move"
	to_move.pressed.connect(func(): _scrub(_scripted_start() - _cursor))
	column.add_child(to_move)
	_readout = Label.new()
	_readout.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_readout)

	column.add_child(_heading("OFFSET AT THIS FRAME"))
	for axis in ["x", "y", "z"]:
		var box := _spin(column, axis + " (m)", -2.0, 2.0, 0.001, 0.0)
		box.value_changed.connect(func(_v):
			if _ui_syncing: return
			_read_offset_boxes())
		_offset_boxes.append(box)
	_yaw_box = _spin(column, "yaw (deg)", -180.0, 180.0, 0.5, 0.0)
	_yaw_box.value_changed.connect(func(_v):
		if _ui_syncing: return
		_read_offset_boxes())
	var buttons := HBoxContainer.new()
	for entry in [["Key (Enter)", _commit], ["Drop (Bksp)", _drop_key], ["Zero (Del)", _zero]]:
		var button := Button.new()
		button.text = entry[0]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(entry[1])
		buttons.add_child(button)
	column.add_child(buttons)

	column.add_child(_heading("KEYS FOR THIS COMBINATION"))
	_key_list = ItemList.new()
	_key_list.custom_minimum_size = Vector2(0.0, 160.0)
	_key_list.item_selected.connect(_go_to_key)
	column.add_child(_key_list)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)
	var hint := Label.new()
	hint.text = "A/D frame   Q/E ten   IJKL/UO nudge   ;' yaw   Shift coarse   Ctrl fine"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint)

func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = NEWLINE + text
	return label

func _spin(into: Node, label_text: String, low: float, high: float,
		step: float, value: float) -> SpinBox:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(110.0, 0.0)
	row.add_child(label)
	var box := SpinBox.new()
	box.min_value = low
	box.max_value = high
	box.step = step
	box.value = value
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(box)
	into.add_child(row)
	return box

func _options(into: Node, label_text: String, items: Array, selected: int) -> OptionButton:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(110.0, 0.0)
	row.add_child(label)
	var box := OptionButton.new()
	for item in items:
		box.add_item(str(item))
	box.selected = selected
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(box)
	into.add_child(row)
	return box

## Takes whatever is in the offset boxes and applies it, keying as it goes --
## the same contract the IJKL nudges have.
func _read_offset_boxes() -> void:
	_live_position = Vector3(_offset_boxes[0].value, _offset_boxes[1].value,
		_offset_boxes[2].value)
	_live_rotation = Vector3(0.0, _yaw_box.value, 0.0)
	player.set_clip_offset_immediately(_live_position, _live_rotation)
	_commit()

func _zero() -> void:
	_live_position = Vector3.ZERO
	_live_rotation = Vector3.ZERO
	player.set_clip_offset_immediately(Vector3.ZERO, Vector3.ZERO)
	_commit()

## Walks the recording to the frame nearest a saved key's time, so the list is a
## way of navigating rather than only a way of looking.
func _go_to_key(index: int) -> void:
	var keys: Array = _current_keys()
	if index < 0 or index >= keys.size():
		return
	var wanted: float = float(keys[index].get("t", 0.0))
	var best := _cursor
	var best_gap := INF
	for i in _frames.size():
		var progress: float = float(_frames[i].get("progress", -1.0))
		if progress < 0.0:
			continue
		var gap: float = absf(progress - wanted)
		if gap < best_gap:
			best_gap = gap
			best = i
	_scrub(best - _cursor)

func _current_keys() -> Array:
	var clip: StringName = _frame_clip()
	if clip == Move.KEEP or not player.body_clip_curves.has(clip):
		return []
	for row in player.body_clip_curves[clip]:
		if absf(float(row.get("h", -1.0)) - height()) < 0.001 \
				and absf(float(row.get("w", -1.0)) - width()) < 0.001:
			return row.get("keys", [])
	return []

func _refresh_ui() -> void:
	if _readout == null:
		return
	_ui_syncing = true
	_timeline.max_value = maxf(float(_frames.size() - 1), 0.0)
	_timeline.value = float(_cursor)
	_height_box.value = height()
	_width_box.selected = _width_index
	_speed_box.value = speed()
	_lead_box.selected = _lead_index
	_offset_boxes[0].value = _live_position.x
	_offset_boxes[1].value = _live_position.y
	_offset_boxes[2].value = _live_position.z
	_yaw_box.value = _live_rotation.y
	var progress: float = _frame_progress()
	var seconds: float = float(_cursor) / float(Engine.physics_ticks_per_second)
	_readout.text = NEWLINE.join([
		"frame %d / %d      %.2f s" % [_cursor, maxi(_frames.size() - 1, 0), seconds],
		"move  %s" % (String(_frames[_cursor].get("move", "-")) if not _frames.is_empty() else "-"),
		"clip  %s" % String(_frame_clip()),
		"path  %s" % ("t = %.3f" % progress if progress >= 0.0 else "not a scripted frame"),
	])
	var keys: Array = _current_keys()
	_key_list.clear()
	for key in keys:
		var pos: Vector3 = key.get("pos", Vector3.ZERO)
		_key_list.add_item("t %.3f   (%+.3f, %+.3f, %+.3f)  yaw %+.1f" % [
			float(key.get("t", 0.0)), pos.x, pos.y, pos.z,
			(key.get("rot", Vector3.ZERO) as Vector3).y])
	_status.text = _note + NEWLINE + ProjectSettings.globalize_path(SAVE_PATH)
	_ui_syncing = false

func _process(_delta: float) -> void:
	_refresh_ui()
