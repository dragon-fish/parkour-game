class_name Crosshair
extends CanvasLayer

# A plain white dot at the centre of the screen, matching the original's.
#
# It is not an aiming reticle -- nothing in this game is aimed. It exists
# because a first-person camera with no fixed point of reference is genuinely
# nauseating to play for long, and because a dot is the cheapest way to read
# which way the body is facing during a wall run or a turn.
#
# Lives on the PLAYER rather than the level, next to ScreenEffects, for the
# same reason that one does: it describes the player's own view, and must
# survive a level change.

## PROJECT-DEFINED. Small enough to read as a point rather than a target.
const RADIUS := 2.0

# --- balance readout ---------------------------------------------------------
#
# A TUNING INSTRUMENT, not a game HUD element. The pendulum is invisible
# internal state, and the owner asked to see it while turning its dials: the
# arc shows how far the lean has gone, and the spur on its end shows where it
# is going next, because the move's entire skill is zeroing those two together
# and a display of only the first hides the half being failed.

## Radius of the arc, pixels, and how far either way it spans. The dot sits at
## its centre of curvature, so the arc reads as a horizon the dot hangs under.
const ARC_RADIUS := 34.0
const ARC_HALF_SPAN_DEG := 60.0
const ARC_TRACK_WIDTH := 2.0
const ARC_MARK_WIDTH := 4.0

## Screen angles, radians. Godot's draw_arc measures from +X with Y pointing
## down, so straight up is -90 degrees.
const _ARC_CENTRE := -PI * 0.5

## Assigned by tools/player_builder.gd. Optional so a hand-built player in a
## headless test does not need one.
@export var player: Player

var _dot: Control

func _ready() -> void:
	layer = 1
	_dot = Control.new()
	_dot.name = "Dot"
	_dot.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dot.draw.connect(_draw_dot)
	add_child(_dot)
	get_viewport().size_changed.connect(_dot.queue_redraw)

func _draw_dot() -> void:
	var centre: Vector2 = _dot.size * 0.5
	_draw_balance_readout(centre)
	# A hairline of dark behind it, so the dot survives being drawn over
	# white geometry -- which this project's blockout is largely made of.
	_dot.draw_circle(centre, RADIUS + 1.0, Color(0.0, 0.0, 0.0, 0.35))
	_dot.draw_circle(centre, RADIUS, Color.WHITE)

## The balance move's own two numbers, drawn as an arc over the dot. Nothing at
## all when the player is not on a beam.
##
## Duck-typed off the active move rather than reached for by name, so this file
## does not depend on BalanceMove's class and a move that grows the same two
## readings later gets the display for free.
func _draw_balance_readout(centre: Vector2) -> void:
	if player == null or player.move_manager == null:
		return
	var move = player.move_manager.move_for(player.move_manager.current_name)
	if move == null:
		return
	if not move.has_method("signed_severity"):
		return
	if not move.has_method("signed_rate_severity"):
		return
	var span: float = deg_to_rad(ARC_HALF_SPAN_DEG)
	_dot.draw_arc(centre, ARC_RADIUS, _ARC_CENTRE - span, _ARC_CENTRE + span,
		48, Color(1.0, 1.0, 1.0, 0.35), ARC_TRACK_WIDTH, true)

	# The lean itself: a band from the centre of the arc out to where the body
	# currently is. Reddens as it approaches the edge it falls off at, which is
	# what severity already means -- 1 IS the fall, so the colour needs no
	# threshold of its own.
	var lean: float = clampf(move.signed_severity(), -1.0, 1.0)
	var lean_angle: float = _ARC_CENTRE + span * lean
	if absf(lean) > 0.01:
		_dot.draw_arc(centre, ARC_RADIUS, minf(_ARC_CENTRE, lean_angle),
			maxf(_ARC_CENTRE, lean_angle), 32,
			Color(1.0, 1.0, 1.0, 0.9).lerp(Color(0.9, 0.2, 0.15, 1.0), absf(lean)),
			ARC_MARK_WIDTH, true)

	# Where it is heading: a spur from the body's own position, forward along
	# the arc. Pointing back toward the centre means the correction is winning.
	var rate: float = clampf(move.signed_rate_severity(), -1.0, 1.0)
	if absf(rate) > 0.01:
		var to_angle: float = lean_angle + span * rate * 0.5
		_dot.draw_arc(centre, ARC_RADIUS + ARC_MARK_WIDTH,
			minf(lean_angle, to_angle), maxf(lean_angle, to_angle), 24,
			Color(0.35, 0.85, 0.4, 0.95), ARC_TRACK_WIDTH, true)

## Shown only while the player actually has control: hidden for the death
## cutscene (which takes the input gate) and while the cursor is released for
## the tuning panel, where a dot over a slider is just clutter.
func _process(_delta: float) -> void:
	if _dot == null:
		return
	var wanted: bool = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
		and (player == null or not player.is_input_locked())
	if _dot.visible != wanted:
		_dot.visible = wanted
	# The dot alone never changes, but the balance arc over it does, every
	# tick. Redrawn only while a move is actually reporting a lean, so an
	# ordinary run costs the same nothing it always did -- PLUS the one frame
	# the readout goes away. A CanvasItem keeps its last drawing until someone
	# asks for another, and on the frame the beam is left nobody is reporting a
	# lean any more, so without that extra redraw the final arc stays painted
	# over the dot for the rest of the run.
	var active: bool = wanted and _balance_readout_active()
	if active or _readout_drawn:
		_dot.queue_redraw()
	_readout_drawn = active

## Whether the last redraw this file asked for carried the balance arc. See
## _process() for why the frame after it goes away needs one more.
var _readout_drawn: bool = false

func _balance_readout_active() -> bool:
	if player == null or player.move_manager == null:
		return false
	var move = player.move_manager.move_for(player.move_manager.current_name)
	return move != null and move.has_method("signed_rate_severity")
