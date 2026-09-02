extends ParkourTest

# The tutorial-finished flag, which three different screens ask about. Only
# the round trip is asserted: what the flag MEANS is decided elsewhere.

## Per PROCESS, not a fixed name: user:// is per project, so two runs of this
## suite at once would otherwise trample each other's file. Same reasoning
## as tests/test_menu.gd's settings path.
var _test_path: String
var _real_path: String

func before_all() -> void:
	_test_path = "user://progress_test_%d.cfg" % OS.get_process_id()
	_real_path = ProgressStore.path
	ProgressStore.path = _test_path

func after_all() -> void:
	_delete_file()
	ProgressStore.path = _real_path

func before_each() -> void:
	_delete_file()

func after_each() -> void:
	_delete_file()
	ProgressStore.replay_requested = false

func _delete_file() -> void:
	if FileAccess.file_exists(ProgressStore.path):
		DirAccess.remove_absolute(ProgressStore.path)

func test_a_first_run_has_not_finished_the_tutorial() -> void:
	# The first launch is the ONE case the whole feature turns on. A store
	# that read a missing file as "finished" would send a new player straight
	# to a main menu he has never earned.
	assert_false(ProgressStore.tutorial_finished(),
		"a machine with no progress file claims the tutorial is already done")

func test_finishing_the_tutorial_survives_a_round_trip() -> void:
	# The silent failure this catches: a key that defaults() does not list is
	# dropped by load_progress(), so the flag is written and never read back.
	ProgressStore.mark_tutorial_finished()
	assert_true(ProgressStore.tutorial_finished(),
		"the tutorial was marked finished and did not read back that way")

func test_the_replay_request_is_never_written_to_disk() -> void:
	# It is a "play it again NOW" request, not a preference. Persisting it
	# would put the player back into the tutorial on every launch, forever.
	ProgressStore.replay_requested = true
	ProgressStore.mark_tutorial_finished()
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(ProgressStore.path), OK, "test setup: nothing was written")
	assert_false(cfg.has_section_key("progress", "replay_requested"),
		"the session-only replay request was written to disk")
