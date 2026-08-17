class_name TuningPanel
extends CanvasLayer

# Runtime tuning UI. Sliders are generated from MovementConfig's property list
# rather than hardcoded, so parameters added in later phases show up here for
# free.

const PRESET_DIR := "user://presets"
## Slider range is this multiple of the property's default value.
const RANGE_FACTOR := 3.0

@export var config: MovementConfig

var _panel: PanelContainer
var _preset_name: LineEdit
var _status: Label

func _ready() -> void:
	visible = false
	DirAccess.make_dir_recursive_absolute(PRESET_DIR)
	# Godot readies children before parents, so `config` is still null here.
	# Arena injects it during its own _ready(); deferring the build to the end
	# of the frame guarantees the injection has already happened.
	call_deferred("_build_ui")

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

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(420.0, 620.0)
	_panel.add_child(scroll)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)

	_add_preset_row(column)

	# Headings are created lazily, right before the first row that actually
	# belongs to them, whenever the row's group differs from the previous
	# row's -- rows already arrive grouped by sub-resource because
	# collect_tunables() walks one sub-resource fully before moving to the
	# next.
	var current_group := ""
	for row in collect_tunables(config):
		if row["group"] != current_group:
			current_group = row["group"]
			var heading := Label.new()
			heading.text = "— %s —" % current_group
			column.add_child(heading)
		_add_slider(column, row)

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
	# Continuous, not stepped. A nonzero step here used to snap the seeded
	# value to the nearest increment (e.g. ground_speed's default 7.2 -> 7.21)
	# and, worse, do it via a plain `slider.value = ...` assignment below,
	# whose value_changed signal wrote the snapped value straight back into
	# the shared config the instant the panel built its UI — perturbing every
	# feel parameter before a human ever touched a slider. For feel tuning,
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

	value_label.text = "%.4f" % slider.value
	slider.value_changed.connect(func(v: float) -> void:
		owner.set(property, v)
		value_label.text = "%.4f" % v)

	# Reloading a preset must move the sliders too, not just the values.
	slider.set_meta("row", row)

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
	var loaded: TuningPreset = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if loaded == null:
		_status.text = "load failed"
		return
	# A path in the file that no longer exists in the config is skipped
	# silently (configs change across tasks); a path in the config absent
	# from the file keeps its current value.
	for row in collect_tunables(config):
		if loaded.values.has(row["path"]):
			row["owner"].set(row["property"], loaded.values[row["path"]])
	_refresh_sliders()
	_status.text = "loaded %s" % path
