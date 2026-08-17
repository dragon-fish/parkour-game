# 镜之边缘 1:1 移动系统重做 · 设计

日期：2026-08-17
证据基础：[`docs/mirrors-edge-deep-research/`](../../mirrors-edge-deep-research/README.md)（全 10 章 + 4 份附录）

---

## 0. 背景

MVP 已经能在场景里跑跳滑铲，但手感与原版差距明显。诊断结论不是「数值没调准」，而是**旋钮不同构**：本项目的参数是自创的抽象（`slide_boost`、`wall_max_duration`、`land_cost_speed_ref`……），原版的参数是另一套（`FrictionModifier` 倍率制、速度能量曲线、`Noob`/`ProAdd` 梯度、累计下落高度）。参数体系不同构，就不可能靠调参收敛到同一个手感。

因此本次不是调参，是**把参数体系与动作框架重做成与原版同构**，让此后的「调参」等于在调 DICE 调过的同一批数字。

### 0.1 当前实现的一处确凿缺陷

`jump_velocity = 6.3` + `gravity = 8.0` → 跳跃最高点 2.48 m，落地垂直速度 6.3 m/s。代入 `air_state.gd:68-78`：

```
severity = 6.3 / land_cost_speed_ref(9.21) = 0.684
keep     = lerp(1.0, land_speed_keep(0.55), 0.684) = 0.692
```

**每一次平地跳跃，落地都掉 31% 水平速度。** 这正是 [09.1](../../mirrors-edge-deep-research/09-Godot移植指南.md) 警告的「照抄 `land_*` 阈值却用了更高的跳跃 → 每跳一次都掉速，游戏立刻不能玩」。根因是 `jump_velocity` 取了 `TdMove_Jump.BaseJumpZ = 630`，而 [02.4](../../mirrors-edge-deep-research/02-速度系统.md) 已用游戏内实测把生效值钉死为 `TdPawn.BaseJumpZ = 560` → **5.6**。

---

## 1. 范围

### 1.1 包含

速度能量曲线、转向损速、摩擦力倍率体系、累计下落高度落地判定、墙面技巧梯度、Vault 变体表与时间前瞻、按状态的镜头约束、Move 声明式参数框架、参数资源分层。

### 1.2 排除

原版有、本项目没有对应动作的部分，属于新功能而非复刻数值：

coil、springboard、swing、zipline、balance、ledgewalk、barge、180turn、dodgejump、wallclimb、wallkick、持重型武器速度曲线、`AiAimPenalties` 战斗耦合层、movement string（[06.3](../../mirrors-edge-deep-research/06-Move状态机架构.md) 明说连携收益未确证）、Vertigo 恐高 FOV。

### 1.3 已拍板的有意偏离（不要"修正"回去）

见 [`docs/decisions-pending-your-review.md`](../../decisions-pending-your-review.md)：

- **FOV 90–105 的速度驱动区间**，不采用原版确证的固定 90°。
- **保留 head bob**（高频低幅），原版在开发中移除了它。

---

## 2. 命名与单位约定

1. **概念与字段名照搬原版**，去掉 `Td` 前缀，转 snake_case。`TdMove_WallRun` → `WallRunMove` + `WallRunConfig`；`TdPawn` → `PawnConfig`；`WallRunningPushAwaySpeedNoob` → `wall_running_push_away_speed_noob`。
2. **单位一律转公制**（1 uu = 1 cm，见研究 README 的三条独立证据）。字段名沿用原版，值是米/秒制。
3. **每个字段的 doc comment 必须记录**：原始 uu 值、来源章节、可信度标记（✅ 确证 / ⚠️ 推断 / ❓ 未知 / 📣 社区）。这是能与 [附录 A1](../../mirrors-edge-deep-research/appendix/A1-TdMove-CDO全量.md) 逐行对照的前提。
4. **两处例外**：原版拼错的 `MinLegdeZNormal` 修正为 `min_ledge_z_normal`；`MaxDistanceTime` 名字说距离实际是秒，保留原名但 doc 里写明。
5. `*ZHeight` 系列在原版里是**高度**不是速度，保持为高度存储，在使用点按 `v = √(2·g·h)` 换算。

---

## 3. 架构

### 3.1 参数分层

```
scripts/player/config/
  movement_config.gd     聚合根：pawn + camera + moves 字典。注入点形状不变
  pawn_config.gd         ≙ TdPawn CDO
  camera_config.gd       感知层（1.3 的有意偏离住这里）
  move_config.gd         ≙ TdMove + TdPhysicsMove 基类
  moves/
    walking_config.gd    jump_config.gd       falling_config.gd
    landing_config.gd    slide_config.gd      crouch_config.gd
    speed_vault_config.gd  grab_config.gd
    wall_run_config.gd   wallrun_jump_config.gd
```

`MoveConfig` 是 [06.2](../../mirrors-edge-deep-research/06-Move状态机架构.md) 那张表的直接落地：

```gdscript
class_name MoveConfig extends Resource
@export var speed_modifier: float = 1.0
@export var friction_modifier: float = 1.0
@export var redo_move_time: float = 0.0
@export var min_look_constraint: Vector3 = Vector3(-PI, -PI, -PI)   # pitch, yaw, roll
@export var max_look_constraint: Vector3 = Vector3(PI, PI, PI)
@export var constrain_look: bool = false
@export var absolute_yaw_constraint: bool = false
@export var check_for_grab: bool = false
@export var check_for_vault_over: bool = false
@export var check_for_wall_climb: bool = false
```

F1 调参面板改成**递归遍历这棵资源树**，每个资源一个可折叠分组。预设存取仍是单个 `.tres`（聚合根），行为不变。

### 3.2 `Move` / `MoveManager`

现有 [`state_machine.gd`](../../../scripts/player/states/state_machine.gd) 的骨架**保留**——注册表 + `enter`/`exit`/`physics_update` + grounded-declaration 不变量。[06.5](../../mirrors-edge-deep-research/06-Move状态机架构.md) 建议的就是这个形状。改三件事：

1. `Move`（取代 `PlayerState`）持有 `cfg: MoveConfig` 与 `pawn: PawnConfig` 两个引用，取代现在每个 state 直接读一个全局 `config`。
2. `MoveManager` 统一管 `redo_move_time` 冷却，取代现在散在 `Player` 里的 `_ledge_cooldown` / `_recent_walls` / `wall_reattach_cooldown` 三套各自为政的冷却。
3. `MoveManager` 每 tick 把当前 Move 的 `min/max_look_constraint` 推给 `CameraRig`；`apply_look()` 改成按当前约束钳制，而不是只读一个全局 `pitch_limit_deg`。

### 3.3 摩擦力倍率体系

取代 `ground_friction = 40.0` / `slide_friction = 5.0` 两个互不相干的绝对减速度：

```
friction = base_friction
         × slope_scale               # 见 4.1，走路与滑铲各一组
         × move.friction_modifier
         × braking_friction_strength
# 走路分支再夹进 [min_walk_friction_modify, max_walk_friction_modify]
```

这是「下坡滑铲飞快、上坡滑铲卡死」唯一能表达的形式（[03.3](../../mirrors-edge-deep-research/03-损速机制.md)）。

⚠️ `base_friction` **原版无确证值**（研究未提取到 `TdPawn.Friction`）。沿用本项目现有的 40.0 作为基数，其余倍率相对它。这一个数需要试玩确定。

### 3.4 `SpeedEnergy`（新增，`scripts/player/speed_energy.gd`）

纯逻辑类，无节点依赖，可 headless 单测。

```gdscript
func cap() -> float                     # 查曲线，钳进 [speed_min_base_velocity, ground_speed]
func accumulate(delta: float, mode: int)
func decay(delta: float)
func spend_turn(radians: float)
func drain(amount: float)               # 落地惩罚等外部扣减
func energy() -> float
```

接入点：

- `Player.ground_accelerate()` 的 `target_speed` 从 `config.ground_speed` 常数 → `speed_energy.cap() × move.speed_modifier`。
- `Player.air_accelerate()` 的 `max(ground_speed, …)` 天花板 → `max(cap(), …)`。

### 3.5 `FallTracker`（新增）

落地判定的依据从当帧 `velocity.y` 改成**自上次触地以来的累计下落高度**。这是 [10.1](../../mirrors-edge-deep-research/10-镜之边缘-like判定标准.md) 的本质机制⑤，也是 [03.5](../../mirrors-edge-deep-research/03-损速机制.md) 整层速通技巧（ventkick / kickglitch / drop-roll）的唯一来源。

```
进入计数：velocity.y < enter_to_falling_z_speed(-2.0) 时记录起始 Y
每 tick ：fall_height = max(fall_height, start_y - global_position.y)
归零    ：任何触地事件；以及 roll 动画结束时（drop-roll 证明结算在动画结束而非落地瞬间）
```

相机 dip 继续读 `impact_speed`（垂直速度），与物理判定分离——dip 是感知层，两者本来就该独立。

---

## 4. 参数表

括号内为原始 uu 值与可信度。

### 4.1 `PawnConfig`

| 字段 | 值 | 来源 |
|---|---|---|
| `ground_speed` | 7.2 | ✅ `GroundSpeed 720` |
| `air_speed` | 24.0 | ✅ `AirSpeed 2400` |
| `accel_rate` | 61.44 | ✅ `AccelRate 6144` |
| `air_control` | 0.025 | ✅ `AirControl 0.025` |
| `gravity` | 8.0 | ✅ `DefaultGravityZ 800` |
| `base_jump_z` | **5.6** | ✅ `TdPawn.BaseJumpZ 560`，实测钉死（02.4） |
| `jump_add_xy` | 1.0 | ⚠️ `JumpAddXY 100`，加法还是取最大值未证 → 取加法 |
| `crouched_pct` | 0.4 | ✅ `CrouchedPct 0.4` |
| `base_eye_height` | 0.76 | ✅ `BaseEyeHeight 76`（现为 0.7） |
| `max_step_height` | 0.35 | ✅ `MaxStepHeight 35` |
| `walkable_floor_z` | 0.71 | ✅ `WalkableFloorZ 0.71`（= 44.7°） |
| `walk_velocity` | 0.5 | ✅ `WalkVelocity 50`，走路修饰键的硬上限 |
| `enter_to_falling_z_speed` | -2.0 | ✅ `EnterToFallingZSpeed -200` |

速度能量：

| 字段 | 值 | 来源 |
|---|---|---|
| `speed_curve` | `[(0,0),(0.4,4.0),(1.0,5.2),(3.5,6.5),(7.0,7.2)]` | ✅ `SpeedCurve_LightWeapon`，`CIM_Linear` |
| `speed_curve_interp_mode` | `LINEAR` \| `SMOOTH` | 见 5.1 |
| `speed_min_base_velocity` | 0.1 | ✅ `SpeedMinBaseVelocity 10` |
| `speed_max_base_velocity` | 4.0 | ✅ `SpeedMaxBaseVelocity 400`，❓ 公式中的角色未知，记录但不使用 |
| `speed_walk_velocity_acceleration_factor` | 7 | ✅ |
| `speed_strafe_velocity_acceleration_factor` | 10 | ✅ |
| `speed_sprint_velocity_acceleration_factor` | 30 | ✅ |
| `speed_energy_deceleration_time` | 3.0 | ✅ |
| `speed_energy_deceleration_exponent` | 0.5 | ✅ |
| `speed_turn_deceleration_factor` | 2.23 | ⚠️ 原值 10，单位不可证；按行为标定，见 5.1 |
| `energy_accumulate_speed_ratio` | 0.9 | ⚠️ **项目自加的守卫**，见 5.1 |

摩擦：

| 字段 | 值 | 来源 |
|---|---|---|
| `base_friction` | 40.0 | ⚠️ 原版无确证值，沿用本项目现值 |
| `upward_walk_friction_scale` | 1.1 | ✅ |
| `downward_walk_friction_scale` | 0.8 | ✅ |
| `min_walk_friction_modify` | 0.4 | ✅ |
| `max_walk_friction_modify` | 2.0 | ✅ |
| `upward_slide_friction_scale` | 5.0 | ✅ |
| `downward_slide_friction_scale` | 1.8 | ✅ |
| `braking_friction_strength` | 0.5 | ✅ `TdPlayerPawn` 覆写（`TdPawn` 为 1.0） |

落地：

| 字段 | 值 | 来源 |
|---|---|---|
| `skill_roll_landing_height` | 2.0 | ✅ `SkillRollLandingHeight 200` |
| `soft_landing_height` | 3.0 | ✅ `SoftLandingHeight 300` |
| `hard_landing_height` | 5.3 | ✅ `HardLandingHeight 530` |
| `landing_speed_reduction` | 0.65 | ❓ `LandingSpeedReduction 65`，读作「损失 65%」，见 7. |
| `roll_trigger_time` | 1.0 | ⚠️ `RollTriggerTime 1.0`，读作 roll 输入预缓冲窗口 |
| `maximum_speed_for_roll_landing` | -50.0 | ✅ |

动画阈值（不参与物理，供 `CharacterAnimator` 分档用，[05.10](../../mirrors-edge-deep-research/05-动作库总览.md)）：`sneak 0.05` / `walk 0.5` / `jog 2.6` / `run 4.0` / `sprint 6.3`；动画侧另一套 `1 / 2.0 / 3.8 / 5.5 / 混入 6.9 满 7.0`。

### 4.2 `CameraConfig`

原样沿用现值：`fov_base 90` / `fov_max 105` / `fov_speed_ref 7.2` / `fov_lerp_speed 6.0` / `bob_frequency 2.618` / `bob_amplitude 0.03` / `bob_fade_speed 6.0` / `land_dip_max 0.32` / `land_dip_recover 2.2` / `land_dip_speed_ref 18.0` / `slide_camera_drop 0.75` / `crouch_lerp_speed 9.0` / `camera_head_follow_strength 0.15` / `mouse_sensitivity 0.0022` / `wall_camera_roll_deg 8.0` / `wall_camera_roll_speed 56.0`。

`eye_height 0.7 → 0.76`（✅ `BaseEyeHeight 76`）——这是数值不是分歧。

记录备用（✅ 确证，本次不接线）：`camera_anim_momentum_influence 0.0001` / `camera_forward_max 0.5` / `camera_downward_max 0.4`。这是原版「晃动幅度是动量的函数」的真身，日后调 bob 时比幅度常数更好用。

### 4.3 各 Move 的 Config

**`WalkingConfig`** — `speed_modifier 1.0`，`friction_modifier 1.0`，镜头约束 pitch ±89°（沿用现值，原版未找到 Walking 的约束）。

**`JumpConfig`** — `check_for_grab`、`check_for_vault_over`、`check_for_wall_climb` 全 `true`（✅ [05.7](../../mirrors-edge-deep-research/05-动作库总览.md) ③）。

**`FallingConfig`** — `check_for_grab`、`check_for_vault_over` 为 `true`，`check_for_wall_climb` 为 **`false`**（✅ 上升能发起爬墙、下降不能）。

**`SlideConfig`**

| 字段 | 值 | 来源 |
|---|---|---|
| `friction_modifier` | 0.1 | ✅ |
| `slide_abort_speed` | 2.5 | ✅ `SlideAbortSpeed 250` |
| `slide_abort_time` | 2.0 | ✅ `SlideAbortTime 2.0` |
| `max_floor_incline_z` | 0.5 | ✅（可滑坡度上限 60°） |
| `min/max_look_constraint` | pitch ±55°、yaw ±55° | ✅ `(-10000,-10000,0)` |
| `slide_capsule_height` | 0.9 | 项目值，无原版对应 |
| `slide_crawl_speed` | 2.5 | 项目值，**保留**：防卡死措施，不是手感机制 |

**`CrouchConfig`** — `speed_modifier 0.4`（✅ `CrouchedPct`；不取 `TdMove_Crouch.SpeedModifier 0.2`，理由见现有 `movement_config.gd` 的原注释：`CrouchedPct` 在两节独立确证，`0.2` 只在裸参数转储里出现一次）。

**`WallRunConfig`**（数值全部 ✅）

| 字段 | 值 |
|---|---|
| `wall_running_min_speed` | 2.0（现为 5.0） |
| `wall_running_velocity_start_limit` | 3.0 |
| `wall_running_min_wall_height` | 1.92 |
| `wall_running_forward_max_start_angle` | 57° |
| `wall_running_strafe_start_angle` | 60° |
| `wall_running_forward_check_distance` | 0.5（现 `wall_reach` 0.75） |
| `wall_running_strafe_check_distance` | 0.5 |
| `wall_running_horisontal_friction` | 0.05 |
| `wall_running_horisontal_acceleration` | 8.2 |
| `wall_running_horisontal_deceleration` | 5.0 |
| `wall_running_horisontal_initial_z_height` | 1.7（⚠️ 读作进入时一次性抬升） |
| `wall_running_horisontal_align_speed` | 7.0 |
| `wall_running_velocity_stop_limit` | -5.0（⚠️ 读作垂直下沉速度到此退出） |
| `rotate_pawn_along_wall_time` | 0.4 |
| `time_to_do_90_turn` | 0.25 |
| `redo_move_time` | 0.15 |
| `min/max_look_constraint` | pitch ±71.4°、yaw ±90°，`absolute_yaw_constraint = true` |

**没有时长上限。** 时长由动量决定——跑得越快贴得越久（[04.1](../../mirrors-edge-deep-research/04-墙面动作.md)）。

**`WallrunJumpConfig`**（独立 Move，原版就是独立类）

| 字段 | 值 |
|---|---|
| `wall_running_push_away_speed_noob` | 1.2 ✅ |
| `wall_running_push_away_speed_pro_add` | 4.0 ✅ |
| `wall_running_push_forward_speed_min` | 0.1 ✅ |
| `wall_running_jump_off_z_height_forward` | 1.0 ✅（高度） |
| `wall_running_jump_off_z_height_max_add_turned` | 0.6 ✅（高度） |

**`SpeedVaultConfig`** — 变体数组，[05.7](../../mirrors-edge-deep-research/05-动作库总览.md) 的表原样转公制：

| 变体 | 高度 m | 落点 | v_z | v_xy | 时长 s | 速度结果 | `max_distance_time` | 连携 |
|---|---|---|---|---|---|---|---|---|
| `auto_step_up_right_leg` | 0–0.48 | onto | −6.0 ~ 0 | 1.0–3.0 | 0.50 | — | 0.2 | — |
| `step_up_right_leg_88` | 0.48–1.48 | onto | 0 ~ 7.0 | 动量 ≤ 2.0 | 0.65 | — | 0.4 | — |
| `vault_onto` | 0.64–1.48 | onto | 0 ~ 100 | ≥ 4.0 | 0.65 | **+0.8** | 0.4 | ✅ |
| `vault_over` | 0.64–1.48 | over | 0 ~ 100 | ≥ 4.0 | 0.65 | **+0.8** | 0.4 | ✅ |
| `vault_over_high` | 1.45–1.92 | over | ≥ 0.5 | 钳到 2.0–4.0 | 1.03 | 净降速 | 0.4 | — |
| `vault_onto_high` | 1.45–1.92 | onto | ≥ 0.5 | 钳到 2.0–4.0 | 1.17 | 净降速 + 重置镜头 | 0.4 | — |

另：`clamp_speed_max 7.2`、`vault_clear_object_height 0.35`、`max_time_to_ledge 0.4`、`ledge_offset_z` 逐变体 `0.9 / 0.6 / 0.25 / 0.25 / 0.05 / 0.35`。

**`GrabConfig`**（ledge hang / pull up）— `min_wall_height 1.8` ✅、`ledge_find_distance 3.5` ✅、`min_ledge_z_normal 0.707` ✅。

---

## 5. 判定逻辑

### 5.1 速度能量

**累积**（⚠️ 方向未经字节码验证，[02.1](../../mirrors-edge-deep-research/02-速度系统.md) 明说）：

```
dE/dt = 当前模式 factor / sprint_factor
  常规奔跑（无修饰键） → 30/30 = 1.0   → 恰好 7 秒爬满，与曲线 X 轴终点及社区实测「7–10 秒」双向吻合
  纯侧移              → 10/30 = 0.33
  按住走路修饰键       →  7/30 = 0.23
```

⚠️ **项目自加的守卫**：仅当 `horizontal_speed ≥ cap() × energy_accumulate_speed_ratio(0.9)` 时才累积。原版无此参数，但没有它则「按住 Ctrl 慢走 7 秒」或「顶着墙推 7 秒」都能攒满能量，一松手立刻拿到 7.2 的上限——那与「速度是需要跑出来的资产」直接矛盾。

**衰减**：把 `speed_energy_deceleration_exponent = 0.5` 当字面指数用，系数由 `speed_energy_deceleration_time = 3` 反解——

```
dE/dt = -k · E^0.5 ,  k = 2·√E_max / T = 2·√7 / 3 ≈ 1.7638
```

满能量恰好 3 秒清零，形状是「刚停下来掉得快、接近零掉得慢」，与 [03.2](../../mirrors-edge-deep-research/03-损速机制.md) 的描述一致。

**转向损速**（❓ `SpeedTurnDecelerationFactor = 10` 单位不可证）：

```
E -= speed_turn_deceleration_factor × |Δθ|
```

`Δθ` 取 **`wish_dir` 的变化角**，不取相机 yaw（转头看路不该花钱，转行进方向才花钱），也不取速度方向（`accel_rate` 61.44 会让速度方向滞后于意图）。`wish_dir` 为零向量的进出不计（否则松开再按方向键会被误判为转向）。仅在 grounded 时计。

默认值 **2.23** 由行为标定而非照抄：一次 180° 完全掉头（π 弧度）花光全部 7.0 能量。90° 转向花掉一半。原始的 10 记录在 doc comment 里。验收观察点是社区的「3-step Rule」（[03.2](../../mirrors-edge-deep-research/03-损速机制.md)）。

**曲线插值**：默认 `LINEAR`，与原版确证的 `CIM_Linear` 一致。另提供 `SMOOTH` 模式作为可切换的手感变体——

```
v(E) = A·(1 - e^(-E/a)) + B·(1 - e^(-E/b))
```

四个系数由五个确证点**在运行时拟合**（不写死），实测残差量级 1e-14，即精确通过全部五点。已测得的系数为 `A=4.422, a=0.2320, B=3.133, b=3.2169`（渐近 7.556，必须钳到 `ground_speed`）。

选择这条而非其他拟合族的理由：它是唯一在全部五个确证点上零偏差的，切换它只改变点与点**之间**——恰好是原始数据本来就没有约束的区域。已测得的差异：

- 拐点之间最大偏离 **+0.76 m/s（在 E=0.17）**，即起跑头 0.4 秒明显更冲。这不是"平滑一点"，是一个真实的手感变体。
- 因为 `accel_rate 61.44` 远大于曲线任何一段斜率（最大 10.0），实际加速度**完全由曲线斜率决定**。分段线性在 E=0.4 处有 10.0 → 2.0 的 5 倍加加速度跳变，E=1.0 处 2.0 → 0.52，E=3.5 处 0.52 → 0.20；`SMOOTH` 全程连续。拐点是否读成「换挡」是经验问题，F1 面板一键 A/B。

被明确排除的拟合族（实测 RMSE，uu/s）：单指数 37.9、双曲 16.1、幂律 14.0、对数 6.69、Hill 3.48、`A·E/(E^p+k)` 1.46。**单指数被数据明确否定**——尾巴远比指数衰减重，这正是「越快越难快」的数学来源。

### 5.2 落地四档

落地时读 `FallTracker.fall_height`，**不读 `velocity.y`**：

```
h < 2.0                    → 零惩罚          （跳跃 apex 1.96 m，平地跳永远免罚）
2.0 ≤ h < 3.0              → 软着陆，roll 可完全化解
3.0 ≤ h < 5.3              → 需要 roll；不 roll 显著损速，roll 后仍有轻微损速 📣
h ≥ 5.3                    → 硬着陆：保留 35%（本项目无血量，跳过 HardLandingDamage）
```

📣 [03.1](../../mirrors-edge-deep-research/03-损速机制.md)：ME1 的 skill roll 本身会损速，但只在翻滚后继续向前移动时才掉速。

### 5.3 下蹲键的上下文解析（本质机制⑥）

[05.2](../../mirrors-edge-deep-research/05-动作库总览.md) 的确证表，一个键五个出口，判据只有三个（在空中还是落地瞬间、水平速度、累计下落高度）：

| 状态 | 条件 | 结果 |
|---|---|---|
| 空中 | 水平速度 ≥ 1.0 | Coil（**本次排除**，无此动作） |
| 空中 | 水平速度 < 1.0 | 无动作 |
| 落地瞬间 | `fall_height ≥ 2.0` | **Roll** |
| 落地瞬间 | `fall_height < 2.0` 且有水平速度 | **Slide** |
| 地面 | 无水平速度 | **Crouch** |

单一缓冲窗口 `roll_trigger_time = 1.0`，分支在落地时按上表解析。取代现有的 `crouch_buffer_time = 0.15` 与散在 `GroundState` / `AirState` 里的两套判定。

### 5.4 Vault 变体选择与时间前瞻

```
每帧前向探测 → t = hit.distance / horizontal_speed
若 t ≤ variant.max_distance_time → 用【此刻】的速度向量查变体表 → 匹配则立即转移
```

需要 [`probes.gd`](../../../scripts/player/probes.gd) 新增两样现在没有的东西：命中**距离**，以及 `check_for_vault_over` 用的「障碍对面有没有落脚地」探测。

前瞻窗口速度归一化的直接后果：4.0 m/s 时前瞻 1.6 m，7.2 m/s 时前瞻 2.88 m。「越快越流畅」是这个机制的产物，不需要额外调参。

❓ 多个变体同时匹配时的优先级需要字节码才能确定（[05.7](../../mirrors-edge-deep-research/05-动作库总览.md) 明说）。按**数组顺序 + 首个匹配**实现，顺序即 4.3 的表——高速甜区排在慢速档之前，使「跑得快解锁更好的动作」成立。

代价是「锁定即提交」：锁定后玩家改输入也不撤销。这与原版「起跳质量决定一切」的整体设计一致。

### 5.5 墙面

**进入**：入射角 0–57° 走 forward 分支，≥60° 走 strafe 分支（57°–60° 的 3 度缝隙是迟滞带，保留）。现在完全没有角度判定，只看侧向射线是否命中。

**维持**：沿墙加速度 8.2、减速度 5.0、摩擦倍率 0.05；重力按 `wall_gravity_scale` 削弱（项目值，原版用 `HorisontalFriction` + `Deceleration` 表达，⚠️ 模型不同）。

**退出**：横向速度 < `wall_running_min_speed(2.0)`，或垂直速度 < `wall_running_velocity_stop_limit(-5.0)`，或触地。**无时长上限。**

**墙跳的技巧梯度**（[04.4](../../mirrors-edge-deep-research/04-墙面动作.md)，本研究的头号建议）：

```
f = clamp(-look_forward · wall_normal, 0, 1)        # 越正对所贴的墙，f 越大
push_away = noob(1.2) + pro_add(4.0) × f            # 4.3 倍区间
jump_off_z_height = forward(1.0) + max_add_turned(0.6) × f
vertical_velocity = √(2 · gravity · jump_off_z_height)   # 4.0 ~ 5.06 m/s
```

⚠️ 插值依据 `f` 参数名未说明，但 04.4 结合社区实测「贴墙跑时尽量正面朝向所贴的墙再跳会获得显著速度增益」几乎可以确定是离墙瞬间视线与墙面法线的夹角。

**镜头约束**：pitch ±71.4°、yaw ±90°、`absolute_yaw_constraint = true`。这是「贴墙时镜头自动看向前进方向」体感的来源——是输入约束，不是动画效果。

### 5.6 待修：贴墙滚转方向反了

📣 **所有者试玩报告**：贴左墙时镜头逆时针旋转，应为顺时针。

这不是实现 bug，是**设计意图搞反了**——代码正确地实现了一个错误的意图。[`camera_rig.gd:190`](../../../scripts/camera/camera_rig.gd)：

```gdscript
var target_roll := -deg_to_rad(_config.wall_camera_roll_deg) * float(_wall_side)
```

那个负号是刻意加的，配套的注释与 `tests/test_camera_rig.gd` 的 `test_the_camera_rolls_toward_the_wall_side` 都明确把意图声明为「**向墙的方向倾**」（左墙 `wall_side = -1` → `rotation.z` 为正 → up 向量倒向 −X → 从玩家视角看是逆时针）。所有者观察到的现象与代码完全一致，即报告准确。

**修法**：去掉那个负号，同时改写注释与测试所声明的意图（现在写的是「向墙倾」，要改成「背墙倾」）。只改符号不改这两处，会留下一段与行为相反的文档。

⚠️ **一处需要所有者知情的冲突**：[09.1](../../mirrors-edge-deep-research/09-Godot移植指南.md) 的相机小节写着「wallrun 的 camera roll（你的 `wall_camera_roll_deg = 14`）方向正确 ✅」。但同一节也说明**原版配置里根本没有这个字段的值**——那个 ✅ 是研究作者的判断，不是提取出来的数据。所以这里没有可援引的原版依据，以所有者的实际观感为准。

---

## 6. 删除清单（自创机制）

以下全部删除，它们是本项目自创的、原版没有对应物的抽象：

| 删除项 | 位置 | 取代者 |
|---|---|---|
| `slide_boost` / `slide_boost_entry_threshold` | `SlideState.enter()` | 无。原版滑铲无任何加速 |
| `slide_friction`（绝对值） | `SlideState._slide()` | `friction_modifier 0.1` 倍率制 |
| `slide_slope_accel` / `slide_max_speed` | 同上 | 上/下坡摩擦倍率 5.0 / 1.8 |
| `land_cost_speed_ref` / `land_speed_keep` / `roll_speed_keep` / `roll_min_fall_speed` | `AirState._apply_landing_cost()` | 累计下落高度四档 |
| `wall_max_duration` | `WallRunState` | 速度衰减自然结束 |
| `wall_jump_up` / `wall_jump_push`（常数） | 同上 | Noob/ProAdd 梯度 |
| `wall_reattach_cooldown` / `wall_same_normal_dot` / `_recent_walls` | `Player` + `WallRunState` | `redo_move_time 0.15` |
| `WallRunState._height_ceiling()`（约 40 行连跳限高） | `WallRunState` | 无。见 8. 风险 |
| `wall_accel` / `wall_max_speed` / `wall_exit_speed` | 同上 | 原版对应字段 |
| `vault_speed_keep` / `vault_duration` / `vault_min_speed` / `vault_reach` | `VaultState` + `Probes` | 6 变体表 + 时间前瞻 |
| `ledge_regrab_cooldown` | `Player` | `redo_move_time` |
| `air_accelerate()` 的减速守卫（`player.gd:900-901`） | `Player` | 无。原版是标准低空中操控，「跳出去就得认」来自 `AirControl = 0.025` 而非禁止刹车；`air_accel` 已经只有 1.536，满滞空顶多刹掉 2.1 m/s |
| `sprint_speed` 概念残留 / `pitch_limit_deg` 全局单值 | 多处 | 速度曲线 / 按 Move 的镜头约束 |

保留但需说明：`coyote_time 0.12` / `jump_buffer_time 0.12`（原版未找到对应参数，作为现代 QoL 保留）、`floor_snap_speed`（Godot 的 `move_and_slide()` 需要，原版 `PHYS_Walking` 自带）、`slide_crawl_speed`（防卡死）。

---

## 7. 未确证项与我们的读法

每一条都是**我们必须做出选择、而数据无法裁决**的地方。日后若有新证据，改这里。

| # | 原始数据 | 可信度 | 我们的读法 | 若判断错的代价 |
|---|---|---|---|---|
| 1 | `LandingSpeedReduction = 65` | ❓ 研究称「本手册最重要的一处 ❓」 | 损失 65%（保留 0.35） | 硬着陆过重或过轻；单参数可调 |
| 2 | `SpeedTurnDecelerationFactor = 10` | ⚠️ 单位不可证 | 弃用原值，按「180° 掉头花光全部能量」标定为 2.23 能量/弧度 | 转向代价整体偏离；单参数可调 |
| 3 | 三个 `Speed*AccelerationFactor` 的方向 | ⚠️ 未经字节码验证 | 除以 `sprint_factor` 归一，常规奔跑 = 1.0 | 若方向相反，则走路攒能量最快——明显荒谬，故取此读法 |
| 4 | `SpeedEnergyDecelerationExponent = 0.5` | ⚠️ 公式写法未知 | 当作 `dE/dt = -k·E^0.5` 的字面指数 | 衰减形状不同；形状与 03.2 的文字描述一致，故取此读法 |
| 5 | `RollTriggerTime = 1.0` | ⚠️ 语义未证 | roll 的输入预缓冲窗口 1.0 秒 | 极宽容；与社区「skill roll 时机很宽松」一致 |
| 6 | `WallRunningVelocityStopLimit = -500` | ⚠️ 负值语义 | 垂直下沉速度到 -5.0 退出 | 墙跑时长偏差 |
| 7 | `WallRunningHorisontalInitialZHeight = 170` | ⚠️ | 进入时一次性抬升 1.7 m | 贴墙起始高度偏差 |
| 8 | WallrunJump 的 `f` 插值依据 | ⚠️ 参数名未说明 | 视线与墙面法线的夹角 | 技巧梯度的触发条件错位；与社区实测吻合，故取此读法 |
| 9 | `JumpAddXY = 100` | ⚠️ 加法还是设为最小值 | 加法 | 起跳前冲略强 |
| 10 | Vault 多变体同时匹配的优先级 | ❓ 需字节码 | 数组顺序 + 首个匹配，高速档在前 | 高速时可能误选慢速变体 |
| 11 | `SpeedMaxBaseVelocity = 400` 的角色 | ❓ | 记录不使用 | 无 |
| 12 | `TdPawn.Friction` 基数 | 研究未提取到 | 沿用本项目 40.0 | 整体刹车手感；需试玩定 |

另有一条**必然的偏差，无法消除**：原版是 UE3 变步长物理且锁 62 FPS，📣 社区实测帧率升高会改变玩家 friction。Godot 固定 tick 更稳定但**必然不完全一致**（[09.2](../../mirrors-edge-deep-research/09-Godot移植指南.md)、[03.6](../../mirrors-edge-deep-research/03-损速机制.md)）。这是移植必须接受的。

---

## 8. 已知风险

**墙面连跳可能变成无限爬升。** 按 1:1 删掉 `wall_reattach_cooldown` 和 `_height_ceiling()` 之后，zig-zag 双墙连跳失去了本项目原有的两道护栏。原版靠 `RedoMoveTime = 0.15` + 速度衰减 + wallclimb 分流约束，而我们**排除了 wallclimb**。

决定：**先按 1:1 做，不预先加护栏**，试玩发现能爬上天再补。这符合「推翻现有机制、更贴合原版」的方向，但中间可能出现一个能爬上天的版本。

**第二个风险**：`base_friction` 与 `energy_accumulate_speed_ratio` 是两个原版无对应的自由参数，它们会影响几乎所有状态的手感，且只能靠试玩定。

---

## 9. 迁移与测试策略

所有者的选择：先全面重做，**先不管现有测试**。

- 现有 22 个测试文件整体移到 `tests/legacy/`（**不删**），`tools/run_tests.ps1` 不跑它们。其中相当一部分锚定在即将删除的机制上（`slide_boost` 的三个用例、`wall_max_duration`、`_height_ceiling` 的连跳限高、`land_speed_keep` 的斜坡），本来就该退役；其余（`test_probes` / `test_arena` / `test_state_machine` / `test_body_attachment`）是之后重写时的现成参照。
- `tests/test_case.gd` 与 `tests/world_fixture.gd` 作为基础设施留在原地继续用。
- 新架构下只补**纯函数断言**（几乎零成本，且是唯一能自动验证的部分）：速度曲线五点插值、`SMOOTH` 模式在五点上的零偏差、能量衰减 3 秒清零、落地四档分界、Noob/ProAdd 梯度端点、6 变体表的查表选择、摩擦倍率链。
- 物理层的回归测试等手感定下来之后再成批补。

**只有所有者能回答的问题**：跑起来爽不爽。本设计能自动验证的只有数值关系与状态机逻辑。
