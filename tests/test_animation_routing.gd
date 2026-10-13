extends ParkourTest

# Every Move decides what it looks like, rather than falling through to the
# default.
#
# The default's list is idle-first, so a move without a case did not merely get
# an approximate clip -- it got the STANDING one. A jump played the idle pose
# through its own take-off while Falling, one tick later, correctly played jump.
# Seven moves were in that state: Jump, FallUncontrolled, Landing, SkillRoll,
# IntoGrab, WallClimb and Turn180.

const TestWorld = preload("res://tests/world_fixture.gd")

var _world: Dictionary = {}

func after_each() -> void:
	if _world.is_empty():
		return
	if _world.has("line") and is_instance_valid(_world["line"]):
		_world["line"].queue_free()
	TestWorld.teardown(_world)
	_world = {}

## Synthetic body, so this never depends on the untracked model.
func _animator_with(clips: Array) -> CharacterAnimator:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var player: Player = _world["player"]
	var body := Node3D.new()
	body.name = "fake_body"
	var anim_player := AnimationPlayer.new()
	anim_player.name = "AnimationPlayer"
	var library := AnimationLibrary.new()
	for clip in clips:
		var animation := Animation.new()
		animation.length = 1.0
		library.add_animation(clip, animation)
	anim_player.add_animation_library("", library)
	body.add_child(anim_player)
	player.get_node("BodyRoot").add_child(body)
	player._wire_body_animation(body)
	return player.get_node("BodyRoot").get_node("CharacterAnimator")

func test_every_move_has_its_own_case() -> void:
	# The guard that keeps this from rotting: a Move added later and never
	# routed lands on the default, which is the standing pose.
	#
	# Compared against Move's own constants rather than a list repeated here,
	# so adding a Move is what makes this fail.
	var animator: CharacterAnimator = await _animator_with([&"idle"])
	var player: Player = _world["player"]
	var source: String = FileAccess.get_file_as_string( \
		"res://scripts/player/character_animator.gd")
	# ⚠️ READ OUT OF Move ITSELF, not repeated here. This list WAS a hand-copy,
	# sitting under a comment that claimed it was not -- so the protection it
	# promised did not exist, and Move.COIL was added without this test
	# noticing. Adding a Move now genuinely is what makes this fail.
	var missing: Array[String] = []
	var values: Dictionary = (Move as Script).get_script_constant_map()
	for name in _move_constant_names():
		# Only the moves the body has: the original's action table names moves
		# this project has not got yet, and they are never current.
		if player.move_manager.move_for(values[name]) == null:
			continue
		if not source.contains("Move.%s:" % name):
			missing.append(name)
	assert_eq(missing, [] as Array[String], \
		"these moves have no animation case and fall through to the standing pose: %s" \
		% ", ".join(missing))

func test_a_jump_does_not_play_the_standing_pose() -> void:
	# THE ONE THAT WAS VISIBLY WRONG. Jump had no case, and the default is
	# idle-first, so a take-off played idle.
	var animator: CharacterAnimator = await _animator_with([&"idle", &"run", &"jump"])
	var player: Player = _world["player"]
	# Read without stepping: start() sets the current move synchronously, and a
	# tick later Jump has already handed off to Falling, so a stepped read asks a
	# different move's question.
	player.move_manager.start(Move.JUMP)
	assert_eq(String(animator._target_animation()), "jump", \
		"a jump asked for '%s'" % String(animator._target_animation()))

func test_a_body_missing_the_ideal_clip_still_gets_something() -> void:
	# Every case is a PRIORITY LIST, not one name: body_scene is optional and
	# per-model, and travel()ing to a name the graph lacks is a real engine
	# error rather than a no-op.
	var animator: CharacterAnimator = await _animator_with([&"idle"])
	var player: Player = _world["player"]
	for move in [Move.JUMP, Move.SKILL_ROLL, Move.WALL_CLIMB, Move.TURN_180, \
			Move.LANDING, Move.INTO_GRAB, Move.FALL_UNCONTROLLED]:
		player.move_manager.start(move)
		assert_eq(String(animator._target_animation()), "idle", \
			"%s resolved to a clip this body does not have" % move)

func test_a_body_with_no_clips_at_all_asks_for_nothing() -> void:
	# Move.KEEP -- "stay put, nothing to do" -- rather than a name the graph
	# cannot reach.
	var animator: CharacterAnimator = await _animator_with([&"unrelated"])
	var player: Player = _world["player"]
	player.move_manager.start(Move.JUMP)
	assert_eq(animator._target_animation(), Move.KEEP, \
		"a body with none of the known clips was still asked for one")

func test_the_ctrl_creep_moves_its_feet() -> void:
	# The Ctrl walk IS the walk. A creep under the idle-versus-moving threshold
	# (1.0) once played a STANDING IDLE: feet still, body drifting.
	var animator: CharacterAnimator = await _animator_with([&"Idle", &"Walk", &"Sprint"])
	var player: Player = _world["player"]
	player.move_manager.start(Move.WALKING)
	var input := MoveInput.new()
	input.walk_held = true
	input.move = Vector2(0.0, 1.0)
	player.last_input = input
	assert_eq(String(animator._target_animation()), "Walk", 		"a Ctrl creep asked for '%s'" % String(animator._target_animation()))

func test_holding_ctrl_while_standing_still_is_still_standing_still() -> void:
	# The pair to the test above. Asked of the INPUT rather than the speed, so
	# the modifier alone must not be enough -- otherwise resting a finger on
	# Ctrl walks on the spot.
	var animator: CharacterAnimator = await _animator_with([&"Idle", &"Walk", &"Sprint"])
	var player: Player = _world["player"]
	player.move_manager.start(Move.WALKING)
	var input := MoveInput.new()
	input.walk_held = true
	player.last_input = input
	assert_eq(String(animator._target_animation()), "Idle", 		"holding Ctrl on the spot asked for '%s'" % String(animator._target_animation()))

## Everything the paid tiers added, plus enough of the free ones that a fallback
## would resolve to SOMETHING if the intended clip were not picked. A test that
## passes because the fallback is missing proves nothing.
const FULL_CLIPS: Array = [
	&"Idle", &"Walk", &"Sprint", &"Jump", &"Jump_Start", &"Jump_Land",
	&"Roll", &"Slide", &"Crouch_Idle", &"Crouch_Fwd", &"NinjaJump_Start",
	&"SafetyVault", &"WallRun_L", &"WallRun_R", &"ClimbUp_1m", &"ClimbUp_2m",
	&"ClimbLedge", &"Climb_Idle", &"Climb_Enter", &"Turn180_L", &"Turn180_R",
	&"StepUp", &"Death01", &"Death02",
	&"WallRun_Jump_L", &"WallRun_Jump_R",
	&"LiftAir_Fall", &"LiftAir_Fall_Air", &"LiftAir_Fall_Impact",
]

func test_the_paid_packs_replace_their_placeholders() -> void:
	# Each of these stood as a PLACEHOLDER borrowing a jump or a run, in some
	# cases since before there was anything else to borrow. Pinned as routing,
	# not as taste: a move that silently goes back to reaching for a take-off
	# is the same class of defect as one with no case at all.
	var animator: CharacterAnimator = await _animator_with(FULL_CLIPS)
	var player: Player = _world["player"]
	# The vault row CanDoMove would have planned: vaultOver.
	(player.move_manager.move_for(Move.SPEED_VAULT) as SpeedVaultMove).active_vault_type = 3
	for row in [[Move.SPEED_VAULT, "SafetyVault"], [Move.WALL_CLIMB, "ClimbUp_2m"],
			[Move.INTO_GRAB, "Climb_Enter"], [Move.TURN_180, "Turn180_R"]]:
		player.move_manager.start(row[0])
		assert_eq(String(animator._target_animation()), row[1], 			"%s asked for '%s'" % [row[0], String(animator._target_animation())])

func test_a_wall_run_picks_the_side_it_is_running_on() -> void:
	# wall_side > 0 is a RIGHT-hand wall (WallRunMove.SIDE_RIGHT). Set AFTER
	# start(), because entering the move is what normally writes it.
	var animator: CharacterAnimator = await _animator_with(FULL_CLIPS)
	var player: Player = _world["player"]
	player.move_manager.start(Move.WALL_RUN)
	player.wall_side = 1
	assert_eq(String(animator._target_animation()), "WallRun_R", 		"a right-hand wall asked for '%s'" % String(animator._target_animation()))
	player.wall_side = -1
	assert_eq(String(animator._target_animation()), "WallRun_L", 		"a left-hand wall asked for '%s'" % String(animator._target_animation()))

func test_a_ledge_hang_hangs_rather_than_jumps() -> void:
	# The hang, still: the hang clip, not a jump.
	var animator: CharacterAnimator = await _animator_with(FULL_CLIPS)
	var player: Player = _world["player"]
	player.move_manager.start(Move.GRAB)
	assert_eq(String(animator._target_animation()), "Climb_Idle", 		"a ledge hang asked for '%s'" % String(animator._target_animation()))

func test_a_step_up_row_steps_up_instead_of_planting_a_hand() -> void:
	# [ME:CONFIRMED 05 §5.7] The original's two step-up rows
	# (autostepuprightleg, stepuprightleg88) are the two with no hand IK: there
	# is no hand on the top in them, so they play the pack's StepUp.
	var animator: CharacterAnimator = await _animator_with(FULL_CLIPS)
	var player: Player = _world["player"]
	var vault := player.move_manager.move_for(Move.VAULT_OVER) as SpeedVaultMove
	vault.active_vault_type = 0
	player.move_manager.start(Move.VAULT_OVER)
	assert_eq(String(animator._target_animation()), "StepUp",
		"a step-up row asked for '%s'" % String(animator._target_animation()))

func test_a_vault_row_plants_a_hand() -> void:
	# The pair. Without it the test above passes on a routing that sends EVERY
	# vault to a step-up.
	var animator: CharacterAnimator = await _animator_with(FULL_CLIPS)
	var player: Player = _world["player"]
	var vault := player.move_manager.move_for(Move.VAULT_OVER) as SpeedVaultMove
	vault.active_vault_type = 3
	player.move_manager.start(Move.VAULT_OVER)
	assert_eq(String(animator._target_animation()), "SafetyVault",
		"a vault row asked for '%s'" % String(animator._target_animation()))

func test_a_dying_body_falls_over_rather_than_carrying_on() -> void:
	# ✅ THE OWNER: "do not play the first-person screen rotation when dying in
	# third person -- play the Death2 animation instead."
	#
	# Dying is not a Move. The level's death sequence locks the input and drives
	# the camera while whatever Move the player died in carries on ticking
	# underneath -- usually a fall -- so without this the body runs its falling
	# clip through the whole cutscene.
	var animator: CharacterAnimator = await _animator_with(FULL_CLIPS)
	var player: Player = _world["player"]
	player.move_manager.start(Move.FALLING)
	assert_eq(String(animator._target_animation()), "Jump",
		"the fixture is not falling, so the test below proves nothing")
	player.set_dying(true)
	# ⚠️ LiftAir_Fall, NOT LiftAir_Fall_Impact, which this pinned first. Impact
	# is the ARRIVAL -- a body hitting the ground and convulsing -- and played
	# as the whole death it thrashes instead of landing. ✅ The owner: "不要用
	# Impact，那个有点太强烈了，看起来像是搁浅的鲤鱼."
	assert_eq(String(animator._target_animation()), "LiftAir_Fall",
		"a dying body asked for '%s'" % String(animator._target_animation()))

func test_a_body_with_no_death_clip_is_not_left_asking_for_one() -> void:
	# Every case in this file is a priority list for the same reason: a body
	# without the paid packs must still resolve to something the graph has.
	var animator: CharacterAnimator = await _animator_with([&"idle", &"jump"])
	var player: Player = _world["player"]
	player.set_dying(true)
	assert_eq(String(animator._target_animation()), "idle",
		"a body with no death clip asked for '%s'" % String(animator._target_animation()))

## Reproduces MoveManager's real hand-off, which passes the OUTGOING move's
## name to enter().
##
## ⚠️ start() does NOT. It passes an empty name, because a restart from outside
## is not a transition from anything -- so a test that starts one move and then
## another never exercises a `previous` at all.
func _hand_off(player: Player, from: StringName, to: StringName) -> void:
	player.move_manager.start(to)
	player.move_manager.move_for(to).enter(from)

## [ME:CONFIRMED decompile] WallrunJump plays WallrunJumpLeft/Right when the
## jump pushed well off the wall (p > 0.6), named for the wall left behind.
func test_a_wall_run_jump_off_the_wall_plays_the_wall_kick() -> void:
	var animator: CharacterAnimator = await _animator_with(FULL_CLIPS)
	var player: Player = _world["player"]
	player.move_manager.start(Move.WALLRUN_JUMP)
	var jump = player.move_manager.move_for(Move.WALLRUN_JUMP)
	jump.push_speed = 1.0
	jump.from_left_wall = false
	assert_eq(String(animator._target_animation()), "WallRun_Jump_R",
		"a kick off a right-hand wall asked for '%s'" % String(animator._target_animation()))
	jump.from_left_wall = true
	assert_eq(String(animator._target_animation()), "WallRun_Jump_L",
		"a kick off a left-hand wall asked for '%s'" % String(animator._target_animation()))

## ... and JumpSlow -- a plain take-off here -- when it did not.
func test_a_wall_run_jump_along_the_wall_is_a_plain_take_off() -> void:
	var animator: CharacterAnimator = await _animator_with(FULL_CLIPS)
	var player: Player = _world["player"]
	player.move_manager.start(Move.WALLRUN_JUMP)
	player.move_manager.move_for(Move.WALLRUN_JUMP).push_speed = 0.2
	assert_eq(String(animator._target_animation()), "Jump_Start",
		"a jump along the wall asked for '%s'" % String(animator._target_animation()))

func test_an_ordinary_jump_is_still_an_ordinary_jump() -> void:
	var animator: CharacterAnimator = await _animator_with(FULL_CLIPS)
	var player: Player = _world["player"]
	_hand_off(player, Move.WALKING, Move.JUMP)
	assert_eq(String(animator._target_animation()), "Jump_Start",
		"a jump off the floor asked for '%s'" % String(animator._target_animation()))

func test_an_uncontrolled_fall_is_not_an_ordinary_one() -> void:
	# ✅ The owner found the clip: LiftAir_Fall is the pack's own out-of-control
	# descent, where Jump is a controlled one with the legs under the body. The
	# two states had shared a clip since there was nothing in the FREE tier that
	# told a flail from a fall.
	var animator: CharacterAnimator = await _animator_with(FULL_CLIPS)
	var player: Player = _world["player"]
	player.move_manager.start(Move.FALLING)
	assert_eq(String(animator._target_animation()), "Jump",
		"an ordinary fall changed too")
	player.move_manager.start(Move.FALL_UNCONTROLLED)
	# ⚠️ THE _Air ONE. The pack names these like NinjaJump_Start / _Idle /
	# _Land: LiftAir_Fall is the ENTRY, played once, and LiftAir_Fall_Air is the
	# descent. Routing the STATE at the entry clip leaves it holding its last
	# frame for the whole drop, which is what the owner read as "you have the
	# falling animation set to the impact one".
	assert_eq(String(animator._target_animation()), "LiftAir_Fall_Air",
		"an uncontrolled fall asked for '%s'" % String(animator._target_animation()))

# --- a clip the graph never heard of is a clip the body does not have ---------

func test_a_shimmy_plays_the_travel_clips() -> void:
	# _has_clip() asks the GRAPH, and only names listed in
	# Player._KNOWN_ANIMATION_CLIPS become nodes in it -- so a clip the body
	# ships and that list omits reads exactly like a clip the body does not
	# have. Asked end to end, stub body, real graph, real routing.
	var animator: CharacterAnimator = await _animator_with(
		[&"idle", &"Climb_Idle", &"Climb_Left", &"Climb_Right"])
	var player: Player = _world["player"]
	player.move_manager.start(Move.GRAB)
	var grab := player.move_manager.move_for(Move.GRAB) as GrabMove
	assert_not_null(grab, "no GrabMove to drive")
	assert_eq(animator._target_animation(), &"Climb_Idle",
		"a still hang did not play the hang clip")
	grab.current_shimmy_move = GrabMove.ShimmyType.SHIMMY
	grab.shimmy_velocity = -0.6
	assert_eq(animator._target_animation(), &"Climb_Left",
		"travelling left did not play Climb_Left")
	grab.shimmy_velocity = 0.6
	assert_eq(animator._target_animation(), &"Climb_Right",
		"travelling right did not play Climb_Right")

func test_a_body_without_the_travel_clips_keeps_hanging() -> void:
	# Degrading to the hang clip is right for a body that lacks the travel
	# clips.
	var animator: CharacterAnimator = await _animator_with([&"idle", &"Climb_Idle"])
	var player: Player = _world["player"]
	player.move_manager.start(Move.GRAB)
	var grab := player.move_manager.move_for(Move.GRAB) as GrabMove
	grab.current_shimmy_move = GrabMove.ShimmyType.SHIMMY
	grab.shimmy_velocity = 0.6
	assert_eq(animator._target_animation(), &"Climb_Idle",
		"a body with no travel clips did not fall back to the hang")

# --- a pull-up is a slow haul ------------------------------------------------

## The pull-up plays ClimbUp_1m for the pose; the original's sequence length
## is the duration, and CharacterAnimator._scripted_fit() fits the clip to it.
func test_a_pull_up_takes_the_short_climb() -> void:
	var animator: CharacterAnimator = await _animator_with(
		[&"idle", &"Climb_Idle", &"ClimbLedge", &"ClimbUp_1m", &"ClimbUp_2m"])
	var player: Player = _world["player"]
	player.move_manager.start(Move.GRAB_PULL_UP)
	assert_eq(animator._target_animation(), &"ClimbUp_1m",
		"a pull-up played '%s'" % String(animator._target_animation()))

func test_a_body_without_it_falls_back_down_the_list() -> void:
	# The chain still degrades: a body with only the short clips uses them
	# rather than standing still.
	var animator: CharacterAnimator = await _animator_with(
		[&"idle", &"Climb_Idle", &"ClimbLedge"])
	var player: Player = _world["player"]
	player.move_manager.start(Move.GRAB_PULL_UP)
	assert_eq(animator._target_animation(), &"ClimbLedge",
		"a body with no ClimbUp clip played '%s'" % String(animator._target_animation()))

# --- the ladder's top exit is a climb over in every way that matters here -------

func test_a_top_exit_plays_climb_up_instead_of_the_hang() -> void:
	var animator: CharacterAnimator = await _animator_with(FULL_CLIPS)
	var player: Player = _world["player"]
	player.move_manager.start(Move.CLIMB)
	var ladder := player.move_manager.move_for(Move.CLIMB) as ClimbMove
	assert_not_null(ladder, "no ClimbMove to drive")
	assert_eq(animator._target_animation(), &"Climb_Idle",
		"an ordinary climb stopped playing the hang placeholder")
	ladder.climb_state = ClimbMove.State.EXIT_AT_TOP
	assert_eq(animator._target_animation(), &"ClimbUp_1m",
		"a top exit played '%s'" % String(animator._target_animation()))

# --- a held climb or shimmy is one cycle, not one clip per step -----------------

const TRAVEL_CLIPS: Array = [&"idle", &"Climb_Idle", &"Climb_Up", &"Climb_Down",
	&"Climb_Left", &"Climb_Right"]

## Whether the state machine's clip went back to an earlier frame than the
## tick before without having looped (the stub clips are 1 s long).
static func _restarted(previous: float, now: float) -> bool:
	return now < previous and previous - now < 0.5

## The original stops between two steps of a held climb for one tick (the
## step is reached, the next is asked for on the tick after). The pack's
## Climb_Up is a cycle: dropped to the hang for that tick, it crossfaded to
## Climb_Idle and back and started over at every rung, which reads as the
## climb stalling step by step.
func test_a_held_climb_keeps_one_climb_cycle_across_its_steps() -> void:
	var animator: CharacterAnimator = await _animator_with(TRAVEL_CLIPS)
	var player: Player = _world["player"]
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = Vector3(2.0, 8.0, 1.0)
	wall.add_child(shape)
	wall.position = Vector3(0.0, 4.0, -2.0)
	add_child_autofree(wall)
	var line := InterestLine.new()
	line.kind = InterestLine.Kind.LADDER
	line.curve = Curve3D.new()
	# The rungs at z = -1.45, the line's front facing +Z out of the wall.
	line.curve.add_point(Basis(Vector3.UP, -PI) * Vector3(0.0, 0.0, -1.45))
	line.curve.add_point(Basis(Vector3.UP, -PI) * Vector3(0.0, 8.0, -1.45))
	line.rotation.y = PI
	add_child_autofree(line)
	await step(1)
	player.rotation.y = 0.0
	player.pawn_yaw = 0.0
	(_world["input"] as ScriptedInputSource).hold_move(0.0, 1.0)
	var climb := player.move_manager.move_for(Move.CLIMB) as ClimbMove
	for i in 120:
		await step(1)
		if player.move_manager.current_name == Move.CLIMB and animator.current_clip == &"Climb_Up":
			break
	assert_eq(animator.current_clip, &"Climb_Up", "the climb never played Climb_Up")
	await step(10)
	var playback: AnimationNodeStateMachinePlayback = animator._playback
	var position: float = playback.get_current_play_position()
	var off_clip: Array[String] = []
	var restarts: int = 0
	# Four steps.
	for i in 4 * 21:
		await step(1)
		if animator.current_clip != &"Climb_Up" or playback.get_current_node() != &"Climb_Up" \
				or animator._gate_input != CharacterAnimator.GRAPH_STATES:
			off_clip.append("%d:%s/%s" % [i, animator.current_clip, playback.get_current_node()])
		var now: float = playback.get_current_play_position()
		if _restarted(position, now):
			restarts += 1
		position = now
	assert_eq(player.move_manager.current_name, Move.CLIMB, "the climb ended")
	assert_true(climb.is_playing_animation or climb.climb_direction() != 0, "the climb was not held")
	assert_eq(off_clip, [] as Array[String], "the climb left its cycle between steps")
	assert_eq(restarts, 0, "Climb_Up started over %d times" % restarts)

# --- the two lists that have to agree -------------------------------------------

## Every state-name constant declared on Move, read from its own source.
##
## KEEP is skipped: it is the "stay put" sentinel, not a state, and nothing
## routes it.
func _move_constant_names() -> Array[String]:
	var source: String = FileAccess.get_file_as_string("res://scripts/player/moves/move.gd")
	var names: Array[String] = []
	var re := RegEx.create_from_string("(?m)^const ([A-Z_0-9]+): StringName")
	for hit in re.search_all(source):
		var found: String = hit.get_string(1)
		if found != "KEEP":
			names.append(found)
	return names

func test_the_move_scan_actually_finds_the_moves() -> void:
	# The scan above degrades to vacuous truth if move.gd's declarations ever
	# stop matching it: an empty list passes every check made against it.
	var names := _move_constant_names()
	assert_gt(names.size(), 15, "the Move constant scan came back nearly empty")
	assert_true(names.has("COIL"), "the Move constant scan missed a known state")
	assert_false(names.has("KEEP"), "the sentinel is not a state")

func test_every_routed_clip_has_a_node_in_the_graph() -> void:
	# ⚠️ THE SECOND TIME THIS EXACT GAP BIT, which is what earns a general test
	# rather than another per-move case.
	#
	# _has_clip() asks the GRAPH, and only names in Player._KNOWN_ANIMATION_CLIPS
	# become nodes in it. So a clip the BODY ships and that list omits reads
	# exactly like a clip the body does not have -- the fallback chain silently
	# takes the next candidate, and everything looks like it works.
	#
	#   1st  the shimmy routed to Climb_Left/Climb_Right from the day it was
	#        written and played Climb_Idle throughout. Caught in play, much
	#        later, by the owner reporting it repeatedly.
	#   2nd  GroundSit_Idle, routed for Move.COIL. Caught by the owner reading
	#        the change -- "席地坐动作可能不在白名单，你得加一下" -- not by any
	#        test, and not by the two upper-case warnings sitting in
	#        _KNOWN_ANIMATION_CLIPS saying this exact thing would happen.
	#
	# Travelling to a name with no node is an ENGINE ERROR rather than a miss,
	# so when the body DOES have the clip the failure is worse than silence.
	#
	# Source-scanned rather than driven, because the alternative is one
	# end-to-end case per clip and there are sixty. It reads only the three
	# call sites that actually hand the graph a name, so a routing written some
	# other way is a false NEGATIVE -- a degradation, never a false alarm.
	var source: String = FileAccess.get_file_as_string(
		"res://scripts/player/character_animator.gd")
	# The graph's own node names. They are the only StringName literals in that
	# file which are not clips; a new one appearing here should fail this test
	# until whoever added it confirms that is what it is.
	var graph_nodes := ["states", "gate", "scripted_a", "scripted_b", "speed"]
	var asks := RegEx.create_from_string(
		"(?s)_first_available\\(\\[(.*?)\\]|_has_clip\\((&\"[A-Za-z0-9_]+\")|_start_oneshot\\((&\"[A-Za-z0-9_]+\")")
	var names := RegEx.create_from_string("&\"([A-Za-z0-9_]+)\"")
	var routed: Array[String] = []
	for hit in asks.search_all(source):
		for group in range(1, 4):
			var chunk: String = hit.get_string(group)
			if chunk.is_empty():
				continue
			for name_hit in names.search_all(chunk):
				var clip: String = name_hit.get_string(1)
				if clip not in graph_nodes and clip not in routed:
					routed.append(clip)
	assert_gt(routed.size(), 30,
		"the scan found almost nothing, so it has stopped matching the source")

	var orphaned: Array[String] = []
	for clip in routed:
		if not Player._KNOWN_ANIMATION_CLIPS.has(StringName(clip)):
			orphaned.append(clip)
	assert_eq(orphaned, [] as Array[String],
		"routed but with no node in the graph, so they can never play -- add them to Player._KNOWN_ANIMATION_CLIPS: %s"
		% ", ".join(orphaned))

func test_each_death_picks_its_own_clip_rather_than_the_first_one_ever() -> void:
	# The latch holds a death's choice for its DURATION, not for the session.
	# It got this wrong once in a way nothing on screen explained: the lists
	# it latches onto are `const`, i.e. read-only, so clear() failed silently
	# and every death after the first replayed the first one's decision.
	var animator := await _animator_with([&"Death01", &"Death02", &"LiftAir_Fall", &"idle"])
	var player: Player = _world["player"]

	player.health.last_cause = Health.Cause.FALL
	player.set_dying(true)
	assert_eq(animator._target_animation(), &"LiftAir_Fall", "test setup: the fall clip is missing")
	player.set_dying(false)
	assert_ne(animator._target_animation(), &"LiftAir_Fall", "the body kept dying after it stopped")

	player.health.last_cause = Health.Cause.HAZARD
	player.set_dying(true)
	assert_eq(animator._target_animation(), &"Death02", \
		"the second death replayed the first one's choice")
	player.set_dying(false)

# --- the balance beam is a walk, the ledge shuffle is direction-aware --------

## A line of `kind` under the body, for the moves that need their volume.
func _line_under(player: Player, kind: InterestLine.Kind) -> InterestLine:
	var line := InterestLine.new()
	line.kind = kind
	line.curve = Curve3D.new()
	line.curve.add_point(Vector3(0.0, 0.0, 2.0))
	line.curve.add_point(Vector3(0.0, 0.0, -8.0))
	_world["player"].get_parent().add_child(line)
	_world["line"] = line
	return line

func test_the_beam_walks_rather_than_leans() -> void:
	# The lean is carried by the camera roll and the skeleton lean
	# (BalanceLean); the body itself is walking, so Walk is the honest clip.
	var animator: CharacterAnimator = await _animator_with([&"Walk", &"Idle"])
	var player: Player = _world["player"]
	var beam := player.move_manager.move_for(Move.BALANCE) as BalanceMove
	beam.volume = _line_under(player, InterestLine.Kind.BALANCE)
	player.move_manager.start(Move.BALANCE)
	player.velocity = Vector3(0.0, 0.0, -1.0)
	assert_eq(String(animator._target_animation()), "Walk",
		"a beam being walked asked for '%s'" % String(animator._target_animation()))
	player.velocity = Vector3.ZERO
	assert_eq(String(animator._target_animation()), "Idle",
		"a beam being stood on asked for '%s'" % String(animator._target_animation()))

func test_the_ledge_shuffles_sideways() -> void:
	var animator: CharacterAnimator = await _animator_with(
		[&"Walk_L", &"Walk_R", &"Walk", &"Idle"])
	var player: Player = _world["player"]
	var ledge := player.move_manager.move_for(Move.LEDGE_WALK) as LedgeWalkMove
	ledge.volume = _line_under(player, InterestLine.Kind.LEDGE_WALK)
	player.move_manager.start(Move.LEDGE_WALK)
	ledge.strafe_factor = -1.0
	assert_eq(String(animator._target_animation()), "Walk_L",
		"shuffling left asked for '%s'" % String(animator._target_animation()))
	ledge.strafe_factor = 1.0
	assert_eq(String(animator._target_animation()), "Walk_R",
		"shuffling right asked for '%s'" % String(animator._target_animation()))
	ledge.strafe_factor = 0.0
	assert_eq(String(animator._target_animation()), "Idle",
		"standing still on a ledge asked for '%s'" % String(animator._target_animation()))

func test_a_ledge_turning_round_plays_the_packs_half_turn() -> void:
	# The turn's own state is poked, the way the shuffle is above.
	var animator: CharacterAnimator = await _animator_with(
		[&"Turn180_L", &"Turn180_R", &"Walk_L", &"Walk_R", &"Idle"])
	var player: Player = _world["player"]
	var ledge := player.move_manager.move_for(Move.LEDGE_WALK) as LedgeWalkMove
	ledge.volume = _line_under(player, InterestLine.Kind.LEDGE_WALK)
	player.move_manager.start(Move.LEDGE_WALK)
	ledge._turning = true
	ledge._turn_sign = -1.0
	assert_eq(String(animator._target_animation()), "Turn180_R",
		"turning right on a ledge asked for '%s'" % String(animator._target_animation()))
	ledge._turn_sign = 1.0
	assert_eq(String(animator._target_animation()), "Turn180_L",
		"turning left on a ledge asked for '%s'" % String(animator._target_animation()))
	assert_true(Player.SCRIPTED_MOVE_CLIPS.has(&"Turn180_L") and Player.SCRIPTED_MOVE_CLIPS.has(&"Turn180_R"),
		"the turn clips are not routed onto a scripted slot")
	ledge._turning = false
	ledge.strafe_factor = 1.0
	assert_eq(String(animator._target_animation()), "Walk_R",
		"the shuffle did not come back once the turn was over")
	# Facing the wall, the pawn's right is the model's left.
	ledge._faces_wall = true
	assert_eq(String(animator._target_animation()), "Walk_L",
		"a model facing the wall shuffled in the pawn's frame ('%s')" % String(animator._target_animation()))

func test_both_fall_back_when_the_pack_is_absent() -> void:
	# The chain still degrades: a body with only the fox's six clips uses
	# `idle` rather than standing on the default pose.
	var animator: CharacterAnimator = await _animator_with([&"idle"])
	var player: Player = _world["player"]
	var beam := player.move_manager.move_for(Move.BALANCE) as BalanceMove
	beam.volume = _line_under(player, InterestLine.Kind.BALANCE)
	player.move_manager.start(Move.BALANCE)
	assert_eq(String(animator._target_animation()), "idle",
		"a balance beam with no Walk clip asked for '%s'" % String(animator._target_animation()))
	var ledge := player.move_manager.move_for(Move.LEDGE_WALK) as LedgeWalkMove
	ledge.volume = beam.volume
	player.move_manager.start(Move.LEDGE_WALK)
	assert_eq(String(animator._target_animation()), "idle",
		"a ledge with no Walk clips asked for '%s'" % String(animator._target_animation()))

func test_a_body_stepping_round_plays_the_packs_quarter_turn() -> void:
	# The step's own state is poked, the way the ledge's turn is above.
	var animator: CharacterAnimator = await _animator_with(
		[&"Turn90_L", &"Turn90_R", &"Idle", &"Sprint"])
	var player: Player = _world["player"]
	player.move_manager.start(Move.WALKING)
	player._turn_clip_left = 0.2
	player._turn_in_place_sign = 1.0
	assert_eq(String(animator._target_animation()), "Turn90_L",
		"stepping round to the left asked for '%s'" % String(animator._target_animation()))
	player._turn_in_place_sign = -1.0
	assert_eq(String(animator._target_animation()), "Turn90_R",
		"stepping round to the right asked for '%s'" % String(animator._target_animation()))
	assert_true(Player.SCRIPTED_MOVE_CLIPS.has(&"Turn90_L") and Player.SCRIPTED_MOVE_CLIPS.has(&"Turn90_R"),
		"the quarter-turn clips are not routed onto a scripted slot")
	player._turn_clip_left = 0.0
	assert_eq(String(animator._target_animation()), "Idle",
		"standing still did not come back once the step was over")

func test_a_spring_board_steps_on_step_up_and_rises_on_the_airborne_loop() -> void:
	# The move's own state is poked, the way the ledge's turn is above: the
	# routing only asks the move which part of it is running.
	var animator: CharacterAnimator = await _animator_with(
		[&"StepUp", &"Jump", &"Idle"])
	var player: Player = _world["player"]
	player.move_manager.start(Move.SPRING_BOARD)
	var board := player.move_manager.move_for(Move.SPRING_BOARD) as SpringBoardMove
	assert_not_null(board, "no SpringBoardMove to drive")
	board.spring_board_state = 1
	assert_eq(String(animator._target_animation()), "StepUp",
		"the steps asked for '%s'" % String(animator._target_animation()))
	assert_almost_eq(board.scripted_duration(),
		player.config.spring_board.step_time_1 + player.config.spring_board.step_time_2, 0.001,
		"the steps did not offer the clip both step times as its window")
	board.spring_board_state = 3
	assert_eq(String(animator._target_animation()), "Jump",
		"the rise asked for '%s'" % String(animator._target_animation()))

func test_a_crouch_punch_keeps_the_crouch_below_and_punches_above() -> void:
	var animator: CharacterAnimator = await _animator_with(
		[&"Crouch_Idle", &"Melee_Uppercut", &"Idle"])
	var player: Player = _world["player"]
	assert_eq(player.upper_overlay_clip, &"Melee_Uppercut", "the overlay did not find the punch")
	player.move_manager.start(Move.MELEE_CROUCH)
	assert_eq(String(animator._target_animation()), "Crouch_Idle",
		"the crouch punch's base asked for '%s'" % String(animator._target_animation()))
	assert_true(Player._is_upper_body_bone("Spine") and Player._is_upper_body_bone("RightHand") \
		and Player._is_upper_body_bone("LeftIndexProximal") and Player._is_upper_body_bone("Head"),
		"the upper-body filter misses part of the spine-and-above chain")
	assert_false(Player._is_upper_body_bone("Hips") or Player._is_upper_body_bone("LeftUpperLeg") \
		or Player._is_upper_body_bone("RightFoot") or Player._is_upper_body_bone("LeftToes"),
		"the upper-body filter reaches the hips or legs")
