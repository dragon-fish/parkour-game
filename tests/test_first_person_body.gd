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
