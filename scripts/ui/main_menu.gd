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
const LOGO_TIME := 0.8
## 0b: plate dissolve, rise, camera pull-back.
const RISE_TIME := 1.2
const LOGO_FADE_TIME := 0.3
## Beat 2: red bar sweep-in, read as "<delay>s <description> (<duration>s)".
const BAR_DELAY := 0.2
const BAR_TIME := 0.3
## Sweep bar edge-wave (see _build_sweep_bar()): amplitude for both halves,
## and the seed values for their four edges -- the two touching INNER edges
## share _SWEEP_SEAM_SEED so they erode identically and close without a gap;
## the two OUTER edges just keep the shader's own defaults (0.0 / 3.7).
const _SWEEP_AMPLITUDE_PX := 6.0
const _SWEEP_SEAM_SEED := 1.4
const _SWEEP_OUTER_SEED_LEFT := 0.0
const _SWEEP_OUTER_SEED_RIGHT := 3.7
## Beat 3: title drop, plus the one-shot glitch jitter.
const TITLE_DELAY := 0.4
const TITLE_DROP_TIME := 0.22
const GLITCH_STEP_TIME := 0.03
const GLITCH_PX := 3.0
## Beat 4: menu stagger (kept in sync with MeMenuList's own constants below).
const MENU_DELAY := 0.5
## Beat 6: idle drift, ±2px @ 0.1Hz -> a 10s full cycle, 5s each leg.
const DRIFT_PX := 2.0
const DRIFT_HALF_PERIOD := 5.0
## Fixed rather than read from the live position -- see _start_idle_drift().
const _DRIFT_BASE_Y := 0.0

# --- silhouette camera framing (visually untunable headless -- see report) -
const _CAMERA_CLOSE_POS := Vector3(-0.45, 1.05, 1.15)
const _CAMERA_CLOSE_ROT_DEG := Vector3(-6.0, 24.0, 0.0)
const _CAMERA_FAR_POS := Vector3(0.0, 0.95, 2.6)
const _CAMERA_FAR_ROT_DEG := Vector3(-4.0, 0.0, 0.0)
const _BODY_CROUCH_OFFSET := Vector3(-0.45, -0.35, 0.0)

var _background: ColorRect
var _paper_noise: ColorRect
var _floor: ColorRect
var _viewport_container: SubViewportContainer
var _viewport: SubViewport
var _silhouette_root: Node3D
var _silhouette_camera: Camera3D
var _silhouette: Node3D
var _anim_player: AnimationPlayer
var _bar_left: ColorRect
var _bar_right: ColorRect
var _title_block: Control
var _title_final_position: Vector2
var _menu_list: MeMenuList
var _settings_menu: MeSettingsMenu
var _logo_plate: Control
var _loading_bar_fill: ColorRect
var _loading_bar_full_width: float = 160.0
var _footer: Label

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
	_play_entrance()

func _real_change_scene(path: String) -> void:
	get_tree().change_scene_to_file(path)

# ---------------------------------------------------------------------------
# Composition
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_background = ColorRect.new()
	_background.color = Color(0.96, 0.96, 0.94)
	_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background)

	_paper_noise = ColorRect.new()
	_paper_noise.color = Color(1.0, 1.0, 1.0, 1.0)
	_paper_noise.set_anchors_preset(Control.PRESET_FULL_RECT)
	_paper_noise.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var noise_material := ShaderMaterial.new()
	noise_material.shader = preload("res://scripts/ui/paper_noise.gdshader")
	_paper_noise.material = noise_material
	add_child(_paper_noise)

	_build_floor()
	_build_viewport()
	_build_sweep_bar()
	_build_title_block()
	_build_menu_list()
	_build_settings_menu()
	_build_corner_metadata()
	_build_footer()
	_build_logo_plate()

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
	_viewport_container = SubViewportContainer.new()
	_viewport_container.stretch = true
	_viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport_container.anchor_left = 0.5
	_viewport_container.anchor_right = 0.5
	_viewport_container.anchor_top = 0.5
	_viewport_container.anchor_bottom = 0.5
	_viewport_container.offset_left = -450.0
	_viewport_container.offset_right = 450.0
	_viewport_container.offset_top = -500.0
	_viewport_container.offset_bottom = 500.0
	add_child(_viewport_container)

	_viewport = SubViewport.new()
	_viewport.size = Vector2i(900, 1000)
	_viewport.transparent_bg = true
	_viewport.handle_input_locally = false
	_viewport_container.add_child(_viewport)

	_silhouette_root = Node3D.new()
	_silhouette_root.position = _BODY_CROUCH_OFFSET
	_viewport.add_child(_silhouette_root)

	_silhouette_camera = Camera3D.new()
	_silhouette_camera.position = _CAMERA_CLOSE_POS
	_silhouette_camera.rotation_degrees = _CAMERA_CLOSE_ROT_DEG
	_viewport.add_child(_silhouette_camera)

## The horizontal red band that sweeps in from both edges (beat 2), separate
## from MeMenuList's own vertical red column. Two halves, each grown from its
## own outer-screen pivot toward the middle (see _sync_sweep_bar_layout()'s
## pivot_offset math -- the left bar's default top-left pivot already sits
## on the screen-left edge, but the right bar needs its pivot pushed out to
## its own top-RIGHT corner, or scale.x would grow it away from center
## instead of toward it).
##
## Carries MeTheme.wave_material after all (spec's edge-wave rule has no
## carve-out for this bar): the two INNER edges -- the left bar's right edge
## and the right bar's left edge -- are the ones that meet at screen-center
## once both halves are fully swept in, and giving them the SAME seed makes
## wave(UV.y, seed) erode identically at every y along that seam, closing it
## instead of leaving a gap. The two OUTER edges, which nothing touches,
## keep the shader's own default seeds.
func _build_sweep_bar() -> void:
	_bar_left = _make_sweep_half(0.0, 0.5, false, _SWEEP_OUTER_SEED_LEFT, _SWEEP_SEAM_SEED)
	_bar_right = _make_sweep_half(0.5, 1.0, true, _SWEEP_SEAM_SEED, _SWEEP_OUTER_SEED_RIGHT)

func _make_sweep_half(anchor_left: float, anchor_right: float, pivot_at_right: bool, \
		seed_left: float, seed_right: float) -> ColorRect:
	var bar := ColorRect.new()
	bar.color = MeTheme.BRAND_RED
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.anchor_left = anchor_left
	bar.anchor_right = anchor_right
	bar.anchor_top = 0.42
	bar.anchor_bottom = 0.58
	bar.offset_left = 0.0
	bar.offset_right = 0.0
	bar.offset_top = 0.0
	bar.offset_bottom = 0.0
	bar.scale = Vector2(0.0, 1.0)

	var material := MeTheme.wave_material(_SWEEP_AMPLITUDE_PX)
	material.set_shader_parameter("seed_left", seed_left)
	material.set_shader_parameter("seed_right", seed_right)
	bar.material = material

	add_child(bar)
	# width_px (the shader's own px->UV conversion) and, for the right bar,
	# pivot_offset both depend on the bar's actual laid-out size, which is
	# not real until a layout pass has happened -- same ordering issue
	# me_menu_list.gd's _sync_overlays() documents. Synced once deferred and
	# again on every resize.
	bar.resized.connect(_sync_sweep_bar_layout.bind(bar, pivot_at_right))
	call_deferred("_sync_sweep_bar_layout", bar, pivot_at_right)
	return bar

func _sync_sweep_bar_layout(bar: ColorRect, pivot_at_right: bool) -> void:
	if pivot_at_right:
		bar.pivot_offset = Vector2(bar.size.x, 0.0)
	if bar.material is ShaderMaterial:
		(bar.material as ShaderMaterial).set_shader_parameter("width_px", maxf(bar.size.x, 1.0))

func _build_title_block() -> void:
	_title_block = Control.new()
	_title_block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_block.position = Vector2(140.0, 90.0)
	_title_block.size = Vector2(520.0, 100.0)
	_title_block.modulate.a = 0.0
	add_child(_title_block)
	_title_final_position = _title_block.position

	var title_label := Label.new()
	title_label.text = str(ProjectSettings.get_setting("application/config/name", "Parkour Game"))
	title_label.add_theme_font_size_override("font_size", 40)
	title_label.add_theme_color_override("font_color", Color(0.08, 0.08, 0.08))
	title_label.add_theme_constant_override("outline_size", 0)
	_title_block.add_child(title_label)

	var accent := ColorRect.new()
	accent.color = MeTheme.BRAND_RED
	accent.position = Vector2(4.0, 56.0)
	accent.size = Vector2(180.0, 6.0)
	_title_block.add_child(accent)

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
	# Settled instantly at build time -- _play_entrance() re-triggers the
	# stagger for beat 4; a fresh MainMenu that never plays an entrance (e.g.
	# a test that only wants the list) still starts fully visible.
	_menu_list.skip_entrance()

func _build_settings_menu() -> void:
	_settings_menu = MeSettingsMenu.new()
	_settings_menu.visible = false
	add_child(_settings_menu)
	_settings_menu.closed.connect(_on_settings_closed)

func _build_corner_metadata() -> void:
	var version: String = str(ProjectSettings.get_setting("application/config/version", "v0.1-dev"))
	_add_corner_label("+", 0.0, 0.0, Vector2(20.0, 16.0))
	_add_corner_label("+", 1.0, 0.0, Vector2(-20.0, 16.0), true)
	_add_corner_label("+", 0.0, 1.0, Vector2(20.0, -32.0))
	_add_corner_label(version, 1.0, 1.0, Vector2(-20.0, -32.0), true)

func _add_corner_label(text: String, anchor_x: float, anchor_y: float, offset: Vector2, right_aligned: bool = false) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", MeTheme.TEXT_BLUE)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.anchor_left = anchor_x
	label.anchor_right = anchor_x
	label.anchor_top = anchor_y
	label.anchor_bottom = anchor_y
	label.size = Vector2(160.0, 24.0)
	label.position = offset - (Vector2(160.0, 0.0) if right_aligned else Vector2.ZERO)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if right_aligned else HORIZONTAL_ALIGNMENT_LEFT
	add_child(label)

func _build_footer() -> void:
	_footer = Label.new()
	_footer.text = "↑↓ 选择 · Enter 确认"
	_footer.add_theme_font_size_override("font_size", 16)
	_footer.add_theme_color_override("font_color", MeTheme.TEXT_BLUE)
	_footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_footer.anchor_left = 0.5
	_footer.anchor_right = 0.5
	_footer.anchor_top = 1.0
	_footer.anchor_bottom = 1.0
	_footer.position = Vector2(-160.0, -40.0)
	_footer.size = Vector2(320.0, 24.0)
	add_child(_footer)

## Beat 0a: the simplified logo/title version pressed over the crouched
## close-up, plus a fake ~0.8s loading bar that covers the real body
## instantiation/animation merge/shader-compile cost that _load_silhouette()
## already paid by the time this is visible.
func _build_logo_plate() -> void:
	_logo_plate = Control.new()
	_logo_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_logo_plate.anchor_left = 0.5
	_logo_plate.anchor_right = 0.5
	_logo_plate.anchor_top = 0.5
	_logo_plate.anchor_bottom = 0.5
	_logo_plate.position = Vector2(-220.0, -60.0)
	_logo_plate.size = Vector2(440.0, 120.0)
	add_child(_logo_plate)

	var plate_label := Label.new()
	plate_label.text = str(ProjectSettings.get_setting("application/config/name", "Parkour Game"))
	plate_label.add_theme_font_size_override("font_size", 32)
	plate_label.add_theme_color_override("font_color", Color(0.08, 0.08, 0.08))
	plate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plate_label.size = Vector2(440.0, 48.0)
	_logo_plate.add_child(plate_label)

	var plate_accent := ColorRect.new()
	plate_accent.color = MeTheme.BRAND_RED
	plate_accent.position = Vector2(120.0, 52.0)
	plate_accent.size = Vector2(200.0, 4.0)
	_logo_plate.add_child(plate_accent)

	var bar_track := ColorRect.new()
	bar_track.color = Color(0.8, 0.8, 0.8, 0.6)
	bar_track.position = Vector2(120.0, 84.0)
	bar_track.size = Vector2(_loading_bar_full_width, 4.0)
	_logo_plate.add_child(bar_track)

	_loading_bar_fill = ColorRect.new()
	_loading_bar_fill.color = MeTheme.BRAND_RED
	_loading_bar_fill.position = Vector2(120.0, 84.0)
	_loading_bar_fill.size = Vector2(0.0, 4.0)
	_logo_plate.add_child(_loading_bar_fill)

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

# ---------------------------------------------------------------------------
# Entrance choreography (spec 入场编排, beats 0a-6). One pacing Tween drives
# the timeline via intervals + callbacks; each beat's actual property
# animation runs on its own short-lived Tween, tracked in _active_tweens so
# _skip_entrance() can kill every one of them at once.
# ---------------------------------------------------------------------------

func _track(tween: Tween) -> Tween:
	_active_tweens.append(tween)
	return tween

func _play_entrance() -> void:
	var pacing := _track(create_tween())
	pacing.tween_callback(_beat_logo)
	pacing.tween_interval(LOGO_TIME)
	pacing.tween_callback(_beat_rise_begin)
	pacing.tween_interval(RISE_TIME)
	pacing.tween_interval(BAR_DELAY)
	pacing.tween_callback(_beat_bar_sweep)
	pacing.tween_interval(BAR_TIME)
	pacing.tween_interval(TITLE_DELAY)
	pacing.tween_callback(_beat_title_drop)
	pacing.tween_interval(TITLE_DROP_TIME + GLITCH_STEP_TIME * 2.0)
	pacing.tween_interval(MENU_DELAY)
	pacing.tween_callback(_beat_menu_stagger)
	pacing.tween_interval(MeMenuList.ENTRANCE_STAGGER * 3.0 + MeMenuList.TWEEN_TIME)
	pacing.tween_callback(_beat_settle)

## 0a: fake loading bar + the dot grid starting to fade in "in the corner".
## The floor's own full fade-in (beat 1) keeps going through 0b below, so it
## lands exactly full alpha as the camera pull-back finishes.
func _beat_logo() -> void:
	var bar := _track(create_tween())
	bar.tween_property(_loading_bar_fill, "size:x", _loading_bar_full_width, LOGO_TIME) \
		.set_ease(Tween.EASE_OUT)

	var floor_fade := _track(create_tween())
	floor_fade.tween_property(_floor, "modulate:a", 1.0, LOGO_TIME + RISE_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

## 0b: logo plate dissolves + rises out of frame; the body rises from its
## crouch (Crouch_Idle -> Idle -> Walk) while the camera pulls back to the
## full-body behind view; the sweep bar peeks in slightly, "for the next
## beat's full sweep" (spec).
func _beat_rise_begin() -> void:
	if not _beat_rise_fired:
		_beat_rise_fired = true
		beat_rise.emit()

	var plate := _track(create_tween())
	plate.set_parallel(true)
	plate.tween_property(_logo_plate, "modulate:a", 0.0, LOGO_FADE_TIME) \
		.set_ease(Tween.EASE_IN)
	plate.tween_property(_logo_plate, "position:y", _logo_plate.position.y - 10.0, LOGO_FADE_TIME) \
		.set_ease(Tween.EASE_IN)

	if _silhouette != null:
		if _anim_player != null and _anim_player.has_animation(&"Idle"):
			_anim_player.play(&"Idle", 0.3)
		var rise := _track(create_tween())
		rise.set_parallel(true)
		rise.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		rise.tween_property(_silhouette_root, "position", Vector3.ZERO, RISE_TIME)
		rise.tween_property(_silhouette_camera, "position", _CAMERA_FAR_POS, RISE_TIME)
		rise.tween_property(_silhouette_camera, "rotation_degrees", _CAMERA_FAR_ROT_DEG, RISE_TIME)
		rise.chain().tween_callback(_start_walk_loop)

	var peek := _track(create_tween())
	peek.set_parallel(true)
	peek.tween_property(_bar_left, "scale:x", 0.12, RISE_TIME).set_delay(RISE_TIME - 0.2)
	peek.tween_property(_bar_right, "scale:x", 0.12, RISE_TIME).set_delay(RISE_TIME - 0.2)

## Beat 5 ("剪影人物同期淡入并持续行走循环", spec): no separate fade-in
## here, deliberately. The silhouette is already on screen from beat 0a --
## visible under the logo plate in its crouched pose -- so by the time beat
## 5 would fire there is no fade moment left to play; it has been visible
## the whole time. What beat 5 actually asks for, "keeps walking", is
## exactly what calling this at the end of the beat-0b rise chain (see
## _beat_rise_begin() above) already guarantees. Accepted reading, recorded
## here so the next person to read this doesn't go looking for a beat-5
## fade that was never meant to exist.
func _start_walk_loop() -> void:
	if _anim_player != null and _anim_player.has_animation(&"Walk"):
		_anim_player.play(&"Walk", 0.3)

## Beat 2: the red band finishes its sweep from wherever the beat-0b "peek"
## left it, meeting at center.
func _beat_bar_sweep() -> void:
	var sweep := _track(create_tween())
	sweep.set_parallel(true)
	sweep.tween_property(_bar_left, "scale:x", 1.0, BAR_TIME).set_ease(Tween.EASE_OUT)
	sweep.tween_property(_bar_right, "scale:x", 1.0, BAR_TIME).set_ease(Tween.EASE_OUT)

## Beat 3: title block drops in (offset above -> settle), then one cheap
## glitch jitter (±3px, one step out and back) at the moment it lands.
func _beat_title_drop() -> void:
	if not _beat_title_fired:
		_beat_title_fired = true
		beat_title.emit()

	var drop := _track(create_tween())
	_title_block.position = _title_final_position - Vector2(0.0, 12.0)
	drop.set_parallel(true)
	drop.tween_property(_title_block, "modulate:a", 1.0, TITLE_DROP_TIME)
	drop.tween_property(_title_block, "position", _title_final_position, TITLE_DROP_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	drop.chain()
	var jitter := Vector2(randf_range(-GLITCH_PX, GLITCH_PX), randf_range(-GLITCH_PX, GLITCH_PX))
	drop.tween_property(_title_block, "position", _title_final_position + jitter, GLITCH_STEP_TIME)
	drop.tween_property(_title_block, "position", _title_final_position, GLITCH_STEP_TIME)

## Beat 4: MeMenuList's own stagger-in.
func _beat_menu_stagger() -> void:
	_menu_list.play_entrance()

## Beat 6: idle drift, forever -- a Tween ping-ponging position.y between
## ±DRIFT_PX with sine easing reads as the spec's "sin摆动" without a second
## animation system. Glitch flicker is explicitly deferred to v2 (spec).
func _beat_settle() -> void:
	_entrance_active = false
	_start_idle_drift()

## Idempotent on purpose: _skip_entrance() can call this again after a
## previous drift tween was killed mid-oscillation, with position.y sitting
## somewhere off-center (not 0). Reading THAT as the new base would let
## repeated skip-entrance calls random-walk the whole menu's resting
## position a little further every time. Snapping back to the fixed
## _DRIFT_BASE_Y before starting a new drift keeps every call settle to the
## exact same place, however many times it runs.
func _start_idle_drift() -> void:
	position.y = _DRIFT_BASE_Y
	var drift := _track(create_tween())
	drift.set_loops()
	drift.tween_property(self, "position:y", _DRIFT_BASE_Y + DRIFT_PX, DRIFT_HALF_PERIOD) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	drift.tween_property(self, "position:y", _DRIFT_BASE_Y - DRIFT_PX, DRIFT_HALF_PERIOD) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

## Jumps straight to the fully-settled state: every tween killed, every
## animated property set to its final value. Wired to any input during the
## entrance window (see _unhandled_input) -- the standard "impatient click
## skips the intro" courtesy.
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
	_logo_plate.visible = false
	_bar_left.scale.x = 1.0
	_bar_right.scale.x = 1.0
	_title_block.modulate.a = 1.0
	_title_block.position = _title_final_position
	_menu_list.skip_entrance()

	if _silhouette != null:
		_silhouette_root.position = Vector3.ZERO
		_silhouette_camera.position = _CAMERA_FAR_POS
		_silhouette_camera.rotation_degrees = _CAMERA_FAR_ROT_DEG
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
