@tool
class_name EffectVolume
extends Area3D

# Somewhere that is not dangerous but is not nothing: give it whatever
# CollisionShape3D children the spot needs, and entering it is heard and felt.
#
# THIS IS HOW THE ORIGINAL WARNS. A Mall train's own mesh has no collision at
# all; what the level hangs on it are volumes like this one. A box 48 m AHEAD
# of the head sounds the horn, so the warning arrives before the thing does; a
# cylinder around the head shakes the camera while it passes. The lethal box
# around the cars is a DeathVolume, built beside this one from the same hull.
#
# NOTHING HERE DECIDES ANYTHING. The exports are the whole interface: what to
# play, how hard to shake, how long. Which volume gets which is read out of the
# original's Kismet by the extractor, so a rule added here would be a second
# opinion about a question already answered.
#
# ONE FIRING PER ENTRY, not per tick. A volume 92 m long takes over a second
# to pass, and a horn re-sounded every frame is a klaxon.

## Sounds for a touch, in no order: one is chosen at random. Several is the
## normal case, not a special one -- the original runs the horn through a
## RandomSwitch so the same train is not heard twice the same way.
@export var sounds: Array[AudioStream] = []
## The original's own shake numbers, unconverted. CameraConfig scales them --
## see its shake_amplitude_scale. Zero amplitude means this volume does not
## shake, which is the common case.
@export var shake_amplitude: float = 0.0
@export var shake_frequency: float = 0.0
## Seconds the shake runs at full before dying away.
@export var shake_hold: float = 0.0

## Players built for one-shots and reused: a train passing every fifteen
## seconds for a whole chapter would otherwise leave a node behind each time.
var _voices: Array[AudioStreamPlayer3D] = []


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	body_entered.connect(_on_body_entered)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	var has_shape := false
	for child in get_children():
		if child is CollisionShape3D and child.shape != null:
			has_shape = true
	if not has_shape:
		warnings.append("No CollisionShape3D with a shape: nothing can ever enter this.")
	if sounds.is_empty() and shake_amplitude <= 0.0:
		warnings.append("Neither a sound nor a shake: entering this does nothing.")
	return warnings


func _on_body_entered(body: Node3D) -> void:
	# Duck-typed, the same stance as DeathVolume and Checkpoint: the volume
	# tells whoever can listen, and cares nothing for who else wanders in.
	if not body.has_method("touch_checkpoint"):
		return
	_play_one()
	if shake_amplitude > 0.0:
		var rig: Node = body.get("camera_rig")
		if rig != null and rig.has_method("add_shake"):
			rig.add_shake(shake_amplitude, shake_frequency, shake_hold)


func _play_one() -> void:
	if sounds.is_empty():
		return
	var voice := _free_voice()
	voice.stream = sounds[randi() % sounds.size()]
	voice.play()


func _free_voice() -> AudioStreamPlayer3D:
	for voice in _voices:
		if not voice.playing:
			return voice
	var made := AudioStreamPlayer3D.new()
	made.name = "Voice%d" % _voices.size()
	# The volume rides the train, so its sound does too, and a source closing
	# at 50 m/s that holds its pitch reads as a recording rather than a thing.
	# The camera carries the other half of this -- see player_builder.gd.
	made.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
	add_child(made)
	_voices.append(made)
	return made
