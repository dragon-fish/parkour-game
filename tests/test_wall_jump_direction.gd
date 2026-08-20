extends ParkourTest

# The kick used to be sent along the wall normal alone, which made it a fixed
# sideways shove the player could not aim. Measured in the original, Faith
# leaves the wall in the direction the CAMERA faces, and the sideways
# component is small.

const CFG := preload("res://scripts/player/config/moves/wallrun_jump_config.gd")

class FakeBody extends Node3D:
	pass

func _body_facing(yaw_deg: float) -> Node3D:
	var body := FakeBody.new()
	get_tree().root.add_child(body)
	body.rotation.y = deg_to_rad(yaw_deg)
	return body

func test_the_kick_follows_the_view_when_it_already_clears_the_wall() -> void:
	var cfg: WallrunJumpConfig = CFG.new()
	# Wall on the player's left, so its normal points +X.
	var normal := Vector3(1.0, 0.0, 0.0)
	# Facing 45 degrees off the wall: -Z rotated -45 deg about Y.
	var body := _body_facing(-45.0)
	await step(1)
	var dir := WallRunMove.wall_jump_push_direction(body, normal, cfg)
	var facing: Vector3 = -body.global_transform.basis.z
	assert_almost_eq(dir.dot(facing.normalized()), 1.0, 0.001, \
		"a kick that already clears the wall did not simply follow the view")
	body.queue_free()
	await step(1)

func test_looking_into_the_wall_still_leaves_it() -> void:
	var cfg: WallrunJumpConfig = CFG.new()
	var normal := Vector3(1.0, 0.0, 0.0)
	# Facing straight INTO the wall (-X).
	var body := _body_facing(-90.0)
	await step(1)
	var dir := WallRunMove.wall_jump_push_direction(body, normal, cfg)
	assert_gt(dir.dot(normal), cfg.wall_jump_min_away - 0.001, \
		"looking into the wall produced a kick that does not leave it")
	assert_almost_eq(dir.length(), 1.0, 0.001, "the kick direction is not a unit vector")
	body.queue_free()
	await step(1)

func test_the_kick_is_not_simply_the_normal() -> void:
	# The regression itself: with the old code every one of these returned the
	# bare normal, whatever the player was looking at.
	var cfg: WallrunJumpConfig = CFG.new()
	var normal := Vector3(1.0, 0.0, 0.0)
	var body := _body_facing(-45.0)
	await step(1)
	var dir := WallRunMove.wall_jump_push_direction(body, normal, cfg)
	assert_true(dir.distance_to(normal) > 0.1, \
		"the kick is still pinned to the wall normal and cannot be aimed")
	body.queue_free()
	await step(1)
