extends ParkourTest

# The two things about a level's fog that BREAK SILENTLY. Everything else it
# does -- how far the curtain sits, how thick the haze reads, what colour the
# horizon turns -- is judged by standing on a roof and looking, so none of it
# is asserted here (see docs/superpowers, the tuning-values rule): a test that
# pins 60.0 fails on every deliberate retune and never once on a bug.
#
# What IS here fails only on a bug, and on a bug you cannot see:
#
#   1. A feel preset must not be able to carry one level's weather into
#      another. TuningPanel._on_save() writes every row collect_tunables()
#      yields; the day fog gets folded into that walk, loading a preset saved
#      on a fogged rooftop silently re-fogs a level that asked for 晴空万里,
#      and nothing anywhere says so.
#   2. Arena must never hand Godot a fog_depth_end of 0 or one at/below
#      fog_depth_begin. Godot reads 0 as "use the camera's far plane" (4000 m),
#      so the dial appears to do nothing at all rather than to be broken --
#      the most expensive kind of wrong, because it reads as "fog is fine,
#      my number just isn't taking".

const TEMPLATE := "res://templates/base_level.tscn"

func _environment_of(arena: Node) -> Environment:
	return (arena.get_node("WorldEnvironment") as WorldEnvironment).environment

## Arena applies fog from _process(), an IDLE-frame callback -- so these wait
## on process_frame rather than going through ParkourTest.step(), which
## advances the PHYSICS clock. Awaiting the wrong clock here would pass by
## luck (the two interleave) instead of by construction.
func _idle_frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

## Instantiates the template, lets Arena._process() run, and returns the pair.
func _live_template() -> Array:
	var arena := (load(TEMPLATE) as PackedScene).instantiate()
	add_child_autofree(arena)
	await _idle_frames(2)
	return [arena, _environment_of(arena)]

func test_a_feel_preset_cannot_carry_a_levels_fog() -> void:
	# The exact walk _on_save() uses to build a preset. Fog living outside it
	# is the whole guarantee; a `for` over MovementConfig's groups that ever
	# reaches a FogConfig is the failure.
	for row in TuningPanel.collect_tunables(MovementConfig.new()):
		assert_ne(row["group"], TuningPanel.FOG_GROUP,
			"fog leaked into the preset walk via %s" % row["path"])

func test_the_panel_still_shows_the_fog_dials() -> void:
	# The other half of the same split: kept OUT of presets, kept IN the UI.
	# Without this, "no fog in presets" is trivially satisfiable by dropping
	# the dials entirely, which is not the design.
	var rows := TuningPanel.collect_fog_tunables(FogConfig.new())
	assert_gt(rows.size(), 0, "the fog page would build no sliders at all")
	for row in rows:
		assert_eq(row["group"], TuningPanel.FOG_GROUP,
			"%s landed on some other page" % row["path"])

func test_a_level_with_no_fog_config_grows_no_fog_page() -> void:
	assert_eq(TuningPanel.collect_fog_tunables(null).size(), 0,
		"a level that declares no fog would show dead sliders")

func test_the_fade_end_never_lands_on_zero_or_below_the_begin() -> void:
	var pair := await _live_template()
	var arena: Arena = pair[0]
	var environment: Environment = pair[1]
	# Every way a mid-drag F1 slider can put the two dials in the wrong order,
	# including the one that reads as "the dial does nothing" (0).
	for end_value in [0.0, -5.0, 10.0, arena.fog.fade_begin_distance]:
		arena.fog.fade_end_distance = end_value
		await _idle_frames(1)
		assert_gt(environment.fog_depth_end, environment.fog_depth_begin,
			"end dial %s produced depth_end %s, at or under depth_begin %s" \
				% [end_value, environment.fog_depth_end, environment.fog_depth_begin])
		assert_gt(environment.fog_depth_end, 0.0,
			"end dial %s produced depth_end 0 -- Godot reads that as the camera far plane" % end_value)

func test_clearing_enabled_turns_both_fogs_off() -> void:
	# "这一关就是想要晴空万里." Both, not one: the depth fog hides the horizon
	# and the volumetric fog hazes the air, and a level left with only the
	# second one is not a clear day.
	var pair := await _live_template()
	var arena: Arena = pair[0]
	var environment: Environment = pair[1]
	arena.fog.enabled = false
	await _idle_frames(1)
	assert_false(environment.fog_enabled, "depth fog survived enabled = false")
	assert_false(environment.volumetric_fog_enabled, "volumetric fog survived enabled = false")

func test_an_arena_with_no_fog_config_leaves_the_environment_alone() -> void:
	# null is not the same as enabled = false: it means "this level does not
	# manage fog", which is what lets a hand-authored Environment (and a
	# test-built Arena that has none) keep whatever it was given.
	var pair := await _live_template()
	var arena: Arena = pair[0]
	var environment: Environment = pair[1]
	environment.fog_enabled = false
	environment.fog_depth_begin = 12.34
	arena.fog = null
	await _idle_frames(1)
	assert_false(environment.fog_enabled, "Arena re-enabled fog for a level that declares none")
	assert_almost_eq(environment.fog_depth_begin, 12.34, 0.001,
		"Arena overwrote a hand-authored fog distance for a level that declares none")
