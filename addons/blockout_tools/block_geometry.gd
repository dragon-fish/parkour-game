@tool
extends RefCounted

# The pure geometry behind the block tool, kept out of the editor plugin so it
# can be tested without an editor. Nothing here touches a node or a viewport.

## World axes, in the order face_basis() prefers them when the normal leaves a
## tie. X first is what makes a floor (normal +Y) come back as the identity
## basis, so the overwhelmingly common case draws boxes aligned to the world
## grid rather than to some arbitrary tangent.
const AXES: Array[Vector3] = [Vector3.RIGHT, Vector3.UP, Vector3.BACK]

## The thinnest a block may be. Below this a CSGBox3D is degenerate: it draws
## nothing and its two size handles land on top of each other, so there is no
## way to pull it back open.
const MIN_THICKNESS: float = 0.001

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
## grab. `height` gets the same protection but NOT the same floor -- it is
## clamped to MIN_THICKNESS, never to the grid. A new block is meant to be
## thinner than the grid it snaps to, so tying the two put a 0.1 block back up
## to 0.5 whenever the grid was coarse.
static func block_from_drag(anchor: Vector3, basis: Basis, extent: Vector2,
		height: float, step: float) -> Dictionary:
	var floor_step: float = maxf(step, MIN_THICKNESS)
	var width: float = extent.x
	if absf(width) < floor_step:
		width = floor_step if width >= 0.0 else -floor_step
	var depth: float = extent.y
	if absf(depth) < floor_step:
		depth = floor_step if depth >= 0.0 else -floor_step
	var rise: float = maxf(height, MIN_THICKNESS)
	var centre_local := Vector3(width * 0.5, rise * 0.5, depth * 0.5)
	return {
		"size": Vector3(absf(width), rise, absf(depth)),
		"transform": Transform3D(basis, anchor + basis * centre_local),
	}

## The cylinder a centre-out drag describes: the drag starts at the footprint's
## centre and reaches to its rim, so `radius` is that reach.
##
## Sits ON the surface like a block does, growing along the normal, which is
## why the origin is half a height up: a CSGCylinder3D is centred on its own
## origin and runs along its local Y.
##
## A radius under one grid step is widened to one, for the same reason a click
## with no drag still lays a whole tile.
static func cylinder_from_drag(anchor: Vector3, basis: Basis, radius: float,
		height: float, step: float) -> Dictionary:
	var reach: float = maxf(absf(radius), maxf(step, MIN_THICKNESS))
	var rise: float = maxf(height, MIN_THICKNESS)
	return {
		"radius": reach,
		"height": rise,
		"transform": Transform3D(basis, anchor + basis.y * (rise * 0.5)),
	}

## The sphere a centre-out drag describes.
##
## Centred exactly where the drag started, half of it under the surface. That
## is what dragging a centre and a radius means, and lifting it to sit on the
## surface -- which this used to do, meaning well -- put the ball somewhere
## nobody pointed at. Thickness has no meaning here, so it takes none.
static func sphere_from_drag(anchor: Vector3, basis: Basis, radius: float,
		step: float) -> Dictionary:
	return {
		"radius": maxf(absf(radius), maxf(step, MIN_THICKNESS)),
		"transform": Transform3D(basis, anchor),
	}

## Turns a world placement into one relative to the parent a node is about to
## be added under.
##
## A Node3D's `transform` is read against its parent, so handing it a world
## transform lands it wherever the parent's own chain happens to put it -- a
## solid drawn on a rotated platform ends up skewed somewhere off to the side.
## `parent_global` already carries the whole ancestor chain, so one inverse is
## the entire correction; walking up level by level is not needed and is not
## more correct.
static func local_placement(parent_global: Transform3D, world: Transform3D) -> Transform3D:
	return parent_global.affine_inverse() * world
