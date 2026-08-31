@tool
extends RefCounted

# The pure geometry behind the block tool, kept out of the editor plugin so it
# can be tested without an editor. Nothing here touches a node or a viewport.

## World axes, in the order face_basis() prefers them when the normal leaves a
## tie. X first is what makes a floor (normal +Y) come back as the identity
## basis, so the overwhelmingly common case draws boxes aligned to the world
## grid rather than to some arbitrary tangent.
const AXES: Array[Vector3] = [Vector3.RIGHT, Vector3.UP, Vector3.BACK]

## An orthonormal basis whose Y column is `normal`, so a box built in it lies
## flush against the surface that normal came from and grows away from it.
##
## Right-handed, because Godot is: z = x.cross(y), NOT y.cross(x). Getting that
## backwards mirrors every box built on a wall and the error is invisible until
## something asymmetric is drawn.
static func face_basis(normal: Vector3) -> Basis:
	var up: Vector3 = normal.normalized()
	if up.is_zero_approx():
		return Basis.IDENTITY
	var reference: Vector3 = AXES[0]
	var weakest: float = INF
	for axis in AXES:
		var alignment: float = absf(axis.dot(up))
		if alignment < weakest:
			weakest = alignment
			reference = axis
	# Gram-Schmidt: take the reference axis and remove whatever of it points
	# along the normal.
	var x: Vector3 = (reference - up * reference.dot(up)).normalized()
	if x.is_zero_approx():
		return Basis.IDENTITY
	return Basis(x, up, x.cross(up))

## Rounds to the nearest multiple of `step`. A step of zero means no snapping,
## which is a legitimate setting, not an error.
static func snap(value: float, step: float) -> float:
	if step <= 0.0:
		return value
	return roundf(value / step) * step

static func snap_vector(value: Vector3, step: float) -> Vector3:
	return Vector3(snap(value.x, step), snap(value.y, step), snap(value.z, step))

## The box a drag describes.
##
## `anchor` is the corner the drag started from, already on the surface.
## `basis` comes from face_basis(). `extent` is the drag's reach from the
## anchor in that basis's X and Z, and may be negative in either. `height` is
## how far the box rises along the normal.
##
## Returns {"size": Vector3, "transform": Transform3D}.
##
## A drag shorter than one step in either direction is widened to one step
## rather than rejected: a plain click is a deliberate way to lay a single
## tile, and a zero-width box is a degenerate CSG shape with no handles to
## grab. For the same reason `height` is never allowed to reach zero here --
## the caller's job is to pick how thin, not whether.
static func block_from_drag(anchor: Vector3, basis: Basis, extent: Vector2,
		height: float, step: float) -> Dictionary:
	var floor_step: float = maxf(step, 0.001)
	var width: float = extent.x
	if absf(width) < floor_step:
		width = floor_step if width >= 0.0 else -floor_step
	var depth: float = extent.y
	if absf(depth) < floor_step:
		depth = floor_step if depth >= 0.0 else -floor_step
	var rise: float = maxf(height, floor_step)
	var centre_local := Vector3(width * 0.5, rise * 0.5, depth * 0.5)
	return {
		"size": Vector3(absf(width), rise, absf(depth)),
		"transform": Transform3D(basis, anchor + basis * centre_local),
	}
