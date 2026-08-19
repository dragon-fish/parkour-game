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

func test_tint_set_before_ready_survives_entering_the_tree() -> void:
	# A caller may set_tint() immediately after ScreenEffects.new(), before the
	# node has ever been added to a tree -- _material is still null at that
	# point. The colour must not be silently dropped: _tint_color has to be
	# the thing that carries it across _ready(), same as tint_amount already
	# does for the float half of this call.
	var fx := ScreenEffects.new()
	fx.set_tint(Color(0.0, 1.0, 0.0, 1.0), 0.5)
	tree.root.add_child(fx)
	await step(1)
	var c: Color = fx.tint_color()
	check_approx(c.r, 0.0, 0.0001, "tint red channel did not survive entering the tree")
	check_approx(c.g, 1.0, 0.0001, "tint green channel did not survive entering the tree")
	check_approx(c.b, 0.0, 0.0001, "tint blue channel did not survive entering the tree")
	check_approx(fx.tint_amount, 0.5, 0.0001, "tint amount did not survive entering the tree")
	fx.queue_free()
	await step(1)
