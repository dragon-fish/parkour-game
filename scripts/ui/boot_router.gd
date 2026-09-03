class_name BootRouter
extends Control

# The game's first scene, and the only thing that decides where a launch goes.
#
# ONE ANSWER TO ONE QUESTION. The main menu used to ask "has this player ever
# finished the tutorial?" inside its own entrance and branch there. The tutorial
# is a level with an opening of its own now, so the question is asked here,
# once, before either of them is built. DO NOT put the branch back into
# MainMenu: two places asking it is two places that can disagree, and the one
# that loses is invisible.
#
# NOTHING HOLDS THIS ON A TIMER. The plate stays up for exactly as long as the
# threaded load takes and not one frame longer -- a minimum hold is a game
# frozen on a picture with nothing left to say, which is the whole of
# docs/seamless-loading.md.

## The two doors. Both are checked by tests/test_scene_paths.gd, which walks
## every constant in this folder -- a typo here is otherwise a launch that dies
## on the first frame with nothing but a loader warning.
const LEVEL_0_SCENE := "res://scenes/levels/level_0/level_0.tscn"
const MAIN_MENU_SCENE := "res://scenes/ui/main_menu.tscn"

## The plate: the same ground and the same mark the main menu's own opening
## beat holds, so the swap into it moves nothing on screen.
##
## COPIED, NOT REFERENCED, and it has to be. MainMenu's LOGO_X_FRAC and
## friends are @export vars, and an exported var is an instance member -- a
## cross-class reference can only reach a const. Keep these equal to that
## scene's values; the hand-over is invisible only while the mark does not
## move. LOGO_TEXTURE itself IS a const there, so the artwork is shared.
const PLATE_COLOUR := Color(0.96, 0.96, 0.94)
const LOGO_X_FRAC := 0.19
const LOGO_Y_FRAC := 0.55
const LOGO_SIZE_PX := 220.0

## Seam for the scene change, same shape as MainMenu._change_scene and
## LevelZero._change_scene: a test observes where this launch was routed
## without a real scene swap replacing the tree under GUT's runner.
var _change_scene: Callable = Callable(self, "_real_change_scene")

## Which door this launch took. Decided in _ready() and never revisited.
var _target: String = MAIN_MENU_SCENE
var _loading: bool = false

func _real_change_scene(path: String) -> void:
	get_tree().change_scene_to_file(path)

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_target = _pick_target()
	_build_plate()
	# Headless keeps the bare synchronous seam -- there is no plate to hold and
	# no renderer to hold it for, and the tests drive this path.
	if DisplayServer.get_name() == "headless":
		_change_scene.call(_target)
		return
	_loading = true
	ResourceLoader.load_threaded_request(_target)
	print("[load] router requested %s" % _target)

## Where this launch goes. The tutorial is the front door until it has been
## finished once, and again for one launch whenever the settings page asks to
## replay it.
func _pick_target() -> String:
	if ProgressStore.replay_requested or not ProgressStore.tutorial_finished():
		return LEVEL_0_SCENE
	return MAIN_MENU_SCENE

func _process(_delta: float) -> void:
	if not _loading:
		return
	var status := ResourceLoader.load_threaded_get_status(_target)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	_loading = false
	var packed: PackedScene = null
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		packed = ResourceLoader.load_threaded_get(_target) as PackedScene
	if packed == null:
		# Fall back to the plain blocking switch rather than leaving the player
		# looking at a plate that will never move.
		_change_scene.call(_target)
		return
	get_tree().change_scene_to_packed(packed)

## The held picture, built here rather than laid out in the .tscn -- the same
## convention every other screen in scripts/ui follows.
##
## set_anchors_and_offsets_preset, never set_anchors_preset: the second sets
## anchors and leaves the offsets describing whatever rect the node has, which
## for a freshly built Control is 0x0. See .claude/skills/godot-ui-layout-traps.
func _build_plate() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var background := ColorRect.new()
	background.color = PLATE_COLOUR
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	add_child(MeTheme.paper_noise_layer())

	if not ResourceLoader.exists(MainMenu.LOGO_TEXTURE):
		return
	var mark := TextureRect.new()
	mark.texture = load(MainMenu.LOGO_TEXTURE)
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.anchor_left = LOGO_X_FRAC
	mark.anchor_right = LOGO_X_FRAC
	mark.anchor_top = LOGO_Y_FRAC
	mark.anchor_bottom = LOGO_Y_FRAC
	mark.offset_left = -LOGO_SIZE_PX * 0.5
	mark.offset_right = LOGO_SIZE_PX * 0.5
	mark.offset_top = -LOGO_SIZE_PX * 0.5
	mark.offset_bottom = LOGO_SIZE_PX * 0.5
	add_child(mark)
