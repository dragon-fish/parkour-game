class_name AnimationGallery
extends Node3D

# Every clip the attached body can play, all at once, on a grid.
#
# The packs ship 254 animations between them and the routing table names about
# forty. A name says nothing about whether a clip is the one a move wants --
# `SafetyVault` could be a hop or a dive, `GetOffWall_2m` could be a dismount or
# a fall -- and opening them one at a time in the editor is how an afternoon
# disappears. So: one body per clip, laid out in labelled rows, grouped by what
# the clip is for.
#
# Built at RUNTIME from a BodyProfile rather than saved as a scene full of
# instances, for the same reason player.tscn carries no body: the model and the
# packs are untracked and per-owner, and a committed scene that named them could
# not be opened by anyone else. This script is tracked; the two-node scene that
# points it at a profile is not.
#
# ⚠️ A viewer, not a test fixture. It instantiates the body once per clip, so
# the cost scales with the library -- see _handle_category_key() for the way out
# when that is more than the machine wants to do at once.

## The body and the animation packs to read. The same resource the Player uses,
## so the gallery cannot drift from what the game actually loads.
@export var profile: BodyProfile

@export_group("Layout")
@export var columns: int = 10
## Metres between neighbouring bodies.
@export var cell_size := Vector2(1.4, 2.0)
## Metres of clear space between one category block and the next.
@export var category_gap: float = 3.0
## Where a clip's name floats, in metres above the body's feet.
@export var label_height: float = 2.0
@export var category_label_height: float = 2.8

@export_group("Camera")
@export var move_speed: float = 6.0
@export var fast_multiplier: float = 4.0
@export var look_sensitivity: float = 0.003

## What goes where. Matched in ORDER against the START of the clip name, so the
## specific prefixes have to come before the general ones: NinjaJump_Idle is
## parkour rather than an idle, and it only lands there because Parkour is
## tested first.
##
## The groups are this project's own, not the packs'. What matters here is which
## of our Moves a clip could serve, so everything a parkour game will never call
## is swept into the last two buckets rather than sorted finely.
const CATEGORIES: Array = [
	# Turn* is here rather than in the "everything else" bucket it first landed
	# in, and finding it there is what this viewer is for: the packs ship real
	# Turn180_L/R and Turn90_L/R clips, and Move.TURN_180 has been borrowing the
	# run this whole time.
	["Locomotion", ["Walk", "Jog", "Sprint", "Run", "Turn"]],
	["Crouch and crawl", ["Crouch", "Crawl", "Sneak"]],
	["Parkour", ["Climb", "WallRun", "GetOffWall", "SafetyVault", "Vault",
		"Slide", "Roll", "NinjaJump", "DoubleJump", "Jump", "Dodge", "KipUp",
		"BackFlip", "LiftAir", "JogToFlip", "Swim", "StepUp"]],
	["Idle and pose", ["Idle", "A_TPose", "TPose", "Counter"]],
	["Combat and damage", ["Sword", "Melee", "Bow", "Pistol", "Punch", "Kick",
		"Shield", "Spell", "Hit", "Death", "Overhand", "Block", "Bandage"]],
	["Zombie", ["Zombie"]],
	["Props and chores", ["Farm", "Fish", "PickUp", "Sitting", "GroundSit",
		"Chest", "Consume", "Drink", "Interact", "Tree", "Driving", "Push",
		"IdleToLay", "LayToIdle", "Lay", "Fixing", "Dance", "Celebration",
		"Crying", "Yes", "No", "Sit"]],
]
const OTHER := "Everything else"

## One Node3D per category actually used, in the order they were built. Kept so
## the number keys can switch a whole block off.
var _groups: Array[Node3D] = []
var _camera: Camera3D
var _looking := false

func _ready() -> void:
	if profile == null or profile.scene == null:
		push_warning("AnimationGallery: no profile, or a profile with no scene.")
		return
	_build_environment()
	_build_camera()
	var library := _merged_library()
	if library == null:
		push_warning("AnimationGallery: the profile's libraries hold no animations.")
		return
	_build_grid(library)

# --- the animations -----------------------------------------------------------

## One library holding every clip from every pack the profile names, built ONCE
## and then shared by every body in the grid.
##
## Shared rather than merged per body, and the difference is not small: merging
## into each of 254 bodies would copy 254 clips 254 times over. An
## AnimationLibrary is a Resource and nothing here writes to it, so one serves
## the whole grid.
func _merged_library() -> AnimationLibrary:
	var library := AnimationLibrary.new()
	for packed in profile.animation_libraries:
		if packed == null:
			continue
		var source_scene: Node = packed.instantiate()
		if source_scene == null:
			continue
		var source := _find_animation_player(source_scene)
		if source != null:
			for clip_name in source.get_animation_list():
				if not library.has_animation(clip_name):
					library.add_animation(clip_name, source.get_animation(clip_name).duplicate())
		source_scene.free()
	if library.get_animation_list().is_empty():
		return null
	return library

## First AnimationPlayer anywhere under `node`. The packs put theirs at the
## root; a VRM puts its own one level down. Neither is worth assuming.
func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null

# --- the grid -----------------------------------------------------------------

func _build_grid(library: AnimationLibrary) -> void:
	var row_offset := 0.0
	for entry in _bucket(library.get_animation_list()):
		var title: String = entry[0]
		var clips: Array = entry[1]
		var group := Node3D.new()
		group.name = _node_name(title)
		add_child(group)
		_groups.append(group)
		var header := "%d. %s (%d)" % [_groups.size(), title, clips.size()]
		group.add_child(_label(header, Vector3(-cell_size.x, category_label_height, -row_offset), 0.012))
		for i in clips.size():
			var at := Vector3((i % columns) * cell_size.x, 0.0,
					-row_offset - (i / columns) * cell_size.y)
			var clip := String(clips[i])
			var cell := _cell(clip, at)
			group.add_child(cell)
			# AFTER add_child, not inside _cell: an AnimationPlayer outside the
			# tree has nothing to drive, and play() on one is silently ignored.
			_play(cell, clip, library)
		var rows: int = maxi(int(ceil(float(clips.size()) / float(columns))), 1)
		row_offset += rows * cell_size.y + category_gap

## One body, playing one clip, with its name over its head.
func _cell(clip: String, at: Vector3) -> Node3D:
	var cell := Node3D.new()
	cell.name = _node_name(clip)
	cell.position = at
	var body := profile.scene.instantiate() as Node3D
	# mount_offset is deliberately NOT applied: it places the body against a
	# capsule that is not here, and the model's own origin is already at its
	# feet. Rotation and scale ARE -- a body facing backwards, or built at the
	# wrong size, is a body you cannot read.
	body.rotation_degrees = profile.mount_rotation_degrees
	body.scale = Vector3.ONE * profile.mount_scale
	cell.add_child(body)
	cell.add_child(_label(clip, Vector3(0.0, label_height, 0.0), 0.006))
	return cell

## Starts the clip. Called after the cell is in the tree, because an
## AnimationPlayer outside it has nothing to drive.
func _play(cell: Node3D, clip: String, library: AnimationLibrary) -> void:
	var body := cell.get_child(0)
	var anim_player := _find_animation_player(body)
	if anim_player == null:
		anim_player = AnimationPlayer.new()
		body.add_child(anim_player)
	if anim_player.has_animation_library(""):
		anim_player.remove_animation_library("")
	anim_player.add_animation_library("", library)
	anim_player.play(clip)

## Splits the clip names into CATEGORIES order, alphabetical within each, with
## the empties dropped -- a category with nothing in it would still cost a
## header and a gap.
func _bucket(names: Array) -> Array:
	var sorted: Array = []
	for name in names:
		sorted.append(String(name))
	sorted.sort()
	var out: Array = []
	var taken := {}
	for entry in CATEGORIES:
		var clips: Array = []
		for name in sorted:
			if taken.has(name):
				continue
			for prefix in entry[1]:
				if name.begins_with(prefix):
					clips.append(name)
					taken[name] = true
					break
		if not clips.is_empty():
			out.append([entry[0], clips])
	var rest: Array = []
	for name in sorted:
		if not taken.has(name):
			rest.append(name)
	if not rest.is_empty():
		out.append([OTHER, rest])
	return out

func _label(text: String, at: Vector3, pixel_size: float) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.position = at
	label.pixel_size = pixel_size
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# Drawn through the bodies in front of it, or half the grid's names sit
	# behind somebody else's shoulder.
	label.no_depth_test = true
	label.outline_size = 8
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	return label

## Godot rejects a handful of characters in node names and silently rewrites
## them. Doing it here keeps the tree readable rather than full of `Idle@2`.
func _node_name(text: String) -> String:
	return text.replace(".", "").replace(":", "").replace("@", "").replace("/", "")

# --- somewhere to stand, and something to see with ----------------------------

func _build_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.13, 0.14, 0.16)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.6, 0.62, 0.68)
	environment.ambient_light_energy = 1.0
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45.0, -30.0, 0.0)
	add_child(sun)

func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.position = Vector3(6.0, 3.0, 6.0)
	_camera.rotation_degrees = Vector3(-10.0, 20.0, 0.0)
	_camera.far = 400.0
	_camera.current = true
	add_child(_camera)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		_looking = event.pressed
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _looking else Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and _looking:
		_camera.rotation.y -= event.relative.x * look_sensitivity
		_camera.rotation.x = clampf(_camera.rotation.x - event.relative.y * look_sensitivity, -1.5, 1.5)
	elif event is InputEventKey and event.pressed and not event.echo:
		_handle_category_key(event.keycode)

## Number keys isolate one category; 0 brings them all back. The way out when
## 254 animated bodies is more than the machine wants to do at once -- hidden
## AND unprocessed, because an AnimationPlayer nobody can see costs exactly as
## much as one they can.
func _handle_category_key(keycode: int) -> void:
	if keycode < KEY_0 or keycode > KEY_9:
		return
	var wanted := keycode - KEY_1
	for i in _groups.size():
		var shown: bool = keycode == KEY_0 or i == wanted
		_groups[i].visible = shown
		if shown:
			_groups[i].process_mode = Node.PROCESS_MODE_INHERIT
		else:
			_groups[i].process_mode = Node.PROCESS_MODE_DISABLED

func _process(delta: float) -> void:
	if _camera == null:
		return
	var wish := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		wish -= _camera.global_transform.basis.z
	if Input.is_key_pressed(KEY_S):
		wish += _camera.global_transform.basis.z
	if Input.is_key_pressed(KEY_A):
		wish -= _camera.global_transform.basis.x
	if Input.is_key_pressed(KEY_D):
		wish += _camera.global_transform.basis.x
	if Input.is_key_pressed(KEY_E):
		wish += Vector3.UP
	if Input.is_key_pressed(KEY_Q):
		wish -= Vector3.UP
	if wish == Vector3.ZERO:
		return
	var speed := move_speed
	if Input.is_key_pressed(KEY_SHIFT):
		speed *= fast_multiplier
	_camera.global_position += wish.normalized() * speed * delta
