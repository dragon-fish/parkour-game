class_name CharacterShowcase
extends Node3D

# The character viewer, reached from the main menu's 角色 entry: the body on
# the left under a free orbit camera, the clip list in the menu's own red
# column on the right. Left-drag turns HER, right-drag pans the camera,
# the wheel zooms. A looping clip loops; a one-shot returns to Idle when it
# ends (✅ the owner: 单次动画播完自动回 idle 避免抽风). The floor speaks the
# menu's dot-grid language (dot_grid_floor.gdshader) with SSR for the sheen.
#
# Whole scene built from code on a one-node .tscn, exactly like MainMenu.

const MAIN_MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const BODY_PROFILE := "res://scenes/player/profiles/vrm_test.tres"
const LOCAL_PROFILE_CONFIG := "res://scenes/player/profiles/local.cfg"

## The clips on offer, in menu order: [label, [part, ...], loops]. A part is
## a clip name, or [clip name, max_seconds] to cut it short -- the packs'
## mid-air / hang cycles run 2.5 s and read as floating (✅ the owner: 悬空时
## 间太久了点, 观感不太连续). A multi-clip entry plays its parts back to back
## once; a looping single loops; everything else settles back on Idle when
## it ends. A fourth element is a HOP HEIGHT in metres: the viewer has no
## physics, so a jump clip plays on the spot and reads as a mime (✅ the
## owner: 跳跃播放期间角色高度没有变化, 还挺怪的). The body rises over the
## first part and drops back at the start of the last one -- presentation
## only, nothing to do with how the game moves a capsule.
## Only entries whose every clip the merged body carries make the list.
const CLIP_MENU: Array = [
	["Idle", [&"Idle"], true],
	["Idle_LookAround", [&"Idle_LookAround"], true],
	["Idle_Tired", [&"Idle_Tired"], true],
	["Idle_Talking", [&"Idle_Talking"], true],
	["Idle_FoldArms", [&"Idle_FoldArms"], true],
	["Idle_No", [&"Idle_No"], true],
	["Sitting_Idle", [&"Sitting_Idle"], true],
	["GroundSit_Idle", [&"GroundSit_Idle"], true],
	["Walk", [&"Walk"], true],
	["Sprint", [&"Sprint"], true],
	["Crouch_Idle", [&"Crouch_Idle"], true],
	["Crouch_Fwd", [&"Crouch_Fwd"], true],
	# No mid-air part at all: a jump has to read as one motion (✅ the owner:
	# 跳跃需要一气呵成的感觉, 否则像悬空). Climb keeps its hang because that IS
	# the pose worth showing.
	# Plays whole: with the scripted hop under it, Jump_Start's ease into
	# the hang reads as the apex rather than as floating.
	["Jump", [&"Jump_Start", &"Jump_Land"], false, 0.55],
	["Slide", [&"Slide_Start", [&"Slide", 1.0], &"Slide_Exit"], false],
	["Roll", [&"Roll"], false],
	["SafetyVault", [&"SafetyVault"], false],
	["StepUp", [&"StepUp"], false],
	["ClimbUp_1m", [&"ClimbUp_1m"], false],
	["ClimbUp_2m", [&"ClimbUp_2m"], false],
	["ClimbLedge", [&"ClimbLedge"], false],
	["Climb", [&"Climb_Enter", [&"Climb_Idle", 1.0], &"Climb_Exit"], false],
	["Climb_Up", [&"Climb_Up"], true],
	["Climb_Down", [&"Climb_Down"], true],
	["WallRun_L", [&"WallRun_L"], true],
]

const ROTATE_SPEED := 0.012
const PITCH_SPEED := 0.008
const PAN_SPEED := 0.0022
const ZOOM_STEP := 0.9
const MIN_DISTANCE := 0.8
const MAX_DISTANCE := 8.0
## Orbit pitch range: negative lifts the camera into a look-down; the small
## positive tail is "slightly below eye line", not an up-skirt angle.
const PITCH_MIN := -1.1
const PITCH_MAX := 0.2
## The pan cage (✅ the owner: 右键要加限位) -- the camera target may wander
## around the stage but never leave it.
const PAN_LIMIT_XZ := 2.0
const PAN_MIN_Y := 0.3
const PAN_MAX_Y := 2.4
const HOME_PIVOT := Vector3(0.55, 1.05, 0.0)
const HOME_DISTANCE := 4.2
## How long the scripted hop takes to fall back, in seconds. Short: the
## landing clip's own cushion carries on after touchdown.
const HOP_FALL_TIME := 0.22

var _body: Node3D
var _anim_player: AnimationPlayer
var _menu_list: MeMenuList
var _clips: Array = []
## The rest of the sequence currently playing, next part first.
var _queue: Array = []
## Bumped every time a part starts, so a time cap scheduled for an earlier
## part cannot cut a later one.
var _part_serial: int = 0
## The scripted hop for the sequence currently playing: its height, and the
## tween carrying the body through it.
var _hop_height: float = 0.0
var _hop_tween: Tween
var _pivot: Node3D
var _camera: Camera3D
var _distance: float = HOME_DISTANCE
var _home_body_basis: Basis
## Same test seam shape as MainMenu/PauseUi.
var _change_scene: Callable = Callable(self, "_real_change_scene")

func _real_change_scene(path: String) -> void:
	get_tree().change_scene_to_file(path)

func _ready() -> void:
	_build_world()
	_build_body()
	_build_ui()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.93, 0.94, 0.96)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.85, 0.86, 0.9)
	e.ambient_light_energy = 0.7
	e.ssr_enabled = true
	e.ssr_max_steps = 32
	add_child(env)
	env.environment = e
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, 28.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60.0, 60.0)
	floor_mesh.mesh = plane
	var material := ShaderMaterial.new()
	material.shader = preload("res://scripts/ui/dot_grid_floor.gdshader")
	floor_mesh.material_override = material
	add_child(floor_mesh)
	_pivot = Node3D.new()
	# Off to the side so SHE sits screen-left and the red column owns the right.
	_pivot.position = HOME_PIVOT
	add_child(_pivot)
	_camera = Camera3D.new()
	_camera.fov = 45.0
	_pivot.add_child(_camera)
	_camera.position = Vector3(0.0, 0.0, _distance)
	_camera.current = true

func _build_body() -> void:
	var path: String = BODY_PROFILE
	var local := ConfigFile.new()
	if local.load(LOCAL_PROFILE_CONFIG) == OK:
		path = str(local.get_value("body", "profile", BODY_PROFILE))
	if not ResourceLoader.exists(path):
		return
	var profile := load(path) as BodyProfile
	if profile == null or profile.scene == null:
		return
	BodyTuning.apply_to(profile,
		BodyTuning.load_for(profile.scene.resource_path))
	_body = profile.scene.instantiate() as Node3D
	if _body == null:
		return
	# The mount rotation points her down the capsule's -Z; the viewer camera
	# sits at +Z, so half a turn more puts her face toward it.
	_body.basis = (Basis(Vector3.UP, PI) \
		* Basis.from_euler(profile.mount_rotation_degrees * (PI / 180.0))) \
		.scaled(Vector3.ONE * maxf(profile.mount_scale, 0.001))
	add_child(_body)
	_home_body_basis = _body.basis
	_anim_player = _find_animation_player(_body)
	if _anim_player == null:
		return
	_merge_libraries(profile.animation_libraries)
	_anim_player.animation_finished.connect(_on_clip_finished)
	for entry in CLIP_MENU:
		var complete := true
		for part in entry[1]:
			if not _anim_player.has_animation(_part_clip(part)):
				complete = false
				break
		if complete:
			_clips.append(entry)
	_play_index(0)

func _find_animation_player(root: Node) -> AnimationPlayer:
	var queue: Array[Node] = [root]
	while not queue.is_empty():
		var node: Node = queue.pop_front()
		if node is AnimationPlayer:
			return node as AnimationPlayer
		for child in node.get_children():
			queue.append(child)
	return null

## Same fill-the-gaps merge as MainMenu/Player: existing clips win.
func _merge_libraries(libraries: Array[PackedScene]) -> void:
	var library: AnimationLibrary
	if _anim_player.has_animation_library(""):
		library = _anim_player.get_animation_library("")
	else:
		library = AnimationLibrary.new()
		_anim_player.add_animation_library("", library)
	for packed in libraries:
		if packed == null:
			continue
		var source_scene := packed.instantiate()
		if source_scene == null:
			continue
		var source := _find_animation_player(source_scene)
		if source != null:
			for clip_name in source.get_animation_list():
				if not library.has_animation(clip_name):
					library.add_animation(clip_name,
						source.get_animation(clip_name).duplicate())
		source_scene.free()

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_menu_list = MeMenuList.new()
	_menu_list.custom_minimum_size = Vector2(420.0, 0.0)
	_menu_list.anchor_left = 1.0
	_menu_list.anchor_right = 1.0
	_menu_list.anchor_top = 0.0
	_menu_list.anchor_bottom = 1.0
	_menu_list.offset_left = -480.0
	_menu_list.offset_right = -60.0
	_menu_list.offset_top = 0.0
	_menu_list.offset_bottom = 0.0
	layer.add_child(_menu_list)
	var items: Array[String] = []
	for entry in _clips:
		items.append(String(entry[0]))
	if items.is_empty():
		items.append("（没有可用动画）")
	_menu_list.set_items(items)
	_menu_list.chosen.connect(_play_index)
	layer.add_child(MeTheme.footer_label("左键 旋转/俯仰 · 右键 平移 · 滚轮 缩放 · Esc 返回"))
	var back := MeTheme.confirm_button("返回", MeTheme.BRAND_RED, _back_to_menu)
	back.position = Vector2(20.0, 16.0)
	layer.add_child(back)
	var reset := MeTheme.confirm_button("重置镜头", Color(0.55, 0.62, 0.72), _reset_camera)
	reset.anchor_top = 1.0
	reset.anchor_bottom = 1.0
	reset.position = Vector2(20.0, -66.0)
	layer.add_child(reset)

func _reset_camera() -> void:
	_pivot.position = HOME_PIVOT
	_pivot.rotation = Vector3.ZERO
	_set_distance(HOME_DISTANCE)
	if _body != null:
		_body.basis = _home_body_basis

func _play_index(index: int) -> void:
	if _anim_player == null or index >= _clips.size():
		return
	var entry: Array = _clips[index]
	var parts: Array = entry[1]
	var loops: bool = entry[2]
	_queue = parts.duplicate()
	var first = _queue.pop_front()
	_start_part(_part_clip(first), loops and _queue.is_empty(), 0.3, _part_cap(first))
	_hop_height = float(entry[3]) if entry.size() > 3 else 0.0
	_land_body()
	if _hop_height > 0.0 and _body != null:
		_hop_tween = create_tween()
		_hop_tween.tween_property(_body, "position:y", _hop_height,
			_part_duration(first)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

static func _part_clip(part) -> StringName:
	return part[0] if part is Array else part

static func _part_cap(part) -> float:
	return float(part[1]) if part is Array else 0.0

## How long a part will actually be on screen: its cap, or the clip's own
## length when it has none.
func _part_duration(part) -> float:
	var cap := _part_cap(part)
	if cap > 0.0:
		return cap
	var animation := _anim_player.get_animation(_part_clip(part))
	return animation.length if animation != null else 0.0

## Puts the body back on the floor and cancels any hop still in flight, so
## picking a new clip mid-jump never leaves her hanging in the air.
func _land_body() -> void:
	if _hop_tween != null and _hop_tween.is_valid():
		_hop_tween.kill()
	if _body != null:
		_body.position.y = 0.0

## A sequence part, or the whole of a single-clip entry: a looping single
## loops; every part of a sequence plays exactly once, or for `max_seconds`
## if that is shorter.
func _start_part(clip: StringName, loops: bool, blend: float, max_seconds: float = 0.0) -> void:
	var animation := _anim_player.get_animation(clip)
	if animation != null:
		animation.loop_mode = Animation.LOOP_LINEAR if loops else Animation.LOOP_NONE
	_anim_player.play(clip, blend)
	_part_serial += 1
	if max_seconds > 0.0:
		var serial := _part_serial
		get_tree().create_timer(max_seconds).timeout.connect(func() -> void:
			if serial == _part_serial:
				_on_clip_finished(clip))

## A part has ended -- naturally (looping clips never emit this) or by its
## time cap: the next part of a sequence if there is one, otherwise settle
## back on Idle rather than freezing on the last frame.
func _on_clip_finished(_clip: StringName) -> void:
	if _anim_player == null:
		return
	if not _queue.is_empty():
		var next = _queue.pop_front()
		_start_part(_part_clip(next), false, 0.15, _part_cap(next))
		# The last part is the landing: come down as it begins.
		if _hop_height > 0.0 and _queue.is_empty() and _body != null:
			if _hop_tween != null and _hop_tween.is_valid():
				_hop_tween.kill()
			_hop_tween = create_tween()
			_hop_tween.tween_property(_body, "position:y", 0.0, HOP_FALL_TIME) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		return
	_land_body()
	if _anim_player.has_animation(&"Idle"):
		_start_part(&"Idle", true, 0.4)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		_back_to_menu()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if motion.button_mask & MOUSE_BUTTON_MASK_LEFT:
			if _body != null:
				_body.rotate_y(motion.relative.x * ROTATE_SPEED)
			# Vertical drag orbits the CAMERA's elevation (✅ the owner:
			# 左键希望可以调俯仰角) -- drag DOWN looks down from above, as if
			# tipping her toward you (✅ the owner: 上下反向一下).
			_pivot.rotation.x = clampf( \
				_pivot.rotation.x - motion.relative.y * PITCH_SPEED,
				PITCH_MIN, PITCH_MAX)
			get_viewport().set_input_as_handled()
		elif motion.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			var right: Vector3 = _camera.global_basis.x
			var up: Vector3 = _camera.global_basis.y
			var wanted: Vector3 = _pivot.position \
				+ (-right * motion.relative.x + up * motion.relative.y) \
				* PAN_SPEED * _distance
			_pivot.position = Vector3( \
				clampf(wanted.x, -PAN_LIMIT_XZ, PAN_LIMIT_XZ),
				clampf(wanted.y, PAN_MIN_Y, PAN_MAX_Y),
				clampf(wanted.z, -PAN_LIMIT_XZ, PAN_LIMIT_XZ))
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_distance(_distance * ZOOM_STEP)
			get_viewport().set_input_as_handled()
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_distance(_distance / ZOOM_STEP)
			get_viewport().set_input_as_handled()

func _set_distance(value: float) -> void:
	_distance = clampf(value, MIN_DISTANCE, MAX_DISTANCE)
	_camera.position = Vector3(0.0, 0.0, _distance)

func _back_to_menu() -> void:
	if not ResourceLoader.exists(MAIN_MENU_SCENE):
		return
	# ✅ 转场约定: normal transitions are WHITE. Headless keeps the seam.
	if DisplayServer.get_name() == "headless":
		_change_scene.call(MAIN_MENU_SCENE)
		return
	PauseUi.run_white_transition(load(MAIN_MENU_SCENE), 0.35)
