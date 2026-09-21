extends ParkourTest

# Puppet.pose(): which of a sequence's animations a moment falls in, and where
# in it. The original's InterpTrackAnimControl rules, not amounts of anything.

const PuppetScript := preload("res://scripts/level/puppet.gd")


func _puppet() -> Dictionary:
	var puppet := Node3D.new()
	puppet.set_script(PuppetScript)
	var body := Node3D.new()
	body.name = "Body"
	puppet.add_child(body)
	var player := AnimationPlayer.new()
	var library := AnimationLibrary.new()
	for entry in [["talk", 10.0], ["walk", 2.0]]:
		var animation := Animation.new()
		animation.length = entry[1]
		library.add_animation(entry[0], animation)
	player.add_animation_library("", library)
	body.add_child(player)
	add_child_autofree(puppet)
	return {puppet = puppet, player = player}


func test_a_moment_falls_in_the_last_animation_begun_by_then() -> void:
	var rig := _puppet()
	await step(1)
	var plays := [
		{animation = "talk", start = 4.0, offset = 1.0, rate = 1.0, loops = false},
		{animation = "walk", start = 20.0, offset = 0.0, rate = 2.0, loops = true}]
	rig.puppet.pose(plays, 1.0)
	assert_eq(String(rig.player.current_animation), "talk", "before anything has begun, the first is held")
	assert_almost_eq(rig.player.current_animation_position, 1.0, 0.001, "at its own starting offset")
	rig.puppet.pose(plays, 9.0)
	assert_almost_eq(rig.player.current_animation_position, 6.0, 0.001, "five seconds in, from an offset of one")
	rig.puppet.pose(plays, 19.0)
	assert_almost_eq(rig.player.current_animation_position, 10.0, 0.001, "one that does not loop holds its last frame")
	rig.puppet.pose(plays, 21.5)
	assert_eq(String(rig.player.current_animation), "walk")
	assert_almost_eq(rig.player.current_animation_position, 1.0, 0.001, "1.5 s at twice the rate is 3 s of a 2 s loop")


func test_the_sequence_owns_the_clock() -> void:
	var rig := _puppet()
	await step(1)
	rig.puppet.pose([{animation = "talk", start = 0.0, offset = 0.0, rate = 1.0, loops = false}], 3.0)
	await step(30)
	assert_almost_eq(rig.player.current_animation_position, 3.0, 0.001, "half a second later and nobody has said so: it has not moved on")


func test_an_animation_the_body_lacks_is_no_error() -> void:
	var rig := _puppet()
	await step(1)
	rig.puppet.pose([{animation = "missing", start = 0.0, offset = 0.0, rate = 1.0, loops = false}], 3.0)
	assert_eq(String(rig.player.current_animation), "")
