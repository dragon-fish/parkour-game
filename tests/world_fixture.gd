class_name TestWorld
extends RefCounted

# Builds a minimal physics world: one large floor slab and one player driven
# by a ScriptedInputSource. Callers must await one physics frame after build()
# before touching global transforms.
#
# Filename deliberately does NOT start with "test_": tests/test_runner.gd
# discovers every tests/test_*.gd file and tries to run it as a TestCase.
# This is a RefCounted helper, not a TestCase, so it must stay outside that
# glob or the runner hangs trying to treat it as one.

## `body_scene`, if given, is set on the instanced Player's body_scene export
## BEFORE it enters the tree -- the same order a local, untracked override of
## player.tscn would set it in -- so Player._ready() attaches it exactly as
## it would in the real game. Left null (the default), a world has no body at
## all, which is what every EXISTING caller of this function wants: the
## committed player.tscn ships no model (see JOB 1's report), so this is not
## a special "bodyless" mode, it is simply what building a player from the
## real scene now does by default.
static func build(tree: SceneTree, cfg: MovementConfig, body_scene: PackedScene = null) -> Dictionary:
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
	floor_shape.shape = box
	floor_body.add_child(floor_shape)
	tree.root.add_child(floor_body)

	var player_scene: PackedScene = load("res://scenes/player/player.tscn")
	var player: Player = player_scene.instantiate()
	if body_scene != null:
		player.body_scene = body_scene
	tree.root.add_child(player)

	var input := ScriptedInputSource.new()
	player.setup(cfg, input)
	# The rig is present in the real scene, so give it the same config the
	# player got — otherwise its update_effects() no-ops and the tests exercise
	# a different code path than the game does.
	if player.camera_rig != null:
		player.camera_rig.setup(cfg)

	return {"player": player, "input": input, "floor": floor_body}

## Places the floor so its top surface is y = 0 and drops the player onto it.
## Must be called after at least one physics frame has elapsed.
static func place(world: Dictionary) -> void:
	world["floor"].global_position = Vector3(0.0, -0.5, 0.0)
	world["player"].global_position = Vector3(0.0, 0.95, 0.0)

## Same minimal world as build(), except the floor is TILTED about the X axis
## by `incline_rad` instead of flat. Exists because Friction's grade-driven
## walk/slide multipliers otherwise have no live-floor-geometry test at all:
## build()'s flat floor can only ever report grade 0 from Player.ground_grade(),
## whatever direction is asked of it. Task 9 deferred exactly this gap for
## ground_grade() itself for lack of a sloped fixture; this pays for both.
##
## Rotation convention matches ArenaBuilder._ramp()'s own (verified there
## empirically, reused here rather than re-derived): a POSITIVE incline_rad
## raises the floor's -Z end and lowers its +Z end. Since Player.wish_direction()
## turns ScriptedInputSource's default "move = (0, 1)" into world -Z on an
## unrotated player (see _run_up() callers across tests/test_slide.gd),
## running FORWARD climbs a positively-inclined slope here and running
## backward descends it.
##
## No place() counterpart: unlike the flat floor, the tilted slab's top-surface
## height at the origin depends on incline_rad, so callers settle the player
## themselves (a handful of physics_frame ticks after spawning it above the
## slab) rather than being handed an exact resting position.
static func build_on_slope(tree: SceneTree, cfg: MovementConfig, incline_rad: float) -> Dictionary:
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# Long along Z (the run/slide direction) and wide enough that steering
	# drift during a slide cannot walk the player off the side within the tick
	# counts any caller here runs for.
	box.size = Vector3(20.0, 1.0, 80.0)
	floor_shape.shape = box
	floor_body.add_child(floor_shape)
	floor_body.rotation.x = incline_rad
	tree.root.add_child(floor_body)

	var player_scene: PackedScene = load("res://scenes/player/player.tscn")
	var player: Player = player_scene.instantiate()
	tree.root.add_child(player)
	# Spawned above the slab near its rotation pivot (the world origin), close
	# enough that a short settle drops it onto the ramp rather than off an edge.
	player.global_position = Vector3(0.0, 1.5, 0.0)

	var input := ScriptedInputSource.new()
	player.setup(cfg, input)
	if player.camera_rig != null:
		player.camera_rig.setup(cfg)

	return {"player": player, "input": input, "floor": floor_body}

static func teardown(world: Dictionary) -> void:
	world["player"].queue_free()
	world["floor"].queue_free()

## Builds an in-memory PackedScene standing in for a real character body, for
## tests that need Player.body_scene to have SOMETHING attached without
## depending on the owner's licensed, untracked model (see JOB 1's report --
## the whole point of body_scene is that nothing committed, tests included,
## may require that model to exist).
##
## `head_name`, if non-empty, adds a plain Node3D child by that name at
## `head_local_position` -- a stand-in for whatever node
## Player._find_head_node() would match in a real body.
##
## `with_animation_player` adds a child literally named "AnimationPlayer"
## carrying empty animations, named after `clips`, in the DEFAULT ("")
## library, matching how the real asset's own AnimationPlayer exposes its
## clips (verified against it directly, see the JOB 2 report). Empty
## Animation resources are enough: CharacterAnimator only needs these clips
## to be SELECTABLE by name, never to contain real keyframes.
##
## `clips` defaults to the near-universal three (idle/jump/run) -- every
## EXISTING caller of this function wants exactly that stub, a body that
## looks like it came from an asset pipeline this project has always
## supported. Pass a different array (e.g. the owner's full reported set, or
## a subset, or an empty array) to build a stub for a body that carries more,
## fewer, or none of the clips character_animator.gd's fallback chains know
## about -- see tests/test_character_animator.gd's fallback coverage for why
## that matters: a body missing a clip must degrade, never error.
static func build_stub_body(head_name: String = "", head_local_position := Vector3.ZERO, \
		with_animation_player: bool = false, \
		clips: PackedStringArray = ["idle", "jump", "run"]) -> PackedScene:
	var root := Node3D.new()
	root.name = "StubBody"

	if with_animation_player:
		var anim_player := AnimationPlayer.new()
		anim_player.name = "AnimationPlayer"
		var library := AnimationLibrary.new()
		for clip_name in clips:
			var clip := Animation.new()
			clip.length = 1.0
			library.add_animation(clip_name, clip)
		anim_player.add_animation_library("", library)
		root.add_child(anim_player)
		anim_player.owner = root

	if head_name != "":
		var head := Node3D.new()
		head.name = head_name
		head.position = head_local_position
		root.add_child(head)
		head.owner = root

	var packed := PackedScene.new()
	var pack_error := packed.pack(root)
	root.free()
	assert(pack_error == OK, "TestWorld.build_stub_body: pack failed: %d" % pack_error)
	return packed
