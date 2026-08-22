class_name ClipOffsetTuner
extends CanvasLayer

# Nudges the visible body until it lines up with what it is standing on, and
# prints a line to paste into a BodyProfile.
#
# THE FREEZE IS THE POINT. A SpeedVault lasts about half a second, which is not
# long enough to nudge anything -- by the time you have pressed a key twice the
# clip is over and the body is walking. So F9 pauses the whole tree on the frame
# you were looking at: the AnimationPlayer holds its pose, the move stops, and
# the offset can be dragged around a body standing still in mid-vault.
#
# THREE THINGS THE FIRST VERSION GOT WRONG, all reported from one session:
#
#   * IT TOOK TWO PRESSES OF F9. The layer started with visible = false, and a
#     hidden CanvasLayer is not a reliable place to receive input from. Nothing
#     is hidden now -- the label simply carries no text while inactive -- and
#     the toggle is read in _input(), which runs before anything else can eat
#     it.
#   * THE CAMERA STAYED PUT. The head-follow runs on the physics tick, which is
#     paused along with everything else, so moving the body did not move the
#     eye and tuning in first person showed nothing. Player.refresh_head_follow()
#     steps it by hand; see its own comment.
#   * IT WOULD NOT REPEAT. Nudging was one key press per centimetre, which the
#     owner counted in the dozens. Held keys are POLLED in _process now, at a
#     rate per second rather than a step per press.
#
# ⚠️ A constant offset can only line up ONE instant of a moving clip. Perfect
# for a hang, a wall run or a crouch; a compromise for a vault, where the body
# travels past the thing its hands are meant to be on. See
# BodyProfile.clip_offsets.

## Spelled out rather than written inline. An escaped newline inside a string
## literal has been mangled four times in this repository by the tooling that
## edits these files -- twice into a line that still parsed and was simply
## wrong. A named constant cannot be mangled into whitespace.
const NEWLINE := "\n"

@export var player: Player

## Metres per second and degrees per second while a key is held.
@export var position_rate: float = 0.20
@export var rotation_rate: float = 40.0
## Multiplier while Shift is held, for finding the rough place first, and the
## divisor while Ctrl is held, for the last millimetre.
@export var coarse_multiplier: float = 5.0
@export var fine_divisor: float = 5.0

## Position keys, as keycode -> unit movement in the body's own frame.
const POSITION_KEYS := {
	KEY_I: Vector3(0.0, 0.0, -1.0),
	KEY_K: Vector3(0.0, 0.0, 1.0),
	KEY_J: Vector3(-1.0, 0.0, 0.0),
	KEY_L: Vector3(1.0, 0.0, 0.0),
	KEY_U: Vector3(0.0, -1.0, 0.0),
	KEY_O: Vector3(0.0, 1.0, 0.0),
}
## Rotation keys, as keycode -> unit rotation in degrees (x pitch, y yaw, z roll).
const ROTATION_KEYS := {
	KEY_BRACKETLEFT: Vector3(0.0, -1.0, 0.0),
	KEY_BRACKETRIGHT: Vector3(0.0, 1.0, 0.0),
	KEY_SEMICOLON: Vector3(-1.0, 0.0, 0.0),
	KEY_APOSTROPHE: Vector3(1.0, 0.0, 0.0),
	KEY_COMMA: Vector3(0.0, 0.0, -1.0),
	KEY_PERIOD: Vector3(0.0, 0.0, 1.0),
}

var _active := false
var _label: Label
## The clip being tuned, captured on freeze -- reading it live would follow the
## body into whatever it does next.
var _clip: StringName = &""
var _position: Vector3 = Vector3.ZERO
var _rotation: Vector3 = Vector3.ZERO
var _note: String = ""

func _ready() -> void:
	# ALWAYS, or the tuner pauses with everything else and the freeze is a hang.
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 2
	_label = Label.new()
	_label.position = Vector2(16.0, 16.0)
	_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6))
	_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	_label.add_theme_constant_override("outline_size", 5)
	add_child(_label)
	_refresh()

## _input, not _unhandled_input: this runs before the GUI and before anything
## the game does with the key, so F9 cannot be swallowed on the way past. Only
## the discrete actions live here -- the nudges are held keys, and those are
## polled in _process().
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.physical_keycode:
		KEY_F9:
			_toggle()
			get_viewport().set_input_as_handled()
		KEY_ENTER, KEY_KP_ENTER:
			if _active:
				_print_table()
				get_viewport().set_input_as_handled()
		KEY_BACKSPACE:
			if _active:
				_position = Vector3.ZERO
				_rotation = Vector3.ZERO
				_apply()
				get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not _active:
		return
	var speed := 1.0
	if Input.is_key_pressed(KEY_SHIFT):
		speed *= coarse_multiplier
	if Input.is_key_pressed(KEY_CTRL):
		speed /= maxf(fine_divisor, 0.001)
	var moved := false
	for key in POSITION_KEYS:
		if Input.is_physical_key_pressed(key):
			_position += POSITION_KEYS[key] * position_rate * speed * delta
			moved = true
	for key in ROTATION_KEYS:
		if Input.is_physical_key_pressed(key):
			_rotation += ROTATION_KEYS[key] * rotation_rate * speed * delta
			moved = true
	if moved:
		_apply()

## F9 freezes on the current frame and starts tuning whatever clip is playing;
## F9 again writes the value into the live table and lets the game run on, so
## the next vault is played with what was just dialled in.
func _toggle() -> void:
	if player == null or player.body == null:
		_note = "no body attached -- nothing to tune"
		_refresh()
		return
	_active = not _active
	get_tree().paused = _active
	if _active:
		_clip = player._current_clip()
		var existing: Array = player.clip_offset_for(_clip)
		_position = existing[0] if not existing.is_empty() else Vector3.ZERO
		_rotation = existing[1] if not existing.is_empty() else Vector3.ZERO
		_note = ""
		_apply()
	else:
		_commit()
		_refresh()

## Into the LIVE table, so the change survives the unfreeze and can be judged in
## motion. Not into the .tres -- that is what the printed line is for. Writing a
## resource from a debug tool is how a tuning session quietly becomes a commit.
func _commit() -> void:
	if _clip == &"" or _clip == Move.KEEP or player == null:
		return
	if _position.is_zero_approx() and _rotation.is_zero_approx():
		player.body_clip_offsets.erase(_clip)
	else:
		player.body_clip_offsets[_clip] = [_position, _rotation]

func _apply() -> void:
	if player != null:
		player.set_clip_offset_immediately(_position, _rotation)
	_refresh()

## EVERY clip tuned so far, not just the one on screen.
##
## ✅ The owner: "I tuned a pile of them and only found out on Enter that it
## printed the current one." The others were never lost -- _commit() writes each
## into the live table as you leave it -- but recovering them meant walking back
## through the clips one at a time to press Enter again, which is not recovery,
## it is doing the work twice.
##
## Printed as the whole property line, so it replaces the one in the .tres
## rather than being merged into it by hand.
func _print_table() -> void:
	var table := _live_table()
	var names: Array = table.keys()
	names.sort()
	var lines := PackedStringArray()
	lines.append("clip_offsets = {")
	for i in names.size():
		var entry: Array = table[names[i]]
		# No comma after the last one: Godot's own .tres writer omits it, and a
		# trailing comma is not something the parser is guaranteed to forgive.
		var tail := "," if i < names.size() - 1 else ""
		lines.append('"%s": [Vector3(%.3f, %.3f, %.3f), Vector3(%.1f, %.1f, %.1f)]%s'
				% [names[i], entry[0].x, entry[0].y, entry[0].z,
				entry[1].x, entry[1].y, entry[1].z, tail])
	lines.append("}")
	# One print, not one per line: the point is a block you can select in the
	# console and paste in one go.
	print(NEWLINE.join(lines))
	_note = "printed %d clip%s to the console" % [names.size(), "" if names.size() == 1 else "s"]
	_refresh()

## The committed table plus whatever is being dragged around right now, keyed by
## plain String. StringName and String are interchangeable as dictionary keys
## (checked directly), so it does not matter which of the two Godot writes back
## into the .tres.
func _live_table() -> Dictionary:
	var table := {}
	if player != null:
		for key in player.body_clip_offsets:
			var entry: Array = player.clip_offset_for(key)
			if not entry.is_empty():
				table[String(key)] = entry
	# The clip on screen has not been committed yet -- that happens on unfreeze.
	if _active and _clip != &"" and _clip != Move.KEEP:
		if _position.is_zero_approx() and _rotation.is_zero_approx():
			table.erase(String(_clip))
		else:
			table[String(_clip)] = [_position, _rotation]
	return table

## The clips carrying an offset right now, for the readout. Seeing the list is
## what tells you the earlier ones are still there.
func _tuned_names() -> Array:
	var names: Array = _live_table().keys()
	names.sort()
	return names

func _refresh() -> void:
	if _label == null:
		return
	if not _active:
		# EMPTIED rather than hidden. A hidden CanvasLayer is not somewhere to
		# rely on receiving input from, and that cost two presses of F9.
		_label.text = _note
		_note = ""
		return
	var lines: Array[String] = [
		"CLIP OFFSET TUNER  --  frozen on '%s'" % _clip,
		"",
		"  position  %+.3f %+.3f %+.3f   (m, body frame, -Z is forward)"
				% [_position.x, _position.y, _position.z],
		"  rotation  %+.1f %+.1f %+.1f   (deg, pivot at the model's feet)"
				% [_rotation.x, _rotation.y, _rotation.z],
		"",
		"  HOLD  I/K forward-back   J/L left-right   U/O down-up",
		"  HOLD  [ ] yaw    ; ' pitch    , . roll",
		"        Shift x%d faster    Ctrl /%d finer"
				% [int(coarse_multiplier), int(fine_divisor)],
		"  Enter  print ALL %d tuned clip(s), as a line to paste into the profile"
				% _live_table().size(),
		"  Back   reset to zero",
		"  F9     unfreeze, keeping this offset live for the next play",
		"",
		"  tuned so far: %s" % (", ".join(_tuned_names()) if not _tuned_names().is_empty() else "nothing yet"),
	]
	if _note != "":
		lines.append("")
		lines.append("  " + _note)
		_note = ""
	_label.text = "\n".join(lines)
