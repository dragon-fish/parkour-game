extends GutTest

# The lighting setting of an extracted Mirror's Edge level
# (SettingsStore.LIGHTING_MODES): classic draws the original's bake, modern the
# plain materials under live light. What the switch reaches and what it leaves
# alone; the tutorial's tests read its generated geometry when this machine
# has it, and pass otherwise.

const Common := preload("res://tools/me_level/me_level_common.gd")
const MeLibrary := preload("res://tools/me_level/mesh_library.gd")
const EnvironmentScript := preload("res://tools/me_level/me_environment.gd")
const LightsScript := preload("res://tools/me_level/me_lights.gd")
const ShadowLight := preload("res://tools/me_level/me_shadow_light.gd")
const TUTORIAL_GEOMETRY := "res://scenes/local_debug_levels/mirrors_edge/sp00_tutorial_geometry.scn"

var _real_settings_path: String


func before_all() -> void:
	_real_settings_path = SettingsStore.path
	SettingsStore.path = "user://settings_test_lighting_%d.cfg" % OS.get_process_id()


func after_all() -> void:
	if FileAccess.file_exists(SettingsStore.path):
		DirAccess.remove_absolute(SettingsStore.path)
	SettingsStore.path = _real_settings_path


func after_each() -> void:
	SettingsStore.lighting_mode = "classic"


class Follower extends Node:
	var modes: Array[String] = []

	func use_lighting(mode: String) -> void:
		modes.append(mode)


func test_classic_is_the_default_and_the_setting_round_trips() -> void:
	assert_eq(SettingsStore.defaults().lighting, "classic")
	var saved := SettingsStore.defaults()
	saved.lighting = "modern"
	SettingsStore.save_settings(saved)
	assert_eq(SettingsStore.load_settings().lighting, "modern")


func test_the_setting_reaches_what_follows_it_now_and_later() -> void:
	var early := Follower.new()
	add_child_autofree(early)
	SettingsStore.follow_lighting(early)
	assert_eq(early.modes, ["classic"] as Array[String], "a follower is told the mode as it joins")
	var s := SettingsStore.defaults()
	s.lighting = "modern"
	SettingsStore.apply_global(s)
	assert_eq(early.modes.back(), "modern", "applying the setting did not reach a follower in the tree")
	var late := Follower.new()
	add_child_autofree(late)
	SettingsStore.follow_lighting(late)
	assert_eq(late.modes, ["modern"] as Array[String], "a section loaded afterwards was not told the mode")
	s.lighting = "nonsense"
	SettingsStore.apply_global(s)
	assert_eq(SettingsStore.lighting_mode, "classic", "an unknown mode from an old file was taken as it is")


func test_the_environment_switches_gi_and_the_suns_reach() -> void:
	var node := EnvironmentScript.new()
	node.lightmapped = true
	node._env = Environment.new()
	node._sun = DirectionalLight3D.new()
	node.use_lighting("modern")
	assert_true(node._env.sdfgi_enabled, "modern lighting has no SDFGI")
	assert_ne(node._sun.light_cull_mask & Common.BAKED_LAYER, 0, "the modern sun does not light the static world")
	node.use_lighting("classic")
	assert_false(node._env.sdfgi_enabled, "classic lighting kept SDFGI over the bake")
	assert_false(node._env.ssao_enabled)
	assert_eq(node._sun.light_cull_mask & Common.BAKED_LAYER, 0, "the classic sun lights the bake a second time")
	node._sun.free()
	node.free()


func test_a_level_without_a_bake_is_lit_one_way_only() -> void:
	var node := EnvironmentScript.new()
	node.lightmapped = false
	assert_false(node.baked())
	node.lighting = "classic"
	assert_false(node.baked(), "a level with no bake was drawn from one")
	node.free()


func test_world_lamps_follow_the_mode_and_character_lamps_do_not() -> void:
	var lights := Node3D.new()
	lights.set_script(LightsScript)
	var world := OmniLight3D.new()
	world.set_meta("me_brightness", 2.0)
	world.light_cull_mask &= ~Common.BAKED_LAYER
	var character := OmniLight3D.new()
	character.set_meta("me_brightness", 2.0)
	character.set_meta(Common.CHARACTER_ONLY_META, true)
	character.light_cull_mask = 1 << 3
	lights.add_child(world)
	lights.add_child(character)
	add_child_autofree(lights)
	lights.use_lighting("modern")
	assert_ne(world.light_cull_mask & Common.BAKED_LAYER, 0, "a world lamp does not light the world in modern")
	assert_eq(character.light_cull_mask, 1 << 3, "a lamp for what moves was turned on the world")
	assert_almost_eq(world.light_energy, 2.0 * lights.modern_energy_scale, 1e-5)
	lights.use_lighting("classic")
	assert_eq(world.light_cull_mask & Common.BAKED_LAYER, 0, "a world lamp lights the bake in classic")
	assert_almost_eq(world.light_energy, 2.0 * lights.energy_scale, 1e-5)


func test_the_shadow_light_stays_dark_in_modern() -> void:
	var light := ShadowLight.new()
	add_child_autofree(light)
	light.visible = true
	light.use_lighting("modern")
	assert_false(light.visible)
	light._physics_process(0.016)
	assert_false(light.visible, "the shadow light came back on under modern lighting")


## No lightmapped material is drawn anywhere in modern, every baked surface
## draws a plain one, and classic puts the file's materials back.
func test_the_tutorials_baked_world_swaps_its_materials_both_ways() -> void:
	if not ResourceLoader.exists(TUTORIAL_GEOMETRY):
		pass_test("no tutorial geometry on this machine")
		return
	var root: Node = (load(TUTORIAL_GEOMETRY) as PackedScene).instantiate()
	add_child_autofree(root)
	var before := _drawn(root)
	assert_gt(_count_lightmapped(before), 2000, "test setup: the file draws too little from its bake")
	root.use_lighting("modern")
	var modern := _drawn(root)
	assert_eq(_count_lightmapped(modern), 0, "modern lighting still draws surfaces from the bake")
	var unlit := 0
	for key in modern:
		for material: Material in modern[key]:
			if material == null:
				unlit += 1
	assert_eq(unlit, 0, "baked surfaces left with no material in modern")
	root.use_lighting("classic")
	assert_eq(_drawn(root), before, "classic did not restore what the file draws")


func test_the_tutorials_runner_vision_paints_with_the_overlay_in_modern() -> void:
	if not ResourceLoader.exists(TUTORIAL_GEOMETRY):
		pass_test("no tutorial geometry on this machine")
		return
	var root: Node = (load(TUTORIAL_GEOMETRY) as PackedScene).instantiate()
	add_child_autofree(root)
	var targets: Array[RunnerVisionTarget] = []
	for node in root.find_children("*", "Node3D", true, false):
		if node is RunnerVisionTarget and (node as RunnerVisionTarget).paint_in_material:
			targets.append(node)
	assert_gt(targets.size(), 50, "test setup: too few baked Runner Vision targets")
	root.use_lighting("modern")
	assert_eq(targets.filter(func(t: RunnerVisionTarget) -> bool: return t.paint_in_material).size(), 0,
			"a target still paints in a material modern lighting does not draw")
	root.use_lighting("classic")
	assert_eq(targets.filter(func(t: RunnerVisionTarget) -> bool: return not t.paint_in_material).size(), 0)


## Baked instance -> what each surface draws: its override, or its mesh's own.
func _drawn(root: Node) -> Dictionary:
	var out := {}
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if instance.layers & Common.BAKED_LAYER == 0 or instance.mesh == null:
			continue
		var materials: Array[Material] = []
		for surface in instance.get_surface_override_material_count():
			var material := instance.get_surface_override_material(surface)
			if material == null and surface < instance.mesh.get_surface_count():
				material = instance.mesh.surface_get_material(surface)
			materials.append(material)
		out[instance] = materials
	return out


func _count_lightmapped(drawn: Dictionary) -> int:
	var count := 0
	for key in drawn:
		for material: Material in drawn[key]:
			if material is ShaderMaterial and (material as ShaderMaterial).shader in MeLibrary.LIGHTMAP_SHADERS.values():
				count += 1
	return count
