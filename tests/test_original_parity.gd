extends ParkourTest

# A playtest against the original: each case reproduces a scenario that was
# MEASURED in Mirror's Edge (2008) -- frame by frame off the Tweaks debug HUD,
# or by the owner in game -- and compares what the port does with what the
# original did. The comparison table and the analysis of every mismatch are in
# docs/mirrors-edge-deep-research/15-原版逻辑反编译.md §15.13.
#
# These are fidelity checks, not tuning tests: the reference value is the
# original's, never a number of this project's. A failure means the port no
# longer reproduces the original. DO NOT widen a tolerance or change a value
# to make one pass; find which of the port, the reproduction or the
# measurement is wrong first. The tolerances are the measurement's own:
# - the HUD shows km/h to 0.01 and metres to 0.01;
# - the original's frames are 58-62 fps with jitter, the port ticks at 60 Hz:
#   one frame of timing is the floor of every timed comparison;
# - an input the recording does not show (when a key went down) is
#   reproduced from what the HUD does show, which costs a frame more.
#
# Not here (see §15.13): the measurements whose conditions cannot be read
# back off the recordings, and those that do not match.

const TestWorld = preload("res://tests/world_fixture.gd")
const KMH := 3.6
const FRAME := 1.0 / 60.0

var _world: Dictionary = {}
var _extra: Array[Node] = []

func after_each() -> void:
	await _clear()

func _clear() -> void:
	for node in _extra:
		if is_instance_valid(node):
			node.queue_free()
	_extra.clear()
	if not _world.is_empty():
		TestWorld.teardown(_world)
		_world = {}
	await step(1)

## A body standing on the 200 m floor (top at y = 0) at `at`, facing `yaw`.
func _player(at: Vector3 = Vector3.ZERO, yaw: float = 0.0) -> Player:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	var player: Player = _world["player"]
	player.global_position = at + Vector3(0.0, 0.95, 0.0)
	_face(player, yaw)
	await step(20)
	return player

func _face(player: Player, yaw: float) -> void:
	player.rotation.y = yaw
	player.pawn_yaw = yaw

func _in() -> ScriptedInputSource:
	return _world["input"]

func _kmh(player: Player) -> float:
	return player.horizontal_speed() * KMH

func _feet(player: Player) -> float:
	return player.global_position.y - player.collision_half_height()

func _box(size: Vector3, center: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	# Placed before it enters the tree: a body that spends a frame at the
	# origin is a floor the walking physics may take for its base.
	body.position = center
	get_tree().root.add_child(body)
	_extra.append(body)
	return body

## Sprints (W held) until the speed reaches `kmh`.
func _run_to(player: Player, kmh: float, limit: int = 900) -> void:
	_in().hold_move(0.0, 1.0)
	for i in limit:
		if _kmh(player) >= kmh:
			return
		await step(1)

func _states(chain: Array) -> Array:
	return chain.map(func(entry: Dictionary) -> StringName: return entry["state"])

# --- the ground --------------------------------------------------------------

## [ME:CONFIRMED 02 §2.1] The sprint from rest, W held, timed from the first
## frame that moves. The median of the seven standing starts in 转向损速测试
## and 多角度进入墙跑测试 (they agree to 0.1 km/h), and the owner's 712.5 /
## 719.2 uu/s at 7 / 13 s. One frame of the original's jitter is 0.07 km/h
## past 1 s; 0.3 covers the frame the start is placed on.
func test_the_sprint_from_rest_climbs_as_the_originals() -> void:
	var player: Player = await _player(Vector3(0.0, 0.0, 95.0))
	var want := {1.0: 18.95, 2.0: 21.62, 3.0: 23.32, 3.5: 24.02, 5.0: 25.16, 7.0: 25.65, 13.0: 25.89}
	_in().hold_move(0.0, 1.0)
	var t := -1.0
	for i in 60 * 14:
		await step(1)
		if t < 0.0 and player.horizontal_speed() > 0.0:
			t = 0.0
		elif t >= 0.0:
			t += FRAME
		for mark in want.keys():
			if absf(t - mark) < FRAME * 0.5:
				assert_almost_eq(_kmh(player), want[mark], 0.3, "the speed %.1f s into the sprint" % mark)

## [ME:CONFIRMED 02 §2.4] The flat jump: apex 1.24 m, airtime 0.775-0.800 s
## (22 jumps, last frame on the ground to first frame back), and the take-off
## adds 3.60 km/h at full speed, 3.77 km/h at 15.8 km/h (sample_run).
func test_the_flat_jump_is_the_originals() -> void:
	for c in [[25.92, 3.60], [15.78, 3.77]]:
		var player: Player = await _player(Vector3(0.0, 0.0, 95.0))
		await _run_to(player, c[0])
		player.velocity *= float(c[0]) / _kmh(player)
		var before := _kmh(player)
		var y0: float = player.global_position.y
		_in().press_jump()
		await step(1)
		_in().release_jump()
		var gain: float = _kmh(player) - before
		await step(1)
		var top := y0
		var frames := 2
		while player.physics != Move.PHYS_WALKING and frames < 120:
			await step(1)
			frames += 1
			top = maxf(top, player.global_position.y)
		assert_almost_eq(gain, c[1], 0.06, "the take-off's gain at %.2f km/h" % c[0])
		assert_almost_eq(top - y0, 1.24, 0.01, "the apex")
		assert_almost_eq(frames * FRAME, 0.788, 0.025, "the airtime")
		await _clear()

## [ME:CONFIRMED 03 §3.3, 05 §5.1] The five recorded slides: entry speed,
## duration until it hands over, last slide speed. One frame of duration;
## the exit speed is the 250 uu/s threshold crossed within a frame.
func test_a_slide_lasts_and_ends_as_the_originals() -> void:
	for c in [[25.78, 1.33, 8.92], [22.18, 1.15, 8.95], [25.74, 1.32, 8.99], [21.78, 1.13, 8.90], [25.18, 1.32, 8.90]]:
		var player: Player = await _player(Vector3(0.0, 0.0, 95.0))
		await _run_to(player, c[0])
		player.velocity *= float(c[0]) / _kmh(player)
		_in().press_crouch()
		await step(1)
		assert_eq(player.move_manager.current_name, Move.SLIDE, "test setup: no slide")
		var frames := 1
		var last := _kmh(player)
		while player.move_manager.current_name == Move.SLIDE and frames < 400:
			last = _kmh(player)
			await step(1)
			frames += 1
		assert_almost_eq(frames * FRAME, c[1], 2.0 * FRAME, "the slide from %.2f km/h" % c[0])
		assert_almost_eq(last, c[2], 0.15, "the last slide frame's speed")
		await _clear()

## [ME:CONFIRMED 03 §3.2] Q at full speed: the four recorded 180Turns, sampled
## from the first 180Turn frame (frames of 转向损速测试 from 14260, 14926,
## 15624). The state lasts the 1.033 s clip and hands over near 19.2 km/h.
## 0.6 km/h is a frame of the 3.3 /s braking and of the re-acceleration.
func test_a_q_turn_brakes_and_recovers_as_the_originals() -> void:
	var player: Player = await _player(Vector3(0.0, 0.0, 95.0))
	await _run_to(player, 25.7)
	var want := {0.05: 21.7, 0.117: 17.0, 0.217: 12.4, 0.283: 9.8, 0.517: 6.5, 0.617: 10.4, 0.717: 13.9, 0.817: 15.8, 1.017: 18.8}
	_in().press_turn()
	var t := 0.0
	var vmin := 99.0
	var ended := -1.0
	for i in 70:
		await step(1)
		t += FRAME
		vmin = minf(vmin, _kmh(player))
		if ended < 0.0 and player.move_manager.current_name != Move.TURN_180:
			ended = t
			assert_almost_eq(_kmh(player), 19.2, 0.5, "the speed the turn hands over at")
		for mark in want.keys():
			if absf(t - mark) < FRAME * 0.5:
				assert_almost_eq(_kmh(player), want[mark], 0.6, "the speed %.3f s into the turn" % mark)
	assert_lt(vmin, 1.5, "the turn did not come to (nearly) a stop")
	assert_almost_eq(ended, 1.05, 0.03, "the turn's length")

## [ME:CONFIRMED 03 §3.2] The 17 clean ground turns of 转向损速测试 replayed
## frame for frame -- the recorded yaw as this tick's mouse input, W held,
## from the recorded entry speed: the lowest speed and the speed 0.5 s after.
## The turn penalty and the sprint's bending of the velocity are both in the
## loss. 1.0 / 0.6 km/h: the recording's 58-61 fps against the port's 60.
func test_the_recorded_ground_turns_lose_what_the_original_lost() -> void:
	for trace in OriginalParityData.GROUND_TURNS:
		var yaw: Array = trace["yaw"]
		var kmh: Array = trace["kmh"]
		var player: Player = await _player()
		await _run_to(player, kmh[0])
		var sens: float = player.config.camera.mouse_sensitivity
		var vmin := 99.0
		for i in range(1, yaw.size()):
			_in().state.look = Vector2(-deg_to_rad(float(yaw[i]) - float(yaw[i - 1])) / sens, 0.0)
			await step(1)
			vmin = minf(vmin, _kmh(player))
		_in().state.look = Vector2.ZERO
		var label := "the turn at frame %d (%.0f deg)" % [trace["frame"], yaw[-1]]
		assert_almost_eq(vmin, float(kmh.min()), 1.0, "%s: lowest speed" % label)
		assert_almost_eq(_kmh(player), float(kmh[-1]), 0.6, "%s: speed after" % label)
		await _clear()

## [ME:CONFIRMED 05 §5.6] Walking a beam: 720 x 0.34 = 8.81 km/h.
func test_a_balance_beam_is_walked_at_the_originals_speed() -> void:
	var player: Player = await _player()
	var line := InterestLine.new()
	line.kind = InterestLine.Kind.BALANCE
	var curve := Curve3D.new()
	curve.add_point(Vector3(0.0, 0.0, 2.0))
	curve.add_point(Vector3(0.0, 0.0, -30.0))
	line.curve = curve
	get_tree().root.add_child(line)
	_extra.append(line)
	await step(1)
	var balance: BalanceMove = player.move_manager.move_for(Move.BALANCE)
	balance.volume = line
	player.move_manager.set_move(Move.BALANCE)
	_in().hold_move(0.0, 1.0)
	await step(60)
	assert_eq(player.move_manager.current_name, Move.BALANCE, "test setup: off the beam")
	assert_almost_eq(_kmh(player), 8.81, 0.02, "the beam's walking speed")

## [ME:CONFIRMED 05 §5.2] A jump straight up and a crouch at the apex does
## nothing; with horizontal speed it is a coil.
func test_a_coil_needs_horizontal_speed_as_in_the_original() -> void:
	for moving in [false, true]:
		var player: Player = await _player()
		if moving:
			await _run_to(player, 8.0)
		_in().press_jump()
		await step(1)
		_in().release_jump()
		await step(22)
		_in().press_crouch()
		await step(2)
		_in().release_crouch()
		if moving:
			assert_eq(player.move_manager.current_name, Move.COIL, "a running jump did not coil")
		else:
			assert_ne(player.move_manager.current_name, Move.COIL, "a standing jump coiled")
		await _clear()

# --- falls and landings ------------------------------------------------------

## Runs off a platform `height` m up, W held, at `kmh` (the speed is held at
## that until the edge). Returns what the landing did.
func _walk_off(height: float, kmh: float, roll: bool = false) -> Dictionary:
	var player: Player = await _player(Vector3(0.0, height, 95.0))
	_box(Vector3(6.0, height, 30.0), Vector3(0.0, height * 0.5, 85.0))
	player.global_position = Vector3(0.0, height + 0.95, 99.0)
	await step(10)
	var hp0: float = player.health.hp
	_in().hold_move(0.0, 1.0)
	var out := {"states": [], "last_air": -1.0, "land": -1.0, "landing_s": 0.0, "roll_s": 0.0, "after": []}
	var t := 0.0
	var land_t := -1.0
	var pressed := false
	for i in 900:
		if player.physics == Move.PHYS_WALKING and land_t < 0.0 and _kmh(player) > kmh:
			player.velocity *= kmh / _kmh(player)
		if roll and not pressed and player.physics == Move.PHYS_FALLING and player.velocity.y < 0.0 \
				and _feet(player) < 0.7:
			_in().press_crouch()
			pressed = true
		elif pressed:
			_in().release_crouch()
		var air: float = _kmh(player) if player.physics == Move.PHYS_FALLING else -1.0
		await step(1)
		t += FRAME
		var name: StringName = player.move_manager.current_name
		if out["states"].is_empty() or out["states"][-1] != name:
			out["states"].append(name)
		if name == Move.LANDING:
			out["landing_s"] += FRAME
		if name == Move.SKILL_ROLL:
			out["roll_s"] += FRAME
		if land_t < 0.0 and air >= 0.0 and player.physics != Move.PHYS_FALLING:
			out["last_air"] = air
			out["land"] = _kmh(player)
			land_t = t
		if name == Move.FALL_UNCONTROLLED:
			break
		if land_t >= 0.0:
			out["after"].append(_kmh(player))
			if t - land_t > 3.5:
				break
	out["damage"] = hp0 - player.health.hp
	return out

## [ME:CONFIRMED 03 §3.1] 4.95 m walked off at 19.84 km/h, W held
## (4.95落差测试 frames 374-600): the fall gains speed to 22.98 km/h, and the
## landing costs nothing -- no hold, no damage, the run goes on rising.
## (The touchdown frame's jump is the forced maximum acceleration for the part
## of the frame after the touchdown, which no recording reproduces: not
## compared.)
func test_a_4_95_m_drop_costs_nothing() -> void:
	var r: Dictionary = await _walk_off(4.95, 19.84)
	assert_almost_eq(float(r["last_air"]), 22.98, 0.2, "the speed the fall gained")
	assert_almost_eq(float(r["landing_s"]), 0.0, 0.001, "the landing held the body")
	assert_eq(float(r["damage"]), 0.0, "the landing hurt")
	var after: Array = r["after"]
	assert_gt(float(after[-1]), float(r["last_air"]), "the run did not go on rising after the landing")

## [ME:CONFIRMED 03 §3.1, 13 §13.1] Past HardLandingHeight: 5.69 m is a hard
## Landing, 7 m and 9 m too -- speed to zero, held ~2.0 s
## (高处摔伤 frame 684), -15 HP whatever the height. Past 10 m the fall is
## lost in the air.
func test_the_hard_landings_are_the_originals() -> void:
	for height in [5.69, 7.0, 9.0]:
		var r: Dictionary = await _walk_off(height, 25.0)
		assert_true(r["states"].has(Move.LANDING), "%.2f m: no Landing in %s" % [height, r["states"]])
		assert_almost_eq(float(r["land"]), 0.0, 0.01, "%.2f m: the landing kept speed" % height)
		assert_almost_eq(float(r["landing_s"]), 2.0, 0.1, "%.2f m: the hold" % height)
		assert_almost_eq(float(r["damage"]), 15.0, 0.001, "%.2f m: the damage" % height)
		await _clear()
	var lost: Dictionary = await _walk_off(10.5, 25.0)
	assert_true(lost["states"].has(Move.FALL_UNCONTROLLED), "a 10.5 m fall was not lost: %s" % [lost["states"]])

## [ME:CONFIRMED 03 §3.1] A 7.5 m drop rolled, W held: no damage, the roll
## lasts its 1.27 s clip, and the run climbs back from ~11 km/h the way the
## original's does (高处摔伤 frames 7894-10362, W held: 16.8 / 19.3 / 20.7 /
## 21.4 km/h at 0.4 / 0.8 / 1.2 / 1.6 s after the roll).
func test_a_rolled_landing_recovers_as_the_originals() -> void:
	var r: Dictionary = await _walk_off(7.5, 25.0, true)
	assert_true(r["states"].has(Move.SKILL_ROLL), "no roll in %s" % [r["states"]])
	assert_eq(float(r["damage"]), 0.0, "the roll hurt")
	assert_almost_eq(float(r["roll_s"]), 1.27, 0.05, "the roll's length")
	var after: Array = r["after"]
	var exit_index := int(round(float(r["roll_s"]) / FRAME))
	for c in [[0.4, 16.8], [0.8, 19.3], [1.2, 20.7], [1.6, 21.4]]:
		assert_almost_eq(float(after[exit_index + int(round(c[0] / FRAME))]), c[1], 0.5,
			"the speed %.1f s after the roll" % c[0])

## [ME:CONFIRMED 04 §4.5] The dodge: from a standstill exactly 21.60 km/h and
## a 0.28 m hop; from a sideways shuffle 0.3 of it carried (dodge2: 5.91 /
## 8.42 / 9.89 km/h in, 23.37 / 24.13 / 24.42 out); the state hands to Falling
## after 0.30-0.32 s; out of a run turned 41 degrees by W+D, 22.08 in, 26.51
## out. 0.2 km/h is the OCR's frame of the entry speed.
func test_the_dodges_are_the_originals() -> void:
	for c in [[0.0, 21.60], [5.91, 23.37], [8.42, 24.13], [9.89, 24.42]]:
		var player: Player = await _player()
		var right: Vector3 = player.facing().cross(Vector3.UP)
		player.velocity = right * float(c[0]) / KMH
		_in().hold_move(1.0, 0.0)
		var y0: float = player.global_position.y
		_in().press_jump()
		await step(1)
		_in().release_jump()
		assert_eq(player.move_manager.current_name, Move.DODGE_JUMP, "test setup: no dodge")
		assert_almost_eq(_kmh(player), c[1], 0.2 if c[0] > 0.0 else 0.02, "the dodge from %.2f km/h" % c[0])
		var top := y0
		var frames := 1
		while player.move_manager.current_name == Move.DODGE_JUMP and frames < 60:
			await step(1)
			frames += 1
			top = maxf(top, player.global_position.y)
		assert_almost_eq(top - y0, 0.28, 0.01, "the dodge's hop")
		assert_almost_eq((frames - 1) * FRAME, 0.31, 0.03, "the dodge's length")
		await _clear()
	var runner: Player = await _player(Vector3(0.0, 0.0, 90.0))
	await _run_to(runner, 25.5)
	_in().hold_move(1.0, 1.0)
	for i in 6:
		await step(1)
	var entry := Vector3(runner.velocity.x, 0.0, runner.velocity.z)
	assert_almost_eq(rad_to_deg(absf(runner.facing().signed_angle_to(entry, Vector3.UP))), 41.0, 3.0,
		"test setup: the run was not turned as the recorded one")
	runner.velocity *= 22.08 / _kmh(runner)
	_in().press_jump()
	await step(1)
	assert_almost_eq(_kmh(runner), 26.51, 0.3, "the dodge out of a run")

# --- walls -------------------------------------------------------------------

## A runway 3 m up beside a tall wall on its LEFT (face at x = -1.2) that runs
## on past the runway's end over a void; the body at `start` facing
## `heading_deg` toward the wall.
func _wall_course(start: Vector3, heading_deg: float) -> Player:
	var player: Player = await _player()
	_box(Vector3(30.0, 3.0, 80.0), Vector3(13.8, 1.5, 42.0))
	_box(Vector3(1.0, 14.0, 160.0), Vector3(-1.7, 7.0, -10.0))
	(_world["floor"] as Node3D).global_position = Vector3(0.0, -30.5, 0.0)
	player.global_position = start + Vector3(0.0, 0.95, 0.0)
	_face(player, deg_to_rad(heading_deg))
	await step(10)
	return player

## [ME:CONFIRMED 04 §4.1] The wall run's arc over a void (墙跑自动离开 frames
## 1542 and 3540: on the wall about 0.9 m up the jump, 25.5 km/h): the top
## 1.60-1.65 m over the take-off about 0.42 s after contact, Falling 1.45 s
## after it, 95 % of the speed kept per second. The pawn turns along the wall
## in 0.40 s. One frame on each time; the HUD's 0.01 m on the heights.
func test_a_wall_run_arcs_as_the_originals() -> void:
	var heading := 20.0
	var dir := Vector3(-sin(deg_to_rad(heading)), 0.0, -cos(deg_to_rad(heading)))
	var at_jump := Vector3(-0.15, 3.0, 2.0)
	var player: Player = await _wall_course(at_jump - dir * (76.0 / absf(dir.z)), heading)
	await _run_to(player, 21.5)
	while player.global_position.z > 2.0:
		player.velocity *= 21.5 / _kmh(player)
		await step(1)
	var take_y: float = player.global_position.y
	_in().press_jump()
	var attach := -1.0
	var attach_h := 0.0
	var attach_kmh := 0.0
	var apex := -1.0
	var apex_t := 0.0
	var aligned := -1.0
	var t := 0.0
	for i in 200:
		await step(1)
		t += FRAME
		var name: StringName = player.move_manager.current_name
		var h: float = player.global_position.y - take_y
		if attach < 0.0:
			if name == Move.WALL_RUN:
				attach = t
				attach_h = h
				attach_kmh = _kmh(player)
			continue
		if aligned < 0.0 and absf(wrapf(player.pawn_yaw, -PI, PI)) < 0.001:
			aligned = t - attach
		if name == Move.WALL_RUN:
			if h > apex:
				apex = h
				apex_t = t - attach
			continue
		assert_almost_eq(attach_h, 0.92, 0.12, "test setup: the run did not start where the recorded ones did")
		assert_almost_eq(apex, 1.62, 0.05, "the run's top over the take-off")
		assert_almost_eq(apex_t, 0.42, 0.05, "when the run tops out")
		assert_almost_eq(t - attach, 1.45, 2.0 * FRAME, "when the run lets go")
		assert_almost_eq(pow(_kmh(player) / attach_kmh, 1.0 / (t - attach)), 0.95, 0.01,
			"the speed the run keeps per second")
		assert_almost_eq(aligned, 0.40, 2.0 * FRAME, "the pawn's turn along the wall")
		return
	fail_test("the wall run never let go")

## [ME:CONFIRMED 04 §4.1] One wall, run at from several angles to its plane
## (多角度进入墙跑测试): up to 55.6 degrees it is a wall run, from 59.5 a
## wall climb.
func test_the_angle_to_the_wall_picks_run_or_climb_as_in_the_original() -> void:
	for c in [[45.0, Move.WALL_RUN], [54.0, Move.WALL_RUN], [56.0, Move.WALL_RUN], [60.0, Move.WALL_CLIMB], [66.0, Move.WALL_CLIMB]]:
		var player: Player = await _player()
		_box(Vector3(40.0, 8.0, 1.0), Vector3(0.0, 4.0, -0.5))
		var yaw := deg_to_rad(90.0 - float(c[0]))
		player.global_position = Vector3(sin(yaw), 0.0, cos(yaw)) * 12.0 + Vector3(0.0, 0.95, 0.3)
		_face(player, yaw)
		await step(5)
		_in().hold_move(0.0, 1.0)
		var jumped := false
		var got: StringName = &""
		for i in 400:
			if not jumped and player.global_position.z < 1.6:
				_in().press_jump()
				jumped = true
			await step(1)
			_in().release_jump()
			var name: StringName = player.move_manager.current_name
			if jumped and (name == Move.WALL_RUN or name == Move.WALL_CLIMB):
				got = name
				break
		assert_eq(got, c[1], "%.0f degrees to the wall" % c[0])
		await _clear()

## Runs along the wall pressed against it, the view `theta_deg` into it, at
## `kmh` on the last walking frame; then a jump and, the frame after, a
## second one. Returns [speed on the wall, speed off it].
func _pressed_wall_jump(theta_deg: float, kmh: float) -> Array:
	var player: Player = await _wall_course(Vector3(0.0, 3.0, 66.0), theta_deg)
	player.global_position.x = -1.2 + player.default_collision_radius() + 0.02
	await step(2)
	_in().hold_move(0.0, 1.0)
	await step(300)
	player.velocity = Vector3(0.0, 0.0, -kmh / KMH)
	await step(1)
	_in().press_jump()
	await step(1)
	_in().release_jump()
	assert_eq(player.move_manager.current_name, Move.WALL_RUN, "test setup: the jump did not take the wall")
	var on := _kmh(player)
	_in().press_jump()
	await step(1)
	_in().release_jump()
	assert_eq(player.move_manager.current_name, Move.WALLRUN_JUMP, "test setup: no wall run jump")
	var off := _kmh(player)
	await step(5)
	assert_almost_eq(_kmh(player), off, 0.05, "the wall run jump did not leave the wall")
	return [on, off]

## [ME:CONFIRMED 04 §4.4] The "instant" wall jumps of 连续瞬间蹬墙跳(-2): run
## along a wall pressed against it, the view at the recorded angle into it,
## jump, and jump again the next frame (the scroll wheel). The jump off keeps
## the along-wall speed times 0.1 + 0.9 (1 - p) with p = normal . view < 0:
## the faster the view looks into the wall, the more is gained. [walk speed
## at the take-off, view angle, speed off the wall]. 0.8 km/h: the take-off
## frame's speed is read a frame early.
func test_the_instant_wall_jumps_gain_what_the_originals_did() -> void:
	for c in [[13.97, 21.36, 29.86], [12.85, 24.6, 33.82], [15.5, 24.6, 34.33], [13.34, 20.12, 28.19],
			[10.0, 25.56, 32.69], [7.75, 25.77, 32.45], [15.72, 23.93, 33.58], [16.3, 24.9, 34.98],
			[14.96, 20.01, 28.56], [17.85, 25.09, 35.78], [17.38, 25.45, 35.68], [14.46, 24.58, 33.42],
			[15.56, 25.01, 34.84]]:
		var r: Array = await _pressed_wall_jump(c[0], c[1])
		assert_almost_eq(float(r[1]), c[2], 0.8, "the jump off a wall run %.2f degrees into the wall" % c[0])
		await _clear()

## [ME:DERIVED 连续瞬间蹬墙跳 2258, 2892] Two more instant wall jumps, whose
## HUD speed (38.98 / 38.70 km/h) the body does not travel at. Off the wall
## it moves 32.90 / 32.77 km/h by the recorded X and Y over 12 frames, where
## the other jumps of the recording travel at a median 0.968 of their HUD
## speed (the recording's time base; the Falling stretch 2102-2114 gives the
## same): 33.99 / 33.85 km/h. physFalling rebuilds Velocity from the
## displacement every frame unless root motion or bJustTeleported skips it,
## so the HUD's extra 5 km/h is a velocity the rebuild never saw
## [ME:UNKNOWN which]; jump 2154 shows the same for three frames (38.58)
## before reading its travel (33.57). The view angle is the HUD's: the body
## drifts off the wall at 0.3 / 0.4 m/s, the normal term 120 + 400 p of
## p = -0.22 / -0.20 (13 / 11 degrees), where the 25 degrees the HUD speed
## would need pushes into the wall. [view angle, walk speed, travel off the
## wall]; 0.8 km/h as above.
func test_the_instant_wall_jumps_whose_hud_overstates_travel_the_originals_speed() -> void:
	for c in [[14.46, 24.64, 33.99], [12.30, 25.67, 33.85]]:
		var r: Array = await _pressed_wall_jump(c[0], c[1])
		assert_almost_eq(float(r[1]), c[2], 0.8, "the jump off a wall run %.2f degrees into the wall" % c[0])
		await _clear()

## [ME:CONFIRMED 04 §4.4] The late wall jumps of 蹬墙跳_入墙后不转动方向 and
## 墙跑接近末端面视前方蹬墙: on the wall `frames` frames, then jump; the
## gain is small because ConstrainAxis has pulled the view back to the wall
## by then. This is the "pressing early gains more" of 04 §4.4: the formula
## has no time in it, the view does. [view angle at contact, run-up km/h,
## frames on the wall, gain]. 0.45 km/h: the speed the jump is read at
## includes a few air frames.
func test_the_late_wall_jumps_gain_what_the_originals_did() -> void:
	for c in [[13.3, 20.46, 29, 1.37], [10.2, 19.4, 34, 1.31], [11.9, 18.21, 41, 1.32],
			[15.9, 19.32, 37, 1.54], [11.5, 21.48, 39, 0.72], [8.75, 22.29, 50, 1.02]]:
		var theta: float = c[0]
		var dir := Vector3(-sin(deg_to_rad(theta)), 0.0, -cos(deg_to_rad(theta)))
		var at_jump := Vector3(-0.4, 3.0, 10.0)
		var player: Player = await _wall_course(at_jump - dir * (66.0 / absf(dir.z)), theta)
		_in().hold_move(0.0, 1.0)
		while _kmh(player) < float(c[1]) - 0.3:
			await step(1)
		while player.global_position.z > at_jump.z:
			if _kmh(player) > float(c[1]):
				player.velocity *= float(c[1]) / _kmh(player)
			await step(1)
		_in().press_jump()
		await step(1)
		_in().release_jump()
		var guard := 0
		while player.move_manager.current_name != Move.WALL_RUN and guard < 60:
			await step(1)
			guard += 1
		for i in int(c[2]) - 1:
			await step(1)
		var before := _kmh(player)
		_in().press_jump()
		await step(1)
		_in().release_jump()
		assert_eq(player.move_manager.current_name, Move.WALLRUN_JUMP, "test setup: no wall run jump")
		await step(4)
		assert_almost_eq(_kmh(player) - before, c[3], 0.45,
			"the jump after %d frames on a wall entered %.1f degrees in" % [c[2], theta])
		await _clear()

# --- obstacles ---------------------------------------------------------------

## How deep the air conditioner's lowered rim is, m. [ME:CONFIRMED
## 测试高墙VaultOver-GrabUp 548-564] walking off the unit the body reads 4.00
## until its centre is 0.14 m short of the face and 3.89 from there to the
## edge: a rim 0.11 m below the top, its inner edge 0.31-0.44 m from the face.
const AC_RIM_DEPTH := 0.35

## The HUD's SZD: Location.Z - LastJumpLocation.Z, Location being the centre
## of the collision [ME:CONFIRMED decompile MirrorsEdgeTrainerSPHUD
## .DrawTrainerItems]. Every recorded take-off here left the course floor, so
## LastJumpLocation is `stand`, the centre standing on it -- which hovers
## above the floor as the walking physics holds it. DO NOT compare a feet
## height over the floor with SZD: it reads that hover (2 cm) high.
func _szd(player: Player, stand: float) -> float:
	return player.collision_center().y - stand

## A box `top` m tall and `depth` m deep across the course, its near face at
## z = 0; the body comes from +z facing -z. A `rim` below `top` lowers the
## top's first AC_RIM_DEPTH to it. With `kmh` > 0 it runs up at that speed and
## jumps so that the jump's first frame has the body's centre `jump_from` m
## off the face (the frame is put there: the run-up's last frame would miss
## it by up to a frame's travel); else it stands 2 cm off the face and jumps
## at once. W held throughout; from a hang, jump to pull up. Returns the state
## chain: for each state its first frame's SZD, centre to the face and speed,
## and the highest SZD in it.
func _obstacle(top: float, depth: float, kmh: float, jump_from: float, rim: float = 0.0) -> Array:
	var player: Player = await _player(Vector3(0.0, 0.0, 60.0))
	if rim > 0.0:
		_box(Vector3(4.0, rim, AC_RIM_DEPTH), Vector3(0.0, rim * 0.5, -AC_RIM_DEPTH * 0.5))
		_box(Vector3(4.0, top, depth - AC_RIM_DEPTH),
			Vector3(0.0, top * 0.5, -AC_RIM_DEPTH - (depth - AC_RIM_DEPTH) * 0.5))
	else:
		_box(Vector3(4.0, top, depth), Vector3(0.0, top * 0.5, -depth * 0.5))
	var r: float = player.default_collision_radius()
	if kmh <= 0.0:
		player.global_position = Vector3(0.0, 0.95, r + 0.02)
		await step(10)
	_in().hold_move(0.0, 1.0)
	if kmh > 0.0:
		await _run_to(player, kmh)
		while player.global_position.z - player.velocity.length() * FRAME > jump_from:
			if _kmh(player) > kmh:
				player.velocity *= kmh / _kmh(player)
			await step(1)
	# LastJumpLocation: the centre the take-off leaves from.
	var stand: float = player.collision_center().y
	_in().press_jump()
	await step(1)
	_in().release_jump()
	if kmh > 0.0:
		var shift: float = jump_from - player.global_position.z
		player.global_position.z += shift
		player.last_jump_location.z += shift
	var chain := []
	var hang := 0
	for i in 400:
		var name: StringName = player.move_manager.current_name
		var szd: float = _szd(player, stand)
		if chain.is_empty() or chain[-1]["state"] != name:
			chain.append({"state": name, "szd": szd, "to_face": player.global_position.z,
				"kmh": _kmh(player), "peak": szd})
		chain[-1]["peak"] = maxf(chain[-1]["peak"], szd)
		if name == Move.GRAB:
			hang += 1
			if hang == 70:
				_in().press_jump()
			elif hang == 71:
				_in().release_jump()
		if name == Move.WALKING and i > 30:
			break
		await step(1)
	return chain

## [ME:CONFIRMED feel-backlog §26-§27] The barbed-wire fence, 2.64 m and very
## narrow, at a run. The fence is at X 8.74, not the 9.40 §26 used: the
## vault's over leg ends exactly on the ledge (LedgeOffset Y 0), and that is
## the frame reading V 0.00 at X 8.74 -- the Falling first frame lands 1.73 m
## past it in the original and in the port alike. So the jump's first frame
## (X 11.33, SZD 0.10) is 2.59 m off. VaultOver commits after 0.95 m of flight
## with SZD 0.76, at 16.83 km/h: on its first frame the body flies (PLM_Fly)
## at the distance to the hand plant (40 uu short of the ledge) over
## VaultTimeUp 0.28 s, 1.32 m / 0.28 s here. SZD tops out at 1.77, and Falling
## takes over 1.73 m past the face with SZD 0.61 at 9.99 km/h. The HUD's
## 0.01 m and about a frame (11 cm of flight) on the distance; the commit is a
## frame of flight too, which on the vault's speed is 0.41 m/s.
func test_the_fence_is_vaulted_as_in_the_original() -> void:
	var chain: Array = await _obstacle(2.64, 0.1, 20.9, 2.59)
	assert_eq(_states(chain).slice(0, 3), [Move.JUMP, Move.VAULT_OVER, Move.FALLING], "the chain: %s" % [_states(chain)])
	var jump: Dictionary = chain[0]
	var vault: Dictionary = chain[1]
	var fall: Dictionary = chain[2]
	assert_almost_eq(float(jump["to_face"]) - float(vault["to_face"]), 0.95, 0.1, "the flight before the vault")
	assert_almost_eq(float(vault["szd"]), 0.76, 0.06, "SZD when the vault commits")
	assert_almost_eq(float(vault["kmh"]), 16.83, 0.41 * KMH, "the vault's first frame")
	assert_almost_eq(float(vault["peak"]), 1.77, 0.05, "the vault's highest SZD")
	assert_almost_eq(float(fall["to_face"]), -1.73, 0.06, "where the fall takes over")
	assert_almost_eq(float(fall["szd"]), 0.61, 0.06, "SZD when the fall takes over")
	assert_almost_eq(float(fall["kmh"]), 9.99, 0.5, "the speed the vault leaves at")

## [ME:CONFIRMED feel-backlog §29] The tall air conditioner (rim 3.89, top
## 4.00) at a run, 16.4 km/h: Jump -> WallClimb -> VaultOver -> Walking on
## top. The climb starts 1.03 m off with SZD 0.53 and the vault commits with
## SZD 2.06 (2.02 and 2.05 in 测试高墙VaultOver-GrabUp 256, 1110). §29's
## "Jump first frame" reads SZD 0.19, the second jump frame (the first reads
## 0.10 in every recorded jump): the jump's first frame is a frame of travel
## before X 16.92, 1.48 m off the face the climb presses against (X 18.31).
## Standing on top it reads 3.96-3.98 on the first frame and settles to 4.00.
func test_the_tall_box_at_a_run_is_climbed_and_vaulted_as_in_the_original() -> void:
	var chain: Array = await _obstacle(4.0, 1.5, 16.4, 1.48, 3.89)
	assert_eq(_states(chain), [Move.JUMP, Move.WALL_CLIMB, Move.VAULT_OVER, Move.WALKING], "the chain")
	assert_almost_eq(float(chain[1]["to_face"]), 1.03, 0.1, "where the climb starts")
	assert_almost_eq(float(chain[1]["szd"]), 0.53, 0.08, "SZD when the climb starts")
	assert_almost_eq(float(chain[2]["szd"]), 2.06, 0.08, "SZD when the vault commits")
	assert_almost_eq(float(chain[3]["szd"]), 3.98, 0.03, "standing on top")

## [ME:CONFIRMED feel-backlog §31-§32] The same air conditioner from a
## standstill is climbed into a hang and pulled up onto; the 2.54 m box from
## a standstill pressed against it is climbed and vaulted onto. The hang is
## held at MoveLedgeLocation - 92.8 uu, the ledge being the rim: SZD 2.04 =
## 3.89 - (92.8 + 90 + 2.15 hover) uu, as in §31 and 测试高墙VaultOver-GrabUp
## 2742-2852 -- static, so the HUD's 0.01 m. IntoGrab's first frame reads
## 2.09 in §31; the low box's VaultOver commits with SZD 0.68 (§32). A frame
## of the climb, 7 cm at those heights, on each.
func test_the_boxes_from_a_standstill_end_as_in_the_original() -> void:
	var tall: Array = await _obstacle(4.0, 1.5, 0.0, 0.0, 3.89)
	assert_eq(_states(tall), [Move.WALL_CLIMB, Move.INTO_GRAB, Move.GRAB, Move.GRAB_PULL_UP, Move.WALKING],
		"the tall box: %s" % [_states(tall)])
	assert_almost_eq(float(tall[1]["szd"]), 2.09, 0.07, "SZD when the grab starts")
	assert_almost_eq(float(tall[2]["szd"]), 2.04, 0.01, "SZD hanging")
	assert_almost_eq(float(tall[-1]["szd"]), 3.98, 0.03, "standing on the tall box")
	await _clear()
	var low: Array = await _obstacle(2.54, 1.5, 0.0, 0.0)
	assert_eq(_states(low), [Move.WALL_CLIMB, Move.VAULT_OVER, Move.WALKING], "the low box: %s" % [_states(low)])
	assert_almost_eq(float(low[1]["szd"]), 0.68, 0.07, "SZD when the vault commits")
	assert_almost_eq(float(low[-1]["szd"]), 2.54, 0.03, "standing on the low box")

## [ME:CONFIRMED 04 §4.6] Shimmying along a ledge, D held, the HUD reads
## 2.15 km/h. The HUD shows the frame's |Velocity.xy| (decompile
## MirrorsEdgeTrainerSPHUD.DrawTrainerItems), not distance over time: this
## is the speed with the strafe animation at full weight, 60 uu/s less
## physFlying's fluid friction (0.15 /s x dt), 59.85 uu/s = 2.1546 km/h.
## DO NOT compare a shimmy's average with it: each strafe blends in over
## 0.2 s and travels 58 uu in its 1.067 s, as the clip's own root does. The
## HUD's rounding to 0.01.
func test_a_shimmy_moves_at_the_originals_speed() -> void:
	var player: Player = await _player(Vector3(0.0, 0.0, 60.0))
	_box(Vector3(4.0, 3.89, 1.5), Vector3(0.0, 3.89 * 0.5, -0.75))
	player.global_position = Vector3(0.0, 0.95, player.default_collision_radius() + 0.02)
	await step(10)
	_in().hold_move(0.0, 1.0)
	_in().press_jump()
	await step(1)
	_in().release_jump()
	for i in 200:
		if player.move_manager.current_name == Move.GRAB:
			break
		await step(1)
	assert_eq(player.move_manager.current_name, Move.GRAB, "test setup: no hang")
	_in().hold_move(0.0, 0.0)
	await step(60)
	_in().hold_move(1.0, 0.0)
	var vmax := 0.0
	for i in 90:
		await step(1)
		vmax = maxf(vmax, _kmh(player))
	assert_eq(player.move_manager.current_name, Move.GRAB, "the shimmy left the hang")
	assert_almost_eq(vmax, 2.15, 0.005, "the shimmy's speed")
