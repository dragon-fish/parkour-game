# P2 翻越与抓边缘 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 加入翻越齐腰障碍与抓住平台边缘攀上，把"跳不上去就摔下来"的挫败感换成"差一点也能救回来"。

**Architecture:** 两者都是**脚本化位移状态**——进入时根据探测射线算出一条固定路径，在固定时长内插值走完，期间不受物理驱动。这是镜之边缘、Dying Light、Titanfall 的共同做法：让世界配合动作，而不是让动作去够世界。

**Tech Stack:** Godot 4.7.1-stable / GDScript / Jolt Physics / 既有的自制 headless 测试运行器

**Spec:** [`docs/superpowers/specs/2026-08-16-parkour-movement-prototype-design.md`](../specs/2026-08-16-parkour-movement-prototype-design.md)

**前置：** P0 与 P1 全部完成

## Global Constraints

沿用 P0/P1 全部约束：

- 引擎 Godot **4.7.1-stable**，headless 用 `.engine\Godot_v4.7.1-stable_win64_console.exe`
- **GDScript**；渲染器锁定 **`gl_compatibility`**；物理 **60 Hz**；Jolt Physics；无第三方插件
- **无魔法数字**：所有手感数值来自 `MovementConfig`
- 测试**只断言关系，不断言数值**；保持轻量
- 测试只用 `pwsh tools/run_tests.ps1`（内含 `--import`）
- 场景由 `tools/build_*.gd` 生成
- 视觉验收用 `tools/capture.gd`，控制者读图

### 累积的硬知识（不要重新试错）

1. 新增/改名 `class_name` 后必须先 `--import`，否则解析失败。
2. `tests/` 下只有真正的 `TestCase` 子类才能用 `test_` 前缀；违反会让进程挂死无退出码。运行器已在每个测试文件之间清理 `root` 的遗留子节点。
3. `add_child()` 之后节点未立即入树，一帧后才能碰全局变换。
4. 打包场景时 `owner` 未设置的节点会被静默丢弃；实例化子场景只设根节点 `owner`。
5. **依赖方向单向：`Player` → 各状态 → `PlayerState`。** 状态脚本不得引用 `Player` 类。
6. `WorldEnvironment` 继承自 `Node` 而非 `Node3D`。
7. `capture.gd` 退出前必须释放实例。
8. **`CapsuleShape3D` 是共享资源**，`Player.setup()` 已改为持有自己的副本。
9. **UI 控件回写配置要用 `set_value_no_signal()`**，否则 `value_changed` 会把量化后的值写回，静默篡改参数。

### P0/P1 既有 API

- `PlayerState`：常量 `KEEP` `GROUND` `AIR` `SLIDE`
- `Player`：`setup` `wish_direction` `horizontal_speed` `ground_accelerate` `air_accelerate` `consume_jump` `set_capsule_height` `standing_height` `has_headroom` `last_landing_speed` `last_landing_rolled`
- `CameraRig`：`setup` `apply_look` `update_effects` `punch_landing` `set_crouch_amount`
- `TestWorld`（`tests/world_fixture.gd`）：`build(tree, cfg)` `place(world)` `teardown(world)`
- 玩家场景已有节点：`CollisionShape3D`、`CameraRig/Camera3D`、`BodyRoot`、`StandClearance`（ShapeCast3D）

---

## File Structure

| 文件 | 职责 |
| --- | --- |
| `scripts/player/states/scripted_move.gd` | 新增：脚本化位移的共享基类 |
| `scripts/player/states/vault_state.gd` | 新增：翻越 |
| `scripts/player/states/ledge_hang_state.gd` | 新增：悬挂与攀上 |
| `scripts/player/states/player_state.gd` | **修改**：新增 `VAULT`、`LEDGE` 常量 |
| `scripts/player/movement_config.gd` | **修改**：Vault 与 Ledge 两个参数组 |
| `scripts/player/probes.gd` | 新增：探测射线的封装与查询 |
| `scripts/player/player.gd` | **修改**：注册新状态、暴露探测结果 |
| `scripts/player/states/ground_state.gd` | **修改**：转入 Vault |
| `scripts/player/states/air_state.gd` | **修改**：转入 LedgeHang |
| `tools/build_player_scene.gd` | **修改**：加入探测射线节点 |
| `tools/build_main_scene.gd` | **修改**：西侧翻越/抓边区 |
| `tests/test_probes.gd` | 探测射线的几何判定 |
| `tests/test_vault.gd` | 翻越 |
| `tests/test_ledge.gd` | 抓边缘与攀上 |

---

## Task 0: 把着地判定从 `is_on_floor()` 收归状态机

**必须先做这一步，否则本阶段的两个状态都会静默出错。**

P0 的最终整分支审查标出了这个隐患：`is_on_floor()` 是目前唯一的着地判定来源，而它**只在 `move_and_slide()` 被调用时刷新**。P2 引入的脚本化位移状态直接写 `global_position`、完全不调用 `move_and_slide()`，于是在翻越或攀爬期间：

- `Player._tick_timers()` 读到陈旧的"在地面上"，**coyote time 被错误续期**，攀爬途中可以凭空起跳
- 相机的步频晃动以为还在跑，**继续累积相位**
- 退出脚本化位移时，`was_airborne` 的边缘检测可能触发 `punch_landing()`，用一个**过期的落地速度**打出一次不该有的相机下沉

**Files:**
- Modify: `scripts/player/player.gd`
- Modify: `scripts/player/states/ground_state.gd`、`air_state.gd`、`slide_state.gd`
- Test: `tests/test_grounded_oracle.gd`

**Interfaces:**
- Produces：
  - `Player.grounded: bool` —— 由状态每帧显式声明，取代对 `is_on_floor()` 的直接读取
  - `Player.set_grounded(value: bool) -> void`
  - `Player.notify_landed(impact_speed: float) -> void` —— 落地事件由状态主动上报，且只消费一次
  - `Player.consume_landing() -> float` —— 返回本帧的落地冲击速度，无落地则返回 `-1.0`

- [ ] **Step 1: 写失败的测试**

创建 `tests/test_grounded_oracle.gd`：

```gdscript
extends TestCase

# The grounded flag must be something states DECLARE, not something inferred
# from a physics call that a scripted-move state never makes.

func _spawn() -> Dictionary:
	var cfg := MovementConfig.new()
	var world := TestWorld.build(tree, cfg)
	await step(1)
	TestWorld.place(world)
	await step(15)
	return world

func test_grounded_tracks_the_ground_state() -> void:
	var world := await _spawn()
	var player: Player = world["player"]
	check(player.grounded, "a resting player should be grounded")

	world["input"].press_jump()
	await step(4)
	check(not player.grounded, "a jumping player should not be grounded")

	for i in 300:
		await step(1)
		if player.state_machine.current_name == &"Ground":
			break
	check(player.grounded, "a landed player should be grounded again")

	TestWorld.teardown(world)
	await step(1)

func test_a_landing_is_reported_exactly_once() -> void:
	var world := await _spawn()
	var player: Player = world["player"]

	world["input"].press_jump()
	await step(4)
	world["input"].release_jump()

	var landings := 0
	for i in 300:
		await step(1)
		if player.last_landing_speed > 0.0 and player.state_machine.current_name == &"Ground":
			landings += 1
			break
	check(landings == 1, "the landing should be reported exactly once")

	# Sitting on the ground must not keep re-reporting a landing.
	await step(60)
	check(player.consume_landing() < 0.0, \
		"resting on the ground must not report further landings")

	TestWorld.teardown(world)
	await step(1)
```

- [ ] **Step 2: 运行测试确认失败**

- [ ] **Step 3: 实现**

`scripts/player/player.gd`：

```gdscript
## Whether the player is standing on something. DECLARED by the active state
## rather than read from is_on_floor(), because scripted-move states drive the
## body's position directly and never call move_and_slide() — is_on_floor()
## would report whatever was true before the move began.
var grounded: bool = false

var _pending_landing: float = -1.0

func set_grounded(value: bool) -> void:
	grounded = value

## Reported by a state at the moment it detects a landing.
func notify_landed(impact_speed: float) -> void:
	_pending_landing = impact_speed
	last_landing_speed = impact_speed

## Returns this tick's landing impact speed, or -1.0 if there was none. The
## event is consumed, so a landing can only ever be acted on once.
func consume_landing() -> float:
	var value := _pending_landing
	_pending_landing = -1.0
	return value
```

把 `player.gd` 里所有对 `is_on_floor()` 的判断改为读 `grounded`：

- `_tick_timers()` 的 coyote 续期
- 相机的 `update_effects(delta, horizontal_speed(), grounded)`
- 落地下沉改为由 `consume_landing()` 驱动，删掉原先的 `was_airborne` 边缘检测

各状态在自己的 `physics_update()` 中声明：

- `GroundState`：`move_and_slide()` 之后 `player.set_grounded(player.is_on_floor())`
- `SlideState`：同上
- `AirState`：落地时 `player.set_grounded(true)` 并 `player.notify_landed(impact_speed)`；否则 `player.set_grounded(false)`

本阶段随后新增的 `VaultState` 与 `LedgeHangState` 必须在 `enter()` 中 `player.set_grounded(false)`，并在结束时按落点声明。

- [ ] **Step 4: 运行测试确认通过并提交**

```bash
git add scripts/player/ tests/test_grounded_oracle.gd
git commit -m "refactor: let states declare grounded-ness instead of inferring it"
```

---

## Task 1: 探测射线

翻越与抓边缘的全部判定都建立在探测结果上，所以先把它做对、单独测好，后面两个状态才有可靠地基。

**Files:**
- Create: `scripts/player/probes.gd`
- Modify: `tools/build_player_scene.gd`
- Modify: `scripts/player/player.gd`
- Test: `tests/test_probes.gd`

**Interfaces:**
- Produces:
  - `class_name Probes extends Node3D`
  - `Probes.setup(cfg: MovementConfig, foot_offset: float) -> void`
  - `Probes.vault_query() -> Dictionary` → `{"valid": bool, "top": Vector3, "normal": Vector3}`
  - `Probes.ledge_query() -> Dictionary` → `{"valid": bool, "edge": Vector3, "normal": Vector3}`
  - `Player.probes: Probes`（`@export`，由生成器接线）

**几何约定（执行者必读）：** 玩家身体原点位于胶囊中心，站立时脚底在原点下方 `standing_height * 0.5`（0.9 m）。所有探测高度都以**脚底**为基准描述，代码里换算成相对原点的偏移。

- [ ] **Step 1: 写失败的测试**

创建 `tests/test_probes.gd`：

```gdscript
extends TestCase

# The probes are the foundation both P2 states stand on, so they are tested
# against real geometry rather than mocked.

func _world_with_obstacle(height: float, distance: float) -> Dictionary:
	var cfg := MovementConfig.new()
	var world := TestWorld.build(tree, cfg)
	await step(1)
	TestWorld.place(world)
	await step(15)

	var obstacle := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, height, 2.0)
	shape.shape = box
	obstacle.add_child(shape)
	tree.root.add_child(obstacle)
	await step(1)
	# Player faces -Z by default; put the obstacle in front of it.
	obstacle.global_position = Vector3(0.0, height * 0.5, -distance)
	await step(2)
	world["obstacle"] = obstacle
	return world

func test_a_waist_high_obstacle_is_vaultable() -> void:
	await step(1)
	var world := await _world_with_obstacle(1.0, 1.2)
	var player: Player = world["player"]
	var query: Dictionary = player.probes.vault_query()
	check(query["valid"], "a 1.0 m obstacle at 1.2 m should be vaultable")
	check_approx(query["top"].y, 1.0, 0.15, "the reported top surface should match the obstacle")
	world["obstacle"].queue_free()
	TestWorld.teardown(world)
	await step(1)

func test_a_tall_wall_is_not_vaultable() -> void:
	await step(1)
	var world := await _world_with_obstacle(3.0, 1.2)
	var player: Player = world["player"]
	check(not player.probes.vault_query()["valid"], \
		"a 3 m wall must not report as vaultable")
	world["obstacle"].queue_free()
	TestWorld.teardown(world)
	await step(1)

func test_nothing_ahead_is_not_vaultable() -> void:
	await step(1)
	var cfg := MovementConfig.new()
	var world := TestWorld.build(tree, cfg)
	await step(1)
	TestWorld.place(world)
	await step(15)
	var player: Player = world["player"]
	check(not player.probes.vault_query()["valid"], "empty space must not report as vaultable")
	TestWorld.teardown(world)
	await step(1)

func test_a_reachable_ledge_is_detected() -> void:
	await step(1)
	var cfg := MovementConfig.new()
	var world := TestWorld.build(tree, cfg)
	await step(1)
	TestWorld.place(world)
	await step(15)

	# A tall block whose top is just above the player's head.
	var block := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, 2.6, 2.0)
	shape.shape = box
	block.add_child(shape)
	tree.root.add_child(block)
	await step(1)
	block.global_position = Vector3(0.0, 1.3, -1.1)
	await step(2)

	var player: Player = world["player"]
	var query: Dictionary = player.probes.ledge_query()
	check(query["valid"], "a ledge at head height should be detected")
	check_approx(query["edge"].y, 2.6, 0.15, "the reported edge height should match the block top")

	block.queue_free()
	TestWorld.teardown(world)
	await step(1)

func test_a_ledge_far_above_reach_is_not_detected() -> void:
	await step(1)
	var cfg := MovementConfig.new()
	var world := TestWorld.build(tree, cfg)
	await step(1)
	TestWorld.place(world)
	await step(15)

	var block := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, 8.0, 2.0)
	shape.shape = box
	block.add_child(shape)
	tree.root.add_child(block)
	await step(1)
	block.global_position = Vector3(0.0, 4.0, -1.1)
	await step(2)

	var player: Player = world["player"]
	check(not player.probes.ledge_query()["valid"], \
		"an 8 m wall offers no reachable ledge")

	block.queue_free()
	TestWorld.teardown(world)
	await step(1)
```

- [ ] **Step 2: 运行测试确认失败**

Run: `pwsh tools/run_tests.ps1`
Expected: FAIL —— `Probes` 未定义。

- [ ] **Step 3: 加配置参数**

`scripts/player/movement_config.gd`，在 Slide 组之后：

```gdscript
@export_group("Vault")
## Highest obstacle top, measured from the player's feet, that can be vaulted.
@export var vault_max_height: float = 1.3
## How far ahead of the body the vault probe reaches.
@export var vault_reach: float = 1.4
## Minimum horizontal speed required to vault. Vaulting from a standstill would
## turn every waist-high box into a free elevator.
@export var vault_min_speed: float = 2.5

@export_group("Ledge")
## Lowest and highest ledge tops, measured from the player's feet, that can be
## grabbed. The lower bound keeps low ledges going through Vault instead.
@export var ledge_min_height: float = 1.4
@export var ledge_max_height: float = 2.8
## How far ahead of the body a ledge can be reached.
@export var ledge_reach: float = 1.0
```

- [ ] **Step 4: 生成器加入探测节点**

`tools/build_player_scene.gd`，在 `StandClearance` 之后：

```gdscript
	# Probe rig. Heights are expressed relative to the body origin, which sits
	# at the capsule centre — feet are 0.9 m below it.
	var probes := Node3D.new()
	probes.name = "Probes"
	probes.set_script(load("res://scripts/player/probes.gd"))
	player.add_child(probes)
	probes.owner = player

	# Forward ray at shin height: does something block the way at all?
	var vault_low := RayCast3D.new()
	vault_low.name = "VaultLow"
	vault_low.position = Vector3(0.0, -0.55, 0.0)
	vault_low.target_position = Vector3(0.0, 0.0, -1.4)
	vault_low.enabled = true
	probes.add_child(vault_low)
	vault_low.owner = player

	# Forward ray at chest height: if THIS hits too, the obstacle is a wall,
	# not something to vault.
	var vault_high := RayCast3D.new()
	vault_high.name = "VaultHigh"
	vault_high.position = Vector3(0.0, 0.45, 0.0)
	vault_high.target_position = Vector3(0.0, 0.0, -1.4)
	vault_high.enabled = true
	probes.add_child(vault_high)
	vault_high.owner = player

	# Downward ray from above and ahead: finds the top surface to land on.
	#
	# The start height is load-bearing. Heights in MovementConfig are measured
	# from the FEET, which sit 0.9 m below this origin, so a ledge at the
	# configured maximum of 2.8 m sits at +1.9 m here. Starting the ray at
	# +1.6 would put its origin BELOW the highest ledge it is supposed to find,
	# and tall ledges would silently never be detected. Start above the
	# configured maximum, and reach below the feet.
	var surface := RayCast3D.new()
	surface.name = "SurfaceDown"
	surface.position = Vector3(0.0, 2.2, -1.0)
	surface.target_position = Vector3(0.0, -3.2, 0.0)
	surface.enabled = true
	probes.add_child(surface)
	surface.owner = player

	player.probes = probes
```

同时在 `player.gd` 加导出字段：

```gdscript
## Assigned in player.tscn. Optional so hand-built test players still work.
@export var probes: Probes
```

重新生成 `player.tscn`（先 `--import`）。

- [ ] **Step 5: 写 Probes**

创建 `scripts/player/probes.gd`：

```gdscript
class_name Probes
extends Node3D

# Environment queries for the parkour states. Every height in the returned
# dictionaries is a WORLD y, while every configured height is measured from
# the player's feet — the conversion happens here so the states never have to
# think about the capsule's origin offset.

const NO_HIT := {"valid": false, "top": Vector3.ZERO, "edge": Vector3.ZERO, "normal": Vector3.UP}

@onready var _vault_low: RayCast3D = $VaultLow
@onready var _vault_high: RayCast3D = $VaultHigh
@onready var _surface: RayCast3D = $SurfaceDown

var _config: MovementConfig
var _foot_offset: float = 0.9

func setup(cfg: MovementConfig, foot_offset: float) -> void:
	_config = cfg
	_foot_offset = foot_offset
	# Apply the configured reaches to the rays, so vault_reach and ledge_reach
	# are genuinely tunable rather than decorative duplicates of a hardcoded
	# ray length. Rays point along -Z, which is the body's forward.
	_vault_low.target_position = Vector3(0.0, 0.0, -cfg.vault_reach)
	_vault_high.target_position = Vector3(0.0, 0.0, -maxf(cfg.vault_reach, cfg.ledge_reach))
	_surface.position = Vector3(0.0, _surface.position.y, -cfg.ledge_reach)

func _feet_y() -> float:
	return global_position.y - _foot_offset

## An obstacle low enough to vault: blocked at shin height, clear at chest
## height, with a walkable top within vault_max_height of the feet.
func vault_query() -> Dictionary:
	if _config == null:
		return NO_HIT
	_vault_low.force_raycast_update()
	_vault_high.force_raycast_update()
	if not _vault_low.is_colliding():
		return NO_HIT
	if _vault_high.is_colliding():
		return NO_HIT

	_surface.force_raycast_update()
	if not _surface.is_colliding():
		return NO_HIT
	var top: Vector3 = _surface.get_collision_point()
	var normal: Vector3 = _surface.get_collision_normal()
	if normal.y < 0.7:
		return NO_HIT
	var height := top.y - _feet_y()
	if height <= 0.0 or height > _config.vault_max_height:
		return NO_HIT
	return {"valid": true, "top": top, "edge": top, "normal": normal}

## A ledge high enough to hang from but still within reach.
func ledge_query() -> Dictionary:
	if _config == null:
		return NO_HIT
	_vault_high.force_raycast_update()
	if not _vault_high.is_colliding():
		return NO_HIT

	_surface.force_raycast_update()
	if not _surface.is_colliding():
		return NO_HIT
	var edge: Vector3 = _surface.get_collision_point()
	var normal: Vector3 = _surface.get_collision_normal()
	if normal.y < 0.7:
		return NO_HIT
	var height := edge.y - _feet_y()
	if height < _config.ledge_min_height or height > _config.ledge_max_height:
		return NO_HIT
	return {"valid": true, "top": edge, "edge": edge, "normal": normal}
```

在 `player.gd` 的 `setup()` 末尾加：

```gdscript
	if probes != null:
		probes.setup(config, _standing_height * 0.5)
```

- [ ] **Step 6: 运行测试确认通过**

Run: `pwsh tools/run_tests.ps1`
Expected: PASS。

若 `test_a_reachable_ledge_is_detected` 失败，**优先检查 `SurfaceDown` 的起点高度与射线长度**是否覆盖了 `ledge_max_height`，不要去改配置默认值。

- [ ] **Step 7: 提交**

```bash
git add scripts/player/ tools/build_player_scene.gd scenes/player/player.tscn tests/test_probes.gd
git commit -m "feat: add environment probes for vaulting and ledge detection"
```

---

## Task 2: 脚本化位移基类与翻越

**Files:**
- Create: `scripts/player/states/scripted_move.gd`
- Create: `scripts/player/states/vault_state.gd`
- Modify: `scripts/player/states/player_state.gd`（`VAULT` 常量）
- Modify: `scripts/player/movement_config.gd`（翻越时长与保速）
- Modify: `scripts/player/player.gd`（注册状态）
- Modify: `scripts/player/states/ground_state.gd`（转入 Vault）
- Test: `tests/test_vault.gd`

**Interfaces:**
- Produces：
  - `class_name ScriptedMove extends PlayerState`：字段 `_from` `_to` `_duration` `_elapsed`；方法 `begin(from: Vector3, to: Vector3, duration: float)`、`advance(delta: float) -> bool`（返回是否已完成）、`progress() -> float`
  - `class_name VaultState extends ScriptedMove`
  - `PlayerState.VAULT: StringName = &"Vault"`

**为什么脚本化位移不用 `move_and_slide()`：** 翻越的整个意义是**穿过**一个物理上挡路的障碍物。用物理推进会被自己要翻的东西挡住。工业做法是在动作期间接管位移、把角色沿算好的路径送过去。代价是这段时间内不做碰撞检测——路径由探测射线算出，所以终点本身是安全的，但极端几何下仍可能穿模。原型阶段接受。

- [ ] **Step 1: 写失败的测试**

创建 `tests/test_vault.gd`：

```gdscript
extends TestCase

func _running_at_obstacle(height: float) -> Dictionary:
	var cfg := MovementConfig.new()
	var world := TestWorld.build(tree, cfg)
	await step(1)
	TestWorld.place(world)
	await step(15)

	var obstacle := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8.0, height, 1.0)
	shape.shape = box
	obstacle.add_child(shape)
	tree.root.add_child(obstacle)
	await step(1)
	obstacle.global_position = Vector3(0.0, height * 0.5, -8.0)
	await step(1)

	world["input"].state.move = Vector2(0.0, 1.0)
	world["input"].state.sprint_held = true
	world["obstacle"] = obstacle
	return world

func test_running_into_a_low_obstacle_vaults_it() -> void:
	await step(1)
	var world := await _running_at_obstacle(1.0)
	var player: Player = world["player"]

	var vaulted := false
	for i in 300:
		await step(1)
		if player.state_machine.current_name == &"Vault":
			vaulted = true
			break
	check(vaulted, "running into a waist-high obstacle should start a vault")

	world["obstacle"].queue_free()
	TestWorld.teardown(world)
	await step(1)

func test_a_vault_ends_beyond_the_obstacle() -> void:
	await step(1)
	var world := await _running_at_obstacle(1.0)
	var player: Player = world["player"]
	var obstacle: StaticBody3D = world["obstacle"]

	for i in 400:
		await step(1)
		if player.state_machine.current_name == &"Vault":
			break
	for i in 400:
		await step(1)
		if player.state_machine.current_name != &"Vault":
			break

	check(player.global_position.z < obstacle.global_position.z, \
		"the vault should leave the player past the obstacle")

	obstacle.queue_free()
	TestWorld.teardown(world)
	await step(1)

func test_a_vault_keeps_most_of_the_approach_speed() -> void:
	await step(1)
	var world := await _running_at_obstacle(1.0)
	var player: Player = world["player"]

	var approach := 0.0
	for i in 400:
		await step(1)
		if player.state_machine.current_name == &"Vault":
			break
		approach = player.horizontal_speed()
	for i in 400:
		await step(1)
		if player.state_machine.current_name != &"Vault":
			break

	# Vaulting is a shortcut, not a speed bump — it must not cost more than a
	# plain landing would.
	check_greater(player.horizontal_speed(), approach * 0.5, \
		"vaulting bled too much speed (%f from %f)" % [player.horizontal_speed(), approach])

	world["obstacle"].queue_free()
	TestWorld.teardown(world)
	await step(1)

func test_a_wall_is_not_vaulted() -> void:
	await step(1)
	var world := await _running_at_obstacle(3.0)
	var player: Player = world["player"]

	for i in 300:
		await step(1)
		check(player.state_machine.current_name != &"Vault", \
			"a 3 m wall must never be vaulted")

	world["obstacle"].queue_free()
	TestWorld.teardown(world)
	await step(1)
```

- [ ] **Step 2: 运行测试确认失败**

Run: `pwsh tools/run_tests.ps1`
Expected: FAIL。

- [ ] **Step 3: 加常量与配置**

`player_state.gd`：

```gdscript
const VAULT: StringName = &"Vault"
const LEDGE: StringName = &"Ledge"
```

`movement_config.gd` 的 Vault 组追加：

```gdscript
## How long the vault motion takes. Short enough to feel snappy, long enough
## to read as a deliberate action rather than a teleport.
@export var vault_duration: float = 0.32
## Fraction of the approach speed carried out the far side.
@export var vault_speed_keep: float = 0.85
## How far past the obstacle top the vault places the player.
@export var vault_exit_forward: float = 0.6
```

- [ ] **Step 4: 写 ScriptedMove**

创建 `scripts/player/states/scripted_move.gd`：

```gdscript
class_name ScriptedMove
extends PlayerState

# Shared machinery for states that DRIVE the body along a computed path rather
# than letting physics push it. Vaulting and mantling both need to pass through
# geometry that would otherwise block them, which is exactly what physics is
# there to prevent — so for the duration of the move, physics steps aside.

var _from: Vector3 = Vector3.ZERO
var _to: Vector3 = Vector3.ZERO
var _duration: float = 0.0
var _elapsed: float = 0.0

func begin(from: Vector3, to: Vector3, duration: float) -> void:
	_from = from
	_to = to
	_duration = maxf(duration, 0.0001)
	_elapsed = 0.0

func progress() -> float:
	return clampf(_elapsed / _duration, 0.0, 1.0)

## Moves the body one tick along the path. Returns true once the path is done.
func advance(delta: float) -> bool:
	_elapsed += delta
	var t := progress()
	# Ease-out: most of the travel happens early, so the action reads as a
	# push-off rather than a constant-speed slide.
	var eased := 1.0 - pow(1.0 - t, 2.0)
	var target := _from.lerp(_to, eased)
	# An arc, so the body rises over the obstacle instead of through it.
	target.y += sin(t * PI) * 0.15
	player.global_position = target
	return t >= 1.0
```

- [ ] **Step 5: 写 VaultState**

创建 `scripts/player/states/vault_state.gd`：

```gdscript
class_name VaultState
extends ScriptedMove

var _exit_speed: float = 0.0
var _exit_direction: Vector3 = Vector3.ZERO

func enter(_previous: StringName) -> void:
	var query: Dictionary = player.probes.vault_query()
	var horizontal := Vector3(player.velocity.x, 0.0, player.velocity.z)
	_exit_speed = horizontal.length() * config.vault_speed_keep
	_exit_direction = horizontal.normalized() if horizontal.length_squared() > 0.0001 else -player.global_transform.basis.z

	var top: Vector3 = query["top"] if query["valid"] else player.global_position
	var landing := top + _exit_direction * config.vault_exit_forward
	landing.y = top.y + player.standing_height() * 0.5

	begin(player.global_position, landing, config.vault_duration)
	player.velocity = Vector3.ZERO

func physics_update(delta: float, _input: MoveInput) -> StringName:
	if advance(delta):
		player.velocity = _exit_direction * _exit_speed
		return GROUND
	return KEEP
```

- [ ] **Step 6: 注册状态并接入 GroundState**

`player.gd` 的 `_build_state_machine()` 中注册 `VaultState`（与既有状态同样的三行模式）。

`ground_state.gd`，在滑铲判定**之后**插入：

```gdscript
	# Vaulting has to be earned with speed, or every waist-high box becomes a
	# free elevator.
	if player.probes != null and player.horizontal_speed() >= config.vault_min_speed:
		if player.probes.vault_query()["valid"]:
			return VAULT
```

- [ ] **Step 7: 运行测试确认通过并提交**

Run: `pwsh tools/run_tests.ps1`

```bash
git add scripts/player/ tests/test_vault.gd
git commit -m "feat: add scripted-move base state and vaulting"
```

---

## Task 3: 抓边缘与攀上

**Files:**
- Create: `scripts/player/states/ledge_hang_state.gd`
- Modify: `scripts/player/movement_config.gd`
- Modify: `scripts/player/player.gd`
- Modify: `scripts/player/states/air_state.gd`
- Test: `tests/test_ledge.gd`

**Interfaces:**
- Produces：`class_name LedgeHangState extends ScriptedMove`

**状态内的两个阶段：** 悬挂（位置冻结，等待输入）与攀上（脚本化位移到平台顶）。合并在一个状态里，因为它们共享同一个边缘数据，拆开会让边缘信息在状态间传递变得别扭。

- [ ] **Step 1: 写失败的测试**

创建 `tests/test_ledge.gd`：

```gdscript
extends TestCase

func _jump_at_ledge(block_height: float) -> Dictionary:
	var cfg := MovementConfig.new()
	var world := TestWorld.build(tree, cfg)
	await step(1)
	TestWorld.place(world)
	await step(15)

	var block := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8.0, block_height, 4.0)
	shape.shape = box
	block.add_child(shape)
	tree.root.add_child(block)
	await step(1)
	block.global_position = Vector3(0.0, block_height * 0.5, -6.0)
	await step(1)

	world["input"].state.move = Vector2(0.0, 1.0)
	world["input"].state.sprint_held = true
	world["block"] = block
	return world

func test_reaching_a_ledge_grabs_it() -> void:
	await step(1)
	var world := await _jump_at_ledge(2.6)
	var player: Player = world["player"]

	var grabbed := false
	for i in 400:
		await step(1)
		if player.horizontal_speed() > 5.0 and player.is_on_floor():
			world["input"].press_jump()
		if player.state_machine.current_name == &"Ledge":
			grabbed = true
			break
	check(grabbed, "jumping at a head-height ledge should grab it")

	world["block"].queue_free()
	TestWorld.teardown(world)
	await step(1)

func test_hanging_holds_position() -> void:
	await step(1)
	var world := await _jump_at_ledge(2.6)
	var player: Player = world["player"]
	for i in 400:
		await step(1)
		if player.horizontal_speed() > 5.0 and player.is_on_floor():
			world["input"].press_jump()
		if player.state_machine.current_name == &"Ledge":
			break
	check(player.state_machine.current_name == &"Ledge", "precondition: should be hanging")

	world["input"].state.move = Vector2.ZERO
	var held := player.global_position
	await step(20)
	check(player.global_position.distance_to(held) < 0.05, \
		"a hanging player must not drift or fall")

	world["block"].queue_free()
	TestWorld.teardown(world)
	await step(1)

func test_pressing_forward_mantles_onto_the_ledge() -> void:
	await step(1)
	var world := await _jump_at_ledge(2.6)
	var player: Player = world["player"]
	for i in 400:
		await step(1)
		if player.horizontal_speed() > 5.0 and player.is_on_floor():
			world["input"].press_jump()
		if player.state_machine.current_name == &"Ledge":
			break

	world["input"].state.move = Vector2(0.0, 1.0)
	for i in 200:
		await step(1)
		if player.state_machine.current_name == &"Ground":
			break
	check(player.state_machine.current_name == &"Ground", "mantling should end on the ledge top")
	check_greater(player.global_position.y, 2.0, "the player should now be above the ledge")

	world["block"].queue_free()
	TestWorld.teardown(world)
	await step(1)

func test_crouching_releases_the_ledge() -> void:
	await step(1)
	var world := await _jump_at_ledge(2.6)
	var player: Player = world["player"]
	for i in 400:
		await step(1)
		if player.horizontal_speed() > 5.0 and player.is_on_floor():
			world["input"].press_jump()
		if player.state_machine.current_name == &"Ledge":
			break

	world["input"].state.move = Vector2.ZERO
	world["input"].state.crouch_held = true
	await step(5)
	check(player.state_machine.current_name == &"Air", "crouching should drop off the ledge")

	world["block"].queue_free()
	TestWorld.teardown(world)
	await step(1)
```

- [ ] **Step 2: 运行测试确认失败**

Run: `pwsh tools/run_tests.ps1`

- [ ] **Step 3: 加配置**

`movement_config.gd` 的 Ledge 组追加：

```gdscript
## How far below the ledge top the body hangs.
@export var ledge_hang_drop: float = 1.1
## How long the mantle motion takes.
@export var mantle_duration: float = 0.42
## Horizontal speed granted on top after a mantle.
@export var mantle_exit_speed: float = 2.0
## After releasing a ledge, how long before another can be grabbed. Without
## this, dropping off a ledge instantly re-grabs the same one.
@export var ledge_regrab_cooldown: float = 0.45
```

- [ ] **Step 4: 写 LedgeHangState**

创建 `scripts/player/states/ledge_hang_state.gd`：

```gdscript
class_name LedgeHangState
extends ScriptedMove

# Two phases in one state: hanging (position frozen, waiting on input) and
# mantling (a scripted move onto the top). They share the same ledge data, and
# splitting them would mean handing that data across a state boundary.

var _edge: Vector3 = Vector3.ZERO
var _normal: Vector3 = Vector3.UP
var _mantling: bool = false

func enter(_previous: StringName) -> void:
	var query: Dictionary = player.probes.ledge_query()
	_edge = query["edge"] if query["valid"] else player.global_position
	_normal = query["normal"] if query["valid"] else Vector3.UP
	_mantling = false
	player.velocity = Vector3.ZERO
	# Hang with the head just under the lip.
	player.global_position = Vector3(
		player.global_position.x,
		_edge.y - config.ledge_hang_drop,
		player.global_position.z)

func physics_update(delta: float, input: MoveInput) -> StringName:
	if _mantling:
		if advance(delta):
			var forward := -player.global_transform.basis.z
			player.velocity = forward * config.mantle_exit_speed
			return GROUND
		return KEEP

	# Hanging: hold still. No gravity, no drift.
	player.velocity = Vector3.ZERO

	if input.crouch_held:
		player.start_ledge_cooldown()
		return AIR

	# Pushing forward, or jumping, climbs up.
	if input.move.y > 0.5 or input.jump_pressed:
		var top := _edge + Vector3(0.0, player.standing_height() * 0.5, 0.0)
		top -= player.global_transform.basis.z * 0.4
		begin(player.global_position, top, config.mantle_duration)
		_mantling = true
	return KEEP
```

- [ ] **Step 5: Player 的抓取冷却与 AirState 转移**

`player.gd`：

```gdscript
var _ledge_cooldown: float = 0.0

func start_ledge_cooldown() -> void:
	_ledge_cooldown = config.ledge_regrab_cooldown

func can_grab_ledge() -> bool:
	return _ledge_cooldown <= 0.0
```

在 `_tick_timers()` 中递减 `_ledge_cooldown`。

`air_state.gd`，在落地判定**之前**插入：

```gdscript
	if player.probes != null and player.can_grab_ledge():
		if player.probes.ledge_query()["valid"]:
			return LEDGE
```

注册 `LedgeHangState`。

- [ ] **Step 6: 运行测试确认通过并提交**

```bash
git add scripts/player/ tests/test_ledge.gd
git commit -m "feat: add ledge hanging and mantling"
```

---

## Task 4: 靶场翻越/抓边区

**Files:**
- Modify: `tools/build_main_scene.gd`
- Test: 追加到 `tests/test_arena.gd`

西侧区域（`VaultArea`，`position = (-14, 0, 0)`），沿用既有的 `_box()` 与 `_material_for()`：

| 名称 | size | position | 用途 |
| --- | --- | --- | --- |
| `VaultLow` | `(6, 0.8, 1)` | `(0, 0.4, -4)` | 齐膝，最容易翻 |
| `VaultMid` | `(6, 1.1, 1)` | `(0, 0.55, -9)` | 齐腰，标准翻越 |
| `VaultHigh` | `(6, 1.3, 1)` | `(0, 0.65, -14)` | 翻越上限 |
| `WallTooTall` | `(6, 2.2, 1)` | `(0, 1.1, -19)` | 翻不过去，只能绕 |
| `LedgeLow` | `(8, 2.2, 4)` | `(0, 1.1, -26)` | 抓边缘下限 |
| `LedgeMid` | `(8, 2.8, 4)` | `(0, 1.4, -33)` | 抓边缘上限 |
| `LedgeTooHigh` | `(8, 4.5, 4)` | `(0, 2.25, -40)` | 够不到 |

- [ ] **Step 1: 追加测试**

```gdscript
func test_the_vault_area_spans_the_configured_limits() -> void:
	await step(1)
	var arena = await _load_arena()
	for name in ["VaultLow", "VaultMid", "VaultHigh", "WallTooTall", "LedgeLow", "LedgeMid", "LedgeTooHigh"]:
		check(arena.get_node_or_null("VaultArea/%s" % name) != null, "%s is missing" % name)

	# The area is only useful if it brackets the configured limits: something
	# just inside each bound and something just outside it.
	var high = arena.get_node("VaultArea/VaultHigh")
	var high_box := ((high.get_node("Collision") as CollisionShape3D).shape as BoxShape3D)
	check(high_box.size.y <= arena.config.vault_max_height, \
		"VaultHigh should sit at or under the vault limit")

	var wall = arena.get_node("VaultArea/WallTooTall")
	var wall_box := ((wall.get_node("Collision") as CollisionShape3D).shape as BoxShape3D)
	check_greater(wall_box.size.y, arena.config.vault_max_height, \
		"WallTooTall should exceed the vault limit, or it teaches nothing")

	arena.queue_free()
	await step(1)
```

- [ ] **Step 2: 生成器加入该区域，重新生成主场景**

- [ ] **Step 3: 运行测试确认通过**

- [ ] **Step 4: 截图验收**

```powershell
.\.engine\Godot_v4.7.1-stable_win64_console.exe --path . --resolution 960x540 --script res://tools/capture.gd -- res://scenes/main.tscn res://.captures/p2_arena.png 120
```

- [ ] **Step 5: 提交**

```bash
git add tools/build_main_scene.gd scenes/main.tscn tests/test_arena.gd
git commit -m "feat: add the vault and ledge practice area"
```

---

## P2 完成标准

**自动可验证：**

- [ ] `pwsh tools/run_tests.ps1` 通过，退出码 0
- [ ] 探测射线能区分可翻越障碍、高墙、可抓边缘、够不到的边缘
- [ ] 跑动撞上齐腰障碍会翻越，且落点在障碍另一侧
- [ ] 翻越保住大部分速度；高墙永不触发翻越
- [ ] 静止时不会翻越（速度门槛生效）
- [ ] 跳向头顶高度的平台会抓住边缘
- [ ] 悬挂时位置冻结，不下坠也不漂移
- [ ] 前推或跳跃会攀上平台顶并进入 Ground
- [ ] 蹲键释放边缘并进入 Air，且冷却期内不会立刻重新抓住
- [ ] 靶场翻越区的几何体跨越了配置上限的两侧
- [ ] 靶场截图渲染正常

**留待使用者确认：**

- [ ] 翻越的时长与弧线是否好看
- [ ] 攀上的速度是否让人觉得利落还是拖沓
- [ ] 抓边缘的触发范围是否过于宽松（导致误抓）或过于苛刻
- [ ] 脚本化位移期间关闭碰撞是否在实际关卡里造成穿模
