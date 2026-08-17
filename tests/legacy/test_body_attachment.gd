extends TestCase

# Covers Player.body_scene: the runtime, licence-safe replacement for what
# tools/build_player_scene.gd used to bake directly into player.tscn (see
# JOB 1's report). Every fixture here is an in-memory stub body built by
# TestWorld.build_stub_body() or _pack() below -- never the owner's real,
# untracked, CC BY-NC-SA model -- so this whole file runs identically on any
# machine, with or without that asset on disk.

## Packs `root` into a PackedScene, setting `owner` on every descendant first
## (PackedScene.pack() only serialises nodes whose owner is the root being
## packed -- the same rule tools/build_player_scene.gd and arena_builder.gd
## both rely on). Frees `root` afterward: pack() only needs the live tree
## for the duration of the call itself.
func _pack(root: Node3D) -> PackedScene:
	_set_owner_recursive(root, root)
	var packed := PackedScene.new()
	var pack_error := packed.pack(root)
	root.free()
	assert(pack_error == OK, "test fixture pack failed: %d" % pack_error)
	return packed

func _set_owner_recursive(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		_set_owner_recursive(child, owner_node)

func test_body_scene_attaches_under_body_root() -> void:
	var cfg := MovementConfig.new()
	var stub := TestWorld.build_stub_body()
	var world := TestWorld.build(tree, cfg, stub)
	await step(1)

	var player: Player = world["player"]
	check(player.body != null, "body_scene did not attach")
	if player.body != null:
		check(player.body.get_parent() == player.get_node("BodyRoot"), \
			"the attached body must be a child of BodyRoot, got parent %s" % player.body.get_parent())

	TestWorld.teardown(world)
	await step(1)

## The other half of JOB 1's "everything downstream must tolerate a null
## body": a body that IS attached but carries no "AnimationPlayer" child is
## also a supported, silently animation-less configuration, not an error --
## and the player must still move under it, same as with no body at all.
func test_body_without_animation_player_degrades_without_animator() -> void:
	var cfg := MovementConfig.new()
	var stub := TestWorld.build_stub_body()  # no head, no AnimationPlayer
	var world := TestWorld.build(tree, cfg, stub)
	await step(1)

	var player: Player = world["player"]
	check(player.body != null, "precondition: a body must still attach")
	check(player.get_node_or_null("BodyRoot/AnimationTree") == null, \
		"a body with no AnimationPlayer must not get an AnimationTree wired")
	check(player.get_node_or_null("BodyRoot/CharacterAnimator") == null, \
		"a body with no AnimationPlayer must not get a CharacterAnimator wired")

	TestWorld.place(world)
	await step(1)
	var input: ScriptedInputSource = world["input"]
	var start := player.global_position
	input.state.move = Vector2(0.0, 1.0)
	# No sprint key: forward input alone already reaches ground_speed.
	await step(30)
	check_greater(player.global_position.distance_to(start), 0.5, \
		"a player with an animation-less body did not move")

	TestWorld.teardown(world)
	await step(1)

func test_body_with_animation_player_wires_character_animator() -> void:
	var cfg := MovementConfig.new()
	var stub := TestWorld.build_stub_body("", Vector3.ZERO, true)
	var world := TestWorld.build(tree, cfg, stub)
	await step(1)

	var player: Player = world["player"]
	var anim_tree := player.get_node_or_null("BodyRoot/AnimationTree") as AnimationTree
	check(anim_tree != null, "AnimationTree was not created for a body with an AnimationPlayer")
	var animator := player.get_node_or_null("BodyRoot/CharacterAnimator") as CharacterAnimator
	check(animator != null, "CharacterAnimator was not created for a body with an AnimationPlayer")
	if anim_tree != null and animator != null and player.body != null:
		check(animator.anim_tree == anim_tree, \
			"CharacterAnimator.anim_tree was not wired to the new AnimationTree")
		check(animator.player == player, "CharacterAnimator.player was not wired to the Player")
		check(anim_tree.root_node == anim_tree.get_path_to(player.body), \
			"AnimationTree.root_node was not wired to the attached body")

	TestWorld.teardown(world)
	await step(1)

## Regression test for the reported bug: glTF import leaves every clip at
## Animation.loop_mode == LOOP_NONE (verified directly against the real
## asset -- see the report), so idle/run held a state forever after playing
## once through instead of repeating. TestWorld.build_stub_body()'s clips
## reproduce that exact starting condition (LOOP_NONE, Animation's own class
## default) rather than a synthetic already-fixed one, so this actually
## exercises _wire_body_animation()'s fix.
func test_sustained_clips_are_forced_to_loop_but_jump_is_not() -> void:
	var cfg := MovementConfig.new()
	var stub := TestWorld.build_stub_body("", Vector3.ZERO, true)
	var world := TestWorld.build(tree, cfg, stub)
	await step(1)

	var player: Player = world["player"]
	check(player.body != null, "precondition: a body must attach")
	if player.body == null:
		TestWorld.teardown(world)
		await step(1)
		return

	var anim_player := player.body.get_node_or_null("AnimationPlayer") as AnimationPlayer
	check(anim_player != null, "precondition: the stub body has an AnimationPlayer")
	if anim_player == null:
		TestWorld.teardown(world)
		await step(1)
		return

	check(anim_player.get_animation("idle").loop_mode == Animation.LOOP_LINEAR, \
		"idle must be forced to loop -- a standing player must not freeze after one pass")
	check(anim_player.get_animation("run").loop_mode == Animation.LOOP_LINEAR, \
		"run must be forced to loop -- this is the exact bug reported")
	check(anim_player.get_animation("jump").loop_mode == Animation.LOOP_NONE, \
		"jump is a one-shot action clip and must be left exactly as imported")

	TestWorld.teardown(world)
	await step(1)

## The fix duplicates before mutating specifically because the SAME
## Animation resource object is shared across every instantiate() of one
## body_scene (verified directly, not assumed -- see the report): two
## players built from the identical stub PackedScene must not affect each
## other's loop_mode, and -- the more revealing half of this test -- the
## STILL-CACHED original clip a freshly-built third player reads must not
## have been mutated in place either.
func test_the_loop_fix_does_not_leak_into_other_instances_of_the_same_body() -> void:
	var cfg := MovementConfig.new()
	var stub := TestWorld.build_stub_body("", Vector3.ZERO, true)

	var world_a := TestWorld.build(tree, cfg, stub)
	await step(1)
	var world_b := TestWorld.build(tree, cfg, stub)
	await step(1)

	var player_a: Player = world_a["player"]
	var player_b: Player = world_b["player"]
	check(player_a.body != null and player_b.body != null, "precondition: both bodies must attach")
	if player_a.body == null or player_b.body == null:
		TestWorld.teardown(world_a)
		TestWorld.teardown(world_b)
		await step(1)
		return

	var ap_a := player_a.body.get_node("AnimationPlayer") as AnimationPlayer
	var ap_b := player_b.body.get_node("AnimationPlayer") as AnimationPlayer
	check(ap_a.get_animation("run") != ap_b.get_animation("run"), \
		"each attached body must own its OWN duplicated Animation resource, not share one")
	check(ap_b.get_animation("run").loop_mode == Animation.LOOP_LINEAR, \
		"player B's run clip was not fixed independently of player A's")

	TestWorld.teardown(world_a)
	TestWorld.teardown(world_b)
	await step(1)

	# A THIRD, freshly-instanced body from the same PackedScene, built only
	# after A and B have already been torn down: if either of them had
	# mutated the shared cached resource in place instead of duplicating,
	# this one would inherit that mutation despite never having been
	# touched by this test itself.
	var world_c := TestWorld.build(tree, cfg, stub)
	await step(1)
	var player_c: Player = world_c["player"]
	if player_c.body != null:
		var ap_c := player_c.body.get_node_or_null("AnimationPlayer") as AnimationPlayer
		if ap_c != null:
			check(ap_c.get_animation("run").loop_mode == Animation.LOOP_LINEAR, \
				"player C's own clip should also get the fix applied independently")
	TestWorld.teardown(world_c)
	await step(1)

## The real asset names its actual head mount "MHead", not "Head" outright
## (verified directly against it -- see the JOB 2 report), so an exact-name
## match would silently find nothing on the one body this whole feature was
## built for. This pins the substring behaviour directly, independent of
## whatever the real asset happens to be named today.
func test_head_node_discovery_matches_by_substring_not_exact_name() -> void:
	var cfg := MovementConfig.new()
	var root := Node3D.new()
	root.name = "StubBody"
	var torso := Node3D.new()
	torso.name = "Torso"
	root.add_child(torso)
	var head := Node3D.new()
	head.name = "MHead"
	head.position = Vector3(0.0, 0.3, 0.0)
	torso.add_child(head)
	var stub := _pack(root)

	var world := TestWorld.build(tree, cfg, stub)
	await step(1)

	var player: Player = world["player"]
	check(player.head_node != null, "no head node was found for a body with an 'MHead' node")
	if player.head_node != null:
		check(player.head_node.name == "MHead", \
			"the wrong node was selected as the head, got %s" % player.head_node.name)

	TestWorld.teardown(world)
	await step(1)

## The real asset ships a second, alternate-form hierarchy marked
## visible = false alongside its actual head -- a camera must never track a
## bone the player cannot currently see. Here the ONLY head-shaped node in
## the whole body is hidden behind one, so this also proves the search
## degrades to "no head found" rather than reaching into the hidden branch
## as a fallback.
func test_head_node_discovery_skips_hidden_branches() -> void:
	var cfg := MovementConfig.new()
	var root := Node3D.new()
	root.name = "StubBody"

	var hidden_form := Node3D.new()
	hidden_form.name = "AltForm"
	hidden_form.visible = false
	root.add_child(hidden_form)
	var hidden_head := Node3D.new()
	hidden_head.name = "Head"
	hidden_form.add_child(hidden_head)

	var visible_form := Node3D.new()
	visible_form.name = "MainForm"
	root.add_child(visible_form)
	var torso := Node3D.new()
	torso.name = "Torso"  # deliberately nothing head-shaped anywhere visible
	visible_form.add_child(torso)

	var stub := _pack(root)
	var world := TestWorld.build(tree, cfg, stub)
	await step(1)

	var player: Player = world["player"]
	check(player.head_node == null, \
		"a head node hidden behind visible = false must not be selected, got %s" \
			% (player.head_node.name if player.head_node != null else "null"))

	TestWorld.teardown(world)
	await step(1)

## End-to-end: a stub body's head node actually moves the camera through the
## real Player -> CameraRig wiring, not just through CameraRig's own unit
## tests (tests/test_camera_rig.gd calls set_head_position() directly and
## never exercises Player._find_head_node()/_physics_process() at all).
func test_head_follow_wires_through_player_to_camera() -> void:
	var cfg := MovementConfig.new()
	cfg.camera_head_follow_strength = 1.0
	var root := Node3D.new()
	root.name = "StubBody"
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0.4, 1.6, -0.1)
	root.add_child(head)
	var stub := _pack(root)

	var world := TestWorld.build(tree, cfg, stub)
	await step(1)
	TestWorld.place(world)
	await step(1)

	var player: Player = world["player"]
	check(player.head_node != null, "precondition: this stub body has a 'Head' node")
	check(player.camera_rig != null, "precondition: the real player.tscn always has a camera_rig")
	if player.head_node == null or player.camera_rig == null:
		TestWorld.teardown(world)
		await step(1)
		return

	# strength 1.0 makes the lerp exact (t=1.0 returns the target bit-for-bit,
	# same reasoning as t=0.0's exactness -- see CameraRig.update_effects()),
	# so this is a tight, not approximate, tolerance.
	var expected := player.to_local(player.head_node.global_position)
	check(player.camera_rig.position.distance_to(expected) < 0.001, \
		"camera did not follow the attached body's head through Player, got %s expected %s" \
			% [player.camera_rig.position, expected])

	TestWorld.teardown(world)
	await step(1)
