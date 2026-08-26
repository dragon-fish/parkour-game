extends ParkourTest

# Every scene in this project that draws a sky must draw THE SAME ONE, loaded
# from assets/sky/day_sky.tres. This used to be four independent
# ProceduralSkyMaterials -- one per scene, plus one built in code -- and the
# only symptom of that would have been swapping the game's sky and finding
# that one level did not follow. That is the failure this catches.
#
# Swapping which panorama day_sky.tres points at is a DECISION and does not
# fail anything here. Re-embedding a private sky in one scene is a BUG and
# does.

const SHARED_SKY := "res://assets/sky/day_sky.tres"
const SKY_DRAWING_SCENES := [
	"res://templates/base_level.tscn",
	"res://scenes/main.tscn",
	"res://scenes/debug_levels/animation_lab.tscn",
]

func test_every_scene_draws_the_one_shared_sky() -> void:
	for path in SKY_DRAWING_SCENES:
		var scene := (load(path) as PackedScene).instantiate()
		var world_env := scene.get_node_or_null("WorldEnvironment") as WorldEnvironment
		assert_not_null(world_env, "%s has no WorldEnvironment" % path)
		var environment: Environment = world_env.environment
		assert_not_null(environment.sky, "%s draws no sky at all" % path)
		assert_eq(environment.sky.resource_path, SHARED_SKY,
			"%s embeds its own sky instead of loading the shared one" % path)
		scene.free()

func test_the_shared_sky_is_a_real_panorama() -> void:
	# The point of the swap was a photographed sky, not another procedural
	# gradient. A material with no panorama loads and renders as black, which
	# is the kind of "it broke and nothing said so" this file exists for.
	var sky := load(SHARED_SKY) as Sky
	var material := sky.sky_material as PanoramaSkyMaterial
	assert_not_null(material, "day_sky.tres no longer carries a PanoramaSkyMaterial")
	assert_not_null(material.panorama, "the shared sky's panorama is empty; it would render black")
