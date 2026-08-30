extends ParkourTest

# STRUCTURAL PROPERTIES ONLY. The dials (base_wobble, beam_half_width, the lean
# and FOV limits) are judged by eye and carry no assertions -- see
# .claude/skills/tuning-dials-not-rules.

const TestWorld = preload("res://tests/world_fixture.gd")

var _world: Dictionary = {}

func after_each() -> void:
	if not _world.is_empty():
		TestWorld.teardown(_world)
		_world = {}

func test_lean_diverges_when_nobody_corrects() -> void:
	var move := BalanceMove.new()
	move.cfg = BalanceConfig.new()
	move.seed_lean(0.01, 0.0)
	var first := absf(move.lean())
	for i in 10:
		move.integrate_lean(1.0 / 60.0, 0.0)
	assert_gt(absf(move.lean()), first,
		"an inverted pendulum with no correction must run away from its apex")

func test_the_apex_is_stationary() -> void:
	var move := BalanceMove.new()
	move.cfg = BalanceConfig.new()
	move.seed_lean(0.0, 0.0)
	for i in 60:
		move.integrate_lean(1.0 / 60.0, 0.0)
	assert_almost_eq(move.lean(), 0.0, 0.0001,
		"zero lean AND zero rate is the unstable equilibrium: it must sit still")

func test_a_standstill_entry_still_leans() -> void:
	var cfg := BalanceConfig.new()
	var lean := BalanceMove.entry_lean(cfg, 0.0, 7.2, 1)
	assert_gt(absf(lean), 0.0,
		"the owner measured that standing still on a beam still loses balance")

func test_entry_lean_grows_with_entry_speed() -> void:
	var cfg := BalanceConfig.new()
	var slow := absf(BalanceMove.entry_lean(cfg, 0.0, 7.2, 1))
	var fast := absf(BalanceMove.entry_lean(cfg, 7.2, 7.2, 1))
	assert_gt(fast, slow, "SpeedInfluence magnifies the ENTRY offset")

func test_correction_opposes_the_lean() -> void:
	var move := BalanceMove.new()
	move.cfg = BalanceConfig.new()
	move.seed_lean(0.05, 0.0)
	var free := move.duplicate_lean_after(0.2, 0.0)
	var corrected := move.duplicate_lean_after(0.2, -1.0)
	assert_lt(corrected, free, "A/D must fight the lean, not steer")

func test_the_ledge_walk_has_no_pendulum() -> void:
	var move := LedgeWalkMove.new()
	assert_false(move.has_method("lean"),
		"LedgeWalk carries none of TdMove_Balance's five pendulum fields")

## Falling off is GEOMETRIC: the same lateral_offset() the camera/skeleton/HUD
## read is what lateral_update() compares against beam_half_width. Needs a
## real Player because lateral_update() calls player.consume_roll() on the
## way out -- not a second, independent threshold check.
func test_falling_off_the_beam_is_geometric() -> void:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	var player: Player = _world["player"]
	var move := BalanceMove.new()
	move.player = player
	move.config = player.config
	move.cfg = BalanceConfig.new()
	# A lean whose real lateral displacement (lean * gravity_influence)
	# already clears the beam's half width.
	var over_the_edge: float = (move.cfg.beam_half_width / move.cfg.gravity_influence) + 0.1
	move.seed_lean(over_the_edge, 0.0)
	var result: StringName = move.lateral_update(1.0 / 60.0, 0.0)
	assert_eq(result, Move.FALLING,
		"past the beam's half width the feet have nothing under them")
