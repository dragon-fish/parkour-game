extends ParkourTest

# Player._ensure_clips_loop, which was 95% of the cost of loading a level.
#
# It used to take ONE clip name and, for each call, deep-copy the entire
# animation library, set one loop_mode on the copy, and swap the copy in. The
# caller handed it forty-five names and the merged UAL library holds 253
# animations -- so every level load deep-copied 253 animations forty-five times
# to set forty-five booleans. 2252 ms of a 2489 ms _ready(), behind a white
# curtain that made it look like loading.
#
# THE COPY ITSELF HAS TO STAY. The imported library is shared; writing
# loop_mode straight into it would reach every other instance and the cached
# resource behind them. Copying ONCE is the fix, and these pin the behaviour
# that has to survive it -- not the timing, which is a machine's business.
#
# Synthetic library on purpose: this needs no private body, so it runs on any
# clone.

func _player_with_clips(names: Array) -> Array:
	var library := AnimationLibrary.new()
	for name in names:
		var animation := Animation.new()
		animation.length = 1.0
		animation.loop_mode = Animation.LOOP_NONE
		library.add_animation(name, animation)
	var anim_player := AnimationPlayer.new()
	anim_player.add_animation_library("", library)
	add_child_autofree(anim_player)
	var player: Player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child_autofree(player)
	return [player, anim_player]

func test_every_named_clip_that_exists_ends_up_looping() -> void:
	var pair := _player_with_clips([&"Idle", &"Walk", &"Sprint"])
	var player: Player = pair[0]
	var anim_player: AnimationPlayer = pair[1]
	player._ensure_clips_loop(anim_player, [&"Idle", &"Walk", &"Sprint"])
	var library := anim_player.get_animation_library("")
	for name in [&"Idle", &"Walk", &"Sprint"]:
		assert_eq(library.get_animation(name).loop_mode, Animation.LOOP_LINEAR,
			"%s did not come out looping" % name)

func test_clips_not_on_the_list_are_left_alone() -> void:
	# Jump is a one-shot and is deliberately absent from the caller's list. A
	# batch that set everything it touched would break it silently.
	var pair := _player_with_clips([&"Idle", &"Jump"])
	var player: Player = pair[0]
	var anim_player: AnimationPlayer = pair[1]
	player._ensure_clips_loop(anim_player, [&"Idle"])
	var library := anim_player.get_animation_library("")
	assert_eq(library.get_animation(&"Jump").loop_mode, Animation.LOOP_NONE,
		"Jump was made to loop; it is a discrete action")

func test_a_name_the_body_does_not_have_is_skipped_not_fatal() -> void:
	# The caller's list is every clip ANY body might carry, so most bodies are
	# missing most of it. That is the normal case, not an error.
	var pair := _player_with_clips([&"Idle"])
	var player: Player = pair[0]
	var anim_player: AnimationPlayer = pair[1]
	player._ensure_clips_loop(anim_player, [&"Idle", &"NotAClipThisBodyHas"])
	var library := anim_player.get_animation_library("")
	assert_eq(library.get_animation(&"Idle").loop_mode, Animation.LOOP_LINEAR,
		"a missing name stopped the ones that were present from being set")

func test_the_shared_source_library_is_never_written_through() -> void:
	# THE REASON THE COPY EXISTS. Writing loop_mode into the imported library
	# would reach every other instance of that body and the cached resource
	# behind them -- an edit that outlives the level that made it.
	var pair := _player_with_clips([&"Idle"])
	var player: Player = pair[0]
	var anim_player: AnimationPlayer = pair[1]
	var source := anim_player.get_animation_library("")
	player._ensure_clips_loop(anim_player, [&"Idle"])
	assert_eq(source.get_animation(&"Idle").loop_mode, Animation.LOOP_NONE,
		"the source library was modified in place")
	assert_ne(anim_player.get_animation_library(""), source,
		"the player is still holding the source library rather than a copy")
