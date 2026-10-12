class_name UE
extends RefCounted

# The one place the original's frame meets Godot's.
#
# The original is left-handed, Z up: +X forward, +Y right. This project maps
# its X to Godot X, its Y to Godot Z and its Z to Godot Y. Swapping two axes is
# a reflection, so every dot product, length and linear combination carries
# over unchanged, and a cross product turns round: the original's A x B is
# B.cross(A) here (cross()).
#
# Rotators: 65536 units to the turn. The original's yaw grows clockwise seen
# from above; a Godot body's rotation.y grows counter-clockwise. A body at
# rotation.y = t faces (-sin t, 0, -cos t), which is the original's yaw
# -(t + PI/2) under the axis map above.

const UNITS_PER_TURN := 65536
const UNITS_PER_RADIAN := 32768.0 / PI

## Rotator(Direction).Yaw: [ME:CONFIRMED decompile N3 §2.5] atan2 scaled to
## rotator units and rounded, wrapped to [-32768, 32767].
static func dir_yaw(v: Vector3) -> int:
	return normalize_axis(int(round(atan2(v.z, v.x) * UNITS_PER_RADIAN)))

## Vector(Rotator(0, Yaw, 0)): the flat unit vector a yaw points along.
static func yaw_dir(units: float) -> Vector3:
	var a: float = units / UNITS_PER_RADIAN
	return Vector3(cos(a), 0.0, sin(a))

## Vector(Rotator(Pitch, Yaw, 0)).
static func rot_dir(pitch_units: float, yaw_units: float) -> Vector3:
	var p: float = pitch_units / UNITS_PER_RADIAN
	var y: float = yaw_units / UNITS_PER_RADIAN
	return Vector3(cos(p) * cos(y), sin(p), cos(p) * sin(y))

## Rotator(Direction).Pitch.
static func dir_pitch(v: Vector3) -> int:
	return normalize_axis(int(round(atan2(v.y, Vector2(v.x, v.z).length()) * UNITS_PER_RADIAN)))

## A Godot body yaw (rotation.y) as the original's yaw, in rotator units.
static func yaw_units(godot_yaw: float) -> int:
	return normalize_axis(int(round(-(godot_yaw + PI * 0.5) * UNITS_PER_RADIAN)))

## The Godot body yaw (rotation.y) that faces the original's yaw `units`.
static func godot_yaw(units: float) -> float:
	return wrapf(-units / UNITS_PER_RADIAN - PI * 0.5, -PI, PI)

## A pitch in radians (positive up, as the camera rig keeps it) in rotator
## units, and back. Both frames pitch up positive.
static func pitch_units(radians: float) -> int:
	return normalize_axis(int(round(radians * UNITS_PER_RADIAN)))

static func pitch_radians(units: float) -> float:
	return units / UNITS_PER_RADIAN

## FRotator::NormalizeAxis: wraps to [-32768, 32767].
static func normalize_axis(units: int) -> int:
	var a: int = units & 0xffff
	return a - 0x10000 if a > 32767 else a

## The original's A x B, in Godot's axes.
static func cross(a: Vector3, b: Vector3) -> Vector3:
	return b.cross(a)
