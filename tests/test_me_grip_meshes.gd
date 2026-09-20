extends GutTest

# Which of the original's meshes a hand passes into rather than collides with.
#
# The rule is matched by family, as a substring: the original spells a family
# more than one way (the Mall's cable is ZipLinePiece01 where every other
# chapter's is ZipLineBase_01_Line), and a list of whole names left the Mall's
# cable solid -- the body hanging under it was thrown off by the cable it hung
# from, two metres in.
#
# THE POST IS THE EXCEPTION and the test says so: it is the one part of a
# zipline a runner is meant to collide with.

const GeometryBuilder := preload("res://tools/me_level/geometry_builder.gd")

## A placement far from any ladder line, so only the name decides.
func _placement() -> Dictionary:
	return {"aabb": {"min": [0.0, 0.0, 0.0], "max": [1.0, 1.0, 1.0]}}

func _is_grip(mesh_name: String) -> bool:
	return GeometryBuilder.new()._is_grip(mesh_name, _placement(), PackedVector3Array())

func test_every_spelling_of_a_cable_is_passed_into() -> void:
	# Both spellings the original uses, and the brackets the cable runs through.
	for mesh_name in ["S_ZipLineBase_01_Line", "S_ZipLinePiece", "S_ZipLinePiece01",
			"S_ZipLineBase_01b", "S_ZipLineBase_01c", "S_ZipLineBase_01d"]:
		assert_true(_is_grip(mesh_name), "%s should be passed into, not collided with" % mesh_name)

func test_the_zipline_post_stays_solid() -> void:
	# Running through the post reads wrong; only its brackets and cable are
	# things a hand passes into.
	assert_false(_is_grip("S_ZipLineBase_01"), "the zipline post lost its collision")
	assert_false(_is_grip("S_ZipLineBase_01@Mall_R1"), "a variant of the post lost its collision")

func test_the_ladder_and_swing_families_are_passed_into() -> void:
	for mesh_name in ["S_LadderSystem_01a", "S_LadderSystem_01b", "S_LadderSystem_01c",
			"S_SwingPole_01b", "S_SwingPole_01c", "S_SwingPole_01d", "S_SwingPole_01e",
			"S_SwingPole_01f", "S_Cable_01"]:
		assert_true(_is_grip(mesh_name), "%s should be passed into, not collided with" % mesh_name)

func test_ordinary_geometry_is_untouched() -> void:
	# The families are narrow on purpose: nothing else in the game matches them.
	for mesh_name in ["S_R_02_02_F_v2_facade", "S_MallFloors_01", "S_Elevator_01",
			"S_Truckbase_02", "S_CableBoxStraight_01", "S_CableSystem_01a"]:
		assert_false(_is_grip(mesh_name), "%s was wrongly freed of its collision" % mesh_name)
