class_name MainMenu
extends Control

# The project's front door (menu feature, Task 5). Endfield-referenced
# composition, ME colors: a near-white background with a pulsing dot-grid
# floor, a red brand silhouette walking in a transparent SubViewport, a left
# red MeMenuList (开始/设置/退出), and the whole entrance choreographed as a
# sequence of beats (see docs/superpowers/specs/2026-08-25-menu-design.md's
# 入场编排). The whole tree is built here in _ready() rather than laid out in
# the .tscn -- scenes/ui/main_menu.tscn stays a one-node root with this
# script attached, matching this project's "code builds UI" convention
# (scripts/ui/pause_ui.gd, settings_menu.gd) and keeping the committed scene
# out of test_generated_scenes.gd's drift-guard entirely.
#
# NO MODEL, NO PROBLEM: SilhouetteBody.build() returns null on a machine with
# no body linked, and this screen treats that as "no figure in the shot".
# A fresh checkout with no model gets the complete UI --
# background, floor, red bar, title, menu, footer -- with the silhouette
# slot simply empty and the beats that only concern it (rise, camera
# pull-back, walk loop) skipped. Nothing else in the choreography depends on
# it.

signal beat_rise
signal beat_title


## What 开始 loads, and where the first-ever click goes. The tutorial is the
## first level as well as the game's front door.
const LEVEL_0_SCENE := "res://scenes/levels/level_0/level_0.tscn"

# --- entrance timing (spec: 入场编排 beats 0a-6) ----------------------------
## STAYS A CONSTANT while its neighbours became exports: MenuMusic times the
## drop against MainMenu.RISE_TIME, and a cross-class reference can only
## reach a const -- an exported var is an instance member. The coupling is
## the point (the chorus lands on the body coming up), so it is the export
## that gives way, not the coupling.
const RISE_TIME := 1.5
## The body reaches FULLY STANDING on the frame the camera lands -- same start,
## same end, one breath. Keep it equal to RISE_TIME. Easing everywhere:
## cubic-bezier(0.65, 0, 0.35, 1) = TRANS_CUBIC / EASE_IN_OUT.
@export var BODY_STAND_BLEND: float = 1.5

@export var WALK_TO_MENU_DELAY: float = 0.15
@export var MENU_PANEL_TIME: float = 0.45
@export var DRIFT_PX: float = 2.0
@export var DRIFT_HALF_PERIOD: float = 5.0
## The drift's fixed baseline; see _start_idle_drift().
const _DRIFT_BASE_Y := 0.0

# --- silhouette framing (✅ the owner's numbers, 2026-08-26 art direction) --
## Beat 0: crouched profile, head centre at screen (45%, 30%), the visible
## upper body (hips to head-top) spanning 40% of screen height, head facing
## screen RIGHT. Beat 1 pushes to the FRONT view: full body centred, 70% of
## screen height. All framing is solved at runtime from the live skeleton
## (Head/Hips bones), so a different model reframes itself.
@export var opening_framing: OpeningFraming = preload("res://presets/opening_framing.tres")
@export var FAR_BODY_FRAC: float = 0.70
## Where the standing walker sits horizontally in the settled view. The
## column moved to the RIGHT (✅ the owner: sending her left-to-right would
## cross the axis -- 越轴), so she keeps the LEFT: the centre of the open
## field left of the column, ~37%.
@export var FAR_X_FRAC: float = 0.37
## Skull above the Head bone, metres -- the bone sits at the neck end.
## The body NEVER rotates (✅ the owner: "让镜头转而不是角色模型和地板转").
## It faces +Z world for the whole show (model forward is -Z after mount,
## so yaw -180); the CAMERA orbits from her right side (azimuth 0 = profile,
## head to screen right) around to her front (azimuth 90 = facing the lens),
## and the floor pattern turns off the same azimuth -- one number, one
## rotation, nothing to desync -- and since the floor became a real plane it
## does not need telling at all: it turns because the camera moved.
## THESE THREE STAY CONSTANTS. They do not encode taste, they encode the
## rule above -- the body never turns, the camera orbits. Made draggable
## they would be an invitation to break it from the inspector, with nothing
## on screen explaining why the floor and the figure had come apart.
const FRONT_YAW_DEG := -180.0
const CLOSE_AZIMUTH_DEG := 180.0
const FAR_AZIMUTH_DEG := 90.0
## Fallbacks when no skeleton is attached (numbers measured off the current
## local model; only used to aim an empty viewport, so precision is moot).
const FALLBACK_CROUCH_HEAD := 0.82
const FALLBACK_CROUCH_HIPS := 0.51
const FALLBACK_STAND_HEAD := 1.43

# --- mirror + glitch -------------------------------------------------------
@export var MIRROR_ALPHA: float = 0.16

## The ground's own dials, mirrored off the shader so they can be dragged
## rather than found by reading GLSL. Pushed every frame, so a drag lands
## while the menu is running.
@export_group("Floor")
## METRES PER SECOND the ground slides past while she walks -- a real unit
## now that the floor is a real plane. The old number lived in the fake
## projection's own space and meant nothing outside it, so it could not be
## carried across.
##
## The direction is read off the body each frame rather than written down:
## which axis is forward is a convention argument nobody wins twice.
@export var FLOOR_SCROLL_SPEED: float = 0.55

## And the pace once she is sprinting for the loading run. A REAL SPEED, not a
## multiplier: the ground became a plane and the unit became metres per
## second, so "2.4 times the walk" was 1.3 m/s under a sprint -- a walking
## pace played against a running clip, and no amount of tuning the multiplier
## would have made that read as anything else.
@export var FLOOR_RUN_SPEED: float = 3.6

## How long the ground takes to appear once she stands. Linear on purpose: an
## ease-in-out puts most of the change in the middle, which is exactly the
## moment a fade is noticed happening.
@export var FLOOR_FADE_TIME: float = 2.4

## Dots per WORLD METRE. See the shader on why the old number could not be
## carried over when the floor became a real plane.
@export var floor_spacing: float = 6.8
## Dot radius as a fraction of a cell.
@export var floor_dot_size: float = 0.12
## How fast each dot breathes, and how far. The per-cell random phase is what
## makes that read as alive rather than as blinking.
@export var floor_pulse_speed: float = 1.2
@export var floor_pulse: float = 0.35
@export var floor_base: float = 0.35
## Metres out at which the ground starts and finishes fading away. Without it
## the cells near the horizon are finer than a pixel and boil.
@export var floor_fade_from: float = 6.0
@export var floor_fade_to: float = 26.0
@export var floor_tint: Color = Color(0.75, 0.82, 0.92, 1.0)
@export_group("")

var _background: ColorRect
var _paper_noise: ColorRect
var _floor: ColorRect
var _viewport_container: SubViewportContainer
var _viewport: SubViewport
var _silhouette_root: Node3D
var _silhouette_camera: Camera3D
var _silhouette: SilhouetteBody
var _mirror: TextureRect
var _mirror_window: Control
## Solved framing parameters (see _solve_framing()/_apply_cam()).
var _head_point := Vector3(0.0, 0.8, 0.0)
var _body_centre := Vector3(0.0, 0.8, 0.0)
var _d_close := 1.1
var _d_far := 2.3
## Screen fraction of the character's feet line in the FAR framing -- where
## the mirror's fold sits.
var _feet_screen_frac := 0.82
var _anim_player: AnimationPlayer
var _menu_list: MeMenuList
var _settings_menu: MeSettingsMenu
var _footer: Label
var _metadata_labels: Array[Control] = []
## Integrated ground flow, in metres, and the pace it is integrated at. Kept
## as an integral rather than a TIME-based shader term because the pace
## changes: a term read off TIME would teleport the pattern the moment it did.
var _floor_phase := 0.0
## Metres per second, so it can be set to a PACE rather than to a factor of
## one. See FLOOR_RUN_SPEED for what the factor cost.
var _floor_pace := 0.0
## The mark and the invitation: one shared beat, see MeOpeningPlate.
var _plate: MeOpeningPlate
var _music: MenuMusic
var _chladni: ChladniField
var _quit_confirm: Control
## The fake-load run (✅ the owner's storyboard): threaded load of the level
## while the menu keeps playing -- she sprints screen-left, camera on her
## LEFT side (azimuth 0), then a push into her eye under a white cover.
var _loading := false
var _load_min_elapsed := 0.0
var _run_orbit_t := 0.0
var _stand_head_y := 1.43

var _active_tweens: Array[Tween] = []
## False until _play_entrance() actually schedules the show. _ready()
## awaits six frames for the framing solve before that happens, and
## _unhandled_input is live for every one of them -- a white transition
## covers exactly this window. DO NOT start this true: skipping an
## entrance that has not been scheduled settles the menu, and _ready()
## then resumes into _frame_close() + _play_entrance(), reframing the
## settled menu back to the opening close-up and replaying the click
## prompt over it, with nothing left able to take input.
var _entrance_active: bool = false
var _beat_rise_fired: bool = false
var _beat_title_fired: bool = false

## Seam for the 开始 handler: swappable so a test can observe "开始 was
## pressed" without a real change_scene_to_file() replacing the scene tree
## out from under GUT's own runner mid-suite. Defaults to the real thing.
var _change_scene: Callable = Callable(self, "_real_change_scene")

## Which scene the start entry loads. A field rather than the constant used
## directly, so it can be retargeted in one place instead of at each of the
## four sites the threaded load touches.
var _target_scene: String = LEVEL_0_SCENE
## Diagnostic only -- see the [load] prints. ✅ THE OWNER: "那就加可观测性，打
## 日志，我来真的点一次看看控制台输出什么东西."
var _load_started_ms: int = 0

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_ui()
	_load_silhouette()
	# The framing is solved off the LIVE skeleton pose, which only exists
	# once the animation has actually been applied -- the measurement probe
	# needed FIVE frames before Crouch_Idle showed up in the bones, and two
	# frames here quietly measured the standing rest pose instead (the exact
	# trap this comment already warned about; six frames with margin now).
	for i in 6:
		await get_tree().process_frame
	_solve_framing()
	_frame_close()
	resized.connect(_on_resized)
	_play_entrance()

func _process(delta: float) -> void:
	if _loading:
		_poll_loading(delta)
	if _floor == null or not (_floor.material is ShaderMaterial):
		return
	# THE CAMERA, HANDED OVER WHOLE. The ground is unprojected per pixel from
	# these, so there is no separate pattern rotation to keep in step any
	# more: the plane turns because the camera does, the way a floor's would.
	_floor_phase += _floor_pace * delta
	var mat := _floor.material as ShaderMaterial
	var eye := _silhouette_camera.global_position
	var tan_v: float = tan(deg_to_rad(opening_framing.fov_degrees) * 0.5)
	mat.set_shader_parameter("eye_height", maxf(eye.y, 0.05))
	mat.set_shader_parameter("cam_yaw", _silhouette_camera.rotation.y)
	mat.set_shader_parameter("cam_pos", Vector2(eye.x, eye.z))
	mat.set_shader_parameter("tan_v", tan_v)
	mat.set_shader_parameter("tan_h", tan_v * (maxf(size.x, 1.0) / maxf(size.y, 1.0)))
	mat.set_shader_parameter("flow_phase", _floor_phase)
	# Read off the body rather than written down: model forward is -Z and
	# the root carries a yaw, so the world direction she walks is a product
	# of two conventions and neither is worth arguing about twice.
	var forward: Vector3 = -_silhouette_root.global_transform.basis.z
	mat.set_shader_parameter("flow_dir", Vector2(forward.x, forward.z).normalized())
	mat.set_shader_parameter("spacing", floor_spacing)
	mat.set_shader_parameter("dot_size", floor_dot_size)
	mat.set_shader_parameter("speed", floor_pulse_speed)
	mat.set_shader_parameter("pulse", floor_pulse)
	mat.set_shader_parameter("base", floor_base)
	mat.set_shader_parameter("fade_from", floor_fade_from)
	mat.set_shader_parameter("fade_to", floor_fade_to)
	mat.set_shader_parameter("tint", floor_tint)

func _on_resized() -> void:
	# Aspect changed: re-solve the framing math and re-aim whatever state
	# the camera is currently meant to hold.
	_solve_framing()
	if not _entrance_active:
		_apply_cam(1.0)

func _real_change_scene(path: String) -> void:
	get_tree().change_scene_to_file(path)

# ---------------------------------------------------------------------------
# Composition
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = MeTheme.ui_theme()
	# The ROOT was the click-eater: a Control defaults to MOUSE_FILTER_STOP,
	# so the full-rect root consumed every mouse press as GUI input before
	# _unhandled_input could ever see it -- keyboard worked, clicks died
	# (✅ the owner found it, annoyed, correctly).
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_background = ColorRect.new()
	_background.color = Color(0.96, 0.96, 0.94)
	_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background)

	_paper_noise = MeTheme.paper_noise_layer()
	add_child(_paper_noise)

	_build_chladni()
	_build_floor()
	_build_viewport()
	_build_mirror()
	_build_menu_list()
	_build_settings_menu()
	_build_corner_metadata()
	_build_footer()
	_build_opening_plate()
	_build_music()

## Powder on a driven plate, above the horizon and behind everything else.
## Built here rather than later so it sits at the very back: the floor, the
## silhouette and the whole menu are added after it and draw over it.
##
## STOPS AT THE HORIZON, where the floor's own dot grid begins. Two fields of
## specks overlapping would read as one noisy one, and the shader fades its
## own bottom edge out so the boundary is not a line.
## ADOPTED FROM THE SCENE, not built here. It is the one part of this screen
## that is pure art direction -- a dozen numbers chosen by eye and nothing
## solved at runtime -- so it belongs where those numbers can be dragged. A
## node created in code has no inspector at edit time, which made its dials
## reachable only by editing the script's defaults.
##
## Its position in the scene is also its layer: it is the first child, so the
## floor, the silhouette and the whole menu are added after it and draw over
## it.
func _build_chladni() -> void:
	_chladni = get_node_or_null("ChladniField") as ChladniField
	if _chladni == null:
		return
	# LIFTED ABOVE THE BACKGROUND, which is the one thing moving it into the
	# scene broke. A scene child is child zero, and the background -- an
	# opaque near-white rect -- is added by code afterwards, so it drew
	# straight over the field and the whole thing vanished. Everything after
	# this point is added later still and keeps drawing over it, which is the
	# order that was wanted all along.
	move_child(_chladni, get_child_count() - 1)
	# DERIVED, not dragged: the figure is symmetric about its own centre, so
	# that centre belongs where the character stands. Pushed from here rather
	# than typed into the scene so the two cannot drift apart.
	_chladni.centre_x = FAR_X_FRAC

func _build_floor() -> void:
	_floor = ColorRect.new()
	_floor.anchor_left = 0.0
	_floor.anchor_right = 1.0
	_floor.anchor_top = 0.5
	_floor.anchor_bottom = 1.0
	_floor.offset_left = 0.0
	_floor.offset_right = 0.0
	_floor.offset_top = 0.0
	_floor.offset_bottom = 0.0
	_floor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_floor.material = MeTheme.dot_grid_material()
	_floor.modulate.a = 0.0
	add_child(_floor)

func _build_viewport() -> void:
	# FULL-RECT, not a centred box: the camera does all the framing now (the
	# owner's screen-fraction numbers are solved in _solve_framing()), so the
	# viewport must simply BE the screen.
	_viewport_container = SubViewportContainer.new()
	_viewport_container.stretch = true
	_viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	# ✅ the owner: "角色剪影带轻微故障粒子" -- occasional sheared bands with
	# a faint chromatic split, hashed off TIME (silhouette_glitch.gdshader).
	var glitch := ShaderMaterial.new()
	glitch.shader = load("res://scripts/ui/silhouette_glitch.gdshader")
	# ✅ The owner: the tear should be a bit more present than the shader's
	# own defaults -- more frequent bursts, taller bands, a wider shear and
	# a heavier chromatic split.
	glitch.set_shader_parameter("burst_chance", 0.22)
	glitch.set_shader_parameter("band_height", 0.022)
	glitch.set_shader_parameter("shear_px", 12.0)
	glitch.set_shader_parameter("split_px", 2.6)
	_viewport_container.material = glitch
	add_child(_viewport_container)

	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1920, 1080)
	_viewport.transparent_bg = true
	_viewport.handle_input_locally = false
	_viewport_container.add_child(_viewport)

	_silhouette_root = Node3D.new()
	_silhouette_root.rotation_degrees = Vector3(0.0, FRONT_YAW_DEG, 0.0)
	_viewport.add_child(_silhouette_root)

	_silhouette_camera = Camera3D.new()
	_silhouette_camera.fov = opening_framing.fov_degrees
	_viewport.add_child(_silhouette_camera)

## The hazy floor reflection (✅ the owner: "地板平整无暇，有朦胧的镜像效果"):
## not a second 3D body -- a TextureRect showing the SAME viewport texture
## flipped vertically, folded at the character's feet line, squashed a little
## and faded down its length. Free, perfectly in sync with the animation.
func _build_mirror() -> void:
	# A clipping window from the feet line down; inside it, the WHOLE frame
	# flipped vertically and positioned so the character's feet in the
	# flipped copy meet the fold exactly -- a true mirror about the feet
	# line, not a squashed thumbnail. _mirror is the window (whose modulate
	# the entrance fades); the child does the flipping.
	_mirror = TextureRect.new()  # repurposed as the clip window's child below
	var window := Control.new()
	window.name = "MirrorWindow"
	window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	window.clip_contents = true
	add_child(window)
	move_child(window, _viewport_container.get_index())
	_mirror_window = window

	_mirror.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mirror.flip_v = true
	_mirror.stretch_mode = TextureRect.STRETCH_SCALE
	var fade := ShaderMaterial.new()
	fade.shader = load("res://scripts/ui/mirror_fade.gdshader")
	_mirror.material = fade
	window.add_child(_mirror)
	window.modulate = Color(1.0, 1.0, 1.0, 0.0)

func _sync_mirror_layout() -> void:
	if _mirror == null or _mirror_window == null:
		return
	_mirror.texture = _viewport.get_texture()
	var h: float = maxf(size.y, 1.0)
	var fold: float = _feet_screen_frac * h
	_mirror_window.position = Vector2(0.0, fold)
	_mirror_window.size = Vector2(size.x, h - fold)
	# Child spans the full frame, flipped; its top sits fold-h above the
	# window so the flipped feet line (at h - fold from its own top) lands
	# exactly on the window's top edge.
	_mirror.position = Vector2(0.0, fold - h)
	_mirror.size = Vector2(size.x, h)

func _build_menu_list() -> void:
	_menu_list = MeMenuList.new()
	# ME-style full-height column on the RIGHT, with a breathing gap off the
	# edge (✅ the owner: 菜单不要贴死右边) -- the character keeps the left,
	# preserving the opening shot's axis.
	_menu_list.custom_minimum_size = Vector2(420.0, 0.0)
	_menu_list.anchor_left = 1.0
	_menu_list.anchor_right = 1.0
	_menu_list.anchor_top = 0.0
	_menu_list.anchor_bottom = 1.0
	_menu_list.offset_left = -480.0
	_menu_list.offset_right = -60.0
	_menu_list.offset_top = 0.0
	_menu_list.offset_bottom = 0.0
	add_child(_menu_list)
	_menu_list.set_items(["开始", "角色", "设置", "退出"])
	_menu_list.chosen.connect(_on_chosen)
	# Settled instantly at build time so its rows have correct final geometry,
	# but HIDDEN (visible = false) until beat 4 (_beat_menu_stagger) actually
	# shows it and plays the stagger-in. MeMenuList._unhandled_input already
	# gates its Up/Down/Enter handling on is_visible_in_tree(), so keeping
	# this false through the logo plate / rise / bar-sweep / title-drop beats
	# mutes its input for free -- fixes a real bug (review finding): the list
	# used to be visible and interactive from frame 0, so a stray Enter
	# during the logo plate landed on 开始 and launched the game before the
	# entrance ever played. _beat_menu_stagger() and _skip_entrance() are the
	# only two places allowed to flip this back to true.
	_menu_list.skip_entrance()
	_menu_list.visible = false

func _build_settings_menu() -> void:
	_settings_menu = MeSettingsMenu.new()
	_settings_menu.visible = false
	add_child(_settings_menu)
	_settings_menu.closed.connect(_on_settings_closed)

func _build_corner_metadata() -> void:
	# The techwear metadata dressing, texts patterned on the owner's PV
	# reference. Collected into _metadata_labels so the entrance can fade
	# them in as their own parallax layer.
	var version: String = str(ProjectSettings.get_setting("application/config/version", "1.0.0"))
	var name_label: String = str(ProjectSettings.get_setting("application/config/name", "Parkour Game"))
	for spec in [
		["%s  ///" % name_label.to_upper(), 0.0, 0.0, Vector2(24.0, 18.0), false],
		["VER // %s" % version, 0.0, 0.0, Vector2(24.0, 38.0), false],
		["SYS / DIAG\n// RUNNER ID", 1.0, 0.0, Vector2(-24.0, 18.0), true],
		["+", 0.62, 0.14, Vector2(0.0, 0.0), false],
		["+", 0.86, 0.42, Vector2(0.0, 0.0), false],
		["ENV / CLEAR", 0.0, 1.0, Vector2(24.0, -56.0), false],
		["PARKOUR OS  BUILD %s" % version, 1.0, 1.0, Vector2(-24.0, -36.0), true],
	]:
		var label := MeTheme.corner_label(spec[0], spec[1], spec[2], spec[3], spec[4])
		label.modulate.a = 0.0
		add_child(label)
		_metadata_labels.append(label)

func _build_footer() -> void:
	_footer = MeTheme.footer_label("↑↓ 选择 · Enter 确认")
	# Navigation has no meaning until the menu itself exists.
	_footer.modulate.a = 0.0
	add_child(_footer)

## The held title shot loops eight restrained bars; the click drops into the
## chorus. Built last so nothing else waits on a stream load.
##
## SKIPPED HEADLESS. There is no audio device under the dummy driver, and the
## menu's own tests drive the click seam on every run -- a music node there
## would be loading a megabyte of ogg for nothing.
func _build_music() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_music = MenuMusic.new()
	_music.name = "MenuMusic"
	add_child(_music)

## Beat 0a: the white mark over the crouched close-up, and the invitation that
## joins it half a second later.
##
## THE SHARED BEAT, NOT A LOCAL ONE. The tutorial opens on the same plate, and
## the two screens must be indistinguishable up to the press -- see
## MeOpeningPlate, which owns every fraction and every timing that beat has.
## Added last of the visual children so it draws over everything.
func _build_opening_plate() -> void:
	_plate = MeOpeningPlate.new()
	_plate.name = "OpeningPlate"
	add_child(_plate)

# ---------------------------------------------------------------------------
# The figure. A SilhouetteBody: a bare model with its own AnimationPlayer and
# nothing else writing its bones. The lookup, the mounting, the library merge
# and the red paint all live there, because the tutorial's opening films the
# same stand-in and the two must not drift apart.
# ---------------------------------------------------------------------------

func _load_silhouette() -> void:
	var figure := SilhouetteBody.build()
	if figure == null:
		return
	_silhouette = figure
	_silhouette_root.add_child(figure)
	_anim_player = figure.anim_player
	figure.hold_crouch()

## Solves both camera positions from the live skeleton (✅ the owner's
## screen fractions). Perspective math: a world point p lands at NDC
## ((p.x-cam.x)/(d*tanH), (p.y-cam.y)/(d*tanV)) for a camera at distance d
## looking straight down -Z, where tanV = tan(fov/2) and tanH = tanV*aspect.
## Solving for the camera instead of the point gives every constraint below.
func _solve_framing() -> void:
	var crouch_head := FALLBACK_CROUCH_HEAD
	var crouch_hips := FALLBACK_CROUCH_HIPS
	var stand_head := FALLBACK_STAND_HEAD
	var skeleton := OpeningFraming.find_skeleton(_silhouette)
	if skeleton != null:
		var head = OpeningFraming.bone_world_position(skeleton, &"Head")
		var hips = OpeningFraming.bone_world_position(skeleton, &"Hips")
		var head_rest = OpeningFraming.bone_world_position(skeleton, &"Head", true)
		if head is Vector3 and hips is Vector3:
			crouch_head = head.y
			crouch_hips = hips.y
		if head_rest is Vector3:
			stand_head = head_rest.y
	_stand_head_y = stand_head
	var tan_v := tan(deg_to_rad(opening_framing.fov_degrees) * 0.5)
	var upper: float = maxf(crouch_head + opening_framing.head_top_padding - crouch_hips, 0.2)
	_d_close = opening_framing.distance_for_span(upper)
	_head_point = Vector3(0.0, crouch_head, 0.0)
	var stature: float = maxf(stand_head + opening_framing.head_top_padding, 0.5)
	_d_far = stature / (FAR_BODY_FRAC * 2.0 * tan_v)
	_body_centre = Vector3(0.0, stature * 0.5, 0.0)
	var feet_ndc: float = (0.0 - _body_centre.y) / (_d_far * tan_v)
	_feet_screen_frac = clampf(0.5 - feet_ndc * 0.5, 0.05, 0.95)
	_sync_mirror_layout()

## Places the camera for a blend factor t: 0 = the crouched close profile
## (azimuth 0, head at the owner's screen fractions), 1 = the centred
## full-body front view (azimuth 90). Everything interpolates through ONE
## parameter, so the orbit, the pull-out and the framing shift are a single
## continuous move -- and the floor reads the same azimuth.
func _apply_cam(t: float) -> void:
	_place_cam(lerpf(CLOSE_AZIMUTH_DEG, FAR_AZIMUTH_DEG, t),
		lerpf(_d_close, _d_far, t),
		_head_point.lerp(_body_centre, t),
		Vector2((opening_framing.head_screen_fraction.x - 0.5) * 2.0,
			(0.5 - opening_framing.head_screen_fraction.y) * 2.0) \
			.lerp(Vector2((FAR_X_FRAC - 0.5) * 2.0, 0.0), t))

## The one camera-solving primitive: azimuth around the body, distance,
## look target, and where that target should land in NDC.
func _place_cam(azimuth_deg: float, d: float, target: Vector3, ndc: Vector2) -> void:
	var screen_frac := Vector2(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5)
	var pose := opening_framing.camera_pose(target, d, deg_to_rad(azimuth_deg),
		size, screen_frac)
	_silhouette_camera.position = pose.eye
	_silhouette_camera.rotation = Vector3(0.0, pose.yaw, 0.0)

# DO NOT turn the body to face the camera's actual position. It was tried:
# framing slides the camera sideways rather than aiming it, so she is seen
# obliquely, and the thirteen degrees of correction that squares her up to
# the lens is thirteen degrees of NOT squaring her up to the frame. She is
# genuinely standing to one side, and a body facing the viewer from over
# there reads as posed. The oblique view is the honest one.

func _frame_close() -> void:
	_silhouette_root.rotation_degrees = Vector3(0.0, FRONT_YAW_DEG, 0.0)
	_apply_cam(0.0)

# ---------------------------------------------------------------------------
# Entrance choreography (spec 入场编排, beats 0a-6). One pacing Tween drives
# the timeline via intervals + callbacks; each beat's actual property
# animation runs on its own short-lived Tween, tracked in _active_tweens so
# _skip_entrance() can kill every one of them at once.
# ---------------------------------------------------------------------------

func _track(tween: Tween) -> Tween:
	_active_tweens.append(tween)
	return tween

## The rise, the camera turn, the mark leaving and the menu arriving are ONE
## event, not four in sequence -- they all launch off the click together; the
## walk takes over when the rise lands, and settle waits for the longest
## strand. The game HOLDS on the opening shot until then: crouched close-up,
## mark, breathing invitation, and nothing else moving.
func _play_entrance() -> void:
	_entrance_active = true
	_plate.open()

## The click: prompt out, and the whole show plays through to the menu.
func _begin_show() -> void:
	# THE HANDOFF, on the click itself rather than on the beat that follows it:
	# the chorus is entered at the phase the loop had reached, so the grid does
	# not break and the drop reads as something this press caused.
	if _music != null:
		_music.to_chorus()
	# The invitation goes at once and the mark over the rise that follows --
	# both on the plate's own timings, shared with the tutorial's opening.
	_plate.dismiss()
	var pacing := _track(create_tween())
	pacing.tween_callback(_beat_rise_begin)
	pacing.tween_interval(RISE_TIME)
	pacing.tween_callback(_start_walk_loop)
	pacing.tween_interval(0.3)
	pacing.tween_callback(_beat_menu_parallax)
	pacing.tween_interval(MENU_PANEL_TIME + MeMenuList.ENTRANCE_STAGGER * 3.0 + MeMenuList.TWEEN_TIME)
	pacing.tween_callback(_beat_settle)

## Frame 0 is already fully composed at build time (crouched profile and white
## mark, with the floor fully hidden); the first beat is the RISE: the body stands
## (Crouch_Idle -> Idle blend) and turns to face the camera while the camera
## eases (✅ ease-in-out) out to the centred full-body front view; the floor
## dots and the mirror arrive as it lands, while the plate takes the mark away.
func _beat_rise_begin() -> void:
	if not _beat_rise_fired:
		_beat_rise_fired = true
		beat_rise.emit()

	var floor_fade := _track(create_tween())
	floor_fade.tween_property(_floor, "modulate:a", 1.0, FLOOR_FADE_TIME)

	# Camera leads: the orbit (see _apply_cam) lands while the body is
	# still finishing its stand. The body itself only stands -- it never
	# rotates; the camera does all the turning.
	var cam := _track(create_tween())
	cam.tween_method(_apply_cam, 0.0, 1.0, RISE_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

	var body := _track(create_tween())
	body.tween_interval(_stand_up_delay())
	body.tween_callback(func() -> void:
		if _silhouette != null:
			_silhouette.start_stand_up(BODY_STAND_BLEND))

	var mirror := _track(create_tween())
	mirror.tween_property(_mirror_window, "modulate:a", MIRROR_ALPHA, RISE_TIME * 0.5) \
		.set_delay(RISE_TIME * 0.5)

func _stand_up_delay() -> float:
	return _silhouette.stand_up_delay(RISE_TIME) if _silhouette != null else 0.0

func _start_walk_loop() -> void:
	if _anim_player != null and _anim_player.has_animation(&"Walk"):
		_anim_player.play(&"Walk", 0.3)
	# The ground starts moving WITH the steps, ramping in rather than
	# jerking from zero.
	var ramp := _track(create_tween())
	ramp.tween_property(self, "_floor_pace", FLOOR_SCROLL_SPEED, 0.6) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

## The menu arrives from the LEFT in layers (✅ the owner: "从左侧分层进入
## （视差效果），非线性动画"): the red column slides in on an expo-out, the
## items ride MeMenuList's own stagger a beat later (a second, slower layer
## = the parallax), and the metadata dressing fades in last. beat_title
## keeps its name for the music hook even though the old title block is
## gone -- it marks the same moment: the UI landing.
func _beat_menu_parallax() -> void:
	if not _beat_title_fired:
		_beat_title_fired = true
		beat_title.emit()

	_menu_list.visible = true
	var footer_fade := _track(create_tween())
	footer_fade.tween_property(_footer, "modulate:a", 1.0, MENU_PANEL_TIME)
	var panel_from: float = _menu_list.position.x
	# From the RIGHT now, matching the column's new home.
	_menu_list.position.x = panel_from + 480.0
	var panel := _track(create_tween())
	panel.tween_property(_menu_list, "position:x", panel_from, MENU_PANEL_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	panel.parallel().tween_callback(_menu_list.play_entrance).set_delay(MENU_PANEL_TIME * 0.4)

	var meta := _track(create_tween())
	meta.set_parallel(true)
	for i in _metadata_labels.size():
		meta.tween_property(_metadata_labels[i], "modulate:a", 1.0, 0.3) \
			.set_delay(MENU_PANEL_TIME * 0.5 + 0.05 * i)

func _beat_settle() -> void:
	_entrance_active = false
	_start_idle_drift()

## Idempotent on purpose: _skip_entrance() can call this again after a
## previous drift tween was killed mid-oscillation; snapping back to the
## fixed _DRIFT_BASE_Y first keeps every call settling identically.
func _start_idle_drift() -> void:
	position.y = _DRIFT_BASE_Y
	var drift := _track(create_tween())
	drift.set_loops()
	drift.tween_property(self, "position:y", _DRIFT_BASE_Y + DRIFT_PX, DRIFT_HALF_PERIOD) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	drift.tween_property(self, "position:y", _DRIFT_BASE_Y - DRIFT_PX, DRIFT_HALF_PERIOD) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

## Jumps straight to the fully-settled state: every tween killed, every
## animated property at its final value.
func _skip_entrance() -> void:
	for tween in _active_tweens:
		if tween != null and tween.is_valid():
			tween.kill()
	_active_tweens.clear()

	if not _beat_rise_fired:
		_beat_rise_fired = true
		beat_rise.emit()
	if not _beat_title_fired:
		_beat_title_fired = true
		beat_title.emit()

	_floor.modulate.a = 1.0
	_plate.settle()
	_mirror_window.modulate.a = MIRROR_ALPHA
	for label in _metadata_labels:
		label.modulate.a = 1.0
	_menu_list.visible = true
	_footer.modulate.a = 1.0
	_menu_list.skip_entrance()

	_silhouette_root.rotation_degrees = Vector3(0.0, FRONT_YAW_DEG, 0.0)
	_apply_cam(1.0)
	_start_walk_loop()
	_floor_pace = FLOOR_SCROLL_SPEED

	_beat_settle()

func _unhandled_input(event: InputEvent) -> void:
	if not _entrance_active:
		return
	var is_key_press := event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo
	var is_click := event is InputEventMouseButton and (event as InputEventMouseButton).pressed
	if not (is_key_press or is_click):
		return
	if _plate.prompt_shown:
		# The invited click on the held title shot: the whole entrance plays.
		# WHERE A LAUNCH GOES IS NOT ASKED HERE. A player who has never finished
		# the tutorial never reaches this scene -- scripts/ui/boot_router.gd
		# sent him to the level instead, before this menu was ever built.
		_begin_show()
	else:
		# Mid-show impatience: jump straight to the settled menu. An entrance
		# already watched a dozen times is not worth forcing on someone in a
		# hurry, so this stays reachable for the whole show -- only the part
		# under the white sheet is out of reach, and that is PauseUi._input's
		# doing, not a guard here.
		_skip_entrance()

# ---------------------------------------------------------------------------
# Menu behavior
# ---------------------------------------------------------------------------

func _on_chosen(index: int) -> void:
	match index:
		0:
			_on_start_pressed()
		1:
			_open_showcase()
		2:
			_show_settings()
		3:
			_show_quit_confirm()

const SHOWCASE_SCENE := "res://scenes/ui/character_showcase.tscn"

## 角色: the character viewer (scripts/ui/character_showcase.gd). White
## transition per the covenant; headless keeps the bare seam for tests.
func _open_showcase() -> void:
	if not ResourceLoader.exists(SHOWCASE_SCENE):
		return
	if DisplayServer.get_name() == "headless":
		_change_scene.call(SHOWCASE_SCENE)
		return
	PauseUi.run_white_transition(load(SHOWCASE_SCENE), 0.35)

## ✅ The owner: "退出游戏按钮太干脆了，挽留一下啊……" The shared ME-styled
## confirm (MeTheme.confirm_dialog): backdrop click or 再跑一会儿 stays,
## 退出 quits.
func _show_quit_confirm() -> void:
	if _quit_confirm == null:
		_quit_confirm = MeTheme.confirm_dialog(
			"就这么走了吗？外面还有屋顶没跑完。", "再跑一会儿", "退出游戏",
			func() -> void: get_tree().quit())
		add_child(_quit_confirm)
	_quit_confirm.visible = true

const LOAD_MIN_RUN := 1.6
## She eases into the sprint -- clip speed ramps to full over this.
const RUN_RAMP_TIME := 1.2
const LOAD_ORBIT_TIME := 0.9

func _on_start_pressed() -> void:
	if _loading:
		return
	# Headless keeps the old synchronous seam (tests drive it; there is no
	# show to play without a renderer). ONLY headless -- the editor-embedded
	# window renders fine, and lumping it in here sent the owner straight
	# back to the frozen switch this feature exists to kill.
	if DisplayServer.get_name() == "headless":
		_change_scene.call(_target_scene)
		return
	_loading = true
	# Started with the load, not with the scene swap: the fade wants the whole
	# of the loading run to breathe over, and by the time the swap happens this
	# node is about to be freed anyway.
	if _music != null:
		_music.fade_out()
	_load_min_elapsed = 0.0
	_load_started_ms = Time.get_ticks_msec()
	ResourceLoader.load_threaded_request(_target_scene)
	print("[load] threaded request sent")
	play_run_look()

## Everything the loading run LOOKS like, with nothing of the loading in it:
## the menu leaves, the camera swings to her left, she breaks into a run and
## the ground sprints with her.
##
## Split out so it can be watched. It lasts about a second and a half and then
## the level takes over, which is not enough to aim a camera against -- see
## scripts/debug/menu_lab.gd, which holds this state open indefinitely and can
## slow it down.
func play_run_look() -> void:
	# UI leaves: column back out to the right, dressing fades.
	var out := _track(create_tween())
	out.set_parallel(true)
	out.tween_property(_menu_list, "position:x", _menu_list.position.x + 520.0, 0.45) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	out.tween_property(_menu_list, "modulate:a", 0.0, 0.45)
	for label in _metadata_labels:
		out.tween_property(label, "modulate:a", 0.0, 0.3)
	out.tween_property(_footer, "modulate:a", 0.0, 0.3)
	if _plate != null:
		out.tween_property(_plate.prompt, "modulate:a", 0.0, 0.2)
	# Camera swings to her LEFT (azimuth 90 -> 0) while she breaks into a
	# run toward screen-left; the floor sprints with her (same azimuth).
	var orbit := _track(create_tween())
	orbit.tween_method(_loading_orbit, 0.0, 1.0, LOAD_ORBIT_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_start_run_clip()
	var pace := _track(create_tween())
	pace.tween_property(self, "_floor_pace", FLOOR_RUN_SPEED, RUN_RAMP_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

func _loading_orbit(t: float) -> void:
	_run_orbit_t = t
	# Starts EXACTLY where the settled menu framing left her (offset left at
	# FAR_X_FRAC -- ✅ the owner caught the snap) and eases to centre as the
	# camera comes around.
	var settled_ndc := Vector2((FAR_X_FRAC - 0.5) * 2.0, 0.0)
	_place_cam(lerpf(FAR_AZIMUTH_DEG, 0.0, t), _d_far, _body_centre,
		settled_ndc.lerp(Vector2.ZERO, t))

func _start_run_clip() -> void:
	if _anim_player == null:
		return
	for clip in [&"Sprint", &"Run", &"Jog_Fwd", &"run", &"Walk"]:
		if _anim_player.has_animation(clip):
			_anim_player.play(clip, 0.4)
			# ✅ The owner: no instant full sprint -- she winds up, the clip
			# speed easing to 1x as she commits.
			_anim_player.speed_scale = 0.35
			var ramp := _track(create_tween())
			ramp.tween_property(_anim_player, "speed_scale", 1.0, RUN_RAMP_TIME) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
			return

## Polls the threaded load; when the level is ready (and the run has had
## its beat), the camera dives into her eye and the white takes over.
func _poll_loading(delta: float) -> void:
	_load_min_elapsed += delta
	var status := ResourceLoader.load_threaded_get_status(_target_scene)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS or _load_min_elapsed < LOAD_MIN_RUN:
		return
	if status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		# Fall back to the plain (blocking) switch rather than stranding
		# the player on the menu.
		_loading = false
		_change_scene.call(_target_scene)
		return
	var packed := ResourceLoader.load_threaded_get(_target_scene) as PackedScene
	_loading = false
	# THIS NUMBER COVERS ONLY _target_scene AND ITS DEPENDENCY TREE. The body,
	# the animation packs and the level's own course pieces are loaded BY PATH
	# inside Arena._ready(), so the loader was never told about them and this
	# figure cannot include them.
	print("[load] threaded load done: %d ms (the run-up held it open)" \
		% (Time.get_ticks_msec() - _load_started_ms))
	var dive := _track(create_tween())
	dive.tween_method(_fp_dive, 0.0, 1.0, 0.8) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	PauseUi.run_white_transition(packed, 0.7)

## The push into first person: distance collapses toward her eye height.
func _fp_dive(t: float) -> void:
	var eye := Vector3(0.0, _stand_head_y * 0.98, 0.0)
	_place_cam(lerpf(0.0, 20.0, t), lerpf(_d_far, 0.12, t),
		_body_centre.lerp(eye, t), Vector2.ZERO)

func _show_settings() -> void:
	_menu_list.visible = false
	_settings_menu.reload()
	_settings_menu.visible = true

func _on_settings_closed() -> void:
	_settings_menu.visible = false
	_menu_list.visible = true
