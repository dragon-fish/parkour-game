extends TestCase

const SCENE := "res://scenes/player/player.tscn"

## Substrings that must never appear in the committed player.tscn's own text.
## Each one identifies the owner's local, CC BY-NC-SA character model
## experiment (see JOB 1's report) -- a licence this project cannot carry.
## Matched against the raw FILE TEXT, not the loaded/instantiated scene: a
## structural check (e.g. "BodyRoot has no children") can only prove the
## GENERATOR'S current output is clean, not that nothing else -- a stray
## ext_resource nobody instances, a comment pasting in the path -- slipped
## into the committed file some other way. Reading the .tscn as text is a
## direct, format-level guarantee that survives however the file got there.
const FORBIDDEN_SUBSTRINGS := [
	"whine_fox",
	"大正女仆酒狐",
	"assets/models",
]

func test_player_scene_never_references_the_licensed_model() -> void:
	var file := FileAccess.open(SCENE, FileAccess.READ)
	check(file != null, "could not open %s to scan its text" % SCENE)
	if file == null:
		return
	var text := file.get_as_text()
	file.close()
	for needle in FORBIDDEN_SUBSTRINGS:
		check(text.find(needle) == -1, \
			"player.tscn's committed text contains %s -- a licensed asset reference leaked back in" % needle)

func test_player_scene_has_the_expected_structure() -> void:
	await step(1)
	check(ResourceLoader.exists(SCENE), "player.tscn was not generated")
	var packed: PackedScene = ResourceLoader.load(SCENE, "", ResourceLoader.CACHE_MODE_IGNORE)
	var player = packed.instantiate()
	tree.root.add_child(player)
	await step(1)

	check(player is CharacterBody3D, "root is not a CharacterBody3D")
	check(player.get_node_or_null("CollisionShape3D") != null, "CollisionShape3D missing")
	check(player.get_node_or_null("CameraRig") != null, "CameraRig missing")
	check(player.get_node_or_null("CameraRig/Camera3D") != null, "Camera3D missing")
	var body_root := player.get_node_or_null("BodyRoot")
	check(body_root != null, "BodyRoot (P5 reservation) missing")
	# The generator must never populate BodyRoot itself -- see JOB 1's report.
	# A future regeneration that quietly went back to baking a body straight
	# into player.tscn would pass every OTHER structural check here (BodyRoot
	# would still exist, still be a Node3D) while reintroducing exactly the
	# hard-committed licensing dependency this scene must not carry.
	if body_root != null:
		check(body_root.get_child_count() == 0, \
			"BodyRoot has %d child(ren) -- the generator must leave it empty, bodies attach at runtime via Player.body_scene" \
				% body_root.get_child_count())
	check(player.body_scene == null, \
		"player.tscn ships a body_scene default -- it must stay null so a fresh clone never tries to load one")
	# Fails open otherwise: Player.has_headroom() treats an absent probe as
	# "always clear" (so hand-built test players without one still work), so
	# a generator regression that silently dropped this node would make every
	# slide ignore ceilings with no test catching it.
	check(player.get_node_or_null("StandClearance") != null, "StandClearance (headroom probe) missing")

	# The exported reference must survive serialisation, or the camera silently
	# does nothing at runtime.
	check(player.camera_rig != null, "camera_rig export was not wired")
	check(player.camera_rig == player.get_node("CameraRig"), "camera_rig points at the wrong node")

	var capsule := (player.get_node("CollisionShape3D") as CollisionShape3D).shape as CapsuleShape3D
	check(capsule != null, "collision shape is not a capsule")
	check_approx(capsule.height, 1.8, 0.001, "capsule height wrong")
	check_approx(capsule.radius, 0.4, 0.001, "capsule radius wrong")

	# The probe is built from capsule.duplicate() in the generator specifically
	# so it cannot drift from the body's actual standing size — assert that
	# relationship rather than re-pinning the probe to its own 1.8/0.4 literal.
	var probe := player.get_node_or_null("StandClearance") as ShapeCast3D
	if probe != null:
		var probe_shape := probe.shape as CapsuleShape3D
		check(probe_shape != null, "StandClearance shape is not a capsule")
		if probe_shape != null:
			check_approx(probe_shape.height, capsule.height, 0.001, \
				"StandClearance capsule height must match the body's standing capsule")
			check_approx(probe_shape.radius, capsule.radius, 0.001, \
				"StandClearance capsule radius must match the body's standing capsule")

	player.queue_free()
	await step(1)

## The direct regression guard for JOB 1: a player instanced from the
## committed player.tscn -- exactly what every OTHER test in this suite
## already does via TestWorld.build(), and exactly what a fresh clone with no
## local model on disk gets -- must still move under ordinary input. This is
## the "still moves" half of the bite-proof; the "does not push errors" half
## is enforced by tools/run_tests.ps1 itself, which fails the whole run on
## any engine error line regardless of what check() below records -- so a
## regression that makes CharacterAnimator, or anything else downstream of a
## null body, error out during this test would fail the run even if every
## check() call here still happened to pass.
func test_player_scene_with_no_body_still_moves() -> void:
	var cfg := MovementConfig.new()
	var world := TestWorld.build(tree, cfg)
	await step(1)
	TestWorld.place(world)
	await step(1)

	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	check(player.body == null, "precondition: this world must not have a body attached")
	check(player.head_node == null, "precondition: a body-less player must have no head node")

	var start_position := player.global_position
	input.state.move = Vector2(0.0, 1.0)
	input.state.sprint_held = true
	await step(60)

	var travelled := player.global_position.distance_to(start_position)
	check_greater(travelled, 1.0, \
		"a body-less player travelled only %f m in one second of sprint input" % travelled)

	TestWorld.teardown(world)
	await step(1)
