# P1 滑铲与翻滚落地 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 加入滑铲与翻滚落地，并补上 P0 遗漏的落地扣速——让"速度难攒、易丢"这条核心规则第一次真正成立。

**Architecture:** 滑铲是状态机里的一个新状态 `SlideState`；翻滚落地不是状态，而是落地转移时的一个修饰。碰撞胶囊在滑铲时缩短，站起前用 `ShapeCast3D` 检查头顶净空。

**Tech Stack:** Godot 4.7.1-stable / GDScript / Jolt Physics / 既有的自制 headless 测试运行器

**Spec:** [`docs/superpowers/specs/2026-08-16-parkour-movement-prototype-design.md`](../specs/2026-08-16-parkour-movement-prototype-design.md)

**前置：** P0 全部完成（[`2026-08-16-p0-movement-foundation.md`](2026-08-16-p0-movement-foundation.md)）

## Global Constraints

沿用 P0 的全部约束，逐条重述以免遗漏：

- 引擎 Godot **4.7.1-stable**，调用 `.engine\Godot_v4.7.1-stable_win64_console.exe`（headless 必须用 `_console.exe` 变体才有 stdout）
- 语言 **GDScript**；渲染器锁定 **`gl_compatibility`**；物理 **60 Hz**；Jolt Physics
- 不引入任何第三方插件
- **无魔法数字**：状态与相机脚本中的每个手感数值都来自 `MovementConfig`
- 测试**只断言关系，不断言数值**；保持轻量，不追覆盖率
- 运行测试只用 `pwsh tools/run_tests.ps1`（内含 `--import`）
- 场景由 `tools/build_*.gd` 生成，不手工编辑
- 视觉验收用 `tools/capture.gd` 截图，由控制者读图判断

### 从 P0 继承的硬知识（不要重新试错）

1. **新增或改名 `class_name` 后必须先 `--headless --path . --import`**，否则解析失败报 `Identifier "Xxx" not declared`。
2. **`tests/` 下只有真正的 `TestCase` 子类才能以 `test_` 开头。** 夹具文件用别的前缀（现有的是 `tests/world_fixture.gd`，`class_name TestWorld`）。违反会让整个 headless 进程**挂死且无退出码**。
3. **`add_child()` 之后节点未立即入树**，一帧之后才能碰全局变换。
4. **打包场景时 `owner` 未设置的节点会被静默丢弃。** 实例化的子场景只设根节点的 `owner`。
5. **依赖方向单向：`Player` → 各状态 → `PlayerState`。** 状态脚本**不得引用 `Player` 类**（状态名常量在 `PlayerState` 上）。
6. `WorldEnvironment` 继承自 `Node` 而非 `Node3D`——生成器里的辅助函数签名要留意。
7. `capture.gd` 退出前必须释放实例，否则会留下孤儿窗口进程。

### P0 既有 API（直接使用，不要重写）

- `MovementConfig`：`walk_speed` `sprint_speed` `ground_accel` `ground_friction` `floor_snap_speed` `air_accel` `air_max_speed` `gravity` `terminal_velocity` `jump_velocity` `coyote_time` `jump_buffer_time` `mouse_sensitivity` `pitch_limit_deg` `fov_base` `fov_max` `fov_speed_ref` `fov_lerp_speed` `bob_frequency` `bob_amplitude` `bob_fade_speed` `land_dip_max` `land_dip_recover` `land_dip_speed_ref`
- `PlayerState`：常量 `KEEP` `GROUND` `AIR`；字段 `player`（无类型）、`config`；方法 `enter(previous)` `physics_update(delta, input) -> StringName` `exit()`
- `StateMachine`：`register(name, state)` `start(name)` `physics_update(delta, input)` `current_name`，信号 `state_changed(from, to)`
- `Player`：`config` `input_source` `state_machine` `last_landing_speed` `last_input`；`setup(cfg, src)` `wish_direction(input)` `horizontal_speed()` `ground_accelerate(wish_dir, target_speed, delta)` `air_accelerate(wish_dir, delta)` `consume_jump()`
- `CameraRig`：`setup(cfg)` `apply_look(look_delta, body)` `update_effects(delta, horizontal_speed, grounded)` `punch_landing(speed)`
- `MoveInput`：`move` `look` `jump_pressed` `jump_held` `sprint_held` `crouch_held`；`ScriptedInputSource` 有可写的 `state`
- `TestWorld`（`tests/world_fixture.gd`）：`build(tree, cfg)` `place(world)` `teardown(world)`
- `TestCase`：`tree` `check` `check_greater` `check_approx` `step(frames)`

---

## File Structure

| 文件 | 职责 |
| --- | --- |
| `scripts/player/movement_config.gd` | **修改**：新增 Landing 与 Slide 两个参数组 |
| `scripts/player/states/air_state.gd` | **修改**：落地时施加扣速或翻滚保速 |
| `scripts/player/states/ground_state.gd` | **修改**：满足条件时转入 Slide |
| `scripts/player/states/slide_state.gd` | 新增：滑铲状态 |
| `scripts/player/states/player_state.gd` | **修改**：新增 `SLIDE` 状态名常量 |
| `scripts/player/player.gd` | **修改**：注册 Slide；胶囊高度切换；头顶净空探测 |
| `scripts/camera/camera_rig.gd` | **修改**：滑铲时降低相机高度 |
| `tools/build_player_scene.gd` | **修改**：加入头顶净空 `ShapeCast3D` |
| `tools/build_main_scene.gd` | **修改**：加入东侧滑铲区 |
| `tests/test_landing.gd` | 落地扣速与翻滚保速 |
| `tests/test_slide_state.gd` | 滑铲进入、加速、衰减、退出、净空 |

---

## Task 1: 落地动量（扣速与翻滚保速）

P0 落地完全不扣速，这条是 spec 里"速度难攒、易丢"的核心，必须先补上——滑铲的价值也依赖它（滑铲攒的速度，落地时要能守住才有意义）。

**Files:**
- Modify: `scripts/player/movement_config.gd`
- Modify: `scripts/player/states/air_state.gd`
- Test: `tests/test_landing.gd`

**Interfaces:**
- Consumes: `MovementConfig`、`AirState`、`Player.horizontal_speed()`
- Produces: `MovementConfig` 新增 Landing 组；`AirState` 落地时改写水平速度；`Player.last_landing_rolled: bool` 供相机与 HUD 读取

- [ ] **Step 1: 写失败的测试**

创建 `tests/test_landing.gd`：

```gdscript
extends TestCase

# Landing is where the "speed is hard to earn, easy to lose" rule bites. These
# assert the ORDERING of outcomes, never the amounts, so tuning cannot break them.

func _airborne_world(cfg: MovementConfig, drop_height: float) -> Dictionary:
	var world := TestWorld.build(tree, cfg)
	await step(1)
	world["floor"].global_position = Vector3(0.0, -0.5, 0.0)
	world["player"].global_position = Vector3(0.0, drop_height, 0.0)
	await step(15)
	return world

## Runs the player up to speed on the ground, then drops it from `height` with
## crouch either held (roll) or not, and returns the horizontal speed on landing.
func _speed_after_drop(height: float, crouch: bool) -> float:
	var cfg := MovementConfig.new()
	var world := TestWorld.build(tree, cfg)
	await step(1)
	TestWorld.place(world)
	await step(15)

	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	input.state.move = Vector2(0.0, 1.0)
	input.state.sprint_held = true
	await step(90)

	# Lift the runner to the drop height without changing its horizontal motion.
	player.global_position = Vector3(player.global_position.x, height, player.global_position.z)
	await step(2)
	input.state.crouch_held = crouch

	for i in 400:
		await step(1)
		if player.state_machine.current_name == &"Ground":
			break
	var speed := player.horizontal_speed()
	TestWorld.teardown(world)
	await step(1)
	return speed

func test_a_plain_landing_costs_speed() -> void:
	await step(1)
	var cfg := MovementConfig.new()
	var world := TestWorld.build(tree, cfg)
	await step(1)
	TestWorld.place(world)
	await step(15)
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	input.state.move = Vector2(0.0, 1.0)
	input.state.sprint_held = true
	await step(90)
	var running_speed := player.horizontal_speed()

	player.global_position = Vector3(player.global_position.x, 12.0, player.global_position.z)
	for i in 400:
		await step(1)
		if player.state_machine.current_name == &"Ground":
			break
	check_greater(running_speed, player.horizontal_speed(), \
		"a plain landing from height must cost horizontal speed")
	TestWorld.teardown(world)
	await step(1)

func test_rolling_keeps_more_speed_than_a_plain_landing() -> void:
	await step(1)
	var plain := await _speed_after_drop(12.0, false)
	var rolled := await _speed_after_drop(12.0, true)
	check_greater(rolled, plain, "rolling must preserve more speed than landing flat")

func test_a_higher_fall_costs_more_speed() -> void:
	await step(1)
	var shallow := await _speed_after_drop(4.0, false)
	var deep := await _speed_after_drop(16.0, false)
	check_greater(shallow, deep, "a deeper fall must cost more speed than a shallow one")

func test_the_roll_flag_reports_which_landing_happened() -> void:
	await step(1)
	var cfg := MovementConfig.new()
	var world := await _airborne_world(cfg, 12.0)
	var player: Player = world["player"]
	world["input"].state.crouch_held = true
	for i in 400:
		await step(1)
		if player.state_machine.current_name == &"Ground":
			break
	check(player.last_landing_rolled, "a crouched landing from height should be flagged as a roll")
	TestWorld.teardown(world)
	await step(1)
```

- [ ] **Step 2: 运行测试确认失败**

Run: `pwsh tools/run_tests.ps1`
Expected: FAIL —— `last_landing_rolled` 未定义，且保速关系不成立。

- [ ] **Step 3: 加配置参数**

在 `scripts/player/movement_config.gd` 的 Camera 组**之前**插入：

```gdscript
@export_group("Landing")
## Fraction of horizontal speed kept after a flat landing at land_dip_speed_ref
## fall speed. Below that fall speed the loss scales down proportionally; this
## is the "speed is easy to lose" half of the momentum design.
@export var land_speed_keep: float = 0.55
## Same, but for a landing where the crouch key was held — the reward for
## knowing the roll is there.
@export var roll_speed_keep: float = 0.94
## Minimum fall speed at which crouching counts as a roll. Below it a crouched
## landing is just a landing, so tapping crouch constantly earns nothing.
@export var roll_min_fall_speed: float = 5.0
```

- [ ] **Step 4: 在 Player 上加状态字段**

`scripts/player/player.gd`，紧邻 `last_landing_speed` 声明：

```gdscript
## True when the most recent landing was a roll. Read by the camera and HUD.
var last_landing_rolled: bool = false
```

- [ ] **Step 5: 改写 AirState 的落地处理**

`scripts/player/states/air_state.gd` 中，把落地分支替换为：

```gdscript
	if player.is_on_floor():
		player.last_landing_speed = impact_speed
		_apply_landing_cost(impact_speed, input)
		return GROUND
	return KEEP

## Landing bleeds horizontal speed in proportion to how hard the impact was.
## Rolling — crouch held on a fast enough landing — bleeds far less. Neither
## path ever ADDS speed, so a landing can only ever cost momentum.
func _apply_landing_cost(impact_speed: float, input: MoveInput) -> void:
	var severity := clampf(impact_speed / maxf(config.land_dip_speed_ref, 0.001), 0.0, 1.0)
	var rolled: bool = input.crouch_held and impact_speed >= config.roll_min_fall_speed
	player.last_landing_rolled = rolled

	var keep_at_full: float = config.roll_speed_keep if rolled else config.land_speed_keep
	var keep := lerpf(1.0, keep_at_full, severity)
	player.velocity.x *= keep
	player.velocity.z *= keep
```

- [ ] **Step 6: 运行测试确认通过**

Run: `pwsh tools/run_tests.ps1`
Expected: PASS，`failures: 0`。

- [ ] **Step 7: 提交**

```bash
git add scripts/player/movement_config.gd scripts/player/player.gd scripts/player/states/air_state.gd tests/test_landing.gd
git commit -m "feat: bleed horizontal speed on landing, and reward rolling"
```

---

## Task 2: SlideState 核心

**Files:**
- Modify: `scripts/player/states/player_state.gd`（新增 `SLIDE` 常量）
- Modify: `scripts/player/movement_config.gd`（Slide 组）
- Modify: `scripts/player/player.gd`（注册状态、胶囊高度切换）
- Modify: `scripts/player/states/ground_state.gd`（转入 Slide）
- Create: `scripts/player/states/slide_state.gd`
- Test: `tests/test_slide_state.gd`

**Interfaces:**
- Consumes: 上列全部 P0 API
- Produces：
  - `PlayerState.SLIDE: StringName = &"Slide"`
  - `Player.set_capsule_height(height: float) -> void`、`Player.standing_height() -> float`
  - `SlideState extends PlayerState`

**关于胶囊缩放的实现约定（执行者必读）：** 身体原点保持不动，只移动 `CollisionShape3D` 的局部 `y`，让**胶囊底面始终位于原点下方 `standing_height * 0.5` 处**。公式：`shape.position.y = -(standing_height - current_height) * 0.5`。这样 `is_on_floor()` 与落点判定完全不受影响，测试也不必补偿身体位移。

- [ ] **Step 1: 写失败的测试**

创建 `tests/test_slide_state.gd`：

```gdscript
extends TestCase

func _running_world(cfg: MovementConfig) -> Dictionary:
	var world := TestWorld.build(tree, cfg)
	await step(1)
	TestWorld.place(world)
	await step(15)
	var input: ScriptedInputSource = world["input"]
	input.state.move = Vector2(0.0, 1.0)
	input.state.sprint_held = true
	await step(90)
	return world

func test_crouching_at_speed_enters_slide() -> void:
	await step(1)
	var cfg := MovementConfig.new()
	var world := await _running_world(cfg)
	var player: Player = world["player"]
	world["input"].state.crouch_held = true
	await step(2)
	check(player.state_machine.current_name == &"Slide", \
		"crouching while running should enter Slide, got %s" % player.state_machine.current_name)
	TestWorld.teardown(world)
	await step(1)

func test_slide_gives_a_one_time_speed_boost() -> void:
	await step(1)
	var cfg := MovementConfig.new()
	var world := await _running_world(cfg)
	var player: Player = world["player"]
	var before := player.horizontal_speed()
	world["input"].state.crouch_held = true
	await step(2)
	check_greater(player.horizontal_speed(), before, "entering a slide must add speed")
	TestWorld.teardown(world)
	await step(1)

func test_crouching_from_a_standstill_does_not_slide() -> void:
	await step(1)
	var cfg := MovementConfig.new()
	var world := TestWorld.build(tree, cfg)
	await step(1)
	TestWorld.place(world)
	await step(15)
	var player: Player = world["player"]
	world["input"].state.crouch_held = true
	await step(5)
	check(player.state_machine.current_name == &"Ground", \
		"a standing crouch must not start a slide")
	TestWorld.teardown(world)
	await step(1)

func test_slide_decays_and_returns_to_ground() -> void:
	await step(1)
	var cfg := MovementConfig.new()
	var world := await _running_world(cfg)
	var player: Player = world["player"]
	world["input"].state.crouch_held = true
	await step(2)
	check(player.state_machine.current_name == &"Slide", "precondition: should be sliding")

	# Hold crouch and let friction do its work.
	for i in 600:
		await step(1)
		if player.state_machine.current_name == &"Ground":
			break
	check(player.state_machine.current_name == &"Ground", \
		"a slide must eventually decay back to Ground")
	TestWorld.teardown(world)
	await step(1)

func test_releasing_crouch_ends_the_slide() -> void:
	await step(1)
	var cfg := MovementConfig.new()
	var world := await _running_world(cfg)
	var player: Player = world["player"]
	world["input"].state.crouch_held = true
	await step(2)
	world["input"].state.crouch_held = false
	await step(5)
	check(player.state_machine.current_name == &"Ground", \
		"releasing crouch should end the slide")
	TestWorld.teardown(world)
	await step(1)

func test_the_capsule_is_shorter_while_sliding() -> void:
	await step(1)
	var cfg := MovementConfig.new()
	var world := await _running_world(cfg)
	var player: Player = world["player"]
	var shape := (player.get_node("CollisionShape3D") as CollisionShape3D).shape as CapsuleShape3D
	var standing := shape.height
	world["input"].state.crouch_held = true
	await step(2)
	check_greater(standing, shape.height, "the capsule must shrink while sliding")

	world["input"].state.crouch_held = false
	await step(10)
	check_approx(shape.height, standing, 0.001, "the capsule must return to standing height")
	TestWorld.teardown(world)
	await step(1)

func test_the_capsule_bottom_does_not_move_when_shrinking() -> void:
	await step(1)
	var cfg := MovementConfig.new()
	var world := await _running_world(cfg)
	var player: Player = world["player"]
	var shape_node := player.get_node("CollisionShape3D") as CollisionShape3D
	var shape := shape_node.shape as CapsuleShape3D

	var bottom_before := shape_node.position.y - shape.height * 0.5
	world["input"].state.crouch_held = true
	await step(2)
	var bottom_after := shape_node.position.y - shape.height * 0.5
	check_approx(bottom_after, bottom_before, 0.001, \
		"shrinking the capsule must keep its bottom in place, or footing shifts")
	TestWorld.teardown(world)
	await step(1)

func test_sliding_off_an_edge_enters_air() -> void:
	await step(1)
	var cfg := MovementConfig.new()
	var world := await _running_world(cfg)
	var player: Player = world["player"]
	world["input"].state.crouch_held = true
	await step(2)
	check(player.state_machine.current_name == &"Slide", "precondition: should be sliding")

	# Remove the floor from under the slide.
	world["floor"].global_position = Vector3(0.0, -80.0, 0.0)
	await step(5)
	check(player.state_machine.current_name == &"Air", \
		"leaving the ground mid-slide must enter Air")
	TestWorld.teardown(world)
	await step(1)
```

- [ ] **Step 2: 运行测试确认失败**

Run: `pwsh tools/run_tests.ps1`
Expected: FAIL —— 状态永远停在 `Ground`。

- [ ] **Step 3: 加状态名常量**

`scripts/player/states/player_state.gd`，紧随 `AIR`：

```gdscript
const SLIDE: StringName = &"Slide"
```

- [ ] **Step 4: 加配置参数**

`scripts/player/movement_config.gd`，在 Landing 组之后插入：

```gdscript
@export_group("Slide")
## Minimum horizontal speed required to start a slide. Below it, crouching just
## crouches — a slide has to be earned with speed already on the clock.
@export var slide_entry_speed: float = 4.0
## One-off speed added on entering a slide. This is the payoff that makes
## sliding worth doing rather than just running.
@export var slide_boost: float = 2.5
## Deceleration while sliding, in m/s^2. Well below ground_friction, which is
## what makes a slide carry.
@export var slide_friction: float = 5.0
## Sliding ends when speed decays to this.
@export var slide_exit_speed: float = 2.0
## Hard cap on slide duration so a slide cannot be held indefinitely on a slope.
@export var slide_max_duration: float = 1.8
## Capsule height while sliding.
@export var slide_capsule_height: float = 0.9
## How fast the slide direction can be steered, in radians per second. Low on
## purpose: a slide commits you to a line.
@export var slide_steer_rate: float = 1.2
```

- [ ] **Step 5: 加 Player 的胶囊控制**

`scripts/player/player.gd`：

```gdscript
@onready var _collision_shape: CollisionShape3D = $CollisionShape3D

var _standing_height: float = 0.0

func standing_height() -> float:
	return _standing_height

## Resizes the capsule while keeping its BOTTOM fixed relative to the body
## origin, so footing and is_on_floor() are unaffected by the change.
func set_capsule_height(height: float) -> void:
	var capsule := _collision_shape.shape as CapsuleShape3D
	if capsule == null:
		return
	if _standing_height <= 0.0:
		_standing_height = capsule.height
	capsule.height = height
	_collision_shape.position.y = -(_standing_height - height) * 0.5
```

在 `setup()` 中取得一份**私有的**胶囊并记录站立高度（放在 `_build_state_machine()` 之前）：

```gdscript
	# The capsule resource is shared by every instance of player.tscn, so
	# resizing it in place would let one player's slide shrink every other
	# player in the scene — including, in tests, worlds from previous cases.
	var shape_node := $CollisionShape3D as CollisionShape3D
	var capsule := shape_node.shape as CapsuleShape3D
	if capsule != null:
		var owned := capsule.duplicate() as CapsuleShape3D
		shape_node.shape = owned
		_standing_height = owned.height
```

在 `_build_state_machine()` 中注册 Slide：

```gdscript
	var slide := SlideState.new()
	slide.player = self
	slide.config = config
	state_machine.add_child(slide)
	state_machine.register(PlayerState.SLIDE, slide)
```

- [ ] **Step 6: 写 SlideState**

创建 `scripts/player/states/slide_state.gd`：

```gdscript
class_name SlideState
extends PlayerState

# A slide is a commitment: it buys speed up front, steers poorly, and ends on
# its own terms. Everything about it is tuned to make the player choose WHERE
# to slide rather than sliding constantly.

var _elapsed: float = 0.0
var _direction: Vector3 = Vector3.ZERO

func enter(_previous: StringName) -> void:
	_elapsed = 0.0
	var horizontal := Vector3(player.velocity.x, 0.0, player.velocity.z)
	_direction = horizontal.normalized() if horizontal.length_squared() > 0.0001 else Vector3.ZERO

	# The boost is applied once, on entry — never per tick.
	var boosted := horizontal.length() + config.slide_boost
	player.velocity.x = _direction.x * boosted
	player.velocity.z = _direction.z * boosted

	player.set_capsule_height(config.slide_capsule_height)

func exit() -> void:
	player.set_capsule_height(player.standing_height())

func physics_update(delta: float, input: MoveInput) -> StringName:
	_elapsed += delta

	# Steering is deliberately slow: a slide commits you to a line.
	var wish_dir: Vector3 = player.wish_direction(input)
	if wish_dir != Vector3.ZERO and _direction != Vector3.ZERO:
		var max_turn := config.slide_steer_rate * delta
		var angle := _direction.signed_angle_to(wish_dir, Vector3.UP)
		_direction = _direction.rotated(Vector3.UP, clampf(angle, -max_turn, max_turn))

	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	speed = maxf(speed - config.slide_friction * delta, 0.0)
	player.velocity.x = _direction.x * speed
	player.velocity.z = _direction.z * speed

	if player.consume_jump():
		player.velocity.y = config.jump_velocity
		player.move_and_slide()
		return AIR

	player.velocity.y = -config.floor_snap_speed
	player.move_and_slide()

	if not player.is_on_floor():
		player.velocity.y = 0.0
		return AIR
	if not input.crouch_held:
		return GROUND
	if speed <= config.slide_exit_speed:
		return GROUND
	if _elapsed >= config.slide_max_duration:
		return GROUND
	return KEEP
```

- [ ] **Step 7: 让 GroundState 能转入 Slide**

`scripts/player/states/ground_state.gd`，在跳跃判定**之后**、贴地偏置**之前**插入：

```gdscript
	# A slide has to be earned: crouching below the entry speed just crouches.
	if input.crouch_held and player.horizontal_speed() >= config.slide_entry_speed:
		return SLIDE
```

- [ ] **Step 8: 运行测试确认通过**

Run: `pwsh tools/run_tests.ps1`
Expected: PASS，`failures: 0`。

- [ ] **Step 9: 提交**

```bash
git add scripts/player/ tests/test_slide_state.gd
git commit -m "feat: add slide state with an entry boost and committed steering"
```

---

## Task 3: 头顶净空与相机下沉

滑铲结束时若头顶有障碍物，玩家不应该站起来穿模。相机也要跟着滑铲下沉，否则视点会穿出低矮通道的顶板。

**Files:**
- Modify: `tools/build_player_scene.gd`（加 `ShapeCast3D`）
- Modify: `scripts/player/player.gd`（净空查询）
- Modify: `scripts/player/states/slide_state.gd`（受阻则不退出）
- Modify: `scripts/player/movement_config.gd`（相机下沉参数）
- Modify: `scripts/camera/camera_rig.gd`（滑铲时降低相机）
- Test: 追加到 `tests/test_slide_state.gd`

**Interfaces:**
- Produces：`Player.has_headroom() -> bool`；`CameraRig.set_crouch_amount(amount: float)`

- [ ] **Step 1: 写失败的测试**

追加到 `tests/test_slide_state.gd`：

```gdscript
func test_a_low_ceiling_keeps_the_player_sliding() -> void:
	await step(1)
	var cfg := MovementConfig.new()
	var world := await _running_world(cfg)
	var player: Player = world["player"]
	world["input"].state.crouch_held = true
	await step(2)
	check(player.state_machine.current_name == &"Slide", "precondition: should be sliding")

	# Drop a slab just above the sliding capsule, across the player's path.
	var ceiling := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 0.5, 40.0)
	shape.shape = box
	ceiling.add_child(shape)
	tree.root.add_child(ceiling)
	await step(1)
	ceiling.global_position = player.global_position + Vector3(0.0, 0.45, 0.0)
	await step(1)

	world["input"].state.crouch_held = false
	await step(10)
	check(player.state_machine.current_name == &"Slide", \
		"the player must not stand up into a ceiling, got %s" % player.state_machine.current_name)

	ceiling.queue_free()
	await step(2)
	await step(20)
	check(player.state_machine.current_name == &"Ground", \
		"once the ceiling is gone the player should stand up")

	TestWorld.teardown(world)
	await step(1)

func test_the_camera_drops_while_sliding() -> void:
	await step(1)
	var cfg := MovementConfig.new()
	var world := await _running_world(cfg)
	var player: Player = world["player"]
	var rig: CameraRig = player.get_node("CameraRig")
	var standing_y := rig.position.y

	world["input"].state.crouch_held = true
	await step(20)
	check(rig.position.y < standing_y, "the camera must drop while sliding")

	world["input"].state.crouch_held = false
	await step(60)
	check_approx(rig.position.y, standing_y, 0.01, "the camera must rise back after the slide")
	TestWorld.teardown(world)
	await step(1)
```

- [ ] **Step 2: 运行测试确认失败**

Run: `pwsh tools/run_tests.ps1`
Expected: FAIL —— 玩家会直接站进天花板；相机高度不变。

- [ ] **Step 3: 生成器加入净空探测**

`tools/build_player_scene.gd`，在 `BodyRoot` 之后、赋值 `camera_rig` 之前：

```gdscript
	# Standing-clearance probe: a capsule the size of the STANDING body, tested
	# in place. A ray would miss geometry the capsule's radius would hit.
	var clearance := ShapeCast3D.new()
	clearance.name = "StandClearance"
	var probe_shape := CapsuleShape3D.new()
	probe_shape.height = 1.8
	probe_shape.radius = 0.4
	clearance.shape = probe_shape
	clearance.target_position = Vector3.ZERO
	clearance.enabled = true
	player.add_child(clearance)
	clearance.owner = player
```

运行生成器重建 `player.tscn`（先 `--import`）。

- [ ] **Step 4: Player 暴露净空查询**

`scripts/player/player.gd`：

```gdscript
@onready var _stand_clearance: ShapeCast3D = get_node_or_null("StandClearance")

## True when the standing-size capsule fits where the body currently is.
## Tests that build a Player by hand have no probe node, so absence means yes.
func has_headroom() -> bool:
	if _stand_clearance == null:
		return true
	_stand_clearance.force_shapecast_update()
	return not _stand_clearance.is_colliding()
```

- [ ] **Step 5: SlideState 受阻则不退出**

把 `slide_state.gd` 结尾**三处返回 `GROUND` 的分支**统一替换为一道净空闸门。**保留前面的 `is_on_floor()` 转 `AIR` 判定不动**——离地时应当直接进入空中，不受净空影响：

```gdscript
	if not player.is_on_floor():
		player.velocity.y = 0.0
		return AIR

	# Every exit to standing passes the same gate: crouch-release, speed decay
	# and timeout alike. Stand up into a ceiling once and the body clips
	# through it, so a blocked slide simply continues.
	var wants_to_stand := (not input.crouch_held) \
		or speed <= config.slide_exit_speed \
		or _elapsed >= config.slide_max_duration
	if wants_to_stand and player.has_headroom():
		return GROUND
	return KEEP
```

**已知边界情况（原型阶段接受）：** 滑铲直接转入 `AIR` 时，`exit()` 会无条件恢复站立高度而不检查净空。在低矮通道里滑出边缘的瞬间理论上可能穿模。靶场里不存在这种几何组合，留待后续阶段处理。

- [ ] **Step 6: 相机下沉**

`movement_config.gd` 的 Camera 组追加：

```gdscript
## How far the camera drops while sliding, in metres.
@export var slide_camera_drop: float = 0.45
## How fast the camera moves between standing and sliding height.
@export var crouch_lerp_speed: float = 9.0
```

`camera_rig.gd` 新增：

```gdscript
var _crouch_amount: float = 0.0
var _rest_height: float = 0.0

## 0 = standing, 1 = fully crouched. Driven by Player each tick.
func set_crouch_amount(amount: float) -> void:
	_crouch_amount = clampf(amount, 0.0, 1.0)
```

在 `setup()` 中记录静止高度：

```gdscript
	_rest_height = position.y
```

在 `update_effects()` 末尾追加：

```gdscript
	var target_height := _rest_height - _config.slide_camera_drop * _crouch_amount
	position.y = move_toward(position.y, target_height, _config.crouch_lerp_speed * delta)
```

`player.gd` 的 `_physics_process` 中，在调用 `camera_rig.update_effects(...)` 之前：

```gdscript
	if camera_rig != null:
		camera_rig.set_crouch_amount(1.0 if state_machine.current_name == PlayerState.SLIDE else 0.0)
```

- [ ] **Step 7: 运行测试确认通过**

Run: `pwsh tools/run_tests.ps1`
Expected: PASS，`failures: 0`。

- [ ] **Step 8: 提交**

```bash
git add scripts/ tools/build_player_scene.gd scenes/player/player.tscn tests/test_slide_state.gd
git commit -m "feat: block standing under ceilings and drop the camera while sliding"
```

---

## Task 4: 靶场滑铲区

**Files:**
- Modify: `tools/build_main_scene.gd`
- Test: 追加到 `tests/test_arena.gd`

东侧滑铲区（`Node3D` 名为 `SlideArea`，`position = (14, 0, 0)`），全部沿用生成器里既有的 `_box()` 辅助函数与颜色约定：

| 名称 | size | position | 用途 |
| --- | --- | --- | --- |
| `RampUp` | `(6, 1, 10)` | `(0, 1.2, -6)`，绕 X 轴旋转 `-12°` | 下坡，测滑铲加速 |
| `TunnelFloor` | `(6, 1, 14)` | `(0, 0.5, -18)` | 通道地面 |
| `TunnelRoof` | `(6, 1, 14)` | `(0, 2.1, -18)` | 只有滑铲能通过的顶板 |
| `TunnelWallL` | `(1, 3, 14)` | `(-3.5, 1.5, -18)` | 侧墙 |
| `TunnelWallR` | `(1, 3, 14)` | `(3.5, 1.5, -18)` | 侧墙 |
| `Runway` | `(6, 1, 20)` | `(0, 0.5, -35)` | 出口跑道，测滑铲出口速度 |

顶板底面在 `y = 1.6`，通道地面顶面在 `y = 1.0`，净高 0.6 m——站立胶囊（1.8 m）过不去，滑铲胶囊（0.9 m）可以。

- [ ] **Step 1: 写失败的测试**

追加到 `tests/test_arena.gd`：

```gdscript
func test_the_slide_area_exists_and_is_low_enough_to_require_sliding() -> void:
	await step(1)
	var arena = await _load_arena()
	var roof = arena.get_node_or_null("SlideArea/TunnelRoof")
	var floor_node = arena.get_node_or_null("SlideArea/TunnelFloor")
	check(roof != null, "the slide tunnel roof is missing")
	check(floor_node != null, "the slide tunnel floor is missing")

	var roof_box := ((roof.get_node("Collision") as CollisionShape3D).shape as BoxShape3D)
	var floor_box := ((floor_node.get_node("Collision") as CollisionShape3D).shape as BoxShape3D)
	var clearance: float = (roof.position.y - roof_box.size.y * 0.5) \
		- (floor_node.position.y + floor_box.size.y * 0.5)

	# The tunnel only earns its place if standing cannot fit and sliding can.
	check(clearance < arena.config.slide_capsule_height + 0.4, \
		"the tunnel is too tall to require a slide (clearance %f)" % clearance)
	check_greater(clearance, arena.config.slide_capsule_height * 0.5, \
		"the tunnel is too short for even a slide to pass")

	arena.queue_free()
	await step(1)
```

- [ ] **Step 2: 运行测试确认失败**

Run: `pwsh tools/run_tests.ps1`
Expected: FAIL —— `SlideArea` 不存在。

- [ ] **Step 3: 生成器加入滑铲区**

按上表在 `tools/build_main_scene.gd` 中构造 `SlideArea`，紧随 `JumpArea` 之后。`RampUp` 需要旋转，因此不能直接用 `_box()` 的返回值——先取得节点再设 `rotation.x = deg_to_rad(-12.0)`。

重新生成主场景（先 `--import`）。

- [ ] **Step 4: 运行测试确认通过**

Run: `pwsh tools/run_tests.ps1`
Expected: PASS，`failures: 0`。

- [ ] **Step 5: 截图验收**

```powershell
.\.engine\Godot_v4.7.1-stable_win64_console.exe --path . --resolution 960x540 --script res://tools/capture.gd -- res://scenes/main.tscn res://.captures/p1_arena.png 120
```

报告中给出 PNG 路径。控制者会实际查看，确认滑铲区的坡道、通道与跑道渲染正常且位置合理。

- [ ] **Step 6: 提交**

```bash
git add tools/build_main_scene.gd scenes/main.tscn tests/test_arena.gd
git commit -m "feat: add the slide practice area to the arena"
```

---

## P1 完成标准

**自动可验证：**

- [ ] `pwsh tools/run_tests.ps1` 通过，退出码 0
- [ ] 普通落地扣速，落差越大扣得越多
- [ ] 翻滚落地比普通落地保住更多速度
- [ ] 满速下蹲进入滑铲并获得一次性加速；静止下蹲不进入滑铲
- [ ] 滑铲会衰减并回到 Ground；松开蹲键提前结束；滑出边缘进入 Air
- [ ] 滑铲时胶囊变矮，且**底面不动**
- [ ] 头顶有障碍时不会站起来；障碍移除后恢复站立
- [ ] 滑铲时相机下沉，结束后回升
- [ ] 靶场滑铲通道的净高确实只允许滑铲通过
- [ ] 靶场截图渲染正常

**留待使用者确认：**

- [ ] 滑铲的加速量与持续时间是否手感合适
- [ ] 转向限制是否过紧或过松
- [ ] 落地扣速的比例是否合理——这是"速度难攒易丢"最直接的旋钮
- [ ] 翻滚的收益是否值得刻意去用
