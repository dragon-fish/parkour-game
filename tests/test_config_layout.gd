class_name TestConfigLayout
extends TestCase

# Pins the layout AND the values a fresh MovementConfig hands out, so the
# migration from the old flat resource can be shown to have changed nothing
# but where the numbers live. One representative field per sub-resource --
# this is a structure test, not a re-transcription of the whole table.

func test_a_fresh_config_builds_every_sub_resource() -> void:
	var config := MovementConfig.new()
	check(config.pawn != null, "pawn config missing")
	check(config.camera != null, "camera config missing")
	check(config.walking != null, "walking config missing")
	check(config.jump != null, "jump config missing")
	check(config.falling != null, "falling config missing")
	check(config.landing != null, "landing config missing")
	check(config.slide != null, "slide config missing")
	check(config.crouch != null, "crouch config missing")
	check(config.speed_vault != null, "speed_vault config missing")
	check(config.grab != null, "grab config missing")
	check(config.wall_run != null, "wall_run config missing")
	check(config.wallrun_jump != null, "wallrun_jump config missing")

func test_two_configs_do_not_share_their_sub_resources() -> void:
	# Player.setup() already duplicates the collision capsule for exactly this
	# reason. An @export default built with .new() is evaluated per instance,
	# but that is worth pinning rather than assuming: a shared sub-resource
	# would let one player's F1 slider retune every other player in the scene,
	# and in the test suite, retune the next test file's world.
	var a := MovementConfig.new()
	var b := MovementConfig.new()
	check(a.pawn != b.pawn, "two configs share one PawnConfig instance")
	check(a.slide != b.slide, "two configs share one SlideConfig instance")

func test_migrated_values_are_unchanged() -> void:
	var config := MovementConfig.new()
	# Repinned, not "unchanged": gravity is the one migrated value that turned
	# out to be wrong. 800 is what DefaultGame.ini says; 1600 is what the game
	# does (02 §2.4, measured across 22 jumps).
	check_approx(config.pawn.gravity, 16.0, 0.0001, "gravity is not the measured 16.0")
	check_approx(config.pawn.ground_speed, 7.2, 0.0001, "ground_speed moved but changed")
	check_approx(config.pawn.accel_rate, 61.44, 0.0001, "accel_rate is not the confirmed 61.44")
	check_approx(config.camera.fov_base, 90.0, 0.0001, "fov_base moved but changed")
	# NOT a migrated value any more: eye_height moved to the confirmed
	# BaseEyeHeight = 76 uu (09 §9.1). Repinned rather than dropped, because
	# tools/player_builder.gd bakes it into player.tscn's CameraRig position --
	# see tests/test_generated_scenes.gd, which is what catches the two going
	# out of step.
	check_approx(config.camera.eye_height, 0.76, 0.0001, "eye_height is not the confirmed 0.76")
	# The sliding eye must not rise above the crouched capsule's top, so this
	# one is DERIVED from eye_height rather than independent of it. Pinned as a
	# RELATIONSHIP: retuning eye_height alone must not be allowed to silently
	# poke the camera through the low tunnels sliding exists to fit under.
	check_greater(config.camera.slide_camera_drop, config.camera.eye_height, \
		"slide_camera_drop no longer covers eye_height -- the sliding eye now sits above the crouched capsule")
	check_approx(config.slide.slide_capsule_height, 0.9, 0.0001, "slide capsule moved but changed")
	check_approx(config.crouch.speed_modifier, 0.4, 0.0001, "crouch pct moved but changed")

func test_move_config_defaults_are_neutral() -> void:
	# A Move that declares nothing must behave exactly as it did before this
	# layer existed: full speed, full friction, no cooldown, no look clamp.
	var cfg := MoveConfig.new()
	check_approx(cfg.speed_modifier, 1.0, 0.0001, "default speed_modifier is not neutral")
	check_approx(cfg.friction_modifier, 1.0, 0.0001, "default friction_modifier is not neutral")
	check_approx(cfg.redo_move_time, 0.0, 0.0001, "default redo_move_time is not zero")
	check(not cfg.constrain_look, "look is constrained by default")
