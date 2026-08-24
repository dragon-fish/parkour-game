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
	var missing: Array[String] = []
	for name in ["WALKING", "FALLING", "FALL_UNCONTROLLED", "JUMP", "LANDING", \
			"SKILL_ROLL", "SLIDE", "CROUCH", "SPEED_VAULT", "INTO_GRAB", \
			"GRAB", "WALL_RUN", "WALL_CLIMB", "TURN_180", "ZIPLINE"]:
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
	# ✅ THE OWNER: "we already have the Ctrl walk -- that IS the walk." It was
	# playing a STANDING IDLE. The modifier caps the body at walk_velocity,
	# 0.5 m/s, and the idle-versus-moving threshold sits at 1.0, so a creep
	# never reached the moving branch at all: feet still, body drifting.
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
	for row in [[Move.SPEED_VAULT, "SafetyVault"], [Move.WALL_CLIMB, "ClimbUp_2m"],
			[Move.INTO_GRAB, "Climb_Enter"], [Move.TURN_180, "Turn180_R"]]:
		player.move_manager.start(row[0])
		assert_eq(String(animator._target_animation()), row[1], 			"%s asked for '%s'" % [row[0], String(animator._target_animation())])

func test_a_wall_run_picks_the_side_it_is_running_on() -> void:
	# wall_side > 0 is a RIGHT-hand wall -- WallRunMove's own look-fan code says
	# so, at the line that reads `span if wall_side > 0`. Set AFTER start(),
	# because entering the move is what normally writes it.
	var animator: CharacterAnimator = await _animator_with(FULL_CLIPS)
	var player: Player = _world["player"]
	player.move_manager.start(Move.WALL_RUN)
	player.wall_side = 1
	assert_eq(String(animator._target_animation()), "WallRun_R", 		"a right-hand wall asked for '%s'" % String(animator._target_animation()))
	player.wall_side = -1
	assert_eq(String(animator._target_animation()), "WallRun_L", 		"a left-hand wall asked for '%s'" % String(animator._target_animation()))

func test_a_ledge_hang_hangs_rather_than_jumps() -> void:
	# GRAB has two phases behind one move. This is the resting one -- the
	# mantle is told apart by GrabMove.is_mantling(), which a move entered from
	# nowhere reports false for.
	var animator: CharacterAnimator = await _animator_with(FULL_CLIPS)
	var player: Player = _world["player"]
	player.move_manager.start(Move.GRAB)
	assert_eq(String(animator._target_animation()), "Climb_Idle", 		"a ledge hang asked for '%s'" % String(animator._target_animation()))

func test_a_scrambled_vault_steps_up_instead_of_planting_a_hand() -> void:
	# ✅ THE OWNER: the compensating vault and the one where the shin catches
	# the edge should both play StepUp. They are the vaults that were never set
	# up -- no run-up, no plant, the player simply arrived. The original agrees
	# from the other direction: its two step-up rows are precisely the two with
	# no hand IK at all (05 §5.7), because there is no hand in them.
	var animator: CharacterAnimator = await _animator_with(FULL_CLIPS)
	var player: Player = _world["player"]
	# The step-up row, resolved through the real table rather than named here,
	# so a renamed variant fails this instead of silently routing to a plant.
	player.pending_vault_variant = player.config.speed_vault.pick_variant(
		0.3, true, -2.0, 2.0)
	assert_false(player.pending_vault_variant.is_empty(),
		"the table no longer has a descending step-up row to test with")
	player.move_manager.start(Move.SPEED_VAULT)
	assert_eq(String(animator._target_animation()), "StepUp",
		"a shin-catch vault asked for '%s'" % String(animator._target_animation()))

func test_a_vault_that_was_set_up_still_plants_a_hand() -> void:
	# The pair. Without it the test above passes on a routing that sends EVERY
	# vault to a step-up, which would quietly delete the plant.
	var animator: CharacterAnimator = await _animator_with(FULL_CLIPS)
	var player: Player = _world["player"]
	player.pending_vault_variant = player.config.speed_vault.pick_variant(
		1.0, false, 1.0, 6.0)
	assert_false(player.pending_vault_variant.is_empty(),
		"the table no longer has a set-up vault row to test with")
	player.pending_vault_rescue = false
	player.move_manager.start(Move.SPEED_VAULT)
	assert_eq(String(animator._target_animation()), "SafetyVault",
		"a committed vault asked for '%s'" % String(animator._target_animation()))

func test_a_rescued_vault_scrambles_even_on_a_plant_variant() -> void:
	# The rescue resolves to the MIDDLE tier -- the same row a run-up would --
	# so the variant name alone cannot tell them apart. The flag can.
	var animator: CharacterAnimator = await _animator_with(FULL_CLIPS)
	var player: Player = _world["player"]
	player.pending_vault_variant = player.config.speed_vault.pick_variant(
		1.0, false, 0.0, 6.0)
	assert_false(player.pending_vault_variant.is_empty(), "no middle-tier row")
	player.pending_vault_rescue = true
	player.move_manager.start(Move.SPEED_VAULT)
	assert_eq(String(animator._target_animation()), "StepUp",
		"a rescued vault asked for '%s'" % String(animator._target_animation()))

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
## another never exercises a `previous` at all, and the first draft of these
## duly reported a wall kick playing an ordinary jump against working code.
func _hand_off(player: Player, from: StringName, to: StringName) -> void:
	player.move_manager.start(to)
	player.move_manager.move_for(to).enter(from)

func test_a_wall_kick_is_not_an_ordinary_jump() -> void:
	# ✅ THE OWNER: "the packs have a WallRunJump and it is not wired up -- a
	# wall kick still plays the ordinary jump." The MECHANISM has been complete
	# for a while -- WallRunMove.wall_jump_launch and the whole Noob/ProAdd
	# skill gradient behind it -- and it hands off to JUMP, so the animator had
	# no way to tell that jump from stepping off a kerb.
	var animator: CharacterAnimator = await _animator_with(FULL_CLIPS)
	var player: Player = _world["player"]
	# recent_wall_side, not wall_side: WallRunMove.exit() clears the live one
	# before JumpMove.enter() ever runs, which is the whole reason JumpMove
	# reads the remembered one.
	player.recent_wall_side = 1
	_hand_off(player, Move.WALL_RUN, Move.JUMP)
	assert_eq(String(animator._target_animation()), "WallRun_Jump_R",
		"a kick off a right-hand wall asked for '%s'" % String(animator._target_animation()))

func test_the_other_wall_kicks_the_other_way() -> void:
	var animator: CharacterAnimator = await _animator_with(FULL_CLIPS)
	var player: Player = _world["player"]
	player.recent_wall_side = -1
	_hand_off(player, Move.WALL_RUN, Move.JUMP)
	assert_eq(String(animator._target_animation()), "WallRun_Jump_L",
		"a kick off a left-hand wall asked for '%s'" % String(animator._target_animation()))

func test_an_ordinary_jump_is_still_an_ordinary_jump() -> void:
	# The pair, and the one that stops the kick clip leaking onto every jump.
	# A jump that did not come from a wall run has no side, whatever the
	# player last ran along.
	var animator: CharacterAnimator = await _animator_with(FULL_CLIPS)
	var player: Player = _world["player"]
	player.recent_wall_side = 1
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
	# ⚠️ THE ROUTING FOR THESE WAS DEAD CODE FROM THE DAY IT WAS WRITTEN, and
	# nothing said so. _has_clip() asks the GRAPH, and only names listed in
	# Player._KNOWN_ANIMATION_CLIPS become nodes in it -- so a clip the body
	# ships and that list omits reads exactly like a clip the body does not
	# have, and the fallback chain quietly takes the next candidate. The shimmy
	# played Climb_Idle throughout while working perfectly otherwise, which is
	# why the owner kept reporting "我还是没观察到左爬和右爬的动画".
	#
	# Asked end to end -- stub body, real graph, real routing -- because the
	# failure lived in the gap between two lists that each looked right alone.
	var animator: CharacterAnimator = await _animator_with(
		[&"idle", &"Climb_Idle", &"Climb_Left", &"Climb_Right"])
	var player: Player = _world["player"]
	player.pending_ledge = {"valid": true,
		"edge": player.global_position + Vector3(0.0, 2.0, -1.0),
		"face_normal": Vector3(0.0, 0.0, 1.0)}
	player.move_manager.start(Move.GRAB)
	var grab := player.move_manager.move_for(Move.GRAB) as GrabMove
	assert_not_null(grab, "no GrabMove to drive")

	grab._shimmy = 0.0
	assert_eq(animator._target_animation(), &"Climb_Idle",
		"a still hang did not play the hang clip")
	grab._shimmy = -1.0
	assert_eq(animator._target_animation(), &"Climb_Left",
		"travelling left did not play Climb_Left")
	grab._shimmy = 1.0
	assert_eq(animator._target_animation(), &"Climb_Right",
		"travelling right did not play Climb_Right")

func test_a_body_without_the_travel_clips_keeps_hanging() -> void:
	# The fallback the chain is written for, and the reason the bug above was
	# invisible: degrading to the hang clip is CORRECT for a body that lacks
	# these, and indistinguishable from the failure when the graph is what is
	# missing them.
	var animator: CharacterAnimator = await _animator_with([&"idle", &"Climb_Idle"])
	var player: Player = _world["player"]
	player.pending_ledge = {"valid": true,
		"edge": player.global_position + Vector3(0.0, 2.0, -1.0),
		"face_normal": Vector3(0.0, 0.0, 1.0)}
	player.move_manager.start(Move.GRAB)
	var grab := player.move_manager.move_for(Move.GRAB) as GrabMove
	grab._shimmy = 1.0
	assert_eq(animator._target_animation(), &"Climb_Idle",
		"a body with no travel clips did not fall back to the hang")

# --- a pull-up is a slow haul ------------------------------------------------

func test_a_pull_up_prefers_the_long_climb() -> void:
	# ✅ THE OWNER: "GrabPullUp 还是太快了...ME 里体感将近 2s 呢，这个动画也得换成
	# ClimbUp_2m."
	#
	# 📌 Measured, the three candidates are ClimbUp_2m 1.300 s, ClimbUp_1m 0.667
	# and ClimbLedge 0.633. TdMove_GrabPullUp carries no duration field at all,
	# which says the length comes from the clip -- so picking the clip IS picking
	# the duration, and GrabConfig.mantle_duration is 1.3 to match.
	#
	# ⚠️ THIS OVERRULES AN ARGUMENT THE ROUTING ITSELF USED TO MAKE, that
	# ClimbUp_* starts from STANDING while ClimbLedge belongs to the hang set.
	# True, and it lost: ClimbLedge is over before the body has left the lip.
	var animator: CharacterAnimator = await _animator_with(
		[&"idle", &"Climb_Idle", &"ClimbLedge", &"ClimbUp_1m", &"ClimbUp_2m"])
	var player: Player = _world["player"]
	player.pending_ledge = {"valid": true,
		"edge": player.global_position + Vector3(0.0, 2.0, -1.0),
		"face_normal": Vector3(0.0, 0.0, 1.0)}
	player.move_manager.start(Move.GRAB)
	var grab := player.move_manager.move_for(Move.GRAB) as GrabMove
	assert_eq(animator._target_animation(), &"Climb_Idle",
		"a still hang stopped playing the hang clip")
	grab._mantling = true
	assert_eq(animator._target_animation(), &"ClimbUp_2m",
		"a pull-up played '%s'" % String(animator._target_animation()))

func test_a_body_without_it_falls_back_down_the_list() -> void:
	# The chain still degrades: a body with only the short clips uses them
	# rather than standing still.
	var animator: CharacterAnimator = await _animator_with(
		[&"idle", &"Climb_Idle", &"ClimbLedge"])
	var player: Player = _world["player"]
	player.pending_ledge = {"valid": true,
		"edge": player.global_position + Vector3(0.0, 2.0, -1.0),
		"face_normal": Vector3(0.0, 0.0, 1.0)}
	player.move_manager.start(Move.GRAB)
	var grab := player.move_manager.move_for(Move.GRAB) as GrabMove
	grab._mantling = true
	assert_eq(animator._target_animation(), &"ClimbLedge",
		"a body with no ClimbUp_2m played '%s'" % String(animator._target_animation()))
