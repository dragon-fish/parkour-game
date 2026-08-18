class_name TestWallrunJump
extends TestCase

# The 4.3x skill gradient, tested as pure arithmetic. 04 §4.4 is explicit
# that the interpolation input is not named in the data; the reading here --
# how squarely the view faces the wall at the moment of the jump -- comes
# from the community's own repeated instruction to "face the wall you are
# running on before jumping", which is the behaviour the gradient has to
# reproduce.

func _cfg() -> WallrunJumpConfig:
	return MovementConfig.new().wallrun_jump

func test_the_confirmed_endpoints_are_in_place() -> void:
	var cfg := _cfg()
	check_approx(cfg.wall_running_push_away_speed_noob, 1.2, 0.0001, "Noob endpoint is wrong")
	check_approx(cfg.wall_running_push_away_speed_pro_add, 4.0, 0.0001, "ProAdd endpoint is wrong")
	check_approx(cfg.wall_running_jump_off_z_height_forward, 1.0, 0.0001, "base rise height is wrong")
	check_approx(cfg.wall_running_jump_off_z_height_max_add_turned, 0.6, 0.0001, "rise bonus is wrong")

func test_the_worst_execution_gets_the_noob_push() -> void:
	# Looking straight AWAY from the wall.
	var normal := Vector3(1.0, 0.0, 0.0)
	var push := WallRunMove.wall_jump_push_away(normal, normal, _cfg())
	check_approx(push, 1.2, 0.001, "looking away from the wall did not give the Noob push")

func test_the_best_execution_gets_the_full_gradient() -> void:
	# Looking straight INTO the wall.
	var normal := Vector3(1.0, 0.0, 0.0)
	var push := WallRunMove.wall_jump_push_away(-normal, normal, _cfg())
	check_approx(push, 5.2, 0.001, "facing the wall did not give the full push")

func test_the_gradient_spans_more_than_four_times() -> void:
	# 10.1 mechanic 4 states the criterion as a ratio: a key move must have a
	# 3x-or-better spread between worst and best execution, or new players and
	# experts are playing the same game.
	var normal := Vector3(1.0, 0.0, 0.0)
	var worst := WallRunMove.wall_jump_push_away(normal, normal, _cfg())
	var best := WallRunMove.wall_jump_push_away(-normal, normal, _cfg())
	check_greater(best / worst, 4.0, "the gradient is narrower than 4x")

func test_the_gradient_is_continuous_not_stepped() -> void:
	var normal := Vector3(1.0, 0.0, 0.0)
	var previous := WallRunMove.wall_jump_push_away(normal, normal, _cfg())
	for i in range(1, 11):
		var angle: float = PI * float(i) / 10.0
		var look := normal.rotated(Vector3.UP, angle)
		var push := WallRunMove.wall_jump_push_away(look, normal, _cfg())
		check_greater(push + 0.0001, previous, "the gradient went backwards at step %d" % i)
		previous = push

func test_the_rise_is_a_height_converted_to_a_speed() -> void:
	# JumpOffZHeight is a HEIGHT in the original, not a velocity -- 1.0 m at
	# worst, 1.6 m at best, which under gravity 8.0 is 4.0 to 5.06 m/s. The
	# old constant 6.5 m/s was a 2.64 m rise, well above either.
	var pawn := PawnConfig.new()
	var normal := Vector3(1.0, 0.0, 0.0)
	var worst := WallRunMove.wall_jump_rise_velocity(normal, normal, _cfg(), pawn)
	var best := WallRunMove.wall_jump_rise_velocity(-normal, normal, _cfg(), pawn)
	check_approx(worst, sqrt(2.0 * 8.0 * 1.0), 0.001, "worst-case rise is not 1.0 m worth")
	check_approx(best, sqrt(2.0 * 8.0 * 1.6), 0.001, "best-case rise is not 1.6 m worth")
