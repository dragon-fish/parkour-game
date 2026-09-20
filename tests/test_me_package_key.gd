extends ParkourTest

# The same table is in the extractor's test_streaming.py: two implementations
# of one rule, and a key spelt two ways is a package that never shows.

const Common := preload("res://tools/me_level/me_level_common.gd")


func test_a_package_is_spelt_one_way() -> void:
	var table := {
		"Convoy_Roof-Conv_slc_lgts": "convoy_roof-conv_slc_lgts",
		"Convoy_Roof.me1": "convoy_roof",
		"Stormdrain_StdP_Art.ME1": "stormdrain_stdp_art",
		"boat_bac": "boat_bac",
	}
	for given: String in table:
		assert_eq(Common.package_key(given), table[given])


func test_the_builder_and_the_level_agree_on_the_meta_name() -> void:
	assert_eq(Common.PACKAGE_META, PackagePresence.PACKAGE_META)
