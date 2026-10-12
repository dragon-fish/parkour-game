class_name LadderVolume
extends RefCounted

# The original's TdLadderVolume, over a LADDER InterestLine. The line is the
# volume's Start..End: from its bottom face to its top face, through its
# centre, along MoveDirection. InterestLine.front() is the side the ladder is
# climbed from (the volume's WallNormal), and the line's area is the volume.
#
# [ME:CONFIRMED decompile 0x012ab620, N7 §1] The steps are built once, as the
# original builds PawnLadderLocations from the brush at load: S, one
# StepHeight (32 uu) above Start and 64 uu back from the climbing face; the top
# step 96 uu under the top face; the steps every StepHeight DOWN from it, as
# many as trunc((TopZ - S.z) / StepHeight) (a TRUNCATION: the remainder is left
# at the bottom, so the lowest step sits 32 .. 64 uu over Start).
# [ME:CONFIRMED emulated 0x012ab3b0 .. 0x012aa0e0] GetLadderLocation holds
# the body 50 uu (pipe 62) out along WallNormal from the step, a pipe's 5 uu
# lower; GetClosestStep is the nearest of ALL the steps by height, the lowest
# on a tie; GetLastStep is the top one, three below it on a pipe.
#
# [ME:INFERRED N7 §1.3] The line carries no brush. The climbing face is taken
# 65 uu in front of the line -- a 128 uu deep volume, the common one, and the
# 1 uu the boundary trace reports outside every face -- which puts S 1 uu out
# from the line: what the cooked steps show on nearly every ladder. With that,
# the builder reproduces the cooked PawnLadderLocations of 88 of the 123
# ladders in the shipped levels; the rest have broken cooked Start/End or a
# brush that is not a box. A ladder an extractor rebuilt from its cooked steps
# (annotations._ladder_from_steps) has the steps themselves as its line, and
# comes out a step short at the bottom and three at the top.

const UU := 0.01
## StepHeight. [ME:CONFIRMED decompile script TdLadderVolume.uc]
const STEP_HEIGHT := 32.0 * UU
## -XYOffsetLadder / -XYOffsetPipe and ZOffsetPipe (ZOffsetLadder is 0).
const XY_OFFSET_LADDER := 50.0 * UU
const XY_OFFSET_PIPE := 62.0 * UU
const Z_OFFSET_PIPE := -5.0 * UU
## The builder's constants: S sits 64 uu behind the climbing face, the top
## step 96 uu under the top face, and no ladder is stepped over more than
## 10000 uu below its top. [ME:CONFIRMED decompile 0x012ab620]
const FACE_INSET := 64.0 * UU
const TOP_INSET := 96.0 * UU
const MAX_RANGE := 10000.0 * UU
## Where the climbing face is taken to be, out from the line. See the header.
const CLIMBING_FACE := 65.0 * UU

var line: InterestLine
## PawnLadderLocations (LadderSteps holds the same points).
var steps: PackedVector3Array = PackedVector3Array()

func _init(interest_line: InterestLine) -> void:
	line = interest_line
	if is_instance_valid(line):
		_build_steps()

## A ladder with no steps (shorter than its insets) offers nothing to hold:
## the original would index an empty array.
func is_valid() -> bool:
	return is_instance_valid(line) and not steps.is_empty()

## LT_Pipe.
func is_pipe() -> bool:
	return line.pipe

## WallNormal: out from the wall, the side it is climbed from.
func wall_normal() -> Vector3:
	return line.front()

## Vector(Rotation): into the wall.
func rotation_dir() -> Vector3:
	return -line.front()

## Start and End: the line's lower and upper ends.
func start() -> Vector3:
	var a: Vector3 = line.sample(0.0)["position"]
	var b: Vector3 = line.sample(line.length())["position"]
	return a if a.y <= b.y else b

func end() -> Vector3:
	var a: Vector3 = line.sample(0.0)["position"]
	var b: Vector3 = line.sample(line.length())["position"]
	return b if a.y <= b.y else a

## MoveDirection: the volume's up axis, Start to End.
func move_direction() -> Vector3:
	var d: Vector3 = end() - start()
	return d.normalized() if d.length_squared() > 1e-8 else Vector3.UP

## Center.
func center() -> Vector3:
	return (start() + end()) * 0.5

## Location.
func location() -> Vector3:
	return center()

## The step builder, 0x012ab620.
func _build_steps() -> void:
	steps.clear()
	var md: Vector3 = move_direction()
	var s: Vector3 = start() + md * STEP_HEIGHT + wall_normal() * (CLIMBING_FACE - FACE_INSET)
	var top_z: float = end().y - md.y * TOP_INSET
	var n: int = int(minf(top_z - s.y, MAX_RANGE) / STEP_HEIGHT)
	# The first step is n steps under the top, and every one up to it is taken:
	# n + 1 of them, none when the truncation lands above the top.
	var first := Vector3(s.x, top_z - float(n) * STEP_HEIGHT, s.z)
	for k in maxi(n + 1, 0):
		steps.append(first + md * STEP_HEIGHT * float(k))

## PawnLadderLocations.Length - 1: the topmost step, which IntoClimb asks for
## even on a pipe.
func top_index() -> int:
	return steps.size() - 1

## GetLastStep: the top step, three below it on a pipe, never below 0.
func get_last_step() -> int:
	var last: int = steps.size() - (4 if is_pipe() else 1)
	return last if last >= 1 else 0

## GetLadderLocation(Index): where the body is held on step Index, clamped to
## the steps there are.
func get_ladder_location(index: int) -> Vector3:
	var i: int = clampi(index, 0, steps.size() - 1)
	var xy: float = XY_OFFSET_PIPE if is_pipe() else XY_OFFSET_LADDER
	var z: float = Z_OFFSET_PIPE if is_pipe() else 0.0
	return steps[i] + move_direction() * z + wall_normal() * xy

## GetClosestStep(LocationZ): the step whose held height is nearest, the
## lowest on a tie. Every step is a candidate, a pipe's top three too.
func get_closest_step(z: float) -> int:
	var best: int = 0
	var best_d: float = absf(get_ladder_location(0).y - z)
	for i in range(1, steps.size()):
		var d: float = absf(get_ladder_location(i).y - z)
		if d < best_d:
			best_d = d
			best = i
	return best

## GetClosestStepUp: the lowest step held above `z`, else the topmost.
func get_closest_step_up(z: float) -> int:
	for i in steps.size():
		if get_ladder_location(i).y > z:
			return i
	return steps.size() - 1

## GetClosestStepDown: from the last step down, the first held below `z`,
## else 0.
func get_closest_step_down(z: float) -> int:
	for i in range(get_last_step(), -1, -1):
		if get_ladder_location(i).y < z:
			return i
	return 0
