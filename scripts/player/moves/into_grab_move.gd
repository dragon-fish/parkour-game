class_name IntoGrabMove
extends Move

# The original's TdMove_IntoGrab: the reach between catching a ledge and
# hanging from it.
#
# The body is carried to a FIXED pose relative to the edge -- 0.30 m back,
# 0.928 m down (GrabDesiredLedgeOffset) -- at a FIXED rate (IntoGrabAlignSpeed,
# 3 m/s). Everything the owner reported about the manoeuvre falls out of those
# two numbers: every hang ends up looking identical however it was caught, and
# a reach that has further to travel takes proportionally longer. The duration
# is a consequence of the geometry, not a setting.
#
# Before this existed the body simply froze wherever it made contact, which is
# what left the player hanging in mid-air a long way out from the wall.
#
# Deliberately NOT a ScriptedMove: that base interpolates over a fixed
# DURATION, and the whole character of this manoeuvre is a fixed SPEED with the
# duration falling out of the distance.

var _aborted: bool = false
var _target: Vector3 = Vector3.ZERO
var _reach_time: float = 0.0

func enter(_previous: StringName) -> void:
	# Declared, not read: this move drives the body directly and never calls
	# move_and_slide(), so is_on_floor() would report whatever the previous
	# move left behind. Same reasoning as SpeedVaultMove and GrabMove.
	player.set_grounded(false)
	_aborted = false
	_reach_time = 0.0
	player.velocity = Vector3.ZERO

	var query: Dictionary = player.probes.ledge_query() if player.probes != null else Probes.NO_HIT.duplicate()
	if not query["valid"]:
		# Nothing to reach for. There is no safe position to invent here, so
		# invent none -- physics_update() hands straight back to Falling.
		_aborted = true
		return
	_target = _hanging_pose(query["edge"])

## Where the body ends up, given the edge it caught.
##
## "Back from the edge" is measured along the body's own approach, taken from
## the edge rather than from the facing: the player may have caught the ledge
## while looking somewhere else entirely, and the pose belongs to the wall, not
## to the camera.
func _hanging_pose(edge: Vector3) -> Vector3:
	# `player` is deliberately untyped (see Move), so its values arrive as
	# Variant and need an explicit type here.
	var to_edge: Vector3 = edge - player.global_position
	to_edge.y = 0.0
	var approach: Vector3 = to_edge.normalized() if to_edge.length_squared() > 0.0001 \
		else -player.global_transform.basis.z
	approach.y = 0.0
	if approach.length_squared() < 0.0001:
		approach = Vector3.FORWARD
	return edge - approach.normalized() * cfg.ledge_back_offset \
		- Vector3.UP * cfg.ledge_down_offset

func physics_update(delta: float, _input: MoveInput) -> StringName:
	if _aborted:
		return FALLING
	_reach_time += delta
	player.set_grounded(false)
	player.velocity = Vector3.ZERO

	var to_target: Vector3 = _target - player.global_position
	# Arrived, or close enough that the rest would not be visible.
	if to_target.length() <= cfg.min_adjust_distance:
		player.global_position = _target
		return GRAB
	if _reach_time >= cfg.max_duration:
		# Something is in the way and the reach is never going to land. Falling
		# is the honest outcome -- better than hanging in the air mid-reach.
		return FALLING

	var stepped: float = cfg.align_speed * delta
	if stepped >= to_target.length():
		player.global_position = _target
		return GRAB
	player.global_position += to_target.normalized() * stepped
	return KEEP
