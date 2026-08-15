# P0 移动地基 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 做出可实际游玩的第一人称移动地基——地面/空中两个状态、跳跃、相机效果、灰盒跳跃靶场、实时调参面板，并让 headless 测试通道全程可用。

**Architecture:** `CharacterBody3D` 挂一个显式状态机，状态自行决定转换目标。所有手感数值集中在 `MovementConfig` 资源中，由 F1 面板运行时修改。输入经由 `InputSource` 抽象读取，测试注入脚本化输入源以驱动物理，无需真实键盘。

**Tech Stack:** Godot 4.7.1-stable / GDScript / Jolt Physics / 自制 70 行 headless 测试运行器（无第三方插件）

**Spec:** [`docs/superpowers/specs/2026-08-16-parkour-movement-prototype-design.md`](../specs/2026-08-16-parkour-movement-prototype-design.md)

## Global Constraints

以下取值直接摘自 spec，每个任务的要求都隐含包含本节：

- 引擎版本：Godot **4.7.1-stable (official)**，调用路径 `.engine\Godot_v4.7.1-stable_win64.exe`（headless 用 `_console.exe` 变体才能拿到 stdout）
- 语言：**GDScript**（锁定；C# 无法导出 Web）
- 渲染器：**`gl_compatibility`**（锁定；全程不得更改 `project.godot` 中的 `renderer/rendering_method`）
- 物理引擎：Jolt Physics，物理帧率 **60 Hz**（已实测确认 `Engine.physics_ticks_per_second == 60`）
- 输入：仅键鼠。WASD 移动 / 鼠标视角 / `Space` 跳 / `Shift` 冲刺 / `Ctrl` 蹲（P1 起用于滑铲）
- 测试：**只断言关系，不断言绝对数值**。不测手感。不追求覆盖率。
- 不引入任何第三方插件

### 无人值守约束

本计划在使用者不在场的情况下执行。**任何要求人在 Godot 编辑器里手动操作的步骤都不可用**，因此：

- **场景不手工编辑。** 所有 `.tscn` 由 `tools/build_*.gd` 生成器脚本产出：在代码中搭好节点树，用 `PackedScene.pack()` + `ResourceSaver.save()` 让引擎自己写文件。格式由引擎保证，不手写、不猜测。
- **视觉验收靠截图。** `tools/capture.gd` 以真实渲染器运行目标场景、推进若干帧、`root.get_texture().get_image().save_png()` 存图，由控制者读取 PNG 判断画面是否正确。
- 无法自动化的验收项（例如"鼠标手感是否跟手"）**不要伪装成已验证**，在报告中明确标注为待人工确认。

### 实测得出的引擎行为（不要重新试错）

以下每一条都来自实际运行的探针，直接采用：

1. `extends SceneTree` 的脚本可通过 `--headless --path . --script res://...` 运行，`await physics_frame` 会真实推进物理。
2. **`root.add_child(node)` 之后节点不会立即入树**。此时读写 `global_position` / `global_transform` 会报
   `ERROR: Condition "!is_inside_tree()" is true. Returning: Transform3D()`。
   **必须先 `await physics_frame` 再操作全局变换**，或改用局部 `position`。
3. 碰撞在 headless 下正常工作：`is_on_floor()`、`get_floor_normal()` 均有效。物理帧率为 60。
4. `await some_refcounted.call("method_name")` 对协程方法和同步方法**都能安全处理**，不会报错或卡死。
5. **新增或改名 `class_name` 后必须先跑一次 `--headless --path . --import`**，否则 headless 运行会直接解析失败：
   `SCRIPT ERROR: Parse Error: Identifier "Xxx" not declared in the current scope.`
   全局类名索引存放在 `.godot/global_script_class_cache.cfg`，只有编辑器扫描（`--import` 会触发）才会刷新它。
   `tools/run_tests.ps1` 已内置这一步，直接用脚本跑测试即可。
6. `PackedScene.pack()` + `ResourceSaver.save()` 的往返完整可靠：节点结构、`transform`、内联子资源、`set_script()` 附加的脚本、`@export` 的资源引用**以及 `@export` 的同场景节点引用**（序列化为 `node_paths=PackedStringArray(...)` + `NodePath`）全部原样还原。
7. 去掉 `--headless` 后 `--script` 会创建真实渲染上下文。连续 `await process_frame` 若干帧、再 `await RenderingServer.frame_post_draw`，即可用 `root.get_texture().get_image()` 取到画面。

---

## File Structure

| 文件 | 职责 |
| --- | --- |
| `tests/test_case.gd` | 测试基类：断言辅助、物理步进辅助 |
| `tests/test_runner.gd` | `SceneTree` 入口：发现并运行所有 `tests/test_*.gd`，汇总结果，设置退出码 |
| `tests/test_world.gd` | 测试世界搭建辅助：造地面、造玩家、步进 |
| `tests/test_player_scene.gd` | 断言生成出的 `player.tscn` 结构与导出引用正确 |
| `tests/test_arena.gd` | 断言靶场装配、重置、HUD 与调参面板的接线 |
| `tools/run_tests.ps1` | 一条命令跑全部测试（内含 `--import` 刷新类缓存） |
| `tools/build_player_scene.gd` | 生成 `scenes/player/player.tscn` |
| `tools/build_main_scene.gd` | 生成 `scenes/main.tscn`（含跳跃区、HUD、调参面板） |
| `tools/capture.gd` | 渲染任意场景并存 PNG，供控制者目视验收 |
| `tools/capture_panel.gd` | 同上，但先展开调参面板 |
| `scripts/player/movement_config.gd` | 所有手感数值的唯一来源 |
| `scripts/player/input/move_input.gd` | 单帧输入快照（纯数据） |
| `scripts/player/input/input_source.gd` | 输入源抽象基类 |
| `scripts/player/input/keyboard_input_source.gd` | 真实键鼠输入 |
| `scripts/player/input/scripted_input_source.gd` | 测试替身 |
| `scripts/player/states/player_state.gd` | 状态基类 |
| `scripts/player/states/state_machine.gd` | 状态注册与转换 |
| `scripts/player/states/ground_state.gd` | 地面移动 |
| `scripts/player/states/air_state.gd` | 空中移动与重力 |
| `scripts/player/player.gd` | 共享数据与移动原语；驱动状态机 |
| `scripts/camera/camera_rig.gd` | 视角、FOV、步频晃动、落地下沉 |
| `scripts/debug/debug_hud.gd` | Tab 切换的实时数据显示 |
| `scripts/debug/tuning_panel.gd` | F1 调参面板与预设存取 |
| `scenes/player/player.tscn` | 玩家场景 |
| `scenes/main.tscn` | 靶场主场景（P0 只含跳跃区） |

---

## Task 1: Headless 测试骨架

**Files:**
- Create: `tests/test_case.gd`
- Create: `tests/test_runner.gd`
- Create: `tests/test_smoke.gd`
- Create: `tools/run_tests.ps1`

**Interfaces:**
- Consumes: 无
- Produces:
  - `TestCase`（`class_name`）：字段 `tree: SceneTree`、`failures: Array[String]`；方法 `check(condition: bool, message: String) -> void`、`check_greater(a: float, b: float, message: String) -> void`、`check_approx(a: float, b: float, tolerance: float, message: String) -> void`、`step(frames: int) -> void`（协程）
  - 测试文件约定：`tests/test_*.gd`，脚本顶部 `extends TestCase`，公开方法以 `test_` 开头
  - 运行命令：`pwsh tools/run_tests.ps1`

- [ ] **Step 1: 写测试基类**

创建 `tests/test_case.gd`：

```gdscript
class_name TestCase
extends RefCounted

# Base class for every test file. The runner injects `tree` before running
# any test method, so `step()` can advance the physics server.

var tree: SceneTree
var failures: Array[String] = []
var checks: int = 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func check_greater(a: float, b: float, message: String) -> void:
	checks += 1
	if not (a > b):
		failures.append("%s (expected %f > %f)" % [message, a, b])

func check_approx(a: float, b: float, tolerance: float, message: String) -> void:
	checks += 1
	if absf(a - b) > tolerance:
		failures.append("%s (expected %f ~= %f, tolerance %f)" % [message, a, b, tolerance])

# Advance the physics server by `frames` ticks. Every test method must await
# this at least once before touching global transforms — nodes added to the
# tree are not actually in-tree until a frame has elapsed.
func step(frames: int) -> void:
	for i in frames:
		await tree.physics_frame
```

- [ ] **Step 2: 写运行器**

创建 `tests/test_runner.gd`：

```gdscript
extends SceneTree

# Headless test entry point. Discovers every tests/test_*.gd, runs each
# `test_` method on a fresh instance, and exits non-zero if anything failed.
#
# Run with:
#   .engine\Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#       --script res://tests/test_runner.gd

const TEST_DIR := "res://tests"

func _initialize() -> void:
	_run_all()

func _run_all() -> void:
	var total_checks := 0
	var all_failures: Array[String] = []
	var files := _discover()

	for path in files:
		var script: GDScript = load(path)
		var case = script.new()
		case.tree = self
		var ran := 0
		for m in case.get_method_list():
			var method_name: String = m.name
			if not method_name.begins_with("test_"):
				continue
			ran += 1
			await case.call(method_name)
			for f in case.failures:
				all_failures.append("%s::%s  %s" % [path.get_file(), method_name, f])
			case.failures.clear()
		total_checks += case.checks
		print("  %-32s %d test(s)" % [path.get_file(), ran])

	print("")
	print("checks: %d   failures: %d" % [total_checks, all_failures.size()])
	for f in all_failures:
		print("  FAIL  ", f)
	quit(1 if all_failures.size() > 0 else 0)

func _discover() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(TEST_DIR)
	if dir == null:
		push_error("cannot open %s" % TEST_DIR)
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.begins_with("test_") and name.ends_with(".gd"):
			if name != "test_runner.gd" and name != "test_case.gd":
				out.append("%s/%s" % [TEST_DIR, name])
		name = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out
```

- [ ] **Step 3: 写冒烟测试**

创建 `tests/test_smoke.gd`。这个文件的存在意义是**证明测试通道本身是通的**——引擎能起、物理能步进、断言能失败。

```gdscript
extends TestCase

# Proves the harness itself works: the physics server advances and a body
# added at runtime actually falls and lands.

func test_physics_server_advances() -> void:
	var before := Engine.get_physics_frames()
	await step(5)
	var after := Engine.get_physics_frames()
	check_greater(float(after), float(before), "physics frame counter did not advance")

func test_body_falls_and_lands() -> void:
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, 1.0, 20.0)
	floor_shape.shape = box
	floor_body.add_child(floor_shape)
	tree.root.add_child(floor_body)

	var body := CharacterBody3D.new()
	var body_shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = 2.0
	capsule.radius = 0.4
	body_shape.shape = capsule
	body.add_child(body_shape)
	tree.root.add_child(body)

	# Nodes are not in-tree until a frame elapses; setting global_position
	# before this point silently fails with an is_inside_tree() error.
	await step(1)
	floor_body.global_position = Vector3(0.0, -0.5, 0.0)
	body.global_position = Vector3(0.0, 5.0, 0.0)

	for i in 200:
		body.velocity.y -= 24.0 * (1.0 / 60.0)
		body.move_and_slide()
		await step(1)
		if body.is_on_floor():
			break

	check(body.is_on_floor(), "body never landed on the floor")
	check_approx(body.global_position.y, 1.0, 0.05, "resting height wrong")

	body.queue_free()
	floor_body.queue_free()
	await step(1)
```

- [ ] **Step 4: 写运行脚本**

创建 `tools/run_tests.ps1`：

```powershell
# Runs the headless test suite. Uses the _console.exe variant because the
# plain exe detaches from the console and swallows stdout on Windows.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$godot = Join-Path $root '.engine\Godot_v4.7.1-stable_win64_console.exe'

if (-not (Test-Path $godot)) {
    Write-Error "Godot not found at $godot (is the .engine junction present?)"
}

# Refresh .godot/global_script_class_cache.cfg first. Without this, any
# class_name declared since the last editor scan fails to resolve and every
# test dies with 'Identifier "Xxx" not declared in the current scope'.
& $godot --headless --path $root --import | Out-Null

& $godot --headless --path $root --script res://tests/test_runner.gd
exit $LASTEXITCODE
```

- [ ] **Step 5: 运行测试，确认通过**

Run: `pwsh tools/run_tests.ps1`

Expected: 列出 `test_smoke.gd  2 test(s)`，`failures: 0`，退出码 `0`。

- [ ] **Step 6: 故意制造一次失败，确认失败真的会被捕获**

临时把 `test_smoke.gd` 中 `check_approx(body.global_position.y, 1.0, 0.05, ...)` 的 `1.0` 改成 `99.0`，重新运行。

Expected: 输出含 `FAIL  test_smoke.gd::test_body_falls_and_lands`，退出码 `1`。

**确认后改回 `1.0`，重新运行确认恢复为 0。** 这一步不能跳——一个永远不会失败的测试套件比没有测试更危险。

- [ ] **Step 7: 提交**

```bash
git add tests/ tools/
git commit -m "test: add headless test harness with a self-verifying smoke test"
```

---

## Task 2: MovementConfig 资源

**Files:**
- Create: `scripts/player/movement_config.gd`
- Test: `tests/test_movement_config.gd`

**Interfaces:**
- Consumes: 无
- Produces: `MovementConfig`（`class_name`，`extends Resource`）。P0 用到的导出属性见下方代码，全部为 `float`。后续任务一律通过 `config.<属性名>` 读取，**不得出现魔法数字**。

- [ ] **Step 1: 写失败的测试**

创建 `tests/test_movement_config.gd`：

```gdscript
extends TestCase

# These assert relationships between parameters, never their values, so they
# survive tuning. If a relationship here breaks, the feel is broken too.

func test_sprint_is_faster_than_walk() -> void:
	await step(1)
	var c := MovementConfig.new()
	check_greater(c.sprint_speed, c.walk_speed, "sprint must be faster than walk")

func test_air_control_is_weaker_than_ground_control() -> void:
	await step(1)
	var c := MovementConfig.new()
	# The whole "commit to your jump" feel depends on this ordering.
	check_greater(c.ground_accel, c.air_accel, "ground acceleration must exceed air acceleration")

func test_fov_widens_with_speed() -> void:
	await step(1)
	var c := MovementConfig.new()
	check_greater(c.fov_max, c.fov_base, "max FOV must exceed base FOV")

func test_terminal_velocity_exceeds_jump_velocity() -> void:
	await step(1)
	var c := MovementConfig.new()
	check_greater(c.terminal_velocity, c.jump_velocity, "terminal velocity must exceed jump velocity")
```

- [ ] **Step 2: 运行测试确认失败**

Run: `pwsh tools/run_tests.ps1`
Expected: FAIL，报错内容为无法识别标识符 `MovementConfig`。

- [ ] **Step 3: 写实现**

创建 `scripts/player/movement_config.gd`：

```gdscript
class_name MovementConfig
extends Resource

# Single source of truth for every feel-related number. Nothing in the state
# scripts may hardcode a value; the F1 tuning panel writes back into an
# instance of this resource at runtime.

@export_group("Ground")
## Target horizontal speed with no sprint key held.
@export var walk_speed: float = 5.0
## Target horizontal speed while sprinting.
@export var sprint_speed: float = 9.0
## How fast horizontal velocity converges on the target, in m/s^2.
@export var ground_accel: float = 60.0
## Deceleration applied when there is no movement input, in m/s^2.
@export var ground_friction: float = 40.0

@export_group("Air")
## Air acceleration. Deliberately far below ground_accel: committing to a
## jump is the core of the movement feel.
@export var air_accel: float = 12.0
## Upper bound on the speed air control alone can reach. Momentum carried in
## from other states is never reduced by air control.
@export var air_max_speed: float = 9.0
@export var gravity: float = 24.0
@export var terminal_velocity: float = 60.0

@export_group("Jump")
@export var jump_velocity: float = 7.5
## Grace period after leaving a ledge during which a jump still works.
@export var coyote_time: float = 0.12
## How long a jump press is remembered before landing.
@export var jump_buffer_time: float = 0.12

@export_group("Camera")
@export var mouse_sensitivity: float = 0.0022
@export var pitch_limit_deg: float = 89.0
@export var fov_base: float = 75.0
@export var fov_max: float = 95.0
## Horizontal speed at which FOV reaches fov_max.
@export var fov_speed_ref: float = 9.0
@export var fov_lerp_speed: float = 6.0
@export var bob_frequency: float = 1.6
@export var bob_amplitude: float = 0.055
@export var land_dip_max: float = 0.32
@export var land_dip_recover: float = 2.2
## Fall speed that produces a full-strength landing dip.
@export var land_dip_speed_ref: float = 18.0
```

- [ ] **Step 4: 运行测试确认通过**

Run: `pwsh tools/run_tests.ps1`
Expected: PASS，`failures: 0`。

- [ ] **Step 5: 提交**

```bash
git add scripts/player/movement_config.gd tests/test_movement_config.gd
git commit -m "feat: add MovementConfig resource holding all feel parameters"
```

---

## Task 3: 输入抽象

**Files:**
- Create: `scripts/player/input/move_input.gd`
- Create: `scripts/player/input/input_source.gd`
- Create: `scripts/player/input/keyboard_input_source.gd`
- Create: `scripts/player/input/scripted_input_source.gd`
- Test: `tests/test_input.gd`

**Interfaces:**
- Consumes: 无
- Produces:
  - `MoveInput`：字段 `move: Vector2`（x=右为正的横移，y=前为正的前后）、`look: Vector2`、`jump_pressed: bool`、`jump_held: bool`、`sprint_held: bool`、`crouch_held: bool`；方法 `copy() -> MoveInput`
  - `InputSource`：方法 `poll() -> MoveInput`
  - `KeyboardInputSource extends InputSource`：额外方法 `accumulate_look(delta: Vector2) -> void`
  - `ScriptedInputSource extends InputSource`：字段 `state: MoveInput`；方法 `press_jump() -> void`

**设计说明（执行者必读）：** P0 **不使用 `InputMap` 动作**，直接用 `Input.is_physical_key_pressed()` 读物理键位。这是有意的取舍——按键重绑定不在原型范围内（见 spec 第 2 节非目标），而手写 `project.godot` 的 `[input]` 段格式繁琐且易错。物理键位还能让 WASD 不受键盘布局影响。

- [ ] **Step 1: 写失败的测试**

创建 `tests/test_input.gd`：

```gdscript
extends TestCase

# The scripted source is what every movement test drives the player with, so
# its edge semantics must match the keyboard source exactly.

func test_scripted_source_returns_what_was_set() -> void:
	await step(1)
	var src := ScriptedInputSource.new()
	src.state.move = Vector2(0.0, 1.0)
	src.state.sprint_held = true
	var snapshot := src.poll()
	check(snapshot.move == Vector2(0.0, 1.0), "move was not passed through")
	check(snapshot.sprint_held, "sprint_held was not passed through")

func test_jump_pressed_is_an_edge_lasting_one_poll() -> void:
	await step(1)
	var src := ScriptedInputSource.new()
	src.press_jump()

	var first := src.poll()
	check(first.jump_pressed, "jump_pressed missing on the first poll")
	check(first.jump_held, "jump_held missing on the first poll")

	var second := src.poll()
	check(not second.jump_pressed, "jump_pressed must not survive a second poll")
	check(second.jump_held, "jump_held must persist until released")

func test_copy_is_independent() -> void:
	await step(1)
	var a := MoveInput.new()
	a.move = Vector2(1.0, 0.0)
	var b := a.copy()
	b.move = Vector2(0.0, 1.0)
	check(a.move == Vector2(1.0, 0.0), "copy() returned a shared reference")
```

- [ ] **Step 2: 运行测试确认失败**

Run: `pwsh tools/run_tests.ps1`
Expected: FAIL，无法识别 `ScriptedInputSource` / `MoveInput`。

- [ ] **Step 3: 写 MoveInput**

创建 `scripts/player/input/move_input.gd`：

```gdscript
class_name MoveInput
extends RefCounted

# One physics tick worth of input. Pure data — no logic, no engine access.

## x = strafe (+ is right), y = forward (+ is forward).
var move := Vector2.ZERO
## Mouse motion accumulated since the previous poll, in pixels.
var look := Vector2.ZERO
## True only on the tick the jump key transitioned from up to down.
var jump_pressed := false
var jump_held := false
var sprint_held := false
var crouch_held := false

func copy() -> MoveInput:
	var out := MoveInput.new()
	out.move = move
	out.look = look
	out.jump_pressed = jump_pressed
	out.jump_held = jump_held
	out.sprint_held = sprint_held
	out.crouch_held = crouch_held
	return out
```

- [ ] **Step 4: 写 InputSource 基类**

创建 `scripts/player/input/input_source.gd`：

```gdscript
class_name InputSource
extends RefCounted

# The seam that lets tests drive the player without a real keyboard.
# Implementations must return a snapshot that is safe to hold for one tick.
func poll() -> MoveInput:
	push_error("InputSource.poll() is abstract and must be overridden")
	return MoveInput.new()
```

- [ ] **Step 5: 写键盘输入源**

创建 `scripts/player/input/keyboard_input_source.gd`：

```gdscript
class_name KeyboardInputSource
extends InputSource

# Reads physical key positions so the bindings do not shift with keyboard
# layout. No InputMap actions are registered: rebinding is out of scope for
# the prototype.

var _jump_was_held := false
var _look_accumulator := Vector2.ZERO

## Called from the player's _input() with the raw mouse relative motion.
func accumulate_look(delta: Vector2) -> void:
	_look_accumulator += delta

func poll() -> MoveInput:
	var out := MoveInput.new()

	var forward := 0.0
	if Input.is_physical_key_pressed(KEY_W):
		forward += 1.0
	if Input.is_physical_key_pressed(KEY_S):
		forward -= 1.0

	var strafe := 0.0
	if Input.is_physical_key_pressed(KEY_D):
		strafe += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		strafe -= 1.0

	out.move = Vector2(strafe, forward)
	if out.move.length_squared() > 1.0:
		out.move = out.move.normalized()

	out.look = _look_accumulator
	_look_accumulator = Vector2.ZERO

	var jump_held := Input.is_physical_key_pressed(KEY_SPACE)
	out.jump_pressed = jump_held and not _jump_was_held
	out.jump_held = jump_held
	_jump_was_held = jump_held

	out.sprint_held = Input.is_physical_key_pressed(KEY_SHIFT)
	out.crouch_held = Input.is_physical_key_pressed(KEY_CTRL)
	return out
```

- [ ] **Step 6: 写脚本化输入源**

创建 `scripts/player/input/scripted_input_source.gd`：

```gdscript
class_name ScriptedInputSource
extends InputSource

# Test double. Tests write into `state` directly; poll() reproduces the
# keyboard source's edge semantics so that jump_pressed lasts exactly one
# tick no matter which source the player is fed.

var state := MoveInput.new()

func press_jump() -> void:
	state.jump_pressed = true
	state.jump_held = true

func release_jump() -> void:
	state.jump_pressed = false
	state.jump_held = false

func poll() -> MoveInput:
	var snapshot := state.copy()
	state.jump_pressed = false
	return snapshot
```

- [ ] **Step 7: 运行测试确认通过**

Run: `pwsh tools/run_tests.ps1`
Expected: PASS，`failures: 0`。

- [ ] **Step 8: 提交**

```bash
git add scripts/player/input/ tests/test_input.gd
git commit -m "feat: add input abstraction with a scripted test double"
```

---

## Task 4: 状态机骨架

**Files:**
- Create: `scripts/player/states/player_state.gd`
- Create: `scripts/player/states/state_machine.gd`
- Test: `tests/test_state_machine.gd`

**Interfaces:**
- Consumes: `MoveInput`（Task 3）
- Produces:
  - `PlayerState extends Node`：常量 `KEEP: StringName = &""`、`GROUND: StringName = &"Ground"`、`AIR: StringName = &"Air"`；字段 `player`（无类型）、`config: MovementConfig`；方法 `enter(previous: StringName) -> void`、`physics_update(delta: float, input: MoveInput) -> StringName`、`exit() -> void`

**依赖方向（必须遵守）：** `Player -> 各状态 -> PlayerState`，单向。状态脚本**不得引用 `Player` 类**（不得写 `Player.AIR`、不得把 `player` 字段声明为 `Player` 类型）。GDScript 在解析期就要解析 `class_name` 全局符号，双向引用会构成循环并导致解析失败。
  - `StateMachine extends Node`：信号 `state_changed(from: StringName, to: StringName)`；字段 `current_name: StringName`；方法 `register(state_name: StringName, state: PlayerState) -> void`、`start(state_name: StringName) -> void`、`physics_update(delta: float, input: MoveInput) -> void`

- [ ] **Step 1: 写失败的测试**

创建 `tests/test_state_machine.gd`：

```gdscript
extends TestCase

# A local stub state so the state machine can be tested without a player.
# NOTE: the recorder is named `events`, not `log` — `log` is GDScript's
# built-in natural logarithm and shadowing it causes confusing errors.
class StubState:
	extends PlayerState
	var events: Array[String] = []
	var next_state: StringName = PlayerState.KEEP

	func enter(previous: StringName) -> void:
		events.append("enter:%s" % previous)

	func physics_update(_delta: float, _input: MoveInput) -> StringName:
		events.append("update")
		var n := next_state
		next_state = PlayerState.KEEP
		return n

	func exit() -> void:
		events.append("exit")


func _build() -> Array:
	var sm := StateMachine.new()
	var a := StubState.new()
	var b := StubState.new()
	sm.add_child(a)
	sm.add_child(b)
	sm.register(&"A", a)
	sm.register(&"B", b)
	return [sm, a, b]


func test_start_enters_the_initial_state() -> void:
	await step(1)
	var parts := _build()
	var sm: StateMachine = parts[0]
	var a: StubState = parts[1]
	sm.start(&"A")
	check(sm.current_name == &"A", "current_name not set by start()")
	check(a.events == ["enter:"], "initial enter() not called exactly once")
	sm.free()

func test_transition_calls_exit_then_enter_in_order() -> void:
	await step(1)
	var parts := _build()
	var sm: StateMachine = parts[0]
	var a: StubState = parts[1]
	var b: StubState = parts[2]
	sm.start(&"A")
	a.events.clear()
	a.next_state = &"B"
	sm.physics_update(1.0 / 60.0, MoveInput.new())
	check(a.events == ["update", "exit"], "outgoing state did not update then exit")
	check(b.events == ["enter:A"], "incoming state did not receive the previous name")
	check(sm.current_name == &"B", "current_name not updated")
	sm.free()

func test_keep_does_not_retrigger_enter() -> void:
	await step(1)
	var parts := _build()
	var sm: StateMachine = parts[0]
	var a: StubState = parts[1]
	sm.start(&"A")
	a.events.clear()
	sm.physics_update(1.0 / 60.0, MoveInput.new())
	sm.physics_update(1.0 / 60.0, MoveInput.new())
	check(a.events == ["update", "update"], "KEEP must not cause exit/enter")
	sm.free()

func test_state_changed_signal_reports_both_names() -> void:
	await step(1)
	var parts := _build()
	var sm: StateMachine = parts[0]
	var a: StubState = parts[1]
	var seen: Array[String] = []
	sm.state_changed.connect(func(from: StringName, to: StringName) -> void:
		seen.append("%s->%s" % [from, to]))
	sm.start(&"A")
	a.next_state = &"B"
	sm.physics_update(1.0 / 60.0, MoveInput.new())
	check(seen == ["->A", "A->B"], "state_changed payload wrong: %s" % str(seen))
	sm.free()
```

- [ ] **Step 2: 运行测试确认失败**

Run: `pwsh tools/run_tests.ps1`
Expected: FAIL，无法识别 `StateMachine` / `PlayerState`。

- [ ] **Step 3: 写状态基类**

创建 `scripts/player/states/player_state.gd`：

```gdscript
class_name PlayerState
extends Node

# One movement state. A state decides its own outgoing transitions: every
# question of the form "can I go from X to Y" has exactly one answer, and it
# lives in X's physics_update.

## Returned from physics_update to stay in the current state.
const KEEP: StringName = &""

# State names live here rather than on Player. GDScript resolves class_name
# globals at parse time, so if the states referenced Player.AIR while Player
# referenced GroundState, the two scripts would form a cycle and fail to
# resolve. Keeping the names on the state layer makes the dependency
# one-directional: Player -> states -> PlayerState.
const GROUND: StringName = &"Ground"
const AIR: StringName = &"Air"

## Set by Player before the state machine starts. Untyped for the same
## reason: a typed reference would reintroduce the cycle.
var player
var config: MovementConfig

func enter(_previous: StringName) -> void:
	pass

## Returns the name of the state to switch to, or KEEP to stay.
func physics_update(_delta: float, _input: MoveInput) -> StringName:
	return KEEP

func exit() -> void:
	pass
```

- [ ] **Step 4: 写状态机**

创建 `scripts/player/states/state_machine.gd`：

```gdscript
class_name StateMachine
extends Node

signal state_changed(from: StringName, to: StringName)

var current_name: StringName = &""

var _current: PlayerState = null
var _states: Dictionary = {}

func register(state_name: StringName, state: PlayerState) -> void:
	_states[state_name] = state

func start(state_name: StringName) -> void:
	assert(_states.has(state_name), "unknown state: %s" % state_name)
	_current = _states[state_name]
	current_name = state_name
	_current.enter(&"")
	state_changed.emit(&"", state_name)

func physics_update(delta: float, input: MoveInput) -> void:
	if _current == null:
		return
	var next: StringName = _current.physics_update(delta, input)
	if next == PlayerState.KEEP or next == current_name:
		return
	assert(_states.has(next), "transition to unknown state: %s" % next)
	var from := current_name
	_current.exit()
	_current = _states[next]
	current_name = next
	_current.enter(from)
	state_changed.emit(from, next)
```

- [ ] **Step 5: 运行测试确认通过**

Run: `pwsh tools/run_tests.ps1`
Expected: PASS，`failures: 0`。

- [ ] **Step 6: 提交**

```bash
git add scripts/player/states/ tests/test_state_machine.gd
git commit -m "feat: add player state machine with self-declared transitions"
```

---

## Task 5: Player 核心与 GroundState

**Files:**
- Create: `scripts/player/player.gd`
- Create: `scripts/player/states/ground_state.gd`
- Create: `tests/test_world.gd`
- Test: `tests/test_ground_state.gd`

**Interfaces:**
- Consumes: `MovementConfig`、`MoveInput`、`InputSource`、`StateMachine`、`PlayerState`
- Produces:
  - `Player extends CharacterBody3D`：
    - 字段 `config: MovementConfig`、`input_source: InputSource`、`state_machine: StateMachine`、`last_landing_speed: float`
    - 方法 `setup(cfg: MovementConfig, src: InputSource) -> void`、`wish_direction(input: MoveInput) -> Vector3`、`ground_accelerate(wish_dir: Vector3, target_speed: float, delta: float) -> void`、`air_accelerate(wish_dir: Vector3, delta: float) -> void`、`consume_jump() -> bool`、`horizontal_speed() -> float`
  - `GroundState extends PlayerState`
  - `TestWorld`（`class_name`）：静态方法 `build(tree: SceneTree, cfg: MovementConfig) -> Dictionary`，返回 `{"player": Player, "input": ScriptedInputSource, "floor": StaticBody3D}`；静态方法 `teardown(world: Dictionary) -> void`

- [ ] **Step 1: 写测试世界辅助**

创建 `tests/test_world.gd`：

```gdscript
class_name TestWorld
extends RefCounted

# Builds a minimal physics world: one large floor slab and one player driven
# by a ScriptedInputSource. Callers must await one physics frame after build()
# before touching global transforms.

static func build(tree: SceneTree, cfg: MovementConfig) -> Dictionary:
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
	floor_shape.shape = box
	floor_body.add_child(floor_shape)
	tree.root.add_child(floor_body)

	var player := Player.new()
	var body_shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.8
	capsule.radius = 0.4
	body_shape.shape = capsule
	player.add_child(body_shape)
	tree.root.add_child(player)

	var input := ScriptedInputSource.new()
	player.setup(cfg, input)

	return {"player": player, "input": input, "floor": floor_body}

## Places the floor so its top surface is y = 0 and drops the player onto it.
## Must be called after at least one physics frame has elapsed.
static func place(world: Dictionary) -> void:
	world["floor"].global_position = Vector3(0.0, -0.5, 0.0)
	world["player"].global_position = Vector3(0.0, 0.95, 0.0)

static func teardown(world: Dictionary) -> void:
	world["player"].queue_free()
	world["floor"].queue_free()
```

- [ ] **Step 2: 写失败的测试**

创建 `tests/test_ground_state.gd`：

```gdscript
extends TestCase

const TICK := 1.0 / 60.0

func _spawn() -> Dictionary:
	var cfg := MovementConfig.new()
	var world := TestWorld.build(tree, cfg)
	await step(1)
	TestWorld.place(world)
	await step(2)
	world["config"] = cfg
	return world

func test_player_starts_grounded() -> void:
	var world := await _spawn()
	check(world["player"].state_machine.current_name == &"Ground", \
		"player did not settle into Ground, got %s" % world["player"].state_machine.current_name)
	TestWorld.teardown(world)
	await step(1)

func test_forward_input_accelerates_the_player() -> void:
	var world := await _spawn()
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]

	input.state.move = Vector2(0.0, 1.0)
	await step(30)

	check_greater(player.horizontal_speed(), 0.5, "player did not accelerate under forward input")
	TestWorld.teardown(world)
	await step(1)

func test_sprint_reaches_a_higher_speed_than_walk() -> void:
	var world := await _spawn()
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]

	input.state.move = Vector2(0.0, 1.0)
	await step(90)
	var walk_speed := player.horizontal_speed()

	input.state.sprint_held = true
	await step(90)
	var sprint_speed := player.horizontal_speed()

	check_greater(sprint_speed, walk_speed, "sprinting was not faster than walking")
	TestWorld.teardown(world)
	await step(1)

func test_releasing_input_brings_the_player_to_rest() -> void:
	var world := await _spawn()
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]

	input.state.move = Vector2(0.0, 1.0)
	await step(60)
	check_greater(player.horizontal_speed(), 1.0, "precondition: player should be moving")

	input.state.move = Vector2.ZERO
	await step(60)
	check(player.horizontal_speed() < 0.2, \
		"friction did not stop the player, speed = %f" % player.horizontal_speed())
	TestWorld.teardown(world)
	await step(1)
```

- [ ] **Step 3: 运行测试确认失败**

Run: `pwsh tools/run_tests.ps1`
Expected: FAIL，无法识别 `Player` / `TestWorld`。

- [ ] **Step 4: 写 Player**

创建 `scripts/player/player.gd`：

```gdscript
class_name Player
extends CharacterBody3D

# Owns the shared movement data and the movement primitives. It deliberately
# contains no transition logic — that belongs to the states.
#
# State names live on PlayerState, not here: Player references the state
# classes, so the states must not reference Player back.

var config: MovementConfig
var input_source: InputSource
var state_machine: StateMachine

## Downward speed at the moment of the most recent landing. Read by CameraRig.
var last_landing_speed: float = 0.0
## Last polled input, exposed for the debug HUD.
var last_input: MoveInput = MoveInput.new()

var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0

func setup(cfg: MovementConfig, src: InputSource) -> void:
	config = cfg
	input_source = src
	_build_state_machine()

func _build_state_machine() -> void:
	state_machine = StateMachine.new()
	add_child(state_machine)

	var ground := GroundState.new()
	var air := AirState.new()
	for s in [ground, air]:
		s.player = self
		s.config = config
		state_machine.add_child(s)

	state_machine.register(PlayerState.GROUND, ground)
	state_machine.register(PlayerState.AIR, air)
	state_machine.start(PlayerState.GROUND)

func _physics_process(delta: float) -> void:
	if state_machine == null:
		return
	var input := input_source.poll()
	last_input = input
	_tick_timers(delta, input)
	state_machine.physics_update(delta, input)

func _tick_timers(delta: float, input: MoveInput) -> void:
	if is_on_floor():
		_coyote_timer = config.coyote_time
	else:
		_coyote_timer = maxf(_coyote_timer - delta, 0.0)

	if input.jump_pressed:
		_jump_buffer_timer = config.jump_buffer_time
	else:
		_jump_buffer_timer = maxf(_jump_buffer_timer - delta, 0.0)

## Spends a buffered jump if one is pending and the player is still within
## coyote time. Returns true at most once per press.
func consume_jump() -> bool:
	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0
		return true
	return false

## World-space horizontal direction the player is asking to move in.
func wish_direction(input: MoveInput) -> Vector3:
	var dir := global_transform.basis * Vector3(input.move.x, 0.0, -input.move.y)
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return Vector3.ZERO
	return dir.normalized()

func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()

## Ground movement: converge on the target velocity, and brake when idle.
func ground_accelerate(wish_dir: Vector3, target_speed: float, delta: float) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if wish_dir == Vector3.ZERO:
		horizontal = horizontal.move_toward(Vector3.ZERO, config.ground_friction * delta)
	else:
		horizontal = horizontal.move_toward(wish_dir * target_speed, config.ground_accel * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

## Air movement: only ever adds speed along wish_dir, and only up to
## air_max_speed measured along that direction. It never brakes, so momentum
## carried in from another state survives — P1's slide depends on this.
func air_accelerate(wish_dir: Vector3, delta: float) -> void:
	if wish_dir == Vector3.ZERO:
		return
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var speed_along_wish := horizontal.dot(wish_dir)
	var headroom := config.air_max_speed - speed_along_wish
	if headroom <= 0.0:
		return
	horizontal += wish_dir * minf(config.air_accel * delta, headroom)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
```

- [ ] **Step 5: 写 GroundState**

创建 `scripts/player/states/ground_state.gd`：

```gdscript
class_name GroundState
extends PlayerState

func enter(_previous: StringName) -> void:
	player.velocity.y = 0.0

func physics_update(delta: float, input: MoveInput) -> StringName:
	var wish_dir: Vector3 = player.wish_direction(input)
	var target_speed: float = config.sprint_speed if input.sprint_held else config.walk_speed
	player.ground_accelerate(wish_dir, target_speed, delta)

	if player.consume_jump():
		player.velocity.y = config.jump_velocity
		player.move_and_slide()
		return AIR

	# A small downward bias keeps the body glued to the floor across seams and
	# gentle slopes; without it is_on_floor() flickers while running.
	player.velocity.y = -2.0
	player.move_and_slide()

	if not player.is_on_floor():
		return AIR
	return KEEP
```

- [ ] **Step 6: 运行测试确认通过**

Run: `pwsh tools/run_tests.ps1`
Expected: PASS，`failures: 0`。

若 `test_player_starts_grounded` 失败，检查 `TestWorld.place()` 的落点：胶囊高 1.8、半径 0.4，静止时中心应在 `y = 0.9`，生成点设为 `0.95` 留了 5cm 余量。

- [ ] **Step 7: 提交**

```bash
git add scripts/player/player.gd scripts/player/states/ground_state.gd tests/test_world.gd tests/test_ground_state.gd
git commit -m "feat: add player body and ground movement state"
```

---

## Task 6: AirState 与跳跃

**Files:**
- Create: `scripts/player/states/air_state.gd`
- Test: `tests/test_air_state.gd`

**Interfaces:**
- Consumes: `Player`、`MovementConfig`、`MoveInput`、`PlayerState`
- Produces: `AirState extends PlayerState`。落地时写入 `player.last_landing_speed`（正值，单位 m/s）。

- [ ] **Step 1: 写失败的测试**

创建 `tests/test_air_state.gd`：

```gdscript
extends TestCase

func _spawn() -> Dictionary:
	var cfg := MovementConfig.new()
	var world := TestWorld.build(tree, cfg)
	await step(1)
	TestWorld.place(world)
	await step(2)
	world["config"] = cfg
	return world

func test_jump_leaves_the_ground() -> void:
	var world := await _spawn()
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]

	check(player.state_machine.current_name == &"Ground", "precondition: should start grounded")
	input.press_jump()
	await step(3)
	check(player.state_machine.current_name == &"Air", "jump did not enter Air")
	check_greater(player.velocity.y, 0.0, "jump did not produce upward velocity")

	TestWorld.teardown(world)
	await step(1)

func test_player_returns_to_ground_after_a_jump() -> void:
	var world := await _spawn()
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]

	input.press_jump()
	await step(3)
	input.release_jump()
	await step(180)

	check(player.state_machine.current_name == &"Ground", \
		"player never landed, state = %s" % player.state_machine.current_name)
	check_greater(player.last_landing_speed, 0.0, "landing speed was not recorded")

	TestWorld.teardown(world)
	await step(1)

func test_air_control_is_weaker_than_ground_control() -> void:
	var cfg := MovementConfig.new()

	# Ground run-up: how much speed is gained in 10 ticks from rest, grounded.
	var ground_world := TestWorld.build(tree, cfg)
	await step(1)
	TestWorld.place(ground_world)
	await step(2)
	var ground_player: Player = ground_world["player"]
	ground_world["input"].state.move = Vector2(0.0, 1.0)
	await step(10)
	var ground_gain := ground_player.horizontal_speed()
	TestWorld.teardown(ground_world)
	await step(1)

	# Air run-up: same 10 ticks of forward input, but airborne from rest.
	var air_world := TestWorld.build(tree, cfg)
	await step(1)
	air_world["floor"].global_position = Vector3(0.0, -60.0, 0.0)
	air_world["player"].global_position = Vector3(0.0, 0.0, 0.0)
	await step(2)
	var air_player: Player = air_world["player"]
	air_world["input"].state.move = Vector2(0.0, 1.0)
	await step(10)
	var air_gain := air_player.horizontal_speed()
	TestWorld.teardown(air_world)
	await step(1)

	check_greater(ground_gain, air_gain, \
		"air control must be weaker than ground control (ground %f vs air %f)" % [ground_gain, air_gain])

func test_coyote_time_allows_a_jump_just_after_leaving_ground() -> void:
	var world := await _spawn()
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]

	# Force the player off the floor without jumping, then jump within the
	# coyote window.
	player.global_position = Vector3(0.0, 3.0, 0.0)
	await step(2)
	check(player.state_machine.current_name == &"Air", "precondition: should be airborne")

	input.press_jump()
	await step(1)
	check_greater(player.velocity.y, 0.0, "coyote jump did not fire")

	TestWorld.teardown(world)
	await step(1)
```

- [ ] **Step 2: 运行测试确认失败**

Run: `pwsh tools/run_tests.ps1`
Expected: FAIL，无法识别 `AirState`。

- [ ] **Step 3: 写 AirState**

创建 `scripts/player/states/air_state.gd`：

```gdscript
class_name AirState
extends PlayerState

func physics_update(delta: float, input: MoveInput) -> StringName:
	var wish_dir: Vector3 = player.wish_direction(input)
	player.air_accelerate(wish_dir, delta)

	# Coyote time: Player.consume_jump() already gates on the timer, so a jump
	# buffered just after walking off a ledge still fires here.
	if player.consume_jump():
		player.velocity.y = config.jump_velocity

	player.velocity.y -= config.gravity * delta
	player.velocity.y = maxf(player.velocity.y, -config.terminal_velocity)

	# Capture the impact speed before move_and_slide() zeroes it on contact.
	var impact_speed := maxf(-player.velocity.y, 0.0)
	player.move_and_slide()

	if player.is_on_floor():
		player.last_landing_speed = impact_speed
		return GROUND
	return KEEP
```

- [ ] **Step 4: 运行测试确认通过**

Run: `pwsh tools/run_tests.ps1`
Expected: PASS，`failures: 0`。

- [ ] **Step 5: 提交**

```bash
git add scripts/player/states/air_state.gd tests/test_air_state.gd
git commit -m "feat: add air state with gravity, air control, and coyote jump"
```

---

## Task 7: 玩家场景与相机

**Files:**
- Create: `scripts/camera/camera_rig.gd`
- Create: `scenes/player/player.tscn`
- Modify: `scripts/player/player.gd`（接入相机与鼠标输入）
- Test: `tests/test_camera_rig.gd`

**Interfaces:**
- Consumes: `MovementConfig`、`Player`
- Produces:
  - `CameraRig extends Node3D`：`@onready var camera: Camera3D`；方法 `setup(cfg: MovementConfig) -> void`、`apply_look(look_delta: Vector2, body: Node3D) -> void`、`update_effects(delta: float, horizontal_speed: float, grounded: bool) -> void`、`punch_landing(speed: float) -> void`
  - `Player` 新增：`@export var camera_rig: CameraRig`；`_input(event)` 中把鼠标位移交给 `KeyboardInputSource.accumulate_look()`
  - `scenes/player/player.tscn`：根节点 `Player`，子节点 `CollisionShape3D`、`CameraRig`（含 `Camera3D`）、`BodyRoot`（P5 骨骼模型预留，P0 为空 `Node3D`）

- [ ] **Step 1: 写失败的测试**

创建 `tests/test_camera_rig.gd`：

```gdscript
extends TestCase

const TICK := 1.0 / 60.0

func _make_rig() -> CameraRig:
	var rig := CameraRig.new()
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	rig.add_child(cam)
	tree.root.add_child(rig)
	return rig

func test_fov_widens_as_speed_rises() -> void:
	var cfg := MovementConfig.new()
	var rig := _make_rig()
	await step(1)
	rig.setup(cfg)

	for i in 120:
		rig.update_effects(TICK, 0.0, true)
	var slow_fov := rig.camera.fov

	for i in 120:
		rig.update_effects(TICK, cfg.fov_speed_ref, true)
	var fast_fov := rig.camera.fov

	check_greater(fast_fov, slow_fov, "FOV did not widen with speed")
	rig.queue_free()
	await step(1)

func test_landing_dip_lowers_then_recovers() -> void:
	var cfg := MovementConfig.new()
	var rig := _make_rig()
	await step(1)
	rig.setup(cfg)

	rig.punch_landing(cfg.land_dip_speed_ref)
	rig.update_effects(TICK, 0.0, true)
	var dipped := rig.camera.position.y
	check(dipped < 0.0, "landing did not lower the camera, y = %f" % dipped)

	for i in 300:
		rig.update_effects(TICK, 0.0, true)
	check_approx(rig.camera.position.y, 0.0, 0.01, "camera did not recover from the landing dip")

	rig.queue_free()
	await step(1)

func test_pitch_is_clamped() -> void:
	var cfg := MovementConfig.new()
	var rig := _make_rig()
	await step(1)
	rig.setup(cfg)

	var body := Node3D.new()
	tree.root.add_child(body)
	await step(1)

	# Push the view far past vertical in both directions.
	for i in 200:
		rig.apply_look(Vector2(0.0, -1000.0), body)
	check(rig.rotation.x <= deg_to_rad(cfg.pitch_limit_deg) + 0.001, "pitch exceeded the upper limit")

	for i in 400:
		rig.apply_look(Vector2(0.0, 1000.0), body)
	check(rig.rotation.x >= -deg_to_rad(cfg.pitch_limit_deg) - 0.001, "pitch exceeded the lower limit")

	rig.queue_free()
	body.queue_free()
	await step(1)
```

- [ ] **Step 2: 运行测试确认失败**

Run: `pwsh tools/run_tests.ps1`
Expected: FAIL，无法识别 `CameraRig`。

- [ ] **Step 3: 写 CameraRig**

创建 `scripts/camera/camera_rig.gd`：

```gdscript
class_name CameraRig
extends Node3D

# Everything the camera does that is not "sit on the player's head".
# Deliberately decoupled from physics: it is fed speed and grounded-ness and
# owns no movement logic of its own.

@onready var camera: Camera3D = $Camera3D

var _config: MovementConfig
var _pitch: float = 0.0
var _bob_phase: float = 0.0
var _dip: float = 0.0

func setup(cfg: MovementConfig) -> void:
	_config = cfg
	if camera != null:
		camera.fov = cfg.fov_base

## Yaw turns the body so movement follows the view; pitch stays on the rig.
func apply_look(look_delta: Vector2, body: Node3D) -> void:
	if _config == null:
		return
	body.rotate_y(-look_delta.x * _config.mouse_sensitivity)
	var limit := deg_to_rad(_config.pitch_limit_deg)
	_pitch = clampf(_pitch - look_delta.y * _config.mouse_sensitivity, -limit, limit)
	rotation.x = _pitch

func update_effects(delta: float, horizontal_speed: float, grounded: bool) -> void:
	if _config == null or camera == null:
		return

	var speed_ratio := clampf(horizontal_speed / maxf(_config.fov_speed_ref, 0.001), 0.0, 1.0)

	var target_fov := lerpf(_config.fov_base, _config.fov_max, speed_ratio)
	camera.fov = lerpf(camera.fov, target_fov, clampf(_config.fov_lerp_speed * delta, 0.0, 1.0))

	var bob := 0.0
	if grounded:
		_bob_phase += delta * _config.bob_frequency * horizontal_speed
		bob = sin(_bob_phase) * _config.bob_amplitude * speed_ratio

	_dip = move_toward(_dip, 0.0, _config.land_dip_recover * delta)
	camera.position.y = bob - _dip

## Called on landing. `speed` is the downward speed at the moment of impact.
func punch_landing(speed: float) -> void:
	if _config == null:
		return
	var strength := clampf(speed / maxf(_config.land_dip_speed_ref, 0.001), 0.0, 1.0)
	_dip = maxf(_dip, strength * _config.land_dip_max)
```

- [ ] **Step 4: 运行测试确认通过**

Run: `pwsh tools/run_tests.ps1`
Expected: PASS，`failures: 0`。

- [ ] **Step 5: 把相机接进 Player**

修改 `scripts/player/player.gd`。在字段区加入：

```gdscript
## Assigned in player.tscn. Optional so headless tests can run without one.
@export var camera_rig: CameraRig
```

在 `_physics_process` 末尾追加相机驱动，并在状态机更新前记录着地状态以侦测落地：

```gdscript
func _physics_process(delta: float) -> void:
	if state_machine == null:
		return
	var input := input_source.poll()
	last_input = input
	_tick_timers(delta, input)

	var was_airborne := not is_on_floor()
	if camera_rig != null:
		camera_rig.apply_look(input.look, self)

	state_machine.physics_update(delta, input)

	if camera_rig != null:
		if was_airborne and is_on_floor():
			camera_rig.punch_landing(last_landing_speed)
		camera_rig.update_effects(delta, horizontal_speed(), is_on_floor())
```

新增鼠标处理（放在 `_physics_process` 之后）。

**注意：这里没有 `_ready()` 去捕获鼠标。** 捕获动作放在 `Arena._ready()`（Task 8），因为 headless 测试会直接 `Player.new()`，若在 Player 里操作 `Input.mouse_mode` 会在无显示服务器的环境下产生噪音。会话级的关注点归关卡管，不归角色管。

```gdscript
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and input_source is KeyboardInputSource:
		(input_source as KeyboardInputSource).accumulate_look(event.relative)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif event.physical_keycode == KEY_F11:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
```

- [ ] **Step 6: 写玩家场景生成器并生成场景**

创建 `tools/build_player_scene.gd`：

```gdscript
extends SceneTree

# Generates scenes/player/player.tscn. Scenes are built in code rather than by
# hand so the whole project is reproducible without an editor session.
#
# Run with:
#   .engine\Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#       --script res://tools/build_player_scene.gd
#
# One-shot scaffolding: once the .tscn exists it is the source of truth, and
# re-running this would discard any later edits made in the editor.

const OUTPUT := "res://scenes/player/player.tscn"

func _initialize() -> void:
	_run()

func _run() -> void:
	var player := CharacterBody3D.new()
	player.name = "Player"
	player.set_script(load("res://scripts/player/player.gd"))

	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.8
	capsule.radius = 0.4
	shape.shape = capsule
	player.add_child(shape)
	shape.owner = player

	var rig := Node3D.new()
	rig.name = "CameraRig"
	rig.set_script(load("res://scripts/camera/camera_rig.gd"))
	# Eye height: 0.7 above the capsule centre puts the view near the top of a
	# 1.8 m body without clipping through the collision shape.
	rig.position = Vector3(0.0, 0.7, 0.0)
	player.add_child(rig)
	rig.owner = player

	var cam := Camera3D.new()
	cam.name = "Camera3D"
	rig.add_child(cam)
	cam.owner = player

	# Reserved for the P5 procedural first-person body. Empty for now, but
	# present so adding a skeleton later does not restructure the scene.
	var body_root := Node3D.new()
	body_root.name = "BodyRoot"
	player.add_child(body_root)
	body_root.owner = player

	player.camera_rig = rig

	DirAccess.make_dir_recursive_absolute("res://scenes/player")
	var packed := PackedScene.new()
	var pack_error := packed.pack(player)
	assert(pack_error == OK, "pack failed: %d" % pack_error)
	var save_error := ResourceSaver.save(packed, OUTPUT)
	assert(save_error == OK, "save failed: %d" % save_error)
	print("wrote ", OUTPUT)
	quit(0)
```

运行生成器：

```powershell
.\.engine\Godot_v4.7.1-stable_win64_console.exe --headless --path . --import | Out-Null
.\.engine\Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tools/build_player_scene.gd
```

Expected: 输出 `wrote res://scenes/player/player.tscn`，退出码 0。

- [ ] **Step 6b: 写场景结构测试**

创建 `tests/test_player_scene.gd`。生成器只保证"写出去了"，这个测试保证"写对了"：

```gdscript
extends TestCase

const SCENE := "res://scenes/player/player.tscn"

func test_player_scene_has_the_expected_structure() -> void:
	await step(1)
	check(ResourceLoader.exists(SCENE), "player.tscn was not generated")
	var packed: PackedScene = ResourceLoader.load(SCENE, "", ResourceLoader.CACHE_MODE_IGNORE)
	var player = packed.instantiate()
	tree.root.add_child(player)
	await step(1)

	check(player is CharacterBody3D, "root is not a CharacterBody3D")
	check(player.get_node_or_null("CollisionShape3D") != null, "CollisionShape3D missing")
	check(player.get_node_or_null("CameraRig") != null, "CameraRig missing")
	check(player.get_node_or_null("CameraRig/Camera3D") != null, "Camera3D missing")
	check(player.get_node_or_null("BodyRoot") != null, "BodyRoot (P5 reservation) missing")

	# The exported reference must survive serialisation, or the camera silently
	# does nothing at runtime.
	check(player.camera_rig != null, "camera_rig export was not wired")
	check(player.camera_rig == player.get_node("CameraRig"), "camera_rig points at the wrong node")

	var capsule := (player.get_node("CollisionShape3D") as CollisionShape3D).shape as CapsuleShape3D
	check(capsule != null, "collision shape is not a capsule")
	check_approx(capsule.height, 1.8, 0.001, "capsule height wrong")
	check_approx(capsule.radius, 0.4, 0.001, "capsule radius wrong")

	player.queue_free()
	await step(1)
```

- [ ] **Step 7: 运行测试确认没有回归**

Run: `pwsh tools/run_tests.ps1`
Expected: PASS，`failures: 0`。

- [ ] **Step 8: 提交**

```bash
git add scripts/camera/ scripts/player/player.gd scenes/player/player.tscn tools/build_player_scene.gd tests/test_camera_rig.gd tests/test_player_scene.gd
git commit -m "feat: add camera rig with speed FOV, head bob, and landing dip"
```

---

## Task 8: 靶场主场景与跳跃区

**Files:**
- Create: `scenes/main.tscn`
- Create: `scripts/level/arena.gd`
- Modify: `project.godot`（设置主场景）

**Interfaces:**
- Consumes: `scenes/player/player.tscn`、`MovementConfig`
- Produces:
  - `Arena extends Node3D`：`@export var player: Player`、`@export var spawn_point: Marker3D`、`@export var config: MovementConfig`；方法 `reset_player() -> void`
  - `project.godot` 中 `run/main_scene = "res://scenes/main.tscn"`

**说明：** P0 只搭北侧跳跃区。其余三个练习区（滑铲 / 蹬墙 / 翻越）分别在 P1~P3 加入，避免搭出用不上的几何体。

- [ ] **Step 1: 写靶场脚本**

创建 `scripts/level/arena.gd`：

```gdscript
class_name Arena
extends Node3D

# Owns the shared MovementConfig instance and the respawn behaviour. The
# config lives here rather than on the player so the tuning panel and the
# player read from the same object.

@export var player: Player
@export var spawn_point: Marker3D
## Leave empty to create a fresh MovementConfig with default values at runtime.
@export var config: MovementConfig

func _ready() -> void:
	if config == null:
		config = MovementConfig.new()
	player.setup(config, KeyboardInputSource.new())
	if player.camera_rig != null:
		player.camera_rig.setup(config)

	# Session-level concern, deliberately not in Player: headless tests
	# instantiate Player directly and must not touch the display server.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	var panel := get_node_or_null("TuningPanel")
	if panel != null:
		panel.config = config

	reset_player()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_R:
			reset_player()

func reset_player() -> void:
	player.velocity = Vector3.ZERO
	player.global_position = spawn_point.global_position
	player.rotation = Vector3.ZERO
```

- [ ] **Step 2: 写靶场生成器并生成主场景**

创建 `tools/build_main_scene.gd`。几何体用 `StaticBody3D` + `BoxShape3D` + `BoxMesh` 组合，**不用 `CSGBox3D`** —— CSG 的碰撞体是运行时生成的，在无编辑器环境下时序不可靠，而显式碰撞体没有这个问题。

```gdscript
extends SceneTree

# Generates scenes/main.tscn: the graybox arena. P0 only builds the northern
# jump area; the slide / vault / wall-run areas arrive with P1-P3 so we never
# carry geometry nothing uses yet.
#
# Run with:
#   .engine\Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#       --script res://tools/build_main_scene.gd

const OUTPUT := "res://scenes/main.tscn"

var _root: Node3D

func _initialize() -> void:
	_run()

## Solid box with explicit collision. CSGBox3D is avoided on purpose: its
## collision body is generated at runtime and is not reliably present on the
## first physics frame in a headless run.
func _box(box_name: String, size: Vector3, pos: Vector3, colour: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = box_name
	body.position = pos

	var shape := CollisionShape3D.new()
	shape.name = "Collision"
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	mesh.material = material
	mesh_instance.mesh = mesh
	body.add_child(mesh_instance)

	return body

func _attach(parent: Node3D, child: Node3D) -> void:
	parent.add_child(child)
	child.owner = _root
	for grandchild in child.get_children():
		grandchild.owner = _root

func _run() -> void:
	_root = Node3D.new()
	_root.name = "Arena"
	_root.set_script(load("res://scripts/level/arena.gd"))

	var light := DirectionalLight3D.new()
	light.name = "Sun"
	light.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(-30.0), 0.0)
	light.shadow_enabled = true
	_attach(_root, light)

	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	world_env.environment = environment
	_attach(_root, world_env)

	var spawn := Marker3D.new()
	spawn.name = "SpawnPoint"
	spawn.position = Vector3(0.0, 1.0, 0.0)
	_attach(_root, spawn)

	var ground := Color(0.42, 0.44, 0.47)
	var gap_colour := Color(0.38, 0.52, 0.62)
	var step_colour := Color(0.56, 0.50, 0.38)
	var drop_colour := Color(0.58, 0.40, 0.44)

	_attach(_root, _box("Floor", Vector3(60.0, 1.0, 60.0), Vector3(0.0, -0.5, 0.0), ground))

	var jump_area := Node3D.new()
	jump_area.name = "JumpArea"
	jump_area.position = Vector3(0.0, 0.0, -12.0)
	_attach(_root, jump_area)

	# Increasing gaps: 2.0, 2.5, 3.0, 3.5, 4.0 m between platform edges.
	# Whichever platform the player can still reach reveals the jump range.
	var gap_z := [0.0, -5.0, -10.5, -16.5, -23.0, -30.0]
	for i in gap_z.size():
		_attach(jump_area, _box("Gap%d" % (i + 1), Vector3(3.0, 1.0, 3.0),
			Vector3(-9.0, 0.5, gap_z[i]), gap_colour))

	# Increasing heights: 1..6 m, for reading off the maximum step-up.
	for i in 6:
		var height := float(i + 1)
		_attach(jump_area, _box("Step%d" % (i + 1), Vector3(3.0, height, 3.0),
			Vector3(0.0, height * 0.5, -4.0 * i), step_colour))

	# Drop towers, for comparing landing-dip strength across fall heights.
	_attach(jump_area, _box("DropLow", Vector3(4.0, 1.0, 4.0), Vector3(9.0, 3.0, 0.0), drop_colour))
	_attach(jump_area, _box("DropMid", Vector3(4.0, 1.0, 4.0), Vector3(9.0, 8.0, -6.0), drop_colour))
	_attach(jump_area, _box("DropHigh", Vector3(4.0, 1.0, 4.0), Vector3(9.0, 15.0, -12.0), drop_colour))

	var player_scene: PackedScene = load("res://scenes/player/player.tscn")
	var player := player_scene.instantiate()
	player.name = "Player"
	_root.add_child(player)
	player.owner = _root
	# An instantiated sub-scene keeps its own internal ownership; marking only
	# the instance root is what makes it serialise as an instance rather than
	# an expanded copy.

	_root.player = player
	_root.spawn_point = spawn

	DirAccess.make_dir_recursive_absolute("res://scenes")
	var packed := PackedScene.new()
	var pack_error := packed.pack(_root)
	assert(pack_error == OK, "pack failed: %d" % pack_error)
	var save_error := ResourceSaver.save(packed, OUTPUT)
	assert(save_error == OK, "save failed: %d" % save_error)
	print("wrote ", OUTPUT)
	quit(0)
```

运行：

```powershell
.\.engine\Godot_v4.7.1-stable_win64_console.exe --headless --path . --import | Out-Null
.\.engine\Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tools/build_main_scene.gd
```

Expected: 输出 `wrote res://scenes/main.tscn`，退出码 0。

- [ ] **Step 3: 设置主场景**

直接编辑 `project.godot`，在 `[application]` 段内加入：

```ini
run/main_scene="res://scenes/main.tscn"
```

**改完后必须确认 `renderer/rendering_method` 仍为 `gl_compatibility`**（Global Constraints 锁定项，Web 导出的唯一可行渲染器）。用以下命令核对：

```powershell
Select-String -Path project.godot -Pattern "main_scene|rendering_method"
```

- [ ] **Step 4: 写靶场测试**

创建 `tests/test_arena.gd`。这些断言替代了原本交给人做的验收项中可自动化的部分：

```gdscript
extends TestCase

const SCENE := "res://scenes/main.tscn"

func _load_arena() -> Node3D:
	var packed: PackedScene = ResourceLoader.load(SCENE, "", ResourceLoader.CACHE_MODE_IGNORE)
	var arena = packed.instantiate()
	tree.root.add_child(arena)
	await step(3)
	return arena

func test_arena_scene_is_wired() -> void:
	await step(1)
	check(ResourceLoader.exists(SCENE), "main.tscn was not generated")
	var arena = await _load_arena()

	check(arena.player != null, "Arena.player export was not wired")
	check(arena.spawn_point != null, "Arena.spawn_point export was not wired")
	check(arena.config != null, "Arena did not create a default MovementConfig")
	check(arena.get_node_or_null("Floor") != null, "Floor missing")
	check(arena.get_node_or_null("JumpArea/Gap6") != null, "jump area geometry missing")
	check(arena.get_node_or_null("JumpArea/DropHigh") != null, "drop towers missing")

	arena.queue_free()
	await step(1)

func test_player_and_panel_share_one_config_instance() -> void:
	await step(1)
	var arena = await _load_arena()
	# If these are different objects, dragging a slider changes nothing.
	check(arena.player.config == arena.config, "player does not share the arena's config")
	arena.queue_free()
	await step(1)

func test_player_settles_on_the_floor_at_spawn() -> void:
	await step(1)
	var arena = await _load_arena()
	await step(60)
	check(arena.player.is_on_floor(), "player did not settle onto the arena floor")
	check(arena.player.state_machine.current_name == &"Ground", "player is not in Ground at rest")
	arena.queue_free()
	await step(1)

func test_reset_returns_the_player_to_spawn() -> void:
	await step(1)
	var arena = await _load_arena()
	arena.player.global_position = Vector3(20.0, 12.0, -20.0)
	await step(5)
	arena.reset_player()
	await step(1)
	var offset: float = arena.player.global_position.distance_to(arena.spawn_point.global_position)
	check(offset < 0.01, "reset did not return the player to spawn (offset %f)" % offset)
	check(arena.player.velocity.length() < 0.01, "reset did not clear velocity")
	arena.queue_free()
	await step(1)

func test_movement_follows_the_view_direction() -> void:
	await step(1)
	var arena = await _load_arena()
	await step(30)
	var player = arena.player

	# Face -X by yawing 90 degrees, then hold forward. Velocity must follow the
	# body's facing, not a fixed world axis.
	player.rotation.y = deg_to_rad(90.0)
	var input := ScriptedInputSource.new()
	input.state.move = Vector2(0.0, 1.0)
	player.input_source = input
	await step(30)

	var horizontal := Vector3(player.velocity.x, 0.0, player.velocity.z)
	check_greater(horizontal.length(), 1.0, "player did not move")
	check(horizontal.normalized().x < -0.9, \
		"movement did not follow the view direction, dir = %s" % horizontal.normalized())

	arena.queue_free()
	await step(1)
```

- [ ] **Step 5: 截图验收**

创建 `tools/capture.gd`：

```gdscript
extends SceneTree

# Renders a scene off the main game loop and writes a PNG, so visual checks do
# not need a human at the keyboard.
#
# Run with (note: no --headless, a real rendering context is required):
#   .engine\Godot_v4.7.1-stable_win64_console.exe --path . --resolution 960x540 \
#       --script res://tools/capture.gd -- <scene_path> <output_png> [settle_frames]

func _initialize() -> void:
	_run()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var scene_path := args[0] if args.size() > 0 else "res://scenes/main.tscn"
	var output := args[1] if args.size() > 1 else "res://capture.png"
	var settle := int(args[2]) if args.size() > 2 else 90

	var packed: PackedScene = load(scene_path)
	var instance = packed.instantiate()
	root.add_child(instance)

	# The arena grabs the mouse in _ready(); give it straight back so a capture
	# run never steals the pointer from whoever is using the machine.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	for i in settle:
		await process_frame
	await RenderingServer.frame_post_draw

	var image := root.get_texture().get_image()
	if image == null:
		push_error("viewport image was null")
		quit(1)
		return
	var error := image.save_png(output)
	print("capture: %s -> %s (err %d)" % [scene_path, output, error])
	quit(0 if error == OK else 1)
```

运行截图：

```powershell
.\.engine\Godot_v4.7.1-stable_win64_console.exe --path . --resolution 960x540 --script res://tools/capture.gd -- res://scenes/main.tscn res://.captures/p0_arena.png 120
```

把生成的 PNG 路径写进任务报告。**控制者会实际查看这张图**，确认：地面与跳跃区几何体可见、光照正常、天空盒渲染、玩家视角高度合理、画面不是黑屏或纯色。

`.captures/` 目录加入 `.gitignore`（截图是验证产物，不是源码）。

- [ ] **Step 6: 无法自动验证的项（如实上报，不要假装已验证）**

以下几项依赖真人操作，本任务**不予验证**，在报告中原样列出留待使用者确认：

1. 鼠标转视角是否跟手、灵敏度是否合适
2. `Shift` 冲刺、`Space` 跳跃的实际手感
3. `Esc` 释放鼠标 / `F11` 重新捕获
4. 落地下沉的观感强度

- [ ] **Step 7: 运行测试确认没有回归**

Run: `pwsh tools/run_tests.ps1`
Expected: PASS，`failures: 0`。

- [ ] **Step 8: 提交**

```bash
git add scenes/main.tscn scripts/level/arena.gd tools/build_main_scene.gd tools/capture.gd tests/test_arena.gd project.godot .gitignore
git commit -m "feat: add graybox arena with the jump practice area"
```

---

## Task 9: 调试 HUD

**Files:**
- Create: `scripts/debug/debug_hud.gd`
- Modify: `scenes/main.tscn`（挂载 HUD）

**Interfaces:**
- Consumes: `Player`
- Produces: `DebugHud extends CanvasLayer`：`@export var player: Player`；`Tab` 切换可见性

- [ ] **Step 1: 写 HUD**

创建 `scripts/debug/debug_hud.gd`：

```gdscript
class_name DebugHud
extends CanvasLayer

# Tab-toggled readout of everything needed to judge whether a tuning change
# did what was intended.

@export var player: Player

var _label: Label

func _ready() -> void:
	_label = Label.new()
	_label.position = Vector2(16.0, 16.0)
	_label.add_theme_color_override("font_color", Color(0.9, 1.0, 0.9))
	_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	_label.add_theme_constant_override("outline_size", 4)
	add_child(_label)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_TAB:
			visible = not visible

func _process(_delta: float) -> void:
	if not visible or player == null or player.state_machine == null:
		return
	var pos := player.global_position
	_label.text = "\n".join([
		"state      %s" % player.state_machine.current_name,
		"speed h    %.2f m/s" % player.horizontal_speed(),
		"speed v    %.2f m/s" % player.velocity.y,
		"position   (%.1f, %.1f, %.1f)" % [pos.x, pos.y, pos.z],
		"grounded   %s" % ("yes" if player.is_on_floor() else "no"),
		"last land  %.2f m/s" % player.last_landing_speed,
		"fps        %d" % Engine.get_frames_per_second(),
		"",
		"Tab HUD   F1 tuning   R reset   Esc release mouse",
	])
```

- [ ] **Step 2: 把 HUD 加进靶场生成器并重新生成**

修改 `tools/build_main_scene.gd`：在 `_run()` 中把玩家实例化并赋给 `_root.player` 之后、打包之前，加入：

```gdscript
	var hud := CanvasLayer.new()
	hud.name = "DebugHud"
	hud.set_script(load("res://scripts/debug/debug_hud.gd"))
	_root.add_child(hud)
	hud.owner = _root
	hud.player = player
```

重新生成主场景：

```powershell
.\.engine\Godot_v4.7.1-stable_win64_console.exe --headless --path . --import | Out-Null
.\.engine\Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tools/build_main_scene.gd
```

- [ ] **Step 3: 写 HUD 测试**

在 `tests/test_arena.gd` 末尾追加：

```gdscript
func test_debug_hud_is_wired_and_reports_state() -> void:
	await step(1)
	var arena = await _load_arena()
	var hud = arena.get_node_or_null("DebugHud")
	check(hud != null, "DebugHud node missing from the arena")
	check(hud.player == arena.player, "DebugHud.player export was not wired")

	await step(30)
	# _process only refreshes while visible, which is the default.
	check(hud.visible, "HUD should start visible")
	var text: String = hud._label.text
	check(text.contains("state"), "HUD text missing the state line")
	check(text.contains("Ground"), "HUD did not report the resting state, text = %s" % text)

	arena.queue_free()
	await step(1)
```

- [ ] **Step 4: 截图验收**

```powershell
.\.engine\Godot_v4.7.1-stable_win64_console.exe --path . --resolution 960x540 --script res://tools/capture.gd -- res://scenes/main.tscn res://.captures/p0_hud.png 120
```

报告中给出 PNG 路径。**控制者会查看该图**，确认左上角 HUD 文本可读、行内容合理（state / speed / position / grounded / fps）。

`Tab` 切换属于键盘交互，headless 不予验证，留待使用者确认。

- [ ] **Step 5: 运行测试确认没有回归**

Run: `pwsh tools/run_tests.ps1`
Expected: PASS，`failures: 0`。

- [ ] **Step 6: 提交**

```bash
git add scripts/debug/debug_hud.gd scenes/main.tscn tools/build_main_scene.gd tests/test_arena.gd
git commit -m "feat: add tab-toggled debug HUD"
```

---

## Task 10: 实时调参面板

**Files:**
- Create: `scripts/debug/tuning_panel.gd`
- Modify: `scenes/main.tscn`（挂载面板）

**Interfaces:**
- Consumes: `MovementConfig`
- Produces: `TuningPanel extends CanvasLayer`：`@export var config: MovementConfig`；`F1` 切换可见性；预设保存到 `user://presets/<name>.tres`

**设计说明：** 滑块**从 `MovementConfig` 的属性表自动生成**，不硬编码。这样 P1~P5 往 config 里加参数时，面板自动多出对应滑块，无需修改本文件。

- [ ] **Step 1: 写面板**

创建 `scripts/debug/tuning_panel.gd`：

```gdscript
class_name TuningPanel
extends CanvasLayer

# Runtime tuning UI. Sliders are generated from MovementConfig's property list
# rather than hardcoded, so parameters added in later phases show up here for
# free.

const PRESET_DIR := "user://presets"
## Slider range is this multiple of the property's default value.
const RANGE_FACTOR := 3.0

@export var config: MovementConfig

var _panel: PanelContainer
var _preset_name: LineEdit
var _status: Label

func _ready() -> void:
	visible = false
	DirAccess.make_dir_recursive_absolute(PRESET_DIR)
	# Godot readies children before parents, so `config` is still null here.
	# Arena injects it during its own _ready(); deferring the build to the end
	# of the frame guarantees the injection has already happened.
	call_deferred("_build_ui")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F1:
			visible = not visible
			# Releasing the mouse is required to actually drag the sliders.
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if visible else Input.MOUSE_MODE_CAPTURED

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_panel.position = Vector2(-430.0, 8.0)
	_panel.custom_minimum_size = Vector2(420.0, 0.0)
	add_child(_panel)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(420.0, 620.0)
	_panel.add_child(scroll)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)

	_add_preset_row(column)

	var defaults := MovementConfig.new()
	var current_group := ""
	for property in config.get_property_list():
		if property.usage & PROPERTY_USAGE_GROUP:
			current_group = property.name
			var heading := Label.new()
			heading.text = "— %s —" % current_group
			column.add_child(heading)
			continue
		if not (property.usage & PROPERTY_USAGE_EDITOR):
			continue
		if property.type != TYPE_FLOAT:
			continue
		_add_slider(column, property.name, defaults.get(property.name))

func _add_preset_row(column: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	column.add_child(row)

	_preset_name = LineEdit.new()
	_preset_name.text = "feel_a"
	_preset_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_preset_name)

	var save_button := Button.new()
	save_button.text = "Save"
	save_button.pressed.connect(_on_save)
	row.add_child(save_button)

	var load_button := Button.new()
	load_button.text = "Load"
	load_button.pressed.connect(_on_load)
	row.add_child(load_button)

	_status = Label.new()
	column.add_child(_status)

func _add_slider(column: VBoxContainer, property_name: String, default_value: float) -> void:
	var row := HBoxContainer.new()
	column.add_child(row)

	var name_label := Label.new()
	name_label.text = property_name
	name_label.custom_minimum_size = Vector2(180.0, 0.0)
	row.add_child(name_label)

	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(64.0, 0.0)
	row.add_child(value_label)

	var slider := HSlider.new()
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.min_value = 0.0
	slider.max_value = maxf(absf(default_value) * RANGE_FACTOR, 0.01)
	slider.step = slider.max_value / 500.0
	slider.value = config.get(property_name)
	row.add_child(slider)

	value_label.text = "%.4f" % slider.value
	slider.value_changed.connect(func(v: float) -> void:
		config.set(property_name, v)
		value_label.text = "%.4f" % v)

	# Reloading a preset must move the sliders too, not just the values.
	slider.set_meta("property_name", property_name)

func _sliders() -> Array[HSlider]:
	var out: Array[HSlider] = []
	for node in _panel.find_children("*", "HSlider", true, false):
		out.append(node as HSlider)
	return out

func _on_save() -> void:
	var path := "%s/%s.tres" % [PRESET_DIR, _preset_name.text]
	var error := ResourceSaver.save(config, path)
	_status.text = "saved %s" % path if error == OK else "save failed (%d)" % error

func _on_load() -> void:
	var path := "%s/%s.tres" % [PRESET_DIR, _preset_name.text]
	if not ResourceLoader.exists(path):
		_status.text = "no preset at %s" % path
		return
	# CACHE_MODE_IGNORE forces a fresh read: without it, repeated loads of the
	# same path return the cached instance and the panel appears to do nothing.
	var loaded: MovementConfig = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if loaded == null:
		_status.text = "load failed"
		return
	for property in loaded.get_property_list():
		if property.usage & PROPERTY_USAGE_EDITOR and property.type == TYPE_FLOAT:
			config.set(property.name, loaded.get(property.name))
	for slider in _sliders():
		slider.value = config.get(slider.get_meta("property_name"))
	_status.text = "loaded %s" % path
```

- [ ] **Step 2: 挂进主场景**

修改 `tools/build_main_scene.gd`，在 HUD 之后加入：

```gdscript
	var panel := CanvasLayer.new()
	# The node name is load-bearing: Arena._ready() finds it with
	# get_node_or_null("TuningPanel") to inject the shared config.
	panel.name = "TuningPanel"
	panel.set_script(load("res://scripts/debug/tuning_panel.gd"))
	_root.add_child(panel)
	panel.owner = _root
```

`config` **不在生成器里赋值**——`Arena._ready()`（Task 8 已写入该逻辑）在运行时注入共享的那一个 `MovementConfig` 实例。这一点很关键：面板和玩家必须操作**同一个对象**，否则拖动滑块不会影响移动。

重新生成主场景：

```powershell
.\.engine\Godot_v4.7.1-stable_win64_console.exe --headless --path . --import | Out-Null
.\.engine\Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tools/build_main_scene.gd
```

- [ ] **Step 3: 写调参面板测试**

在 `tests/test_arena.gd` 末尾追加。重点验证**滑块确实写回共享 config**，以及预设存取的往返：

```gdscript
func test_tuning_panel_writes_back_into_the_shared_config() -> void:
	await step(1)
	var arena = await _load_arena()
	var panel = arena.get_node_or_null("TuningPanel")
	check(panel != null, "TuningPanel node missing from the arena")
	check(panel.config == arena.config, "panel was not given the shared config instance")

	# _build_ui is deferred, so give it a frame to construct the sliders.
	await step(2)
	var sliders: Array = panel._sliders()
	check_greater(float(sliders.size()), 10.0, "expected a slider per float parameter")

	var target: HSlider = null
	for s in sliders:
		if s.get_meta("property_name") == "walk_speed":
			target = s
			break
	check(target != null, "no slider was generated for walk_speed")

	var before: float = arena.config.walk_speed
	target.value = before + 1.0
	await step(1)
	check_approx(arena.config.walk_speed, before + 1.0, 0.001, \
		"moving the slider did not write back into the shared config")
	# The player must see it too, since it holds the same object.
	check_approx(arena.player.config.walk_speed, before + 1.0, 0.001, \
		"the player does not observe the tuned value")

	arena.queue_free()
	await step(1)

func test_preset_save_and_load_round_trips() -> void:
	await step(1)
	var arena = await _load_arena()
	var panel = arena.get_node_or_null("TuningPanel")
	await step(2)

	panel._preset_name.text = "test_roundtrip"
	arena.config.walk_speed = 3.25
	panel._on_save()

	arena.config.walk_speed = 99.0
	panel._on_load()
	check_approx(arena.config.walk_speed, 3.25, 0.001, \
		"preset load did not restore the saved value")

	DirAccess.remove_absolute("user://presets/test_roundtrip.tres")
	arena.queue_free()
	await step(1)
```

- [ ] **Step 4: 截图验收**

面板默认隐藏，截图前需要打开它。创建 `tools/capture_panel.gd`：

```gdscript
extends SceneTree

# Same idea as capture.gd, but reveals the tuning panel first so the captured
# frame actually shows it.

func _initialize() -> void:
	_run()

func _run() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var arena = packed.instantiate()
	root.add_child(arena)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	for i in 30:
		await process_frame
	arena.get_node("TuningPanel").visible = true

	for i in 60:
		await process_frame
	await RenderingServer.frame_post_draw

	var image := root.get_texture().get_image()
	if image == null:
		push_error("viewport image was null")
		quit(1)
		return
	var error := image.save_png("res://.captures/p0_tuning_panel.png")
	print("capture err ", error)
	quit(0 if error == OK else 1)
```

```powershell
.\.engine\Godot_v4.7.1-stable_win64_console.exe --path . --resolution 1280x720 --script res://tools/capture_panel.gd
```

**控制者会查看该图**，确认面板可见、滑块与标签排布正常、分组标题存在、数值文本可读。

- [ ] **Step 5: 无法自动验证的项（如实上报）**

1. 按 `F1` 开关面板、鼠标释放与重新捕获
2. 拖动滑块时手感的实际变化是否符合预期

- [ ] **Step 6: 运行测试确认没有回归**

Run: `pwsh tools/run_tests.ps1`
Expected: PASS，`failures: 0`。

- [ ] **Step 7: 提交**

```bash
git add scripts/debug/tuning_panel.gd scenes/main.tscn tools/build_main_scene.gd tools/capture_panel.gd tests/test_arena.gd
git commit -m "feat: add F1 runtime tuning panel with preset save and load"
```

---

## P0 完成标准

全部任务完成后应当满足：

**自动可验证（本计划内必须全部达成）：**

- [ ] `pwsh tools/run_tests.ps1` 通过，退出码 0
- [ ] `scenes/player/player.tscn` 与 `scenes/main.tscn` 均由生成器产出，结构测试通过
- [ ] 玩家在靶场中落地并稳定处于 `Ground`；移动方向跟随视角
- [ ] `R` 重置能回到出生点并清零速度
- [ ] 调参面板的滑块写回共享 `MovementConfig`，玩家能观测到；预设存取往返正确
- [ ] HUD 报告当前状态且文本内容合理
- [ ] 靶场截图渲染正常（非黑屏、几何体与光照可见）
- [ ] 调参面板截图排布正常
- [ ] `project.godot` 中 `renderer/rendering_method` 仍为 `gl_compatibility`

**留待使用者确认（不得声称已验证）：**

- [ ] 鼠标转视角的跟手程度与灵敏度
- [ ] `Shift` 冲刺 / `Space` 跳跃 / `Tab` / `F1` / `Esc` / `F11` 的键盘交互
- [ ] 落地下沉、步频晃动、FOV 变化的观感强度
- [ ] **手感本身**——跑起来爽不爽

自动化测试只能保证逻辑没错。手感优劣是 P1 之前唯一需要人来回答的问题。
