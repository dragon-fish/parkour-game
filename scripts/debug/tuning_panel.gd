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

	var defaults := MovementConfig.new()
	# Headings are created lazily, right before the first float property that
	# actually belongs to them, rather than the moment a GROUP marker is seen.
	# get_property_list() includes Godot's own built-in "Resource" group (with
	# no float members of its own) ahead of the script's @export_groups; a
	# heading created eagerly for every GROUP marker would print a spurious
	# "— Resource —" line above the real ones. This approach needs no special
	# case for that name and stays correct if the engine adds other built-in
	# groups later.
	var pending_heading := ""
	for property in config.get_property_list():
		if property.usage & PROPERTY_USAGE_GROUP:
			pending_heading = property.name
			continue
		if not (property.usage & PROPERTY_USAGE_EDITOR):
			continue
		if property.type != TYPE_FLOAT:
			continue
		if pending_heading != "":
			var heading := Label.new()
			heading.text = "— %s —" % pending_heading
			column.add_child(heading)
			pending_heading = ""
		_add_slider(column, property.name, defaults.get(property.name))

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

func _add_slider(column: VBoxContainer, property_name: String, default_value: float) -> void:
	var row := HBoxContainer.new()
	column.add_child(row)

	var name_label := Label.new()
	name_label.text = property_name
	name_label.custom_minimum_size = Vector2(180.0, 0.0)
	row.add_child(name_label)

	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(64.0, 0.0)
	row.add_child(value_label)

	var slider := HSlider.new()
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.min_value = 0.0
	slider.max_value = maxf(absf(default_value) * RANGE_FACTOR, 0.01)
	# Continuous, not stepped. A nonzero step here used to snap the seeded
	# value to the nearest increment (e.g. walk_speed's default 5.0 -> 5.01)
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
	slider.set_value_no_signal(config.get(property_name))
	row.add_child(slider)

	value_label.text = "%.4f" % slider.value
	slider.value_changed.connect(func(v: float) -> void:
		config.set(property_name, v)
		value_label.text = "%.4f" % v)

	# Reloading a preset must move the sliders too, not just the values.
	slider.set_meta("property_name", property_name)

func _sliders() -> Array[HSlider]:
	var out: Array[HSlider] = []
	for node in _panel.find_children("*", "HSlider", true, false):
		out.append(node as HSlider)
	return out

func _on_save() -> void:
	var path := "%s/%s.tres" % [PRESET_DIR, _preset_name.text]
	var error := ResourceSaver.save(config, path)
	_status.text = "saved %s" % path if error == OK else "save failed (%d)" % error

func _on_load() -> void:
	var path := "%s/%s.tres" % [PRESET_DIR, _preset_name.text]
	if not ResourceLoader.exists(path):
		_status.text = "no preset at %s" % path
		return
	# CACHE_MODE_IGNORE forces a fresh read: without it, repeated loads of the
	# same path return the cached instance and the panel appears to do nothing.
	var loaded: MovementConfig = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if loaded == null:
		_status.text = "load failed"
		return
	for property in loaded.get_property_list():
		if property.usage & PROPERTY_USAGE_EDITOR and property.type == TYPE_FLOAT:
			config.set(property.name, loaded.get(property.name))
	for slider in _sliders():
		# set_value_no_signal, not `slider.value = ...`: a plain assignment
		# fires value_changed, which would run straight back through the
		# connected callback and re-set(...) the value we just loaded into
		# config. Harmless in itself now that sliders are continuous
		# (step = 0, so nothing gets snapped in the process), but it would
		# still be a pointless round-trip through the signal for every
		# slider on every load, so keep using the no-signal setter and
		# refresh the label manually instead.
		var property_name: String = slider.get_meta("property_name")
		slider.set_value_no_signal(config.get(property_name))
		var value_label := slider.get_parent().get_child(1) as Label
		if value_label != null:
			value_label.text = "%.4f" % slider.value
	_status.text = "loaded %s" % path
