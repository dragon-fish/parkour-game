extends TestCase

# Drives the REAL Player through CharacterAnimator's three cases and checks
# where the AnimationTree's own state machine actually landed -- through the
# real node wiring (Player -> CharacterAnimator -> AnimationTree.travel()),
# not by calling _target_animation() directly. A broken NodePath, a tree
# left inactive, or a transition graph that still races itself to "End" (see
# tools/build_player_scene.gd's own note on why advance_mode must not be
# AUTO) would all fail this test exactly as they would fail the running
# game; calling the mapping function directly would have caught none of
# them.

# The owner's full reported clip set (see the animation-vocabulary report):
# idle/run/jump plus the three real matches this task adds. A literal here,
# not a reference to player.gd's own _KNOWN_ANIMATION_CLIPS -- these tests
# are pinning the PUBLIC clip names the mapping promises, and a typo in one
# list must be able to disagree with the other and fail loudly, rather than
# both drifting together silently.
const _FULL_CLIP_SET: PackedStringArray = [
	"idle", "run", "jump", "sneak", "sneaking", "ladder_stillness",
]
# The near-universal three, with none of the YSM/Blockbench-specific clips --
# what a body from a completely different asset pipeline looks like.
const _REDUCED_CLIP_SET: PackedStringArray = ["idle", "run", "jump"]

func _spawn() -> Dictionary:
	return await _spawn_with_clips(_REDUCED_CLIP_SET)

## Same shape as _spawn(), but with an explicit clip list -- lets fallback
## tests build a body missing some (or all) of the clips
## character_animator.gd's priority lists reach for.
func _spawn_with_clips(clips: PackedStringArray) -> Dictionary:
	var cfg := MovementConfig.new()
	# A stub body, not the owner's real (untracked, CC BY-NC-SA) model -- see
	# JOB 1's report. TestWorld.build_stub_body(with_animation_player=true)
	# gives Player._wire_body_animation() a real "AnimationPlayer" child with
	# `clips` to wire the SAME AnimationTree/CharacterAnimator graph against,
	# so these tests still exercise the real node wiring (Player ->
	# CharacterAnimator -> AnimationTree.travel()) end to end, just without
	# needing the licensed asset to exist on whatever machine runs this suite.
	var world := TestWorld.build(tree, cfg, TestWorld.build_stub_body("", Vector3.ZERO, true, clips))
	await step(1)
	TestWorld.place(world)
	await step(30)
	return world

## Hand-places the player against a tall block and forces a grab, the same
## way tests/test_ledge.gd's test_mantling_completes_from_the_top_of_the_
## grab_range does -- feet placed within ledge_reach of the block's near
## face, well clear of the floor, so ledge_query() reads a genuine valid grab
## rather than one this helper merely asserts into existence. Returns the
## block so the caller can free it during teardown.
func _grab_ledge(world: Dictionary) -> Node3D:
	var player: Player = world["player"]
	var block := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8.0, 6.0, 4.0)
	shape.shape = box
	block.add_child(shape)
	tree.root.add_child(block)
	await step(1)
	block.global_position = Vector3(0.0, 3.0, -6.0)
	await step(1)

	# Feet at world y = 6.0 (edge) - 2.75 = 3.25, well clear of the floor;
	# within ledge_reach (1.0 m default) of the block's near face (z = -4.0).
	player.global_position = Vector3(0.0, 3.25 + player.standing_height() * 0.5, -3.5)
	await step(1)

	var query: Dictionary = player.probes.ledge_query()
	check(query["valid"], "precondition: this hand-placed position should read as a valid ledge grab")

	player.state_machine.start(PlayerState.LEDGE)
	await step(1)
	check(player.state_machine.current_name == PlayerState.LEDGE, \
		"precondition: should be hanging, got %s" % player.state_machine.current_name)

	# Reset to a NEUTRAL baseline before returning. The hover teleport above
	# gives GroundState's own physics_update() one tick to notice the player
	# is no longer on a floor and hand off to Air, BEFORE state_machine.start()
	# forcibly overrides that back to Ledge -- which leaves the clip already
	# at "jump" from that transient Air tick, for a reason that has nothing to
	# do with LEDGE's own animation mapping. Without this reset, a caller
	# checking for "jump" during the hang phase could pass on that leftover
	# alone even with LEDGE's own fallback completely broken -- caught
	# exactly that way while bite-proofing this file's
	# test_ledge_hang_falls_back_to_jump_when_ladder_stillness_is_unavailable,
	# which read as passing under a defect that removed the fallback entirely.
	# "idle" is always present: both _REDUCED_CLIP_SET and _FULL_CLIP_SET (the
	# only two callers of this helper) carry it.
	var anim_tree := player.get_node("BodyRoot/AnimationTree") as AnimationTree
	var playback: AnimationNodeStateMachinePlayback = anim_tree.get("parameters/playback")
	playback.travel(&"idle")
	await step(2)
	return block

func _current_clip(player: Player) -> StringName:
	var anim_tree := player.get_node("BodyRoot/AnimationTree") as AnimationTree
	var playback: AnimationNodeStateMachinePlayback = anim_tree.get("parameters/playback")
	return playback.get_current_node()

func test_standing_still_plays_idle() -> void:
	var world := await _spawn()
	var player: Player = world["player"]
	check(player.state_machine.current_name == PlayerState.GROUND, \
		"precondition: player should have settled into Ground, got %s" % player.state_machine.current_name)
	check(player.horizontal_speed() < player.config.run_animation_speed_threshold, \
		"precondition: a freshly settled player should be at rest")

	# A few ticks for CharacterAnimator's travel() request to actually apply.
	await step(5)
	check(_current_clip(player) == &"idle", \
		"standing still did not select idle, playing %s" % _current_clip(player))

	TestWorld.teardown(world)
	await step(1)

func test_running_above_the_threshold_plays_run() -> void:
	var world := await _spawn()
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]

	input.state.move = Vector2(0.0, 1.0)
	# No sprint key: forward input alone already reaches ground_speed.
	await step(30)
	check(player.state_machine.current_name == PlayerState.GROUND, \
		"precondition: running on flat ground should stay in Ground, got %s" % player.state_machine.current_name)
	check_greater(player.horizontal_speed(), player.config.run_animation_speed_threshold, \
		"precondition: the player should be moving above the run threshold")

	await step(5)
	check(_current_clip(player) == &"run", \
		"moving above the threshold did not select run, playing %s" % _current_clip(player))

	TestWorld.teardown(world)
	await step(1)

func test_airborne_plays_jump() -> void:
	var world := await _spawn()
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]

	input.press_jump()
	await step(2)
	check(player.state_machine.current_name == PlayerState.AIR, \
		"precondition: pressing jump should leave the player airborne, got %s" % player.state_machine.current_name)

	await step(5)
	check(_current_clip(player) == &"jump", \
		"being airborne did not select jump, playing %s" % _current_clip(player))

	TestWorld.teardown(world)
	await step(1)

## The real mapping: crouch STILL and crouch WALKING are two different clips
## in the owner's reported vocabulary (sneaking / sneak respectively), told
## apart by the exact same speed threshold GROUND already uses for
## idle-versus-run. Forces Crouch directly via state_machine.start(), the
## same pattern tests/test_crouch_state.gd already uses (CrouchState is
## reached today only from a decayed Slide -- see its own header comment --
## and re-deriving one here would only obscure what this test is actually
## checking).
func test_crouch_still_plays_sneaking_and_crouch_moving_plays_sneak() -> void:
	var world := await _spawn_with_clips(_FULL_CLIP_SET)
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]

	input.state.crouch_held = true
	player.state_machine.start(PlayerState.CROUCH)
	await step(5)
	check(player.state_machine.current_name == PlayerState.CROUCH, \
		"precondition: forcing Crouch with crouch_held true should hold, got %s" % player.state_machine.current_name)
	check(player.horizontal_speed() < player.config.run_animation_speed_threshold, \
		"precondition: a freshly forced crouch with no move input should be at rest")
	check(_current_clip(player) == &"sneaking", \
		"crouching still did not select sneaking, playing %s" % _current_clip(player))

	input.state.move = Vector2(0.0, 1.0)
	await step(30)
	check(player.state_machine.current_name == PlayerState.CROUCH, \
		"precondition: crouch-walking on flat ground should stay in Crouch, got %s" % player.state_machine.current_name)
	check_greater(player.horizontal_speed(), player.config.run_animation_speed_threshold, \
		"precondition: crouch-walking forward should cross the run threshold")

	await step(5)
	check(_current_clip(player) == &"sneak", \
		"crouch-walking did not select sneak, playing %s" % _current_clip(player))

	TestWorld.teardown(world)
	await step(1)

## The fallback chain, not the real mapping: a body with only the
## near-universal three must still land on something it actually has while
## crouch-walking, rather than travel()ing to "sneak" -- a name its graph
## does not carry, which is a real engine error (see character_animator.gd's
## _has_clip() comment), not a graceful miss.
func test_crouch_moving_falls_back_to_run_when_sneak_is_unavailable() -> void:
	var world := await _spawn_with_clips(_REDUCED_CLIP_SET)
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]

	input.state.crouch_held = true
	input.state.move = Vector2(0.0, 1.0)
	player.state_machine.start(PlayerState.CROUCH)
	await step(30)
	check(player.state_machine.current_name == PlayerState.CROUCH, \
		"precondition: forcing Crouch with crouch_held true should hold, got %s" % player.state_machine.current_name)
	check_greater(player.horizontal_speed(), player.config.run_animation_speed_threshold, \
		"precondition: crouch-walking forward should cross the run threshold")

	await step(5)
	check(_current_clip(player) == &"run", \
		"a body without sneak should fall back to run while crouch-walking, playing %s" % _current_clip(player))

	TestWorld.teardown(world)
	await step(1)

## The real mapping's other half: hanging on a ledge gets ladder_stillness
## (a genuine match -- "hanging on a ladder" suits a ledge hang exactly), but
## the mantle sub-phase still has no real match and keeps the old jump
## placeholder -- see character_animator.gd's LEDGE case for why. Checked in
## one test, in sequence, specifically to pin that the SAME ledge stint
## changes clip the instant it starts mantling.
func test_ledge_hang_plays_ladder_stillness_then_mantle_keeps_the_jump_placeholder() -> void:
	var world := await _spawn_with_clips(_FULL_CLIP_SET)
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	var block := await _grab_ledge(world)

	await step(5)
	check(_current_clip(player) == &"ladder_stillness", \
		"hanging did not select ladder_stillness, playing %s" % _current_clip(player))

	input.state.move = Vector2(0.0, 1.0)
	await step(2)
	var ledge_state = player.state_machine.state_for(PlayerState.LEDGE)
	check(ledge_state != null and ledge_state.is_mantling(), \
		"precondition: pushing forward while hanging should start the mantle")

	await step(5)
	check(_current_clip(player) == &"jump", \
		"mantling did not keep the jump placeholder, playing %s" % _current_clip(player))

	block.queue_free()
	TestWorld.teardown(world)
	await step(1)

## The fallback chain for LEDGE: a body without ladder_stillness must still
## land on the old jump placeholder while hanging, not on a name its graph
## does not carry.
func test_ledge_hang_falls_back_to_jump_when_ladder_stillness_is_unavailable() -> void:
	var world := await _spawn_with_clips(_REDUCED_CLIP_SET)
	var player: Player = world["player"]
	var block := await _grab_ledge(world)

	await step(5)
	check(_current_clip(player) == &"jump", \
		"a body without ladder_stillness should fall back to jump while hanging, playing %s" % _current_clip(player))

	block.queue_free()
	TestWorld.teardown(world)
	await step(1)

## The far end of the fallback chain: a body whose AnimationPlayer exists but
## carries NONE of the clips character_animator.gd knows about -- distinct
## from tests/test_body_attachment.gd's "no AnimationPlayer at all" case,
## which never creates an AnimationTree/CharacterAnimator in the first place.
## Here both get created (there IS a real AnimationPlayer to wire against),
## but every travel() target this animator could ever ask for is missing, so
## _target_animation() must resolve to PlayerState.KEEP every tick and
## _physics_process() must skip travel() entirely -- calling it anyway would
## throw real engine ERROR lines every physics tick, which
## tools/run_tests.ps1 treats as a hard failure of the whole run regardless
## of what any single check() here asserts. The player's own movement, which
## depends on none of this, must be completely unaffected.
func test_a_body_with_no_recognised_clips_still_moves_without_erroring() -> void:
	var world := await _spawn_with_clips([])
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]

	var anim_tree := player.get_node_or_null("BodyRoot/AnimationTree") as AnimationTree
	check(anim_tree != null, "precondition: a body with an AnimationPlayer still gets an AnimationTree")

	var start := player.global_position
	input.state.move = Vector2(0.0, 1.0)
	# No sprint key: forward input alone already reaches ground_speed.
	await step(30)
	check_greater(player.global_position.distance_to(start), 0.5, \
		"a player with a clip-less body did not move")

	TestWorld.teardown(world)
	await step(1)
