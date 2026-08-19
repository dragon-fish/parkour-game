class_name TestScreenEffects
extends TestCase

# The effect layer holds NO time logic: states drive it with plain numbers and
# do their own fading. That split is what keeps "how a landing feels" in the
# landing state instead of smeared across a shader wrapper.

func _effects() -> ScreenEffects:
	var fx := ScreenEffects.new()
	tree.root.add_child(fx)
	return fx

func test_it_starts_neutral() -> void:
	var fx := _effects()
	await step(1)
	check_approx(fx.tint_amount, 0.0, 0.0001, "tint is not neutral at rest")
	check_approx(fx.desaturation, 0.0, 0.0001, "desaturation is not neutral at rest")
	check_approx(fx.blur, 0.0, 0.0001, "blur is not neutral at rest")
	fx.queue_free()
	await step(1)

func test_each_channel_is_independent() -> void:
	var fx := _effects()
	await step(1)
	fx.set_desaturation(1.0)
	check_approx(fx.tint_amount, 0.0, 0.0001, "setting desaturation moved the tint")
	check_approx(fx.blur, 0.0, 0.0001, "setting desaturation moved the blur")
	check_approx(fx.desaturation, 1.0, 0.0001, "desaturation did not take")
	fx.queue_free()
	await step(1)

func test_values_are_clamped() -> void:
	# States interpolate these every tick; a caller that overshoots by a hair
	# must not produce an out-of-range uniform.
	var fx := _effects()
	await step(1)
	fx.set_desaturation(1.4)
	check_approx(fx.desaturation, 1.0, 0.0001, "desaturation exceeded 1")
	fx.set_blur(-0.2)
	check_approx(fx.blur, 0.0, 0.0001, "blur went below 0")
	fx.queue_free()
	await step(1)
