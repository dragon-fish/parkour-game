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
# NO MODEL, NO PROBLEM: the silhouette comes from the same three-stage
# profile lookup arena.gd uses (local.cfg -> BODY_PROFILE constant -> absent
# = no body). A fresh checkout with no model gets the complete UI --
# background, floor, red bar, title, menu, footer -- with the silhouette
# slot simply empty and the beats that only concern it (rise, camera
# pull-back, walk loop) skipped. Nothing else in the choreography depends on
# it.

signal beat_rise
signal beat_title

const MAIN_SCENE := "res://scenes/main.tscn"

## Same fallback chain as scripts/level/arena.gd's BODY_PROFILE/
## LOCAL_PROFILE_CONFIG -- copied rather than shared, since Arena is level
## code and this is UI code with no business depending on it.
const BODY_PROFILE := "res://scenes/player/profiles/vrm_test.tres"
const LOCAL_PROFILE_CONFIG := "res://scenes/player/profiles/local.cfg"

# --- entrance timing (spec: 入场编排 beats 0a-6) ----------------------------
## 0a: logo plate over the crouched close-up, fake loading bar.
const LOGO_HOLD := 1.0
const RISE_TIME := 1.5
## ✅ The owner, on the harsh turn: the body starts rising WITH the camera
## but finishes AFTER it -- the camera is already squared while the body is
## still standing up -- and the camera does not fly straight: it swings an
## arc, letting the character drift screen-LEFT before centring
## (quadratic bezier through a sideways control point). Easing everywhere:
## cubic-bezier(0.65, 0, 0.35, 1) = TRANS_CUBIC / EASE_IN_OUT.
const BODY_RISE_DELAY := 0.15
const BODY_TURN_TIME := 2.2
const BODY_STAND_BLEND := 1.5
const CAM_ARC_SIDE := 0.45
const LOGO_FADE_TIME := 0.4
const WALK_TO_MENU_DELAY := 0.15
const MENU_PANEL_TIME := 0.45
const DRIFT_PX := 2.0
const DRIFT_HALF_PERIOD := 5.0
## The drift's fixed baseline; see _start_idle_drift().
const _DRIFT_BASE_Y := 0.0

# --- silhouette framing (✅ the owner's numbers, 2026-08-26 art direction) --
## Beat 0: crouched profile, head centre at screen (45%, 30%), the visible
## upper body (hips to head-top) spanning 40% of screen height, head facing
## screen RIGHT. Beat 1 pushes to the FRONT view: full body centred, 70% of
## screen height. All framing is solved at runtime from the live skeleton
## (Head/Hips bones), so a different model reframes itself.
const FRAME_FOV_DEG := 55.0
const HEAD_X_FRAC := 0.45
const HEAD_Y_FRAC := 0.34
const CLOSE_BODY_FRAC := 0.85
const FAR_BODY_FRAC := 0.70
## Skull above the Head bone, metres -- the bone sits at the neck end.
const HEAD_TOP_PAD := 0.16
## Yaw for the profile (facing screen right, camera on +Z looking -Z) and
## the front view (facing the camera). Model forward is -Z after mounting,
## the same convention the game body uses.
const PROFILE_YAW_DEG := -90.0
const FRONT_YAW_DEG := -180.0
## Fallbacks when no skeleton is attached (numbers measured off the current
## local model; only used to aim an empty viewport, so precision is moot).
const FALLBACK_CROUCH_HEAD := 0.82
const FALLBACK_CROUCH_HIPS := 0.51
const FALLBACK_STAND_HEAD := 1.43

# --- logo mark (white recolor of the codex topo emblem) --------------------
const LOGO_TEXTURE := "res://assets/ui/logo_mark_white.svg"
## Centre of the mark, as screen fractions (✅ the owner: left 20% top 66%).
const LOGO_X_FRAC := 0.19
const LOGO_Y_FRAC := 0.55
const LOGO_SIZE_PX := 220.0

# --- mirror + glitch -------------------------------------------------------
const MIRROR_ALPHA := 0.16

var _background: ColorRect
var _paper_noise: ColorRect
var _floor: ColorRect
var _viewport_container: SubViewportContainer
var _viewport: SubViewport
var _silhouette_root: Node3D
var _silhouette_camera: Camera3D
var _silhouette: Node3D
var _logo_mark: TextureRect
var _mirror: TextureRect
var _mirror_window: Control
## Solved framing (see _solve_framing()): [0] close cam pos, [1] far cam pos.
var _cam_close := Vector3(-0.1, 0.9, 1.1)
var _cam_far := Vector3(0.0, 0.8, 2.3)
## Screen fraction of the character's feet line in the FAR framing -- where
## the mirror's fold sits.
var _feet_screen_frac := 0.82
var _anim_player: AnimationPlayer
var _menu_list: MeMenuList
var _settings_menu: MeSettingsMenu
var _footer: Label
var _metadata_labels: Array[Control] = []

var _active_tweens: Array[Tween] = []
var _entrance_active: bool = true
var _beat_rise_fired: bool = false
var _beat_title_fired: bool = false

## Seam for the 开始 handler: swappable so a test can observe "开始 was
## pressed" without a real change_scene_to_file() replacing the scene tree
## out from under GUT's own runner mid-suite. Defaults to the real thing.
var _change_scene: Callable = Callable(self, "_real_change_scene")

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_ui()
	_load_silhouette()
	# The framing is solved off the LIVE skeleton pose, which only exists
	# after the animation has actually been applied -- a frame or two in
	# (the same lesson the crouch-measurement probe learned: reading bones
	# before the frame loop returns the rest pose).
	await get_tree().process_frame
	await get_tree().process_frame
	_solve_framing()
	_frame_close()
	resized.connect(_on_resized)
	_play_entrance()

func _on_resized() -> void:
	# Aspect changed: re-solve the framing math and re-aim whatever state
	# the camera is currently meant to hold.
	_solve_framing()
	if not _entrance_active:
		_silhouette_camera.position = _cam_far

func _real_change_scene(path: String) -> void:
	get_tree().change_scene_to_file(path)

# ---------------------------------------------------------------------------
# Composition
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = MeTheme.ui_theme()

	_background = ColorRect.new()
	_background.color = Color(0.96, 0.96, 0.94)
	_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background)

	_paper_noise = MeTheme.paper_noise_layer()
	add_child(_paper_noise)

	_build_floor()
	_build_viewport()
	_build_mirror()
	_build_menu_list()
	_build_settings_menu()
	_build_corner_metadata()
	_build_footer()
	_build_logo_mark()

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
	_viewport_container.material = glitch
	add_child(_viewport_container)

	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1920, 1080)
	_viewport.transparent_bg = true
	_viewport.handle_input_locally = false
	_viewport_container.add_child(_viewport)

	_silhouette_root = Node3D.new()
	_silhouette_root.rotation_degrees = Vector3(0.0, PROFILE_YAW_DEG, 0.0)
	_viewport.add_child(_silhouette_root)

	_silhouette_camera = Camera3D.new()
	_silhouette_camera.fov = FRAME_FOV_DEG
	_silhouette_camera.position = _cam_close
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
	_menu_list.custom_minimum_size = Vector2(420.0, 0.0)
	_menu_list.anchor_left = 0.0
	_menu_list.anchor_right = 0.0
	_menu_list.anchor_top = 0.5
	_menu_list.anchor_bottom = 0.5
	_menu_list.offset_left = 90.0
	_menu_list.offset_right = 90.0 + 420.0
	_menu_list.offset_top = -90.0
	_menu_list.offset_bottom = 90.0
	add_child(_menu_list)
	_menu_list.set_items(["开始", "设置", "退出"])
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
	add_child(_footer)

## Beat 0a: the simplified logo/title version pressed over the crouched
## close-up, plus a fake ~0.8s loading bar that covers the real body
## instantiation/animation merge/shader-compile cost that _load_silhouette()
## already paid by the time this is visible.
## The white emblem over the crouched silhouette (✅ the owner: codex's topo
## mark, centre at left 20% / top 66%). Fades out with the rise.
func _build_logo_mark() -> void:
	_logo_mark = TextureRect.new()
	_logo_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_logo_mark.texture = load(LOGO_TEXTURE)
	_logo_mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo_mark.anchor_left = LOGO_X_FRAC
	_logo_mark.anchor_right = LOGO_X_FRAC
	_logo_mark.anchor_top = LOGO_Y_FRAC
	_logo_mark.anchor_bottom = LOGO_Y_FRAC
	_logo_mark.offset_left = -LOGO_SIZE_PX * 0.5
	_logo_mark.offset_right = LOGO_SIZE_PX * 0.5
	_logo_mark.offset_top = -LOGO_SIZE_PX * 0.5
	_logo_mark.offset_bottom = LOGO_SIZE_PX * 0.5
	add_child(_logo_mark)

# ---------------------------------------------------------------------------
# Silhouette: profile lookup, body instancing, animation, unshaded red paint
# (arena.gd's BODY_PROFILE/local.cfg pattern; Player._wire_body_animation's
# library-merge, minus the state machine -- see this task's brief).
# ---------------------------------------------------------------------------

func _load_silhouette() -> void:
	var profile := _resolve_body_profile()
	if profile == null or profile.scene == null:
		return
	# The real pipeline never mounts a profile's raw fields directly --
	# BodyProfile.apply() always runs them through BodyTuning first
	# (scenes/player/tuning/*.json, keyed by the model's own filename,
	# default.json as the fallback -- see body_tuning.gd). Reusing those two
	# calls here rather than profile.apply() itself: that method also writes
	# a dozen Player-only fields (body_scene, body_clip_offsets, ...) that
	# this bare silhouette, with no Player around it, has nowhere to put.
	BodyTuning.apply_to(profile, BodyTuning.load_for(profile.scene.resource_path))
	var instance := profile.scene.instantiate()
	if not (instance is Node3D):
		return
	_silhouette = instance as Node3D
	_silhouette_root.add_child(_silhouette)
	_silhouette.transform = Transform3D(
		Basis.from_euler(profile.mount_rotation_degrees * (PI / 180.0)) \
			.scaled(Vector3.ONE * maxf(profile.mount_scale, 0.001)),
		profile.mount_offset)
	_merge_animation_library(_silhouette, profile.animation_libraries)
	_paint_silhouette(_silhouette)
	_anim_player = _find_animation_player(_silhouette)
	if _anim_player == null:
		return
	_ensure_clip_loops(_anim_player, &"Idle")
	_ensure_clip_loops(_anim_player, &"Walk")
	if _anim_player.has_animation(&"Crouch_Idle"):
		_anim_player.play(&"Crouch_Idle")
	elif _anim_player.has_animation(&"Idle"):
		_anim_player.play(&"Idle")

func _resolve_body_profile() -> BodyProfile:
	var path: String = BODY_PROFILE
	var local := ConfigFile.new()
	if local.load(LOCAL_PROFILE_CONFIG) == OK:
		path = str(local.get_value("body", "profile", BODY_PROFILE))
	if not ResourceLoader.exists(path):
		return null
	return load(path) as BodyProfile

## Every MeshInstance3D under the body gets an unshaded, brand-red material
## override -- turning whatever model is attached into the flat silhouette
## the spec asks for regardless of its own materials.
func _paint_silhouette(node: Node) -> void:
	if node is MeshInstance3D:
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = MeTheme.BRAND_RED
		(node as MeshInstance3D).material_override = material
	for child in node.get_children():
		_paint_silhouette(child)

## Same shape as Player._merge_animation_library (scripts/player/player.gd)
## -- copied rather than shared, since this runs against a bare instanced
## body with no Player around it at all. Existing clips win; a library only
## fills gaps.
func _merge_animation_library(body_node: Node3D, libraries: Array[PackedScene]) -> void:
	if libraries.is_empty():
		return
	var target := _find_animation_player(body_node)
	if target == null:
		return
	var library := target.get_animation_library("")
	if library == null:
		library = AnimationLibrary.new()
		target.add_animation_library("", library)
	for packed in libraries:
		if packed == null:
			continue
		var source_scene := packed.instantiate()
		if source_scene == null:
			continue
		var source := _find_animation_player(source_scene)
		if source == null:
			source_scene.free()
			continue
		for clip_name in source.get_animation_list():
			if library.has_animation(clip_name):
				continue
			library.add_animation(clip_name, source.get_animation(clip_name).duplicate())
		source_scene.free()

func _find_animation_player(root: Node) -> AnimationPlayer:
	if root == null:
		return null
	var queue: Array[Node] = [root]
	while not queue.is_empty():
		var node: Node = queue.pop_front()
		if node is AnimationPlayer:
			return node as AnimationPlayer
		for child in node.get_children():
			queue.append(child)
	return null

## Same fix as Player._ensure_clip_loops: glTF/VRM imports carry no "this
## clip loops" flag, so a merged Walk/Idle clip comes in as LOOP_NONE and
## would freeze on its last frame instead of cycling.
func _ensure_clip_loops(anim_player: AnimationPlayer, clip_name: StringName) -> void:
	var original_library := anim_player.get_animation_library("")
	if original_library == null or not original_library.has_animation(clip_name):
		return
	var library := original_library.duplicate(true) as AnimationLibrary
	library.get_animation(clip_name).loop_mode = Animation.LOOP_LINEAR
	anim_player.remove_animation_library("")
	anim_player.add_animation_library("", library)

## Solves both camera positions from the live skeleton (✅ the owner's
## screen fractions). Perspective math: a world point p lands at NDC
## ((p.x-cam.x)/(d*tanH), (p.y-cam.y)/(d*tanV)) for a camera at distance d
## looking straight down -Z, where tanV = tan(fov/2) and tanH = tanV*aspect.
## Solving for the camera instead of the point gives every constraint below.
func _solve_framing() -> void:
	var crouch_head := FALLBACK_CROUCH_HEAD
	var crouch_hips := FALLBACK_CROUCH_HIPS
	var stand_head := FALLBACK_STAND_HEAD
	var skeleton: Skeleton3D = null
	if _silhouette != null:
		for child in _silhouette.find_children("*", "Skeleton3D", true, false):
			skeleton = child
			break
	if skeleton != null:
		var head := skeleton.find_bone("Head")
		var hips := skeleton.find_bone("Hips")
		if head >= 0 and hips >= 0:
			# Live pose = the crouch (Crouch_Idle is already playing);
			# rest pose = standing, no need to play Idle just to measure.
			crouch_head = (skeleton.global_transform * skeleton.get_bone_global_pose(head)).origin.y
			crouch_hips = (skeleton.global_transform * skeleton.get_bone_global_pose(hips)).origin.y
			stand_head = (skeleton.global_transform * skeleton.get_bone_global_rest(head)).origin.y
	var tan_v := tan(deg_to_rad(FRAME_FOV_DEG) * 0.5)
	var aspect: float = maxf(size.x, 1.0) / maxf(size.y, 1.0)
	var tan_h := tan_v * aspect

	# CLOSE: the crouched upper body (hips..head-top) spans CLOSE_BODY_FRAC
	# of the screen; the head centre sits at (HEAD_X_FRAC, HEAD_Y_FRAC).
	var upper: float = maxf(crouch_head + HEAD_TOP_PAD - crouch_hips, 0.2)
	var d_close: float = upper / (CLOSE_BODY_FRAC * 2.0 * tan_v)
	var ndc_x: float = (HEAD_X_FRAC - 0.5) * 2.0
	var ndc_y: float = (0.5 - HEAD_Y_FRAC) * 2.0
	_cam_close = Vector3(
		0.0 - ndc_x * d_close * tan_h,
		crouch_head - ndc_y * d_close * tan_v,
		d_close)

	# FAR: the standing body (feet..head-top) spans FAR_BODY_FRAC, centred.
	var stature: float = maxf(stand_head + HEAD_TOP_PAD, 0.5)
	var d_far: float = stature / (FAR_BODY_FRAC * 2.0 * tan_v)
	_cam_far = Vector3(0.0, stature * 0.5, d_far)
	# Where the feet (y = 0) land on screen in the far framing -- the
	# mirror's fold line.
	var feet_ndc: float = (0.0 - _cam_far.y) / (d_far * tan_v)
	_feet_screen_frac = clampf(0.5 - feet_ndc * 0.5, 0.05, 0.95)
	_sync_mirror_layout()

func _frame_close() -> void:
	_silhouette_camera.position = _cam_close
	_silhouette_camera.rotation = Vector3.ZERO
	_silhouette_root.rotation_degrees = Vector3(0.0, PROFILE_YAW_DEG, 0.0)

# ---------------------------------------------------------------------------
# Entrance choreography (spec 入场编排, beats 0a-6). One pacing Tween drives
# the timeline via intervals + callbacks; each beat's actual property
# animation runs on its own short-lived Tween, tracked in _active_tweens so
# _skip_entrance() can kill every one of them at once.
# ---------------------------------------------------------------------------

func _track(tween: Tween) -> Tween:
	_active_tweens.append(tween)
	return tween

## ✅ THE OWNER (v3): "角色起身、转镜头、logo消失、菜单出现，这几个事情是
## 同时发生的" -- after the LOGO_HOLD, everything launches TOGETHER; the walk
## takes over when the rise lands, and settle waits for the longest strand.
func _play_entrance() -> void:
	var pacing := _track(create_tween())
	pacing.tween_interval(LOGO_HOLD)
	pacing.tween_callback(_beat_everything)
	pacing.tween_interval(RISE_TIME)
	pacing.tween_callback(_start_walk_loop)
	pacing.tween_interval(maxf(
		MENU_PANEL_TIME + MeMenuList.ENTRANCE_STAGGER * 3.0 + MeMenuList.TWEEN_TIME - RISE_TIME,
		0.0) + 0.05)
	pacing.tween_callback(_beat_settle)

func _beat_everything() -> void:
	_beat_rise_begin()
	_beat_menu_parallax()

## Frame 0 is already fully composed at build time (crouched profile, white
## mark, faint floor); the first beat is the RISE: the body stands
## (Crouch_Idle -> Idle blend) and turns to face the camera while the camera
## eases (✅ ease-in-out) out to the centred full-body front view; the white
## mark fades away with it; the floor dots and the mirror arrive as it lands.
func _beat_rise_begin() -> void:
	if not _beat_rise_fired:
		_beat_rise_fired = true
		beat_rise.emit()

	var logo_fade := _track(create_tween())
	logo_fade.tween_property(_logo_mark, "modulate:a", 0.0, LOGO_FADE_TIME) \
		.set_ease(Tween.EASE_IN)

	var floor_fade := _track(create_tween())
	floor_fade.tween_property(_floor, "modulate:a", 1.0, RISE_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# Camera leads: an arced flight (see _arc_camera) that lands while the
	# body is still finishing its stand. Body turn + stand start a beat
	# later and run longer.
	var cam := _track(create_tween())
	cam.tween_method(_arc_camera, 0.0, 1.0, RISE_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

	var body := _track(create_tween())
	body.tween_interval(BODY_RISE_DELAY)
	body.tween_callback(_start_stand_up)
	body.parallel().tween_property(_silhouette_root, "rotation_degrees:y", FRONT_YAW_DEG, BODY_TURN_TIME) \
		.set_delay(BODY_RISE_DELAY).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

	var mirror := _track(create_tween())
	mirror.tween_property(_mirror_window, "modulate:a", MIRROR_ALPHA, RISE_TIME * 0.5) \
		.set_delay(RISE_TIME * 0.5)

func _start_stand_up() -> void:
	if _anim_player != null and _anim_player.has_animation(&"Idle"):
		_anim_player.play(&"Idle", BODY_STAND_BLEND)

## Quadratic bezier from the close position to the far one, bulging
## sideways (+X) at the midpoint so the character drifts screen-left before
## centring -- ✅ the owner's sketch: the camera rounds a circle, it does
## not fly the chord.
func _arc_camera(t: float) -> void:
	var control := (_cam_close + _cam_far) * 0.5 + Vector3(CAM_ARC_SIDE, 0.08, 0.0)
	var a := _cam_close.lerp(control, t)
	var b := control.lerp(_cam_far, t)
	_silhouette_camera.position = a.lerp(b, t)

func _start_walk_loop() -> void:
	if _anim_player != null and _anim_player.has_animation(&"Walk"):
		_anim_player.play(&"Walk", 0.3)

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
	var panel_from: float = _menu_list.position.x
	_menu_list.position.x = panel_from - 480.0
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
	_logo_mark.modulate.a = 0.0
	_mirror_window.modulate.a = MIRROR_ALPHA
	for label in _metadata_labels:
		label.modulate.a = 1.0
	_menu_list.visible = true
	_menu_list.skip_entrance()

	_silhouette_camera.position = _cam_far
	_silhouette_camera.rotation = Vector3.ZERO
	_silhouette_root.rotation_degrees = Vector3(0.0, FRONT_YAW_DEG, 0.0)
	_start_walk_loop()

	_beat_settle()

func _unhandled_input(event: InputEvent) -> void:
	if not _entrance_active:
		return
	var is_key_press := event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo
	var is_click := event is InputEventMouseButton and (event as InputEventMouseButton).pressed
	if is_key_press or is_click:
		_skip_entrance()

# ---------------------------------------------------------------------------
# Menu behavior
# ---------------------------------------------------------------------------

func _on_chosen(index: int) -> void:
	match index:
		0:
			_on_start_pressed()
		1:
			_show_settings()
		2:
			get_tree().quit()

func _on_start_pressed() -> void:
	_change_scene.call(MAIN_SCENE)

func _show_settings() -> void:
	_menu_list.visible = false
	_settings_menu.reload()
	_settings_menu.visible = true

func _on_settings_closed() -> void:
	_settings_menu.visible = false
	_menu_list.visible = true
