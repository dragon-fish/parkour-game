class_name AnimationGallery
extends Node3D

# Every clip the attached body can play, on a labelled grid, ONE CATEGORY AT A
# TIME.
#
# The packs ship 253 animations between them and the routing table names about
# forty. A name tells you nothing about whether a clip is the one a move wants
# -- `SafetyVault` could be a hop or a dive, `GetOffWall_2m` could be a dismount
# or a fall -- and opening them one at a time in the editor is how an afternoon
# disappears.
#
# ⚠️ ONE CATEGORY, and that is not a preference. The first version built all 253
# at once and the owner's report was immediate: "way too laggy, one character is
# 40k tris." 253 x 40k is ten million triangles, which is not a viewer, it is a
# benchmark. So a category is built the first time it is asked for and not
# before, every category sits at the SAME origin rather than in a long row, and
# only one is ever in the tree's way. The largest is 79 bodies; most are under
# 40.
#
# Built at RUNTIME from a BodyProfile rather than saved as a scene full of
# instances, for the same reason player.tscn carries no body: the model and the
# packs are untracked and per-owner, so a committed scene naming them could not
# be opened by anyone else. This script is tracked; the two-node scene that
# points it at a profile is not.

## The body and the animation packs to read. The same resource the Player uses,
## so the gallery cannot drift from what the game actually loads.
@export var profile: BodyProfile

@export_group("Layout")
@export var columns: int = 10
## Metres between neighbouring bodies.
@export var cell_size := Vector2(1.4, 2.0)
## Where a clip's name floats, in metres above the body's feet.
@export var label_height: float = 2.0

@export_group("Camera")
@export var move_speed: float = 6.0
@export var fast_multiplier: float = 4.0
@export var look_sensitivity: float = 0.003

@export_group("Cost")
## Metres past which a body stops being DRAWN. Its skeleton still animates --
## this only spares the triangles, which at 40k a body is the half that hurts.
## Zero disables it.
@export var draw_distance: float = 40.0
## Build every category up front instead of on demand. Ten million triangles
## with this model; here for a smaller body, not for this one.
@export var eager: bool = false

## What goes where. Matched in ORDER against the START of the clip name, so the
## specific prefixes have to come before the general ones: NinjaJump_Idle is
## parkour rather than an idle, and it only lands there because Parkour is
## tested first.
##
## The groups are this project's own, not the packs'. What matters here is which
## of our Moves a clip could serve, so everything a parkour game will never call
## is swept into the last buckets rather than sorted finely.
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

## [[title, clips], ...] in display order, decided once in _ready().
var _buckets: Array = []
## One Node3D per bucket, added empty and filled on first view.
var _groups: Array[Node3D] = []
var _built: Array[bool] = []
var _current: int = 0
## Shared by every body ever built here -- see _merged_library().
var _library: AnimationLibrary
var _hud: Label
var _camera: Camera3D
var _looking := false

func _ready() -> void:
	if profile == null or profile.scene == null:
		push_warning("AnimationGallery: no profile, or a profile with no scene.")
		return
	_build_environment()
	_build_camera()
	_library = _merged_library()
	if _library == null:
		push_warning("AnimationGallery: the profile's libraries hold no animations.")
		return
	_buckets = _bucket(_library.get_animation_list())
	for entry in _buckets:
		var group := Node3D.new()
		group.name = _node_name(String(entry[0]))
		add_child(group)
		_groups.append(group)
		_built.append(false)
	_build_hud()
	if eager:
		for i in _buckets.size():
			_fill(i)
	_show(0)

# --- the animations -----------------------------------------------------------

## One library holding every clip from every pack the profile names, built ONCE
## and then shared by every body in the grid.
##
## Shared rather than merged per body, and the difference is not small: merging
## into each of 253 bodies would copy 253 clips 253 times over. An
## AnimationLibrary is a Resource and nothing here writes to it, so one serves
## them all.
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

## Fills one category's group with bodies. Called on first view, not up front.
func _fill(index: int) -> void:
	if _built[index]:
		return
	_built[index] = true
	var group := _groups[index]
	var clips: Array = _buckets[index][1]
	# EVERY CATEGORY AT THE SAME ORIGIN, since only one is ever visible. Laying
	# them end to end meant flying past four hundred metres of zombies to reach
	# the parkour.
	group.add_child(_label("%d. %s" % [index + 1, _buckets[index][0]],
			Vector3(-cell_size.x, label_height + 0.8, cell_size.y), 0.014))
	for i in clips.size():
		var clip := String(clips[i])
		var at := Vector3((i % columns) * cell_size.x, 0.0, -(i / columns) * cell_size.y)
		var cell := _cell(clip, at)
		group.add_child(cell)
		# AFTER add_child, not inside _cell: an AnimationPlayer outside the tree
		# has nothing to drive, and play() on one is silently ignored.
		_play(cell, clip)

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
	if draw_distance > 0.0:
		_limit_draw_distance(body)
	cell.add_child(_label(clip, Vector3(0.0, label_height, 0.0), 0.006))
	return cell

## Stops a body being DRAWN past draw_distance. The skeleton keeps animating --
## this is about the 40k triangles, which is the half that hurts.
func _limit_draw_distance(node: Node) -> void:
	if node is GeometryInstance3D:
		node.visibility_range_end = draw_distance
		node.visibility_range_end_margin = 4.0
	for child in node.get_children():
		_limit_draw_distance(child)

func _play(cell: Node3D, clip: String) -> void:
	var body := cell.get_child(0)
	var anim_player := _find_animation_player(body)
	if anim_player == null:
		anim_player = AnimationPlayer.new()
		body.add_child(anim_player)
	if anim_player.has_animation_library(""):
		anim_player.remove_animation_library("")
	anim_player.add_animation_library("", _library)
	anim_player.play(clip)

## Splits the clip names into CATEGORIES order, alphabetical within each, with
## the empties dropped.
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

# --- switching ----------------------------------------------------------------

## Builds the wanted category if this is its first view, then hides every other
## one -- hidden AND unprocessed, because an AnimationPlayer nobody can see
## costs exactly as much as one they can.
func _show(index: int) -> void:
	if index < 0 or index >= _groups.size():
		return
	_current = index
	_fill(index)
	for i in _groups.size():
		var shown: bool = i == index
		_groups[i].visible = shown
		if shown:
			_groups[i].process_mode = Node.PROCESS_MODE_INHERIT
		else:
			_groups[i].process_mode = Node.PROCESS_MODE_DISABLED
	_update_hud()

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
	_camera.position = Vector3(6.0, 3.0, 8.0)
	_camera.rotation_degrees = Vector3(-8.0, 0.0, 0.0)
	_camera.far = 400.0
	_camera.current = true
	add_child(_camera)

## The category list has to be on screen: with one category visible at a time,
## a viewer that does not say what the other keys do is a viewer showing one
## category.
func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(16.0, 12.0)
	_hud.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	_hud.add_theme_constant_override("outline_size", 6)
	layer.add_child(_hud)
	_update_hud()

func _update_hud() -> void:
	if _hud == null:
		return
	var lines: Array[String] = []
	for i in _buckets.size():
		var clips: Array = _buckets[i][1]
		var mark := ">" if i == _current else " "
		var loaded := "" if _built[i] else "   (not built yet)"
		lines.append("%s %d  %-20s %3d%s" % [mark, i + 1, _buckets[i][0], clips.size(), loaded])
	lines.append("")
	lines.append("1-9 category   RMB look   WASD move   Q/E down/up   Shift faster")
	_hud.text = "\n".join(lines)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		_looking = event.pressed
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _looking else Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and _looking:
		_camera.rotation.y -= event.relative.x * look_sensitivity
		_camera.rotation.x = clampf(_camera.rotation.x - event.relative.y * look_sensitivity, -1.5, 1.5)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode >= KEY_1 and event.keycode <= KEY_9:
			_show(event.keycode - KEY_1)

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
