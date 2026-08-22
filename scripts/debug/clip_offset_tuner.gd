class_name ClipOffsetTuner
extends CanvasLayer

# Nudges the visible body until it lines up with what it is standing on, and
# prints a line to paste into a BodyProfile.
#
# THE FREEZE IS THE POINT. A SpeedVault lasts about half a second, which is not
# long enough to nudge anything -- by the time you have pressed a key twice the
# clip is over and the body is walking. So F9 pauses the whole tree on the frame
# you were looking at: the AnimationPlayer holds its pose, the move stops, and
# the offset can be dragged around a body that is standing still in mid-vault.
#
# Player._drive_clip_offset() is paused along with everything else, which is why
# this calls set_clip_offset_immediately() instead of writing the table and
# waiting: while paused nothing would ever apply it.
#
# ⚠️ A constant offset can only line up ONE instant of a moving clip. Perfect
# for a hang, a wall run or a crouch; a compromise for a vault, where the body
# travels past the thing its hands are meant to be on. See
# BodyProfile.clip_offsets.

@export var player: Player

## Metres per key press, and degrees per key press.
@export var position_step: float = 0.01
@export var rotation_step: float = 1.0
## Multiplier while Shift is held, for finding the rough place first.
@export var coarse_multiplier: float = 10.0

var _active := false
var _label: Label
## The clip being tuned, captured on freeze -- reading it live would follow the
## body into whatever it does next.
var _clip: StringName = &""
var _position: Vector3 = Vector3.ZERO
var _rotation: Vector3 = Vector3.ZERO

func _ready() -> void:
	# ALWAYS, or the tuner pauses with everything else and the freeze is a hang.
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 2
	visible = false
	_label = Label.new()
	_label.position = Vector2(16.0, 16.0)
	_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6))
	_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	_label.add_theme_constant_override("outline_size", 5)
	add_child(_label)

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.physical_keycode == KEY_F9:
		_toggle()
		return
	if not _active:
		return
	var step := position_step
	var turn := rotation_step
	if event.shift_pressed:
		step *= coarse_multiplier
		turn *= coarse_multiplier
	match event.physical_keycode:
		# Position, in the body's own frame: -Z is the way it faces.
		KEY_I: _position.z -= step
		KEY_K: _position.z += step
		KEY_J: _position.x -= step
		KEY_L: _position.x += step
		KEY_U: _position.y -= step
		KEY_O: _position.y += step
		# Rotation. Yaw is the one that matters most -- a vault plants one
		# particular hand, so a clip built for the other side needs turning.
		KEY_BRACKETLEFT: _rotation.y -= turn
		KEY_BRACKETRIGHT: _rotation.y += turn
		KEY_SEMICOLON: _rotation.x -= turn
		KEY_APOSTROPHE: _rotation.x += turn
		KEY_COMMA: _rotation.z -= turn
		KEY_PERIOD: _rotation.z += turn
		KEY_BACKSPACE:
			_position = Vector3.ZERO
			_rotation = Vector3.ZERO
		KEY_ENTER, KEY_KP_ENTER:
			_print_entry()
			return
		_:
			return
	_apply()

## F9 freezes on the current frame and starts tuning whatever clip is playing;
## F9 again writes the value into the live table and lets the game run on, so
## the next vault is played with what was just dialled in.
func _toggle() -> void:
	if player == null or player.body == null:
		return
	_active = not _active
	visible = _active
	get_tree().paused = _active
	if _active:
		_clip = player._current_clip()
		var existing: Array = player.clip_offset_for(_clip)
		_position = existing[0] if not existing.is_empty() else Vector3.ZERO
		_rotation = existing[1] if not existing.is_empty() else Vector3.ZERO
		_apply()
	else:
		_commit()

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

func _print_entry() -> void:
	print('"%s": [Vector3(%.3f, %.3f, %.3f), Vector3(%.1f, %.1f, %.1f)],'
			% [_clip, _position.x, _position.y, _position.z,
			_rotation.x, _rotation.y, _rotation.z])
	_refresh("printed to the console")

func _refresh(note: String = "") -> void:
	if _label == null:
		return
	var lines: Array[String] = [
		"CLIP OFFSET TUNER  --  frozen on '%s'" % _clip,
		"",
		"  position  %+.3f %+.3f %+.3f   (m, body frame, -Z is forward)"
				% [_position.x, _position.y, _position.z],
		"  rotation  %+.1f %+.1f %+.1f   (deg, pivot at the model's feet)"
				% [_rotation.x, _rotation.y, _rotation.z],
		"",
		"  I/K forward-back   J/L left-right   U/O down-up",
		"  [ ] yaw    ; ' pitch    , . roll    Shift = x%d" % int(coarse_multiplier),
		"  Enter  print the line to paste into the profile",
		"  Back   reset to zero",
		"  F9     unfreeze, keeping this offset live for the next play",
	]
	if note != "":
		lines.append("")
		lines.append("  " + note)
	_label.text = "\n".join(lines)
