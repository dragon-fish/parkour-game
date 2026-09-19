extends RefCounted

# Mirror's Edge post process tone curves, baked into the 1D colour correction
# texture Godot's Environment takes: per channel, Scene_MidTones as a gamma,
# then the channel's own curve, then curve A (all three).
#
# The curves are sampled Catmull-Rom through their control points. [ME:UNKNOWN]
# the original's own interpolation between points; a smooth one keeps the
# S-curves the level artists drew from turning into kinks.

const WIDTH := 256


static func texture(r: PackedVector2Array, g: PackedVector2Array, b: PackedVector2Array,
		a: PackedVector2Array, midtones: Vector3) -> ImageTexture:
	var image := Image.create(WIDTH, 1, false, Image.FORMAT_RGB8)
	var channels := [r, g, b]
	for i in WIDTH:
		var x := i / float(WIDTH - 1)
		var out := Color()
		for c in 3:
			var v := pow(x, 1.0 / maxf(midtones[c], 0.01))
			v = sample(channels[c], v)
			v = sample(a, v)
			out[c] = v
		image.set_pixel(i, 0, out)
	return ImageTexture.create_from_image(image)


## The curve through `points` at x, the identity when there are none.
static func sample(points: PackedVector2Array, x: float) -> float:
	if points.size() < 2:
		return x
	for k in range(1, points.size()):
		if x <= points[k].x:
			var p0 := points[maxi(k - 2, 0)]
			var p1 := points[k - 1]
			var p2 := points[k]
			var p3 := points[mini(k + 1, points.size() - 1)]
			var t := (x - p1.x) / maxf(p2.x - p1.x, 0.0001)
			var y := 0.5 * ((2.0 * p1.y) + (-p0.y + p2.y) * t
					+ (2.0 * p0.y - 5.0 * p1.y + 4.0 * p2.y - p3.y) * t * t
					+ (-p0.y + 3.0 * p1.y - 3.0 * p2.y + p3.y) * t * t * t)
			return clampf(y, 0.0, 1.0)
	return points[points.size() - 1].y
