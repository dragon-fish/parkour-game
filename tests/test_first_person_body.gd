extends ParkourTest

# The camera renders exactly one of the body's two mesh variants.
#
# VRM has a mechanism for this in the spec, and godot-vrm implements it: with
# head hiding set to Layers, the importer generates a HEADLESS variant of the
# body and puts the two on separate render layers. Measured on the owner's own
# export: "Body (Headless)" on layer 2, and Body/Face/Hair on layer 4.
#
# A camera renders every layer by default, so both variants drew at once -- and
# the face and hair sit exactly where the eye is. That is what the owner
# reported as the neck passing through the view. The model already ships the
# answer; the camera just has to pick a side.

const TestWorld = preload("res://tests/world_fixture.gd")

var _world: Dictionary = {}

func after_each() -> void:
	if _world.is_empty():
		return
	TestWorld.teardown(_world)
	_world = {}

func _rig() -> CameraRig:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	return (_world["player"] as Player).camera_rig

func test_first_person_hides_the_full_head_and_keeps_the_headless_body() -> void:
	var rig: CameraRig = await _rig()
	var cfg: CameraConfig = (_world["player"] as Player).config.camera
	await step(2)
	assert_eq(rig.camera.cull_mask & cfg.third_person_body_layers, 0, \
		"the full-head meshes are still drawn from inside the head")
	assert_eq(rig.camera.cull_mask & cfg.first_person_body_layers, \
		cfg.first_person_body_layers, "the headless body is not drawn at all")

func test_third_person_swaps_them() -> void:
	# Looking at your own body is the entire point of the third-person view, so
	# it must show the variant that HAS a head.
	var rig: CameraRig = await _rig()
	var cfg: CameraConfig = (_world["player"] as Player).config.camera
	rig.toggle_third_person()
	await step(2)
	assert_eq(rig.camera.cull_mask & cfg.first_person_body_layers, 0, \
		"the headless body is still drawn from outside, so the body has two torsos")
	assert_eq(rig.camera.cull_mask & cfg.third_person_body_layers, \
		cfg.third_person_body_layers, "the full body is not drawn")

func test_the_world_is_never_culled() -> void:
	# THE FAILURE THAT WOULD LOOK LIKE A CRASH. Every ordinary mesh in this
	# project is on layer 1, so a mask built by assignment rather than by
	# clearing two bits would render a black screen.
	var rig: CameraRig = await _rig()
	for third_person in [false, true]:
		if rig.third_person != third_person:
			rig.toggle_third_person()
		await step(2)
		assert_ne(rig.camera.cull_mask & 1, 0, \
			"layer 1 was culled with third_person=%s -- the world is invisible" % third_person)

func test_toggling_back_and_forth_does_not_accumulate() -> void:
	# The mask is edited in place every tick, so a bug that only ever CLEARS
	# bits would strip the camera down to nothing over a few toggles.
	var rig: CameraRig = await _rig()
	var cfg: CameraConfig = (_world["player"] as Player).config.camera
	await step(2)
	var first_pass: int = rig.camera.cull_mask
	for i in 4:
		rig.toggle_third_person()
		await step(2)
		rig.toggle_third_person()
		await step(2)
	assert_eq(rig.camera.cull_mask, first_pass, \
		"eight toggles changed the mask from %d to %d" % [first_pass, rig.camera.cull_mask])

func test_the_third_person_offset_is_reachable_from_the_tuning_panel() -> void:
	# THE REASON IT IS THREE FLOATS. The panel walks MovementConfig's
	# sub-resources and collects TYPE_FLOAT only, so the Vector3 this obviously
	# wants to be would never appear in it -- and framing a third-person camera
	# is the exact thing you want on a slider while running around.
	#
	# Asked of the panel's own collector rather than of the config, so this
	# fails if either side changes.
	var config := MovementConfig.new()
	var rows: Array[Dictionary] = TuningPanel.collect_tunables(config)
	var found: Array[String] = []
	for row in rows:
		var path: String = String(row["path"])
		if path.contains("third_person"):
			found.append(path)
	for wanted in ["camera.third_person_right", "camera.third_person_up", \
			"camera.third_person_back"]:
		assert_true(found.has(wanted), \
			"%s is not tunable from the panel -- found %s" % [wanted, ", ".join(found)])

# --- a body the scene did not name -----------------------------------------------

func test_a_profile_adopted_after_ready_still_attaches_its_body() -> void:
	# ✅ THE OWNER: "干脆给 main 也挂上人物模型嘛."
	#
	# ⚠️ AND IT CANNOT BE DONE IN THE SCENE. The profile points at a licensed
	# model that is not in the repository, so a committed main.tscn naming it
	# would break every checkout without it -- and fail test_generated_scenes.gd,
	# which compares the builder's output against what is committed. Only a
	# git-ignored scene can afford to reference a git-ignored resource, which is
	# why the sandbox was the only level with a body.
	#
	# So the level asks at runtime, which means asking AFTER _ready() has run --
	# and apply() sets body_scene as one of the things it sets, so the attach has
	# to be re-triggered rather than merely awaited.
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(world)
	await step(20)
	var player: Player = world["player"]
	assert_null(player.get_node_or_null("BodyRoot/fake_body"),
		"the fixture already had a body, so this proves nothing")

	var profile := BodyProfile.new()
	profile.scene = TestWorld.build_stub_body()
	player.adopt_body_profile(profile)
	await step(2)
	assert_not_null(player.body,
		"a profile adopted after _ready() attached no body")
	assert_eq(player.body_profile, profile, "the profile was not kept")
	TestWorld.teardown(world)
	await step(1)


## The head's SHADOW, which is a third thing on top of the two variants above.
##
## A mesh the camera culls does not cast either, so moving the full-head mesh to
## the third-person layer silently took its shadow with it: in first person the
## body's shadow ended at the neck, with no head shape at all, and nothing
## anywhere reported a problem. It stayed that way for a long time because you
## only see your own shadow in the right light. HeadlessVariant now adds a
## never-drawn SHADOWS_ONLY copy per split mesh; these assert the three roles
## stay distinct.
##
## Needs the real body: the split runs on actual skin weights, so a machine
## without the private asset has nothing to check and says so.
const BODY_WRAPPER := "res://assets/models/local/beriul/beriul_body.tscn"

func _split_meshes() -> Array:
	var level := (load("res://templates/base_level.tscn") as PackedScene).instantiate()
	add_child_autofree(level)
	await step(20)
	return level.find_children("*", "MeshInstance3D", true, false)

func test_every_split_mesh_keeps_exactly_one_shadow_caster() -> void:
	if not ResourceLoader.exists(BODY_WRAPPER):
		pass_test("no local body to split")
		return
	var meshes: Array = await _split_meshes()
	var by_name := {}
	for node in meshes:
		by_name[(node as MeshInstance3D).name] = node as MeshInstance3D
	var stand_ins := 0
	for name in by_name:
		if not String(name).ends_with("Shadow"):
			continue
		stand_ins += 1
		var stand_in: MeshInstance3D = by_name[name]
		assert_eq(stand_in.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY,
			"%s is drawn, not just cast -- it would double the body" % name)
		# The visible variants it stands in for must have gone quiet, or the
		# neck-cut shadow comes back layered under the correct one.
		var source: String = String(name).trim_suffix("Shadow")
		for variant in [source, source + "Headless"]:
			if by_name.has(variant):
				assert_eq((by_name[variant] as MeshInstance3D).cast_shadow,
					GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
					"%s still casts alongside its stand-in" % variant)
	assert_gt(stand_ins, 0, "the split produced no shadow stand-in at all")

func test_the_stand_in_is_reachable_from_every_camera() -> void:
	# SHADOWS_ONLY means no camera draws it, but a camera still has to have it
	# in its cull mask for it to reach the shadow map -- which is the whole
	# lesson here. Keeping the layers it arrived on (layer 1, the world layer)
	# is what guarantees that for both first and third person.
	if not ResourceLoader.exists(BODY_WRAPPER):
		pass_test("no local body to split")
		return
	var meshes: Array = await _split_meshes()
	var cfg := CameraConfig.new()
	var body_only: int = cfg.first_person_body_layers | cfg.third_person_body_layers
	for node in meshes:
		var m := node as MeshInstance3D
		if not m.name.ends_with("Shadow"):
			continue
		assert_ne(m.layers & ~body_only, 0,
			"%s sits only on a body layer, so a camera culling that layer drops its shadow" % m.name)
