class_name TuningPanel
extends CanvasLayer

# Runtime tuning UI. Sliders are generated from MovementConfig's property list
# rather than hardcoded, so parameters added in later phases show up here for
# free.

const PRESET_DIR := "user://presets"
## Slider range is this multiple of the property's default value.
const RANGE_FACTOR := 3.0
## How far a slider's value must sit from its default before its reset button
## shows. Floats read back from a signal round-trip essentially never land on
## an exact bit-for-bit default, so a plain != would leave every reset button
## glued on; this is the same purpose test_a_row_can_read_and_write_its_own_value()
## serves with assert_almost_eq.
const RESET_EPSILON := 0.0001

## The Debug tab's checkboxes: one row of overlay label + the node name
## DebugHud gives that overlay (debug_hud.gd ~36-60), so the panel can find it
## in the "debug_overlay" group without knowing its class. Order here is
## display order. Only Capsule and Scripted path keep a key, so only those two
## labels carry one -- see the F9/F11 removal in the other three scripts.
const DEBUG_OVERLAYS: Array[Dictionary] = [
	{"label": "Capsule (F10)", "node_name": "CapsuleDebug"},
	{"label": "Scripted path (F12)", "node_name": "ScriptedPathDebug"},
	{"label": "Shimmy probes", "node_name": "ShimmyDebug"},
	{"label": "Ledge probe (F12)", "node_name": "GrabMarkers"},
	{"label": "Wall probe (F12)", "node_name": "WallClimbMarkers"},
	# persist = false: activating the tuner PAUSES the whole tree, so restoring
	# it at boot is a SOFTLOCK -- a T-pose with the screen frozen and unresponsive,
	# not even Esc getting out of it. With no key bound to it, this panel is its
	# only off-switch.
	{"label": "Clip offset tuner", "node_name": "ClipOffsetTuner", "persist": false},
]

## Whether an overlay's state may be persisted across sessions. Anything that
## does more than draw -- the tuner freezes the game -- must start OFF.
static func overlay_persists(node_name: String) -> bool:
	for entry in DEBUG_OVERLAYS:
		if entry["node_name"] == node_name:
			return bool(entry.get("persist", true))
	return true

@export var config: MovementConfig
## The CURRENT LEVEL's fog dials, injected by Arena next to `config`. Null in a
## test-built panel and in any level that declares no FogConfig, in which case
## the panel simply grows no Fog page. See collect_fog_tunables() for why this
## is a second field and not another group inside `config`.
@export var fog: FogConfig
## Tab title and row-key prefix for the fog sliders, playing the part a
## MovementConfig sub-resource's property name plays for every other page.
const FOG_GROUP := "fog"

var _panel: PanelContainer
var _preset_name: LineEdit
var _status: Label
## Every slider row, as {node, key} -- key is "group/property", lowercase --
## so the search box can hide the rest. Every group expanded at once is far
## too many sliders to scan by eye, which is what the search box is for.
var _search_rows: Array = []
var _tabs: TabContainer
## node_name -> CheckBox, filled by _add_debug_tab().
var _overlay_checkboxes: Dictionary = {}
## node_name -> bool, the toggle model. Loaded once in _ready() (headless and
## cheap, per DebugToggles) and kept in memory as the write-through cache for
## every checkbox change, so a save never has to re-read the file it is about
## to overwrite.
var _toggle_states: Dictionary = {}

func _ready() -> void:
	# ALWAYS, because the clip offset tuner pauses the tree and this panel is
	# its only off-switch -- a paused panel cannot un-pause anything, which is
	# the softlock the owner reported. Also what lets F1 open at all mid-pause.
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	DirAccess.make_dir_recursive_absolute(PRESET_DIR)
	_toggle_states = DebugToggles.load_states()
	# Godot readies children before parents, so `config` is still null here.
	# Arena injects it during its own _ready(); deferring the build to the end
	# of the frame guarantees the injection has already happened.
	call_deferred("_build_ui")

func _process(_delta: float) -> void:
	# Two-way sync, and only worth the per-frame walk while the panel is
	# actually being looked at: a keyboard toggle (F10/F12) must not leave a
	# checkbox lying about what is on screen.
	if not visible:
		return
	for node_name in _overlay_checkboxes:
		var overlay := _find_overlay(node_name)
		if overlay == null or not overlay.has_method("overlay_shown"):
			continue
		var checkbox: CheckBox = _overlay_checkboxes[node_name]
		# _no_signal: this is a read-back, not a user action. A plain
		# `.button_pressed =` would fire `toggled` straight back into
		# _on_overlay_toggled(), which would re-drive the very overlay this
		# frame is only trying to reflect, and re-save the toggle file for a
		# state that did not actually change.
		checkbox.set_pressed_no_signal(overlay.overlay_shown())

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F1:
			visible = not visible
			# Releasing the mouse is required to actually drag the sliders.
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if visible else Input.MOUSE_MODE_CAPTURED

## Walks the config's resource tree and returns one row per slider-drivable
## float, in declaration order. Static and UI-free on purpose: this is the
## whole of the panel's model, so it can be tested headlessly (the previous
## version lived inside _build_ui() and could not be).
##
## Recursion depth is exactly one level (aggregate root -> sub-resource) by
## construction, but the walk is written generically so a future nested
## resource does not silently vanish from the panel.
static func collect_tunables(config: MovementConfig) -> Array[Dictionary]:
	var defaults := MovementConfig.new()
	var rows: Array[Dictionary] = []
	for property in config.get_property_list():
		if not (property.usage & PROPERTY_USAGE_EDITOR):
			continue
		if property.type != TYPE_OBJECT:
			continue
		var owner: Resource = config.get(property.name)
		var defaults_owner: Resource = defaults.get(property.name)
		if owner == null or defaults_owner == null:
			continue
		_collect_from(owner, defaults_owner, String(property.name), rows)
	return rows

## The same rows for the LEVEL's fog, in the same shape, reusing the same walk.
##
## SEPARATE FROM collect_tunables() ON PURPOSE, and the reason is _on_save():
## a preset is built by walking collect_tunables() and writing every value it
## yields. Fog belongs to the level, not to a feel preset -- folding it into
## that walk would mean a preset saved on a fogged rooftop silently re-fogs
## whatever level it is next loaded into, which is exactly the coupling
## FogConfig exists to prevent. Keeping it out of that function is what makes
## that impossible rather than merely unlikely.
##
## Returns nothing for a level with no FogConfig, so the page disappears
## rather than showing dead sliders.
static func collect_fog_tunables(fog_config: FogConfig) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if fog_config == null:
		return rows
	_collect_from(fog_config, FogConfig.new(), FOG_GROUP, rows)
	return rows

static func _collect_from(owner: Resource, defaults_owner: Resource, prefix: String, \
		rows: Array[Dictionary]) -> void:
	for property in owner.get_property_list():
		if not (property.usage & PROPERTY_USAGE_EDITOR):
			continue
		if property.type != TYPE_FLOAT:
			continue
		rows.append({
			"path": "%s.%s" % [prefix, property.name],
			"label": String(property.name),
			"group": prefix,
			"owner": owner,
			"property": String(property.name),
			"default": float(defaults_owner.get(property.name)),
		})

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_panel.position = Vector2(-430.0, 8.0)
	_panel.custom_minimum_size = Vector2(420.0, 0.0)
	add_child(_panel)

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel.add_child(root)

	# GLOBAL AREA, above the tabs: a preset save/load is one click no matter
	# which page happens to be open.
	_add_preset_row(root)

	# THE SEARCH BOX, above the tabs: type to filter every page at once.
	var search := LineEdit.new()
	search.placeholder_text = "search settings…"
	search.clear_button_enabled = true
	search.text_changed.connect(_apply_search)
	root.add_child(search)

	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(420.0, 620.0)
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(tabs)
	_tabs = tabs

	# FIRST TAB, always: the Debug page is not a tunable group, so it does not
	# come from collect_tunables() -- it is added once, ahead of the loop
	# below, which is what makes it the first child and so the first tab.
	_add_debug_tab(tabs)

	# One tab per distinct group, auto-generated in encounter order -- ZERO
	# CURATION, so a config group added to MovementConfig later shows up here
	# for free. Same standing principle collect_tunables() itself follows;
	# rows already arrive grouped by sub-resource because that walk finishes
	# one sub-resource fully before moving to the next, so a group change in
	# the row stream is exactly a page change here.
	var current_group := ""
	var group_column: VBoxContainer = null
	# The level's fog dials are appended AFTER every player-side group, so the
	# Fog page lands last and the pages before it keep the order they had.
	for row in collect_tunables(config) + collect_fog_tunables(fog):
		if row["group"] != current_group:
			current_group = row["group"]
			group_column = _add_group_tab(tabs, current_group)
		_add_slider(group_column, row)
		# _add_slider appended its HBox last; record it for the search box.
		_search_rows.append({"node": group_column.get_child(group_column.get_child_count() - 1),
			"key": ("%s/%s" % [row["group"], row["label"]]).to_lower()})

	# The overlays DebugHud spawns are themselves add_child.call_deferred()'d
	# (debug_hud.gd ~36-60), so at THIS point -- already one frame deferred
	# from _ready() -- they may or may not exist yet, depending on whichever
	# of the two _ready()s the scene tree happens to run first. One more
	# deferred hop makes the ordering a non-issue instead of a coin flip.
	call_deferred("_apply_persisted_toggles")

## Hides every slider row the query does not match (case-insensitive
## substring against "group/property"), and flags matching tabs with a dot
## so the hits are findable across pages. Empty text restores everything.
func _apply_search(query: String) -> void:
	var q := query.strip_edges().to_lower()
	var hit_tabs := {}
	for entry in _search_rows:
		var visible: bool = q.is_empty() or entry["key"].contains(q)
		(entry["node"] as Control).visible = visible
		if visible and not q.is_empty():
			var page := (entry["node"] as Control).get_parent()
			while page != null and page.get_parent() != _tabs:
				page = page.get_parent()
			if page != null:
				hit_tabs[_tabs.get_tab_idx_from_control(page)] = true
	for i in _tabs.get_tab_count():
		var title := _tabs.get_tab_title(i).trim_suffix(" •")
		_tabs.set_tab_title(i, title + " •" if (not q.is_empty() and hit_tabs.has(i)) else title)

## Builds the Debug page: one CheckBox per overlay in DEBUG_OVERLAYS, wired
## both ways -- pressing one drives the matching overlay and persists every
## overlay's state; _process() reads the overlay back into the checkbox so a
## keyboard toggle never desyncs the UI.
func _add_debug_tab(tabs: TabContainer) -> void:
	var column := VBoxContainer.new()
	column.name = "Debug"
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_child(column)

	for entry in DEBUG_OVERLAYS:
		var node_name: String = entry["node_name"]
		var checkbox := CheckBox.new()
		checkbox.text = entry["label"]
		checkbox.button_pressed = bool(_toggle_states.get(node_name, false))
		checkbox.toggled.connect(func(on: bool) -> void:
			_on_overlay_toggled(node_name, on))
		column.add_child(checkbox)
		_overlay_checkboxes[node_name] = checkbox

## One tab page per config group: a ScrollContainer (the same 420x620 real
## estate the single-column panel used to give the whole thing) wrapping a
## VBox of that group's slider rows. `group_name` becomes the tab's title,
## which is the row's own dotted-path prefix (e.g. "pawn", "wall_run") --
## exactly what the old inline "— pawn —" heading said, so nothing is lost by
## dropping that heading now that the tab itself carries the name.
func _add_group_tab(tabs: TabContainer, group_name: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = group_name
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(scroll)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	return column

## Applies whatever DebugToggles.load_states() found in _ready() to the actual
## overlay nodes and their checkboxes. Split out from _ready() itself for the
## deferred timing above, and guarded on is_inside_tree(): the model tests
## build a TuningPanel directly without adding it to the SceneTree (see
## test_tuning_panel_model.gd's own comment on why), so get_tree() below would
## be null there. Nothing here runs in that case, which is the point -- a
## headless test that never builds the panel UI must not go looking for
## overlays that were never spawned for it.
func _apply_persisted_toggles() -> void:
	if not is_inside_tree():
		return
	for node_name in _overlay_checkboxes:
		if not _toggle_states.has(node_name):
			continue
		# A stale cfg from before an overlay was marked transient must not
		# re-freeze the game either -- filter on APPLY, not only on save.
		if not overlay_persists(node_name):
			continue
		var on: bool = _toggle_states[node_name]
		var overlay := _find_overlay(node_name)
		if overlay != null:
			_set_overlay_active(overlay, on)
		var checkbox: CheckBox = _overlay_checkboxes[node_name]
		checkbox.set_pressed_no_signal(on)

func _on_overlay_toggled(node_name: String, on: bool) -> void:
	var overlay := _find_overlay(node_name)
	if overlay != null:
		_set_overlay_active(overlay, on)
	if not overlay_persists(node_name):
		return
	_toggle_states[node_name] = on
	# Written immediately, not batched: the whole point of persisting this is
	# surviving a crash or a kill from the editor's stop button, same as
	# CameraRig.save_preferences() next to this file's own precedent.
	DebugToggles.save_states(_toggle_states)

## The overlay by the node name DebugHud gave it, or null before DebugHud has
## spawned it (or if this panel is not in the tree at all -- see
## _apply_persisted_toggles()'s own guard).
func _find_overlay(node_name: String) -> Node:
	for node in get_tree().get_nodes_in_group("debug_overlay"):
		if node.name == node_name:
			return node
	return null

## Duck-types the setter: ClipOffsetTuner uses set_active() (its freeze/unfreeze
## side effects make "toggle" the wrong shape for a plain visibility flag);
## the other three share show_overlay(). Both remain to widen a match rather
## than an if-chain, in case a future overlay needs a third shape.
func _set_overlay_active(overlay: Node, on: bool) -> void:
	if overlay.has_method("set_active"):
		overlay.set_active(on)
	elif overlay.has_method("show_overlay"):
		overlay.show_overlay(on)

## Whether a slider's current value has drifted from its seeded default by
## more than a float can be expected to land on exactly -- see RESET_EPSILON.
## Pure and static so it is testable without building any UI, same as
## collect_tunables() above it.
static func differs_from_default(value: float, default_value: float) -> bool:
	return absf(value - default_value) > RESET_EPSILON

## The one seam all three sites that can move a slider's value -- construction
## (seeding), a drag (the value_changed lambda), and a preset Load
## (_refresh_sliders()) -- go through to keep a row's reset button in sync.
## Extracted after a review caught _refresh_sliders() skipping this: it seeded
## the slider and the value label on Load but never recomputed the button, so
## a row could come back from Load either stuck showing ↺ after landing back
## on its default, or showing none after landing away from it. A fourth call
## site cannot forget this again without also duplicating the one line here.
static func _sync_reset_button(reset_button: Button, value: float, default_value: float) -> void:
	reset_button.visible = differs_from_default(value, default_value)

func _add_preset_row(column: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	column.add_child(row)

	_preset_name = LineEdit.new()
	_preset_name.text = "feel_a"
	_preset_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_preset_name)

	var save_button := Button.new()
	save_button.text = "Save"
	save_button.pressed.connect(_on_save)
	row.add_child(save_button)

	var load_button := Button.new()
	load_button.text = "Load"
	load_button.pressed.connect(_on_load)
	row.add_child(load_button)

	_status = Label.new()
	column.add_child(_status)

func _add_slider(column: VBoxContainer, row: Dictionary) -> void:
	var hrow := HBoxContainer.new()
	column.add_child(hrow)

	var name_label := Label.new()
	name_label.text = row["label"]
	name_label.custom_minimum_size = Vector2(180.0, 0.0)
	hrow.add_child(name_label)

	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(64.0, 0.0)
	hrow.add_child(value_label)

	var slider := HSlider.new()
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.min_value = 0.0
	var default_value: float = row["default"]
	slider.max_value = maxf(absf(default_value) * RANGE_FACTOR, 0.01)
	# Continuous, not stepped. DO NOT give this a nonzero step: it would snap
	# the seeded value to the nearest increment (e.g. ground_speed's default
	# 7.2 -> 7.21), and the plain `slider.value = ...` assignment below would
	# fire value_changed on that snapped value, writing it straight back into
	# the shared config the instant the panel builds its UI — perturbing every
	# feel parameter before a human ever touches a slider. For feel tuning,
	# continuous is what you want anyway: the label already formats to four
	# decimals, and nobody is hunting for round numbers.
	slider.step = 0.0
	# set_value_no_signal, not `slider.value = ...`: even with step = 0, a
	# plain assignment would fire value_changed before the callback below is
	# connected, which is harmless today but fragile. Seeding without a
	# signal keeps "construction never writes into config" true regardless.
	var owner: Resource = row["owner"]
	var property: String = row["property"]
	slider.set_value_no_signal(owner.get(property))
	hrow.add_child(slider)

	# Per-row reset: visible only while the value has actually
	# drifted from its default, so a page of untouched rows shows no clutter.
	# Goes through the SAME signal path a drag would (a plain `.value =`, not
	# the no-signal setter above) so the config write and the label update
	# happen exactly as if the human had dragged it there themselves.
	var reset_button := Button.new()
	reset_button.text = "↺"
	reset_button.tooltip_text = "Reset to default (%.4f)" % default_value
	reset_button.custom_minimum_size = Vector2(28.0, 0.0)
	_sync_reset_button(reset_button, slider.value, default_value)
	reset_button.pressed.connect(func() -> void:
		slider.value = default_value)
	hrow.add_child(reset_button)

	value_label.text = "%.4f" % slider.value
	slider.value_changed.connect(func(v: float) -> void:
		owner.set(property, v)
		value_label.text = "%.4f" % v
		_sync_reset_button(reset_button, v, default_value))

	# Reloading a preset must move the sliders too, not just the values --
	# and, past _refresh_sliders(), the reset button too. Both meta keys are
	# read back together there.
	slider.set_meta("row", row)
	slider.set_meta("reset_button", reset_button)

func _sliders() -> Array[HSlider]:
	var out: Array[HSlider] = []
	for node in _panel.find_children("*", "HSlider", true, false):
		out.append(node as HSlider)
	return out

func _refresh_sliders() -> void:
	for slider in _sliders():
		# set_value_no_signal, not `slider.value = ...`: a plain assignment
		# fires value_changed, which would run straight back through the
		# connected callback and re-set(...) the value we just loaded into
		# config. Harmless in itself now that sliders are continuous
		# (step = 0, so nothing gets snapped in the process), but it would
		# still be a pointless round-trip through the signal for every
		# slider on every load, so keep using the no-signal setter and
		# refresh the label manually instead.
		var row: Dictionary = slider.get_meta("row")
		var owner: Resource = row["owner"]
		var property: String = row["property"]
		slider.set_value_no_signal(owner.get(property))
		var value_label := slider.get_parent().get_child(1) as Label
		if value_label != null:
			value_label.text = "%.4f" % slider.value
		# The reset button is the THIRD site that can move a slider's value
		# (construction and a drag are the other two, both above) -- a Load
		# that lands a row back on its default, or away from it, must move
		# the button the same way a drag would, or it goes stale until the
		# next drag happens to touch that row.
		var reset_button := slider.get_meta("reset_button") as Button
		if reset_button != null:
			_sync_reset_button(reset_button, slider.value, float(row["default"]))

func _on_save() -> void:
	var path := "%s/%s.tres" % [PRESET_DIR, _preset_name.text]
	# Explicit path->value mapping rather than ResourceSaver.save(config, ...):
	# ResourceSaver omits any property whose value equals its DECLARED
	# default. CrouchConfig sets speed_modifier = 0.4 in _init(), but the
	# property is declared on the MoveConfig base with default 1.0 -- so a
	# preset in which the user tuned crouch speed to exactly 1.0 would never
	# be written to the .tres, and on reload _init() would silently restore
	# 0.4. Writing every tunable's current value explicitly sidesteps
	# default-skipping entirely.
	var values := {}
	for row in collect_tunables(config):
		values[row["path"]] = row["owner"].get(row["property"])
	var preset := TuningPreset.new()
	preset.values = values
	var error := ResourceSaver.save(preset, path)
	_status.text = "saved %s" % path if error == OK else "save failed (%d)" % error

func _on_load() -> void:
	var path := "%s/%s.tres" % [PRESET_DIR, _preset_name.text]
	if not ResourceLoader.exists(path):
		_status.text = "no preset at %s" % path
		return
	# CACHE_MODE_IGNORE forces a fresh read: without it, repeated loads of the
	# same path return the cached instance and the panel appears to do nothing.
	#
	# Loaded as a plain Resource, not TuningPreset: a statically-typed
	# `var loaded: TuningPreset = ResourceLoader.load(...)` throws a SCRIPT
	# ERROR on assignment the moment the file holds any OTHER resource type --
	# in particular a preset saved by the pre-Task-3 panel, which serialized
	# a whole MovementConfig instead of a TuningPreset. That assignment fails
	# before the `loaded == null` check below ever runs, so _on_load() would
	# abort mid-function with no status update -- silent to the user, unlike
	# every other failure path in this function. Checking `is TuningPreset`
	# explicitly turns that crash into the same graceful "load failed" shape
	# the rest of this function already uses.
	var loaded: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if loaded == null:
		_status.text = "load failed"
		return
	if not (loaded is TuningPreset):
		_status.text = "%s is not a tuning preset (old-format save?)" % path
		return
	var preset: TuningPreset = loaded
	# A path in the file that no longer exists in the config is skipped
	# silently (configs change across tasks); a path in the config absent
	# from the file keeps its current value.
	for row in collect_tunables(config):
		if preset.values.has(row["path"]):
			row["owner"].set(row["property"], preset.values[row["path"]])
	_refresh_sliders()
	_status.text = "loaded %s" % path
