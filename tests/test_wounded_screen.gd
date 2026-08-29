extends ParkourTest

# [13.4] THE PICTURE IS THE HEALTH BAR. There is no number on screen in the
# original and none here, so what these guard is that the picture keeps
# saying the right thing -- above all that the two bands stay in the right
# ORDER. Reversed, the gentlest cue arrives at the most dangerous moment.
#
# The strengths and thresholds themselves are dials and are not asserted.

const TestWorld = preload("res://tests/world_fixture.gd")

var _worlds: Array = []

func after_each() -> void:
	for world in _worlds:
		TestWorld.teardown(world)
	_worlds.clear()

func _player() -> Player:
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	_worlds.append(world)
	await step(2)
	return world["player"]

## Puts the bar at `fraction` of full and lets one tick paint it.
func _wound_to(player: Player, fraction: float) -> void:
	var max_health: float = player.config.pawn.max_health
	player.health.hp = max_health * fraction
	await step(1)

func test_a_whole_body_leaves_the_picture_alone() -> void:
	var player := await _player()
	assert_almost_eq(player.screen_effects.desaturation, 0.0, 0.001, \
		"an untouched body was shown as wounded")
	assert_almost_eq(player.screen_effects.vignette_amount, 0.0, 0.001, \
		"an untouched body was shown as dying")

func test_colour_drains_before_the_edge_reddens() -> void:
	# The ordering that matters. Between the two thresholds the picture must
	# already be losing colour and must NOT yet be flashing.
	var player := await _player()
	var camera: CameraConfig = player.config.camera
	assert_lt(camera.wounded_alarm_at, camera.wounded_desaturation_at, \
		"the red band was moved above the grey one, so the last warning comes first")
	var between: float = (camera.wounded_alarm_at + camera.wounded_desaturation_at) * 0.5
	await _wound_to(player, between)
	assert_gt(player.screen_effects.desaturation, 0.0, "colour did not start draining")
	assert_almost_eq(player.screen_effects.vignette_amount, 0.0, 0.001, \
		"the edge reddened while the body was only half hurt")

func test_the_edge_reddens_once_the_body_is_nearly_out() -> void:
	var player := await _player()
	await _wound_to(player, player.config.camera.wounded_alarm_at * 0.3)
	assert_gt(await _peak_alarm(player), 0.0, "a body about to die showed no alarm at all")
	assert_eq(player.screen_effects.vignette_color(), Color.RED, "the alarm was not red")

func test_two_hits_of_wire_is_inside_the_alarm_band_and_visibly_so() -> void:
	# The case the band was described by, and the one a strict comparison
	# puts outside it: two hits is exactly the threshold. It also has to be
	# SEEN there -- a ramp starting from nothing puts the first real warning
	# somewhere below the line it was meant to mark.
	var player := await _player()
	var pawn: PawnConfig = player.config.pawn
	player.health.hp = pawn.max_health
	player.take_damage(35.0, Health.Cause.HAZARD)
	player.take_damage(35.0, Health.Cause.HAZARD)
	await step(1)
	assert_almost_eq(player.health.fraction(), player.config.camera.wounded_alarm_at, 0.001,
		"test setup: two wire hits no longer land on the threshold")
	var peak: float = await _peak_alarm(player)
	assert_gt(peak, 0.0, "standing exactly on the threshold showed nothing")
	assert_gt(peak, player.config.camera.wounded_alarm_strength * 0.2,
		"the alarm was technically on but too faint to be a warning")

## The alarm breathes, so a single tick can land on the quiet half of it.
func _peak_alarm(player: Player) -> float:
	var peak: float = 0.0
	for i in 90:
		await step(1)
		peak = maxf(peak, player.screen_effects.vignette_amount)
	return peak

func test_the_picture_comes_back_as_health_does() -> void:
	var player := await _player()
	await _wound_to(player, 0.1)
	assert_gt(player.screen_effects.desaturation, 0.0, "test setup: never went grey")
	player.health.hp = player.config.pawn.max_health
	await step(1)
	assert_almost_eq(player.screen_effects.desaturation, 0.0, 0.001, \
		"colour did not come back with the health")
	assert_almost_eq(player.screen_effects.vignette_amount, 0.0, 0.001, \
		"the alarm outlived the wound")

func test_the_death_dims_and_steepens_rather_than_cutting_to_it() -> void:
	# Losing consciousness, not a post-process bug. Cut to all at once the
	# grade reads as a fault; arriving over the sequence it reads as the
	# lights going out behind the eyes.
	var arena: Arena = preload("res://scenes/main.tscn").instantiate()
	add_child_autofree(arena)
	await step(2)
	var effects: ScreenEffects = arena.player.screen_effects
	arena._death_sequence.play(arena.player)
	await step(2)
	var early_brightness: float = effects.brightness
	var early_blur: float = effects.blur
	assert_almost_eq(early_brightness, 1.0, 0.05, \
		"the picture was dimmed on the very first frame of the death")
	await step(90)
	assert_lt(effects.brightness, early_brightness, "the light never went out")
	assert_gt(effects.contrast, 1.0, "the picture dimmed without steepening, which is a fade")
	assert_gt(effects.blur, early_blur, "the picture never went soft")

func test_the_next_life_is_not_played_through_the_death_grade() -> void:
	var arena: Arena = preload("res://scenes/main.tscn").instantiate()
	add_child_autofree(arena)
	await step(2)
	var effects: ScreenEffects = arena.player.screen_effects
	arena._death_sequence.play(arena.player)
	await step(120)
	assert_lt(effects.brightness, 1.0, "test setup: the grade never arrived")
	arena._death_sequence.stop()
	await step(1)
	assert_almost_eq(effects.brightness, 1.0, 0.001, "the next life started dimmed")
	assert_almost_eq(effects.contrast, 1.0, 0.001, "the next life started steepened")
	assert_almost_eq(effects.blur, 0.0, 0.001, "the next life started blurred")
