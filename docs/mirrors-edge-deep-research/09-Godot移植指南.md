# 09 · Godot 移植指南

← [README](README.md) · 上一篇 [08-速通社区交叉验证](08-速通社区交叉验证.md)

本章把前面的逆向数值落到本项目的实际代码上，**逐字段对照 `scripts/player/movement_config.gd`**。

---

## 单位换算

**1 uu = 1 cm**，即 `m/s = uu/s ÷ 100`。

三条独立证据：

1. 📣 社区实测最高跑速 16 mph / 26 km/h，与 `GroundSpeed = 720` 在 1 uu = 1 cm 下的 25.92 km/h 吻合（见 [08.1](08-速通社区交叉验证.md#81--精确吻合可信度最高)）
2. ✅ `CrouchHeight = 40`（半高）→ 蹲下总高 80 uu = 0.8 m，合理
3. ✅ `MaxStepHeight = 35` → 0.35 m 台阶，合理（若按 1 uu = 2 cm 则是 0.7 m，荒谬）

⚠️ 注意 UE3 **没有**统一的单位比例：官方文档说 UT 系列用 1 uu = 2 cm，"多数被授权方"用 1 uu = 1 cm，而 Gears of War 用 ≈1.27 cm。所以不能套用别的 UE3 项目的换算。

⚠️ Epic 同时警告：引擎常数是按默认比例调的，**偏离超过 2 倍会有难以追踪的副作用**。也就是说 UE3 的移动行为**不是尺度无关的**——这也是为什么直接照搬数值到 Godot 不一定得到相同手感，见下方"物理模型差异"。

---

## 9.1 逐字段对照

下表把 ME 的确证值换算成 m/s 后，与本项目 `movement_config.gd` 的当前默认值并列。

### Ground / Air / Jump

| `movement_config.gd` | 当前值 | ME 对应值 | 差异 |
|---|---|---|---|
| `walk_speed` | 5.0 | `JogVelocity 260` → **2.6** / `RunVelocity 400` → **4.0** | 偏快 |
| `sprint_speed` | 9.0 | `GroundSpeed 720` → **7.2** | **偏快 25%** |
| `ground_accel` | 60.0 | `AccelRate 6144` → **61.44** | ✅ **几乎完全一致** |
| `ground_friction` | 40.0 | ❓ 无直接对应（ME 用摩擦力倍率体系） | — |
| `air_accel` | 12.0 | `AirControl 0.025` × 加速度 | ME 空中操控极低 |
| `air_max_speed` | 9.0 | `AirSpeed 2400` → **24.0** | **ME 基本不限空中速度** |
| `gravity` | 24.0 | `DefaultGravityZ 800` → **8.0** | ⚠️ **相差 3 倍** |
| `jump_velocity` | 7.5 | `BaseJumpZ 560` → **5.6**（实测确认，见 [02.4](02-速度系统.md#24-重力与跳跃)） | — |
| `coyote_time` | 0.12 | ❓ ME 中未找到 | — |
| `jump_buffer_time` | 0.12 | `RollTriggerTime = 1.0`？⚠️ 语义未证 | — |

🔶 **推导出的实际跳跃形态对比**（这才是手感差异的真身）：

| | 本项目 | 镜之边缘 | 倍数 |
|---|---|---|---|
| 跳跃最高点 | 1.17 m | **1.96 m** | 1.7× |
| 上升时间 | 0.31 s | **0.70 s** | 2.2× |
| 平地总滞空 | 0.63 s | **1.40 s** | 2.2× |
| 满速平跳水平距离 | 5.6 m | **10.1 m** | 1.8× |

**这是本项目与镜之边缘最大的一处分歧。** 镜之边缘跑得**更慢**（7.2 vs 9.0），但跳得**远将近两倍**——因为重力只有你的三分之一。那种"在空中有时间看清落点、判断"的从容感，来自 1.40 秒的滞空，不是来自速度。

同时 ME 用 `AirControl = 0.025`（极低）把这段滞空锁死：**给你很长的时间，但几乎不给你修正的能力**。这个组合是刻意的——起跳质量决定一切，空中只能等待结果。你当前的 `air_accel = 12.0` + `air_max_speed = 9.0` 是相反的取舍（滞空短、可修正）。

⚠️ **注意一处参数咬合**：ME 的跳跃最高点 1.96 m 卡在 `SkillRollLandingHeight = 2.00 m` **下方 4 cm**——平地跳跃永远不触发翻滚，也不触发任何落地惩罚（`SoftLandingHeight = 3.00 m`）。移植时若照抄 `land_*` 阈值却用了更高的跳跃，会导致**每跳一次都掉速**，游戏立刻不能玩。**这三组数必须一起校准。**

**建议**：如果目标是镜之边缘手感，先试 `gravity: 24.0 → 8.0`、`jump_velocity: 7.5 → 5.6`、`sprint_speed: 9.0 → 7.2`，然后把 `air_accel` 往下压，最后确认 `roll_min_fall_speed` 对应的高度仍高于新的跳跃最高点。这几个数一起改才有意义，单改任何一个都会更糟。

### Landing

| `movement_config.gd` | 当前值 | ME 对应值 | 差异 |
|---|---|---|---|
| `land_cost_speed_ref` | 18.0 | `HardLandingHeight 530` → 落地速度 **9.21** | 你的阈值高一倍 |
| `land_speed_keep` | 0.55 | `LandingSpeedReduction = 65` ❓单位未证 | 若"保留 65%"则你更严厉 |
| `roll_speed_keep` | 0.94 | ME 的 roll **仍会损速**（向前移动时） | 你更宽容 |
| `roll_min_fall_speed` | 5.0 | `SkillRollLandingHeight 200` → **5.66** | ✅ **很接近** |

ME 的三段阈值换算成落地垂直速度：**5.66 / 6.93 / 9.21 m/s**（对应 2.0 / 3.0 / 5.3 m 落差）。你的 `roll_min_fall_speed = 5.0` 几乎踩在第一档上，很准。

⚠️ **强烈建议补上的一件事**：ME 的落地惩罚基于**"自上次触地以来的累计下落高度"计数器**，不是当帧的 `velocity.y`。这个差别是 [03.5](03-损速机制.md#35-绕过损速的社区技巧机制原理) 里一整层速通技巧的来源。改成计数器几乎零成本，却能凭空长出一层技巧空间。

### Slide

| `movement_config.gd` | 当前值 | ME 对应值 | 差异 |
|---|---|---|---|
| `slide_boost` | **2.5** | ME **没有任何滑铲加速** | ⚠️ **设计分歧** |
| `slide_friction` | 5.0 | `FrictionModifier = 0.1`（倍率制） | 模型不同 |
| `slide_exit_speed` | 2.0 | `SlideAbortSpeed 250` → **2.5** | ✅ 接近 |
| `slide_max_duration` | 1.8 | `SlideAbortTime = 2.0` | ✅ 接近 |
| `slide_slope_accel` | 22.0 | `UpwardSlideFrictionScale=5.0` / `Downward=1.8` | ME 用坡度调制摩擦而非加速 |

**这是一处真正的设计分歧，不是调参问题。** 你的滑铲是**净收益**（`slide_boost = 2.5` 的一次性奖励），镜之边缘的滑铲是**净损失**——社区公认它是全游戏最慢的动作，只在踢门和矮管道有价值（[05.1](05-动作库总览.md#51-slide滑铲)）。

你的注释里已经把它设计成"用速度换爆发"的交换（`slide_boost_entry_threshold`），思路是自洽的。**只是要知道这一条让你偏离了原作**：在 ME 里，玩家学到的是"别乱滑"；在你的版本里，学到的是"多滑"。哪个更好是设计取舍，但它会改变整个关卡的最优解形态。

ME 的坡度处理值得抄：`UpwardSlideFrictionScale = 5.0` vs `DownwardSlideFrictionScale = 1.8`——**上坡滑铲摩擦力 5 倍，几乎立刻停死**。这比单一的 `slide_slope_accel` 更能表达"下坡是奖励、上坡是惩罚"。

### Wall Run

| `movement_config.gd` | 当前值 | ME 对应值 | 差异 |
|---|---|---|---|
| `wall_min_speed` | 5.0 | `WallRunningMinSpeed 200` → **2.0** | 你严格得多 |
| `wall_max_duration` | 1.5 | ME **没有时长上限** | ⚠️ 模型分歧 |
| `wall_jump_up` | 6.5 | `JumpOffZHeightForward 100` + `MaxAddTurned 60` | 单位语义不同 |
| `wall_jump_push` | **6.0（常数）** | **`Noob 120` → `Pro 520`，即 1.2 → 5.2** | ⚠️ **最重要的一条** |
| `wall_reattach_cooldown` | 0.5 | `TdMove_WallRun.RedoMoveTime = 0.15` / `WallKick = 1.0` | ME 区分不同动作 |
| `wall_camera_roll_deg` | 14.0 | ❓ ME 配置中未找到 | — |
| `wall_gravity_scale` | 0.35 | `HorisontalFriction 0.05` + `Deceleration 500` | 模型不同 |

⭐ **`wall_jump_push` 是本手册给你的头号建议。**

你现在给的是常数 6.0。镜之边缘给的是一个 **120 → 520 uu/s（1.2 → 5.2 m/s）的 4.3 倍区间**，DICE 直接把参数命名为 `Noob` 和 `ProAdd`，插值依据几乎可以确定是离墙瞬间玩家视角与墙面的夹角（[04.4](04-墙面动作.md)）。

**这一个改动可能是"像不像镜之边缘"的最大单点杠杆。** 它让同一个按键在不同执行质量下产生天差地别的结果，不需要额外按键、不需要教学、不需要 UI——技巧梯度直接长在动作里。改法：

```gdscript
@export var wall_jump_push_min: float = 1.2   # 执行最差
@export var wall_jump_push_bonus: float = 4.0 # 执行最好时的加成
# 实际推力 = min + bonus * f(离墙瞬间视线与墙法线的夹角)
```

另一处：`wall_max_duration = 1.5` 的硬性时限 vs ME **完全没有时长上限**——ME 的 wallrun 靠 `WallRunningVelocityStopLimit = -500` 的速度衰减自然结束。**跑得越快贴得越久**，这本身就是对速度的奖励。硬时限则让速度在墙上不产生任何回报。

### Camera / 感知层

| `movement_config.gd` | 当前值 | ME 对应值 | 差异 |
|---|---|---|---|
| `eye_height` | 0.7 | `BaseEyeHeight 76` → **0.76**（相对碰撞体中心） | ✅ 接近 |
| `fov_base` / `fov_max` | 75 / 95 | ME **固定 90°**，无速度 FOV | ⚠️ **分歧** |
| `fov_speed_ref` | 9.0 | ME 唯一的动态 FOV 是 Vertigo：90° → **84°**（缩小） | — |
| `bob_frequency` / `bob_amplitude` | 1.6 / 0.055 | DICE **移除了 head bob** | ⚠️ **分歧** |
| `pitch_limit_deg` | 89.0 | wallrun 时 ME 限制到 **±71.4°**，yaw **±90°** | ME 按状态限制视角 |

⚠️ **两处需要认真考虑的分歧**：

1. **速度 FOV**：你有 75→95 的速度驱动 FOV。ME **固定 90°**——DICE 的一手说明是把 FOV 开到"画面开始弯曲之前"的最大值然后**不动它**，速度感来自摄像机运动而非视野缩放。ME 唯一的动态 FOV 是站在高处边缘时**缩小**到 84°（恐高效果）。
2. **head bob**：你有 `bob_frequency = 1.6` / `bob_amplitude = 0.055`。ME **没有任何程序化 bob 参数**——2031 个 CDO 里搜不到幅度/频率，相机变换取自 `CalcCamera()` 里的 `CameraAnimLocation` / `CameraAnimRotation`，即**动画数据**。DICE 在开发过程中移除了 head bob，目标重述为「从你的**眼睛**看世界，而不是从你的**头**」。完整证据见 [05.10](05-动作库总览.md#510-相机晃动没有程序化-head-bob)。

ME 里唯一等价于"晃动强度"的是 `CameraAnimMomentumInfluence = 0.0001`——**动量对相机动画的耦合系数**，幅度被 `CameraForwardMax = 0.50 m` / `CameraDownwardMax = 0.40 m` 钳住。「频率」则等于步频，由动画混合时间控制，没有独立参数。

⚠️ 而且 `TdSkelControlSpring` 里 `EnableVelocityDependedTranslationSpring = FALSE`、`EnableAccelerationBased = FALSE`——**DICE 试过程序化摇晃然后关掉了**，留下的弹簧只用于武器摇摆。

这两条不是说你错了——速度 FOV 是现代第一人称跑酷的通用语汇（Titanfall、Ghostrunner 都用）。但如果目标是"镜之边缘-like"，**原作明确拒绝了这两个手段**，而用了别的东西：

- 专用第一人称 rig（脊椎/颈/肩驱动摄像机）
- 落地 dip（你的 `land_dip_*` 方向正确 ✅）
- wallrun 的 camera roll（你的 `wall_camera_roll_deg = 14` 方向正确 ✅）
- roll 时的**芭蕾 spotting**：头部甩转后**回到与触发前完全相同的注视方向**——不是自由跟随身体旋转
- 中央焦点白点作为防晕锚点

⚠️ 你的 `camera_head_follow_strength = 0.15` 的注释里担心"完全跟随头骨节点会让人晕"——**DICE 用 15 秒就验证了同样的结论**并推翻了那套方案。你的低默认值是对的。

### Vault / Ledge

| `movement_config.gd` | 当前值 | ME 对应值 | 差异 |
|---|---|---|---|
| `vault_max_height` | 1.3 | 甜区 `64–148 uu` = **0.64–1.48 m** | ✅ 吻合 |
| `vault_min_speed` | 2.5 | `ClampSpeedMin 400` → **4.0** | — |
| `vault_speed_keep` | **0.85（损失）** | 甜区内 `SpeedAddition = 80` → **+0.8 m/s（奖励）** | ⚠️ 符号相反 |
| `ledge_min_height` / `max` | 1.4 / 2.8 | `MinWallHeight 180`、`LedgeFindDistance 350` | — |
| `min_walkable_normal_y` | 0.7 | `WalkableFloorZ = 0.71` | ✅ **几乎一致** |

⚠️ **这里有两处结构性差异，不只是数值。**

**差异一：ME 有 6 个 vault 变体，你有 1 个。**

你的 `vault_duration = 0.32` 是单一常数，`vault_speed_keep = 0.85` 也是。ME 按 5 个轴（高度 / onto-vs-over / 垂直速度方向 / 水平动量 / 距离时间窗口）在 6 个变体里选，时长从 **0.50 s 到 1.17 s**，速度结果从 **+80 uu/s 奖励**到**钳到 200–400 的净降速**。完整表见 [05.7](05-动作库总览.md#57-vault翻越)。

注意你的 0.32 s **比 ME 最短的变体还快 36%**——配合 `vault_speed_keep = 0.85` 的损速，你的翻越是"快而亏"，ME 甜区的翻越是"慢而赚"。

**差异二：ME 用速度决定播哪个动作，你用速度决定能不能翻。**

你的 `vault_min_speed = 2.5` 是一个开关（够快就能翻）。ME 在同一高度区间放了两个候选，靠动量分流：

```
动量 ≤ 200 (2.0 m/s)   → stepuprightleg88，慢，无奖励
速度 ≥ 400 (4.0 m/s)   → vaultOnto/Over，+80 uu/s 奖励，且可连携
```

**这一条比数值本身更值得抄**：它让"跑得快"在翻越环节获得**可见的、动画层面的**回报，而不只是数字上的。玩家能一眼看出自己这次翻得漂不漂亮。

**建议**：把 `vault_duration` / `vault_speed_keep` 从标量改成按变体查表，最少分三档：

```gdscript
# 低（0–0.48 m）：迈上去，无手，0.5 s
# 甜区（0.64–1.48 m）+ 高速进入：单手速翻，0.65 s，速度 +0.8 m/s，可连携
# 高（1.45–1.92 m）：必须起跳，双手，1.0–1.17 s，速度钳到 2.0–4.0 m/s，重置镜头
```

⚠️ 另外 ME 的高档 vault 要求 `MinSpeedZ = 50`——**必须已经起跳且仍在上升**才触发。这让"高障碍要按跳跃键"成为一条玩家能内化的规则，而不是靠自动吸附。

**差异三：判定用「到达时间」前瞻，不是接触检测。**

ME 的 `MaxDistanceTime = 0.2/0.4`、`MaxTimeToLedge = 0.4` 都是**秒**（详见 [05.7](05-动作库总览.md#-判定发生在接触前-0204-秒不是接触瞬间)）。动作在**接触前 0.2–0.4 秒**就锁定，用的是那一刻的速度向量。

你的 `vault_reach = 1.4` 是固定距离。改成时间前瞻只是几行：

```gdscript
var hit = probes.vault_query()
if hit:
    var t = hit.distance / maxf(horizontal_speed, 0.01)
    if t <= vault_lookahead_time:               # 0.2 / 0.4
        var v = pick_variant(hit.height, hit.has_landing_beyond,
                             velocity.y, horizontal_speed)
        if v: enter_vault(v)                     # 还剩 0.4 s 做动画混合
```

**三点收益**：

1. **前瞻距离自动随速度缩放**——720 uu/s 时前瞻 288 uu，400 uu/s 时只有 160 uu。「越快越流畅」是这个机制的直接产物，不需要额外调参。你的固定 `vault_reach` 在高速时会显得触发太晚、低速时太早。
2. **拿到的是干净的速度向量**——接触瞬间速度已被碰撞改变，法线和位置也会抖。
3. **有 0.4 秒做动画混合**——接触后才判定必然生硬。

代价是要接受"锁定即提交"（锁定后玩家改输入也不撤销）。ME 看起来正是这么做的，这与它"起跳质量决定一切"的整体设计一致。

**关卡设计规范**：把障碍做成 **0.64–1.48 m**，玩家全速通过还能加速；想给高速段落打个逗号，就放一个 **1.5 m 以上**的。

---

## 9.2 UE3 → Godot 物理模型差异

| 差异 | 说明 | 影响 |
|---|---|---|
| **变步长 vs 固定步长** | UE3 按帧长积分；ME 默认锁 **62 FPS**，📣 社区实测**帧率升高会提高玩家 friction**，>150 FPS 时下坡滑铲几乎无法控制 | ME 的手感部分是**帧率相关的产物**。Godot 固定 tick 会更稳定但**必然不完全一致**——这是必须接受的偏差 |
| **坐标系** | UE3 Z-up；Godot Y-up | 换算时注意 `DefaultGravityZ`、`JumpZ`、`*ZHeight` 都是 Z 轴 |
| **角度单位** | UE3 用 65536 = 360° 的整数角 | `MinLookConstraint = 13000` → 13000/65536×360 = **71.4°** |
| **移动求解** | UE3 有自己的 `PHYS_Walking`；Godot 是 `CharacterBody3D.move_and_slide()` | 台阶/斜坡行为不同。ME 的 `MaxStepHeight = 35` → 0.35 m，对应 Godot 的 `floor_max_angle` / 手动台阶探测 |
| **可行走坡度** | `WalkableFloorZ = 0.71` → acos = **44.7°** | ✅ Godot 默认 `floor_max_angle = 45°`，基本一致 |
| **PhysX** | ME 用 PhysX 2.8 **只做碎片/布料特效**，角色移动是引擎自研的 character movement | 复刻**不需要**碰刚体物理，`CharacterBody3D` 就是对的选择 |

---

## 9.3 建议的实施顺序

按"改动收益 / 改动成本"排序：

1. **速度曲线**（[02.1](02-速度系统.md#21-速度曲线核心)）——把 `sprint_speed` 从常数换成 `Curve` 资源，X = 速度能量，Y = 当前上限。**这是"像不像"的第一决定因素**，也是你现在完全缺失的一层。
2. **`wall_jump_push` 改成技巧梯度**（[04.4](04-墙面动作.md)）——单点杠杆最大。
3. **落地惩罚改成累计下落高度计数器**（[03.5](03-损速机制.md#35-绕过损速的社区技巧机制原理)）——成本极低，凭空长出一层技巧空间。
4. **重力/跳跃三件套**（`gravity` 24→8、`jump_velocity` 7.5→6.3、`sprint_speed` 9→7.2）——必须一起改。
5. **转向损速**（`SpeedTurnDecelerationFactor`）——你目前完全没有这一项，而它是 ME 技巧深度的重要一半。
6. **wallrun 去掉硬时限**，改由速度衰减决定时长。
7. Vault 甜区改成奖励而非惩罚。
8. 感知层（FOV / bob）——**最后再动，且这是设计选择不是对错**。

**关于工程实践**：你的 `MovementConfig extends Resource` + F1 实时调参面板，正是 DICE 用 `.ini` 达成的同一件事（[06.5](06-Move状态机架构.md#65-对-godot-的架构建议)）。**这个基础设施已经对了**——手感是调出来的，不是写出来的，而调的前提是改一个数字不用重新编译。剩下的就是把上面这些数字调进去。

---

← [08-速通社区交叉验证](08-速通社区交叉验证.md) · 下一篇 → [10-镜之边缘-like判定标准](10-镜之边缘-like判定标准.md)
