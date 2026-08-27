class_name CharacterShowcase
extends Node3D

# The character viewer, reached from the main menu's Character entry: the
# body on the left under a free orbit camera, the clip list in the menu's
# own red column on the right. Left-drag turns HER, right-drag pans the
# camera, the wheel zooms. A looping clip loops; a one-shot returns to Idle
# when it ends. The floor speaks the menu's dot-grid language
# (dot_grid_floor.gdshader) with SSR for the sheen.
#
# Whole scene built from code on a one-node .tscn, exactly like MainMenu.

const MAIN_MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const BODY_PROFILE := "res://scenes/player/local/profiles/vrm_test.tres"
const LOCAL_PROFILE_CONFIG := "res://scenes/player/local/profiles/local.cfg"

## The showcase catalogue. One dictionary per entry; everything but `label`
## is optional:
##
##   label     The name shown in the menu.
##   clip      A single-part entry writes this directly.
##   parts     A multi-part entry: parts played in sequence, one dictionary
##             each:
##               clip      The clip's name.
##               from/to   Play only this span of the clip, in seconds
##                         (defaults to the whole clip).
##               duration  How many seconds this part gets on screen
##                         (defaults to to - from).
##               stretch   true    = change the playback speed to fill
##                                   `duration` exactly.
##                         omitted = play at normal speed and cut to the
##                                   next part when `duration` is up.
##   loop      Whether a single-part entry loops; a multi-part entry always
##             plays through exactly once.
##   hop       A scripted jump arc {height = metres, apex = seconds to the
##             top}: the body follows half a sine, lands at apex × 2, and
##             **the arc itself decides when to cut to the final part**,
##             independent of clip length (set to 0.6 and it peaks at
##             0.6 s, lands at 1.2 s). The showcase has no physics --
##             without this a jump is just miming in place.
##
## A single-part entry returns to Idle automatically when it finishes. Only
## entries whose body actually carries every part they name make it into
## the menu.
const CLIP_MENU: Array = [
	{label = "Idle", clip = &"Idle", loop = true},
	{label = "Idle_LookAround", clip = &"Idle_LookAround", loop = true},
	{label = "Idle_Tired", clip = &"Idle_Tired", loop = true},
	{label = "Idle_Talking", clip = &"Idle_Talking", loop = true},
	{label = "Idle_FoldArms", clip = &"Idle_FoldArms", loop = true},
	{label = "Idle_No", clip = &"Idle_No", loop = true},
	{label = "Sitting_Idle", clip = &"Sitting_Idle", loop = true},
	{label = "GroundSit_Idle", clip = &"GroundSit_Idle", loop = true},
	{label = "Walk", clip = &"Walk", loop = true},
	{label = "Sprint", clip = &"Sprint", loop = true},
	{label = "Crouch_Idle", clip = &"Crouch_Idle", loop = true},
	{label = "Crouch_Fwd", clip = &"Crouch_Fwd", loop = true},
	{
		label = "Jump",
		parts = [{clip = &"Jump_Start"}, {clip = &"Jump_Land"}],
		hop = {height = 0.65, apex = 0.65},
	},
	{
		label = "Slide",
		parts = [
			{clip = &"Slide_Start"},
			{clip = &"Slide", duration = 1.0},
			{clip = &"Slide_Exit"},
		],
	},
	{label = "Roll", clip = &"Roll"},
	{label = "SafetyVault", clip = &"SafetyVault"},
	{label = "StepUp", clip = &"StepUp"},
	{label = "ClimbUp_1m", clip = &"ClimbUp_1m"},
	{label = "ClimbUp_2m", clip = &"ClimbUp_2m"},
	{label = "ClimbLedge", clip = &"ClimbLedge"},
	{
		label = "Climb",
		parts = [
			{clip = &"Climb_Enter"},
			{clip = &"Climb_Idle", duration = 1.0},
			{clip = &"Climb_Exit"},
		],
	},
	{label = "Climb_Up", clip = &"Climb_Up", loop = true},
	{label = "Climb_Down", clip = &"Climb_Down", loop = true},
	{label = "WallRun_L", clip = &"WallRun_L", loop = true},
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
## The pan cage -- the camera target may wander
## around the stage but never leave it.
const PAN_LIMIT_XZ := 2.0
const PAN_MIN_Y := 0.3
const PAN_MAX_Y := 2.4
const HOME_PIVOT := Vector3(0.55, 1.05, 0.0)
const HOME_DISTANCE := 4.2

var _body: Node3D
var _anim_player: AnimationPlayer
var _menu_list: MeMenuList
var _clips: Array = []
## The rest of the sequence currently playing, next part first.
var _queue: Array = []
## Bumped every time a part starts, so a timer scheduled for an earlier
## part cannot cut a later one.
var _part_serial: int = 0
## Whether the current part has already handed over -- the timer and the
## clip's own end both call _advance(), and only the first may count.
var _part_done: bool = false
## The scripted hop for the sequence currently playing: its height and the
## tween carrying the body along the arc.
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
	# The shared acrylic material, the same one levels can put on any mesh.
	floor_mesh.material_override = preload("res://materials/acrylic.tres")
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
	_anim_player.animation_finished.connect(func(_clip: StringName) -> void: _advance())
	for entry in CLIP_MENU:
		var complete := true
		for part in _entry_parts(entry):
			if not _anim_player.has_animation(part.clip):
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
		items.append(String(entry.label))
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
	var entry: Dictionary = _clips[index]
	_land_body()
	_queue = _entry_parts(entry)
	var first: Dictionary = _queue.pop_front()
	var hop: Dictionary = entry.get("hop", {})
	_hop_height = float(hop.get("height", 0.0))
	# A hop with no apex named takes half the take-off part.
	var apex := float(hop.get("apex", _part_span(first) * 0.5))
	# THE ARC DRIVES THE CUT: the take-off gives way to the landing part
	# exactly at touchdown, whatever the clips' own lengths are.
	var cut := 0.0
	if _hop_height > 0.0 and apex > 0.0 and not _queue.is_empty():
		cut = apex * 2.0
	_start_part(first, bool(entry.get("loop", false)) and _queue.is_empty(), 0.3, cut)
	if _hop_height > 0.0 and apex > 0.0 and _body != null:
		_hop_tween = create_tween()
		_hop_tween.tween_method(_set_hop_phase, 0.0, 1.0, apex * 2.0)

## Where the body sits along the arc: a half sine, so it leaves and meets
## the floor at speed and eases through the apex.
func _set_hop_phase(phase: float) -> void:
	if _body != null:
		_body.position.y = _hop_height * sin(PI * clampf(phase, 0.0, 1.0))

## An entry's parts, as dictionaries: a single top-level `clip`, or the
## `parts` list. A bare clip name in that list still works, but the menu
## itself spells every part out -- a config that only grows stays readable
## only while every field is named.
func _entry_parts(entry: Dictionary) -> Array:
	var out: Array = []
	if entry.has("clip"):
		out.append({clip = entry.clip})
	for part in entry.get("parts", []):
		out.append(part if part is Dictionary else {clip = part})
	return out

## How much of the clip a part covers, in seconds of the CLIP's own time
## (before any stretch): `to - from`, defaulting to the whole thing.
func _part_span(part: Dictionary) -> float:
	var animation := _anim_player.get_animation(part.clip)
	var length: float = animation.length if animation != null else 0.0
	return maxf(float(part.get("to", length)) - float(part.get("from", 0.0)), 0.0)

## Puts the body back on the floor and cancels any hop still in flight, so
## picking a new clip mid-jump never leaves her hanging in the air.
func _land_body() -> void:
	if _hop_tween != null and _hop_tween.is_valid():
		_hop_tween.kill()
	if _body != null:
		_body.position.y = 0.0

## Plays one part. `cut_override` is the hop's touchdown time, which
## outranks the part's own duration; see _play_index.
func _start_part(part: Dictionary, loops: bool, blend: float,
		cut_override: float = 0.0) -> void:
	var clip: StringName = part.clip
	var animation := _anim_player.get_animation(clip)
	if animation != null:
		animation.loop_mode = Animation.LOOP_LINEAR if loops else Animation.LOOP_NONE
	var span := _part_span(part)
	var on_screen := float(part.get("duration", span))
	if cut_override > 0.0:
		on_screen = cut_override
	# stretch fits the clip to the time; without it the clip runs at its own
	# speed and simply gets cut when the time is up.
	var stretch := bool(part.get("stretch", false))
	_anim_player.speed_scale = span / on_screen if stretch and on_screen > 0.0 and span > 0.0 else 1.0
	_part_serial += 1
	_part_done = false
	_anim_player.play(clip, blend)
	var from := float(part.get("from", 0.0))
	if from > 0.0:
		_anim_player.seek(from, true)
	if loops or on_screen <= 0.0:
		return
	# A timer, not the clip's own end, whenever the part stops early -- a
	# cut, a stretch, or a `to` short of the clip's length.
	var serial := _part_serial
	get_tree().create_timer(on_screen).timeout.connect(func() -> void:
		if serial == _part_serial:
			_advance())

## The part is over -- by its timer or by the clip running out. Whichever
## arrives first wins; the other is ignored, so a part never advances twice.
func _advance() -> void:
	if _anim_player == null or _part_done:
		return
	_part_done = true
	if not _queue.is_empty():
		_start_part(_queue.pop_front(), false, 0.15)
		return
	_land_body()
	if _anim_player.has_animation(&"Idle"):
		_start_part({clip = &"Idle"}, true, 0.4)

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
			# Vertical drag orbits the CAMERA's elevation: drag DOWN looks down
			# from above, as if tipping her toward you -- the sign below is
			# intentionally inverted from a literal reading of the motion.
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
	# Normal transitions are WHITE (the transition-colour convention). Headless
	if DisplayServer.get_name() == "headless":
		_change_scene.call(MAIN_MENU_SCENE)
		return
	PauseUi.run_white_transition(load(MAIN_MENU_SCENE), 0.35)
