class_name LevelZero
extends Node

# The tutorial's own chain, and nothing else: the lessons run out, the tower
# stands up, stepping onto it takes the plain away, and the orb at the top ends
# the level. Everything below this is either Arena's or TutorialDirector's.
#
# THE TOWER APPEARS IN FRONT OF THE BODY, not at a fixed spot. The plain is a
# torus: a body that has crossed a few boundaries is nowhere in particular, and
# a tower nailed to the world origin would ALSO give the wrap away, because
# every crossing would jump it a whole period sideways in his view. Standing it
# up where he is looking, at the moment the wrap retires, costs nothing and
# removes both problems.
#
# THE FLOOR DOES NOT USE THE CUBE SWARM. It is hundreds of metres across and
# would voxelise into millions of instances. It leaves the way the spec asks
# for instead: the sheet is painted the colour of the void behind it, which
# takes its surface away while its dot field is still there, and then the whole
# slab sinks -- so the light the floor turned into is still in view, further
# away every second, and reads as an altimeter. DO NOT reach for CubeSwarm here.

## Where the thanks page lives. The first level does not exist yet, so this is
## the tutorial's landing spot.
const THANKS_SCENE := "res://scenes/ui/thanks_for_playing.tscn"

@export var player: Player
@export var director: TutorialDirector
@export var wrap: TorusWrap
## The whole tower, hidden and intangible until the lessons run out.
@export var tower: Node3D
## The checkpoint at the tower's foot. Touching it is what starts the floor
## leaving -- one node, two consumers, so the save and the show cannot disagree
## about when the climb began.
@export var tower_checkpoint: Area3D
## The light at the summit. Touching it ends the level.
@export var orb: Area3D
@export var plain: StaticBody3D
@export var plain_mesh: MeshInstance3D
@export var plain_collision: CollisionShape3D

## How far ahead of the body the tower stands up. Far enough to see all of it,
## near enough to run to. Tuning value.
@export var tower_distance: float = 45.0

## What the sheet is painted as it goes: the colour of the void behind it, so
## a floor painted this has no edge left. Tuning value -- keep it equal to the
## level's own horizon colour.
##
## COLOUR IS NOT WHAT MAKES THE FLOOR VISIBLE, so this alone changes nothing.
## acrylic_void.tres already ships the horizon colour as its albedo; what the
## eye actually reads is the mirror -- metallic 0.9, roughness 0.04. The sheen
## is what has to go, and acrylic.gdshader writes no ALPHA, so there is nothing
## to fade instead. DO NOT "fix" a floor that will not leave by lengthening
## floor_fade_time; check that these three move together.
@export var void_colour: Color = Color(0.93, 0.96, 0.98)

## What the surface stops being as it goes. Flat and rough is a plane that
## reflects nothing, which against a void of the same colour is no plane at
## all. Tuning values.
@export var void_metallic: float = 0.0
@export var void_roughness: float = 1.0

## Seconds the surface takes to go. Tuning value.
@export var floor_fade_time: float = 3.0
## Seconds the dot field takes to sink, and how far it sinks. Tuning values.
@export var floor_drop_time: float = 6.0
@export var floor_drop_depth: float = 90.0
## What is left of the dots at the bottom. Zero puts them out entirely; a
## little is what leaves the player something to read his height against.
@export var floor_dots_remaining: float = 0.12

## Seam for the exit, same shape as MainMenu._change_scene and
## ThanksScreen._change_scene: a test observes the request without a real
## scene swap under GUT's runner.
var _change_scene: Callable = Callable(self, "_real_change_scene")

## Each of the three beats happens exactly once. The orb's volume is wider than
## the ball, and a checkpoint reports every entry, so all three are reachable
## twice by an ordinary player.
var _tower_up: bool = false
var _floor_leaving: bool = false
var _finished: bool = false

## The collision layer each of the tower's bodies had before it was hidden.
## Remembered rather than assumed: guessing a layer number here would quietly
## move the whole tower onto a layer nothing collides with.
var _tower_layers: Dictionary = {}

func _real_change_scene(path: String) -> void:
	get_tree().change_scene_to_file(path)

func _ready() -> void:
	if director != null:
		director.finished.connect(raise_tower)
	if tower != null:
		_remember_tower_layers()
		_set_tower_solid(false)
	if tower_checkpoint != null:
		tower_checkpoint.body_entered.connect(_on_tower_reached)
	if orb != null:
		orb.body_entered.connect(_on_orb_entered)

func _remember_tower_layers() -> void:
	for body in tower.find_children("*", "CollisionObject3D", true, false):
		_tower_layers[body] = (body as CollisionObject3D).collision_layer

func _set_tower_solid(solid: bool) -> void:
	tower.visible = solid
	for body in _tower_layers:
		if not is_instance_valid(body):
			continue
		(body as CollisionObject3D).collision_layer = _tower_layers[body] if solid else 0
		# AN AREA HAS TO BE SWITCHED OFF SEPARATELY. It finds bodies through its
		# MASK, so zeroing its layer leaves it watching: the checkpoint at the
		# foot of an invisible tower would save a respawn out in the middle of
		# the plain and take the floor away while the lessons are still running.
		if body is Area3D:
			(body as Area3D).monitoring = solid

## The lessons ran out. The tower stands up in front of the body and the wrap
## retires -- the two are one event, because a tower standing on a plain that
## still wraps is a tower that jumps a period sideways every crossing.
func raise_tower() -> void:
	if _tower_up or tower == null:
		return
	_tower_up = true
	if wrap != null:
		wrap.set_physics_process(false)
	if player != null:
		var forward: Vector3 = -player.global_transform.basis.z
		forward.y = 0.0
		if forward.length() < 0.001:
			forward = Vector3.FORWARD
		var here: Vector3 = player.global_position
		tower.global_position = Vector3(here.x, 0.0, here.z) \
			+ forward.normalized() * tower_distance
	_set_tower_solid(true)

## The first step onto the tower. Everything below is taken away.
func _on_tower_reached(_body: Node3D) -> void:
	if _floor_leaving:
		return
	_floor_leaving = true
	# BELT TO raise_tower()'s BRACE. The wrap is retired when the tower goes
	# up; a level whose director never announced it still must not teleport a
	# climbing body.
	if wrap != null:
		wrap.set_physics_process(false)
	_dissolve_floor()

func _dissolve_floor() -> void:
	# THE MATERIAL GATES ONLY THE FADE. Losing the floor and sinking the dots
	# are what let the player off the plain, and neither reads the material --
	# returning early on a mis-wired scene would leave a permanently solid
	# floor and say nothing about why.
	var material: ShaderMaterial = null
	if plain_mesh != null and plain_mesh.material_override is ShaderMaterial:
		# DUPLICATED FIRST. materials/acrylic_void.tres is shared with the
		# debug plain, and tweening the shared resource would repaint every
		# other scene that loads it in this session.
		material = (plain_mesh.material_override as ShaderMaterial).duplicate() as ShaderMaterial
		plain_mesh.material_override = material

	var tween := create_tween()
	if material != null:
		var from_colour: Color = material.get_shader_parameter("base_color")
		var from_metallic: float = float(material.get_shader_parameter("metallic_amount"))
		var from_roughness: float = float(material.get_shader_parameter("roughness_amount"))
		# THE SURFACE GOES FIRST AND THE DOTS STAY. It goes by losing its
		# sheen, not its colour -- see void_colour. The dots are what the floor
		# turns into, so they are still there when it starts to fall.
		tween.tween_method(func(k: float) -> void:
			material.set_shader_parameter("base_color", from_colour.lerp(void_colour, k))
			material.set_shader_parameter("metallic_amount", lerpf(from_metallic, void_metallic, k))
			material.set_shader_parameter("roughness_amount", lerpf(from_roughness, void_roughness, k)),
			0.0, 1.0, floor_fade_time)
	else:
		tween.tween_interval(floor_fade_time)
	# NOT BEFORE THE FADE. The player is standing on the tower's first platform
	# by now, but a body still crossing the last few metres of plain must not
	# drop through it mid-stride. Deferred because a body may be resting on
	# this shape in the physics step that is running.
	tween.tween_callback(func() -> void:
		if plain_collision != null:
			plain_collision.set_deferred("disabled", true))
	if plain != null:
		tween.tween_property(plain, "position:y",
			plain.position.y - floor_drop_depth, floor_drop_time) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	if material != null:
		var from_dots: float = float(material.get_shader_parameter("dot_opacity"))
		tween.parallel().tween_method(func(opacity: float) -> void:
			material.set_shader_parameter("dot_opacity", opacity),
			from_dots, floor_dots_remaining, floor_drop_time)

func _on_orb_entered(_body: Node3D) -> void:
	if _finished:
		return
	_finished = true
	ProgressStore.mark_tutorial_finished()
	# The replay request is spent the moment the tutorial is played again.
	ProgressStore.replay_requested = false
	if player != null:
		# The white spans several frames with the level still live underneath
		# it; nothing should be able to run off the summit during them.
		player.lock_input()
	# WHITE, per the transition-colour convention: this is a chosen ending, not
	# a death. Headless keeps the bare seam for the tests.
	if DisplayServer.get_name() == "headless":
		_change_scene.call(THANKS_SCENE)
		return
	PauseUi.run_white_transition(load(THANKS_SCENE), 0.9)
