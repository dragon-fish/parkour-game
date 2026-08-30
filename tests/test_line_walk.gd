extends ParkourTest

# The projection is the whole point of the tier: "a beam is forward/back and a
# ledge is left/right" must fall out of ONE line of code plus one angle, not
# out of two key mappings.

const TestWorld = preload("res://tests/world_fixture.gd")

var _world: Dictionary = {}
var _line: InterestLine = null

func after_each() -> void:
	if _line != null and is_instance_valid(_line):
		_line.queue_free()
	_line = null
	if not _world.is_empty():
		TestWorld.teardown(_world)
		_world = {}

func _make_line(kind: InterestLine.Kind, from: Vector3, to: Vector3) -> InterestLine:
	var line := InterestLine.new()
	line.kind = kind
	line.curve = Curve3D.new()
	line.curve.add_point(Vector3.ZERO)
	line.curve.add_point(to - from)
	line.position = from
	add_child_autofree(line)
	return line

func test_a_beam_travels_on_w_and_ignores_a_and_d() -> void:
	var cfg := BalanceConfig.new()
	var out := LineWalkMove.project_input(
		Vector2(0.0, 1.0), 0.0, deg_to_rad(cfg.body_yaw_offset_deg))
	assert_almost_eq(out.x, 1.0, 0.001, "W must drive travel along the beam")
	out = LineWalkMove.project_input(
		Vector2(1.0, 0.0), 0.0, deg_to_rad(cfg.body_yaw_offset_deg))
	assert_almost_eq(out.x, 0.0, 0.001, "D must not walk you off the beam")
	assert_almost_eq(out.y, 1.0, 0.001, "D is the correction instead")

func test_a_ledge_travels_on_a_and_d_and_ignores_w() -> void:
	var cfg := LedgeWalkConfig.new()
	var out := LineWalkMove.project_input(
		Vector2(1.0, 0.0), 0.0, deg_to_rad(cfg.body_yaw_offset_deg))
	assert_almost_eq(out.x, 1.0, 0.001, "D must shuffle along the ledge")
	out = LineWalkMove.project_input(
		Vector2(0.0, 1.0), 0.0, deg_to_rad(cfg.body_yaw_offset_deg))
	assert_almost_eq(out.x, 0.0, 0.001, "W must not walk you off the ledge")

func test_the_foot_gate_refuses_a_body_running_past_at_ground_level() -> void:
	_line = _make_line(InterestLine.Kind.LEDGE_WALK,
		Vector3(0, 3, 0), Vector3(0, 3, 4))
	var body_on_it := Vector3(0, 3, 2)
	var body_below := Vector3(0, 0, 2)
	assert_true(LineWalkMove.foot_gate_at(_line, body_on_it, 0.35))
	assert_false(LineWalkMove.foot_gate_at(_line, body_below, 0.35),
		"the reach volume alone would swallow a body running past below")
