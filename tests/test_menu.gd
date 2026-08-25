extends ParkourTest

# Minimal smoke tests for the ME theme factory (Task 1 of the menu feature).
# Structural only: MeTheme is a static, stateless factory, and the two
# gdshader resources have no visual output to assert on here -- later menu
# tasks exercise them in a real scene. What matters at this layer is that
# the factories hand back the right shapes and that both shaders actually
# compile (a ShaderMaterial with shader == null, or a Godot shader-compile
# error printed to stderr, is the failure mode this guards against).

func test_button_style_is_a_leaning_stylebox() -> void:
	var style := MeTheme.button_style(MeTheme.BRAND_RED)
	assert_not_null(style, "button_style returned nothing")
	assert_eq(style.bg_color, MeTheme.BRAND_RED, "button_style dropped the requested bg color")
	assert_true(style.skew.x < 0.0, "button_style is not leaning (skew.x >= 0)")

func test_wave_material_loads_its_shader() -> void:
	var material := MeTheme.wave_material(6.0)
	assert_not_null(material, "wave_material returned nothing")
	assert_not_null(material.shader, "wave_material's ShaderMaterial has no Shader resource")
	assert_eq(material.get_shader_parameter("amplitude_px"), 6.0, "amplitude_px was not applied")

func test_dot_grid_material_loads_its_shader() -> void:
	var material := MeTheme.dot_grid_material()
	assert_not_null(material, "dot_grid_material returned nothing")
	assert_not_null(material.shader, "dot_grid_material's ShaderMaterial has no Shader resource")
