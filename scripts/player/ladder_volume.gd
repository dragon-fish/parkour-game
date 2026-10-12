class_name LadderVolume
extends RefCounted

# The original's TdLadderVolume, over a LADDER InterestLine: the line runs up
# the rungs, InterestLine.front() is the side the ladder is climbed from (the
# volume's WallNormal), and the line's area is the volume.
#
# [ME:CONFIRMED decompile script TdLadderVolume.uc] StepHeight 32 uu, the pawn
# held XYOffsetLadder 50 uu (XYOffsetPipe 62) out from the ladder, a pipe's
# steps ZOffsetPipe 5 uu lower; Vector(Rotation) points into the wall
# (IntoClimb's facing and behind-the-ladder tests need it so); MoveDirection is
# up (IntoClimb's top entry lands FirstStepZDistance, 38 uu, below the top step
# with it).
# [ME:INFERRED] The step natives (GetLadderLocation, GetClosestStep and its Up
# and Down variants, GetLastStep) were not decompiled. Here step 0 holds the
# body standing at the ladder's foot -- its centre the default half height over
# the line's lower end -- and every step is StepHeight above the last, up to
# the highest that keeps the centre on the line. The closest step rounds and is
# not clamped (the script clamps it where it matters); a location is asked for
# a clamped step.

const UU := 0.01
const STEP_HEIGHT := 32.0 * UU
const XY_OFFSET_LADDER := 50.0 * UU
const XY_OFFSET_PIPE := 62.0 * UU
const Z_OFFSET_PIPE := -5.0 * UU
## The default pawn's half height, the foot step's centre over the line.
const FOOT_HEIGHT := 90.0 * UU

var line: InterestLine

func _init(interest_line: InterestLine) -> void:
	line = interest_line

func is_valid() -> bool:
	return is_instance_valid(line)

## LT_Pipe.
func is_pipe() -> bool:
	return line.pipe

## WallNormal: out from the wall, the side it is climbed from.
func wall_normal() -> Vector3:
	return line.front()

## Vector(Rotation): into the wall.
func rotation_dir() -> Vector3:
	return -line.front()

## MoveDirection.
func move_direction() -> Vector3:
	return Vector3.UP

## The line's lower and upper ends.
func _bottom() -> Vector3:
	var a: Vector3 = line.sample(0.0)["position"]
	var b: Vector3 = line.sample(line.length())["position"]
	return a if a.y <= b.y else b

func _top() -> Vector3:
	var a: Vector3 = line.sample(0.0)["position"]
	var b: Vector3 = line.sample(line.length())["position"]
	return b if a.y <= b.y else a

## Center.
func center() -> Vector3:
	return (_bottom() + _top()) * 0.5

## Location.
func location() -> Vector3:
	return center()

func _step_zero_z() -> float:
	return _bottom().y + FOOT_HEIGHT + (Z_OFFSET_PIPE if is_pipe() else 0.0)

## GetLastStep.
func get_last_step() -> int:
	return maxi(0, int(floor((_top().y - _step_zero_z()) / STEP_HEIGHT)))

## GetClosestStep(LocationZ): rounded, unclamped.
func get_closest_step(z: float) -> int:
	return int(round((z - _step_zero_z()) / STEP_HEIGHT))

## GetClosestStepDown / Up.
func get_closest_step_down(z: float) -> int:
	return int(floor((z - _step_zero_z()) / STEP_HEIGHT))

func get_closest_step_up(z: float) -> int:
	return int(ceil((z - _step_zero_z()) / STEP_HEIGHT))

## GetLadderLocation(Index): where the body is held on step Index (clamped):
## on the line at that height, out from it by the ladder's offset.
func get_ladder_location(index: int) -> Vector3:
	var i: int = clampi(index, 0, get_last_step())
	var z: float = _step_zero_z() + float(i) * STEP_HEIGHT
	var bottom: Vector3 = _bottom()
	var top: Vector3 = _top()
	var t: float = 0.0 if is_equal_approx(top.y, bottom.y) else clampf((z - bottom.y) / (top.y - bottom.y), 0.0, 1.0)
	var on_line: Vector3 = bottom.lerp(top, t)
	var out: float = XY_OFFSET_PIPE if is_pipe() else XY_OFFSET_LADDER
	return Vector3(on_line.x, z, on_line.z) + wall_normal() * out
