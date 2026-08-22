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
			"GRAB", "WALL_RUN", "WALL_CLIMB", "TURN_180"]:
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
