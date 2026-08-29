class_name ChladniField
extends ColorRect

# The main menu's background field: powder on a plate the music is driving.
# Above the horizon, behind everything, and reacting to what is playing.
#
# See chladni.gdshader for what a Chladni figure is and how it is drawn. This
# half is only the wiring: read the spectrum, decide which mode the plate is
# in, and how hard it is being shaken.
#
# WHY THE BANDS ARE SPLIT THIS WAY. The two mode numbers want to move
# independently and slowly, so they are driven by the two ends of the
# spectrum -- the bottom, which is the drums, and the top, which is the
# percussion and air. The mids drive nothing: they barely change between the
# menu's quiet state and its loud one (see docs/music-transitions.md), so a
# figure driven from them would sit still through the one moment it exists to
# answer.

const SHADER := preload("res://scripts/ui/chladni.gdshader")

## The modes the plate is allowed to be in.
##
## INTEGERS, and small ones. The closed form only produces a symmetric figure
## at whole numbers, and past about nine the lines are finer than the grain
## and it turns into an even grey. The pair must also differ, or the two terms
## cancel and the plate is flat everywhere.
const MODE_MIN := 2
const MODE_MAX := 9

## How fast the figure reorganises. A real plate snaps between modes; this
## crosses through the shapes in between instead, because at this size and
## opacity a snap reads as a glitch rather than as physics.
const MODE_EASE := 0.7

## How fast loudness reaches the shader. Quicker than the modes, so the grain
## visibly answers the beat while the figure it belongs to holds.
const LEVEL_EASE := 8.0

## Loudness that counts as the plate being driven flat out. Menu music is
## deliberately quiet, so this is well below unity.
const FULL_DRIVE := 0.12

@export var tint: Color = Color(0.34, 0.41, 0.52, 1.0)
## How strongly the field shows at all. It sits behind a title card and a
## figure; it is scenery, not a visualiser.
@export var strength: float = 0.5

var _material: ShaderMaterial
var _analyzer: AudioEffectSpectrumAnalyzerInstance
## True only if this node was the one to install the analyser, so it does not
## remove somebody else's on the way out.
var _installed_analyzer: bool = false

var _n: float = float(MODE_MIN)
var _m: float = float(MODE_MAX)
var _drive: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color(0.0, 0.0, 0.0, 0.0)
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	material = _material
	_material.set_shader_parameter("tint", tint)
	_install_analyzer()

## On Master rather than on the music's own bus: the music plays through two
## buses that come and go with the menu, and a field that stopped moving
## whenever one of them was swapped would be a bug nobody could find.
##
## Reused if one is already there. Effects on a bus are engine-wide, so a menu
## rebuilt on the way back from the level would otherwise stack a new analyser
## per visit.
func _install_analyzer() -> void:
	var count: int = AudioServer.get_bus_effect_count(0)
	for i in count:
		if AudioServer.get_bus_effect(0, i) is AudioEffectSpectrumAnalyzer:
			_analyzer = AudioServer.get_bus_effect_instance(0, i)
			return
	AudioServer.add_bus_effect(0, AudioEffectSpectrumAnalyzer.new())
	_installed_analyzer = true
	_analyzer = AudioServer.get_bus_effect_instance(0, count)

func _exit_tree() -> void:
	if not _installed_analyzer:
		return
	for i in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0, i) is AudioEffectSpectrumAnalyzer:
			AudioServer.remove_bus_effect(0, i)
			return

func _process(delta: float) -> void:
	if _material == null:
		return
	var bottom: float = _band(30.0, 220.0)
	var top: float = _band(3500.0, 11000.0)
	var loudness: float = _band(30.0, 16000.0)

	# The pair is chosen from the two ends and then kept apart: equal modes
	# cancel the closed form to zero, which is a plate with nothing on it.
	var wanted := mode_pair(bottom, top)
	_n = lerpf(_n, float(wanted.x), clampf(delta * MODE_EASE, 0.0, 1.0))
	_m = lerpf(_m, float(wanted.y), clampf(delta * MODE_EASE, 0.0, 1.0))
	_drive = lerpf(_drive, clampf(loudness / FULL_DRIVE, 0.0, 1.0),
		clampf(delta * LEVEL_EASE, 0.0, 1.0))

	_material.set_shader_parameter("mode_n", _n)
	_material.set_shader_parameter("mode_m", _m)
	_material.set_shader_parameter("agitation", _drive)
	# A plate driven harder holds its powder less tightly, so the figure
	# thickens rather than only shaking.
	_material.set_shader_parameter("settle", lerpf(0.10, 0.30, _drive))
	_material.set_shader_parameter("brightness", strength * lerpf(0.55, 1.0, _drive))
	_material.set_shader_parameter("aspect", maxf(size.x, 1.0) / maxf(size.y, 1.0))

## Which mode the two ends of the spectrum ask for. Pure and static so the
## mapping can be checked without an audio device -- a headless run has a
## dummy driver and every band reads zero, which would make a test of this
## pass while proving nothing.
##
## The two are pulled apart deliberately: at n == m the closed form is zero
## everywhere, so the plate would go blank at exactly the moments the whole
## spectrum moves together, which is every drop. Pulled apart by ONE step --
## see below for why sending the clash to an end of the range is worse than
## the clash.
static func mode_pair(bottom: float, top: float) -> Vector2i:
	var span: int = MODE_MAX - MODE_MIN
	var n: int = MODE_MIN + int(round(clampf(bottom * 12.0, 0.0, 1.0) * float(span)))
	var m: int = MODE_MIN + int(round(clampf(top * 40.0, 0.0, 1.0) * float(span)))
	# NUDGED ONE STEP, not thrown to an end. Sending the clash to MODE_MAX
	# also sends SILENCE there -- both ends read zero, both land on MODE_MIN,
	# and the plate answers with its finest figure at the quietest moment.
	if n == m:
		m = n + 1 if n < MODE_MAX else n - 1
	return Vector2i(n, m)

func _band(from_hz: float, to_hz: float) -> float:
	if _analyzer == null:
		return 0.0
	return _analyzer.get_magnitude_for_frequency_range(from_hz, to_hz).length()
