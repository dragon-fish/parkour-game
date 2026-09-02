extends ParkourTest

# The tutorial's own chain: the tower is not there, then it is; reaching it
# retires the wrap and takes the floor away; touching the orb records the run
# and leaves. What any of it LOOKS like is asserted nowhere, and neither is how
# long any of it takes -- every duration in LevelZero is a dial.

## A body a Checkpoint can talk to, duck-typed exactly as Player is.
class TouchLog extends Node3D:
	var touched: Checkpoint = null

	func touch_checkpoint(checkpoint: Checkpoint) -> void:
		touched = checkpoint

var _test_progress: String
var _real_progress: String

func before_all() -> void:
	_test_progress = "user://progress_test_%d.cfg" % OS.get_process_id()
	_real_progress = ProgressStore.path
	ProgressStore.path = _test_progress

func after_all() -> void:
	_delete_progress()
	ProgressStore.path = _real_progress

func before_each() -> void:
	_delete_progress()

func after_each() -> void:
	_delete_progress()

func _delete_progress() -> void:
	if FileAccess.file_exists(ProgressStore.path):
		DirAccess.remove_absolute(ProgressStore.path)

## A LevelZero with just enough around it: a tower carrying one solid slab, its
## base checkpoint and its orb -- all three under the tower, the way
## scenes/levels/level_0/tower.tscn builds them -- a director, a wrap, and a
## plain whose collision and material can both be watched.
func _level() -> Dictionary:
	var level := LevelZero.new()

	var tower := Node3D.new()
	tower.name = "Tower"
	var slab := StaticBody3D.new()
	slab.name = "Platform00"
	slab.collision_layer = 1
	tower.add_child(slab)
	var checkpoint := Checkpoint.new()
	checkpoint.name = "Checkpoint00"
	tower.add_child(checkpoint)
	var orb := Area3D.new()
	orb.name = "Orb"
	tower.add_child(orb)
	level.tower = tower
	level.tower_checkpoint = checkpoint
	level.orb = orb

	var wrap := TorusWrap.new()
	wrap.name = "TorusWrap"
	level.wrap = wrap

	var director := TutorialDirector.new()
	director.name = "TutorialDirector"
	level.director = director

	var plain := StaticBody3D.new()
	plain.name = "Plain"
	var collision := CollisionShape3D.new()
	collision.shape = BoxShape3D.new()
	plain.add_child(collision)
	var plain_mesh := MeshInstance3D.new()
	plain_mesh.mesh = BoxMesh.new()
	# A COPY, never materials/acrylic_void.tres itself. The dissolve is supposed
	# to duplicate before it paints; a test holding the real resource would let
	# a missing duplicate() repaint every later test in the same session.
	var shared := (load("res://materials/acrylic_void.tres") as ShaderMaterial).duplicate() as ShaderMaterial
	plain_mesh.material_override = shared
	plain.add_child(plain_mesh)
	level.plain = plain
	level.plain_mesh = plain_mesh
	level.plain_collision = collision

	add_child_autofree(tower)
	add_child_autofree(wrap)
	add_child_autofree(director)
	add_child_autofree(plain)
	add_child_autofree(level)
	await step(1)
	return {level = level, tower = tower, slab = slab, wrap = wrap,
		director = director, plain = plain, collision = collision,
		plain_mesh = plain_mesh, shared = shared, orb = orb,
		checkpoint = checkpoint}

func test_a_tower_that_is_not_there_yet_is_also_intangible() -> void:
	# HIDING IS NOT ENOUGH. The tower stands where the lessons are taught, so a
	# tower that is merely invisible is an invisible wall in the middle of the
	# plain -- and the player has no way to understand what he just ran into.
	var live: Dictionary = await _level()
	assert_false((live.tower as Node3D).visible, "the tower is visible before it rises")
	assert_eq((live.slab as StaticBody3D).collision_layer, 0,
		"the hidden tower is still solid")

func test_the_hidden_tower_does_not_catch_anything_that_walks_through_it() -> void:
	# An Area3D finds bodies through its MASK, so zeroing its layer leaves it
	# watching. The checkpoint at the foot of an invisible tower would then save
	# a respawn and take the floor away in the middle of the lessons.
	var live: Dictionary = await _level()
	assert_false((live.checkpoint as Area3D).monitoring,
		"the hidden tower's checkpoint is still watching")
	assert_false((live.orb as Area3D).monitoring,
		"the hidden tower's orb is still watching")
	(live.level as LevelZero).raise_tower()
	await step(1)
	assert_true((live.checkpoint as Area3D).monitoring,
		"the raised tower's checkpoint never started watching")
	assert_true((live.orb as Area3D).monitoring,
		"the raised tower's orb never started watching")

func test_raising_the_tower_gives_it_back_its_collision() -> void:
	# The other half of the same bug: a tower that comes back visible but not
	# solid drops the player straight through the thing he just climbed onto.
	var live: Dictionary = await _level()
	(live.level as LevelZero).raise_tower()
	await step(1)
	assert_true((live.tower as Node3D).visible, "the tower did not become visible")
	assert_eq((live.slab as StaticBody3D).collision_layer, 1,
		"the raised tower did not get its collision layer back")

func test_the_tower_waits_for_the_last_lesson() -> void:
	# The tower rising is the tutorial's one announcement that the lessons are
	# over. Hung on the wrong signal it stands up after the first lesson, which
	# tells the player the opposite of what it means.
	var live: Dictionary = await _level()
	assert_false((live.tower as Node3D).visible, "test setup: the tower was already up")
	(live.director as TutorialDirector).finished.emit()
	await step(1)
	assert_true((live.tower as Node3D).visible,
		"every lesson was passed and the tower did not rise")

func test_reaching_the_tower_retires_the_wrap() -> void:
	# A wrap still running while the player is on the tower teleports him off
	# it the moment he crosses a period boundary in mid-climb.
	var live: Dictionary = await _level()
	var level: LevelZero = live.level
	level._on_tower_reached(null)
	await step(1)
	assert_false((live.wrap as TorusWrap).is_physics_processing(),
		"the wrap is still running after the tower was reached")

func test_the_base_checkpoint_is_also_what_takes_the_floor_away() -> void:
	# ONE NODE, TWO CONSUMERS. The save and the show must not be able to
	# disagree about when the climb began: a floor that leaves on a trigger of
	# its own can go while the last live respawn is still out on the plain.
	var live: Dictionary = await _level()
	var level: LevelZero = live.level
	level.floor_fade_time = 0.05
	level.floor_drop_time = 0.05
	var body := TouchLog.new()
	add_child_autofree(body)
	(live.checkpoint as Checkpoint).body_entered.emit(body)
	await step(40)
	assert_eq(body.touched, live.checkpoint,
		"the node that takes the floor away is not a live checkpoint")
	assert_true((live.collision as CollisionShape3D).disabled,
		"stepping onto the tower did not start the floor leaving")

func test_the_surface_stops_being_a_mirror_not_just_a_colour() -> void:
	# WHAT MAKES THE FLOOR VISIBLE IS THE SHEEN, NOT THE COLOUR. acrylic_void
	# already carries the horizon colour as its albedo, so a fade that moves
	# base_color alone moves nothing an eye can see -- and the shader writes no
	# ALPHA, so there is no transparency to fall back on. This asserts the
	# surface stopped reflecting; how far it goes is a tuning value and is not
	# asserted.
	var live: Dictionary = await _level()
	var level: LevelZero = live.level
	level.floor_fade_time = 0.05
	level.floor_drop_time = 0.05
	var before: float = float((live.shared as ShaderMaterial).get_shader_parameter("metallic_amount"))
	var body := TouchLog.new()
	add_child_autofree(body)
	(live.checkpoint as Checkpoint).body_entered.emit(body)
	await step(40)
	var worn := (live.plain_mesh as MeshInstance3D).material_override as ShaderMaterial
	assert_lt(float(worn.get_shader_parameter("metallic_amount")), before,
		"the floor faded its colour but kept its mirror, so nothing left the screen")

func test_a_floor_with_no_shader_still_lets_the_player_off_the_plain() -> void:
	# THE MATERIAL GATES ONLY THE SHOW. A scene wired without a ShaderMaterial
	# still has to drop its floor: skipping that leaves the plain permanently
	# solid and reports nothing, which reads as "the tower beat never fired".
	var live: Dictionary = await _level()
	var level: LevelZero = live.level
	level.floor_fade_time = 0.05
	level.floor_drop_time = 0.05
	(live.plain_mesh as MeshInstance3D).material_override = null
	var body := TouchLog.new()
	add_child_autofree(body)
	(live.checkpoint as Checkpoint).body_entered.emit(body)
	await step(40)
	assert_true((live.collision as CollisionShape3D).disabled,
		"a floor with no shader material never lost its collision")

func test_the_floor_turns_into_light_and_falls_away() -> void:
	# Four ways this goes wrong and none of them can be seen from a tally: a
	# misspelled uniform aborts the whole dissolve, a surface that never fades
	# leaves a lit floor hanging in the void, collision left on makes the void
	# walkable, and a shared material painted in place repaints every other
	# scene that loads it this session.
	var live: Dictionary = await _level()
	var level: LevelZero = live.level
	var shared: ShaderMaterial = live.shared
	var before: Color = shared.get_shader_parameter("base_color")
	level.void_colour = Color(0.1, 0.2, 0.3, 1.0)
	level.floor_fade_time = 0.05
	level.floor_drop_time = 0.05
	level.floor_drop_depth = 12.0
	level.floor_dots_remaining = 0.0
	level._on_tower_reached(null)
	await step(40)

	var worn := (live.plain_mesh as MeshInstance3D).material_override as ShaderMaterial
	assert_ne(worn, shared, "the plain is still wearing the shared material")
	assert_true(shared.get_shader_parameter("base_color").is_equal_approx(before),
		"the dissolve painted the shared material instead of a copy")
	assert_true(worn.get_shader_parameter("base_color").is_equal_approx(level.void_colour),
		"the floor's surface never went")
	assert_almost_eq(float(worn.get_shader_parameter("dot_opacity")), 0.0, 0.001,
		"the dot field never went with it")
	assert_true((live.collision as CollisionShape3D).disabled,
		"the floor left but stayed walkable")
	assert_lt((live.plain as StaticBody3D).position.y, -11.0,
		"the floor never sank")

func test_touching_the_orb_records_the_tutorial_and_leaves() -> void:
	# Both halves matter and both are invisible when they fail: without the
	# record the player can never reach the main menu, and without the scene
	# change he stands on the summit with nothing happening.
	var live: Dictionary = await _level()
	var level: LevelZero = live.level
	var requested := [""]
	level._change_scene = func(path): requested[0] = path
	level._on_orb_entered(null)
	await step(1)
	assert_true(ProgressStore.tutorial_finished(),
		"reaching the orb did not record the tutorial as finished")
	assert_eq(requested[0], LevelZero.THANKS_SCENE,
		"reaching the orb did not ask for the thanks page")

func test_the_page_the_orb_asks_for_can_actually_be_loaded() -> void:
	# The seam above compares the request against the constant, so a typo in
	# the constant satisfies it and the tutorial's ending is a white screen the
	# player never comes back from.
	assert_true(ResourceLoader.exists(LevelZero.THANKS_SCENE),
		"LevelZero.THANKS_SCENE does not name a real scene")

func test_the_orb_only_ends_the_level_once() -> void:
	# The orb's volume is bigger than the ball, so a body drifting through it
	# can report more than one entry; a second white transition on top of the
	# first swaps the tree twice.
	var live: Dictionary = await _level()
	var level: LevelZero = live.level
	var asked := [0]
	level._change_scene = func(_path): asked[0] += 1
	level._on_orb_entered(null)
	level._on_orb_entered(null)
	await step(1)
	assert_eq(asked[0], 1, "the orb ended the level %d times" % asked[0])
