extends GutTest

# The original's tone curve segments as the render thread builds them from the
# stored Ms/Bs (tools/me_level/me_tone_map.gd, build_curves). The monotonic
# clamp is a behaviour of the original, quirk included: it keeps a running
# maximum of segment STARTS only, so a segment may still end lower than it
# began. [ME:CONFIRMED _local/me-re/findings/TM1.md, emulated]

const ToneMap := preload("res://tools/me_level/me_tone_map.gd")


func _flat(slope: float, offset: float) -> Array:
	var ms := PackedVector3Array()
	var bs := PackedVector3Array()
	for i in 16:
		ms.append(Vector3(slope, slope, slope))
		bs.append(Vector3(offset, offset, offset))
	return [ms, bs]


func test_an_identity_curve_stays_the_identity() -> void:
	var curve := _flat(1.0, 0.0)
	var built := ToneMap.build_curves(curve[0], curve[1], 1.0)
	for i in 16:
		assert_almost_eq(built[0][i].x, 1.0, 1e-6, "segment %d slope" % i)
		assert_almost_eq(built[1][i].x, 0.0, 1e-6, "segment %d offset" % i)


func test_contrast_is_added_to_every_slope() -> void:
	var curve := _flat(1.0, 0.0)
	var built := ToneMap.build_curves(curve[0], curve[1], 1.2)
	assert_almost_eq(built[0][3].y, 1.2, 1e-6)


func test_a_segment_wholly_below_the_ones_before_is_held_at_their_level() -> void:
	var curve := _flat(1.0, 0.0)
	# Segment 5 dropped by 10/15: it runs from -5/15 to -4/15.
	curve[1][5] = Vector3.ONE * (-10.0 / 15.0)
	var built := ToneMap.build_curves(curve[0], curve[1], 1.0)
	assert_almost_eq(built[0][5].x, 0.0, 1e-6, "held flat")
	assert_almost_eq(built[1][5].x, 4.0 / 15.0, 1e-6, "at the start of the segment before")


func test_a_segment_starting_below_but_ending_above_rises_from_the_running_maximum() -> void:
	var curve := _flat(1.0, 0.0)
	# Segment 5 starts at 3/15 and climbs to 9/15.
	curve[0][5] = Vector3.ONE * 6.0
	curve[1][5] = Vector3.ONE * (3.0 / 15.0 - 6.0 * 5.0 / 15.0)
	var built := ToneMap.build_curves(curve[0], curve[1], 1.0)
	var y0: float = 5.0 / 15.0 * built[0][5].x + built[1][5].x
	var y1: float = 6.0 / 15.0 * built[0][5].x + built[1][5].x
	assert_almost_eq(y0, 4.0 / 15.0, 1e-5, "starts at the running maximum")
	assert_almost_eq(y1, 9.0 / 15.0, 1e-5, "and still ends where it ended")


const ToneSettings := preload("res://tools/me_level/me_tone_settings.gd")


func _settings(slope: float, midtone: float, high: float) -> Resource:
	var out: Resource = ToneSettings.new()
	var curve := _flat(slope, 0.1 * slope)
	out.curve_m = curve[0]
	out.curve_b = curve[1]
	out.midtones = Vector3.ONE * midtone
	out.exposure_high = high
	return out


## The view's settings are a copy of the world's, blended into a volume's and
## back. The world's own values must come through that untouched: a copy that
## shared the world's curves rewrote them with the volume's, and the street
## stayed graded as the corridor after the player came back out.
func test_a_round_trip_through_a_volume_returns_exactly_to_the_world_settings() -> void:
	var world := _settings(0.5, 1.0, 1.5)
	var volume := _settings(1.0, 0.95, 1.65)
	var view: Resource = world.duplicate()
	for i in 30:
		view.blend_toward(volume, 0.2)
	view.blend_toward(volume, 1.0)
	assert_eq(view.curve_m[3], volume.curve_m[3], "inside, the volume's curves")
	assert_eq(world.curve_m[3], Vector3.ONE * 0.5, "the world's own curves untouched by the blend in")
	assert_eq(world.curve_b[3], Vector3.ONE * 0.05)
	for i in 30:
		view.blend_toward(world, 0.2)
	view.blend_toward(world, 1.0)
	for i in 16:
		assert_eq(view.curve_m[i], world.curve_m[i], "segment %d slope back to the world's" % i)
		assert_eq(view.curve_b[i], world.curve_b[i], "segment %d offset back to the world's" % i)
	assert_eq(view.midtones, world.midtones)
	assert_eq(view.exposure_high, world.exposure_high)
	assert_eq(volume.curve_m[3], Vector3.ONE, "nor the volume's by the blend out")
