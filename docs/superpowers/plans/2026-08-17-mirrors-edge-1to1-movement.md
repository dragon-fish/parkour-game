# 镜之边缘 1:1 移动系统重做 · 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把本项目自创的移动参数体系与动作框架，重做成与《镜之边缘》原版同构的形态，使此后的手感调校等于在调 DICE 调过的同一批数字。

**Architecture:** 参数按原版的 CDO 层级切成 `PawnConfig`（Pawn 级共享）+ 每个动作一份 `MoveConfig` 子类 + `CameraConfig`（感知层），由 `MovementConfig` 聚合根持有并注入。`PlayerState`/`StateMachine` 升级为 `Move`/`MoveManager`，每个 Move 声明自己的速度倍率、摩擦倍率、冷却、镜头约束与环境探测策略。新增 `SpeedEnergy`（速度能量曲线）与 `FallTracker`（累计下落高度）两个纯逻辑组件，取代常数速度上限与读 `velocity.y` 的落地判定。

**Tech Stack:** Godot 4.7.1（`.engine` junction 指向 `D:\GodotEngine\`）、GDScript、Jolt Physics、GL Compatibility 渲染。无第三方依赖。测试为自研 headless runner（`tools/run_tests.ps1`）。

**Spec:** [`docs/superpowers/specs/2026-08-17-mirrors-edge-1to1-movement-design.md`](../specs/2026-08-17-mirrors-edge-1to1-movement-design.md)

## Global Constraints

以下适用于**每一个** task，不再逐条重复。

- **命名**：概念与字段名照搬原版，去掉 `Td` 前缀，转 snake_case。`TdMove_WallRun` → `WallRunMove` + `WallRunConfig`；`TdPawn` → `PawnConfig`；`WallRunningPushAwaySpeedNoob` → `wall_running_push_away_speed_noob`。两处例外：原版拼错的 `MinLegdeZNormal` 修正为 `min_ledge_z_normal`；`MaxDistanceTime` 保留原名但 doc 注明它是秒。
- **单位**：一律公制（1 uu = 1 cm）。字段名沿用原版，值是米 / 秒制。
- **doc comment 必填三件事**：原始 uu 值、来源章节、可信度标记（✅ 确证 / ⚠️ 推断 / ❓ 未知 / 📣 社区）。没有这三样的新字段视为未完成。
- **注释语言**：英文（沿用本仓库既有约定）。
- **`*ZHeight` 系列存为高度**，在使用点按 `v = sqrt(2 * gravity * h)` 换算成速度。
- **不引入任何第三方依赖。**
- **以下路径一律不要碰**，所有者正在其中做逆向工作，文件变动频繁，任何 agent 的改动都可能与之冲突：
  - `_local/`（从本地正版提取的关卡测量数据，已 gitignore）
  - `scenes/debug_levels/`（所有者的白盒试验场，已 gitignore）
  - `docs/mirrors-edge-deep-research/tools/` 下**未入库**的脚本（`mapdump.py`、`build_blockout.py`、`find_spawn.py`、`survey_actors.py`、`diag_*.py` 等关卡分析脚本）。已入库的 7 个 UE3 解包脚本是调研手册的一部分，同样只读不改。
  不要读取、不要修改、不要提交、不要在 `git add -A` 时把它们捎上——每个 task 的提交步骤都写了明确的路径，照着写，不要图省事用 `git add -A .`。
- **运行测试**：`pwsh -File tools/run_tests.ps1`。该脚本会先跑一次 `--import` 刷新 `global_script_class_cache.cfg`，再跑 runner，并**扫描引擎错误输出**——任何 `SCRIPT ERROR:` / `ERROR:` 行都会让整轮失败，即使断言全过。
- **测试写法约束**（`tests/test_case.gd` 的真实接口）：只有 `check(cond, msg)`、`check_greater(a, b, msg)`、`check_approx(a, b, tol, msg)` 三个断言，**没有 `check_less`**（要用 `check(a < b, msg)`）。每个 `test_` 方法**必须至少调用一次断言**，否则 runner 记为失败。需要物理推进时 `await step(n)`。
- **提交**：Conventional Commits，纯英文，每个 task 至少一笔。commit message 末尾加
  `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`
- **不 push**，除非所有者明确指示。

---

## File Structure

### 新建

| 文件 | 职责 |
|---|---|
| `scripts/player/config/pawn_config.gd` | ≙ `TdPawn` CDO：全局移动属性、速度能量参数、摩擦倍率组、落地阈值 |
| `scripts/player/config/camera_config.gd` | 感知层参数（含所有者已拍板的 FOV / bob 分歧） |
| `scripts/player/config/move_config.gd` | ≙ `TdMove` + `TdPhysicsMove` 基类：每个动作都有的声明字段 |
| `scripts/player/config/moves/walking_config.gd` 等 10 份 | 各动作自己的参数 |
| `scripts/player/speed_energy.gd` | 速度能量：曲线查值、累积、衰减、转向扣减。纯逻辑 |
| `scripts/player/fall_tracker.gd` | 累计下落高度计数器。纯逻辑 |
| `scripts/player/moves/move.gd` | ≙ `TdMove`，取代 `PlayerState` |
| `scripts/player/moves/move_manager.gd` | ≙ `TdPlayerMoveManager`，取代 `StateMachine` |
| `scripts/player/moves/*_move.gd` | 7 个动作，由现有 `states/*_state.gd` 改名迁移而来 |
| `tests/legacy/.gdignore` | 让 Godot 完全跳过归档测试目录 |

### 修改

| 文件 | 改什么 |
|---|---|
| `scripts/player/movement_config.gd` | 从 498 行的扁平大杂烩，变成只持有子资源引用的聚合根 |
| `scripts/player/player.gd` | 配置访问路径、持有 `SpeedEnergy`/`FallTracker`、删掉三套散装冷却与空中减速守卫 |
| `scripts/camera/camera_rig.gd` | 配置访问路径、按 Move 的镜头约束钳制、贴墙滚转方向修正 |
| `scripts/player/probes.gd` | 配置访问路径、新增命中距离与 vault-over 探测 |
| `scripts/level/arena.gd` | 配置访问路径 |
| `scripts/player/character_animator.gd` | 配置访问路径 |
| `scripts/debug/tuning_panel.gd` | 改为递归遍历资源树生成滑块 |
| `tools/arena_builder.gd` | 配置访问路径；跳跃弧与 vault 高度变了要重新生成场景 |
| `tools/build_player_scene.gd` | 配置访问路径（`eye_height`） |
| `tests/world_fixture.gd` | 配置访问路径 |

### 归档（不删）

`tests/test_*.gd` 共 22 个 → `tests/legacy/`。`tests/test_case.gd`、`tests/test_runner.gd`、`tests/world_fixture.gd` 留在原地继续用。

---

## Task 1: 归档现有测试，腾出重做空间

现有测试大量锚定在即将删除的机制上（`slide_boost`、`wall_max_duration`、`_height_ceiling`、`land_speed_keep`）。更要命的是：GDScript 对**类型化**的属性访问做静态检查，一旦删掉 `MovementConfig` 的字段，这些文件会产生解析错误，而 `run_tests.ps1` 会因为扫到 `SCRIPT ERROR:` 行直接判整轮失败。所以必须先让 Godot **完全不扫描**这个目录。

**Files:**
- Create: `tests/legacy/.gdignore`（空文件）
- Move: `tests/test_air_state.gd`、`test_arena.gd`、`test_base_level_template.gd`、`test_body_attachment.gd`、`test_camera_rig.gd`、`test_character_animator.gd`、`test_crouch_state.gd`、`test_ground_state.gd`、`test_grounded_oracle.gd`、`test_input.gd`、`test_landing.gd`、`test_ledge.gd`、`test_movement_config.gd`、`test_player_scene.gd`、`test_probes.gd`、`test_slide_state.gd`、`test_smoke.gd`、`test_state_machine.gd`、`test_vault.gd`、`test_wall_run.gd` → `tests/legacy/`（连同各自的 `.uid`）
- 保持原地：`tests/test_case.gd`、`tests/test_runner.gd`、`tests/world_fixture.gd`

**Interfaces:**
- Consumes: 无
- Produces: 一个空的、可用的测试目录。后续所有 task 的新测试写在 `tests/test_*.gd`。

- [ ] **Step 1: 确认 `.gdignore` 确实能让 Godot 跳过目录**

这是本 task 的核心假设，先验证再动手，不要假定。建一个临时目录放一个**故意写错**的脚本：

```bash
mkdir -p tests/_gdignore_probe
printf '' > tests/_gdignore_probe/.gdignore
printf 'extends Node\nfunc f() -> void:\n\tthis is not valid gdscript\n' > tests/_gdignore_probe/broken.gd
```

- [ ] **Step 2: 跑一次导入，确认坏脚本没有被扫到**

Run: `pwsh -File tools/run_tests.ps1`

Expected: 退出码 0，输出里**没有** `broken.gd` 相关的 `SCRIPT ERROR:` / `ERROR:` 行。

若失败（说明 `.gdignore` 没生效），改用备选方案：把归档文件的扩展名改成 `.gd.txt`（Godot 不会把 `.txt` 当脚本解析），本 task 后续步骤照此调整，并在计划里记下这次偏离。

- [ ] **Step 3: 删掉探针，正式建立归档目录**

```bash
rm -rf tests/_gdignore_probe
mkdir -p tests/legacy
printf '' > tests/legacy/.gdignore
git mv tests/test_air_state.gd tests/test_air_state.gd.uid tests/legacy/
git mv tests/test_arena.gd tests/test_arena.gd.uid tests/legacy/
git mv tests/test_base_level_template.gd tests/test_base_level_template.gd.uid tests/legacy/
git mv tests/test_body_attachment.gd tests/test_body_attachment.gd.uid tests/legacy/
git mv tests/test_camera_rig.gd tests/test_camera_rig.gd.uid tests/legacy/
git mv tests/test_character_animator.gd tests/test_character_animator.gd.uid tests/legacy/
git mv tests/test_crouch_state.gd tests/test_crouch_state.gd.uid tests/legacy/
git mv tests/test_ground_state.gd tests/test_ground_state.gd.uid tests/legacy/
git mv tests/test_grounded_oracle.gd tests/test_grounded_oracle.gd.uid tests/legacy/
git mv tests/test_input.gd tests/test_input.gd.uid tests/legacy/
git mv tests/test_landing.gd tests/test_landing.gd.uid tests/legacy/
git mv tests/test_ledge.gd tests/test_ledge.gd.uid tests/legacy/
git mv tests/test_movement_config.gd tests/test_movement_config.gd.uid tests/legacy/
git mv tests/test_player_scene.gd tests/test_player_scene.gd.uid tests/legacy/
git mv tests/test_probes.gd tests/test_probes.gd.uid tests/legacy/
git mv tests/test_slide_state.gd tests/test_slide_state.gd.uid tests/legacy/
git mv tests/test_smoke.gd tests/test_smoke.gd.uid tests/legacy/
git mv tests/test_state_machine.gd tests/test_state_machine.gd.uid tests/legacy/
git mv tests/test_vault.gd tests/test_vault.gd.uid tests/legacy/
git mv tests/test_wall_run.gd tests/test_wall_run.gd.uid tests/legacy/
```

- [ ] **Step 4: 写一个替身冒烟测试，证明测试基础设施仍然活着**

一个空的测试套件跑出 `checks: 0` 是无法区分「归档成功」和「runner 坏了」的。放一个最小用例把这件事钉死。

Create `tests/test_harness_alive.gd`:

```gdscript
class_name TestHarnessAlive
extends TestCase

# The legacy suite is archived under tests/legacy/ (excluded from Godot's
# filesystem scan by its own .gdignore). Without at least one live test, a
# green run would be indistinguishable from a broken runner, since
# tests/test_runner.gd reports "checks: 0  failures: 0" and exits 0 either
# way. This file is deliberately trivial and is expected to outlive the
# rebuild as the suite's floor.

func test_the_runner_discovers_and_runs_a_live_test() -> void:
	check(true, "the runner reached a live test method")

func test_the_physics_step_helper_still_advances_frames() -> void:
	var node := Node3D.new()
	tree.root.add_child(node)
	await step(1)
	check(node.is_inside_tree(), "step() did not let a node enter the tree")
	node.queue_free()
	await step(1)
```

- [ ] **Step 5: 跑测试确认归档生效且新测试通过**

Run: `pwsh -File tools/run_tests.ps1`

Expected: 退出码 0。输出里出现 `test_harness_alive.gd   2 test(s)`，总计 `checks: 3   failures: 0`，且**没有任何** legacy 测试文件出现在输出中，也没有 `SCRIPT ERROR:` 行。

- [ ] **Step 6: 记下 run_tests.ps1 的两条 allowlist 现在处于休眠状态**

`tools/run_tests.ps1` 的 `$allowlist` 里两条（`Assertion failed: transition to unknown state: Nonexistent`、`state Silent did not declare grounded-ness`）分别服务于已归档的 `test_state_machine.gd` 与 `test_grounded_oracle.gd`。**不要删**——Task 4 的 `MoveManager` 会原样保留这两条不变量和同样的消息文本，重写测试时会重新用上。在 `$allowlist` 上方加一行注释说明它们暂时无人触发。

```powershell
# NOTE: both entries below are DORMANT as of the 1:1 movement rebuild -- the
# two tests that trigger them are archived under tests/legacy/. They are kept
# because MoveManager preserves both invariants verbatim (same message text),
# so the rewritten tests will need them again. Do not prune.
```

- [ ] **Step 7: 提交**

```bash
git add -A tests tools/run_tests.ps1
git commit -F - <<'EOF'
test: archive the pre-rebuild suite behind a .gdignore

Most of it pins mechanics the 1:1 rebuild deletes outright (slide_boost,
wall_max_duration, the wall-jump height governor, the landing keep-ratio
ramp), so it cannot survive the change on its own terms. Archiving rather
than deleting keeps it as a reference for the rewrite.

The .gdignore is load-bearing, not tidiness: GDScript statically checks
typed property access, so a deleted MovementConfig field would turn every
archived file into a parse error, and run_tests.ps1 fails the run on any
engine error line regardless of the assertion count.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
```

---

## Task 2: 参数按原版 CDO 层级切开（**不改任何数值**）

这是全计划改动面最大的一笔，但它是**纯搬迁**：每个值原样搬到新位置、换成原版的名字、补上出处与可信度。行为必须完全不变。

即将被删除的字段（`slide_boost`、`wall_max_duration` 等）**在本 task 里照搬不误**，它们各自在后续 task 里随取代者一起删。这样本 task 的验收标准干净：游戏行为逐帧一致。

**Files:**
- Create: `scripts/player/config/pawn_config.gd`、`camera_config.gd`、`move_config.gd`
- Create: `scripts/player/config/moves/` 下 10 份：`walking_config.gd`、`jump_config.gd`、`falling_config.gd`、`landing_config.gd`、`slide_config.gd`、`crouch_config.gd`、`speed_vault_config.gd`、`grab_config.gd`、`wall_run_config.gd`、`wallrun_jump_config.gd`
- Rewrite: `scripts/player/movement_config.gd`
- Modify: `scripts/player/player.gd`、`scripts/camera/camera_rig.gd`、`scripts/player/probes.gd`、`scripts/level/arena.gd`、`scripts/player/character_animator.gd`、`scripts/player/states/{ground,air,slide,crouch,vault,ledge_hang,wall_run}_state.gd`、`tools/arena_builder.gd`、`tools/build_player_scene.gd`、`tests/world_fixture.gd`
- Test: `tests/test_config_layout.gd`

**Interfaces:**
- Consumes: 无
- Produces:
  - `MovementConfig.pawn: PawnConfig`、`.camera: CameraConfig`
  - `MovementConfig.walking/jump/falling/landing/slide/crouch/speed_vault/grab/wall_run/wallrun_jump`（各为对应的 `*Config`）
  - `MoveConfig` 基类字段：`speed_modifier: float`、`friction_modifier: float`、`redo_move_time: float`、`min_look_constraint: Vector3`、`max_look_constraint: Vector3`、`constrain_look: bool`、`absolute_yaw_constraint: bool`、`check_for_grab: bool`、`check_for_vault_over: bool`、`check_for_wall_climb: bool`

- [ ] **Step 1: 写失败的测试**

Create `tests/test_config_layout.gd`:

```gdscript
class_name TestConfigLayout
extends TestCase

# Pins the layout AND the values a fresh MovementConfig hands out, so the
# migration from the old flat resource can be shown to have changed nothing
# but where the numbers live. One representative field per sub-resource --
# this is a structure test, not a re-transcription of the whole table.

func test_a_fresh_config_builds_every_sub_resource() -> void:
	var config := MovementConfig.new()
	check(config.pawn != null, "pawn config missing")
	check(config.camera != null, "camera config missing")
	check(config.walking != null, "walking config missing")
	check(config.jump != null, "jump config missing")
	check(config.falling != null, "falling config missing")
	check(config.landing != null, "landing config missing")
	check(config.slide != null, "slide config missing")
	check(config.crouch != null, "crouch config missing")
	check(config.speed_vault != null, "speed_vault config missing")
	check(config.grab != null, "grab config missing")
	check(config.wall_run != null, "wall_run config missing")
	check(config.wallrun_jump != null, "wallrun_jump config missing")

func test_two_configs_do_not_share_their_sub_resources() -> void:
	# Player.setup() already duplicates the collision capsule for exactly this
	# reason. An @export default built with .new() is evaluated per instance,
	# but that is worth pinning rather than assuming: a shared sub-resource
	# would let one player's F1 slider retune every other player in the scene,
	# and in the test suite, retune the next test file's world.
	var a := MovementConfig.new()
	var b := MovementConfig.new()
	check(a.pawn != b.pawn, "two configs share one PawnConfig instance")
	check(a.slide != b.slide, "two configs share one SlideConfig instance")

func test_migrated_values_are_unchanged() -> void:
	var config := MovementConfig.new()
	check_approx(config.pawn.gravity, 8.0, 0.0001, "gravity moved but changed")
	check_approx(config.pawn.ground_speed, 7.2, 0.0001, "ground_speed moved but changed")
	check_approx(config.pawn.accel_rate, 60.0, 0.0001, "ground_accel moved but changed")
	check_approx(config.camera.fov_base, 90.0, 0.0001, "fov_base moved but changed")
	check_approx(config.camera.eye_height, 0.7, 0.0001, "eye_height moved but changed")
	check_approx(config.slide.slide_capsule_height, 0.9, 0.0001, "slide capsule moved but changed")
	check_approx(config.crouch.speed_modifier, 0.4, 0.0001, "crouch pct moved but changed")

func test_move_config_defaults_are_neutral() -> void:
	# A Move that declares nothing must behave exactly as it did before this
	# layer existed: full speed, full friction, no cooldown, no look clamp.
	var cfg := MoveConfig.new()
	check_approx(cfg.speed_modifier, 1.0, 0.0001, "default speed_modifier is not neutral")
	check_approx(cfg.friction_modifier, 1.0, 0.0001, "default friction_modifier is not neutral")
	check_approx(cfg.redo_move_time, 0.0, 0.0001, "default redo_move_time is not zero")
	check(not cfg.constrain_look, "look is constrained by default")
```

- [ ] **Step 2: 跑测试确认失败**

Run: `pwsh -File tools/run_tests.ps1`

Expected: FAIL —— 会出现 `SCRIPT ERROR:` 提示 `MoveConfig` 未声明、以及 `MovementConfig` 上没有 `pawn` 属性。

- [ ] **Step 3: 建 `MoveConfig` 基类**

Create `scripts/player/config/move_config.gd`:

```gdscript
class_name MoveConfig
extends Resource

# Base class for every move's own parameters -- the Godot counterpart of the
# original's TdMove + TdPhysicsMove default properties (see
# docs/mirrors-edge-deep-research/06-Move状态机架构.md §6.2).
#
# Every default here is DELIBERATELY NEUTRAL: a move that declares nothing
# must behave exactly as it did before this layer existed. Declaring a value
# is how a move opts into being different.

## Multiplier on the ground speed cap while this move is active.
## Source: 06 §6.2 `SpeedModifier`. ✅ confirmed field, per-move values in 05.
@export var speed_modifier: float = 1.0

## Multiplier on PawnConfig.base_friction while this move is active.
## Source: 06 §6.2 `FrictionModifier`. ✅ e.g. Slide 0.1, WallRun 0.05.
@export var friction_modifier: float = 1.0

## Seconds before this same move may be entered again.
## Source: 06 §6.2 `RedoMoveTime`. ✅ e.g. WallRun 0.15, WallKick 1.0.
@export var redo_move_time: float = 0.0

## Look-angle clamp while this move is active, as (pitch, yaw, roll) in
## RADIANS. The original stores these as UE3 integer angles where
## 65536 = 360 degrees (see 09 §9.2), e.g. WallRun's
## `MinLookConstraint = (-13000, -16384, -32768)` -> pitch -71.4 deg,
## yaw -90 deg, roll -180 deg. Converted at authoring time, not at runtime.
## Source: 06 §6.2, 04 §4.1. ✅
@export var min_look_constraint: Vector3 = Vector3(-PI, -PI, -PI)
@export var max_look_constraint: Vector3 = Vector3(PI, PI, PI)

## Whether the clamp above is applied at all. Source: 06 §6.2
## `bConstrainLook`. ✅
@export var constrain_look: bool = false

## Whether the yaw half of the clamp is measured against a fixed world yaw
## captured on entering the move, rather than against the current facing.
## Source: 04 §4.1 `bUseAbsoluteYawConstraint = True` on WallRun. ✅
@export var absolute_yaw_constraint: bool = false

## Which environment probes this move runs each tick. The original makes
## these per-move switches rather than hardcoding them in each state's
## update -- which is how "a rising jump can start a wall climb but a fall
## cannot" is expressed as data (05 §5.7 ③: TdMove_Jump has
## bCheckForWallClimb, TdMove_Falling does not).
## Source: 06 §6.2 `bCheckForGrab` / `bCheckForVaultOver` /
## `bCheckForWallClimb`. ✅
@export var check_for_grab: bool = false
@export var check_for_vault_over: bool = false
@export var check_for_wall_climb: bool = false
```

- [ ] **Step 4: 建 `PawnConfig`**

Create `scripts/player/config/pawn_config.gd`. 字段清单如下——**本 task 只搬迁，值全部沿用现状**，右列标注了后续 task 会把它改成什么（现在不要动）：

```gdscript
class_name PawnConfig
extends Resource

# The Godot counterpart of the original's TdPawn CDO. Everything here is
# Pawn-wide -- shared by every move -- as opposed to MoveConfig, which is
# per-move. Field names follow the original's own (minus the Td prefix,
# snake_case); values are metric at 1 uu = 1 cm.

@export_group("Locomotion")
## Source: 02 §2.3 `GroundSpeed = 720` uu/s. ✅
## From Task 6 this stops being the target speed directly and becomes the
## CEILING of the speed-energy curve (02 §2.1); it keeps the same value.
@export var ground_speed: float = 7.2
## Source: 02 §2.3 `AirSpeed = 2400` uu/s. ✅ Essentially uncapped (3.3x
## GroundSpeed) -- the defence against an air-control exploit is air_control
## being almost zero, not a low ceiling here.
@export var air_speed: float = 24.0
## Source: 02 §2.3 `AccelRate = 6144` uu/s^2 -> 61.44. ✅
## MIGRATION NOTE: carried over from the old `ground_accel = 60.0`, NOT yet
## re-pointed at the confirmed 61.44 -- this task changes no values. Task 6
## corrects it.
@export var accel_rate: float = 60.0
## Source: 02 §2.3 `AirControl = 0.025`. ✅ Engine default is 0.05; DICE
## halved it. Used as a multiplier on accel_rate (09 §9.1).
## MIGRATION NOTE: the old flat `air_accel = 1.5` is carried in air_accel
## below until Task 6 derives it from this instead.
@export var air_control: float = 0.025
@export var air_accel: float = 1.5
## Source: 09 §9.1 `DefaultGravityZ = 800` uu/s^2. ✅
@export var gravity: float = 8.0
@export var terminal_velocity: float = 60.0
## Source: 02 §2.2 `WalkVelocity = 50` uu/s. ✅ The hard cap while the walk
## modifier (Ctrl) is held.
@export var walk_velocity: float = 0.5
## Source: 02 §2.3 `CrouchedPct = 0.4`. ✅ Also lives as CrouchConfig's own
## speed_modifier; kept here too because the original declares it Pawn-wide.
@export var crouched_pct: float = 0.4
## Source: 02 §2.3 `MaxStepHeight = 35` uu. ✅ Recorded; Godot's
## move_and_slide() has its own step handling, so nothing reads this yet.
@export var max_step_height: float = 0.35
## Source: 02 §2.3 `WalkableFloorZ = 0.71` -> acos = 44.7 degrees. ✅
## Carried over from the old `min_walkable_normal_y = 0.7`; Task 14 moves it
## to the confirmed 0.71.
@export var walkable_floor_z: float = 0.7

@export_group("Jump")
## Source: 02 §2.4 `TdPawn.BaseJumpZ = 560` uu/s. ✅ CONFIRMED BY IN-GAME
## MEASUREMENT -- the conflicting `TdMove_Jump.BaseJumpZ = 630` is ruled out
## there.
## MIGRATION NOTE: still carrying the old 6.3 (which came from the ruled-out
## 630). Task 6 corrects it to 5.6, together with the landing thresholds --
## 09 §9.1 is explicit that these must be calibrated as a group.
@export var base_jump_z: float = 6.3
## Source: 02 §2.4 `JumpAddXY = 100` uu/s. ⚠️ Inferred as extra horizontal
## speed along the facing at the moment of take-off; whether it adds or sets
## a minimum is unverified. Wired up in Task 6.
@export var jump_add_xy: float = 1.0
## No confirmed counterpart in the original (02 §2.4 searched and found
## none). Kept as a modern quality-of-life affordance.
@export var coyote_time: float = 0.12
@export var jump_buffer_time: float = 0.12

@export_group("Friction")
## No confirmed value in the original -- the research did not extract
## TdPawn.Friction. Carried over from this project's own ground_friction, and
## every scale below is relative to it, so this is the one number in this
## group that has to be settled by playtest.
@export var base_friction: float = 40.0
## Source: 03 §3.3. ✅ Terrain grade modulates friction directly: downhill is
## a free acceleration lane, uphill is a tax.
@export var upward_walk_friction_scale: float = 1.1
@export var downward_walk_friction_scale: float = 0.8
@export var min_walk_friction_modify: float = 0.4
@export var max_walk_friction_modify: float = 2.0
## Source: 03 §3.3. ✅ A slide's grade sensitivity is far more extreme than
## walking's -- uphill sliding stops almost immediately.
@export var upward_slide_friction_scale: float = 5.0
@export var downward_slide_friction_scale: float = 1.8
## Source: 03 §3.3. ✅ TdPawn declares 1.0; TdPlayerPawn overrides to 0.5 --
## the player is deliberately harder to bring to a stop than the AI.
@export var braking_friction_strength: float = 0.5
## Godot-specific: the downward bias GroundState writes every tick so
## is_on_floor() does not flicker across seams. The original's PHYS_Walking
## has no equivalent because it does not need one.
@export var floor_snap_speed: float = 2.0

@export_group("Speed energy")
## Source: 02 §2.1 `SpeedCurve_LightWeapon`, an InterpCurveFloat with
## interpolation mode CIM_Linear. ✅ X is speed energy in seconds, Y is the
## ground speed ceiling. Held as the five confirmed knots rather than a
## fitted formula: the original evaluates a table, so a table has zero
## approximation error where a formula does not.
@export var speed_curve: PackedVector2Array = PackedVector2Array([
	Vector2(0.0, 0.0), Vector2(0.4, 4.0), Vector2(1.0, 5.2),
	Vector2(3.5, 6.5), Vector2(7.0, 7.2),
])
## Source: 02 §2.1 `SpeedMinBaseVelocity = 10` uu/s. ✅ Floor under the curve
## so a standing start is not literally frozen at the curve's own v(0) = 0.
@export var speed_min_base_velocity: float = 0.1
## Source: 02 §2.1 `SpeedMaxBaseVelocity = 400` uu/s. ✅ as a value,
## ❓ as a role -- the research could not determine what it does in the
## formula. Recorded so the number is not lost; nothing reads it.
@export var speed_max_base_velocity: float = 4.0
## Source: 02 §2.1. ✅ as values, ⚠️ as direction (unverified by bytecode).
## Read as: energy accrues at (active factor / sprint factor) per second, so
## ordinary running is 30/30 = 1.0 and the curve's 7.0 s X-axis endpoint is
## reached in exactly 7 s -- which is what the community's own "7-10 seconds
## from a standstill to full sprint" measurement independently reports.
@export var speed_walk_velocity_acceleration_factor: float = 7.0
@export var speed_strafe_velocity_acceleration_factor: float = 10.0
@export var speed_sprint_velocity_acceleration_factor: float = 30.0
## Source: 02 §2.1 `SpeedEnergyDecelerationTime = 3`. ✅
@export var speed_energy_deceleration_time: float = 3.0
## Source: 02 §2.1 `SpeedEnergyDecelerationExponent = 0.5`. ✅ as a value,
## ⚠️ as a formula -- taken literally as the exponent in
## dE/dt = -k * E^0.5, with k solved from the time above.
@export var speed_energy_deceleration_exponent: float = 0.5
## Source: 03 §3.2 `SpeedTurnDecelerationFactor = 10`. ❓ THE UNIT IS NOT
## RECOVERABLE from the binary. The original value is recorded here in the
## comment and deliberately NOT used: this project calibrates the knob to a
## stated behaviour instead -- a full 180 degree reversal (pi radians) spends
## the entire 7.0 energy budget, hence 7.0 / pi = 2.23 energy per radian.
@export var speed_turn_deceleration_factor: float = 2.23
## PROJECT-ADDED GUARD, no counterpart in the original. Energy only accrues
## while actually travelling at this fraction of the current cap. Without it,
## holding the walk modifier for 7 seconds -- or shoving into a wall for 7
## seconds -- banks a full energy budget and hands over a 7.2 ceiling the
## instant the obstruction clears, which contradicts the whole premise that
## speed is an asset that has to be run for.
@export var energy_accumulate_speed_ratio: float = 0.9

@export_group("Landing")
## Source: 03 §3.1 `TdMove_Landing` CDO, as fall HEIGHTS (not impact
## speeds). ✅ 200 / 300 / 530 uu.
@export var skill_roll_landing_height: float = 2.0
@export var soft_landing_height: float = 3.0
@export var hard_landing_height: float = 5.3
## Source: 03 §3.1 `LandingSpeedReduction = 65`. ❓ UNIT UNVERIFIED -- the
## research calls this its single most important open question. Read as
## "lose 65%", i.e. keep 0.35, on the strength of the community consensus
## that a hard landing takes speed almost to zero.
@export var landing_speed_reduction: float = 0.65
## Source: 03 §3.1 `TdMove_Falling.EnterToFallingZSpeed = -200` uu/s. ✅
## The downward speed at which the fall-height counter starts accruing, so
## the first few centimetres of a step-off are not counted.
@export var enter_to_falling_z_speed: float = -2.0
## Source: 03 §3.1 `TdPawn.RollTriggerTime = 1.0`. ⚠️ Read as the roll input
## pre-buffer window. Extremely forgiving next to the 0.1-0.2 s typical of
## the genre, which matches the community's own "skill roll timing is very
## lenient" consensus.
@export var roll_trigger_time: float = 1.0
## Source: 03 §3.1 `TdMove_Falling.MaximumSpeedForRollLanding = -5000`. ✅
@export var maximum_speed_for_roll_landing: float = -50.0

@export_group("Legacy -- deleted by later tasks")
## MIGRATION ONLY. Every field below is a project invention with no
## counterpart in the original, carried unchanged so this task can be shown
## to change no behaviour. Each is deleted by the task that lands its
## replacement -- see the spec's own deletion table (§6).
## Deleted by Task 9 (fall-height landing tiers).
@export var land_cost_speed_ref: float = 9.21
@export var land_speed_keep: float = 0.55
@export var roll_speed_keep: float = 0.94
@export var roll_min_fall_speed: float = 5.0
## Deleted by Task 9 (single roll_trigger_time buffer).
@export var crouch_buffer_time: float = 0.15
## Deleted by Task 11/12 (redo_move_time).
@export var wall_reattach_cooldown: float = 0.5
@export var wall_same_normal_dot: float = 0.85
## Deleted by Task 13 (redo_move_time).
@export var ledge_regrab_cooldown: float = 0.45

@export_group("World")
## How far below y = 0 the player must fall before Arena teleports them back.
## Project-specific; the original has no equivalent.
@export var fall_recovery_depth: float = 20.0
## Horizontal speed above which CharacterAnimator plays a moving clip. A
## readability threshold, not a physics one.
@export var run_animation_speed_threshold: float = 1.0
```

- [ ] **Step 5: 建 `CameraConfig`**

Create `scripts/player/config/camera_config.gd`——把 `movement_config.gd` 现有 `Camera` 分组的 16 个字段原样搬来（`eye_height`、`mouse_sensitivity`、`pitch_limit_deg`、`fov_base`、`fov_max`、`fov_speed_ref`、`fov_lerp_speed`、`bob_frequency`、`bob_amplitude`、`bob_fade_speed`、`land_dip_max`、`land_dip_recover`、`land_dip_speed_ref`、`slide_camera_drop`、`crouch_lerp_speed`、`camera_head_follow_strength`），值不变，**连同它们现有的长 doc comment 一起搬**——`fov_base`/`fov_max` 和 `bob_frequency`/`bob_amplitude` 上那两段「DIVERGENCE FROM SOURCE, KEPT DELIBERATELY」是所有者的决定记录，丢了就会被将来的人「修正」回原版。另加两个 `wall_camera_roll_deg`、`wall_camera_roll_speed`。

再加三个本 task 新记录、暂不接线的确证字段：

```gdscript
## Recorded from the original, not yet wired to anything. Source: 05 §5.10.
## ✅ These are the real shape of "how much does the view move" in the
## original: amplitude is a function of MOMENTUM, hard-clamped, rather than a
## constant. There is no procedural head-bob amplitude or frequency anywhere
## in the game's 2031 CDOs -- DICE removed head bob during development. Kept
## here because when the owner comes back to tune bob (which this project
## keeps on purpose, see bob_frequency's own note), these are better knobs
## than a constant amplitude.
@export var camera_anim_momentum_influence: float = 0.0001
@export var camera_forward_max: float = 0.5
@export var camera_downward_max: float = 0.4
```

- [ ] **Step 6: 建 10 份 move config**

每份 `extends MoveConfig`，只声明该动作自己的字段，**值全部沿用现状**。本 task 的分配如下：

| 文件 | class_name | 本 task 装进去的字段（值不变） |
|---|---|---|
| `walking_config.gd` | `WalkingConfig` | 无自有字段（继承默认即可） |
| `jump_config.gd` | `JumpConfig` | 无自有字段 |
| `falling_config.gd` | `FallingConfig` | 无自有字段 |
| `landing_config.gd` | `LandingConfig` | 无自有字段 |
| `slide_config.gd` | `SlideConfig` | `slide_entry_speed 4.0`、`slide_boost 2.5`、`slide_boost_entry_threshold 9.0`、`slide_friction 5.0`、`slide_exit_speed 2.0`、`slide_max_duration 1.8`、`slide_capsule_height 0.9`、`slide_steer_rate 1.2`、`slide_crawl_speed 2.5`、`slide_slope_accel 22.0`、`slide_max_speed 20.0` |
| `crouch_config.gd` | `CrouchConfig` | `crouch_capsule_height 0.9`；并在 `_init()` 里设 `speed_modifier = 0.4`（原 `crouch_speed_pct`） |
| `speed_vault_config.gd` | `SpeedVaultConfig` | `vault_max_height 1.3`、`vault_reach 1.4`、`vault_min_speed 2.5`、`vault_duration 0.32`、`vault_speed_keep 0.85`、`vault_exit_forward 0.6`、`vault_arc_height 0.15` |
| `grab_config.gd` | `GrabConfig` | `ledge_min_height 1.4`、`ledge_max_height 2.8`、`ledge_reach 1.0`、`mantle_duration 0.42`、`mantle_exit_speed 2.0`、`mantle_forward_offset 0.4`、`mantle_arc_height 0.3` |
| `wall_run_config.gd` | `WallRunConfig` | `wall_min_speed 5.0`、`wall_reach 0.75`、`wall_gravity_scale 0.35`、`wall_accel 18.0`、`wall_max_speed 7.2`、`wall_exit_speed 2.5`、`wall_max_duration 1.5`、`wall_stick_force 0.5` |
| `wallrun_jump_config.gd` | `WallrunJumpConfig` | `wall_jump_up 6.5`、`wall_jump_push 6.0` |

`CrouchConfig` 用 `_init()` 覆写基类默认值的写法：

```gdscript
class_name CrouchConfig
extends MoveConfig

## Capsule height while standing-crouched. Shares a number with
## SlideConfig.slide_capsule_height without sharing a variable: a slide that
## decays into a crouch under a low roof must not visibly pop, but the two
## stay independently tunable.
@export var crouch_capsule_height: float = 0.9

func _init() -> void:
	# Source: 02 §2.3 / 03 §3.4 `CrouchedPct = 0.4`. ✅ Chosen over
	# 05 §5.8's `TdMove_Crouch.SpeedModifier = 0.2`: CrouchedPct is
	# independently confirmed and explained in two separate sections, while
	# 0.2 appears once in a bare parameter dump with no narrative.
	speed_modifier = 0.4
```

- [ ] **Step 7: 把 `movement_config.gd` 改写成聚合根**

Rewrite `scripts/player/movement_config.gd`:

```gdscript
class_name MovementConfig
extends Resource

# Aggregate root. Holds nothing of its own -- every number lives in the
# sub-resource that matches the original's own layering: PawnConfig for what
# TdPawn declares Pawn-wide, one MoveConfig subclass per move for what each
# TdMove_* declares, CameraConfig for the perception layer.
#
# Kept as the single injected object (Arena -> Player/CameraRig/Probes/
# TuningPanel) so every consumer still reads from one shared instance, and a
# preset is still one .tres.
#
# Each default is built with .new() rather than left null: a fresh
# MovementConfig must be immediately usable (Arena falls back to
# MovementConfig.new() when nothing is assigned in the scene), and per-
# instance construction is what keeps two players from sharing one
# PawnConfig -- the same hazard Player.setup() already guards against for the
# collision capsule.

@export var pawn: PawnConfig = PawnConfig.new()
@export var camera: CameraConfig = CameraConfig.new()

@export var walking: WalkingConfig = WalkingConfig.new()
@export var jump: JumpConfig = JumpConfig.new()
@export var falling: FallingConfig = FallingConfig.new()
@export var landing: LandingConfig = LandingConfig.new()
@export var slide: SlideConfig = SlideConfig.new()
@export var crouch: CrouchConfig = CrouchConfig.new()
@export var speed_vault: SpeedVaultConfig = SpeedVaultConfig.new()
@export var grab: GrabConfig = GrabConfig.new()
@export var wall_run: WallRunConfig = WallRunConfig.new()
@export var wallrun_jump: WallrunJumpConfig = WallrunJumpConfig.new()
```

- [ ] **Step 8: 逐点改写全部消费者**

下表是 `grep -rno "config\.[a-z_]*" --include=*.gd scripts` 的完整结果，按新路径给出。**逐条改完，不要漏**：

| 文件 | 旧访问 → 新访问 |
|---|---|
| `camera_rig.gd` | `config.eye_height` / `mouse_sensitivity` / `pitch_limit_deg` / `fov_*` / `bob_*` / `land_dip_*` / `slide_camera_drop` / `crouch_lerp_speed` / `camera_head_follow_strength` / `wall_camera_roll_deg` / `wall_camera_roll_speed` → `config.camera.<同名>`；`var _config: MovementConfig` 保持不变 |
| `arena.gd` | `config.fall_recovery_depth` → `config.pawn.fall_recovery_depth` |
| `character_animator.gd` | `config.run_animation_speed_threshold` → `config.pawn.run_animation_speed_threshold`（2 处） |
| `player.gd` | `config.air_accel` / `air_max_speed`→`air_speed` / `coyote_time` / `ground_accel`→`accel_rate` / `ground_friction`→`base_friction` / `ground_speed` / `jump_buffer_time` → `config.pawn.<新名>`；`config.crouch_buffer_time` / `ledge_regrab_cooldown` / `wall_reattach_cooldown` / `wall_same_normal_dot` → `config.pawn.<同名>` |
| `probes.gd` | `config.ledge_max_height` / `ledge_min_height` / `ledge_reach` → `config.grab.<同名>`；`config.vault_max_height` / `vault_reach` → `config.speed_vault.<同名>`；`config.wall_reach` → `config.wall_run.wall_reach`；`config.min_walkable_normal_y` → `config.pawn.walkable_floor_z` |
| `ground_state.gd` | `floor_snap_speed`→`config.pawn.floor_snap_speed`；`ground_speed`→`config.pawn.ground_speed`；`jump_velocity`→`config.pawn.base_jump_z`；`walk_speed`→`config.pawn.walk_velocity`；`slide_entry_speed`→`config.slide.slide_entry_speed`；`vault_min_speed`→`config.speed_vault.vault_min_speed` |
| `air_state.gd` | `gravity` / `terminal_velocity` → `config.pawn.<同名>`；`jump_velocity`→`config.pawn.base_jump_z`；`land_cost_speed_ref` / `land_speed_keep` / `roll_min_fall_speed` / `roll_speed_keep` → `config.pawn.<同名>`；`wall_min_speed`→`config.wall_run.wall_min_speed` |
| `slide_state.gd` | `floor_snap_speed`→`config.pawn.floor_snap_speed`（3 处）；`jump_velocity`→`config.pawn.base_jump_z`；其余 `slide_*` → `config.slide.<同名>` |
| `crouch_state.gd` | `crouch_capsule_height`→`config.crouch.crouch_capsule_height`；`crouch_speed_pct`→`config.crouch.speed_modifier`；`floor_snap_speed`→`config.pawn.floor_snap_speed`；`ground_speed`→`config.pawn.ground_speed` |
| `vault_state.gd` | `vault_arc_height` / `vault_duration` / `vault_exit_forward` / `vault_speed_keep` → `config.speed_vault.<同名>` |
| `ledge_hang_state.gd` | `mantle_*` → `config.grab.<同名>` |
| `wall_run_state.gd` | `gravity`（4 处）→`config.pawn.gravity`；`jump_velocity`（2 处）→`config.pawn.base_jump_z`；`wall_accel` / `wall_exit_speed` / `wall_gravity_scale` / `wall_max_duration` / `wall_max_speed` / `wall_stick_force` → `config.wall_run.<同名>`；`wall_jump_up`（4 处）/ `wall_jump_push` → `config.wallrun_jump.<同名>` |
| `tools/arena_builder.gd` | `MovementConfig.new()` 之后的所有字段访问按上表改；跳跃弧用 `config.pawn.base_jump_z` / `config.pawn.gravity` |
| `tools/build_player_scene.gd` | `MovementConfig.new().eye_height` → `MovementConfig.new().camera.eye_height` |
| `tests/world_fixture.gd` | 签名不变（仍收 `MovementConfig`），无字段访问，无需改 |

- [ ] **Step 9: 跑测试确认通过**

Run: `pwsh -File tools/run_tests.ps1`

Expected: PASS，退出码 0，`test_config_layout.gd  4 test(s)`，无 `SCRIPT ERROR:` 行。

- [ ] **Step 10: 人工确认游戏仍能跑，且行为没变**

Run: `.engine\Godot_v4.7.1-stable_win64_console.exe --path .`

Expected: 场景正常加载，能跑能跳能滑铲能贴墙。**行为应与本 task 之前逐帧一致**——这是本 task 唯一的验收标准。F1 面板此时可能只显示聚合根上的零个 float 属性（滑块空了），这是预期的，Task 3 修复。

- [ ] **Step 11: 提交**

```bash
git add -A scripts tools tests
git commit -F - <<'EOF'
refactor(config): split the flat config along the original's own CDO layers

498 lines of invented abstractions become PawnConfig (what TdPawn declares
Pawn-wide), one MoveConfig subclass per move (what each TdMove_* declares)
and CameraConfig (the perception layer), behind an aggregate root so every
consumer still shares one injected instance and a preset is still one .tres.

Fields are renamed to the original's own names, minus the Td prefix, and
every one now carries its source uu value, its chapter, and a confidence
marker -- which is what makes the table comparable to appendix A1 line by
line, and what makes a confirmed CDO value impossible to mistake for an
inference.

No value changes. Fields with no counterpart in the original are carried
verbatim under a "deleted by later tasks" group so this commit can be shown
to change no behaviour at all.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
```

---

## Task 3: F1 调参面板递归遍历资源树

Task 2 之后面板会空掉——它 `for property in config.get_property_list()` 只找 `TYPE_FLOAT`，而聚合根上一个 float 都没有。手感是调出来的，面板断了整个计划就失去了验证手段，所以紧接着修。

顺带把「走属性树」这件事从 UI 里拆成纯函数，这样它可以被 headless 测——现在它完全测不了。

**Files:**
- Modify: `scripts/debug/tuning_panel.gd`
- Test: `tests/test_tuning_panel_model.gd`

**Interfaces:**
- Consumes: `MovementConfig` 的资源树（Task 2 产出）
- Produces: `TuningPanel.collect_tunables(config: MovementConfig) -> Array[Dictionary]`，每项形如
  `{"path": String, "label": String, "group": String, "owner": Resource, "property": String, "default": float}`。
  `path` 是点分全路径（如 `"slide.slide_friction"`），`owner`/`property` 供 `set()`/`get()` 直接使用。

- [ ] **Step 1: 写失败的测试**

Create `tests/test_tuning_panel_model.gd`:

```gdscript
class_name TestTuningPanelModel
extends TestCase

# The panel's own property walk, tested without building any UI. Extracted
# from _build_ui() precisely so it can be: the old version was pure UI code
# and had no test at all.

func _paths(rows: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for row in rows:
		out.append(row["path"])
	return out

func test_it_reaches_floats_inside_every_sub_resource() -> void:
	var config := MovementConfig.new()
	var paths := _paths(TuningPanel.collect_tunables(config))
	check(paths.has("pawn.gravity"), "pawn floats not reached")
	check(paths.has("camera.fov_base"), "camera floats not reached")
	check(paths.has("slide.slide_friction"), "per-move floats not reached")
	check(paths.has("wall_run.wall_accel"), "wall_run floats not reached")

func test_inherited_move_config_fields_are_reached_too() -> void:
	# speed_modifier/friction_modifier live on the MoveConfig BASE class, not
	# on CrouchConfig itself. A walk that only reported a resource's own
	# declared properties would silently drop every one of them -- which is
	# most of what makes a move a move.
	var config := MovementConfig.new()
	var paths := _paths(TuningPanel.collect_tunables(config))
	check(paths.has("crouch.speed_modifier"), "inherited MoveConfig fields not reached")
	check(paths.has("slide.friction_modifier"), "inherited friction_modifier not reached")

func test_a_row_can_read_and_write_its_own_value() -> void:
	var config := MovementConfig.new()
	for row in TuningPanel.collect_tunables(config):
		if row["path"] != "pawn.gravity":
			continue
		check_approx(row["owner"].get(row["property"]), 8.0, 0.0001, "row read the wrong value")
		row["owner"].set(row["property"], 12.0)
		check_approx(config.pawn.gravity, 12.0, 0.0001, "writing through a row did not reach the config")
		return
	check(false, "no row for pawn.gravity")

func test_non_float_and_non_resource_properties_are_skipped() -> void:
	var config := MovementConfig.new()
	var paths := _paths(TuningPanel.collect_tunables(config))
	# speed_curve is a PackedVector2Array and cannot be driven by a slider;
	# constrain_look is a bool. Neither belongs in the generated UI.
	check(not paths.has("pawn.speed_curve"), "a non-float property leaked into the rows")
	check(not paths.has("slide.constrain_look"), "a bool property leaked into the rows")

func test_every_row_carries_a_default_from_a_fresh_config() -> void:
	# The slider range is default * RANGE_FACTOR, so a row whose default came
	# from the LIVE config would shrink its own range every time a preset with
	# a smaller value was loaded.
	var config := MovementConfig.new()
	config.pawn.gravity = 1.0
	for row in TuningPanel.collect_tunables(config):
		if row["path"] == "pawn.gravity":
			check_approx(row["default"], 8.0, 0.0001, "default came from the live config, not a fresh one")
			return
	check(false, "no row for pawn.gravity")
```

- [ ] **Step 2: 跑测试确认失败**

Run: `pwsh -File tools/run_tests.ps1`

Expected: FAIL —— `SCRIPT ERROR:` 提示 `TuningPanel` 没有 `collect_tunables` 这个静态方法。

- [ ] **Step 3: 实现 `collect_tunables`**

在 `scripts/debug/tuning_panel.gd` 里加：

```gdscript
## Walks the config's resource tree and returns one row per slider-drivable
## float, in declaration order. Static and UI-free on purpose: this is the
## whole of the panel's model, so it can be tested headlessly (the previous
## version lived inside _build_ui() and could not be).
##
## Recursion depth is exactly one level (aggregate root -> sub-resource) by
## construction, but the walk is written generically so a future nested
## resource does not silently vanish from the panel.
static func collect_tunables(config: MovementConfig) -> Array[Dictionary]:
	var defaults := MovementConfig.new()
	var rows: Array[Dictionary] = []
	for property in config.get_property_list():
		if not (property.usage & PROPERTY_USAGE_EDITOR):
			continue
		if property.type != TYPE_OBJECT:
			continue
		var owner: Resource = config.get(property.name)
		var defaults_owner: Resource = defaults.get(property.name)
		if owner == null or defaults_owner == null:
			continue
		_collect_from(owner, defaults_owner, String(property.name), rows)
	return rows

static func _collect_from(owner: Resource, defaults_owner: Resource, prefix: String, \
		rows: Array[Dictionary]) -> void:
	for property in owner.get_property_list():
		if not (property.usage & PROPERTY_USAGE_EDITOR):
			continue
		if property.type != TYPE_FLOAT:
			continue
		rows.append({
			"path": "%s.%s" % [prefix, property.name],
			"label": String(property.name),
			"group": prefix,
			"owner": owner,
			"property": String(property.name),
			"default": float(defaults_owner.get(property.name)),
		})
```

注意 `get_property_list()` **包含继承来的属性**，所以 `MoveConfig` 基类上的 `speed_modifier` / `friction_modifier` 会自动出现在每个子类的行里——这正是 Step 1 第二个测试要钉住的。

- [ ] **Step 4: 跑测试确认通过**

Run: `pwsh -File tools/run_tests.ps1`

Expected: PASS，`test_tuning_panel_model.gd  5 test(s)`。

- [ ] **Step 5: 用这个模型重建 UI，并把预设存取改成走同一批行**

改写 `_build_ui()`：按 `row["group"]` 变化时插入一条 `— <group> —` 标题，然后为每行调用改造后的 `_add_slider(column, row)`。`_add_slider` 改为从 `row` 读 `owner`/`property`/`default`，回调写 `row["owner"].set(row["property"], v)`。滑块的 `set_meta("row", row)` 取代原来的 `set_meta("property_name", ...)`。

`_on_load()` 原本遍历 `loaded.get_property_list()` 拷贝顶层 float——现在顶层没有 float 了，改成遍历 `collect_tunables(loaded)` 与 `collect_tunables(config)` 并按 `path` 对齐赋值：

```gdscript
func _on_load() -> void:
	var path := "%s/%s.tres" % [PRESET_DIR, _preset_name.text]
	if not ResourceLoader.exists(path):
		_status.text = "no preset at %s" % path
		return
	# CACHE_MODE_IGNORE forces a fresh read: without it, repeated loads of the
	# same path return the cached instance and the panel appears to do nothing.
	# CACHE_MODE_IGNORE_DEEP, not IGNORE: the sub-resources are what actually
	# carry the values now, and a shallow ignore would hand back cached copies
	# of exactly those.
	var loaded: MovementConfig = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	if loaded == null:
		_status.text = "load failed"
		return
	var incoming: Dictionary = {}
	for row in TuningPanel.collect_tunables(loaded):
		incoming[row["path"]] = row["owner"].get(row["property"])
	for row in TuningPanel.collect_tunables(config):
		if incoming.has(row["path"]):
			row["owner"].set(row["property"], incoming[row["path"]])
	_refresh_sliders()
	_status.text = "loaded %s" % path
```

`_refresh_sliders()` 走 `_sliders()`，从每个滑块的 `row` meta 重新读值、`set_value_no_signal()`、刷新标签——保留原来「绝不用普通赋值触发 value_changed」的理由。

- [ ] **Step 6: 人工确认面板可用**

Run: `.engine\Godot_v4.7.1-stable_win64_console.exe --path .`，按 F1。

Expected: 出现分组滑块（`— pawn —`、`— camera —`、`— slide —` …），拖动 `pawn.gravity` 时角色下落立刻变化；输入预设名 Save 后改几个值再 Load，滑块与手感都回到保存时的状态。

- [ ] **Step 7: 提交**

```bash
git add scripts/debug/tuning_panel.gd tests/test_tuning_panel_model.gd
git commit -F - <<'EOF'
feat(tuning): walk the whole config tree instead of one flat resource

Splitting the config left the panel with nothing to show -- it only ever
looked for floats directly on the injected object, and there are none there
any more. It now recurses into each sub-resource, groups by which one a value
came from, and reads inherited MoveConfig fields (speed_modifier and friends)
that a same-class-only walk would have dropped.

The walk itself moves out of _build_ui() into a static, UI-free
collect_tunables(), which is how it gets a test at all: preset load also goes
through it, so a preset now matches by path rather than by a top-level
property name that no longer exists.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
```

---

## Task 4: `PlayerState`/`StateMachine` → `Move`/`MoveManager`

结构骨架已经是对的（注册表 + `enter`/`exit`/`physics_update` + grounded-declaration 不变量，正是 06.5 建议的形状）。本 task 改三件事：每个 Move 拿到自己的 `cfg`、`redo_move_time` 统一冷却、把镜头约束推给相机。**不改任何移动行为。**

**Files:**
- Rename: `scripts/player/states/player_state.gd` → `scripts/player/moves/move.gd`；`state_machine.gd` → `moves/move_manager.gd`；`ground_state.gd` → `moves/walking_move.gd`；`air_state.gd` → `moves/falling_move.gd`；`slide_state.gd` → `moves/slide_move.gd`；`crouch_state.gd` → `moves/crouch_move.gd`；`vault_state.gd` → `moves/speed_vault_move.gd`；`ledge_hang_state.gd` → `moves/grab_move.gd`；`wall_run_state.gd` → `moves/wall_run_move.gd`；`scripted_move.gd` → `moves/scripted_move.gd`
- Modify: `scripts/player/player.gd`、`scripts/level/arena.gd`、`scripts/debug/debug_hud.gd`、`scripts/player/character_animator.gd`、`scripts/camera/camera_rig.gd`
- Test: `tests/test_move_manager.gd`

**Interfaces:**
- Consumes: Task 2 的 `MoveConfig` 与 `MovementConfig` 的各 `*Config` 字段
- Produces:
  - `Move` 常量：`KEEP: StringName = &""`、`WALKING = &"Walking"`、`FALLING = &"Falling"`、`SLIDE = &"Slide"`、`CROUCH = &"Crouch"`、`SPEED_VAULT = &"SpeedVault"`、`GRAB = &"Grab"`、`WALL_RUN = &"WallRun"`
  - `Move` 成员：`player`（untyped）、`config: MovementConfig`、`cfg: MoveConfig`
  - `Move.current_config() -> MoveConfig`（虚方法，默认返回 `cfg`）
  - `MoveManager.register(name: StringName, move: Move) -> void`、`.start(name) -> void`、`.physics_update(delta, input) -> void`、`.current_name: StringName`、`.move_for(name) -> Move`、`.can_enter(name) -> bool`、`signal move_changed(from, to)`
  - `Player.move_manager: MoveManager`（取代 `Player.state_machine`）
  - `CameraRig.set_look_constraint(min_c: Vector3, max_c: Vector3, absolute_yaw: bool) -> void`、`.clear_look_constraint() -> void`

- [ ] **Step 1: 写失败的测试**

Create `tests/test_move_manager.gd`:

```gdscript
class_name TestMoveManager
extends TestCase

# Drives MoveManager with bare stub moves -- no player, no physics -- so the
# manager's own contract (registration, transitions, redo_move_time, the
# look-constraint hand-off) is tested in isolation from any real movement.

class StubMove extends Move:
	var next: StringName = Move.KEEP
	var entered: int = 0
	func enter(_previous: StringName) -> void:
		entered += 1
	func physics_update(_delta: float, _input: MoveInput) -> StringName:
		return next

func _manager(names: Array) -> MoveManager:
	var manager := MoveManager.new()
	tree.root.add_child(manager)
	for n in names:
		var move := StubMove.new()
		move.cfg = MoveConfig.new()
		manager.add_child(move)
		manager.register(n, move)
	return manager

func test_a_transition_enters_the_target_move() -> void:
	var manager := _manager([Move.WALKING, Move.FALLING])
	manager.start(Move.WALKING)
	(manager.move_for(Move.WALKING) as StubMove).next = Move.FALLING
	manager.physics_update(0.016, MoveInput.new())
	check(manager.current_name == Move.FALLING, "did not transition")
	check((manager.move_for(Move.FALLING) as StubMove).entered == 1, "target enter() not called")
	manager.queue_free()
	await step(1)

func test_redo_move_time_blocks_re_entering_the_same_move() -> void:
	# The original gives each move its own cooldown (TdMove.RedoMoveTime,
	# e.g. WallRun 0.15, WallKick 1.0). Centralising it here is what lets the
	# three ad-hoc cooldowns Player used to carry go away.
	var manager := _manager([Move.WALKING, Move.WALL_RUN])
	manager.move_for(Move.WALL_RUN).cfg.redo_move_time = 0.5
	manager.start(Move.WALKING)
	var walking := manager.move_for(Move.WALKING) as StubMove
	var wall := manager.move_for(Move.WALL_RUN) as StubMove

	walking.next = Move.WALL_RUN
	manager.physics_update(0.016, MoveInput.new())
	check(manager.current_name == Move.WALL_RUN, "first entry was blocked")

	wall.next = Move.WALKING
	manager.physics_update(0.016, MoveInput.new())
	check(manager.current_name == Move.WALKING, "did not leave the wall")

	# Still cooling down: the request is refused and the manager simply stays.
	manager.physics_update(0.016, MoveInput.new())
	check(manager.current_name == Move.WALKING, "redo_move_time did not block re-entry")

	# Park the wall move before running the clock out, or the two stubs bounce
	# off each other for the rest of the loop and the final state says nothing.
	wall.next = Move.KEEP
	for i in 40:
		manager.physics_update(0.016, MoveInput.new())
	check(manager.current_name == Move.WALL_RUN, "cooldown never expired")
	manager.queue_free()
	await step(1)

func test_a_move_with_no_cooldown_can_be_re_entered_immediately() -> void:
	var manager := _manager([Move.WALKING, Move.SLIDE])
	manager.start(Move.WALKING)
	var walking := manager.move_for(Move.WALKING) as StubMove
	var slide := manager.move_for(Move.SLIDE) as StubMove
	walking.next = Move.SLIDE
	slide.next = Move.WALKING
	for i in 4:
		manager.physics_update(0.016, MoveInput.new())
	check((manager.move_for(Move.SLIDE) as StubMove).entered == 2, "a zero cooldown blocked re-entry")
	manager.queue_free()
	await step(1)

func test_current_config_defaults_to_the_moves_own_cfg() -> void:
	var move := StubMove.new()
	var cfg := MoveConfig.new()
	move.cfg = cfg
	check(move.current_config() == cfg, "current_config() did not fall through to cfg")
```

- [ ] **Step 2: 跑测试确认失败**

Run: `pwsh -File tools/run_tests.ps1`

Expected: FAIL —— `Move` / `MoveManager` 未声明。

- [ ] **Step 3: 由 `player_state.gd` 改出 `move.gd`**

`git mv scripts/player/states/player_state.gd scripts/player/moves/move.gd`，然后：

```gdscript
class_name Move
extends Node

# One movement action -- the Godot counterpart of the original's TdMove. A
# move decides its own outgoing transitions: every question of the form "can
# I go from X to Y" has exactly one answer, and it lives in X's
# physics_update.
#
# Names live here rather than on Player. GDScript resolves class_name globals
# at parse time, so if the moves referenced Player.FALLING while Player
# referenced WalkingMove, the two scripts would form a cycle and fail to
# resolve. Keeping the names on this layer makes the dependency
# one-directional: Player -> moves -> Move.
#
# Names follow the original's own move classes (minus the Td prefix):
# TdMove_Walking, TdMove_Falling, TdMove_Slide, TdMove_Crouch,
# TdMove_SpeedVault, TdMove_Grab, TdMove_WallRun.

## Returned from physics_update to stay in the current move.
const KEEP: StringName = &""

const WALKING: StringName = &"Walking"
const FALLING: StringName = &"Falling"
const SLIDE: StringName = &"Slide"
const CROUCH: StringName = &"Crouch"
const SPEED_VAULT: StringName = &"SpeedVault"
const GRAB: StringName = &"Grab"
const WALL_RUN: StringName = &"WallRun"

## Set by Player before the manager starts. Untyped for the same reason the
## names live here: a typed reference would reintroduce the cycle.
var player

## The whole config tree, for the Pawn-wide values every move needs.
var config: MovementConfig

## This move's OWN declared parameters. Assigned by Player at registration
## from the matching MovementConfig field.
var cfg: MoveConfig

## The MoveConfig in force RIGHT NOW. Overridable because the original splits
## a single airborne stretch across two move classes with different probe
## switches -- TdMove_Jump while rising, TdMove_Falling while descending (05
## §5.7 ③) -- and FallingMove reproduces that split without doubling the
## machine. Everything else returns its own cfg.
func current_config() -> MoveConfig:
	return cfg

func enter(_previous: StringName) -> void:
	pass

## Returns the name of the move to switch to, or KEEP to stay.
func physics_update(_delta: float, _input: MoveInput) -> StringName:
	return KEEP

func exit() -> void:
	pass
```

- [ ] **Step 4: 由 `state_machine.gd` 改出 `move_manager.gd`**

`git mv scripts/player/states/state_machine.gd scripts/player/moves/move_manager.gd`。类名与类型改掉（`StateMachine` → `MoveManager`，`PlayerState` → `Move`，`_states` → `_moves`，`signal state_changed` → `move_changed`），**grounded-declaration 不变量整段原样保留**（连同它上面那段长注释和 `assert` / `push_error` 的消息文本——`run_tests.ps1` 的 allowlist 依赖那段文本）。新增两块：

```gdscript
## Seconds of cooldown still owed per move name. An entry only exists while a
## move is actually cooling down.
var _redo_cooldowns: Dictionary = {}

## False while `move_name`'s own redo_move_time is still running. The original
## declares this per move (TdMove.RedoMoveTime) rather than scattering it
## across the callers, which is what lets Player stop carrying three separate
## hand-rolled cooldowns of its own (the ledge regrab timer, the recent-wall
## list, and the wall reattach window).
func can_enter(move_name: StringName) -> bool:
	return not _redo_cooldowns.has(move_name)

func _tick_cooldowns(delta: float) -> void:
	for key in _redo_cooldowns.keys():
		var remaining: float = _redo_cooldowns[key] - delta
		if remaining <= 0.0:
			_redo_cooldowns.erase(key)
		else:
			_redo_cooldowns[key] = remaining

func _arm_cooldown(move_name: StringName, move: Move) -> void:
	var seconds: float = move.cfg.redo_move_time if move.cfg != null else 0.0
	if seconds > 0.0:
		_redo_cooldowns[move_name] = seconds
```

`physics_update()` 开头调 `_tick_cooldowns(delta)`；拿到 `next` 之后、`assert` 之前插入拒绝分支：

```gdscript
	# A move that asks for a target still cooling down simply stays put. Done
	# here rather than in each caller so no move can forget, and so the
	# refusal never silently drops the tick's own transition INTENT into some
	# third state.
	if not can_enter(next):
		_check_declared_grounded()
		return
```

`_current.exit()` 之后调 `_arm_cooldown(from, 出去的那个 move)`。

再加镜头约束推送——放在 `physics_update()` 末尾与 `start()` 末尾各一次：

```gdscript
## Pushes the ACTIVE move's look clamp to the camera every tick. The original
## makes this per-move data (MinLookConstraint / MaxLookConstraint /
## bConstrainLook, see 06 §6.2 and 04 §4.1), and it is an INPUT constraint,
## not an animation effect -- "the view swings to face along the wall" is this
## and nothing else. Pushed every tick rather than only on transition because
## FallingMove's own constraint changes mid-move (see Move.current_config()).
func _push_look_constraint() -> void:
	if _current == null or _current.player == null:
		return
	var rig = _current.player.camera_rig
	if rig == null:
		return
	var active: MoveConfig = _current.current_config()
	if active == null or not active.constrain_look:
		rig.clear_look_constraint()
		return
	rig.set_look_constraint(active.min_look_constraint, active.max_look_constraint, \
		active.absolute_yaw_constraint)
```

- [ ] **Step 5: 给 `CameraRig` 加约束接口（本 task 只存不用）**

在 `camera_rig.gd` 加三个成员与两个方法。**本 task 只把值存下来，`apply_look()` 暂不消费**——真正生效在 Task 15，那里连同贴墙滚转方向一起改，才有可人工验证的观感变化。

```gdscript
## The active move's look clamp, in radians, or "no clamp" when
## _has_look_constraint is false. Driven by MoveManager every tick; consumed
## by apply_look() from Task 15 onward.
var _look_min: Vector3 = Vector3(-PI, -PI, -PI)
var _look_max: Vector3 = Vector3(PI, PI, PI)
var _look_absolute_yaw: bool = false
var _has_look_constraint: bool = false

func set_look_constraint(min_c: Vector3, max_c: Vector3, absolute_yaw: bool) -> void:
	_look_min = min_c
	_look_max = max_c
	_look_absolute_yaw = absolute_yaw
	_has_look_constraint = true

func clear_look_constraint() -> void:
	_has_look_constraint = false
```

`reset_state()` 里也把 `_has_look_constraint` 置回 `false`。

- [ ] **Step 6: 改名七个 move 并接上各自的 cfg**

逐个 `git mv` 并改类名：`ground_state.gd`→`walking_move.gd`/`WalkingMove`，`air_state.gd`→`falling_move.gd`/`FallingMove`，`slide_state.gd`→`slide_move.gd`/`SlideMove`，`crouch_state.gd`→`crouch_move.gd`/`CrouchMove`，`vault_state.gd`→`speed_vault_move.gd`/`SpeedVaultMove`，`ledge_hang_state.gd`→`grab_move.gd`/`GrabMove`，`wall_run_state.gd`→`wall_run_move.gd`/`WallRunMove`，`scripted_move.gd` 只移目录不改名。

每个文件里把 `extends PlayerState` 改成 `extends Move`，常量引用 `GROUND`→`WALKING`、`AIR`→`FALLING`、`VAULT`→`SPEED_VAULT`、`LEDGE`→`GRAB`、`WALL`→`WALL_RUN`。

⚠️ `slide_move.gd` 顶部那段注释里写着「第一个测试会 grep 本文件源码里 `PlayerState` 的常量名」——那个测试已归档，但注释仍然准确描述了设计意图（Slide 不得直接进 WallRun），**把注释里的类名更新为 `Move`，意图保留**。

`FallingMove` 覆写 `current_config()`：

```gdscript
## The original splits one airborne stretch into two move classes whose probe
## switches differ: TdMove_Jump can start a wall climb, TdMove_Falling cannot
## (05 §5.7 ③). Reproduced here as one move with two configs rather than two
## registered moves, so landing detection, the wall check and the ledge check
## stay in one place instead of being duplicated across a pair.
func current_config() -> MoveConfig:
	return config.jump if player.velocity.y > 0.0 else config.falling
```

- [ ] **Step 7: 改 `Player`、`Arena`、`DebugHud`、`CharacterAnimator`**

`player.gd`：`var state_machine: StateMachine` → `var move_manager: MoveManager`；`_build_state_machine()` → `_build_moves()`，注册时同时赋 `config`/`cfg`：

```gdscript
func _build_moves() -> void:
	move_manager = MoveManager.new()
	add_child(move_manager)

	# name -> [move instance, its own config]. One table instead of the
	# seven near-identical blocks this used to be, so a new move is one row.
	var table := [
		[Move.WALKING, WalkingMove.new(), config.walking],
		[Move.FALLING, FallingMove.new(), config.falling],
		[Move.SLIDE, SlideMove.new(), config.slide],
		[Move.CROUCH, CrouchMove.new(), config.crouch],
		[Move.SPEED_VAULT, SpeedVaultMove.new(), config.speed_vault],
		[Move.GRAB, GrabMove.new(), config.grab],
		[Move.WALL_RUN, WallRunMove.new(), config.wall_run],
	]
	for row in table:
		var move: Move = row[1]
		move.player = self
		move.config = config
		move.cfg = row[2]
		move_manager.add_child(move)
		move_manager.register(row[0], move)

	move_manager.start(Move.WALKING)
```

⚠️ **`player.gd:474` 有一个同名局部变量 `var state_machine := AnimationNodeStateMachine.new()`**——那是动画树，与移动无关，**不要改它**。

`arena.gd:72`：`player.state_machine.start(PlayerState.GROUND)` → `player.move_manager.start(Move.WALKING)`。

`debug_hud.gd:25,29`：`player.state_machine` → `player.move_manager`。

`character_animator.gd`：`player.state_machine` → `player.move_manager`（3 处），`PlayerState.KEEP/GROUND/AIR/SLIDE/VAULT/LEDGE/WALL/CROUCH` → `Move.KEEP/WALKING/FALLING/SLIDE/SPEED_VAULT/GRAB/WALL_RUN/CROUCH`，`state_for` → `move_for`。

- [ ] **Step 8: 跑测试确认通过**

Run: `pwsh -File tools/run_tests.ps1`

Expected: PASS，`test_move_manager.gd  5 test(s)`，无 `SCRIPT ERROR:`。

- [ ] **Step 9: 人工确认行为未变**

Run: `.engine\Godot_v4.7.1-stable_win64_console.exe --path .`

Expected: 跑跳滑铲贴墙翻越全部与 Task 3 之后一致；Tab 打开的 debug HUD 里状态名现在显示 `Walking` / `Falling` / `WallRun` 等新名字。**没有任何手感变化**——`redo_move_time` 全部默认 0，镜头约束全部未启用。

- [ ] **Step 10: 提交**

```bash
git add -A scripts tests
git commit -F - <<'EOF'
refactor(moves): make each state a Move that declares its own parameters

The skeleton was already the shape the original uses -- a registry of action
classes with enter/exit/update -- so it stays. What it lacked was the half
that makes the shape worth having: a move could not declare anything about
itself, so its speed multiplier, friction multiplier, cooldown, look clamp
and probe switches all had to be hardcoded somewhere else.

RedoMoveTime now lives on the manager, which is what will let Player stop
carrying three hand-rolled cooldowns of its own. The look clamp is pushed to
the camera every tick but not yet consumed -- that lands with the wall-run
constraint, where it has something visible to verify against.

Names follow the original's move classes: Ground/Air/Vault/Ledge/Wall become
Walking/Falling/SpeedVault/Grab/WallRun. No behaviour change.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
```

---

## Task 5: `SpeedEnergy` 组件（纯逻辑，未接线）

10.4 验收表的第 1 条，也是研究反复强调的「第一判据」。本 task 只造零件并测透，不接线——接线在 Task 6，那时才有手感变化可验证。

**Files:**
- Create: `scripts/player/speed_energy.gd`
- Modify: `scripts/player/config/pawn_config.gd`（加 `speed_curve_interp_mode`、`speed_curve_smooth_fit`）
- Test: `tests/test_speed_energy.gd`

**Interfaces:**
- Consumes: `PawnConfig` 的整个 `Speed energy` 分组
- Produces: `SpeedEnergy`（`extends RefCounted`）
  - `SpeedEnergy.new(pawn: PawnConfig)`
  - `enum Mode { WALK, STRAFE, SPRINT }`（`SpeedEnergy.WALK` 等）
  - `energy: float`（可读可写）
  - `cap() -> float`
  - `accumulate(delta: float, mode: int) -> void`
  - `decay(delta: float) -> void`
  - `spend_turn(radians: float) -> void`
  - `drain(amount: float) -> void`
  - `reset() -> void`
  - `static curve_at(pawn: PawnConfig, e: float) -> float`

- [ ] **Step 1: 给 `PawnConfig` 加两个曲线字段**

```gdscript
## LINEAR reproduces the original exactly (its curve is an InterpCurveFloat
## with interpolation mode CIM_Linear, 02 §2.1). SMOOTH is an opt-in feel
## variant: because accel_rate is far larger than any segment's slope, the
## curve's slope IS the felt acceleration, so the piecewise form steps it
## 10.0 -> 2.0 -> 0.52 -> 0.20 m/s^2 at three instants. Whether that reads as
## a gear change is an empirical question, so it is a switch, not an argument.
@export_enum("LINEAR", "SMOOTH") var speed_curve_interp_mode: int = 0

## (A, a, B, b) of v(E) = A*(1 - e^(-E/a)) + B*(1 - e^(-E/b)), the SMOOTH
## mode's curve. Fitted OFFLINE to the five confirmed knots above with
## scipy.optimize.curve_fit; measured residual at every knot is under 1e-4,
## i.e. this passes through all five confirmed points and only differs
## BETWEEN them -- exactly the region the source data never constrained.
## Peak divergence from LINEAR is +0.76 m/s at E = 0.17 (the opening 0.4 s
## is noticeably punchier); the sum A + B = 7.556 overshoots ground_speed, so
## cap() clamps.
##
## IF THE KNOTS ABOVE ARE EVER EDITED, THESE MUST BE REFITTED:
##   import numpy as np; from scipy.optimize import curve_fit
##   t = np.array([0,.4,1,3.5,7.]); v = np.array([0,4.,5.2,6.5,7.2])
##   f = lambda t,A,a,B,b: A*(1-np.exp(-t/a)) + B*(1-np.exp(-t/b))
##   print(curve_fit(f, t, v, p0=[4,.3,3,3.], maxfev=200000)[0])
## tests/test_speed_energy.gd's knot test is the guard against forgetting.
@export var speed_curve_smooth_fit: Vector4 = Vector4(4.4222, 0.23199, 3.1335, 3.2169)
```

- [ ] **Step 2: 写失败的测试**

Create `tests/test_speed_energy.gd`:

```gdscript
class_name TestSpeedEnergy
extends TestCase

# Pure logic, no physics world. This is the one layer of the rebuild that can
# be fully verified without a human playing the game, so it is tested hard.

func _pawn() -> PawnConfig:
	return PawnConfig.new()

func test_the_curve_passes_through_every_confirmed_knot() -> void:
	var pawn := _pawn()
	for knot in pawn.speed_curve:
		check_approx(SpeedEnergy.curve_at(pawn, knot.x), knot.y, 0.0001, \
			"LINEAR curve misses the confirmed knot at E=%f" % knot.x)

func test_the_smooth_curve_also_passes_through_every_confirmed_knot() -> void:
	# This is the guard against the fitted coefficients silently drifting away
	# from the knots -- see speed_curve_smooth_fit's own note.
	var pawn := _pawn()
	pawn.speed_curve_interp_mode = 1
	for knot in pawn.speed_curve:
		check_approx(SpeedEnergy.curve_at(pawn, knot.x), knot.y, 0.001, \
			"SMOOTH curve misses the confirmed knot at E=%f" % knot.x)

func test_the_curve_is_flat_past_its_last_knot() -> void:
	var pawn := _pawn()
	check_approx(SpeedEnergy.curve_at(pawn, 20.0), 7.2, 0.0001, "curve kept climbing past E=7")

func test_the_cap_never_exceeds_ground_speed_in_either_mode() -> void:
	# SMOOTH's own asymptote is 7.556, above ground_speed, so the clamp is
	# load-bearing rather than defensive.
	var pawn := _pawn()
	pawn.speed_curve_interp_mode = 1
	var energy := SpeedEnergy.new(pawn)
	energy.energy = 100.0
	check_approx(energy.cap(), 7.2, 0.0001, "SMOOTH cap escaped ground_speed")

func test_the_cap_never_drops_below_the_base_velocity_floor() -> void:
	# The curve's own v(0) is 0, which would freeze a standing start solid.
	var pawn := _pawn()
	var energy := SpeedEnergy.new(pawn)
	energy.energy = 0.0
	check_approx(energy.cap(), pawn.speed_min_base_velocity, 0.0001, "no floor under the cap")

func test_ordinary_running_reaches_the_top_of_the_curve_in_seven_seconds() -> void:
	# The single most-cited property of the original's speed system: 7 seconds
	# from a standstill to full speed. Sprint factor / sprint factor = 1.0, so
	# one second of running is one unit of energy, and the curve's X axis is
	# in seconds by construction.
	var pawn := _pawn()
	var energy := SpeedEnergy.new(pawn)
	for i in 420:
		energy.accumulate(1.0 / 60.0, SpeedEnergy.SPRINT)
	check_approx(energy.cap(), 7.2, 0.01, "seven seconds of running did not reach top speed")

func test_energy_is_more_than_half_spent_in_the_first_four_tenths_of_a_second() -> void:
	# The curve's shape, stated as behaviour: 55% of the final speed arrives
	# in the first 0.4 s and the remaining 45% takes the other 6.6.
	var pawn := _pawn()
	var energy := SpeedEnergy.new(pawn)
	for i in 24:
		energy.accumulate(1.0 / 60.0, SpeedEnergy.SPRINT)
	check_greater(energy.cap(), 7.2 * 0.5, "the opening of the curve is not steep enough")
	check(energy.cap() < 7.2 * 0.6, "the opening of the curve overshot its 55% share")

func test_strafing_and_walking_bank_energy_more_slowly_than_running() -> void:
	var pawn := _pawn()
	var run := SpeedEnergy.new(pawn)
	var strafe := SpeedEnergy.new(pawn)
	var walk := SpeedEnergy.new(pawn)
	for i in 60:
		run.accumulate(1.0 / 60.0, SpeedEnergy.SPRINT)
		strafe.accumulate(1.0 / 60.0, SpeedEnergy.STRAFE)
		walk.accumulate(1.0 / 60.0, SpeedEnergy.WALK)
	check_greater(run.energy, strafe.energy, "strafing banked energy as fast as running")
	check_greater(strafe.energy, walk.energy, "walking banked energy as fast as strafing")
	check_approx(strafe.energy, 10.0 / 30.0, 0.001, "strafe factor is not 10/30 per second")
	check_approx(walk.energy, 7.0 / 30.0, 0.001, "walk factor is not 7/30 per second")

func test_a_full_energy_budget_decays_to_nothing_in_three_seconds() -> void:
	# SpeedEnergyDecelerationTime = 3, with the 0.5 exponent taken literally:
	# dE/dt = -k * sqrt(E), k solved so a full budget empties in exactly T.
	# Integrated with explicit Euler at the physics tick rate; the expected
	# values below were measured against that integration, not against the
	# closed form (Euler runs slightly ahead of it because |dE/dt| shrinks
	# within each step).
	var pawn := _pawn()
	var energy := SpeedEnergy.new(pawn)
	energy.energy = 7.0
	for i in 150:
		energy.decay(1.0 / 60.0)
	check_approx(energy.energy, 0.183, 0.02, "decay at 2.5 s is off the measured curve")
	for i in 30:
		energy.decay(1.0 / 60.0)
	check_approx(energy.energy, 0.0, 0.001, "a full budget did not empty in three seconds")

func test_decay_is_fast_at_first_and_slow_near_zero() -> void:
	# The shape the research describes in words. Half the elapsed time must
	# take far more than half the energy.
	var pawn := _pawn()
	var energy := SpeedEnergy.new(pawn)
	energy.energy = 7.0
	for i in 90:
		energy.decay(1.0 / 60.0)
	check(energy.energy < 7.0 * 0.3, "half the decay window did not take most of the energy")
	check_greater(energy.energy, 0.0, "decay reached zero too early")

func test_energy_never_goes_negative() -> void:
	var pawn := _pawn()
	var energy := SpeedEnergy.new(pawn)
	energy.energy = 0.5
	for i in 600:
		energy.decay(1.0 / 60.0)
	check_approx(energy.energy, 0.0, 0.0001, "energy went negative")

func test_a_full_reversal_spends_the_entire_budget() -> void:
	# The calibration the turn cost is set from: the original's own
	# SpeedTurnDecelerationFactor = 10 has an unrecoverable unit, so the knob
	# is pinned to a stated behaviour instead.
	var pawn := _pawn()
	var energy := SpeedEnergy.new(pawn)
	energy.energy = 7.0
	energy.spend_turn(PI)
	check_approx(energy.energy, 0.0, 0.02, "a 180 degree reversal did not spend the budget")

func test_a_quarter_turn_costs_half_the_budget() -> void:
	var pawn := _pawn()
	var energy := SpeedEnergy.new(pawn)
	energy.energy = 7.0
	energy.spend_turn(PI * 0.5)
	check_approx(energy.energy, 3.5, 0.02, "a 90 degree turn did not cost half the budget")

func test_turning_has_no_free_allowance() -> void:
	# 10.1 ③: the research found no "costs nothing below N degrees" threshold
	# parameter anywhere, which is what makes turning a continuous tax rather
	# than a gate. A tiny turn must still cost something.
	var pawn := _pawn()
	var energy := SpeedEnergy.new(pawn)
	energy.energy = 7.0
	energy.spend_turn(deg_to_rad(1.0))
	check(energy.energy < 7.0, "a small turn was free")
```

- [ ] **Step 3: 跑测试确认失败**

Run: `pwsh -File tools/run_tests.ps1`

Expected: FAIL —— `SpeedEnergy` 未声明。

- [ ] **Step 4: 实现 `SpeedEnergy`**

Create `scripts/player/speed_energy.gd`:

```gdscript
class_name SpeedEnergy
extends RefCounted

# The original's two-layer speed model (02 §2.5), which is the single largest
# source of its feel:
#
#   layer 1 (fast): actual speed --accel_rate--> the current cap
#   layer 2 (slow): the cap      <--speed_curve(energy)-- speed energy
#
# The player's input drives layer 2. Layer 1 only keeps the body glued to
# whatever ceiling layer 2 currently allows. Collapsing the two into one --
# which is what a constant ground_speed does -- is exactly what makes speed
# stop being an asset worth protecting.
#
# Deliberately RefCounted, not a Node: nothing here touches the scene tree,
# which is what lets the whole layer be tested without a physics world.

## Which accumulation factor is in force this tick. The original declares
## three (02 §2.1, all ✅ as values, ⚠️ as direction).
enum { WALK, STRAFE, SPRINT }

var energy: float = 0.0

var _pawn: PawnConfig

func _init(pawn: PawnConfig) -> void:
	_pawn = pawn

func reset() -> void:
	energy = 0.0

## The ground speed ceiling for the current energy, clamped into
## [speed_min_base_velocity, ground_speed]. The upper clamp is load-bearing
## in SMOOTH mode, whose own asymptote (A + B = 7.556) sits above
## ground_speed; the lower one keeps a standing start from being frozen at
## the curve's own v(0) = 0.
func cap() -> float:
	return clampf(curve_at(_pawn, energy), _pawn.speed_min_base_velocity, _pawn.ground_speed)

## Evaluates the speed curve at `e`. Static and taking the config explicitly
## so tests (and the arena builder) can ask about a curve without owning an
## energy budget.
static func curve_at(pawn: PawnConfig, e: float) -> float:
	if pawn.speed_curve_interp_mode == 1:
		var f := pawn.speed_curve_smooth_fit
		return f.x * (1.0 - exp(-e / f.y)) + f.z * (1.0 - exp(-e / f.w))
	var knots := pawn.speed_curve
	if knots.is_empty():
		return 0.0
	if e <= knots[0].x:
		return knots[0].y
	for i in range(1, knots.size()):
		var a := knots[i - 1]
		var b := knots[i]
		if e <= b.x:
			var span := b.x - a.x
			if span <= 0.0:
				return b.y
			return a.y + (b.y - a.y) * ((e - a.x) / span)
	# Past the last knot the original holds its final value rather than
	# extrapolating -- GroundSpeed IS the curve's ceiling (02 §2.1).
	return knots[knots.size() - 1].y

## One tick of running banks (active factor / sprint factor) seconds of
## energy, so ordinary running is 1.0 and the curve's X axis is literally
## seconds-of-running. Callers are responsible for the
## energy_accumulate_speed_ratio gate -- see Player, which owns the speed
## reading this class deliberately does not.
func accumulate(delta: float, mode: int) -> void:
	var sprint: float = maxf(_pawn.speed_sprint_velocity_acceleration_factor, 0.001)
	var factor: float = sprint
	match mode:
		WALK:
			factor = _pawn.speed_walk_velocity_acceleration_factor
		STRAFE:
			factor = _pawn.speed_strafe_velocity_acceleration_factor
	energy = minf(energy + delta * (factor / sprint), _energy_ceiling())

## dE/dt = -k * E^exponent, with k solved so a FULL budget empties in exactly
## speed_energy_deceleration_time. Explicit Euler at the physics tick rate,
## which runs slightly ahead of the closed form because the rate shrinks
## within each step -- pinned by the measured values in the tests rather than
## by the analytic solution.
func decay(delta: float) -> void:
	if energy <= 0.0:
		energy = 0.0
		return
	var e_max: float = _energy_ceiling()
	var time: float = maxf(_pawn.speed_energy_deceleration_time, 0.001)
	var exponent: float = _pawn.speed_energy_deceleration_exponent
	# Solving (d/dt)E = -k*E^p for E(0) = e_max reaching 0 at t = time gives
	# k = e_max^(1-p) / ((1-p) * time). At p = 0.5 that is 2*sqrt(e_max)/time.
	var k: float = pow(e_max, 1.0 - exponent) / (maxf(1.0 - exponent, 0.001) * time)
	energy = maxf(energy - k * pow(energy, exponent) * delta, 0.0)

## Turning is a continuous tax with no free allowance (10.1 ③): the research
## found no "costs nothing below N degrees" parameter anywhere in the game.
func spend_turn(radians: float) -> void:
	drain(_pawn.speed_turn_deceleration_factor * absf(radians))

func drain(amount: float) -> void:
	energy = maxf(energy - absf(amount), 0.0)

## The curve's own last knot -- the energy at which the cap stops climbing.
## Both the accumulation clamp and the decay rate are derived from it rather
## than from a second, separately-tunable number that could disagree with the
## curve.
func _energy_ceiling() -> float:
	var knots := _pawn.speed_curve
	return knots[knots.size() - 1].x if not knots.is_empty() else 1.0
```

- [ ] **Step 5: 把转向系数改成 7.0/π 的精确值**

`PawnConfig.speed_turn_deceleration_factor` 的默认值由 spec 里写的 `2.23` 改为 **`2.2282`**（= 7.0/π），这样「180° 掉头恰好花光 7.0」是精确成立而不是四舍五入近似——Step 2 的两个标定测试用 0.02 容差正是按这个值定的。在 doc comment 里写明它是 `energy ceiling / PI` 推出来的。

- [ ] **Step 6: 跑测试确认通过**

Run: `pwsh -File tools/run_tests.ps1`

Expected: PASS，`test_speed_energy.gd  14 test(s)`。

- [ ] **Step 7: 提交**

```bash
git add scripts/player/speed_energy.gd scripts/player/config/pawn_config.gd tests/test_speed_energy.gd
git commit -F - <<'EOF'
feat(movement): add the speed-energy curve layer

The original's ground speed is not a constant, it is the ceiling of a curve
that takes seven seconds to climb -- 55% of it arrives in the first 0.4 s and
the remaining 45% takes the other 6.6. That shape is the reason speed is an
asset worth protecting, and every loss mechanism in the game is built on top
of it being hard to earn.

Both interpolation modes are here: LINEAR reproduces the original's own
CIM_Linear table exactly, SMOOTH is an opt-in variant whose fitted
coefficients pass through all five confirmed knots and differ only between
them. A test pins that property so the fit cannot drift away from the knots
unnoticed.

Not wired to anything yet -- this commit is the component and its tests.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
```

---

## Task 6: 落地三件套一起校准（下落高度计数器 + 四档 + `base_jump_z`）

**这三组数必须一起改。** spec §0.1 记录的现存缺陷正是它们不同步的后果：`base_jump_z = 6.3` 的 apex 是 2.48 m，越过了 2.0 m 的翻滚阈值，于是每一次平地跳跃落地都掉 31% 水平速度。改成实测确证的 5.6 之后 apex 恰好 1.96 m，卡在阈值下方 4 cm——原版这个 2% 余量几乎不可能是巧合。

单独改跳跃、或单独改落地判定，都会让手感更糟而不是更好。

**Files:**
- Create: `scripts/player/fall_tracker.gd`
- Modify: `scripts/player/player.gd`、`scripts/player/moves/falling_move.gd`、`scripts/player/moves/walking_move.gd`、`scripts/player/config/pawn_config.gd`（删 5 个字段、改 1 个值）
- Regenerate: `scenes/main.tscn`（经 `tools/build_main_scene.gd`）
- Test: `tests/test_fall_tracker.gd`、`tests/test_landing_tiers.gd`

**Interfaces:**
- Consumes: `PawnConfig` 的 `Landing` 分组
- Produces:
  - `FallTracker`（`extends RefCounted`）：`FallTracker.new(pawn: PawnConfig)`、`fall_height: float`、`update(delta: float, vertical_velocity: float, world_y: float) -> void`、`reset() -> void`
  - `Player.fall_tracker: FallTracker`
  - `Player.landing_tier(fall_height: float) -> int`，返回 `Player.TIER_FREE / TIER_SOFT / TIER_ROLLABLE / TIER_HARD`
  - `Player.landing_keep_ratio(fall_height: float, rolled: bool) -> float`

- [ ] **Step 1: 写失败的测试（计数器）**

Create `tests/test_fall_tracker.gd`:

```gdscript
class_name TestFallTracker
extends TestCase

# The counter the whole landing system reads instead of velocity.y. Getting
# this shape right is what makes the community's ventkick / drop-roll layer
# possible at all -- 03 §3.5 is explicit that reading the current frame's
# vertical speed can never produce those behaviours.

func _tracker() -> FallTracker:
	return FallTracker.new(PawnConfig.new())

func test_a_gentle_step_off_does_not_start_counting() -> void:
	# EnterToFallingZSpeed = -200 uu/s: the first fraction of a step-down is
	# deliberately not counted at all.
	var tracker := _tracker()
	tracker.update(1.0 / 60.0, -0.5, 10.0)
	tracker.update(1.0 / 60.0, -1.0, 9.99)
	check_approx(tracker.fall_height, 0.0, 0.0001, "counting started below the falling threshold")

func test_it_accumulates_height_lost_since_the_fall_began() -> void:
	var tracker := _tracker()
	tracker.update(1.0 / 60.0, -3.0, 10.0)
	tracker.update(1.0 / 60.0, -4.0, 8.0)
	tracker.update(1.0 / 60.0, -5.0, 6.0)
	check_approx(tracker.fall_height, 4.0, 0.0001, "did not accumulate the drop")

func test_it_measures_from_the_highest_point_not_the_first_sample() -> void:
	# A wall-jump chain rises after the counter has already armed. The drop
	# that matters is the one from the apex, not from wherever the counter
	# happened to start.
	var tracker := _tracker()
	tracker.update(1.0 / 60.0, -3.0, 10.0)
	tracker.update(1.0 / 60.0, 5.0, 14.0)
	tracker.update(1.0 / 60.0, -3.0, 11.0)
	check_approx(tracker.fall_height, 3.0, 0.0001, "measured from the first sample instead of the apex")

func test_reset_clears_the_counter() -> void:
	# Any ground contact resets it. This is the whole mechanism behind the
	# community's drop-roll: touch down, and the accumulated height is gone
	# before you step off the edge again.
	var tracker := _tracker()
	tracker.update(1.0 / 60.0, -3.0, 10.0)
	tracker.update(1.0 / 60.0, -6.0, 4.0)
	check_greater(tracker.fall_height, 5.0, "nothing accumulated to reset")
	tracker.reset()
	check_approx(tracker.fall_height, 0.0, 0.0001, "reset did not clear the counter")

func test_rising_alone_never_produces_a_fall() -> void:
	var tracker := _tracker()
	for i in 30:
		tracker.update(1.0 / 60.0, 5.0, 10.0 + i)
	check_approx(tracker.fall_height, 0.0, 0.0001, "climbing registered as a fall")
```

- [ ] **Step 2: 写失败的测试（四档）**

Create `tests/test_landing_tiers.gd`:

```gdscript
class_name TestLandingTiers
extends TestCase

# The four-tier landing table (03 §3.1), stated as behaviour. Tier boundaries
# are fall HEIGHTS, not impact speeds -- that difference is the point.

func _player_stub() -> Player:
	var player := Player.new()
	player.config = MovementConfig.new()
	return player

func test_a_flat_jump_lands_in_the_free_tier() -> void:
	# The calibration this whole task exists for: base_jump_z 5.6 against
	# gravity 8.0 peaks at 1.96 m, four centimetres under the 2.0 m roll
	# threshold, so an ordinary jump can never cost speed.
	var player := _player_stub()
	var pawn := player.config.pawn
	var apex: float = pawn.base_jump_z * pawn.base_jump_z / (2.0 * pawn.gravity)
	check_approx(apex, 1.96, 0.005, "the jump arc is not the confirmed one")
	check(apex < pawn.skill_roll_landing_height, "a flat jump reaches the roll threshold")
	check(player.landing_tier(apex) == Player.TIER_FREE, "a flat jump is not in the free tier")
	check_approx(player.landing_keep_ratio(apex, false), 1.0, 0.0001, "a flat jump cost speed")
	player.free()

func test_the_free_tier_costs_nothing_at_all() -> void:
	# Not "costs a little" -- the original has a genuinely free band, which
	# the old continuous ramp from zero did not.
	var player := _player_stub()
	check_approx(player.landing_keep_ratio(1.99, false), 1.0, 0.0001, "the free band is not free")
	check_approx(player.landing_keep_ratio(0.2, false), 1.0, 0.0001, "a curb cost speed")
	player.free()

func test_a_roll_fully_negates_a_soft_landing() -> void:
	var player := _player_stub()
	check(player.landing_tier(2.5) == Player.TIER_SOFT, "2.5 m is not the soft tier")
	check(player.landing_keep_ratio(2.5, false) < 1.0, "an unrolled soft landing was free")
	check_approx(player.landing_keep_ratio(2.5, true), 1.0, 0.0001, "a rolled soft landing still cost speed")
	player.free()

func test_a_roll_only_softens_the_rollable_tier() -> void:
	# Community consensus (03 §3.1): ME1's skill roll bleeds speed of its own
	# when you keep moving forward out of it, so a roll above the soft band is
	# a discount, never a cancellation.
	var player := _player_stub()
	check(player.landing_tier(4.0) == Player.TIER_ROLLABLE, "4.0 m is not the rollable tier")
	var rolled := player.landing_keep_ratio(4.0, true)
	var unrolled := player.landing_keep_ratio(4.0, false)
	check_greater(rolled, unrolled, "rolling did not help")
	check(rolled < 1.0, "a roll fully cancelled a rollable-tier landing")
	player.free()

func test_a_hard_landing_keeps_only_the_reduction_share() -> void:
	var player := _player_stub()
	check(player.landing_tier(6.0) == Player.TIER_HARD, "6.0 m is not the hard tier")
	check_approx(player.landing_keep_ratio(6.0, false), 0.35, 0.0001, "hard landing keep ratio is wrong")
	player.free()

func test_no_tier_can_ever_add_speed() -> void:
	# The F1 panel sizes every slider to three times its default, so any keep
	# ratio is draggable past 1.0. A landing may cost speed or cost nothing;
	# it must never be a source of it.
	var player := _player_stub()
	player.config.pawn.landing_speed_reduction = -5.0
	for height in [0.5, 2.5, 4.0, 9.0]:
		check(player.landing_keep_ratio(height, false) <= 1.0, \
			"a landing at %f m added speed" % height)
		check(player.landing_keep_ratio(height, true) <= 1.0, \
			"a rolled landing at %f m added speed" % height)
	player.free()
```

- [ ] **Step 3: 跑测试确认失败**

Run: `pwsh -File tools/run_tests.ps1`

Expected: FAIL —— `FallTracker` 未声明，`Player` 没有 `landing_tier` / `TIER_FREE`。

- [ ] **Step 4: 实现 `FallTracker`**

Create `scripts/player/fall_tracker.gd`:

```gdscript
class_name FallTracker
extends RefCounted

# Accumulated fall height since the last ground contact -- the quantity the
# original's landing system actually judges on (03 §3.1, 10.1 mechanic 5).
#
# WHY NOT velocity.y: 03 §3.5 traces an entire layer of community technique
# (ventkick, kickglitch, drop-roll, fall-break kick) to this being a
# RESETTABLE COUNTER rather than an instantaneous reading. Anything that
# produces a ground-contact event zeroes it, and that emergent behaviour is
# unreachable if the landing reads the current frame's vertical speed.
#
# Deliberately RefCounted and fed plain floats: it owns no node and does no
# queries, so it can be tested without a physics world.

var fall_height: float = 0.0

var _pawn: PawnConfig
var _falling: bool = false
var _apex_y: float = 0.0

func _init(pawn: PawnConfig) -> void:
	_pawn = pawn

func reset() -> void:
	fall_height = 0.0
	_falling = false

## `vertical_velocity` and `world_y` are read straight from the body. Arming
## on the velocity threshold rather than on "y decreased" is what reproduces
## EnterToFallingZSpeed: the first few centimetres of stepping off a kerb are
## deliberately not counted.
func update(_delta: float, vertical_velocity: float, world_y: float) -> void:
	if not _falling:
		if vertical_velocity > _pawn.enter_to_falling_z_speed:
			return
		_falling = true
		_apex_y = world_y
	# Track the APEX, not the arming point: a wall-jump chain keeps rising
	# after the counter has armed, and the drop that matters is measured from
	# the highest point actually reached.
	_apex_y = maxf(_apex_y, world_y)
	fall_height = maxf(fall_height, _apex_y - world_y)
```

- [ ] **Step 5: 在 `Player` 上实现四档判定**

在 `player.gd` 加：

```gdscript
## Landing tiers, from 03 §3.1's confirmed TdMove_Landing thresholds. Read as
## fall HEIGHTS -- the original's own parameters are heights, and converting
## them to impact speeds (which is what this project used to do) is what
## erased the free band.
enum { TIER_FREE, TIER_SOFT, TIER_ROLLABLE, TIER_HARD }

## Accumulated fall height since the last ground contact. Built in setup().
var fall_tracker: FallTracker

func landing_tier(fall_height: float) -> int:
	var pawn := config.pawn
	if fall_height < pawn.skill_roll_landing_height:
		return TIER_FREE
	if fall_height < pawn.soft_landing_height:
		return TIER_SOFT
	if fall_height < pawn.hard_landing_height:
		return TIER_ROLLABLE
	return TIER_HARD

## Fraction of horizontal speed a landing from `fall_height` keeps.
##
## Clamped to 1.0 at every exit: the F1 panel sizes each slider to three times
## its default, so landing_speed_reduction is draggable to a value that would
## otherwise make landing a source of free speed.
func landing_keep_ratio(fall_height: float, rolled: bool) -> float:
	var pawn := config.pawn
	var hard_keep: float = clampf(1.0 - pawn.landing_speed_reduction, 0.0, 1.0)
	match landing_tier(fall_height):
		TIER_FREE:
			# Genuinely free, not "nearly free". A flat jump peaks four
			# centimetres under this boundary, which is what lets the player
			# jump as often as they like without paying for it.
			return 1.0
		TIER_SOFT:
			# A roll cancels this band outright; without one it scales in from
			# nothing at the boundary to the hard ratio at the next one.
			if rolled:
				return 1.0
			var t: float = inverse_lerp(pawn.skill_roll_landing_height, \
				pawn.soft_landing_height, fall_height)
			return clampf(lerpf(1.0, hard_keep, clampf(t, 0.0, 1.0)), 0.0, 1.0)
		TIER_ROLLABLE:
			# Above the soft band a roll is a discount, never a cancellation:
			# the community reports ME1's skill roll bleeding speed of its own
			# whenever you keep moving forward out of it (03 §3.1). Unrolled,
			# the cost ramps continuously from nothing at the soft boundary to
			# the full hard ratio at the hard one; rolling pays 35% of
			# whatever that ramp asks for.
			var t2: float = clampf(inverse_lerp(pawn.soft_landing_height, \
				pawn.hard_landing_height, fall_height), 0.0, 1.0)
			var unrolled: float = lerpf(1.0, hard_keep, t2)
			return clampf(unrolled if not rolled else lerpf(1.0, unrolled, 0.35), 0.0, 1.0)
		_:
			return hard_keep
```

- [ ] **Step 6: 接线到 `Player` 与 `FallingMove`**

`player.setup()` 里建 `fall_tracker = FallTracker.new(config.pawn)`；`reset_state()` 里 `fall_tracker.reset()`。

`player._physics_process()` 在 `state_machine.physics_update` **之前**调用：

```gdscript
	# Before the moves run, so a move that lands this tick reads a counter
	# that already includes this tick's descent.
	fall_tracker.update(delta, velocity.y, global_position.y)
```

`set_grounded(true)` 里加 `fall_tracker.reset()`——**任何**触地事件归零，这一条就是 drop-roll 那类技巧的机制来源。

`falling_move.gd` 的 `_apply_landing_cost()` 改写：

```gdscript
## Landing bleeds horizontal speed according to which of the four confirmed
## tiers the ACCUMULATED FALL HEIGHT falls into -- never according to this
## frame's vertical speed. See Player.landing_keep_ratio().
func _apply_landing_cost(fall_height: float, rolled: bool) -> void:
	var keep: float = player.landing_keep_ratio(fall_height, rolled)
	player.velocity.x *= keep
	player.velocity.z *= keep
```

调用点改为：

```gdscript
	if player.is_on_floor():
		# Read BEFORE set_grounded(), which resets the counter.
		var fall_height: float = player.fall_tracker.fall_height
		var rolled: bool = player.consume_roll() \
			and fall_height >= config.pawn.skill_roll_landing_height
		player.last_landing_rolled = rolled
		player.set_grounded(true)
		player.notify_landed(impact_speed)
		_apply_landing_cost(fall_height, rolled)
		return WALKING
```

- [ ] **Step 7: 下蹲键改成单一缓冲 + 上下文解析**

05 §5.2 的确证表是「一个键、五个出口」，判据只有三个。把 `Player` 现有的 `_crouch_buffer_timer` 改名为 `_roll_buffer_timer`，窗口由 `crouch_buffer_time (0.15)` 换成 `roll_trigger_time (1.0)`，`consume_crouch()` 改名 `consume_roll()`。

`walking_move.gd` 的滑铲入口保持读同一个缓冲（`player.consume_roll()`），这样落地那一刻究竟出 Roll 还是 Slide，由 `fall_height` 是否达到 `skill_roll_landing_height` 决定，而不是由两套各自为政的判定决定。在 `walking_move.gd` 的滑铲分支上方写清这张表：

```gdscript
	# GBA_Crouch is one key with five outlets (05 §5.2, confirmed by in-game
	# measurement), and only three discriminators: airborne or touching down,
	# horizontal speed, accumulated fall height.
	#   airborne, speed >= 1.0        -> Coil          (OUT OF SCOPE, no such move)
	#   airborne, speed <  1.0        -> nothing
	#   touchdown, fall >= 2.0 m      -> Roll          (FallingMove, above)
	#   touchdown, fall <  2.0 m, moving -> Slide      (here)
	#   grounded, not moving          -> Crouch
	# There are no chords, no hold-versus-tap, no direction modifiers.
```

删掉 `PawnConfig.crouch_buffer_time`。

- [ ] **Step 8: 把跳跃改到确证值，并删掉旧的落地旋钮**

`PawnConfig`：`base_jump_z` 由 `6.3` 改为 **`5.6`**，doc comment 里删掉 “MIGRATION NOTE”，写明这是 02 §2.4 的游戏内实测结论。删除 `land_cost_speed_ref`、`land_speed_keep`、`roll_speed_keep`、`roll_min_fall_speed` 四个字段，以及 `Legacy` 分组里对应的注释行。

- [ ] **Step 9: 重新生成竞技场**

`tools/arena_builder.gd` 从跳跃弧推导练习区几何（间隙宽度、墙高、平台高度）。跳跃初速降低 11%、滞空缩短 11% 之后，旧几何会出现跳不过去的间隙。

Run: `.engine\Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tools/build_main_scene.gd`

⚠️ 生成器是**一次性脚手架**，会整个覆盖 `scenes/main.tscn`。本仓库的场景本来就全部由生成器产出、没有手工编辑（见 `docs/decisions-pending-your-review.md` 第 3 条），所以这次覆盖是安全的；但若届时工作区里有人手改过 main.tscn，先 `git diff scenes/main.tscn` 确认。

- [ ] **Step 10: 跑测试确认通过**

Run: `pwsh -File tools/run_tests.ps1`

Expected: PASS，`test_fall_tracker.gd  5 test(s)`、`test_landing_tiers.gd  6 test(s)`。

- [ ] **Step 11: 人工验证——这是全计划第一次真正的手感变化**

Run: `.engine\Godot_v4.7.1-stable_win64_console.exe --path .`

Expected:
1. **全速跑动中连续跳跃，速度不再逐跳衰减**——这是本 task 最重要的一条，之前每跳一次掉 31%。
2. 跳跃明显变「飘」：滞空由 1.575 s 降到 1.40 s，但高度由 2.48 m 降到 1.96 m，整体更贴地、更可控。
3. 从练习区的高台跳下（超过 2 m）仍然掉速；落地前按住 Shift 则不掉。
4. 练习区的间隙仍然跳得过去（Step 9 已按新弧线重生成）。

- [ ] **Step 12: 提交**

```bash
git add -A scripts scenes tests
git commit -F - <<'EOF'
fix(movement): judge landings on accumulated fall height, and fix the jump arc

These are one change, not three. base_jump_z was taking the value the
research explicitly rules out by in-game measurement (TdMove_Jump's 630
rather than TdPawn's confirmed 560), which put the jump apex at 2.48 m --
above the 2.0 m roll threshold. Against a landing penalty that ramped
continuously from zero, that meant every single flat jump bled 31% of
horizontal speed. At the confirmed 5.6 the apex is 1.96 m, four centimetres
under the threshold, which is where the original deliberately parks it.

The penalty itself now reads a resettable fall-height counter rather than the
current frame's vertical speed, and resolves into the four confirmed tiers
with a genuinely free band below 2 m. 03 §3.5 traces a whole layer of
community technique to this being a counter; none of it is reachable from an
instantaneous reading.

The crouch key collapses to one buffered press resolved by context, which is
what the original does with it -- the fall height decides roll versus slide,
instead of two separate checks deciding independently.

The arena is regenerated because its practice geometry is derived from the
jump arc.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
```

---

## Task 7: 接线速度能量（10.4 验收表第 1 条）

Task 5 造好的组件在此接上。这是全计划**手感变化最大**的一笔：地面最高速从「按住 W 立刻到 7.2」变成「要跑满 7 秒才到 7.2」。

**Files:**
- Modify: `scripts/player/player.gd`、`scripts/player/moves/walking_move.gd`、`scripts/player/moves/crouch_move.gd`、`scripts/player/config/pawn_config.gd`
- Test: `tests/test_speed_energy_wiring.gd`

**Interfaces:**
- Consumes: Task 5 的 `SpeedEnergy`
- Produces:
  - `Player.speed_energy: SpeedEnergy`
  - `Player.speed_cap() -> float`（= `speed_energy.cap()`，供 Move 与相机读）
  - `Player.ground_accelerate(wish_dir: Vector3, target_speed: float, delta: float) -> void`（签名不变）
  - `Player.air_accelerate(wish_dir: Vector3, delta: float) -> void`（签名不变，天花板改由 `speed_cap()` 决定）

- [ ] **Step 1: 写失败的测试**

Create `tests/test_speed_energy_wiring.gd`:

```gdscript
class_name TestSpeedEnergyWiring
extends TestCase

# Driven-state tests: a real player on a real floor, with input scripted
# rather than typed. Verifies that the curve actually governs ground speed --
# the component's own maths is already covered by test_speed_energy.gd.

func _world() -> Dictionary:
	var world := TestWorld.build(tree, MovementConfig.new())
	return world

func test_top_speed_is_not_reachable_in_one_second() -> void:
	# The first judgement criterion in the research's own checklist: if
	# holding forward for two seconds reaches full speed, it is not this game,
	# because speed stops being an asset that can be lost.
	var world := _world()
	await step(1)
	TestWorld.place(world)
	await step(2)
	world["input"].state.move = Vector2(0.0, 1.0)
	for i in 60:
		await step(1)
	var speed: float = world["player"].horizontal_speed()
	check(speed < 5.4, "one second of running already reached %f m/s" % speed)
	check_greater(speed, 4.5, "one second of running did not even reach the 1.0 s knot")
	TestWorld.teardown(world)
	await step(1)

func test_seven_seconds_of_running_reaches_the_confirmed_top_speed() -> void:
	var world := _world()
	await step(1)
	TestWorld.place(world)
	await step(2)
	world["input"].state.move = Vector2(0.0, 1.0)
	for i in 430:
		await step(1)
	check_approx(world["player"].horizontal_speed(), 7.2, 0.15, "did not reach 7.2 m/s")
	TestWorld.teardown(world)
	await step(1)

func test_stopping_bleeds_the_energy_back_off() -> void:
	var world := _world()
	await step(1)
	TestWorld.place(world)
	await step(2)
	world["input"].state.move = Vector2(0.0, 1.0)
	for i in 430:
		await step(1)
	var banked: float = world["player"].speed_energy.energy
	check_greater(banked, 6.5, "never banked a full budget")
	world["input"].state.move = Vector2.ZERO
	for i in 120:
		await step(1)
	check(world["player"].speed_energy.energy < banked * 0.5, "energy survived two seconds of standing still")
	TestWorld.teardown(world)
	await step(1)

func test_the_walk_modifier_caps_speed_and_banks_almost_nothing() -> void:
	var world := _world()
	await step(1)
	TestWorld.place(world)
	await step(2)
	world["input"].state.move = Vector2(0.0, 1.0)
	world["input"].state.walk_held = true
	for i in 180:
		await step(1)
	check(world["player"].horizontal_speed() < 0.8, "the walk modifier did not cap speed")
	TestWorld.teardown(world)
	await step(1)

func test_energy_does_not_accumulate_while_shoved_against_a_wall() -> void:
	# The project-added guard: without it, holding forward into geometry for
	# seven seconds banks a full budget and hands it over the instant the
	# obstruction clears.
	var world := _world()
	await step(1)
	TestWorld.place(world)
	await step(2)
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10.0, 4.0, 1.0)
	shape.shape = box
	wall.add_child(shape)
	tree.root.add_child(wall)
	await step(1)
	wall.global_position = Vector3(0.0, 2.0, -1.5)
	world["input"].state.move = Vector2(0.0, 1.0)
	for i in 300:
		await step(1)
	check(world["player"].speed_energy.energy < 1.0, "banked energy while going nowhere")
	wall.queue_free()
	TestWorld.teardown(world)
	await step(1)
```

- [ ] **Step 2: 跑测试确认失败**

Run: `pwsh -File tools/run_tests.ps1`

Expected: FAIL —— `Player` 没有 `speed_energy`；且前两个用例会失败，因为当前一秒内就到 7.2。

- [ ] **Step 3: 在 `Player` 上建能量并每 tick 驱动它**

`setup()` 里 `speed_energy = SpeedEnergy.new(config.pawn)`；`reset_state()` 里 `speed_energy.reset()`。

```gdscript
## The current ground speed ceiling. Every move that wants "top speed" asks
## here rather than reading pawn.ground_speed, which is now only the curve's
## own upper bound rather than a target anything reaches directly.
func speed_cap() -> float:
	return speed_energy.cap()

## Which accumulation factor this tick's input asks for. The original
## declares three (02 §2.1) and this is the reading that makes all three
## usable: ordinary running is the sprint factor (there is no sprint key --
## the curve IS the sprint), the walk modifier drops to the walk factor, and
## a mostly-lateral input takes the strafe factor.
func _energy_mode(input: MoveInput) -> int:
	if input.walk_held:
		return SpeedEnergy.WALK
	if absf(input.move.x) > absf(input.move.y):
		return SpeedEnergy.STRAFE
	return SpeedEnergy.SPRINT

## Energy accrues only while GROUNDED, actually asking to move, and actually
## travelling near the ceiling that energy has already bought. Held (neither
## banked nor bled) while airborne: 10.1 mechanic 2 is explicit that speed
## earned before take-off is carried across the jump intact, and bleeding the
## energy that BOUGHT that speed mid-flight would contradict it.
func _update_speed_energy(delta: float, input: MoveInput) -> void:
	if not grounded:
		return
	var wish := wish_direction(input)
	if wish == Vector3.ZERO:
		speed_energy.decay(delta)
		return
	if horizontal_speed() >= speed_cap() * config.pawn.energy_accumulate_speed_ratio:
		speed_energy.accumulate(delta, _energy_mode(input))
	else:
		# Asking to move but not actually getting anywhere -- shoved into
		# geometry, or still climbing toward a ceiling already paid for.
		# Neither banks anything; neither is a reason to bleed, either.
		pass
```

在 `_physics_process()` 里、`move_manager.physics_update()` **之后**调用 `_update_speed_energy(delta, input)`——`grounded` 与 `horizontal_speed()` 都要读本 tick 的结果。

- [ ] **Step 4: 让地面移动向能量要上限**

`walking_move.gd`：

```gdscript
	# No sprint key: the curve IS the sprint (02 §2.1). The walk modifier is
	# the one thing that overrides it, with its own confirmed hard cap.
	var target_speed: float = config.pawn.walk_velocity if input.walk_held \
		else player.speed_cap() * cfg.speed_modifier
```

`crouch_move.gd`：`config.pawn.ground_speed * config.crouch.speed_modifier` → `player.speed_cap() * cfg.speed_modifier`。

`player.air_accelerate()` 里 `maxf(config.pawn.ground_speed, speed_along_wish)` → `maxf(speed_cap(), speed_along_wish)`，并更新那段长注释里对 `ground_speed` 的引用。

- [ ] **Step 5: 修正加速度、去掉空中减速守卫、接上 `jump_add_xy`**

`PawnConfig`：`accel_rate` 由 `60.0` 改为 **`61.44`**（确证值 `AccelRate = 6144`），删掉迁移注记。删除 `air_accel` 字段。

`player.air_accelerate()` 里改为按确证语义推导：

```gdscript
	# AirControl is a MULTIPLIER on ground acceleration (09 §9.1), not an
	# acceleration in its own right: 61.44 * 0.025 = 1.536 m/s^2.
	var air_accel: float = config.pawn.accel_rate * config.pawn.air_control
```

**删掉幅值守卫**（原 `if candidate.length() < horizontal.length(): return` 那三行及其上方注释）。改为在函数头注释里记录这次逆转：

```gdscript
## Air movement, the original's way: a Quake-style projection scaled by
## air_control.
##
## An earlier version of this project forbade the projection from ever
## reducing horizontal speed, so holding the opposite key in mid-air did
## nothing at all. That guard is gone: the original uses ordinary low air
## control, and "commit to the jump you made" comes from air_control being
## 0.025 -- half the engine's own default -- not from a special rule. At
## 1.536 m/s^2 a full 1.40 s hang time can shed at most ~2.1 m/s even if the
## player holds backward the whole way, which is a correction, not a brake.
```

`walking_move.gd` 与 `slide_move.gd` 的起跳分支加上确证的起跳前冲：

```gdscript
		# Source: 02 §2.4 `JumpAddXY = 100` uu/s. ⚠️ Inferred as an ADDITION
		# along the facing at take-off (whether it adds or sets a minimum is
		# unverified); taking off is itself a small forward commitment.
		var facing: Vector3 = -player.global_transform.basis.z
		player.velocity.x += facing.x * config.pawn.jump_add_xy
		player.velocity.z += facing.z * config.pawn.jump_add_xy
```

- [ ] **Step 6: 跑测试确认通过**

Run: `pwsh -File tools/run_tests.ps1`

Expected: PASS，`test_speed_energy_wiring.gd  5 test(s)`。

- [ ] **Step 7: 人工验证**

Run: `.engine\Godot_v4.7.1-stable_win64_console.exe --path .`

Expected：起步 0.4 秒内很跟手地冲到约 4 m/s，之后**明显变难**，要持续跑很久才逼近 7.2；停下两秒再起步，又要重新爬。按 F1 把 `pawn.speed_curve_interp_mode` 切到 1（SMOOTH）再跑一遍，感受起跑那 0.4 秒是否更顺、拐点是否像「换挡」——**这一条正是这个开关存在的理由，请给出你的判断**。

- [ ] **Step 8: 提交**

```bash
git add -A scripts tests
git commit -F - <<'EOF'
feat(movement): make ground speed the ceiling of a curve, not a constant

Holding forward now climbs a seven-second curve instead of snapping to top
speed, which is the first item on the research's own checklist and the
premise every loss mechanism depends on: nothing else in the rebuild means
anything if speed cannot be lost.

accel_rate goes to the confirmed 61.44 and air acceleration is derived from
it rather than stored separately, since AirControl is documented as a
multiplier on ground acceleration. The guard that forbade air control from
ever reducing speed is removed: the original commits you to a jump through
air_control being 0.025, not through a special rule, and at that value a full
hang time sheds at most ~2.1 m/s anyway.

Energy holds rather than bleeds while airborne, so speed earned before
take-off survives the flight intact.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
```

---

## Task 8: 转向损速（10.4 验收表第 3 条）

10.1 ③ 把「转向连续损速、没有免费额度」列为本质机制。这是原版技巧深度的重要一半，也是 Catalyst 丢掉后被社区形容成「像 UFO」的那一条。

**Files:**
- Modify: `scripts/player/player.gd`
- Test: `tests/test_turn_deceleration.gd`

**Interfaces:**
- Consumes: Task 5 的 `SpeedEnergy.spend_turn()`、Task 7 的 `Player._update_speed_energy()`
- Produces: 无新公开接口（`Player._last_wish_dir: Vector3` 为私有）

- [ ] **Step 1: 写失败的测试**

Create `tests/test_turn_deceleration.gd`:

```gdscript
class_name TestTurnDeceleration
extends TestCase

func _world() -> Dictionary:
	return TestWorld.build(tree, MovementConfig.new())

func _run_up(world: Dictionary, ticks: int) -> void:
	world["input"].state.move = Vector2(0.0, 1.0)
	for i in ticks:
		await step(1)

func test_turning_costs_banked_speed_energy() -> void:
	var world := _world()
	await step(1)
	TestWorld.place(world)
	await step(2)
	await _run_up(world, 430)
	var before: float = world["player"].speed_energy.energy
	check_greater(before, 6.5, "never banked a full budget")
	# A hard left: the wish direction swings 90 degrees in one tick.
	world["input"].state.move = Vector2(-1.0, 0.0)
	await step(1)
	var after: float = world["player"].speed_energy.energy
	check(after < before - 3.0, "a 90 degree turn cost almost nothing (%f -> %f)" % [before, after])
	TestWorld.teardown(world)
	await step(1)

func test_running_straight_costs_nothing() -> void:
	var world := _world()
	await step(1)
	TestWorld.place(world)
	await step(2)
	await _run_up(world, 430)
	var before: float = world["player"].speed_energy.energy
	for i in 60:
		await step(1)
	check_greater(world["player"].speed_energy.energy, before - 0.01, \
		"running in a straight line bled energy")
	TestWorld.teardown(world)
	await step(1)

func test_releasing_and_repressing_a_direction_is_not_a_turn() -> void:
	# wish_direction() returns the zero vector with no input. Treating the
	# transition through zero as a heading change would charge the player for
	# every momentary key release.
	var world := _world()
	await step(1)
	TestWorld.place(world)
	await step(2)
	await _run_up(world, 430)
	var before: float = world["player"].speed_energy.energy
	world["input"].state.move = Vector2.ZERO
	await step(1)
	world["input"].state.move = Vector2(0.0, 1.0)
	await step(1)
	# One tick of no input does bleed a little through ordinary decay, but it
	# must be nothing like a turn's own cost.
	check_greater(world["player"].speed_energy.energy, before - 0.5, \
		"passing through zero input was charged as a turn")
	TestWorld.teardown(world)
	await step(1)

func test_turning_in_the_air_is_free() -> void:
	# Turn cost is a ground mechanic: air_control is 0.025, so there is barely
	# any turning to charge for, and charging for it would double-punish a
	# jump the player is already committed to.
	var world := _world()
	await step(1)
	TestWorld.place(world)
	await step(2)
	await _run_up(world, 430)
	world["input"].press_jump()
	await step(1)
	world["input"].release_jump()
	for i in 10:
		await step(1)
	var before: float = world["player"].speed_energy.energy
	world["input"].state.move = Vector2(-1.0, 0.0)
	for i in 10:
		await step(1)
	check_approx(world["player"].speed_energy.energy, before, 0.01, "turning in the air cost energy")
	TestWorld.teardown(world)
	await step(1)
```

- [ ] **Step 2: 跑测试确认失败**

Run: `pwsh -File tools/run_tests.ps1`

Expected: FAIL —— 第一个用例失败（转向目前完全免费）。

- [ ] **Step 3: 实现**

`player.gd` 加一个私有字段与一段计费逻辑，接进 Task 7 建好的 `_update_speed_energy()`：

```gdscript
## Last tick's wish direction, for charging heading changes. Zero means "no
## input last tick", which is deliberately NOT a heading -- see
## _charge_turn().
var _last_wish_dir: Vector3 = Vector3.ZERO

## Turning is a continuous tax with no free allowance (10.1 mechanic 3): the
## research searched for a "costs nothing below N degrees" parameter and
## found none anywhere in the game, which is what forces players to plan a
## line instead of improvising one.
##
## Charged on the WISH direction, not the camera yaw and not the velocity
## direction. Not the camera, because turning your head to read the route
## ahead should be free -- it is turning the RUN that costs. Not the velocity
## either, because accel_rate 61.44 makes the velocity lag the intent, which
## would smear the charge across the frames after the decision instead of
## billing the decision itself.
func _charge_turn(wish: Vector3) -> void:
	if wish == Vector3.ZERO or _last_wish_dir == Vector3.ZERO:
		# Nothing to compare against. A momentary key release passes through
		# zero, and billing that transition would charge for letting go.
		_last_wish_dir = wish
		return
	var radians: float = absf(_last_wish_dir.signed_angle_to(wish, Vector3.UP))
	if radians > 0.0:
		speed_energy.spend_turn(radians)
	_last_wish_dir = wish
```

在 `_update_speed_energy()` 里，**只在 grounded 分支内**调用：

```gdscript
func _update_speed_energy(delta: float, input: MoveInput) -> void:
	var wish := wish_direction(input)
	if not grounded:
		# Neither banked, bled, nor charged for turning while airborne.
		_last_wish_dir = wish
		return
	_charge_turn(wish)
	if wish == Vector3.ZERO:
		speed_energy.decay(delta)
		return
	if horizontal_speed() >= speed_cap() * config.pawn.energy_accumulate_speed_ratio:
		speed_energy.accumulate(delta, _energy_mode(input))
```

`reset_state()` 里 `_last_wish_dir = Vector3.ZERO`。

- [ ] **Step 4: 跑测试确认通过**

Run: `pwsh -File tools/run_tests.ps1`

Expected: PASS，`test_turn_deceleration.gd  4 test(s)`。

- [ ] **Step 5: 人工验证**

Expected: 全速直线跑然后猛打方向，速度上限明显跌一档、且要花几秒重新爬回来；沿着大半径弧线跑则损失小得多。社区的「3-step Rule」（落地后先直行约三步再转向，否则掉速）应该能被观察到——落地惩罚与转向损速叠加正是这条经验规则的机制来源。

- [ ] **Step 6: 提交**

```bash
git add scripts/player/player.gd tests/test_turn_deceleration.gd
git commit -F - <<'EOF'
feat(movement): charge speed energy for every heading change

The research found no threshold parameter anywhere -- no "costs nothing below
N degrees" -- which makes turning a continuous tax rather than a gate, and is
what pushes the player into planning a line instead of improvising one. It is
also the half of the loss system this project had no equivalent of at all.

Billed on the wish direction: turning your head to read the route ahead is
free, turning the run is not. The original's own factor has an unrecoverable
unit, so the knob is calibrated to a stated behaviour instead -- a full
reversal spends the entire budget.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
```

---

## Task 9: 摩擦力倍率体系

把两个互不相干的绝对减速度（`base_friction` 走路用、`slide_friction` 滑铲用）换成原版的倍率链。这是「下坡是免费加速带、上坡是税」唯一能表达的形式，也是 Task 10 滑铲重做的前置。

**Files:**
- Create: `scripts/player/friction.gd`
- Modify: `scripts/player/player.gd`
- Test: `tests/test_friction.gd`

**Interfaces:**
- Consumes: `PawnConfig` 的 `Friction` 分组、`MoveConfig.friction_modifier`
- Produces: `Friction`（全静态工具类）
  - `static walk_friction(pawn: PawnConfig, move_modifier: float, grade: float) -> float`
  - `static slide_friction(pawn: PawnConfig, move_modifier: float, grade: float) -> float`
  - `grade` 约定：`+1` 正对下坡方向，`-1` 正对上坡，`0` 平地

- [ ] **Step 1: 写失败的测试**

Create `tests/test_friction.gd`:

```gdscript
class_name TestFriction
extends TestCase

# 03 §3.3's confirmed multiplier chain. All eight scales are confirmed
# values; base_friction is the one number with no counterpart in the original
# and is expected to move during playtest, so every assertion here is stated
# as a RELATION between outputs rather than as an absolute.

func test_flat_ground_applies_only_the_braking_strength() -> void:
	var pawn := PawnConfig.new()
	var flat := Friction.walk_friction(pawn, 1.0, 0.0)
	check_approx(flat, pawn.base_friction * pawn.braking_friction_strength, 0.0001, \
		"flat friction is not base * braking strength")

func test_walking_uphill_costs_more_than_downhill() -> void:
	var pawn := PawnConfig.new()
	check_greater(Friction.walk_friction(pawn, 1.0, -1.0), Friction.walk_friction(pawn, 1.0, 1.0), \
		"uphill walking is not more expensive than downhill")

func test_sliding_is_far_more_slope_sensitive_than_walking() -> void:
	# The whole reason the original feels the way it does on a ramp: walking's
	# spread is 1.1 vs 0.8, sliding's is 5.0 vs 1.8.
	var pawn := PawnConfig.new()
	var walk_spread := Friction.walk_friction(pawn, 1.0, -1.0) / Friction.walk_friction(pawn, 1.0, 1.0)
	var slide_spread := Friction.slide_friction(pawn, 1.0, -1.0) / Friction.slide_friction(pawn, 1.0, 1.0)
	check_greater(slide_spread, walk_spread * 2.0, "sliding is not markedly more slope-sensitive")

func test_a_moves_own_modifier_scales_the_result() -> void:
	var pawn := PawnConfig.new()
	var full := Friction.slide_friction(pawn, 1.0, 0.0)
	var tenth := Friction.slide_friction(pawn, 0.1, 0.0)
	check_approx(tenth, full * 0.1, 0.0001, "the move's friction_modifier did not scale the result")

func test_the_walk_clamp_bounds_the_slope_term_only() -> void:
	# MinWalkFrictionModify / MaxWalkFrictionModify are named for walking, and
	# sliding's own 5.0 scale sits above the 2.0 ceiling -- so the clamp must
	# not be applied to sliding or the steepest slide case would be silently
	# capped at less than half its intended friction.
	var pawn := PawnConfig.new()
	pawn.upward_walk_friction_scale = 99.0
	var clamped := Friction.walk_friction(pawn, 1.0, -1.0)
	check_approx(clamped, pawn.base_friction * pawn.max_walk_friction_modify \
		* pawn.braking_friction_strength, 0.0001, "the walk clamp did not bind")
	pawn.upward_slide_friction_scale = 5.0
	var slide_up := Friction.slide_friction(pawn, 1.0, -1.0)
	check_greater(slide_up, pawn.base_friction * pawn.max_walk_friction_modify, \
		"the walk clamp wrongly bound a slide")

func test_friction_is_never_negative() -> void:
	var pawn := PawnConfig.new()
	pawn.downward_slide_friction_scale = -3.0
	check_greater(Friction.slide_friction(pawn, 1.0, 1.0) + 0.0001, 0.0, "friction went negative")
```

- [ ] **Step 2: 跑测试确认失败**

Run: `pwsh -File tools/run_tests.ps1`

Expected: FAIL —— `Friction` 未声明。

- [ ] **Step 3: 实现**

Create `scripts/player/friction.gd`:

```gdscript
class_name Friction
extends RefCounted

# The original's friction model (03 §3.3): terrain grade modulates friction
# directly, and every move declares its own multiplier on top. This replaces
# two unrelated absolute decelerations -- one for walking, one for sliding --
# which between them could not express "downhill is a free acceleration lane
# and uphill is a tax" at all.
#
# `grade` is +1 pointing straight down the fall line, -1 straight up it, 0 on
# the flat -- i.e. the downhill component of the movement direction, which is
# exactly what SlideMove._slope_direction() already computes.
#
# All static: nothing here has state.

static func walk_friction(pawn: PawnConfig, move_modifier: float, grade: float) -> float:
	var scale: float = _grade_scale(grade, pawn.upward_walk_friction_scale, \
		pawn.downward_walk_friction_scale)
	# The clamp is named MinWalkFrictionModify / MaxWalkFrictionModify and is
	# applied ONLY here: sliding's own uphill scale (5.0) sits above the 2.0
	# ceiling, so applying it there would silently cap the steepest slide case
	# at less than half the friction the original gives it.
	scale = clampf(scale, pawn.min_walk_friction_modify, pawn.max_walk_friction_modify)
	return _compose(pawn, move_modifier, scale)

static func slide_friction(pawn: PawnConfig, move_modifier: float, grade: float) -> float:
	var scale: float = _grade_scale(grade, pawn.upward_slide_friction_scale, \
		pawn.downward_slide_friction_scale)
	return _compose(pawn, move_modifier, scale)

## Interpolates between the uphill and downhill scales by grade, holding 1.0
## on the flat so level ground reduces to plain base friction. Linear rather
## than a step, because the original's own walking pair (1.1 / 0.8) straddles
## 1.0 and a step would make a barely-tilted floor behave like a ramp.
static func _grade_scale(grade: float, uphill: float, downhill: float) -> float:
	var g: float = clampf(grade, -1.0, 1.0)
	if g >= 0.0:
		return lerpf(1.0, downhill, g)
	return lerpf(1.0, uphill, -g)

static func _compose(pawn: PawnConfig, move_modifier: float, scale: float) -> float:
	# TdPlayerPawn overrides BrakingFrictionStrength from 1.0 down to 0.5 --
	# the player is deliberately harder to stop than the AI, which is what
	# makes them "slide" a little into every direction change.
	return maxf(pawn.base_friction * scale * move_modifier * pawn.braking_friction_strength, 0.0)
```

- [ ] **Step 4: 让走路用上它**

`player.ground_accelerate()` 的刹车分支改为向 `Friction` 要值。签名加一个坡度参数，调用方 `walking_move.gd` / `crouch_move.gd` 传当前地面的下坡分量（`-player.get_floor_normal().y` 的方式与 `SlideMove._slope_direction()` 一致；无地面时传 0）：

```gdscript
## Ground movement: converge on the target velocity, and brake when idle.
## `grade` is the downhill component of the current heading (+1 straight
## down the fall line, -1 straight up, 0 flat); see Friction.
func ground_accelerate(wish_dir: Vector3, target_speed: float, delta: float, grade: float = 0.0) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if wish_dir == Vector3.ZERO:
		var braking: float = Friction.walk_friction(config.pawn, \
			move_manager.current_move_friction_modifier(), grade)
		horizontal = horizontal.move_toward(Vector3.ZERO, braking * delta)
	else:
		horizontal = horizontal.move_toward(wish_dir * target_speed, config.pawn.accel_rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
```

`MoveManager` 加一个取当前 move 摩擦倍率的小方法：

```gdscript
## The active move's own friction multiplier, or 1.0 when there is no move or
## no config. Read by Player.ground_accelerate() so braking respects whatever
## move is in force without Player having to know which one that is.
func current_move_friction_modifier() -> float:
	if _current == null:
		return 1.0
	var active: MoveConfig = _current.current_config()
	return active.friction_modifier if active != null else 1.0
```

- [ ] **Step 5: 跑测试确认通过**

Run: `pwsh -File tools/run_tests.ps1`

Expected: PASS，`test_friction.gd  6 test(s)`，其余套件不回归。

- [ ] **Step 6: 人工验证**

Expected: 平地松开方向键后的刹车比之前**慢一倍**（`braking_friction_strength = 0.5` 生效，玩家现在更难刹住车——这是原版刻意的）。上坡走比下坡走更「粘」。滑铲此时**还没**改（Task 10 才动），所以 ramp 上的滑铲行为暂时不变。

- [ ] **Step 7: 提交**

```bash
git add scripts/player/friction.gd scripts/player/player.gd scripts/player/moves/move_manager.gd tests/test_friction.gd
git commit -F - <<'EOF'
feat(movement): replace absolute decelerations with the multiplier chain

The original modulates friction by terrain grade and lets every move declare
its own multiplier on top. This project had two unrelated absolute
decelerations instead -- one for walking, one for sliding -- which between
them could not express "downhill is a free lane, uphill is a tax" at all, and
meant retuning ground friction did nothing to a slide.

The walk clamp is applied only to walking, deliberately: it is named for
walking, and sliding's own uphill scale sits above its ceiling, so clamping
there would silently halve the friction the steepest slide case is supposed
to get.

Braking strength drops to the player-specific 0.5, so stopping takes about
twice as long as it did -- the original makes the player harder to halt than
its own AI on purpose.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
```

---

## Task 10: 滑铲重做——从净收益变成净损失

所有者已拍板走原版：**滑铲没有任何加速项**，只是把摩擦降到 10% 来*保持*速度，且 2 秒硬性结束。社区共识是「它是游戏里最慢的动作」，逆向数据确认了——CDO 里根本没有加速参数。本项目原来的 `slide_boost = 2.5` 教给玩家的是「多滑」，原版教的是「别乱滑」。

**Files:**
- Modify: `scripts/player/config/moves/slide_config.gd`、`scripts/player/moves/slide_move.gd`、`scripts/player/moves/walking_move.gd`
- Test: `tests/test_slide.gd`

**Interfaces:**
- Consumes: Task 9 的 `Friction.slide_friction()`
- Produces: `SlideConfig` 新字段 `slide_abort_speed: float = 2.5`、`slide_abort_time: float = 2.0`、`max_floor_incline_z: float = 0.5`；删除 `slide_entry_speed`、`slide_boost`、`slide_boost_entry_threshold`、`slide_friction`、`slide_exit_speed`、`slide_max_duration`、`slide_slope_accel`、`slide_max_speed`

- [ ] **Step 1: 写失败的测试**

Create `tests/test_slide.gd`:

```gdscript
class_name TestSlide
extends TestCase

func _world() -> Dictionary:
	return TestWorld.build(tree, MovementConfig.new())

func _run_up(world: Dictionary, ticks: int) -> void:
	world["input"].state.move = Vector2(0.0, 1.0)
	for i in ticks:
		await step(1)

func test_entering_a_slide_never_adds_speed() -> void:
	# The single behavioural difference from this project's old slide, and the
	# one that changes what the whole level teaches: the original has no
	# acceleration term anywhere in TdMove_Slide.
	var world := _world()
	await step(1)
	TestWorld.place(world)
	await step(2)
	await _run_up(world, 200)
	var before: float = world["player"].horizontal_speed()
	world["input"].press_crouch()
	await step(1)
	await step(1)
	check(world["player"].horizontal_speed() <= before + 0.001, \
		"the slide added speed (%f -> %f)" % [before, world["player"].horizontal_speed()])
	TestWorld.teardown(world)
	await step(1)

func test_chaining_slides_cannot_ratchet_speed_upward() -> void:
	var world := _world()
	await step(1)
	TestWorld.place(world)
	await step(2)
	await _run_up(world, 200)
	var peak: float = world["player"].horizontal_speed()
	for cycle in 6:
		world["input"].press_crouch()
		for i in 20:
			await step(1)
		world["input"].release_crouch()
		for i in 20:
			await step(1)
		peak = maxf(peak, world["player"].horizontal_speed())
	check(peak <= world["player"].config.pawn.ground_speed + 0.01, \
		"chained slides climbed past the ground ceiling (%f)" % peak)
	TestWorld.teardown(world)
	await step(1)

func test_a_slide_ends_once_speed_decays_to_the_abort_speed() -> void:
	var world := _world()
	await step(1)
	TestWorld.place(world)
	await step(2)
	await _run_up(world, 200)
	world["input"].press_crouch()
	await step(1)
	world["input"].state.move = Vector2.ZERO
	for i in 240:
		await step(1)
	check(world["player"].move_manager.current_name != Move.SLIDE, \
		"the slide never ended")
	TestWorld.teardown(world)
	await step(1)

func test_a_slide_cannot_outlast_the_abort_time() -> void:
	var world := _world()
	await step(1)
	TestWorld.place(world)
	await step(2)
	await _run_up(world, 430)
	world["input"].press_crouch()
	await step(1)
	# SlideAbortTime = 2.0 s. Give it a generous margin and it must be gone.
	for i in 150:
		await step(1)
	check(world["player"].move_manager.current_name != Move.SLIDE, \
		"the slide outlasted SlideAbortTime")
	TestWorld.teardown(world)
	await step(1)

func test_the_slide_declares_the_confirmed_friction_multiplier() -> void:
	var config := MovementConfig.new()
	check_approx(config.slide.friction_modifier, 0.1, 0.0001, \
		"slide friction_modifier is not the confirmed 0.1")
```

- [ ] **Step 2: 跑测试确认失败**

Run: `pwsh -File tools/run_tests.ps1`

Expected: FAIL —— 第一、二个用例失败（入场 boost 仍在），第五个失败（`friction_modifier` 仍是 1.0）。

- [ ] **Step 3: 改 `SlideConfig`**

```gdscript
class_name SlideConfig
extends MoveConfig

## Source: 05 §5.1 `SlideAbortSpeed = 250` uu/s. ✅ Below this a slide ends.
## Also serves as the ENTRY gate: entering under it would abort on the very
## next tick anyway, so the original needs no separate minimum and neither do
## we (the old `slide_entry_speed = 4.0` was this project's own invention).
@export var slide_abort_speed: float = 2.5
## Source: 05 §5.1 `SlideAbortTime = 2.0` s. ✅
@export var slide_abort_time: float = 2.0
## Source: 05 §5.1 `MaxFloorInclineZ = 0.5`. ✅ Steeper than ~60 degrees and
## the surface cannot be slid on at all.
@export var max_floor_incline_z: float = 0.5
## Project-specific, no counterpart in the original: the capsule size and how
## fast the line can be steered.
@export var slide_capsule_height: float = 0.9
@export var slide_steer_rate: float = 1.2
## Project-specific SAFETY VALVE, not a feel knob. A slide that stops under a
## ceiling too low to stand up in has no exit at all -- every route back is
## gated on headroom and nothing in this move generates speed. The original
## has other outlets (LayOnGround and friends) that this project does not.
@export var slide_crawl_speed: float = 2.5

func _init() -> void:
	# Source: 05 §5.1 `FrictionModifier = 0.1`. ✅ The whole of what a slide
	# does to speed: it PRESERVES it by cutting friction to a tenth. There is
	# no acceleration term anywhere in TdMove_Slide, which is why the
	# community calls it the slowest move in the game.
	friction_modifier = 0.1
	# Source: 05 §5.1 `MinLookConstraint = (-10000, -10000, 0)`, UE3 integer
	# angles at 65536 = 360 degrees -> +-54.9 degrees on pitch and yaw. ✅
	constrain_look = true
	min_look_constraint = Vector3(-deg_to_rad(54.9), -deg_to_rad(54.9), -PI)
	max_look_constraint = Vector3(deg_to_rad(54.9), deg_to_rad(54.9), PI)
```

- [ ] **Step 4: 改 `SlideMove`**

`enter()`：删掉整段 boost 逻辑（`entry_speed` / `boosted` / 那两行速度写回），只保留方向捕获与 `set_capsule_height()`。

`_slide()`：删掉 `slide_slope_accel` / `slide_max_speed` 那套，改成向 `Friction` 要减速度：

```gdscript
	# Slope drives FRICTION, not acceleration (03 §3.3). Uphill multiplies it
	# by 5.0 -- an uphill slide stops almost immediately -- while downhill
	# drops it to 1.8x, which is what makes a descent one of the few places a
	# slide is genuinely worth doing. `grade` is +1 straight down the fall
	# line, matching Friction's own convention.
	var slope_dir := _slope_direction()
	var grade := -slope_dir.y
	var decel: float = Friction.slide_friction(config.pawn, cfg.friction_modifier, grade)
	speed = maxf(speed - decel * delta, 0.0)
```

注意：**下坡不再净加速**，只是掉得慢。原版下坡滑铲之所以快，是因为重力沿坡分量在 `move_and_slide()` 里自然作用；本实现沿坡驱动的写法已经保留了那一分量（`velocity = slope_dir * (speed / horizontal_len)`），所以不需要额外的加速项。

退出条件改名：`config.slide.slide_exit_speed` → `slide_abort_speed`，`slide_max_duration` → `slide_abort_time`。

`walking_move.gd` 的滑铲入口：`config.slide.slide_entry_speed` → `config.slide.slide_abort_speed`。

- [ ] **Step 5: 跑测试确认通过**

Run: `pwsh -File tools/run_tests.ps1`

Expected: PASS，`test_slide.gd  5 test(s)`。

- [ ] **Step 6: 人工验证**

Expected: 滑铲不再有入场爆发，纯粹是「保住已有速度并压低身形」。练习区那条 16.7° 下坡滑起来仍然明显比平地快、比走路快；试着从坡底往上滑，应该几乎**立刻停死**（5 倍摩擦）。平地上反复点 Shift 不再能越滑越快。

- [ ] **Step 7: 提交**

```bash
git add -A scripts tests
git commit -F - <<'EOF'
feat(slide): make sliding preserve speed instead of creating it

TdMove_Slide has no acceleration term at all -- it cuts friction to a tenth
and aborts after two seconds, which is why the community calls it the slowest
move in the game and why the only places it pays are kicking doors and low
ducts. This project's slide handed out a one-off boost, so the level taught
"slide constantly" where the original teaches "don't".

Slope now drives friction rather than acceleration, which is what makes the
5.0-versus-1.8 uphill/downhill spread expressible: an uphill slide stops
almost on the spot, a downhill one carries. The old slope acceleration and
its companion speed rail both go away, since friction can no longer produce
unbounded speed for a rail to catch.

Entry keys off SlideAbortSpeed instead of an invented minimum: entering below
the abort speed would abort on the next tick anyway.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
```

---

## Task 11: 墙跑重做——时长由动量决定，不由计时器决定

原版**没有最长持续时间参数**。wallrun 靠速度衰减自然结束：跑得越快贴得越久。硬时限则让速度在墙上不产生任何回报，怎么调都不对。同时补上原版有而本项目完全没有的**入射角判定**。

**Files:**
- Modify: `scripts/player/config/moves/wall_run_config.gd`、`scripts/player/moves/wall_run_move.gd`、`scripts/player/moves/falling_move.gd`、`scripts/player/player.gd`、`scripts/player/probes.gd`
- Test: `tests/test_wall_run_entry.gd`

**Interfaces:**
- Consumes: Task 4 的 `MoveManager.can_enter()`
- Produces:
  - `WallRunConfig` 全字段改为原版名（见 spec §4.3 的表）
  - `Probes.wall_query()` 的返回字典增加 `"incidence"`（入射角，弧度）
  - `Player` 删除 `note_wall_detach()`、`can_attach_wall()`、`_recent_walls`、`MAX_RECENT_WALLS`

- [ ] **Step 1: 写失败的测试**

Create `tests/test_wall_run_entry.gd`。用 `TestWorld` 建墙、脚本化输入，覆盖三条：

```gdscript
class_name TestWallRunEntry
extends TestCase

func _world_with_wall(wall_yaw: float) -> Dictionary:
	var world := TestWorld.build(tree, MovementConfig.new())
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, 6.0, 1.0)
	shape.shape = box
	wall.add_child(shape)
	tree.root.add_child(wall)
	world["wall"] = wall
	world["wall_yaw"] = wall_yaw
	return world

func test_a_wall_run_has_no_duration_cap() -> void:
	# The original has no such parameter: TdMove_WallRun's own listing has
	# entry conditions, friction, acceleration and deceleration, and no time
	# limit anywhere. Duration is momentum's business.
	var config := MovementConfig.new()
	for property in config.wall_run.get_property_list():
		check(not String(property.name).contains("duration"), \
			"a duration cap survived on WallRunConfig: %s" % property.name)

func test_the_confirmed_entry_thresholds_are_in_place() -> void:
	var config := MovementConfig.new()
	check_approx(config.wall_run.wall_running_min_speed, 2.0, 0.0001, "min speed is not 200 uu/s")
	check_approx(config.wall_run.wall_running_forward_max_start_angle, deg_to_rad(57.0), 0.001, \
		"forward entry angle is not 57 degrees")
	check_approx(config.wall_run.wall_running_strafe_start_angle, deg_to_rad(60.0), 0.001, \
		"strafe entry angle is not 60 degrees")
	check_approx(config.wall_run.redo_move_time, 0.15, 0.0001, "RedoMoveTime is not 0.15")
	check_approx(config.wall_run.wall_running_horisontal_friction, 0.05, 0.0001, \
		"wall friction is not 0.05")

func test_a_faster_entry_stays_on_the_wall_longer() -> void:
	# The whole point of removing the timer: speed has to buy something on the
	# wall, and duration is what it buys.
	var slow := await _measure_wall_ticks(4.0)
	var fast := await _measure_wall_ticks(7.0)
	check_greater(fast, slow, "a faster entry did not last longer (%d vs %d ticks)" % [fast, slow])

## Drives a player into a wall at `entry_speed` and returns how many ticks the
## wall run lasted. Implemented with a direct velocity assignment rather than
## by running the speed curve up first, so the two cases differ ONLY in entry
## speed.
func _measure_wall_ticks(entry_speed: float) -> int:
	var world := _world_with_wall(0.0)
	await step(1)
	TestWorld.place(world)
	world["wall"].global_position = Vector3(1.2, 3.0, 0.0)
	world["wall"].rotation = Vector3(0.0, PI * 0.5, 0.0)
	await step(2)
	var player: Player = world["player"]
	player.velocity = Vector3(0.0, 0.0, -entry_speed)
	var ticks := 0
	for i in 400:
		await step(1)
		if player.move_manager.current_name == Move.WALL_RUN:
			ticks += 1
		elif ticks > 0:
			break
	world["wall"].queue_free()
	TestWorld.teardown(world)
	await step(1)
	return ticks
```

⚠️ 最后一个用例依赖真实几何，第一次跑通前可能要微调墙的位置/朝向。**若两次测得的 tick 数都为 0，先排查几何而不是改断言**——把墙挪到玩家侧方 `wall_reach` 以内是关键。

- [ ] **Step 2: 跑测试确认失败**

Run: `pwsh -File tools/run_tests.ps1`

Expected: FAIL —— `wall_max_duration` 仍在、新字段不存在。

- [ ] **Step 3: 改写 `WallRunConfig`**

按 spec §4.3 的表逐字段写入（全部 ✅ 确证，每条带原始 uu 值）：`wall_running_min_speed 2.0`、`wall_running_velocity_start_limit 3.0`、`wall_running_min_wall_height 1.92`、`wall_running_forward_max_start_angle deg_to_rad(57)`、`wall_running_strafe_start_angle deg_to_rad(60)`、`wall_running_forward_check_distance 0.5`、`wall_running_strafe_check_distance 0.5`、`wall_running_horisontal_friction 0.05`、`wall_running_horisontal_acceleration 8.2`、`wall_running_horisontal_deceleration 5.0`、`wall_running_horisontal_initial_z_height 1.7`、`wall_running_horisontal_align_speed 7.0`、`wall_running_velocity_stop_limit -5.0`、`rotate_pawn_along_wall_time 0.4`、`time_to_do_90_turn 0.25`；保留项目专有的 `wall_gravity_scale 0.35`、`wall_stick_force 0.5`（标注⚠️模型不同）。

`_init()` 里：

```gdscript
func _init() -> void:
	# Source: 04 §4.1 `RedoMoveTime = 0.15`. ✅ Far shorter than the 0.5 s
	# same-wall cooldown this project invented, because the original does not
	# need a cooldown to stop an endless climb -- a wall run does not lift you
	# at all, it only slows your descent, and every wall jump's own rise is
	# bounded by JumpOffZHeight.
	redo_move_time = 0.15
	friction_modifier = 0.05
	# Source: 04 §4.1 `MinLookConstraint = (-13000, -16384, -32768)` /
	# `MaxLookConstraint` mirrored, at 65536 = 360 degrees -> pitch +-71.4,
	# yaw +-90. ✅ With bUseAbsoluteYawConstraint = True. This is where "the
	# view swings to face along the wall" comes from -- an input constraint,
	# not an animation.
	constrain_look = true
	absolute_yaw_constraint = true
	min_look_constraint = Vector3(-deg_to_rad(71.4), -deg_to_rad(90.0), -PI)
	max_look_constraint = Vector3(deg_to_rad(71.4), deg_to_rad(90.0), PI)
```

- [ ] **Step 4: 让 `Probes.wall_query()` 报告入射角**

返回字典加一项：

```gdscript
## Angle between the player's heading and the wall PLANE, in radians. 0 means
## running straight at the wall, PI/2 means running exactly parallel to it.
## Source: 04 §4.1 -- the original branches on this hard (0-57 degrees takes
## the forward branch, 60+ takes the strafe branch; the three-degree gap
## between them is a deliberate hysteresis band that keeps a borderline
## approach from flickering).
"incidence": incidence,
```

计算：`incidence = abs(asin(clamp(heading.dot(normal), -1, 1)))`——`normal` 指离墙、`heading` 为水平单位速度方向；正对墙时 `dot ≈ -1` → `asin` 绝对值 ≈ π/2 …… ⚠️ **实现时先在一个临时脚本里验一遍符号与取值范围**，不要照着这行注释想当然。目标语义是「正对墙 = 0，平行 = π/2」。

- [ ] **Step 5: 改 `WallRunMove` 的进入、维持与退出**

进入（在 `falling_move.gd` 里）：把速度门槛由 `wall_min_speed(5.0)` 换成 `wall_running_min_speed(2.0)`，并加入射角判定——超过 `wall_running_strafe_start_angle` 走 strafe 分支，低于 `wall_running_forward_max_start_angle` 走 forward 分支，落在 57°–60° 之间则**保持当前状态**（迟滞带）。用 `player.move_manager.can_enter(Move.WALL_RUN)` 取代原来的 `player.can_attach_wall(normal)`。

`enter()` 里加一次性抬升：

```gdscript
	# Source: 04 §4.1 `WallRunningHorisontalInitialZHeight = 170` uu. ⚠️ Read
	# as a one-off lift on attaching, expressed as the vertical speed that
	# reaches that height under plain gravity.
	var lift: float = cfg.wall_running_horisontal_initial_z_height
	if lift > 0.0:
		player.velocity.y = maxf(player.velocity.y, sqrt(2.0 * config.pawn.gravity * lift))
```

维持：沿墙加速用 `wall_running_horisontal_acceleration`，并**每 tick 施加 `wall_running_horisontal_deceleration`**——这才是让墙跑自然结束的力。删掉 `wall_max_speed` 的钳制（速度上限交给能量曲线）。

退出：删掉 `_elapsed >= wall_max_duration` 分支，改为

```gdscript
	# No timer. The original ends a wall run by momentum alone -- friction is
	# only 0.05 but deceleration works on it every tick, so a faster entry
	# simply lasts longer. That is what makes speed pay off on a wall.
	if Vector2(player.velocity.x, player.velocity.z).length() < cfg.wall_running_min_speed:
		return FALLING
	if player.velocity.y < cfg.wall_running_velocity_stop_limit:
		return FALLING
```

- [ ] **Step 6: 删掉自创的两道护栏**

删除 `WallRunMove._height_ceiling()` 整个方法及其两个调用点（连跳限高）；删除 `Player._recent_walls`、`MAX_RECENT_WALLS`、`note_wall_detach()`、`can_attach_wall()`，以及 `PawnConfig.wall_reattach_cooldown` / `wall_same_normal_dot`；`reset_state()` 里对 `_recent_walls` 的清理一并删掉。

⚠️ **这是 spec §8 记录的已知风险**：zig-zag 双墙连跳可能变成无限爬升。**先按 1:1 做、不预先加护栏**——Step 8 的人工验证要专门试这个。

- [ ] **Step 7: 跑测试确认通过**

Run: `pwsh -File tools/run_tests.ps1`

Expected: PASS，`test_wall_run_entry.gd  3 test(s)`。

- [ ] **Step 8: 人工验证（含风险探查）**

Expected:
1. 低速（约 2–3 m/s）现在也能贴墙，之前要 5.0。
2. 高速贴墙明显比低速贴得久——**这是本 task 的核心观感**。
3. 正对墙冲过去不再触发横向墙跑（入射角判定生效）。
4. **专门试**：在练习区的 ZigLeft/ZigRight 双墙之间反复连跳，看能不能一直爬上去。若能，记录到 spec §8 下方，作为下一轮要补护栏的依据；**本 task 不修**。

- [ ] **Step 9: 提交**

```bash
git add -A scripts tests
git commit -F - <<'EOF'
feat(wall-run): let momentum decide how long a wall run lasts

TdMove_WallRun has no duration parameter. It ends when velocity decays past
its stop limit, which means a faster entry simply lasts longer -- speed buys
something on the wall. A hard 1.5 s timer gave speed no return there at all,
so no amount of tuning could make it feel right.

Entry now branches on incidence angle the way the original does (0-57 forward,
60+ strafe, with the three-degree gap between them left as the hysteresis band
it evidently is), and the minimum entry speed drops to the confirmed 2.0 m/s.

The same-wall cooldown and the chained-climb height governor are gone, both
project inventions. The original bounds a climb through each jump's own
JumpOffZHeight instead, and its RedoMoveTime is only 0.15 s. This is a known
risk -- see the spec's own risk section -- and is deliberately shipped without
a replacement guard so playtesting can say whether one is needed.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
```

---

## Task 12: 墙跳的技巧梯度（研究的头号建议）

04.4 是整本手册最重要的单条发现：DICE 把 `Noob` / `ProAdd` 直接写进了参数名，推离速度是一个 **1.2 → 5.2 m/s 的 4.3 倍区间**。同一个按键、不同执行质量、天差地别的结果——不需要额外按键、不需要教学。这是「像不像镜之边缘」的最大单点杠杆。

**Files:**
- Modify: `scripts/player/config/moves/wallrun_jump_config.gd`、`scripts/player/moves/wall_run_move.gd`
- Test: `tests/test_wallrun_jump.gd`

**Interfaces:**
- Produces: `WallRunMove.wall_jump_push_away(look_forward: Vector3, wall_normal: Vector3) -> float`、`.wall_jump_rise_velocity(look_forward: Vector3, wall_normal: Vector3) -> float`（均为静态或纯函数，便于单测）

⚠️ **一处对 spec 的有意偏离**：spec §4.3 说把 WallrunJump 做成**独立注册的 Move**（原版 `TdMove_WallrunJump` 确实是独立类）。实现时不这么做——一个只活一 tick 的 Move 要么白白停顿一帧，要么把 `FallingMove` 的落地/探测逻辑整个抄一遍。改为：墙跳留在 `WallRunMove` 内，但**全部参数取自 `config.wallrun_jump`**，梯度计算拆成可单测的纯函数。Task 16 会据此更新 spec。

- [ ] **Step 1: 写失败的测试**

Create `tests/test_wallrun_jump.gd`:

```gdscript
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
```

- [ ] **Step 2: 跑测试确认失败**

Run: `pwsh -File tools/run_tests.ps1`

Expected: FAIL —— `WallRunMove` 没有这两个静态方法，配置字段也还是旧名。

- [ ] **Step 3: 改 `WallrunJumpConfig`**

```gdscript
class_name WallrunJumpConfig
extends MoveConfig

# Source: 04 §4.4 `TdMove_WallrunJump` CDO. ✅ ALL FOUR CONFIRMED.
#
# DICE wrote the skill gradient into the parameter names themselves -- Noob
# and ProAdd -- which is the single most important finding in the whole
# research: the same key produces a 4.3x spread depending on how well it is
# executed, with no extra input, no QTE and no tutorial. The community called
# this "wall boost" for years and never knew why it worked.

## `WallRunningPushAwaySpeedNoob = 120` uu/s -- worst execution.
@export var wall_running_push_away_speed_noob: float = 1.2
## `WallRunningPushAwaySpeedProAdd = 400` uu/s -- added on top at best
## execution, for 520 uu/s = 5.2 m/s total.
@export var wall_running_push_away_speed_pro_add: float = 4.0
## `WallRunningPushForwardSpeedMin = 0.1`. ✅
@export var wall_running_push_forward_speed_min: float = 0.1
## `WallRunningJumpOffZHeightForward = 100` uu -- a HEIGHT (1.0 m), converted
## to a launch speed at the point of use.
@export var wall_running_jump_off_z_height_forward: float = 1.0
## `WallRunningJumpOffZHeightMaxAddTurned = 60` uu -- up to 0.6 m more.
@export var wall_running_jump_off_z_height_max_add_turned: float = 0.6
```

- [ ] **Step 4: 实现梯度并接线**

在 `wall_run_move.gd` 加两个静态纯函数：

```gdscript
## How squarely the view faces the wall at the moment of the jump, 0 (looking
## straight away) to 1 (looking straight into it).
##
## ⚠️ The interpolation input is NOT named in the original's data (04 §4.4).
## This reading comes from the community instruction the gradient has to
## reproduce -- "face the wall you are running on, without running into it,
## then jump, and you gain noticeably more speed" -- which no other candidate
## input explains.
static func wall_jump_quality(look_forward: Vector3, wall_normal: Vector3) -> float:
	var look := Vector3(look_forward.x, 0.0, look_forward.z)
	var normal := Vector3(wall_normal.x, 0.0, wall_normal.z)
	if look.length_squared() < 0.0001 or normal.length_squared() < 0.0001:
		return 0.0
	# The normal points AWAY from the wall, so facing INTO it is -1.
	return clampf((-look.normalized().dot(normal.normalized()) + 1.0) * 0.5, 0.0, 1.0)

static func wall_jump_push_away(look_forward: Vector3, wall_normal: Vector3, \
		cfg: WallrunJumpConfig) -> float:
	var quality := wall_jump_quality(look_forward, wall_normal)
	return cfg.wall_running_push_away_speed_noob \
		+ cfg.wall_running_push_away_speed_pro_add * quality

static func wall_jump_rise_velocity(look_forward: Vector3, wall_normal: Vector3, \
		cfg: WallrunJumpConfig, pawn: PawnConfig) -> float:
	var quality := wall_jump_quality(look_forward, wall_normal)
	var height: float = cfg.wall_running_jump_off_z_height_forward \
		+ cfg.wall_running_jump_off_z_height_max_add_turned * quality
	# JumpOffZHeight is a height, not a speed -- convert at the point of use.
	return sqrt(2.0 * maxf(pawn.gravity, 0.001) * maxf(height, 0.0))
```

墙跳分支改为：

```gdscript
	if player.consume_buffered_jump():
		var look: Vector3 = -player.global_transform.basis.z
		var jump_cfg: WallrunJumpConfig = config.wallrun_jump
		player.velocity.y = wall_jump_rise_velocity(look, _normal, jump_cfg, config.pawn)
		player.velocity += _normal * wall_jump_push_away(look, _normal, jump_cfg)
		player.move_and_slide()
		player.set_grounded(player.is_on_floor())
		return FALLING
```

- [ ] **Step 5: 跑测试确认通过**

Run: `pwsh -File tools/run_tests.ps1`

Expected: PASS，`test_wallrun_jump.gd  6 test(s)`。

- [ ] **Step 6: 人工验证——这一条最值得亲自体会**

Expected: 贴墙跑时**扭头看向所贴的墙**再跳，弹离速度明显大得多；看着前方随便跳则弱得多。两者应该差出「一眼能看出来」的量级（4.3 倍）。垂直方向变弱了（由 6.5 降到 4.0–5.06 m/s），所以墙跳更像是「换方向 + 带走速度」而不是「上电梯」。

- [ ] **Step 7: 提交**

```bash
git add -A scripts tests
git commit -F - <<'EOF'
feat(wall-run): give the wall jump its Noob-to-Pro gradient

DICE wrote the skill gradient into the parameter names -- Noob 120, ProAdd
400 -- so the push away from a wall spans 1.2 to 5.2 m/s depending on how
squarely you were facing the wall when you jumped. The community called this
"wall boost" for years without knowing why it worked; it is not a bug, it is
the clearest single example of the design putting the skill ceiling inside
the move rather than behind an extra button.

A constant 6.0 push had no room for execution quality to mean anything, which
is what made this the research's own top recommendation.

The rise is now a height converted to a launch speed, as the original stores
it: 1.0 to 1.6 m, so 4.0 to 5.06 m/s rather than a flat 6.5. A wall jump
changes direction and carries speed; it is not an elevator.

The interpolation input is inferred -- see the note on wall_jump_quality().

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
```

---

## Task 13: 探针补齐 vault 变体表所需的两样信息

Task 14 的变体查表需要两样 `Probes` 现在拿不到的东西：**命中距离**（时间前瞻的分子）和**对面有没有落脚地**（`bCheckForVaultOver`，决定 onto 还是 over）。先把探针补好并单独测，再动状态逻辑。

**Files:**
- Modify: `scripts/player/probes.gd`、`tools/build_player_scene.gd`（新增一根 `VaultOverDown` 射线）
- Regenerate: `scenes/player/player.tscn`
- Test: `tests/test_probes_vault.gd`

**Interfaces:**
- Produces: `Probes.vault_query()` 返回字典新增
  - `"distance": float`——从玩家身体原点到障碍面的水平距离
  - `"height": float`——障碍顶相对脚底的高度（此前调用方要自己算）
  - `"vault_over": bool`——障碍对面 `vault_over_probe_distance` 处是否有可站立的地面

- [ ] **Step 1: 写失败的测试**

Create `tests/test_probes_vault.gd`。用 `TestWorld` 摆一个箱子在玩家正前方，覆盖四条：

```gdscript
class_name TestProbesVault
extends TestCase

func _world_with_box(size: Vector3, at: Vector3) -> Dictionary:
	var world := TestWorld.build(tree, MovementConfig.new())
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	tree.root.add_child(body)
	world["box"] = body
	world["box_at"] = at
	return world

func _place(world: Dictionary) -> void:
	TestWorld.place(world)
	world["box"].global_position = world["box_at"]

func test_a_hit_reports_the_obstacle_height_above_the_feet() -> void:
	var world := _world_with_box(Vector3(2.0, 1.0, 0.6), Vector3(0.0, 0.5, -1.0))
	await step(1)
	_place(world)
	await step(2)
	var hit: Dictionary = world["player"].probes.vault_query()
	check(hit["valid"], "the probe missed a waist-high box")
	check_approx(hit["height"], 1.0, 0.08, "reported height is not the box top above the feet")
	world["box"].queue_free()
	TestWorld.teardown(world)
	await step(1)

func test_a_hit_reports_how_far_ahead_the_obstacle_is() -> void:
	# The numerator of the time-to-obstacle lookahead. Without it the whole
	# variant table has nothing to divide by.
	var world := _world_with_box(Vector3(2.0, 1.0, 0.6), Vector3(0.0, 0.5, -1.1))
	await step(1)
	_place(world)
	await step(2)
	var hit: Dictionary = world["player"].probes.vault_query()
	check(hit["valid"], "the probe missed the box")
	check_greater(hit["distance"], 0.0, "distance was not reported")
	check(hit["distance"] < 1.5, "distance is implausibly large: %f" % hit["distance"])
	world["box"].queue_free()
	TestWorld.teardown(world)
	await step(1)

func test_a_thin_obstacle_reads_as_vaultable_over() -> void:
	var world := _world_with_box(Vector3(2.0, 1.0, 0.4), Vector3(0.0, 0.5, -1.0))
	await step(1)
	_place(world)
	await step(2)
	var hit: Dictionary = world["player"].probes.vault_query()
	check(hit["valid"], "the probe missed a thin box")
	check(hit["vault_over"], "a thin obstacle with clear floor beyond did not read as vault-over")
	world["box"].queue_free()
	TestWorld.teardown(world)
	await step(1)

func test_a_deep_obstacle_reads_as_onto_only() -> void:
	# bVaultOnto is functionally the obstacle's THICKNESS: is there anywhere
	# to land on the far side, or only its own top?
	var world := _world_with_box(Vector3(2.0, 1.0, 4.0), Vector3(0.0, 0.5, -2.8))
	await step(1)
	_place(world)
	await step(2)
	var hit: Dictionary = world["player"].probes.vault_query()
	check(hit["valid"], "the probe missed a deep box")
	check(not hit["vault_over"], "a deep obstacle wrongly read as vault-over")
	world["box"].queue_free()
	TestWorld.teardown(world)
	await step(1)
```

⚠️ 上面四个用例的箱子尺寸/位置是按 `player.tscn` 现有探针几何估的。第一次跑若 `valid` 为 false，**先用 `print()` 打出探针命中情况定位几何**，再调整测试里的摆放；不要改断言的语义。

- [ ] **Step 2: 跑测试确认失败**

Run: `pwsh -File tools/run_tests.ps1`

Expected: FAIL —— 返回字典里没有 `height` / `distance` / `vault_over` 键。

- [ ] **Step 3: 给 `SpeedVaultConfig` 加探测距离参数**

```gdscript
## How far past the obstacle's far face to look for somewhere to land, which
## is what decides vault-OVER from vault-ONTO. The original expresses this as
## the bCheckForVaultOver probe on TdPhysicsMove (06 §6.2) rather than as a
## distance, so this number is ours: half the body's own depth is enough to
## tell "there is floor on the other side" from "this thing is thick".
@export var vault_over_probe_distance: float = 0.5
```

- [ ] **Step 4: 在 `player.tscn` 生成器里加一根向下射线**

`tools/build_player_scene.gd` 的探针组新增 `VaultOverDown`，与 `SurfaceDown` 同样由 `Probes` 在查询时按 live config 定位（**不要烘死几何**，理由见 `probes.gd` 的 `setup()` 注释）。

Run: `.engine\Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tools/build_player_scene.gd`

- [ ] **Step 5: 扩展 `vault_query()`**

在现有的高度校验之后，补三项并返回：

```gdscript
	# Horizontal distance from the body origin to the obstacle face. The
	# lookahead in SpeedVaultMove divides this by horizontal speed, so it has
	# to be measured to the FACE (VaultLow's own hit), not to the top surface
	# SurfaceDown found further along the ray.
	var face_point: Vector3 = _vault_low.get_collision_point()
	var to_face := face_point - global_position
	var distance: float = Vector2(to_face.x, to_face.z).length()

	# bVaultOnto is functionally the obstacle's thickness (05 §5.7 axis 2):
	# is there anywhere to land beyond it, or only its own top? Probed by
	# dropping a ray just past the far face.
	var vault_over: bool = _query_vault_over(top, normal)

	return {
		"valid": true, "top": top, "edge": top, "normal": normal,
		"height": height, "distance": distance, "vault_over": vault_over,
	}
```

`_query_vault_over()` 把 `VaultOverDown` 放到「障碍顶再往前 `vault_over_probe_distance`」处、从略高于顶面向下打，命中面法线满足 `walkable_floor_z` 且高度不高于障碍顶即为 true。写法与 `_query_surface()` 平行，同样每次查询现算几何。

- [ ] **Step 6: 跑测试确认通过**

Run: `pwsh -File tools/run_tests.ps1`

Expected: PASS，`test_probes_vault.gd  4 test(s)`；其余套件不回归（`vault_query()` 只是**新增**键，旧键语义未变）。

- [ ] **Step 7: 提交**

```bash
git add -A scripts tools scenes tests
git commit -F - <<'EOF'
feat(probes): report obstacle distance, height and whether there is a far side

The variant table needs two things this rig could not answer: how far ahead
the obstacle is (the numerator of the time-to-obstacle lookahead) and whether
anything is landable beyond it, which is what separates vaulting ONTO
something from vaulting OVER it -- functionally the obstacle's thickness.

Height comes along for the ride because every caller was recomputing it from
the returned top and its own foot offset.

Additive only: existing keys keep their meaning, so nothing downstream
changes yet.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
```

---

## Task 14: Vault 六变体表 + 时间前瞻

现在的翻越是「一个常数时长、一个常数损速、按固定距离触发」。原版按 5 个轴在 6 个变体里选，时长 0.50–1.17 s，速度结果从 **+0.8 m/s 奖励**到**钳到 2.0–4.0 的净降速**；而且判定发生在**接触前 0.2–0.4 秒**，用那一刻的速度向量。

前瞻窗口是时间而非距离，带来一个免费的好性质：4.0 m/s 时前瞻 1.6 m，7.2 m/s 时前瞻 2.88 m——**越快越流畅**不需要额外调参。

**Files:**
- Modify: `scripts/player/config/moves/speed_vault_config.gd`、`scripts/player/moves/speed_vault_move.gd`、`scripts/player/moves/walking_move.gd`、`scripts/player/moves/falling_move.gd`
- Regenerate: `scenes/main.tscn`
- Test: `tests/test_vault_variants.gd`

**Interfaces:**
- Produces:
  - `SpeedVaultConfig.variants: Array[Dictionary]`，每项键为
    `name / min_height / max_height / vault_onto / min_speed_z / max_speed_z / clamp_speed_min / clamp_speed_max / max_momentum / speed_addition / duration / max_distance_time / is_stringable / reset_camera / ledge_offset_z`
  - `SpeedVaultConfig.pick_variant(height: float, vault_over: bool, speed_z: float, speed_xy: float) -> Dictionary`（未匹配返回空字典）
  - `SpeedVaultConfig.should_commit(distance: float, speed_xy: float, variant: Dictionary) -> bool`

- [ ] **Step 1: 写失败的测试**

Create `tests/test_vault_variants.gd`:

```gdscript
class_name TestVaultVariants
extends TestCase

# The variant table, tested as a lookup. 05 §5.7 is the source; the five
# discriminating axes are height, whether there is a far side, vertical speed
# direction, horizontal momentum, and the time-to-obstacle window.

func _cfg() -> SpeedVaultConfig:
	return MovementConfig.new().speed_vault

func test_the_table_has_all_six_confirmed_variants() -> void:
	var names := PackedStringArray()
	for v in _cfg().variants:
		names.append(v["name"])
	for expected in ["auto_step_up_right_leg", "step_up_right_leg_88", "vault_onto", \
			"vault_over", "vault_over_high", "vault_onto_high"]:
		check(names.has(expected), "variant %s missing from the table" % expected)

func test_running_fast_at_a_sweet_spot_obstacle_earns_speed() -> void:
	# The reason the move is called SpeedVault: speed is the key that unlocks
	# the better animation, and the better animation pays a bonus.
	var variant := _cfg().pick_variant(1.0, true, 0.0, 6.0)
	check(variant.has("name"), "no variant matched a fast sweet-spot approach")
	check(variant["name"] == "vault_over", "a fast approach did not pick vault_over")
	check_greater(variant["speed_addition"], 0.0, "the sweet spot did not pay a bonus")

func test_walking_at_the_same_obstacle_picks_the_slow_climb() -> void:
	# Same height, same geometry -- only the momentum differs, and the
	# original resolves that into a different animation with no bonus.
	var variant := _cfg().pick_variant(1.0, true, 1.0, 1.5)
	check(variant.has("name"), "no variant matched a slow approach")
	check(variant["name"] == "step_up_right_leg_88", "a slow approach did not pick the climb")
	check_approx(variant["speed_addition"], 0.0, 0.0001, "the slow climb paid a bonus")

func test_a_high_obstacle_requires_already_being_on_the_way_up() -> void:
	# MinSpeedZ = 50: the high variants only trigger while still RISING, which
	# is what makes "you have to jump at tall things" a rule the player can
	# internalise instead of an autograb.
	var cfg := _cfg()
	check(not cfg.pick_variant(1.7, false, -1.0, 6.0).has("name"), \
		"a high obstacle matched while descending")
	check(cfg.pick_variant(1.7, false, 2.0, 6.0).has("name"), \
		"a high obstacle did not match while rising")

func test_a_high_obstacle_clamps_speed_down() -> void:
	var variant := _cfg().pick_variant(1.7, false, 2.0, 7.0)
	check(variant["clamp_speed_max"] < 7.0, "the high variant did not clamp speed down")
	check_greater(variant["duration"], 1.0, "the high variant is not markedly slower")

func test_nothing_matches_above_the_tables_own_ceiling() -> void:
	# Past 1.92 m the original leaves VaultTypes entirely and goes down the
	# wall-climb / grab / pull-up chain instead.
	check(not _cfg().pick_variant(2.5, false, 2.0, 7.0).has("name"), \
		"an out-of-range obstacle matched a vault variant")

func test_the_lookahead_window_is_time_not_distance() -> void:
	# The property that makes "faster feels smoother" fall out for free: the
	# same 0.4 s window is 1.6 m at 4 m/s and 2.88 m at 7.2 m/s.
	var cfg := _cfg()
	var variant := cfg.pick_variant(1.0, true, 0.0, 6.0)
	check(cfg.should_commit(2.0, 7.2, variant), "a fast approach did not commit at 2.0 m")
	check(not cfg.should_commit(2.0, 4.0, variant), "a slow approach committed at 2.0 m anyway")

func test_a_stationary_approach_never_commits() -> void:
	# distance / speed must not divide by zero into an infinite lookahead.
	var cfg := _cfg()
	var variant := cfg.pick_variant(1.0, true, 0.0, 6.0)
	check(not cfg.should_commit(1.0, 0.0, variant), "a standstill committed to a vault")
```

- [ ] **Step 2: 跑测试确认失败**

Run: `pwsh -File tools/run_tests.ps1`

Expected: FAIL —— `SpeedVaultConfig` 没有 `variants` / `pick_variant` / `should_commit`。

- [ ] **Step 3: 写入变体表**

`SpeedVaultConfig` 删掉 `vault_max_height` / `vault_min_speed` / `vault_duration` / `vault_speed_keep`，保留 `vault_reach`（探针几何用）、`vault_exit_forward`、`vault_arc_height`、`vault_over_probe_distance`，并加：

```gdscript
## Source: 05 §5.7 `TdMove_SpeedVault.VaultTypes`. ✅ All six, converted to
## metric. ORDER IS SIGNIFICANT: pick_variant() takes the first match, and
## ❓ the original's own precedence rule needs bytecode to recover, so the
## high-momentum variants are listed ahead of the low-momentum ones. That
## ordering is what makes "running fast unlocks the better move" true.
##
## TWO DIFFERENT SPEED CONCEPTS, deliberately separate fields -- 05 §5.7 ②
## reads them as different things and conflating them makes the table
## unsatisfiable:
##   entry_speed_min / entry_speed_max  ENTRY GATE. Which variant this
##       approach is allowed to trigger. `stepuprightleg88` is gated by
##       MaxMomentum = 200 (an UPPER bound: walk up to it and you climb),
##       `vaultOnto`/`vaultOver` by ClampSpeedMin = 400 (a LOWER bound: run
##       at it and you speed-vault).
##   clamp_speed_min / clamp_speed_max  OUTPUT CLAMP. What the move does to
##       your speed once it is running. This is where the high variants'
##       "clamped to 200-400" punishment lives.
@export var variants: Array[Dictionary] = [
	{
		"name": "vault_over", "min_height": 0.64, "max_height": 1.48,
		"vault_onto": false, "min_speed_z": 0.0, "max_speed_z": 100.0,
		"entry_speed_min": 4.0, "entry_speed_max": INF,
		"clamp_speed_min": 0.0, "clamp_speed_max": 7.2,
		"speed_addition": 0.8, "duration": 0.65, "max_distance_time": 0.4,
		"is_stringable": true, "reset_camera": false, "ledge_offset_z": 0.25,
	},
	{
		"name": "vault_onto", "min_height": 0.64, "max_height": 1.48,
		"vault_onto": true, "min_speed_z": 0.0, "max_speed_z": 100.0,
		"entry_speed_min": 4.0, "entry_speed_max": INF,
		"clamp_speed_min": 0.0, "clamp_speed_max": 7.2,
		"speed_addition": 0.8, "duration": 0.65, "max_distance_time": 0.4,
		"is_stringable": true, "reset_camera": false, "ledge_offset_z": 0.25,
	},
	{
		"name": "vault_over_high", "min_height": 1.45, "max_height": 1.92,
		"vault_onto": false, "min_speed_z": 0.5, "max_speed_z": 100.0,
		"entry_speed_min": 0.0, "entry_speed_max": INF,
		"clamp_speed_min": 2.0, "clamp_speed_max": 4.0,
		"speed_addition": 0.0, "duration": 1.03, "max_distance_time": 0.4,
		"is_stringable": false, "reset_camera": true, "ledge_offset_z": 0.05,
	},
	{
		"name": "vault_onto_high", "min_height": 1.45, "max_height": 1.92,
		"vault_onto": true, "min_speed_z": 0.5, "max_speed_z": 100.0,
		"entry_speed_min": 0.0, "entry_speed_max": INF,
		"clamp_speed_min": 2.0, "clamp_speed_max": 4.0,
		"speed_addition": 0.0, "duration": 1.17, "max_distance_time": 0.4,
		"is_stringable": false, "reset_camera": true, "ledge_offset_z": 0.35,
	},
	{
		"name": "step_up_right_leg_88", "min_height": 0.48, "max_height": 1.48,
		"vault_onto": true, "min_speed_z": 0.0, "max_speed_z": 7.0,
		"entry_speed_min": 0.0, "entry_speed_max": 2.0,
		"clamp_speed_min": 0.0, "clamp_speed_max": 7.0,
		"speed_addition": 0.0, "duration": 0.65, "max_distance_time": 0.4,
		"is_stringable": false, "reset_camera": false, "ledge_offset_z": 0.6,
	},
	{
		"name": "auto_step_up_right_leg", "min_height": 0.0, "max_height": 0.48,
		"vault_onto": true, "min_speed_z": -6.0, "max_speed_z": 0.0,
		"entry_speed_min": 1.0, "entry_speed_max": 3.0,
		"clamp_speed_min": 0.0, "clamp_speed_max": 3.0,
		"speed_addition": 0.0, "duration": 0.50, "max_distance_time": 0.2,
		"is_stringable": false, "reset_camera": false, "ledge_offset_z": 0.9,
	},
]

## First variant whose five axes all admit this approach, or {} for none.
## An empty result is a normal outcome, not an error -- above 1.92 m the
## original leaves VaultTypes entirely (05 §5.7) and this project simply
## does not vault.
func pick_variant(height: float, vault_over: bool, speed_z: float, speed_xy: float) -> Dictionary:
	for v in variants:
		if height < v["min_height"] or height > v["max_height"]:
			continue
		# An OVER variant needs somewhere to land on the far side; an ONTO
		# variant is always admissible, because a thin obstacle can be
		# climbed onto just as well as crossed. bVaultOnto describes what the
		# ANIMATION does, not what the geometry forbids -- reading it as a
		# two-way exclusive leaves a thin obstacle approached slowly with no
		# match at all.
		if not v["vault_onto"] and not vault_over:
			continue
		if speed_z < v["min_speed_z"] or speed_z > v["max_speed_z"]:
			continue
		if speed_xy < v["entry_speed_min"] or speed_xy > v["entry_speed_max"]:
			continue
		return v
	return {}

## True once the obstacle is within `max_distance_time` SECONDS of arrival.
## The parameter is named MaxDistanceTime and holds 0.2 / 0.4 while every
## genuine distance in the same file is 50-350 uu, so it is a time (05 §5.7).
##
## Committing on time rather than on contact buys three things: the lookahead
## scales with speed for free, the velocity vector read at commit time is
## still clean (contact has not yet perturbed it), and there is a real 0.2-0.4
## s left to blend an animation into. The cost is that commitment is final --
## changing input after the lock does not cancel it, which is consistent with
## the original's "the quality of the take-off decides everything".
func should_commit(distance: float, speed_xy: float, variant: Dictionary) -> bool:
	if variant.is_empty() or speed_xy <= 0.01:
		return false
	return distance / speed_xy <= variant["max_distance_time"]
```

- [ ] **Step 4: 让 `WalkingMove` / `FallingMove` 按前瞻提交，`SpeedVaultMove` 按变体执行**

两个 Move 的翻越检查统一改成：

```gdscript
	if player.probes != null and current_config().check_for_vault_over:
		var hit: Dictionary = player.probes.vault_query()
		if hit["valid"]:
			var variant: Dictionary = config.speed_vault.pick_variant(
				hit["height"], hit["vault_over"], player.velocity.y, player.horizontal_speed())
			if config.speed_vault.should_commit(hit["distance"], player.horizontal_speed(), variant):
				player.pending_vault_variant = variant
				return SPEED_VAULT
```

`WalkingConfig._init()` 设 `check_for_vault_over = true`；`JumpConfig._init()` 设 `check_for_vault_over = true` 与 `check_for_grab = true`（外加 `check_for_wall_climb = true`，本项目无 wallclimb，记录而已）；`FallingConfig._init()` 设 `check_for_vault_over = true`、`check_for_grab = true`、`check_for_wall_climb = false`。

`Player` 加 `var pending_vault_variant: Dictionary = {}`。`SpeedVaultMove.enter()` 读它，用 `variant["duration"]` 作时长、`variant["ledge_offset_z"]` 作落点高度偏移，退出速度按：

```gdscript
	# The sweet spot PAYS (+0.8 m/s); the high variants are clamped DOWN. This
	# is the opposite sign from this project's old flat 0.85 keep ratio, and
	# it is the whole reason the original's obstacles read as opportunities
	# rather than as taxes.
	var exit_speed: float = clampf(entry_speed + variant["speed_addition"], \
		variant["clamp_speed_min"], variant["clamp_speed_max"])
```

- [ ] **Step 5: 更新关卡几何到甜区**

`tools/arena_builder.gd` 的翻越练习区改为按 05 §5.7 的甜区布置：矮档 0.3 m、甜区 0.9 m 与 1.3 m、高档 1.7 m 各一。

Run: `.engine\Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tools/build_main_scene.gd`

- [ ] **Step 6: 跑测试确认通过**

Run: `pwsh -File tools/run_tests.ps1`

Expected: PASS，`test_vault_variants.gd  8 test(s)`。

- [ ] **Step 7: 人工验证**

Expected: 全速冲过 0.9 m 的箱子**变快了**（+0.8 m/s），而且动作触发得更早、更顺；慢慢走过去则是「爬上去」，没有奖励。1.7 m 的高障碍**必须先按跳、在上升途中**才能翻，落地明显掉速且耗时约两倍。

- [ ] **Step 8: 提交**

```bash
git add -A scripts tools scenes tests
git commit -F - <<'EOF'
feat(vault): resolve six variants by momentum, and commit before contact

The original picks among six vault animations on five axes and pays out
differently for each: the 0.64-1.48 m sweet spot taken at speed ADDS 0.8 m/s
and can be strung, while the 1.45-1.92 m band clamps you down to 2-4 m/s,
takes twice as long and resets the camera. This project had one animation,
one duration, and a flat 0.85 keep ratio -- the opposite sign from the sweet
spot, so its obstacles read as taxes rather than opportunities.

Commitment now happens 0.2-0.4 SECONDS before contact rather than at a fixed
distance. The parameter is named MaxDistanceTime but holds 0.2/0.4 where
every real distance in the same file is 50-350 uu, so it is a time -- and
reading it as one means the lookahead scales with speed for free, the
velocity vector at commit time is still clean, and there is real time left to
blend an animation. Commitment is final in exchange, which is consistent with
the original making the take-off the decisive moment.

Variant precedence needs bytecode to recover, so the table is ordered
high-momentum first, which is what makes running fast unlock the better move.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
```

---

## Task 15: 按 Move 的镜头约束 + 修正贴墙滚转方向

Task 4 已经把约束推给了 `CameraRig` 但没有消费。现在接上，并一并修掉所有者报告的滚转方向问题。

**Files:**
- Modify: `scripts/camera/camera_rig.gd`
- Test: `tests/test_camera_constraints.gd`

**Interfaces:**
- Consumes: Task 4 的 `CameraRig.set_look_constraint()` / `clear_look_constraint()`
- Produces: 无新接口；`apply_look()` 行为改变

- [ ] **Step 1: 写失败的测试**

Create `tests/test_camera_constraints.gd`:

```gdscript
class_name TestCameraConstraints
extends TestCase

func _rig() -> CameraRig:
	var scene: PackedScene = load("res://scenes/player/player.tscn")
	var player: Player = scene.instantiate()
	tree.root.add_child(player)
	var config := MovementConfig.new()
	player.setup(config, ScriptedInputSource.new())
	player.camera_rig.setup(config)
	return player.camera_rig

func test_an_unconstrained_move_uses_the_default_pitch_limit() -> void:
	var rig := _rig()
	await step(1)
	rig.clear_look_constraint()
	for i in 200:
		rig.apply_look(Vector2(0.0, -100.0), rig.get_parent())
	check(rig.rotation.x <= deg_to_rad(89.1), "pitch escaped the default limit")
	check_greater(rig.rotation.x, deg_to_rad(88.0), "pitch did not reach the default limit")
	rig.get_parent().queue_free()
	await step(1)

func test_a_constrained_move_clamps_pitch_harder() -> void:
	# WallRun clamps to +-71.4 degrees, which is where "you cannot look back
	# while on a wall" comes from -- an input constraint, not an animation.
	var rig := _rig()
	await step(1)
	rig.set_look_constraint(Vector3(-deg_to_rad(71.4), -PI, -PI), \
		Vector3(deg_to_rad(71.4), PI, PI), false)
	for i in 200:
		rig.apply_look(Vector2(0.0, -100.0), rig.get_parent())
	check(rig.rotation.x <= deg_to_rad(71.5), "pitch escaped the move's own limit")
	check_greater(rig.rotation.x, deg_to_rad(70.0), "pitch did not reach the move's own limit")
	rig.get_parent().queue_free()
	await step(1)

func test_leaving_a_constrained_move_restores_the_default_limit() -> void:
	var rig := _rig()
	await step(1)
	rig.set_look_constraint(Vector3(-deg_to_rad(20.0), -PI, -PI), \
		Vector3(deg_to_rad(20.0), PI, PI), false)
	for i in 100:
		rig.apply_look(Vector2(0.0, -100.0), rig.get_parent())
	rig.clear_look_constraint()
	for i in 200:
		rig.apply_look(Vector2(0.0, -100.0), rig.get_parent())
	check_greater(rig.rotation.x, deg_to_rad(80.0), "the clamp stayed applied after clearing")
	rig.get_parent().queue_free()
	await step(1)

func test_a_left_wall_rolls_the_camera_clockwise() -> void:
	# OWNER-REPORTED, and the reason this changes: the previous code
	# deliberately rolled the view TOWARD the wall (its own comment and its
	# archived test both said so), which reads as backwards in play.
	# Clockwise from the player's own viewpoint is a NEGATIVE rotation.z --
	# positive z takes +X toward +Y, i.e. counter-clockwise when viewed from
	# behind the camera.
	var rig := _rig()
	await step(1)
	rig.set_wall_side(-1)
	for i in 60:
		rig.update_effects(1.0 / 60.0, 5.0, false)
	check(rig.rotation.z < -0.01, "a left wall did not roll the camera clockwise")
	rig.get_parent().queue_free()
	await step(1)

func test_the_two_wall_sides_roll_opposite_ways() -> void:
	var rig := _rig()
	await step(1)
	rig.set_wall_side(-1)
	for i in 60:
		rig.update_effects(1.0 / 60.0, 5.0, false)
	var left := rig.rotation.z
	rig.set_wall_side(1)
	for i in 120:
		rig.update_effects(1.0 / 60.0, 5.0, false)
	var right := rig.rotation.z
	check(left * right < 0.0, "the two wall sides rolled the same way")
	rig.get_parent().queue_free()
	await step(1)
```

- [ ] **Step 2: 跑测试确认失败**

Run: `pwsh -File tools/run_tests.ps1`

Expected: FAIL —— 约束用例失败（`apply_look()` 还只读 `pitch_limit_deg`），滚转用例失败（当前是反的）。

- [ ] **Step 3: 让 `apply_look()` 消费约束**

```gdscript
## Yaw turns the body so movement follows the view; pitch stays on the rig.
##
## The ACTIVE MOVE's own clamp wins over the global pitch limit when it
## declares one. The original makes this per-move data (MinLookConstraint /
## MaxLookConstraint, 06 §6.2) and it is a genuine input constraint: on a wall
## the view is locked into a +-90 degree yaw fan and cannot look back, which
## is where that whole sensation comes from.
func apply_look(look_delta: Vector2, body: Node3D) -> void:
	if _config == null:
		return
	var yaw_delta := -look_delta.x * _config.camera.mouse_sensitivity
	if _has_look_constraint:
		# Absolute yaw: measured against the facing captured when the move
		# began, so the fan stays pinned to the wall rather than drifting with
		# the player. Source: 04 §4.1 bUseAbsoluteYawConstraint = True.
		var reference: float = _yaw_reference if _look_absolute_yaw else body.rotation.y
		var next_yaw: float = body.rotation.y + yaw_delta
		var relative: float = wrapf(next_yaw - reference, -PI, PI)
		relative = clampf(relative, _look_min.y, _look_max.y)
		body.rotation.y = reference + relative
	else:
		body.rotate_y(yaw_delta)

	var pitch_min: float = -deg_to_rad(_config.camera.pitch_limit_deg)
	var pitch_max: float = deg_to_rad(_config.camera.pitch_limit_deg)
	if _has_look_constraint:
		pitch_min = maxf(pitch_min, _look_min.x)
		pitch_max = minf(pitch_max, _look_max.x)
	_pitch = clampf(_pitch - look_delta.y * _config.camera.mouse_sensitivity, pitch_min, pitch_max)
	rotation.x = _pitch
```

`set_look_constraint()` 在**从无约束转为有约束**的那一次调用里记下 `_yaw_reference = get_parent().rotation.y`（后续 tick 的重复调用不要重置它，否则扇形会跟着玩家漂走）。

- [ ] **Step 4: 修正滚转方向**

`update_effects()` 里去掉那个负号：

```gdscript
	# SIGN: positive rotation.z rotates local up toward -X (verified against
	# this exact Godot build: rotation.z = 10 degrees gives basis.y =
	# (-0.17, 0.98, 0)), which from behind the camera reads as
	# counter-clockwise. A left wall (wall_side = -1) therefore produces a
	# NEGATIVE rotation.z here, i.e. clockwise -- which is what the owner
	# reports as correct in play.
	#
	# This REVERSES the earlier intent. The previous code negated this
	# deliberately, and both its comment and its (now archived) test declared
	# the goal as "roll toward the wall". The research offers no ruling either
	# way: 09 §9.1 calls the direction correct, but the same section records
	# that the original has NO VALUE for this field at all, so that was the
	# researcher's judgement rather than extracted data. The owner is playing
	# it; the owner wins.
	var target_roll := deg_to_rad(_config.camera.wall_camera_roll_deg) * float(_wall_side)
```

- [ ] **Step 5: 跑测试确认通过**

Run: `pwsh -File tools/run_tests.ps1`

Expected: PASS，`test_camera_constraints.gd  5 test(s)`。

- [ ] **Step 6: 人工验证**

Expected: 贴左墙时镜头**顺时针**滚转（所有者报告的期望方向）。贴墙期间视角被锁在正负 90° 的扇形里，**回不了头**；滑铲期间上下左右都被收到约 55°。松开墙/结束滑铲后视角限制立刻恢复正常。

- [ ] **Step 7: 提交**

```bash
git add scripts/camera/camera_rig.gd tests/test_camera_constraints.gd
git commit -F - <<'EOF'
feat(camera): clamp the view per move, and roll the right way on a wall

Look constraints are per-move data in the original, and on a wall they are
severe: pitch to +-71.4 degrees and yaw to a +-90 degree fan measured against
the facing the move started with. "The view swings to face along the wall" is
that clamp and nothing else -- an input constraint, not an animation.

The wall roll direction is reversed from what this project had. The previous
sign was deliberate: its comment and its test both declared the intent as
"roll toward the wall". Playing it says otherwise, and the research cannot
adjudicate -- it calls the direction correct while also recording that the
original has no value for this field at all, so that was judgement, not data.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
```

---

## Task 16: 收尾——清残留、对验收表、更新 spec

**Files:**
- Modify: `scripts/player/config/pawn_config.gd`、`scripts/player/config/camera_config.gd`、`scripts/player/config/moves/grab_config.gd`、`scripts/player/moves/grab_move.gd`、`scripts/player/probes.gd`、`docs/superpowers/specs/2026-08-17-mirrors-edge-1to1-movement-design.md`
- Regenerate: `scenes/player/player.tscn`
- Test: `tests/test_acceptance_checklist.gd`

- [ ] **Step 1: 清掉 `Legacy` 分组的最后残留**

删除 `PawnConfig` 的 `Legacy -- deleted by later tasks` 分组本身。到此该组应只剩 `ledge_regrab_cooldown`——把它换成 `GrabConfig._init()` 里的 `redo_move_time = 0.45`，`grab_move.gd` 里 `player.start_ledge_cooldown()` 与 `player.can_grab_ledge()` 的调用改由 `MoveManager` 的冷却接管，随后删除 `Player._ledge_cooldown`、`start_ledge_cooldown()`、`can_grab_ledge()`。

同时把 `walkable_floor_z` 由迁移时的 `0.7` 改到确证的 **`0.71`**（= `acos` 44.7°，与 Godot 默认 `floor_max_angle` 45° 基本一致）。

- [ ] **Step 1b: 把 `GrabConfig` 的抓边参数换成确证值**

Task 2 只搬迁了本项目自创的 `ledge_min_height 1.4` / `ledge_max_height 2.8` / `ledge_reach 1.0`，spec §4.3 记的三个确证值一直没落地。改为：

```gdscript
## Source: 04 §4.2 `TdMove_WallClimb.MinWallHeight = 180` uu. ✅ The lowest
## thing worth grabbing rather than vaulting -- and it dovetails with the
## vault table, whose own ceiling is 1.92 m (05 §5.7).
@export var min_wall_height: float = 1.8
## Source: 05 §5.7 `LedgeFindDistance = 350` uu. ✅ Notably longer than this
## project's own 1.0 m reach: the original starts looking for a ledge from
## much further out, which is part of why its grabs read as deliberate rather
## than as last-instant saves.
@export var ledge_find_distance: float = 3.5
## Source: 04 §4.2 `MinLegdeZNormal = 0.707` -> 45 degrees. ✅ (The original
## misspells the field; corrected here per the naming convention.)
@export var min_ledge_z_normal: float = 0.707
```

`ledge_min_height` → 由 `min_wall_height` 取代；`ledge_reach` → 由 `ledge_find_distance` 取代（`probes.gd` 的 `ledge_query()` 相应改名）。`ledge_max_height 2.8` **保留**为项目值（原版没有上界，因为超过 1.92 m 走的是 wallclimb 链，而本项目排除了 wallclimb，所以需要一个上界兜底）——在 doc comment 里写明这层原因。

- [ ] **Step 1c: 眼高改到确证值并重生成玩家场景**

`CameraConfig.eye_height` 由 `0.7` 改为 **`0.76`**（✅ `BaseEyeHeight = 76` uu）。`tools/build_player_scene.gd` 把这个值烘进 `player.tscn` 的 `CameraRig` 初始位置，所以要重新生成：

Run: `.engine\Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tools/build_player_scene.gd`

⚠️ Task 13 Step 4 已经往这个生成器里加过 `VaultOverDown` 射线，本次重生成会把两处改动一起带上——跑完 `git diff scenes/player/player.tscn` 确认只有眼高和探针两项变化。

- [ ] **Step 2: 写验收清单测试**

Create `tests/test_acceptance_checklist.gd`——把 10.4 那张速查表里**能自动判定的**几条钉住，作为整个重做的回归底线：

```gdscript
class_name TestAcceptanceChecklist
extends TestCase

# The research's own checklist (10 §10.4), reduced to what a headless test can
# actually decide. Whether it FEELS right is not in here and cannot be.

func test_1_top_speed_needs_more_than_five_seconds_of_running() -> void:
	var pawn := PawnConfig.new()
	var energy := SpeedEnergy.new(pawn)
	for i in 300:
		energy.accumulate(1.0 / 60.0, SpeedEnergy.SPRINT)
	check(energy.cap() < pawn.ground_speed - 0.05, \
		"five seconds of running already reached top speed")

func test_2_air_speed_is_effectively_uncapped_and_air_control_is_tiny() -> void:
	var pawn := PawnConfig.new()
	check_greater(pawn.air_speed, pawn.ground_speed * 3.0, "air speed is capped near ground speed")
	check(pawn.accel_rate * pawn.air_control < 2.0, "air control is not almost nothing")

func test_3_turning_has_a_continuous_cost() -> void:
	var pawn := PawnConfig.new()
	var energy := SpeedEnergy.new(pawn)
	energy.energy = 7.0
	energy.spend_turn(deg_to_rad(5.0))
	check(energy.energy < 7.0, "a small turn was free")

func test_5_a_key_move_spans_at_least_three_times() -> void:
	var cfg := MovementConfig.new().wallrun_jump
	var worst := cfg.wall_running_push_away_speed_noob
	var best := worst + cfg.wall_running_push_away_speed_pro_add
	check_greater(best / worst, 3.0, "no key move has a 3x execution gradient")

func test_6_landing_is_judged_on_a_resettable_counter() -> void:
	var tracker := FallTracker.new(PawnConfig.new())
	tracker.update(1.0 / 60.0, -5.0, 10.0)
	tracker.update(1.0 / 60.0, -5.0, 6.0)
	check_greater(tracker.fall_height, 3.0, "the counter did not accumulate")
	tracker.reset()
	check_approx(tracker.fall_height, 0.0, 0.0001, "the counter is not resettable")

func test_8_moves_declare_their_own_camera_constraints() -> void:
	var config := MovementConfig.new()
	check(config.wall_run.constrain_look, "wall running declares no look constraint")
	check(config.slide.constrain_look, "sliding declares no look constraint")
	check(not config.walking.constrain_look, "walking wrongly constrains the look")

func test_10_a_flat_jump_hangs_for_about_one_and_a_half_seconds() -> void:
	var pawn := PawnConfig.new()
	var hang: float = 2.0 * pawn.base_jump_z / pawn.gravity
	check_approx(hang, 1.40, 0.02, "flat-jump hang time is not the confirmed 1.40 s")
	var apex: float = pawn.base_jump_z * pawn.base_jump_z / (2.0 * pawn.gravity)
	check(apex < pawn.skill_roll_landing_height, \
		"the jump apex reaches the roll threshold, so every jump costs speed")
```

- [ ] **Step 3: 跑全套测试**

Run: `pwsh -File tools/run_tests.ps1`

Expected: PASS，退出码 0，无 `SCRIPT ERROR:` 行。记录总 `checks:` 数。

- [ ] **Step 4: 更新 spec 记录实施过程中的三处偏离**

在 spec 里补上：

1. **§4.3 / §5.5**：WallrunJump **没有**做成独立注册的 Move（见 Task 12 的说明——一个只活一 tick 的 Move 要么停顿一帧要么复制 `FallingMove` 的全部逻辑）。参数仍全部取自 `wallrun_jump` config，梯度是可单测的纯函数。
2. **§3.5**：`fall_height` 的归零只发生在**触地事件**，没有单独实现「roll 动画结束时归零」——本项目没有 Roll 这个独立动作状态。实际影响很小：drop-roll 的效果本来就来自落地那次触地归零。
3. **§8 风险**：把 Task 11 Step 8 实测到的 zig-zag 连跳结果写进去（能否无限爬升，以及若能，爬到多高）。

- [ ] **Step 5: 提交**

```bash
# Path-scoped on purpose: `docs` as a whole would sweep in the owner's
# untracked reverse-engineering scripts under mirrors-edge-deep-research/tools/.
git add -A scripts tests scenes docs/superpowers/specs
git commit -F - <<'EOF'
chore(movement): retire the last carried-over knobs and pin the checklist

The ledge regrab cooldown becomes the Grab move's own RedoMoveTime, which was
the last of the three hand-rolled cooldowns Player used to carry, and
walkable_floor_z moves to the confirmed 0.71.

The acceptance test encodes the parts of the research's own checklist a
headless run can actually decide -- speed takes more than five seconds to
build, air control is almost nothing, turning is never free, a key move spans
more than 3x, landings read a resettable counter, moves declare their own
camera clamps, and a flat jump hangs for 1.40 s without reaching the roll
threshold. Whether it FEELS right is not in there and cannot be.

The spec is updated with the three places the implementation diverged from
it.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
```

---

## 自测清单（所有者用）

自动化测试只能证明数值关系与状态机逻辑成立。以下**只有你能判断**，建议按顺序跑一遍并记录感受：

1. 起步 0.4 秒的跟手程度，之后「越快越难快」的坡度是否合适（`pawn.speed_curve`）。
2. `pawn.speed_curve_interp_mode` 在 0/1 之间切换，拐点是否读成「换挡」。
3. 转向代价是否过重（`pawn.speed_turn_deceleration_factor`，默认 2.2282）。
4. 平地连跳是否完全不掉速；2 m 以上跳下是否掉、按 Shift 是否救得回来。
5. 贴墙跑：速度是否明显换来时长；**扭头看墙再跳**与随便跳的差距是否一眼可见。
6. **双墙 zig-zag 是否能无限爬升**（spec §8 记录的已知风险）。
7. 滑铲现在是净损失，下坡是否仍然值得滑、上坡是否立刻停死。
8. 甜区障碍（0.9 / 1.3 m）全速通过是否真的更快更顺；1.7 m 是否必须先跳。
9. 刹车变慢一倍（`braking_friction_strength = 0.5`）是否可接受。
10. `base_friction = 40.0` 是全表唯一没有原版依据的数——它决定整体「粘滞感」，请务必自己拖一遍。
