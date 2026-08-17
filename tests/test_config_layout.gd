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
	check_approx(config.pawn.gravity, 8.0, 0.0001, "gravity moved but changed")
	check_approx(config.pawn.ground_speed, 7.2, 0.0001, "ground_speed moved but changed")
	check_approx(config.pawn.accel_rate, 60.0, 0.0001, "ground_accel moved but changed")
	check_approx(config.camera.fov_base, 90.0, 0.0001, "fov_base moved but changed")
	check_approx(config.camera.eye_height, 0.7, 0.0001, "eye_height moved but changed")
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
