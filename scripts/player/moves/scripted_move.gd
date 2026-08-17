class_name ScriptedMove
extends Move

# Shared machinery for states that DRIVE the body along a computed path rather
# than letting physics push it. Vaulting and mantling both need to pass through
# geometry that would otherwise block them, which is exactly what physics is
# there to prevent — so for the duration of the move, physics steps aside.

var _from: Vector3 = Vector3.ZERO
var _to: Vector3 = Vector3.ZERO
var _duration: float = 0.0
var _elapsed: float = 0.0
## Peak height of the vertical arc added on top of the straight from->to lerp.
## A per-call value (not a shared literal) so each concrete move can supply
## its own — the ledge state arriving next needs a different arc than vault's.
var _arc: float = 0.0

func begin(from: Vector3, to: Vector3, duration: float, arc: float = 0.0) -> void:
	_from = from
	_to = to
	_duration = maxf(duration, 0.0001)
	_elapsed = 0.0
	_arc = arc

func progress() -> float:
	return clampf(_elapsed / _duration, 0.0, 1.0)

## Moves the body one tick along the path. Returns true once the path is done.
func advance(delta: float) -> bool:
	_elapsed += delta
	var t := progress()
	# Ease-out: most of the travel happens early, so the action reads as a
	# push-off rather than a constant-speed slide. The exponent is a curve-shape
	# decision, not a feel dial with a meaningful tuning range, so it stays a
	# literal here rather than moving into MovementConfig alongside _arc.
	var eased := 1.0 - pow(1.0 - t, 2.0)
	var target := _from.lerp(_to, eased)
	# An arc, so the body rises over the obstacle instead of through it.
	target.y += sin(t * PI) * _arc
	player.global_position = target
	return t >= 1.0
