class_name MenuMusic
extends Node

# The menu's music, in two pieces cut from one track.
#
# THE POINT IS THE HANDOFF. The held title shot plays eight restrained bars;
# the click enters the record two bars before its chorus, on the approach the
# composer wrote into it, and the drop then arrives by itself.
#
# It works because the tempo never changes across the track, so the phase the
# fragment had reached is still the right phase anywhere in the record. Enter
# at that phase and the grid runs unbroken through the crossfade: no waiting
# for a bar line, which on a button would read as the button not working, and
# no restarting the count inside the fade.
#
# THREE MOMENTS, TWO FILES. The title fragment loops continuously and
# gaplessly -- background for a decision nobody is being hurried into. The
# other file is the whole record, and it covers the remaining two by itself:
# entered at bar 32 it is "from the chorus onward", and entered at zero, after
# a rest, it is the track from the top, on repeat. Cutting a separate chorus
# file would have stored the same three minutes twice.
#
# NOTHING HERE JUMPS IN LEVEL. The loop sits well back, the chorus arrives at
# that same level and then swells to its own, and leaving is a long fade. A
# menu is the first thing a player hears, often through headphones they set
# for something else.

const LOOP_STREAM := "res://assets/audio/menu_loop.ogg"
const FULL_STREAM := "res://assets/audio/menu_full.ogg"

## Measured off the track, not guessed: 132.5076 BPM in 4/4. Two independent
## methods agreed (a beat comb over the onset envelope, and a least-squares fit
## through 203 kick onsets), and the structure confirms it -- the drums enter
## at exactly bar 16 and the chorus at exactly bar 32, with the first downbeat
## at 0.000 s. A cross-correlation estimate of 132.63 was the outlier.
const BAR := 1.811217

## Where the chorus lands in the record: bar 32.
const CHORUS_START := 32.0 * BAR

## AND WHERE THE CLICK ACTUALLY ENTERS: two bars earlier, on the approach the
## composer wrote into it.
##
## Entering at the chorus itself was the first attempt and it was abrupt, for
## a reason worth keeping: aligning the BEAT is the weakest alignment there
## is. Music is beats inside bars inside phrases, and entering bar 32 partway
## through means its downbeat -- the heaviest moment in the piece -- has
## already gone by. The full arrangement simply appears, with no arrival.
##
## Bars 30 and 31 are the lift: the same sparse texture the title fragment
## has, with a riser climbing through it. Entering there, the crossfade is
## between two quiet things and is barely audible, and because the grid runs
## unbroken the chorus's own downbeat then lands on time and at full weight
## three and a half seconds later -- which is also about when the menu
## finishes arriving.
##
## This is the cheap version of what a middleware transition does with a
## composed bridge or a stinger: use the composer's own approach as the
## transition rather than butting two sections together.
const APPROACH_START := 30.0 * BAR


## Held back on purpose. This plays under a title card while the player is
## still deciding to press anything, and it is the first sound the game makes.
const HELD_LEVEL := 0.20

## Where the chorus settles. Fuller, not loud -- the drop is carried by the
## drums arriving on the grid, not by the fader.
const CHORUS_LEVEL := 0.62

## The crossfade itself, at HELD_LEVEL throughout: this is a change of
## material, not of volume.
const HANDOFF := 0.6

## THE SWEEP OPENS AT BOTH ENDS, and that shape was measured rather than
## chosen. A recording of a shipped menu that does this properly -- a quiet
## loop, a click, a full arrangement -- differs between its two states by
## +7.3 dB in the sub, +8.0 dB in the low and +7.4 dB in the top, against
## only +2.5 dB across the mids. That is the fingerprint of vertical
## layering: the melodic core is the SAME layer in both states, and what
## arrives on the click is the bottom (kick and bass) and the air (hats and
## percussion).
##
## So the closed state is a BAND, not a muffle. A plain low-pass is that
## fingerprint upside down -- it keeps the bottom and takes the mids away --
## and it sounds like a filter, where this sounds like instruments arriving.
##
## This is as close to layering as a finished mix gets, and as close as this
## track allows: separated into stems, its kick and its sub-bass overlapped
## too far to be pulled apart, and a drum-less version kept most of its kick.
##
## Swept in OCTAVES, not hertz. Pitch is logarithmic, so a linear ramp through
## frequency spends nearly all its time in the top octave, where almost
## nothing is happening, and crosses the octaves that matter in an instant.
const TOP_FROM_HZ := 2600.0
const TOP_TO_HZ := 20500.0
const BOTTOM_FROM_HZ := 260.0
const BOTTOM_TO_HZ := 20.0

## The lift to CHORUS_LEVEL runs from the moment of the click until the drop,
## so it is not a constant: it is however much of the approach is left. That
## way the level arrives exactly when the chorus does, rather than still
## climbing through it or having got there early and sat waiting.

## The pause before the record starts over. Long enough to read as deliberate
## rather than as a dropout; the piece it follows is two and a half minutes
## long, so nobody is waiting on it.
const REST := 3.0

## Leaving for the level. Longer than everything else here: this one has the
## whole loading run to happen over, and there is nothing to be gained by
## finishing early.
const FADE_OUT := 2.2

## The bus the record plays through, so the sweep has somewhere to live. The
## fragment is left on Master: it already sits inside the band the sweep opens
## out of, and filtering it too would only take away the thing being matched.
const BUS := &"MenuMusicSweep"

var _loop: AudioStreamPlayer
var _record: AudioStreamPlayer
var _top: AudioEffectLowPassFilter
var _bottom: AudioEffectHighPassFilter
var _in_chorus: bool = false
## True once the menu is on its way out, which cancels the rest-and-restart
## cycle. Without it a piece that ends mid-fade schedules itself to start
## again at full level, over the top of the fade that was seeing it off.
var _leaving: bool = false

func _ready() -> void:
	_build_bus()
	_loop = _player(LOOP_STREAM, true)
	_record = _player(FULL_STREAM, false)
	_loop.volume_db = _gain_db(HELD_LEVEL)
	_record.volume_db = _gain_db(0.0)
	_record.bus = BUS
	_record.finished.connect(_rest_then_play_from_the_top)
	_loop.play()

## Reused rather than added again if one is already there: a menu rebuilt (a
## return from the level, a scene reload) would otherwise stack a new bus per
## visit, and the buses are engine-wide.
func _build_bus() -> void:
	var index: int = AudioServer.get_bus_index(BUS)
	if index == -1:
		index = AudioServer.bus_count
		AudioServer.add_bus(index)
		AudioServer.set_bus_name(index, BUS)
		AudioServer.set_bus_send(index, &"Master")
	while AudioServer.get_bus_effect_count(index) > 0:
		AudioServer.remove_bus_effect(index, 0)
	# 24 dB per octave on both. A gentler slope leaves enough through that the
	# sweep reads as a change of volume rather than as instruments arriving.
	_bottom = AudioEffectHighPassFilter.new()
	_bottom.cutoff_hz = BOTTOM_TO_HZ
	_bottom.db = AudioEffectFilter.FILTER_24DB
	AudioServer.add_bus_effect(index, _bottom)
	_top = AudioEffectLowPassFilter.new()
	_top.cutoff_hz = TOP_TO_HZ
	_top.db = AudioEffectFilter.FILTER_24DB
	AudioServer.add_bus_effect(index, _top)

## Engine-wide state, so it is this node's to clean up. Looked up by name
## rather than by a remembered index: another system adding a bus in the
## meantime shifts every index after its own.
func _exit_tree() -> void:
	var index: int = AudioServer.get_bus_index(BUS)
	if index != -1:
		AudioServer.remove_bus(index)

## `looping` decides who owns the repeat. The title fragment is looped by the
## engine, which is sample-accurate and gapless; the record is left un-looped
## so its ending can be heard and rested after.
##
## The flag is set on the resource rather than in the .import file on purpose
## -- see .claude/skills/authoring-godot-scene-files: an import file is
## regenerated, often untracked, and a first headless import can wipe it. A
## duplicate() so nothing else loading the same path inherits the flag.
func _player(path: String, looping: bool) -> AudioStreamPlayer:
	var node := AudioStreamPlayer.new()
	if ResourceLoader.exists(path):
		var stream: AudioStream = load(path)
		if looping:
			stream = stream.duplicate()
			if stream is AudioStreamOggVorbis:
				(stream as AudioStreamOggVorbis).loop = true
		node.stream = stream
	add_child(node)
	return node

## The record has played out. Rest, then take it FROM THE TOP -- not from the
## chorus, and not back to the quiet figure. The first pass entered late
## because a click had just happened; a second pass has no click to answer,
## so it is simply the track.
##
## Silent while leaving: a piece that ends mid-goodbye would otherwise
## schedule itself to start again at full level, over the top of the fade
## that was seeing it off.
func _rest_then_play_from_the_top() -> void:
	if _leaving or _record.stream == null:
		return
	var again := create_tween()
	again.tween_interval(REST)
	again.tween_callback(_record.play.bind(0.0))

## The click. Enters the chorus at the phase the loop had reached, so the grid
## continues through the crossfade instead of restarting inside it.
func to_chorus() -> void:
	if _in_chorus or _record.stream == null:
		return
	_in_chorus = true
	var entry: float = chorus_entry(_loop.get_playback_position())
	var run_up: float = time_to_the_drop(entry)
	_set_openness(0.0)
	_record.play(entry)
	var hand := create_tween().set_parallel()
	hand.tween_method(_set_handoff, 0.0, 1.0, HANDOFF)
	# The sweep and the swell both END ON THE DROP, so the record arrives
	# open and at level exactly as the chorus's downbeat lands.
	hand.tween_method(_set_openness, 0.0, 1.0, run_up) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	hand.tween_method(_set_record_level, HELD_LEVEL, CHORUS_LEVEL, run_up) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# Its own tween: the fragment is silent once the handoff ends, and the
	# sweep it runs alongside is five times longer.
	var release := create_tween()
	release.tween_interval(HANDOFF)
	release.tween_callback(_loop.stop)

## Where in the RECORD to start, given where the title fragment had got to.
## The approach's own downbeat, plus however far into a bar the fragment was,
## so the grid continues through the crossfade instead of restarting inside
## it -- and so the chorus that follows lands on time.
##
## Pure and static so the arithmetic can be checked without an audio device: a
## headless run has a dummy driver and reports a playback position of zero
## forever, which would make a test of this pass for the wrong reason.
static func chorus_entry(loop_position: float) -> float:
	return APPROACH_START + fmod(maxf(loop_position, 0.0), BAR)

## How long the entry has before the chorus lands on it. The swell is given
## exactly this, so the two arrive together.
static func time_to_the_drop(entry: float) -> float:
	return maxf(CHORUS_START - entry, 0.1)

## Leaving the menu. Silence would be as wrong as a hard cut.
func fade_out(seconds: float = FADE_OUT) -> void:
	_leaving = true
	var out := create_tween().set_parallel()
	for player in [_loop, _record]:
		if player.playing:
			out.tween_property(player, "volume_db", _gain_db(0.0), seconds)

## Equal power at a CONSTANT total, not a fade up to a new level: two halves
## of a linear crossfade sum to a dip in the middle, which on a continuous
## beat is heard as the music flinching at the moment the click was supposed
## to land. The lift to CHORUS_LEVEL is a separate, much slower move.
func _set_handoff(k: float) -> void:
	_loop.volume_db = _gain_db(cos(k * PI * 0.5) * HELD_LEVEL)
	_record.volume_db = _gain_db(sin(k * PI * 0.5) * HELD_LEVEL)

func _set_record_level(level: float) -> void:
	_record.volume_db = _gain_db(level)

## 0 is the band alone, 1 is the whole spectrum. Both ends move together, so
## the bottom and the top arrive on the same beat.
func _set_openness(k: float) -> void:
	if _top != null:
		_top.cutoff_hz = sweep_at(k, TOP_FROM_HZ, TOP_TO_HZ)
	if _bottom != null:
		_bottom.cutoff_hz = sweep_at(k, BOTTOM_FROM_HZ, BOTTOM_TO_HZ)

## Where a sweep is at `k`, 0 closed to 1 open. Geometric, so equal stretches
## of the tween cover equal numbers of octaves. Static so the curve can be
## checked without an audio device.
static func sweep_at(k: float, from_hz: float, to_hz: float) -> float:
	return from_hz * pow(to_hz / from_hz, clampf(k, 0.0, 1.0))

## Silence is -80 dB, not -inf: linear_to_db(0) returns -inf and the mixer
## refuses it. Same floor SettingsStore uses for a volume slider at zero.
static func _gain_db(amplitude: float) -> float:
	return linear_to_db(amplitude) if amplitude > 0.0001 else -80.0
