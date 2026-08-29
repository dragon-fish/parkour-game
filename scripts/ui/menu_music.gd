class_name MenuMusic
extends Node

# The menu's music, in two pieces cut from one track.
#
# THE POINT IS THE HANDOFF. The held title shot loops eight restrained bars;
# the click drops straight into the chorus. Because both pieces come from the
# same recording at the same tempo and both start on a downbeat, the chorus is
# entered AT THE PHASE THE LOOP HAD REACHED -- so the beat never breaks and the
# crossfade can be short enough to feel like the click caused it. Waiting for
# the next bar line instead would be up to 1.8 s of nothing happening, which
# on a button reads as the button not working.
#
# The two files are pre-cut rather than seeked within one stream, so the engine
# loops them itself: a loop driven from _process() re-seeks a frame late and
# clicks, and MP3 cannot loop gaplessly at all because of encoder padding.
# Each file's own head is crossfaded with the material that followed its tail
# in the original, so the join carries real continuation rather than a cut.

const LOOP_STREAM := "res://assets/audio/menu_loop.ogg"
const CHORUS_STREAM := "res://assets/audio/menu_chorus.ogg"

## Measured off the track, not guessed: 132.5076 BPM in 4/4. Two independent
## methods agreed (a beat comb over the onset envelope, and a least-squares fit
## through 203 kick onsets), and the structure confirms it -- the drums enter
## at exactly bar 16 and the chorus at exactly bar 32, with the first downbeat
## at 0.000 s. A cross-correlation estimate of 132.63 was the outlier.
##
## DO NOT round this to 132. The loop is eight bars long, so an error here is
## eight times as large by the time it reaches the seam.
const BAR := 1.811217

## Long enough to swallow the level change between the two mixes, short enough
## that the click still feels like the cause. The beat carries across it
## unbroken, which is what lets it be this short.
const CROSSFADE := 0.45

## Leaving for the level. Slower than the handoff -- this one is a goodbye,
## not a hit.
const FADE_OUT := 0.9

var _loop: AudioStreamPlayer
var _chorus: AudioStreamPlayer
var _in_chorus: bool = false

func _ready() -> void:
	_loop = _player(LOOP_STREAM)
	_chorus = _player(CHORUS_STREAM)
	_chorus.volume_db = _gain_db(0.0)
	_loop.play()

## Both streams loop. The chorus loops too: a player who sits on the settled
## menu should not be left in silence, and the sixteen bars it holds are the
## whole chorus before the track breaks down.
##
## The flag is set on the resource rather than in the .import file on purpose
## -- see .claude/skills/authoring-godot-scene-files: an import file is
## regenerated, often untracked, and a first headless import can wipe it. A
## duplicate() so two players of the same path cannot fight over one flag.
func _player(path: String) -> AudioStreamPlayer:
	var node := AudioStreamPlayer.new()
	if ResourceLoader.exists(path):
		var stream: AudioStream = load(path).duplicate()
		if stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true
		node.stream = stream
	add_child(node)
	return node

## The click. Enters the chorus at the phase the loop had reached, so the
## grid continues through the crossfade instead of restarting inside it.
func to_chorus() -> void:
	if _in_chorus or _chorus.stream == null:
		return
	_in_chorus = true
	_chorus.play(chorus_entry(_loop.get_playback_position()))
	var blend := create_tween()
	blend.tween_method(_set_blend, 0.0, 1.0, CROSSFADE)
	blend.tween_callback(_loop.stop)

## Where in the chorus to start, given where the loop had got to.
##
## Pure and static so the arithmetic can be checked without an audio device:
## a headless run has a dummy driver and reports a playback position of zero
## forever, which would make a test of this pass for the wrong reason.
static func chorus_entry(loop_position: float) -> float:
	return fmod(maxf(loop_position, 0.0), BAR)

## Leaving the menu. Silence would be as wrong as a hard cut.
func fade_out(seconds: float = FADE_OUT) -> void:
	var out := create_tween().set_parallel()
	for player in [_loop, _chorus]:
		if player.playing:
			out.tween_property(player, "volume_db", _gain_db(0.0), seconds)

## Equal power, not equal amplitude: two halves of a linear crossfade sum to a
## dip in the middle, which on a continuous beat is heard as the music
## flinching at the exact moment the click was supposed to land.
func _set_blend(k: float) -> void:
	_loop.volume_db = _gain_db(cos(k * PI * 0.5))
	_chorus.volume_db = _gain_db(sin(k * PI * 0.5))

## Silence is -80 dB, not -inf: linear_to_db(0) returns -inf and the mixer
## refuses it. Same floor SettingsStore uses for a volume slider at zero.
static func _gain_db(amplitude: float) -> float:
	return linear_to_db(amplitude) if amplitude > 0.0001 else -80.0
