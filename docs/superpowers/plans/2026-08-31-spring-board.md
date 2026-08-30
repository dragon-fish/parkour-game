# SpringBoard（踏板跳）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 复刻 ME1 的 `TdMove_SpringBoard`：地形上的两个落脚点 + 空格触发，两段脚本小弧后以 9.5 m/s 抛出，上升到顶点交给 Falling。

**Architecture:** 一条新探针 `Probes.springboard_query()` 找两个落脚点（球形投射，柱子也认得）；一个新 Move `SpringBoardMove`（继承 `AirborneMove`，组合一个 `ScriptedMove` 子节点跑两段弧）；一个新 `SpringBoardConfig` 挂在 `MovementConfig` 上；`WalkingMove` 在普通跳之前多问一次探针。

**Tech Stack:** Godot 4.7 / GDScript，GUT 测试（`bun tools/run_tests.ts <needle>`），`.engine/` 里钉死的引擎二进制。

**Spec:** `docs/superpowers/specs/2026-08-31-spring-board-design.md`

## Global Constraints

- 引擎只用 `.engine/Godot_v4.7.1-stable_win64_console.exe`，测试只通过 `bun tools/run_tests.ts`。
- 代码注释英文、无 emoji；唯一带标记的是关于原作的论断，标记只用 `[ME:CONFIRMED]` / `[ME:DERIVED]` / `[ME:INFERRED]` / `[ME:COMMUNITY]` / `[ME:UNKNOWN]`。
- `MoveConfig` 默认值是中性的；一个 move 通过声明值来"选择不同"。行为开关是配置数据，不是状态里的分支。
- 每个"能否从 X 到 Y"只在 X 的 `physics_update` 里回答一次；跨 move 数据走 `Player` 上的一次性字段，读取方清空。
- `Player.grounded` 由活动状态声明，不从 `is_on_floor()` 推断。
- 手写 `.tres` 时**不要编造 `uid://`**，省略 uid 字段让引擎自己分配；改完用 `check_references.gd` 验证。
- 表现值不写单测；结构性不变量写。
- Commit message 英文、Conventional Commits，末尾带 `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>` 与 `Claude-Session: https://claude.ai/code/session_01CZhLsDPityFkuHx1qRRwA9`。
- 分支 `feat/spring-board`，每个 task 一笔提交。

---

## File Structure

| 文件 | 职责 |
|---|---|
| `scripts/player/moves/move.gd` | 加 `SPRING_BOARD` 常量 |
| `scripts/player/config/moves/spring_board_config.gd`（新） | 全部旋钮与行为开关 |
| `scripts/player/movement_config.gd` | 聚合根加 `spring_board` |
| `presets/default.tres` | 加对应子资源 |
| `scripts/player/probes.gd` | `springboard_query()` + `_plant_top()` |
| `scripts/player/moves/spring_board_move.gd`（新） | 四阶段 Move |
| `scripts/player/player.gd` | `pending_spring_board` 一次性字段；注册 Move |
| `scripts/player/moves/walking_move.gd` | 入口 |
| `scripts/player/character_animator.gd` | `Move.SPRING_BOARD` 路由分支 |
| `tests/test_spring_board.gd`（新） | 探针 + Move 的结构性测试 |
| `tests/test_config_layout.gd` | 聚合根多一项 |
| `tests/test_animation_routing.gd` | 路由分支 |
| `scenes/debug_levels/balance_course.tscn` | 一排踏板变体供实机验证 |

---

### Task 1: 常量、配置与聚合根

**Files:**
- Modify: `scripts/player/moves/move.gd:42`
- Create: `scripts/player/config/moves/spring_board_config.gd`
- Modify: `scripts/player/movement_config.gd:45`
- Modify: `presets/default.tres`
- Test: `tests/test_config_layout.gd`

**Interfaces:**
- Produces: `Move.SPRING_BOARD == &"SpringBoard"`；`SpringBoardConfig`（字段见下）；`MovementConfig.spring_board: SpringBoardConfig`。

- [ ] **Step 1: 写失败的测试**

在 `tests/test_config_layout.gd` 末尾追加：

```gdscript
func test_spring_board_is_on_the_aggregate() -> void:
	var config := MovementConfig.new()
	assert_not_null(config.spring_board, "MovementConfig must carry a SpringBoardConfig")
	assert_true(config.spring_board is SpringBoardConfig)
	# The throw's own numbers, straight off the CDO. Declared, not defaulted.
	assert_almost_eq(config.spring_board.jump_z, 9.5, 0.001)
	assert_true(config.spring_board.check_for_grab, "the rise must keep the original's grab check")
	assert_false(config.spring_board.check_for_coil, "a spring board cannot coil: Coil is Jump's alone")
```

- [ ] **Step 2: 跑测试确认失败**

Run: `bun tools/run_tests.ts config_layout`
Expected: FAIL —— `Identifier "SpringBoardConfig" not declared` 或 `spring_board` 不存在。

- [ ] **Step 3: 加常量**

`scripts/player/moves/move.gd` 第 42 行 `const LEDGE_WALK` 之后加：

```gdscript
const SPRING_BOARD: StringName = &"SpringBoard"
```

- [ ] **Step 4: 写配置**

新建 `scripts/player/config/moves/spring_board_config.gd`：

```gdscript
class_name SpringBoardConfig
extends MoveConfig

# The original's TdMove_SpringBoard: two foot plants and the biggest vertical
# impulse in the game. Faithful to the FIRST game, on the owner's call -- not
# Catalyst's "press jump before the apex of a step-up", which turns every low
# ledge into a double jump and breaks the level language. Here the TERRAIN
# decides where a spring board is, exactly as the original does:
# [ME:CONFIRMED] the owner, in the original -- there is no trigger volume;
# two standable points 0.6 m apart in height and about a metre apart
# horizontally, faced within 53 degrees, ARE the spring board. Two poles
# qualify. See docs/superpowers/specs/2026-08-31-spring-board-design.md.

## Vertical launch speed, m/s. [ME:CONFIRMED] SpringBoardJumpZ = 950 uu/s;
## a recording put the apex 2.82 m above the launch, 0.6 s later, which is
## exactly this at gravity 16.
@export var jump_z: float = 9.5

## Added to the horizontal speed the body arrived with, m/s -- NEGATIVE:
## the spring board buys height with speed. [ME:CONFIRMED] SpringBoardJumpXYAdd
## = -100 uu/s; the recording left a 5.75 m/s walk at 4.5 m/s.
@export var xy_add: float = -1.0

## The horizontal speed the throw never drops below, m/s. [ME:CONFIRMED]
## SpringBoardJumpXYMin = 400 uu/s; thrown with no key held the HUD read
## 14.4 km/h, which is this.
@export var xy_min: float = 4.0

## Height of the FIRST foot plant above the feet, metres. [ME:CONFIRMED]
## IntermediateFootPlantHeight = 64 uu.
@export var plant_1_height: float = 0.64

## Horizontal distance from the first plant to the second, metres.
## [ME:CONFIRMED] IntermediateFootPlantDistance = 112 uu.
@export var plant_spacing: float = 1.12

## The SECOND plant's height above the feet, metres, as a range.
## [ME:CONFIRMED] SpringBoardMinHeight = 80 uu, SpringBoardMaxHeight = 148 uu;
## the recording launched from +1.24.
@export var plant_2_min_height: float = 0.8
@export var plant_2_max_height: float = 1.48

## How long each of the two steps takes, seconds. [ME:CONFIRMED] StepTime1 =
## StepTime2 = 0.2; the recording's climb is 0.40 s from the face to launch.
@export var step_time_1: float = 0.2
@export var step_time_2: float = 0.2

## Half-width of the fan, degrees, that the line from the first plant to the
## second may lie in either side of the body's facing. [ME:CONFIRMED] the
## owner, in the original, repeatedly: 53 -- no CDO field carries it.
@export var approach_angle_deg: float = 53.0

## How far ahead of the feet the first plant may be for the jump key to mean
## a spring board, metres. A project dial: the recording shows 1.2 m accepted
## and standing against the face accepted; the far limit was never swept.
## CheckDistanceTime = 1.0 s in the CDO is unexplained and NOT this.
@export var trigger_distance: float = 1.2

## Spacing of the samples walked forward looking for the first plant, metres.
@export var plant_sample_step: float = 0.1

## Tolerance on plant_1_height, metres, either way. Also the least a second
## plant must stand above the first to count as a second tier at all.
@export var plant_height_tolerance: float = 0.2

## Tolerance on plant_spacing, metres, either way; three rings are tried.
@export var plant_spacing_tolerance: float = 0.3

## Radius of the sphere dropped onto each candidate point, metres. A foot,
## roughly -- wide enough to land on a pole thinner than the capsule.
@export var plant_probe_radius: float = 0.12

## How close the feet must come to the first plant, horizontally, before the
## first step begins, metres. Wider than the capsule's radius (0.4): a box's
## face stops the capsule that far short of a plant on its top edge.
@export var plant_reach: float = 0.55

## How long the walk to the first plant may take before the move gives up
## and hands back, seconds. The recording took 0.1 to 0.2.
@export var approach_timeout: float = 0.6

## How far each step's arc peaks above the higher of its two ends, metres,
## and where the arc's control point sits (ScriptedMove.begin's control_bias:
## 0 hugs the destination, 1 rises first). Both project dials.
@export var plant_arc_height: float = 0.15
@export var plant_arc_bias: float = 0.6

func _init() -> void:
	# [ME:CONFIRMED] bCheckForGrab, bCheckForVaultOver, bCheckForWallClimb are
	# all True on the CDO: the rise looks for all three. NOT coil: Coil enters
	# from Jump alone (05 sec 5.2), and this is not Jump.
	check_for_grab = true
	check_for_vault_over = true
	check_for_wall_climb = true
	# The steps are scripted: the model is pinned along the plants while the
	# capsule and the view stay the player's. [ME:CONFIRMED] ControllerState =
	# PlayerWalking and no bConstrainLook -- the view is free the whole time,
	# which is what lets a fast mouse throw the body backwards.
	freeze_visual_yaw = true
	allows_turn = false
```

- [ ] **Step 5: 挂进聚合根**

`scripts/player/movement_config.gd` 第 45 行 `ledge_walk` 之后加：

```gdscript
@export var spring_board: SpringBoardConfig = SpringBoardConfig.new()
```

- [ ] **Step 6: 加进预设**

`presets/default.tres`：
1. 在第 27 行（`ledge_walk_config.gd` 的 ext_resource）之后加一行，**不写 uid**：
   ```
   [ext_resource type="Script" path="res://scripts/player/config/moves/spring_board_config.gd" id="26_sprbd"]
   ```
2. 在 `[sub_resource type="Resource" id="Resource_lw81h"]` 那一段之后（它以 `allows_turn = false` 结尾，后面是空行）加：
   ```
   [sub_resource type="Resource" id="Resource_sprbd"]
   script = ExtResource("26_sprbd")
   check_for_grab = true
   check_for_vault_over = true
   check_for_wall_climb = true
   freeze_visual_yaw = true
   allows_turn = false

   ```
3. 在文件末尾 `ledge_walk = SubResource("Resource_lw81h")` 之后加：
   ```
   spring_board = SubResource("Resource_sprbd")
   ```

- [ ] **Step 7: 跑测试与引用检查**

Run: `bun tools/run_tests.ts config_layout generated_scenes`
Expected: PASS。
Run: `./.engine/Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tools/check_references.gd`
Expected: 无 missing 报告；`default.tres` 加载正常。若报 `invalid UID`，删掉 `.godot/uid_cache.bin` 后重跑一次。

- [ ] **Step 8: 提交**

```bash
git add scripts/player/moves/move.gd scripts/player/config/moves/spring_board_config.gd scripts/player/movement_config.gd presets/default.tres tests/test_config_layout.gd
git commit -m "feat(spring-board): the config, on the aggregate and in the preset"
```

---

### Task 2: 探针 `Probes.springboard_query()`

**Files:**
- Modify: `scripts/player/probes.gd`（在 `ledge_beside()` 之前加）
- Create: `tests/test_spring_board.gd`

**Interfaces:**
- Consumes: `_config: MovementConfig`、`feet_y()`、`_no_hit()`、`_surface.collision_mask`（Task 1 的 `SpringBoardConfig`）。
- Produces: `springboard_query() -> Dictionary`，命中为 `{"valid": true, "plant_1": Vector3, "plant_2": Vector3}`（两个世界坐标脚落点），否则 `_no_hit()`（`valid == false`）。

- [ ] **Step 1: 写失败的测试**

新建 `tests/test_spring_board.gd`：

```gdscript
extends ParkourTest

# STRUCTURAL: which shapes are a spring board and which are not, and what the
# move does with one. The numbers themselves (9.5, 0.64, 1.12, 53) are the
# original's and are not asserted here beyond "the move uses the config's".

const TestWorld = preload("res://tests/world_fixture.gd")

var _world: Dictionary = {}
var _props: Array[Node] = []

func after_each() -> void:
	for prop in _props:
		if is_instance_valid(prop):
			prop.queue_free()
	_props.clear()
	if not _world.is_empty():
		TestWorld.teardown(_world)
		_world = {}

## A standing player on the fixture floor (top at y = 0), facing -Z.
func _standing_player() -> Player:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var player: Player = _world["player"]
	assert_eq(player.move_manager.current_name, Move.WALKING, "test setup: not standing")
	return player

## A pole `height` tall standing on the floor, its top centred at (x, z).
## 0.3 m across by default: thinner than the capsule, which is the case a ray
## misses. `depth` (along Z) defaults to `across`.
func _pole(x: float, z: float, height: float, across: float = 0.3, depth: float = -1.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(across, height, depth if depth > 0.0 else across)
	shape.shape = box
	body.add_child(shape)
	get_tree().root.add_child(body)
	body.global_position = Vector3(x, height * 0.5, z)
	_props.append(body)
	return body

## The two poles of a spring board ahead of a player at the origin facing -Z:
## the first `ahead` metres out, the second 1.12 m further, turned `bearing_deg`
## off the facing about the first.
func _spring_board_ahead(ahead: float, bearing_deg: float = 0.0) -> void:
	var cfg := SpringBoardConfig.new()
	_pole(0.0, -ahead, cfg.plant_1_height)
	var second := Vector3(0.0, 0.0, -cfg.plant_spacing).rotated(Vector3.UP, deg_to_rad(bearing_deg))
	_pole(second.x, -ahead + second.z, cfg.plant_1_height + 0.6)

func test_two_plants_ahead_are_a_spring_board() -> void:
	var player: Player = await _standing_player()
	_spring_board_ahead(1.0)
	await step(2)
	var hit: Dictionary = player.probes.springboard_query()
	assert_true(hit["valid"], "two plants ahead were not seen as a spring board")
	assert_almost_eq(hit["plant_1"].y, 0.64, 0.05, "the first plant's top is wrong")
	assert_almost_eq(hit["plant_2"].y, 1.24, 0.05, "the second plant's top is wrong")
	assert_almost_eq(hit["plant_2"].z, -2.12, 0.35, "the second plant is not where the pole is")

func test_one_plant_is_not_a_spring_board() -> void:
	var player: Player = await _standing_player()
	_pole(0.0, -1.0, 0.64)
	await step(2)
	assert_false(player.probes.springboard_query()["valid"],
		"a single low pole was taken for a spring board")

func test_the_second_plant_must_lie_inside_the_approach_fan() -> void:
	var player: Player = await _standing_player()
	_spring_board_ahead(1.0, 70.0)
	await step(2)
	assert_false(player.probes.springboard_query()["valid"],
		"a second plant 70 degrees off the facing was accepted")

func test_the_second_plant_may_lie_off_the_facing_inside_the_fan() -> void:
	var player: Player = await _standing_player()
	_spring_board_ahead(1.0, 40.0)
	await step(2)
	assert_true(player.probes.springboard_query()["valid"],
		"a second plant 40 degrees off the facing was refused")

func test_a_first_plant_beyond_the_trigger_distance_is_out_of_reach() -> void:
	var player: Player = await _standing_player()
	_spring_board_ahead(2.0)
	await step(2)
	assert_false(player.probes.springboard_query()["valid"],
		"a spring board 2 m out was accepted")

func test_a_wide_step_is_a_spring_board_too() -> void:
	# The plants are points on whatever is there: two tiers 3 m wide work
	# exactly like two poles. Each a metre deep, so the second tier's face
	# sits plant_spacing from the first plant (the first tier's front edge),
	# the way the recording's two crates did.
	var player: Player = await _standing_player()
	_pole(0.0, -1.5, 0.64, 3.0, 1.0)
	_pole(0.0, -2.62, 1.24, 3.0, 1.0)
	await step(2)
	assert_true(player.probes.springboard_query()["valid"],
		"two wide tiers were not seen as a spring board")
```

- [ ] **Step 2: 跑测试确认失败**

Run: `bun tools/run_tests.ts spring_board`
Expected: FAIL —— `Nonexistent function 'springboard_query'`。

- [ ] **Step 3: 写探针**

`scripts/player/probes.gd`，在 `## Whether the ledge the player is hanging from continues` 那段注释（`ledge_beside()` 的文档）之前插入：

```gdscript
## Two foot plants ahead for a spring board, or a miss: {valid, plant_1,
## plant_2}, both world positions of the feet on top of each plant.
##
## FINDS POINTS, NOT FACES. [ME:CONFIRMED] the owner, in the original: two
## poles about a metre apart, one 0.6 m tall and one 1.2 m, are a spring
## board, and nothing about width or depth is asked. So every probe here is a
## SPHERE dropped from above onto a candidate point -- a pole can be thinner
## than the capsule, and a ray fired beside it reports nothing at all.
##
## The first plant is looked for straight ahead, nearest first, out to
## trigger_distance. The second is looked for on rings of plant_spacing
## around the first, inside the approach fan -- and the fan is walked from
## the facing OUTWARD, so on a wide tier the second plant is where the
## facing crosses it (in at an angle, out at that angle) and only two bare
## poles land it at the fan's edge. Whether the body FITS on either point is
## not asked here: Probes answer geometry, and standing room is Player's
## question (fits_standing_at), the same split ledge_query() keeps.
func springboard_query() -> Dictionary:
	if _config == null:
		return _no_hit()
	var cfg: SpringBoardConfig = _config.spring_board
	var feet := Vector3(global_position.x, feet_y(), global_position.z)
	var forward: Vector3 = -global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return _no_hit()
	forward = forward.normalized()

	var plant_1 := Vector3.ZERO
	var found_first := false
	var samples: int = int(ceil(cfg.trigger_distance / maxf(cfg.plant_sample_step, 0.01)))
	for i in range(samples + 1):
		var at: Vector3 = feet + forward * (float(i) * cfg.plant_sample_step)
		var top: float = _plant_top(at, cfg.plant_1_height + cfg.plant_height_tolerance, cfg)
		if is_nan(top):
			continue
		if absf(top - feet.y - cfg.plant_1_height) <= cfg.plant_height_tolerance:
			plant_1 = Vector3(at.x, top, at.z)
			found_first = true
			break
	if not found_first:
		return _no_hit()

	# Bearings from the facing outward, alternating sides: 0, +a, -a, +2a, ...
	var half_fan: float = deg_to_rad(cfg.approach_angle_deg)
	var bearings: Array[float] = [0.0]
	for k in range(1, 4):
		var a: float = half_fan * float(k) / 3.0
		bearings.append(a)
		bearings.append(-a)
	var radii: Array[float] = [cfg.plant_spacing,
		cfg.plant_spacing - cfg.plant_spacing_tolerance,
		cfg.plant_spacing + cfg.plant_spacing_tolerance]
	for bearing in bearings:
		var toward: Vector3 = forward.rotated(Vector3.UP, bearing)
		for radius in radii:
			var at: Vector3 = plant_1 + toward * radius
			at.y = feet.y
			var top: float = _plant_top(at, cfg.plant_2_max_height, cfg)
			if is_nan(top):
				continue
			var rise: float = top - feet.y
			if rise < cfg.plant_2_min_height or rise > cfg.plant_2_max_height:
				continue
			# A second TIER, not the same one again: the first plant's own top
			# is inside plant_2's range when it stands tall.
			if top <= plant_1.y + cfg.plant_height_tolerance:
				continue
			return {"valid": true, "plant_1": plant_1, "plant_2": Vector3(at.x, top, at.z)}
	return _no_hit()

## The top surface under a sphere dropped onto `at` from `reach` above it,
## as a world Y, or NAN when nothing is there down to a little below `at`.
## The sphere's radius is the config's plant_probe_radius.
func _plant_top(at: Vector3, reach: float, cfg: SpringBoardConfig) -> float:
	var space := get_world_3d().direct_space_state
	if space == null:
		return NAN
	var sphere := SphereShape3D.new()
	sphere.radius = cfg.plant_probe_radius
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = sphere
	# Start a little above the reach so a top exactly at the reach is still
	# met from above rather than started inside.
	var start_y: float = at.y + reach + cfg.plant_probe_radius + 0.3
	params.transform = Transform3D(Basis.IDENTITY, Vector3(at.x, start_y, at.z))
	var drop: float = start_y - at.y + cfg.plant_height_tolerance
	params.motion = Vector3.DOWN * drop
	params.collision_mask = _surface.collision_mask if _surface != null else 1
	var body := get_parent() as CollisionObject3D
	if body != null:
		params.exclude = [body.get_rid()]
	var fractions: PackedFloat32Array = space.cast_motion(params)
	if fractions.size() < 2 or fractions[0] >= 1.0:
		return NAN
	# The sphere's underside where it stopped is the surface it stopped on.
	return start_y - fractions[0] * drop - cfg.plant_probe_radius
```

- [ ] **Step 4: 跑测试确认通过**

Run: `bun tools/run_tests.ts spring_board probes_ledge probes_vault`
Expected: 全部 PASS（后两者确认没有动到已有探针）。若 `test_two_plants_ahead...` 因 `plant_2.z` 偏差失败，先打印 `hit`，确认 `_plant_top` 返回的是柱顶而不是柱侧（`fractions[0]` 为 0 表示球起点已在几何内，检查 `start_y`）。

- [ ] **Step 5: 提交**

```bash
git add scripts/player/probes.gd tests/test_spring_board.gd
git commit -m "feat(spring-board): a probe that finds two foot plants, poles included"
```

---

### Task 3: `SpringBoardMove` 与入口

**Files:**
- Create: `scripts/player/moves/spring_board_move.gd`
- Modify: `scripts/player/player.gd:45`（一次性字段）、`scripts/player/player.gd:1346`（注册）
- Modify: `scripts/player/moves/walking_move.gd:44`（入口）
- Test: `tests/test_spring_board.gd`（追加）

**Interfaces:**
- Consumes: Task 1 的 `SpringBoardConfig`、Task 2 的 `springboard_query()`；`AirborneMove.apply_air_physics(delta, wish_dir)` / `probe_transition() -> StringName` / `advance_and_hand_off(destination) -> StringName` / `settle_landing(delta) -> StringName`；`Move.carry_ballistically(delta)`；`ScriptedMove.begin(from, to, duration, apex_y, control_bias, ease)` / `advance(delta) -> bool` / `sample(t)` / `path_debug()` / `scripted_duration()`；`Player.lock_input()` / `unlock_input()` / `set_grounded()` / `pin_visual_yaw(radians)` / `set_clip_lift_cancelled(bool)` / `horizontal_speed()` / `standing_height()` / `fits_standing_at(feet_point)` / `consume_jump()` / `fall_tracker.reset(y)` / `probes.feet_y()`。
- Produces: `Player.pending_spring_board: Dictionary`；`SpringBoardMove.is_stepping() -> bool`、`scripted_duration() -> float`、`path_debug() -> Dictionary`、`sample(t) -> Vector3`。

- [ ] **Step 1: 写失败的测试**

在 `tests/test_spring_board.gd` 末尾追加：

```gdscript
# --- the move --------------------------------------------------------------

## Stands the player 1 m short of a spring board and presses jump.
func _press_jump_at_a_spring_board(bearing_deg: float = 0.0) -> Player:
	var player: Player = await _standing_player()
	_spring_board_ahead(1.0, bearing_deg)
	await step(2)
	_world["input"].state.jump_pressed = true
	_world["input"].state.jump_held = true
	await step(1)
	_world["input"].state.jump_pressed = false
	return player

func test_jump_at_a_spring_board_is_a_spring_board_not_a_jump() -> void:
	var player: Player = await _press_jump_at_a_spring_board()
	assert_eq(player.move_manager.current_name, Move.SPRING_BOARD,
		"jump in front of two plants did not spring board")

func test_jump_with_only_one_plant_ahead_is_a_plain_jump() -> void:
	var player: Player = await _standing_player()
	_pole(0.0, -1.0, 0.64)
	await step(2)
	_world["input"].state.jump_pressed = true
	_world["input"].state.jump_held = true
	await step(1)
	assert_eq(player.move_manager.current_name, Move.JUMP,
		"one pole ahead turned a jump into something else")

func test_a_plant_the_body_cannot_stand_on_is_refused() -> void:
	# A slab hanging 1.0 m above the second plant's top: the capsule is 1.8 m.
	var player: Player = await _standing_player()
	_spring_board_ahead(1.0)
	var roof := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 0.2, 1.0)
	shape.shape = box
	roof.add_child(shape)
	get_tree().root.add_child(roof)
	roof.global_position = Vector3(0.0, 1.24 + 1.0 + 0.1, -2.12)
	_props.append(roof)
	await step(2)
	_world["input"].state.jump_pressed = true
	_world["input"].state.jump_held = true
	await step(1)
	assert_eq(player.move_manager.current_name, Move.JUMP,
		"a spring board the body cannot stand on top of was still taken")

func test_the_steps_put_the_feet_on_each_plant_in_turn() -> void:
	var player: Player = await _press_jump_at_a_spring_board()
	var board := player.move_manager.move_for(Move.SPRING_BOARD) as SpringBoardMove
	# Walk on to the first plant's face.
	var ticks: int = 0
	while not board.is_stepping() and ticks < 60:
		await step(1)
		ticks += 1
	assert_true(board.is_stepping(), "the steps never began")
	assert_true(player.grounded, "stepping on the plants is not declared grounded")
	assert_true(player.is_input_locked(), "the steps did not lock input")
	await step(int(player.config.spring_board.step_time_1 * 60.0))
	var feet_1: float = player.probes.feet_y()
	assert_almost_eq(feet_1, 0.64, 0.08,
		"after the first step the feet are at %.2f, not on the first plant" % feet_1)
	await step(int(player.config.spring_board.step_time_2 * 60.0))
	var feet_2: float = player.probes.feet_y()
	assert_almost_eq(feet_2, 1.24, 0.08,
		"after the second step the feet are at %.2f, not on the second plant" % feet_2)

func test_the_throw_is_the_configs_and_the_rise_ends_in_falling() -> void:
	var player: Player = await _press_jump_at_a_spring_board()
	var board := player.move_manager.move_for(Move.SPRING_BOARD) as SpringBoardMove
	var cfg: SpringBoardConfig = player.config.spring_board
	var ticks: int = 0
	while board.is_stepping() or not board.has_launched():
		await step(1)
		ticks += 1
		assert_true(ticks < 120, "the throw never came")
	assert_eq(player.move_manager.current_name, Move.SPRING_BOARD,
		"the throw handed off instead of the move keeping the rise")
	# One tick of the rise's own gravity has come off already.
	assert_gt(player.velocity.y, cfg.jump_z - player.config.pawn.gravity * 0.05,
		"the throw's vertical speed is not the config's (%.2f)" % player.velocity.y)
	assert_almost_eq(player.horizontal_speed(), cfg.xy_min, 0.3,
		"a standing start must be thrown at xy_min (%.2f)" % player.horizontal_speed())
	assert_false(player.is_input_locked(), "the rise did not give input back")
	# The rise stays with the move until the apex.
	while player.velocity.y > 0.0 and ticks < 200:
		assert_eq(player.move_manager.current_name, Move.SPRING_BOARD, "the rise left the move early")
		await step(1)
		ticks += 1
	await step(2)
	assert_eq(player.move_manager.current_name, Move.FALLING,
		"past the apex the move did not hand off to Falling")

func test_the_throw_goes_where_the_camera_looks_at_that_instant() -> void:
	# The owner: turn the view round during the steps and the body is thrown
	# backwards -- a known glitch in the original, copied on purpose.
	var player: Player = await _press_jump_at_a_spring_board()
	var board := player.move_manager.move_for(Move.SPRING_BOARD) as SpringBoardMove
	var ticks: int = 0
	while not board.is_stepping() and ticks < 60:
		await step(1)
		ticks += 1
	player.rotation.y += PI  # facing +Z now
	while not board.has_launched() and ticks < 120:
		await step(1)
		ticks += 1
	assert_gt(player.velocity.z, 0.0,
		"thrown along the plants (-Z) instead of the way the camera looks (+Z)")

func test_the_rise_cannot_coil() -> void:
	var player: Player = await _press_jump_at_a_spring_board()
	var board := player.move_manager.move_for(Move.SPRING_BOARD) as SpringBoardMove
	var ticks: int = 0
	while not board.has_launched() and ticks < 120:
		await step(1)
		ticks += 1
	_world["input"].state.crouch_pressed = true
	_world["input"].state.crouch_held = true
	await step(3)
	assert_ne(player.move_manager.current_name, Move.COIL,
		"a spring board coiled: Coil belongs to Jump alone")
```

- [ ] **Step 2: 跑测试确认失败**

Run: `bun tools/run_tests.ts spring_board`
Expected: 新用例 FAIL —— `Identifier "SpringBoardMove" not declared` / `Move.SPRING_BOARD` 进不去。

- [ ] **Step 3: 一次性字段与注册**

`scripts/player/player.gd` 第 45 行 `var pending_vault_variant` 之前加：

```gdscript
## The two foot plants the spring board about to start was admitted on --
## WalkingMove's own springboard_query() result -- so SpringBoardMove.enter()
## does not probe again from a body that has moved a tick since. One-shot:
## SpringBoardMove.enter() reads it and clears it.
var pending_spring_board: Dictionary = {}
```

同文件 `_build_moves()` 的表里，`[Move.BALANCE, BalanceMove.new(), config.balance],` 之后加：

```gdscript
		[Move.SPRING_BOARD, SpringBoardMove.new(), config.spring_board],
```

- [ ] **Step 4: 写 Move**

新建 `scripts/player/moves/spring_board_move.gd`：

```gdscript
class_name SpringBoardMove
extends AirborneMove

# The original's TdMove_SpringBoard, faithful to the first game: two foot
# plants the terrain provides, a walk up to the first, two scripted steps with
# no gravity, a throw at the biggest vertical impulse in the game, and the
# rise kept by this move until the apex. See
# docs/superpowers/specs/2026-08-31-spring-board-design.md for the
# measurements every number here comes from.
#
# FOUR PHASES IN ONE MOVE, and the first and last are the reason it is one:
# [ME:CONFIRMED] a recording of the original holds SpringBoarding from the
# jump press, through 0.1-0.2 s of ordinary walking up to the first face,
# through the 0.4 s climb, and on through the whole 0.6 s rise -- Falling only
# takes over at the apex. Handing the rise to JumpMove instead would let it
# coil, which the original cannot (Coil enters from Jump alone), and would
# run Jump's probes rather than the three the CDO gives this move.
#
# Extends AirborneMove for the rise's air physics and probes, and COMPOSES a
# ScriptedMove for the two steps -- the same shape LadderMove gives its top
# exit, because GDScript has no second base class.

enum Phase { APPROACH, STEP_1, STEP_2, RISE }

## The step being walked, and the arc it is on. A child so its lifetime is
## this move's; see LadderMove._top_exit.
var _hop: ScriptedMove = ScriptedMove.new()
var _phase: Phase = Phase.APPROACH
var _plant_1: Vector3 = Vector3.ZERO
var _plant_2: Vector3 = Vector3.ZERO
## Horizontal speed at entry -- what the throw is priced against. Read
## BEFORE anything zeroes velocity (the steps do), the same trap
## BalanceMove.enter() documents.
var _entry_speed: float = 0.0
var _approach_time: float = 0.0
var _launched: bool = false
var _aborted: bool = false

func _ready() -> void:
	super._ready()
	add_child(_hop)

func enter(_previous: StringName) -> void:
	var board: Dictionary = player.pending_spring_board
	player.pending_spring_board = {}
	_aborted = board.is_empty() or not bool(board.get("valid", false))
	_launched = false
	if _aborted:
		return
	_plant_1 = board["plant_1"]
	_plant_2 = board["plant_2"]
	_entry_speed = player.horizontal_speed()
	_phase = Phase.APPROACH
	_approach_time = 0.0
	_hop.player = player
	# The feet are on things for the whole of the walk and the steps:
	# declared, never inferred, and set again every tick below.
	player.set_grounded(true)
	player.lock_input()
	# The model faces along the plants for the steps; the capsule keeps
	# following the view, which is what the throw reads.
	var along: Vector3 = _plant_2 - _plant_1
	along.y = 0.0
	if along.length_squared() > 0.0001:
		along = along.normalized()
		player.pin_visual_yaw(atan2(-along.x, -along.z))
	# The arcs carry the whole climb; a clip lifting its own hips on top
	# would double it -- the gate every scripted carry arms.
	player.set_clip_lift_cancelled(true)

func exit() -> void:
	player.unlock_input()
	player.set_clip_lift_cancelled(false)

func physics_update(delta: float, input: MoveInput) -> StringName:
	if _aborted:
		player.set_grounded(player.is_on_floor())
		return WALKING
	match _phase:
		Phase.APPROACH:
			return _approach(delta)
		Phase.STEP_1, Phase.STEP_2:
			return _step(delta)
		Phase.RISE:
			return _rise(delta, input)
	return KEEP

## Walking on at the speed the body arrived with until the feet are within
## plant_reach of the first plant. [ME:CONFIRMED] the recording: 0.1-0.2 s of
## ordinary travel between the press and the climb. Timed out rather than
## waited on forever: a body that never gets there -- the press was taken
## from further out than the walk can cover -- is handed back to walk.
func _approach(delta: float) -> StringName:
	_approach_time += delta
	var feet := Vector3(player.global_position.x, player.probes.feet_y(), player.global_position.z)
	var gap := Vector3(_plant_1.x - feet.x, 0.0, _plant_1.z - feet.z)
	if gap.length() <= cfg.plant_reach:
		_begin_step(_plant_1, cfg.step_time_1)
		_phase = Phase.STEP_1
		return KEEP
	if _approach_time >= cfg.approach_timeout:
		player.set_grounded(player.is_on_floor())
		return WALKING
	carry_ballistically(delta)
	player.set_grounded(true)
	return KEEP

## One step: a small arc from where the body is to `plant`, the capsule's
## centre a half height above the plant, peaking plant_arc_height above the
## higher end. ScriptedMove's one bezier, the shape every scripted carry
## shares (see its sample()).
func _begin_step(plant: Vector3, duration: float) -> void:
	var from: Vector3 = player.global_position
	var to: Vector3 = plant + Vector3.UP * (player.standing_height() * 0.5)
	var apex: float = maxf(from.y, to.y) + cfg.plant_arc_height
	_hop.begin(from, to, duration, apex, cfg.plant_arc_bias)
	# NO GRAVITY THROUGH THE STEPS. [ME:CONFIRMED] PawnPhysics = PHYS_Flying:
	# the arc owns the body outright and velocity means nothing until the
	# throw writes it.
	player.velocity = Vector3.ZERO

func _step(delta: float) -> StringName:
	player.set_grounded(true)
	if not _hop.advance(delta):
		return KEEP
	if _phase == Phase.STEP_1:
		_begin_step(_plant_2, cfg.step_time_2)
		_phase = Phase.STEP_2
		return KEEP
	_launch()
	return KEEP

## The throw, the tick the second step lands.
##
## THE CAMERA'S WAY, READ NOW. [ME:CONFIRMED] the owner, twice in the
## original: in at an angle, out at that angle; turn the view right round
## during the steps and the body is thrown backwards. The capsule's yaw IS the
## view's, in both of this project's views, so it is read off the capsule.
## Priced against the speed the body ARRIVED with: [ME:CONFIRMED] a 5.75 m/s
## walk left at 4.5, and a standing start left at 4.0 -- xy_add and xy_min.
func _launch() -> void:
	var dir: Vector3 = -player.global_transform.basis.z
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		dir = _plant_2 - _plant_1
		dir.y = 0.0
	dir = dir.normalized()
	var xy: float = maxf(_entry_speed + cfg.xy_add, cfg.xy_min)
	player.velocity = dir * xy + Vector3.UP * cfg.jump_z
	# The fall is measured from the launch, not from the ground the walk
	# began on: a spring board is not a 1.2 m drop before it has even risen.
	player.fall_tracker.reset(player.global_position.y)
	player.set_grounded(false)
	player.unlock_input()
	player.set_clip_lift_cancelled(false)
	_launched = true
	_phase = Phase.RISE

## The rise, kept here until the apex. Air physics and the config's own
## probes (grab, vault over, wall climb -- [ME:CONFIRMED] the three
## bCheckFor* on the CDO), and Falling the tick the vertical speed is gone
## ([ME:CONFIRMED] bCheckExitToFalling). No coil: that is Jump's alone.
func _rise(delta: float, input: MoveInput) -> StringName:
	apply_air_physics(delta, player.wish_direction(input))
	var probed := probe_transition()
	if probed != KEEP:
		player.set_grounded(false)
		return probed
	if player.velocity.y <= 0.0:
		return advance_and_hand_off(FALLING)
	return settle_landing(delta)

## True through the two scripted steps. Read by CharacterAnimator and tests.
func is_stepping() -> bool:
	return _phase == Phase.STEP_1 or _phase == Phase.STEP_2

## True once the throw has been written. Read by tests.
func has_launched() -> bool:
	return _launched

## The scripted-fit hook (CharacterAnimator._scripted_fit): the whole climb,
## both steps, is one window for the clip; 0 outside the steps.
func scripted_duration() -> float:
	return cfg.step_time_1 + cfg.step_time_2 if is_stepping() else 0.0

## For the debug HUD's scripted row and the animation lab, which draw the
## real curve rather than a picture of a second implementation.
func path_debug() -> Dictionary:
	return _hop.path_debug() if is_stepping() else {}

func sample(t: float) -> Vector3:
	return _hop.sample(t)
```

- [ ] **Step 5: 入口**

`scripts/player/moves/walking_move.gd`，在第 44 行 `if player.consume_jump():` 之前插入：

```gdscript
	# A SPRING BOARD OUTRANKS A PLAIN JUMP. [ME:CONFIRMED] the owner, in the
	# original: two foot plants ahead and the jump key IS the spring board.
	# Asked on the press only, and only from the ground -- the original never
	# enters this from the air. Standing room on both plants is Player's
	# question, not the probe's, the same split ledge_query() keeps.
	if player.grounded and input.jump_pressed and player.probes != null \
			and player.move_manager.can_enter(SPRING_BOARD):
		var board: Dictionary = player.probes.springboard_query()
		if board["valid"] and player.fits_standing_at(board["plant_1"]) \
				and player.fits_standing_at(board["plant_2"]):
			# Spent here so the buffered press cannot fire a second jump on
			# the way down; refused only by a level's own jump block, in
			# which case the plain jump below is refused the same way.
			if player.consume_jump():
				player.pending_spring_board = board
				return SPRING_BOARD
```

- [ ] **Step 6: 跑测试确认通过**

Run: `bun tools/run_tests.ts spring_board move_manager standing_jump coil`
Expected: 全部 PASS。常见失败与对策：
- `the steps never began`：`plant_reach` 小于胶囊半径加立面余量，先打印 `gap.length()`，必要时把 `plant_reach` 提到 0.6（是旋钮，不改逻辑）。
- `a standing start must be thrown at xy_min`：`_entry_speed` 读晚了（在 `velocity` 被清零之后），检查 `enter()` 顺序。
- `test_every_move_has_its_own_case`（animation_routing）此时会开始失败，这是 Task 4 的事。

- [ ] **Step 7: 提交**

```bash
git add scripts/player/moves/spring_board_move.gd scripts/player/player.gd scripts/player/moves/walking_move.gd tests/test_spring_board.gd
git commit -m "feat(spring-board): the move -- walk up, two steps, the throw, the rise to the apex"
```

---

### Task 4: 动画路由

**Files:**
- Modify: `scripts/player/character_animator.gd`（`Move.SPEED_VAULT:` 分支之前）
- Test: `tests/test_animation_routing.gd`（追加）

**Interfaces:**
- Consumes: `SpringBoardMove.is_stepping()`、`scripted_duration()`（Task 3）；`_first_available()`、`AIRBORNE_LOOP`。

- [ ] **Step 1: 写失败的测试**

`tests/test_animation_routing.gd` 末尾追加：

```gdscript
func test_a_spring_board_steps_on_step_up_and_rises_on_the_airborne_loop() -> void:
	# The move's own phase is poked, the way the ledge's turn is above: with
	# no plants registered the move aborts, but the routing only asks the
	# move which phase it is in.
	var animator: CharacterAnimator = await _animator_with(
		[&"StepUp", &"Jump", &"Idle"])
	var player: Player = _world["player"]
	player.move_manager.start(Move.SPRING_BOARD)
	var board := player.move_manager.move_for(Move.SPRING_BOARD) as SpringBoardMove
	assert_not_null(board, "no SpringBoardMove to drive")
	board._phase = SpringBoardMove.Phase.STEP_1
	assert_eq(String(animator._target_animation()), "StepUp",
		"the steps asked for '%s'" % String(animator._target_animation()))
	assert_almost_eq(board.scripted_duration(),
		player.config.spring_board.step_time_1 + player.config.spring_board.step_time_2, 0.001,
		"the steps did not offer the clip both step times as its window")
	board._phase = SpringBoardMove.Phase.RISE
	assert_eq(String(animator._target_animation()), "Jump",
		"the rise asked for '%s'" % String(animator._target_animation()))
```

- [ ] **Step 2: 跑测试确认失败**

Run: `bun tools/run_tests.ts animation_routing`
Expected: `test_every_move_has_its_own_case` FAIL（源码里没有 `Move.SPRING_BOARD:`），新用例 FAIL。

- [ ] **Step 3: 加路由分支**

`scripts/player/character_animator.gd`，在 `Move.SPEED_VAULT:` 那个 case 之前插入：

```gdscript
		Move.SPRING_BOARD:
			# The walk up and the two steps play the pack's StepUp -- a
			# no-hands scramble is what stepping up two plants is -- fitted
			# to both step times through scripted_duration(). The rise is a
			# rise: the same airborne loop every other one plays. No clip in
			# the pack is a spring board; this is the nearest shape.
			var board = player.move_manager.move_for(Move.SPRING_BOARD)
			if board != null and board.is_stepping():
				return _first_available([&"StepUp", &"Jump_Start", &"jump", &"idle"])
			if board != null and board.has_launched():
				return _first_available(AIRBORNE_LOOP)
			return _first_available([&"StepUp", &"Jump_Start", &"Idle", &"idle"])
```

- [ ] **Step 4: 跑测试确认通过**

Run: `bun tools/run_tests.ts animation_routing spring_board`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add scripts/player/character_animator.gd tests/test_animation_routing.gd
git commit -m "feat(spring-board): route the steps onto StepUp and the rise onto the airborne loop"
```

---

### Task 5: 白盒关卡里的踏板画廊 + 全套验证

**Files:**
- Modify: `scenes/debug_levels/balance_course.tscn`
- Test: 全套

**Interfaces:**
- Consumes: 以上全部。

- [ ] **Step 1: 摆一排踏板变体（"画廊"）**

在 `scenes/debug_levels/balance_course.tscn` 里加一块新平台 `SpringGallery`，
紧贴 PlatformA（中心 (20, 4.75, 0)，3 m 见方，顶面 y = 5.0）的 +X 侧，从出生点
往 +X 走就到。平台 12 × 0.5 × 12，中心 (28, 4.75, 0)，顶面 5.0，x 22..34，z -6..6。
四条通道沿 +X 方向，各自一种几何，第一落脚点的前沿都在 x = 25.5，第二落脚点的
前沿在 x = 26.62（相距 1.12）：

| 通道 z | 第一级（顶面脚上 0.64） | 第二级（顶面脚上 1.24） |
|---|---|---|
| -4.5 | 箱子 1.2 宽 × 1.0 深，中心 x 26.0 | 箱子 1.2 宽 × 1.0 深，中心 x 27.12 |
| -1.5 | 箱子（同上） | 柱子 0.3 × 0.3，中心 x 26.77 |
| 1.5 | 柱子 0.3 × 0.3，中心 x 25.65 | 柱子 0.3 × 0.3，中心 x 26.77 |
| 4.5 | 栏杆：0.1 厚 × 1.5 宽的薄板，中心 x 25.55 | 矮墙：0.2 厚 × 1.5 宽，中心 x 26.72 |

（中心 y：0.64 高的是 5.32，1.24 高的是 5.62。）

在 `[sub_resource type="BoxShape3D" id="Shape_endplatform"]` 之前加形状与网格
（网格材质复用 `Material_platform` / `Material_ledge`）：

```
[sub_resource type="BoxShape3D" id="Shape_gallery"]
size = Vector3(12, 0.5, 12)

[sub_resource type="BoxMesh" id="Mesh_gallery"]
material = SubResource("Material_platform")
size = Vector3(12, 0.5, 12)

[sub_resource type="BoxShape3D" id="Shape_sb_box_low"]
size = Vector3(1.0, 0.64, 1.2)

[sub_resource type="BoxMesh" id="Mesh_sb_box_low"]
material = SubResource("Material_ledge")
size = Vector3(1.0, 0.64, 1.2)

[sub_resource type="BoxShape3D" id="Shape_sb_box_high"]
size = Vector3(1.0, 1.24, 1.2)

[sub_resource type="BoxMesh" id="Mesh_sb_box_high"]
material = SubResource("Material_ledge")
size = Vector3(1.0, 1.24, 1.2)

[sub_resource type="BoxShape3D" id="Shape_sb_pole_low"]
size = Vector3(0.3, 0.64, 0.3)

[sub_resource type="BoxMesh" id="Mesh_sb_pole_low"]
material = SubResource("Material_ledge")
size = Vector3(0.3, 0.64, 0.3)

[sub_resource type="BoxShape3D" id="Shape_sb_pole_high"]
size = Vector3(0.3, 1.24, 0.3)

[sub_resource type="BoxMesh" id="Mesh_sb_pole_high"]
material = SubResource("Material_ledge")
size = Vector3(0.3, 1.24, 0.3)

[sub_resource type="BoxShape3D" id="Shape_sb_rail"]
size = Vector3(0.1, 0.64, 1.5)

[sub_resource type="BoxMesh" id="Mesh_sb_rail"]
material = SubResource("Material_ledge")
size = Vector3(0.1, 0.64, 1.5)

[sub_resource type="BoxShape3D" id="Shape_sb_wall"]
size = Vector3(0.2, 1.24, 1.5)

[sub_resource type="BoxMesh" id="Mesh_sb_wall"]
material = SubResource("Material_ledge")
size = Vector3(0.2, 1.24, 1.5)

```

（注意箱子的 `size` 是 (深 x, 高, 宽 z)：通道沿 +X，所以"深"在 x。）

在文件末尾加节点。每个障碍都是 `StaticBody3D` + `Collision` + `Mesh` 三个节点，
模板如下，按表格换名字、形状、网格与 transform 的平移：

```
[node name="SpringGallery" type="StaticBody3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 28, 4.75, 0)

[node name="Collision" type="CollisionShape3D" parent="SpringGallery"]
shape = SubResource("Shape_gallery")

[node name="Mesh" type="MeshInstance3D" parent="SpringGallery"]
mesh = SubResource("Mesh_gallery")

[node name="SbBoxBoxLow" type="StaticBody3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 26.0, 5.32, -4.5)

[node name="Collision" type="CollisionShape3D" parent="SbBoxBoxLow"]
shape = SubResource("Shape_sb_box_low")

[node name="Mesh" type="MeshInstance3D" parent="SbBoxBoxLow"]
mesh = SubResource("Mesh_sb_box_low")
```

全部节点（名字 → 形状/网格 id 后缀 → 平移）：

| 节点名 | 形状/网格后缀 | 平移 (x, y, z) |
|---|---|---|
| `SbBoxBoxLow` | `sb_box_low` | (26.0, 5.32, -4.5) |
| `SbBoxBoxHigh` | `sb_box_high` | (27.12, 5.62, -4.5) |
| `SbBoxPoleLow` | `sb_box_low` | (26.0, 5.32, -1.5) |
| `SbBoxPoleHigh` | `sb_pole_high` | (26.77, 5.62, -1.5) |
| `SbPolePoleLow` | `sb_pole_low` | (25.65, 5.32, 1.5) |
| `SbPolePoleHigh` | `sb_pole_high` | (26.77, 5.62, 1.5) |
| `SbRailLow` | `sb_rail` | (25.55, 5.32, 4.5) |
| `SbRailHigh` | `sb_wall` | (26.72, 5.62, 4.5) |

- [ ] **Step 2: 用引擎加载验证场景**

Run: `./.engine/Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tools/check_references.gd`
Expected: 无错误。再跑一次课程探针确认柱子在：写临时脚本 `tools/_probe_spring.gd`（跑完删除）：

```gdscript
extends SceneTree
func _initialize() -> void:
	var level: Node = load("res://scenes/debug_levels/balance_course.tscn").instantiate()
	get_root().add_child(level)
	for i in 30:
		await physics_frame
	var player: Player = level.get_node("Player")
	var scripted := ScriptedInputSource.new()
	player.input_source = scripted
	# Lane by lane: the two boxes, box + pole, two poles, rail + wall.
	for lane_z in [-4.5, -1.5, 1.5, 4.5]:
		player.move_manager.start(Move.WALKING)
		player.global_position = Vector3(24.3, 5.95, lane_z)
		player.rotation.y = LineWalkMove.yaw_of(Vector3(1.0, 0.0, 0.0))
		player.velocity = Vector3.ZERO
		for i in 20:
			await physics_frame
		print("lane %.1f query: %s" % [lane_z, player.probes.springboard_query()])
		scripted.state.jump_pressed = true
		scripted.state.jump_held = true
		var seen: Array = []
		var last: StringName = &""
		for tick in 120:
			await physics_frame
			scripted.state.jump_pressed = false
			var now: StringName = player.move_manager.current_name
			if now != last:
				seen.append("%d:%s y=%.2f" % [tick, now, player.global_position.y])
				last = now
		print("lane %.1f: %s" % [lane_z, seen])
		scripted.state.jump_held = false
		for i in 60:
			await physics_frame
	quit()
```

Run: `./.engine/Godot_v4.7.1-stable_win64_console.exe --headless --fixed-fps 60 --path . -s res://tools/_probe_spring.gd`
Expected: 四条通道的 `query` 都为 valid，序列都形如 `["1:SpringBoard y=5.95", "~45:Falling y=~9.5"]`——顶点约在起跳点（6.24 + 0.9 = 7.14）之上 2.82 m。栏杆那条若探针漏掉薄板（0.1 m 厚 vs 球半径 0.12），把 `SbRailLow` 加厚到 0.15 再试，并把结论记到 spec 的已知空白。删除 `tools/_probe_spring.gd` 与 `.uid`。

- [ ] **Step 3: 全套测试**

Run: `bun tools/run_tests.ts`
Expected: 除既有 pending 的 `test_hand_ik.gd` 外全部 PASS，无 `SCRIPT ERROR`。

- [ ] **Step 4: 提交**

```bash
git add scenes/debug_levels/balance_course.tscn
git commit -m "feat(debug): a spring board gallery on the balance course -- boxes, poles, a rail"
```

- [ ] **Step 5: 实机验证（owner）**

第一/第三人称各跑一遍：正对、斜 40° 进入、蹬踏期扭头 180°；对照 spec 的录像数值看起跳高度与方向。手感值（`plant_arc_height`、`plant_arc_bias`、`plant_reach`）在 F1 面板调。
