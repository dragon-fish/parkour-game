extends Node3D

# A bench for posing a held clip by hand. The body holds one frame of a
# clip, and every joint the BonePoseOffset scoped to that clip can turn gets
# three sliders. What the sliders set IS that node's `rotations`, live, so
# what is on screen is what the game will show.
#
# The dropdown picks the target (TARGETS); switching reloads the scene. Right
# mouse drag orbits, wheel zooms, middle drag pans.
#
# Two kinds of target, told apart by which key they carry:
#   modifier -- the correction lives in the body scene as a BonePoseOffset
#               scoped to the clip; "保存" writes its `rotations` back there.
#   bake     -- a clip the game already plays for something else (Roll is the
#               roll), so no correction may be scoped to it. The node is made
#               here and never saved; "保存" bakes the frame on screen into a
#               one-frame clip of its own (BAKE_PATH) and keeps the slider
#               values in user:// so the next session resumes them.

const BODY_PROFILE := "res://scenes/player/local/profiles/beriul.tres"
const LOCAL_PROFILE_CONFIG := "res://scenes/player/local/profiles/local.cfg"
## What can be posed: the clip held, the frame held (`time`, seconds; a
## negative value is the last frame), and where the result goes (`modifier`
## or `bake`, see the note at the top).
const TARGETS: Array[Dictionary] = [
	{label = "躺地", clip = &"LiftAir_Fall", time = -1.0, modifier = "LyingPose"},
	{label = "屈膝跳·抱膝坐", clip = &"GroundSit_Idle", time = 0.0, modifier = "CoilPose"},
	{label = "屈膝跳·空翻", clip = &"JogToFlip", time = 0.7, bake = &"Coil_Tuck"},
	{label = "屈膝跳·翻滚", clip = &"Roll", time = 0.62, bake = &"Coil_Tuck"},
]
## Where baked poses go: a scene holding an AnimationPlayer, the shape
## BodyProfile.animation_libraries takes. Private, next to the packs it was
## cut from.
const BAKE_PATH := "res://assets/animations/local/beriul_poses.tscn"
const WORKING_DIR := "user://pose_lab"
## Survives the reload a target switch does.
static var _target_index: int = 0

## The joints offered, top to bottom. Fingers and toes are left out: they are
## too small to read at this distance and would bury the ones that matter.
const BONES: Array[String] = [
	"Hips", "Spine", "Chest", "UpperChest", "Neck", "Head",
	"LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand",
	"RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand",
	"LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
	"RightUpperLeg", "RightLowerLeg", "RightFoot",
	# The skirt's roots hang off the THIGHS, so raised knees lift the whole
	# hem with them; turning these back is how a lifted skirt is laid down.
	"HemRoot.L", "HemRoot.R",
	# The gold waist chain hangs off the SPINE, so bending the spine to sit her
	# up swings it off the body. It moves only itself: the dress under it is
	# weighted to Hips.
	"ChainRoot",
]
## Points whose height above the floor is shown, so a hand pushed into the
## ground is a negative number and not a guess.
const PROBES: Array[String] = [
	"Head", "Hips", "LeftHand", "RightHand", "LeftFoot", "RightFoot",
]
const ANGLE_LIMIT := 150.0
## Meshes hidden on arrival: clothes that hide the joints being posed. Every
## mesh gets a toggle, so a wrong guess here costs a click.
const HIDDEN_AT_START: Array[String] = ["Tops", "No-sleeve", "Bandage"]

var _body: Node3D
var _skeleton: Skeleton3D
var _pose: BonePoseOffset
var _anim: AnimationPlayer
var _clip_length: float = 0.0
var _clip_at: float = 0.0
var _mirror: CheckBox
var _readout: Label
var _status: Label
var _sliders: Dictionary = {}  # bone name -> Array[HSlider] (x, y, z)
var _syncing := false

var _pivot: Node3D
var _camera: Camera3D
var _yaw := 0.9
var _pitch := -0.35
var _distance := 3.2
var _orbiting := false
var _panning := false

func _ready() -> void:
	_build_world()
	if not _build_body():
		return
	_build_ui()
	_skeleton.skeleton_updated.connect(_on_skeleton_updated)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.93, 0.94, 0.96)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.85, 0.86, 0.9)
	e.ambient_light_energy = 0.7
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, 28.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20.0, 20.0)
	floor_mesh.mesh = plane
	var grid := StandardMaterial3D.new()
	grid.albedo_color = Color(0.72, 0.74, 0.78)
	floor_mesh.material_override = grid
	add_child(floor_mesh)
	_pivot = Node3D.new()
	_pivot.position = Vector3(0.0, 0.35, 0.0)
	add_child(_pivot)
	_camera = Camera3D.new()
	_camera.fov = 45.0
	_pivot.add_child(_camera)
	_camera.current = true
	_place_camera()

## Mounted the way Player mounts a body, feet at the floor, plus the clip's
## own offset -- the same placement LayOnGroundMove shows on flat ground.
func _build_body() -> bool:
	var path: String = BODY_PROFILE
	var local := ConfigFile.new()
	if local.load(LOCAL_PROFILE_CONFIG) == OK:
		path = str(local.get_value("body", "profile", BODY_PROFILE))
	if not ResourceLoader.exists(path):
		push_error("pose lab: no body profile at %s" % path)
		return false
	var profile := load(path) as BodyProfile
	BodyTuning.apply_to(profile, BodyTuning.load_for(profile.scene.resource_path))
	_body = profile.scene.instantiate() as Node3D
	var mount := Player.compute_mount_transform(0.0, profile.mount_offset,
		profile.mount_rotation_degrees, profile.mount_scale)
	var offset: Vector3 = Vector3.ZERO
	var entry = profile.clip_offsets.get(String(_clip()), null)
	if entry is Array and entry.size() >= 1 and entry[0] is Vector3:
		offset = entry[0]
	_body.transform = Transform3D(mount.basis, mount.origin + offset)
	add_child(_body)
	_skeleton = _find(_body, "Skeleton3D") as Skeleton3D
	_anim = _find(_body, "AnimationPlayer") as AnimationPlayer
	if _skeleton == null or _anim == null:
		push_error("pose lab: body has no skeleton or player")
		return false
	if _is_bake():
		_pose = _make_lab_modifier()
	else:
		for node in _body.find_children(_modifier(), "", true, false):
			if node is BonePoseOffset:
				_pose = node
	if _pose == null:
		push_error("pose lab: body has no %s" % _modifier())
		return false
	_merge_libraries(profile.animation_libraries)
	if not _anim.has_animation(_clip()):
		push_error("pose lab: no clip %s" % _clip())
		return false
	_clip_length = _anim.get_animation(_clip()).length
	var held: float = TARGETS[_target_index].time
	_clip_at = _clip_length - 0.02 if held < 0.0 else minf(held, _clip_length - 0.02)
	# Held by a zero speed rather than paused: a paused player reports no
	# current_animation, and the modifier only comes on while its clip plays.
	_anim.play(_clip())
	_anim.speed_scale = 0.0
	_anim.seek(_clip_at, true)
	return true

func _clip() -> StringName:
	return TARGETS[_target_index].clip

func _modifier() -> String:
	return TARGETS[_target_index].get("modifier", "")

func _is_bake() -> bool:
	return TARGETS[_target_index].has("bake")

func _working_path() -> String:
	return "%s/%s.json" % [WORKING_DIR, TARGETS[_target_index].label]

## A correction scoped to the held clip, made here and never saved. Placed
## straight after the body's own pose corrections, so it runs before the
## spring simulators the way they do.
func _make_lab_modifier() -> BonePoseOffset:
	var node := BonePoseOffset.new()
	node.name = "PoseLabOffset"
	node.clips = [String(_clip())]
	node.blend_time = 0.0
	var saved := FileAccess.get_file_as_string(_working_path())
	if not saved.is_empty():
		var parsed = JSON.parse_string(saved)
		if parsed is Dictionary:
			var rotations: Dictionary[String, Vector3] = {}
			for bone in parsed:
				var v: Array = parsed[bone]
				rotations[bone] = Vector3(v[0], v[1], v[2])
			node.rotations = rotations
	_skeleton.add_child(node)
	var lying := _skeleton.get_node_or_null("LyingPose")
	if lying != null:
		_skeleton.move_child(node, lying.get_index() + 1)
	return node

func _merge_libraries(libraries: Array[PackedScene]) -> void:
	var library: AnimationLibrary
	if _anim.has_animation_library(""):
		library = _anim.get_animation_library("")
	else:
		library = AnimationLibrary.new()
		_anim.add_animation_library("", library)
	for packed in libraries:
		if packed == null:
			continue
		var source_scene := packed.instantiate()
		var source := _find(source_scene, "AnimationPlayer") as AnimationPlayer
		if source != null:
			for clip_name in source.get_animation_list():
				if not library.has_animation(clip_name):
					library.add_animation(clip_name, source.get_animation(clip_name).duplicate())
		source_scene.free()

func _find(root: Node, type_name: String) -> Node:
	var queue: Array[Node] = [root]
	while not queue.is_empty():
		var node: Node = queue.pop_front()
		if node.is_class(type_name):
			return node
		queue.append_array(node.get_children())
	return null

# --- UI -----------------------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.anchor_bottom = 1.0
	panel.offset_left = 8.0
	panel.offset_top = 8.0
	panel.offset_bottom = -8.0
	panel.custom_minimum_size = Vector2(430.0, 0.0)
	layer.add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)

	var top := HBoxContainer.new()
	column.add_child(top)
	var target := OptionButton.new()
	for entry in TARGETS:
		target.add_item(entry.label)
	target.selected = _target_index
	target.item_selected.connect(func(index: int) -> void:
		_target_index = index
		get_tree().reload_current_scene())
	top.add_child(target)
	_mirror = CheckBox.new()
	_mirror.text = "左右联动"
	_mirror.button_pressed = true
	top.add_child(_mirror)
	var save := Button.new()
	save.text = "保存"
	save.pressed.connect(_save)
	top.add_child(save)
	var reset := Button.new()
	reset.text = "全部归零"
	reset.pressed.connect(_reset_all)
	top.add_child(reset)

	var time_row := HBoxContainer.new()
	column.add_child(time_row)
	var time_label := Label.new()
	time_label.text = "片段时间"
	time_row.add_child(time_label)
	var time := HSlider.new()
	time.min_value = 0.0
	time.max_value = _clip_length - 0.02
	time.step = 0.01
	time.value = _clip_at
	time.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	time.value_changed.connect(func(v: float) -> void:
		_clip_at = v
		_anim.seek(v, true))
	time_row.add_child(time)

	var meshes := HFlowContainer.new()
	column.add_child(meshes)
	for node in _skeleton.get_children():
		if not node is MeshInstance3D or not (node as MeshInstance3D).visible:
			continue
		var mesh := node as MeshInstance3D
		var toggle := CheckBox.new()
		toggle.text = mesh.name
		toggle.button_pressed = not HIDDEN_AT_START.has(String(mesh.name))
		mesh.visible = toggle.button_pressed
		toggle.toggled.connect(func(on: bool) -> void: mesh.visible = on)
		meshes.add_child(toggle)

	_readout = Label.new()
	column.add_child(_readout)
	_status = Label.new()
	column.add_child(_status)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for bone in BONES:
		if _skeleton.find_bone(bone) < 0:
			continue
		_add_bone_rows(list, bone)

func _add_bone_rows(list: VBoxContainer, bone: String) -> void:
	var header := Label.new()
	header.text = bone
	header.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4))
	list.add_child(header)
	var current: Vector3 = _pose.rotations.get(bone, Vector3.ZERO)
	var sliders: Array[HSlider] = []
	for axis in 3:
		var row := HBoxContainer.new()
		list.add_child(row)
		var name_label := Label.new()
		name_label.text = ["  X", "  Y", "  Z"][axis]
		name_label.custom_minimum_size = Vector2(28.0, 0.0)
		row.add_child(name_label)
		var slider := HSlider.new()
		slider.min_value = -ANGLE_LIMIT
		slider.max_value = ANGLE_LIMIT
		slider.step = 1.0
		slider.value = current[axis]
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(slider)
		var value := SpinBox.new()
		value.min_value = -ANGLE_LIMIT
		value.max_value = ANGLE_LIMIT
		value.step = 1.0
		value.value = current[axis]
		value.custom_minimum_size = Vector2(90.0, 0.0)
		row.add_child(value)
		slider.value_changed.connect(func(v: float) -> void:
			value.set_value_no_signal(v)
			_on_slider(bone))
		value.value_changed.connect(func(v: float) -> void:
			slider.value = v)
		sliders.append(slider)
	_sliders[bone] = sliders

func _vector_of(bone: String) -> Vector3:
	var s: Array = _sliders[bone]
	return Vector3(s[0].value, s[1].value, s[2].value)

func _set_vector(bone: String, v: Vector3) -> void:
	if not _sliders.has(bone):
		return
	var s: Array = _sliders[bone]
	for axis in 3:
		s[axis].value = v[axis]

## Mirrored across the body's midline: a turn about X (across the body) is the
## same on both sides, turns about Y and Z swap sign.
func _mirror_name(bone: String) -> String:
	if bone.begins_with("Left"):
		return "Right" + bone.substr(4)
	if bone.begins_with("Right"):
		return "Left" + bone.substr(5)
	if bone.ends_with(".L"):
		return bone.trim_suffix(".L") + ".R"
	if bone.ends_with(".R"):
		return bone.trim_suffix(".R") + ".L"
	return ""

func _on_slider(bone: String) -> void:
	if _syncing:
		return
	var v := _vector_of(bone)
	var other := _mirror_name(bone)
	if _mirror.button_pressed and other != "":
		_syncing = true
		_set_vector(other, Vector3(v.x, -v.y, -v.z))
		_syncing = false
	_push()

func _push() -> void:
	var rotations: Dictionary[String, Vector3] = {}
	for bone in _sliders:
		var v := _vector_of(bone)
		if not v.is_zero_approx():
			rotations[bone] = v
	_pose.rotations = rotations

func _reset_all() -> void:
	_syncing = true
	for bone in _sliders:
		_set_vector(bone, Vector3.ZERO)
	_syncing = false
	_push()

# --- save ---------------------------------------------------------------------

func _format_rotations(newline: String) -> String:
	var keys: Array = _pose.rotations.keys()
	keys.sort()
	var lines: PackedStringArray = []
	for bone in keys:
		var v: Vector3 = _pose.rotations[bone]
		lines.append("\"%s\": Vector3(%s, %s, %s)" % [bone, _num(v.x), _num(v.y), _num(v.z)])
	if lines.is_empty():
		return "rotations = Dictionary[String, Vector3]({})"
	return "rotations = Dictionary[String, Vector3]({" + newline \
		+ (","  + newline).join(lines) + newline + "})"

func _num(f: float) -> String:
	return str(int(f)) if is_equal_approx(f, roundf(f)) else str(f)

func _save() -> void:
	if _is_bake():
		_bake_requested = true
		return
	_save_rotations()

## Rewrites the `rotations` block under the target's node in the body scene,
## keeping the file's own line endings (the body scene is CRLF).
func _save_rotations() -> void:
	var path := _body.scene_file_path
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		_status.text = "读不到 %s" % path
		return
	var newline := "\r\n" if text.contains("\r\n") else "\n"
	var block := _format_rotations(newline)
	DisplayServer.clipboard_set(block)
	var header := "[node name=\"%s\"" % _modifier()
	var at := text.find(header)
	if at < 0:
		_status.text = "场景里没有 %s 节点，已复制到剪贴板" % _modifier()
		return
	var next_node := text.find(newline + "[", at + header.length())
	if next_node < 0:
		next_node = text.length()
	var section := text.substr(at, next_node - at)
	var re := RegEx.create_from_string("rotations = Dictionary\\[String, Vector3\\]\\(\\{[^}]*\\}\\)")
	var found := re.search(section)
	var updated: String
	if found != null:
		updated = section.substr(0, found.get_start()) + block + section.substr(found.get_end())
	else:
		updated = section.rstrip("\r\n") + newline + block + newline
	var out := FileAccess.open(path, FileAccess.WRITE)
	if out == null:
		_status.text = "写不进 %s，已复制到剪贴板" % path
		return
	out.store_string(text.substr(0, at) + updated + text.substr(next_node))
	out.close()
	_status.text = "已保存到 %s 并复制到剪贴板" % path.get_file()
	print(block)

## Set by "保存" on a bake target; the bake itself runs from
## _on_skeleton_updated(), the only moment the corrected pose can be read.
var _bake_requested := false
## Whether the camera has been pointed at the hips yet. Once, on the first
## pose: a held frame from a flip is well off the floor.
var _framed := false

## Writes the frame on screen as a one-frame clip into BAKE_PATH, one key per
## track the held clip has, so the baked clip animates exactly the bones the
## pack does and leaves the rest (springs, the spliced chest) to the body.
func _bake() -> void:
	var clip_name: StringName = TARGETS[_target_index].bake
	var source := _anim.get_animation(_clip())
	var baked := Animation.new()
	baked.length = 0.1
	baked.loop_mode = Animation.LOOP_LINEAR
	for track in source.get_track_count():
		var type := source.track_get_type(track)
		if type != Animation.TYPE_POSITION_3D and type != Animation.TYPE_ROTATION_3D \
				and type != Animation.TYPE_SCALE_3D:
			continue
		var path := source.track_get_path(track)
		var bone := _skeleton.find_bone(path.get_concatenated_subnames())
		if bone < 0:
			continue
		var pose := _skeleton.get_bone_global_pose(bone)
		var parent := _skeleton.get_bone_parent(bone)
		if parent >= 0:
			pose = _skeleton.get_bone_global_pose(parent).affine_inverse() * pose
		var index := baked.add_track(type)
		baked.track_set_path(index, path)
		match type:
			Animation.TYPE_POSITION_3D:
				baked.position_track_insert_key(index, 0.0, pose.origin)
			Animation.TYPE_ROTATION_3D:
				baked.rotation_track_insert_key(index, 0.0, pose.basis.get_rotation_quaternion())
			Animation.TYPE_SCALE_3D:
				baked.scale_track_insert_key(index, 0.0, pose.basis.get_scale())
	var root: Node3D
	if ResourceLoader.exists(BAKE_PATH):
		root = (load(BAKE_PATH) as PackedScene).instantiate() as Node3D
	else:
		root = Node3D.new()
		root.name = "BeriulPoses"
		var player := AnimationPlayer.new()
		player.name = "AnimationPlayer"
		root.add_child(player)
		player.owner = root
		player.add_animation_library("", AnimationLibrary.new())
	var library := (root.get_node("AnimationPlayer") as AnimationPlayer).get_animation_library("")
	if library.has_animation(clip_name):
		library.remove_animation(clip_name)
	library.add_animation(clip_name, baked)
	var packed := PackedScene.new()
	packed.pack(root)
	var error := ResourceSaver.save(packed, BAKE_PATH)
	root.free()
	DirAccess.make_dir_recursive_absolute(WORKING_DIR)
	var working := {}
	for bone in _pose.rotations:
		var v: Vector3 = _pose.rotations[bone]
		working[bone] = [v.x, v.y, v.z]
	var out := FileAccess.open(_working_path(), FileAccess.WRITE)
	if out != null:
		out.store_string(JSON.stringify(working, "\t"))
		out.close()
	if error == OK:
		_status.text = "已烘焙为 %s -> %s" % [clip_name, BAKE_PATH.get_file()]
	else:
		_status.text = "烘焙失败：%s" % error_string(error)

# --- readout and camera -------------------------------------------------------

func _on_skeleton_updated() -> void:
	if _bake_requested:
		_bake_requested = false
		_bake()
	if not _framed:
		_framed = true
		var hips := _skeleton.find_bone("Hips")
		if hips >= 0:
			_pivot.position = _skeleton.global_transform * _skeleton.get_bone_global_pose(hips).origin
	if _readout == null:
		return
	var parts: PackedStringArray = []
	for bone in PROBES:
		var index := _skeleton.find_bone(bone)
		if index < 0:
			continue
		var world := _skeleton.global_transform * _skeleton.get_bone_global_pose(index).origin
		parts.append("%s %.2f" % [bone, world.y])
	_readout.text = "离地高度 (m): " + "  ".join(parts)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_RIGHT:
			_orbiting = button.pressed
		elif button.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = button.pressed
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = maxf(_distance * 0.9, 0.6)
			_place_camera()
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = minf(_distance * 1.1, 10.0)
			_place_camera()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _orbiting:
			_yaw -= motion.relative.x * 0.008
			_pitch = clampf(_pitch - motion.relative.y * 0.008, -1.5, 0.4)
			_place_camera()
		elif _panning:
			var right := _camera.global_basis.x
			var up := _camera.global_basis.y
			_pivot.position += (-right * motion.relative.x + up * motion.relative.y) * 0.002 * _distance
			_place_camera()

func _place_camera() -> void:
	_pivot.rotation = Vector3(_pitch, _yaw, 0.0)
	_camera.position = Vector3(0.0, 0.0, _distance)
	# Shifted so the body sits right of the slider panel, not behind it.
	_camera.h_offset = -0.3 * _distance
