# 平衡木（Balance）与檐走（LedgeWalk）设计

复刻原版 `TdMove_Balance` + `balance_TdBalanceWalkVolume`，以及
`TdMove_LedgeWalk` + `ledgewalk_TdLedgeWalkVolume`。两个动作一起做，因为它们在
CDO 层面是同一副骨架。

## 证据与裁定

### 两者的骨架字段逐字相同

A1 附录的两份 CDO 并排（✅ 全量已核对）：

| 字段 | Balance | LedgeWalk |
|---|---|---|
| `ControllerState` | PlayerBalanceWalk | PlayerLedgeWalking |
| `SpeedModifier` | 0.34 | 0.10 |
| `bConstrainLook` | True | True |
| `bDisableFaceRotation` | True | True |
| `bDisableControllerFacingPawnYawRotation` | True | True |
| `bAvoidLedges` | False | False |
| `MinLookConstraint` | (-13000, -6000, -32768) | (-14000, -10000, -32768) |
| `MaxLookConstraint` | (25000, 6000, 32768) | (16384, 10000, 32768) |
| `MovementGroup` | MG_TwoHandsBusy | MG_OneHandBusy |
| `bEnableAgainstWall` | — | True |
| `RedoMoveTime` | 0.5 | — |
| 倒立摆五参 | 全套 | **一个都没有** |

四个布尔一字不差，那就是「强制沿线 + 锁身体朝向 + 锁视角」这副骨架。

⚠️ **檐走没有平衡机制。** 名字里没有 balance，CDO 里也没有：
`GravityInfluence` / `ControlInfluence` / `SpeedInfluence` / `TimeToCounter`
一个都不存在。檐走全部的内容就是「速度砍到 10% + 视角锁死 + 身体朝向锁死」，
掉不下去。不要给它加平衡玩法。

### 速度

```
Balance    GroundSpeed 720 x 0.34 = 244.8 uu/s = 8.813 km/h   ✅ HUD 实测 8.81
LedgeWalk  GroundSpeed 720 x 0.10 =  72.0 uu/s = 2.592 km/h
```

📌 `SpeedModifier` 乘的是 **`GroundSpeed` 常量，不是当前速度**——25.9 km/h
冲上梁也直接摁到 8.8。项目里 `ground_speed = 7.2 m/s`，两者分别是
**2.448 m/s** 与 **0.72 m/s**。

### 视角约束（65536 = 360° 换算，Rotator 顺序 Pitch/Yaw/Roll）

| | pitch | yaw | roll |
|---|---|---|---|
| Balance | -71.4° ~ +137.3° ❓ | ±32.96° | 不限 |
| LedgeWalk | -76.9° ~ +90.0° | ±54.93° | 不限 |

❓ Balance 的 pitch 上限 25000 超出 UE3 pitch 的 ±16384 常规范围，含义不明。
**按 +90° 实现**，原值记在这里备查，不要照搬 137°。

Balance 的 yaw 比檐走还窄一半——梁上比檐上更不许转头，与「夺走控制权、镜头沿梁
走」一致。`-13000` 与 wallrun 的 pitch 下限是同一个数。

### 倒立摆：✅ owner 实测，它不是一串随机推力

见 05 §5.6。手感模型是**放在拱顶上的小球**（✅ owner 另画示意图确认）：进入瞬间
按当时速度把球随机摆到左边或右边某个位置，速度越快摆得越偏；之后的发散是不稳定
平衡自己长出来的，与速度无关。开头把偏移**和它的变化率一起**归零，后半程球稳稳
待在中间。

⚠️ **不要注入随机推力。** 随机只出现在入场那一次的初始偏移里。改成「每隔几秒推
一下」，熟练玩家就再也拿不到那段稳定路段，而那正是这个动作给玩家的奖励。

### 🔶 本设计对 `GravityInfluence` 的重新裁定

05 §5.6 把 `GravityInfluence = 0.3` 读作「不稳定系数」，同时把
`TimeToCounter = 0.8s` 读作「发散的特征时间」。**在任何自洽的二阶系统里这两句话
说的是同一件事**——发散速率只有一个，两个数管它就必然有一个冗余。

[ME:INFERRED] 本设计改读作：`GravityInfluence` 与 `CameraInfluence` **并列**，
两个都是 0.3，两个都是「把失衡量转换成某个后果」的系数——`CameraInfluence` 转成
镜头 roll，`GravityInfluence` 转成**身体真的偏离梁中心线的横向位移**。

四个数于是各管一件不重叠的事，而且摔下去变成**几何结果**（横向偏移超出梁半宽，
脚踩空）而不是又一个阈值判定，落在 `docs/contact-drives-movement.md` 上。

⚠️ 这是推导，不是从原作读出来的。05 §5.6 里「不稳定系数」那句要相应改掉。

### owner 裁定

- **验收场地**：从 `templates/base_level.tscn` 继承一张新的 debug 关，不动生成的
  `calibration_course`。
- **失衡的表现**：模型程序化倾斜 + 第一人称镜头 roll；**第三人称镜头 roll 大幅
  减小**（外部视角跟着歪会眩晕），信息量改由模型承担。
- **倾斜的形状**：不要全身一起歪，那很奇怪。**脚跟固定，下半身微倾，上半身承担
  倾斜的提示。**
- **FOV**：收缩模拟恐高与紧张，**只跟失衡量走**——稳住时 FOV 完全正常，只有快摔
  了才收。奖励稳定，与倒立摆「开头调顺了后面几乎不用管」的结构一致。
- **本次范围**包含：动画接线、失衡量的调试可视化、TuningPanel 旋钮。

### 关卡里的形状

`S_PipeSystem_*` 多段管子拼接，覆盖一个 `TdBalanceWalkVolume`；me_level0 里
`TdLedgeWalkVolume` 出现 2 次（12 号文档确证）。✅ 平衡木**必须**用标记而非几何
探测，owner 给的是玩法理由：Balance 是「进去就出不来」的夺权状态，误入的代价远
大于漏判；用几何探测触发它等于在关卡里到处埋坑。多段管子靠几何每帧现推中心线还
会在接缝处抖，标记直接给一条干净的线。

📌 檐走是**关卡节奏工具**而非移动能力（11 号文档 owner 判断）：几何上玩家本来就
走得过去，这个兴趣点存在的意义就是逼你慢下来。

## 类结构

```
Move
└── LineMove              取线、磁吸淡入、转身、出线冷却、slide_to    （已有）
    ├── ZiplineMove       挂在线下，沿线滑                          （已有）
    ├── SwingMove         挂在线下，垂直摆                          （已有）
    ├── LadderMove        挂在线上，沿线爬                          （已有）
    └── LineWalkMove      站在线上，沿线走                          ← 新
        ├── BalanceMove   ＋倒立摆                                  ← 新
        └── LedgeWalkMove 薄壳，差异全在 config                      ← 新
```

分界线是 05 §5.6.5 自己写下的那句：滑索**挂在线下**沿线滑、单杠**挂在线下**垂直
摆、平衡木**站在线上**沿线走。`LineWalkMove` 收「站着」的那一份，`LedgeWalkMove`
里不会有任何恒为零的摆状态。

⛔ **不要把两者合并成一个 Move 用 config 开关区分。** 骨架同构不等于动作同一：
倒立摆是 Balance 独有的完整子系统，合并会让檐走拖着一整套恒零状态跑，也违反
「一个 move 拥有一个动作、每个转移只有一个答案」。

### `LineWalkMove` 拥有

吸附上线并声明 `grounded`、沿线一维推进、速度钳到 `speed_modifier`、身体朝向锁在
「相对线切线转 `body_yaw_offset` 度」、走到线的两端交回 `WALKING`、跳交回
`FALLING`、应用 look constraint。

### 沿线速度是一次投影，不是两套键位

把 `MoveInput.move` 转成世界方向，投影到线的切线上，得到沿线速度。

- Balance `body_yaw_offset = 0°`（身体顺着线）：W 投影满值、D 投影为零。
  **「A/D 不能让你横着走下梁」是这个投影的结果，不是一条规则。**
- LedgeWalk `body_yaw_offset = 90°`（身体垂直于线、背对墙）：同一行代码变成
  A/D 驱动、W/S 无效。

✅ 一代的 `TdMove_LedgeWalk` **永远背对墙**，只有一种朝向（07 owner 实测）；
Catalyst 才按入墙角度分成两种。本项目照一代做，只需要一个侧向挪步片段。

「一个只能前后、一个只能左右」落在数据上就是 `body_yaw_offset` 这一个角度。

## 场景标记

`InterestLine.Kind` 增加 `LEDGE_WALK`（`BALANCE` 已经在了）。摆放约定：

- 曲线沿**梁的中轴 / 檐的中轴**画，可多段，可弯曲（Curve3D 本来就支持）。
- Balance：节点朝向无意义，线本身就是全部信息。
- LedgeWalk：节点自身的 **-Z 指向墙**（沿用 `front()` 的既有语义，与 Ladder 的
  正面约定一致）。玩家背对墙站，所以身体朝向是 `+front()`。
- 体积仍由 `InterestLine` 自动生成。

## 进入与退出

### 进入

照 `LadderMove.catch_gate()` 的**静态门**写法（同一个问题只有一个答案，不许
enter-then-abort），挂在 `WalkingMove`（走上去）和 `AirborneMove`（跳上去）。

除了体积命中和 `line_ready()` 冷却，多一个条件：**脚的高度贴着线**。
`reach_radius` 默认 0.6 m，光靠体积的话从梁**旁边**跑过也会被吸进去，而 Balance
是「进去就出不来」的状态，误入代价远大于漏判。判据：

```
abs(feet_y - line_y_at_closest_offset) <= foot_snap_height
```

`AirborneMove` 侧走 `check_for_balance` / `check_for_ledge_walk` 开关
（`MoveConfig` 的既有形状，和 `check_for_zipline` 一致）；`WalkingMove` 侧不读
开关，直接问静态门——与 Ladder 的地面进入同一处理。

磁吸淡入沿用 `LineMove` 的既有形状：位置拉到线上、身体转到目标 yaw，淡入结束
`_centre_fan()` 居中视角扇。入场瞬间水平速度丢弃（`SpeedModifier` 乘的是常量，
不是当前速度）。

### 退出

| 出口 | 去向 |
|---|---|
| 走到线的任一端 | `WALKING` |
| 跳 | `FALLING` |
| 蹲 | `FALLING`（松手；`consume_roll()` 吃掉这次按键，同 Ladder） |
| Balance 失衡到脚踩空 | `FALLING` |

`RedoMoveTime = 0.5` 填进 `redo_move_time`；`LineMove.note_left()` 的 per-line
冷却免费继承——跳下梁不会立刻被吸回去。

⚠️ **屈膝跳上梁后立刻再跳可以不进入 Balance**（owner 实测的原作 glitch）。
📌 **本项目不复刻它**，也不要把它的缺席当成 bug 去修。

## 倒立摆（只属于 BalanceMove）

状态两个数：`_offset`（失衡量，米，正 = 向线的右侧）与 `_offset_rate`。每帧：

```
offset_accel = offset / divergence_time^2  -  correction_gain * lateral_input
```

- `divergence_time` = `TimeToCounter` = 0.8 s。⚠️ 读成**发散时间常数**而不是
  「纠正窗口」：偏移每 0.8 s 放大一个 e 倍，指数发散没有宽限期，只有时间常数——
  这才解释得了为什么晚一点点就彻底来不及。
- `correction_gain` = `ControlInfluence` = 1.5。
- `lateral_input` = 输入世界向量在**线的水平法线**上的投影。与沿线速度用的是同一
  个输入向量的另一个分量，没有分支。

三条硬约束：

1. ⛔ **不加阻尼，一个字都不加。** 系统里不许有任何东西替玩家把 `_offset_rate`
   拉回零。「熟练者在开头把偏移和它的变化率一起归零」只有在没人帮忙时才有意义；
   加阻尼等于系统替玩家稳住，那段「后半程几乎不用按 A/D」的奖励就不再是他挣来的。
2. ⛔ **随机只在入场发生一次。**
   `offset = (base_wobble + entry_speed_influence * v / ground_speed) * ±1`，
   `entry_speed_influence` = `SpeedInfluence` = 2.5。此后再无随机数，一个都没有。
   `base_wobble` **必须非零**：✅「站在原地不动也会失衡」要求 v=0 时初值仍不为零，
   只是小、发散慢。
3. **摔落是几何结果。** 身体沿线的水平法线真的偏移
   `offset * gravity_influence`（见上文裁定），偏出 `beam_half_width` 即脚踩空
   → `FALLING`。不是一个额外的阈值判定。

## 表现层

一个数据源 `_offset`，三个表现通道（分段倾斜、镜头 roll、FOV 收缩）。檐走没有
`_offset`，因此这三条只对 Balance 生效——檐走的表现就是 `Walk_L/R_Loop` + 视角
约束 + 0.72 m/s。动画路由不由 `_offset` 驱动，两个 move 都要，单列在后。

### 分段倾斜（新 `SkeletonModifier3D`）

⚠️ **不要全身一起歪。** 也不要用满速前进的身体倾斜片段（`Jog_Fwd_LeanL/R`）——
owner 已裁定那不适合这里，而且这也是平衡木动画缺口消失的原因：身体只是在以
8.81 km/h 走路，`Walk` 就够。

`scripts/player/head_look.gd` 是这套机制的完整先例，照它的手法换一根轴：

- 按链分配一个 roll 角度，全部走 `set_bone_global_pose`（humanoid 骨骼的局部轴是
  rest pose 决定的，局部旋转会把身体弯到别处去，而这个项目看不见只能测）。
- 父到子累加：下层的份额要从上层减回去，否则叠加过冲。
- **`Hips` 只给很小的份额**（初值 3~5°），`Spine` 起分大头，`Chest` / `UpperChest`
  收尾。HeadLook 选 `Spine` 而不是 `Chest` 当起点的理由在这里同样成立：Spine 的
  原点就在髋上方，那是人真正弯折的地方，从 Chest 起会读成耸肩。

⚠️ **项目没有腿部 IK**（只有 `hand_ik.gd`），所以「脚跟绝对固定」做不到。Hips 份额
压到很小之后，脚的位移只剩髋部带出来的那一点，视觉上就是脚扎在梁上、身子在上面
晃。真要脚完全钉死得另开 foot IK，**不在本次范围内**。

⚠️ **技术风险，必须先验证**：`HeadLook` 与这个新 modifier 会同时改同一批骨骼（走
平衡木时照样在东张西望），两个 `SkeletonModifier3D` 都用 `set_bone_global_pose`
时能否干净叠加未经验证。叠不了就合并进 `HeadLook`——它自己的注释已经说过「两件事
合在一个 modifier 里是因为共享同一套减法算术」，roll 共享的正是同一套。

### 镜头 roll

失衡量 × `CameraInfluence`(0.3) × 一个角度上限，第一人称全额。
**第三人称乘一个大幅减小的系数**（`CameraConfig` 新字段），外部视角跟着歪会眩晕。

### FOV 收缩

`CameraConfig` 现有的 FOV 通道是**速度驱动**且方向相反（越快越开，
`fov_base 90 → fov_max 105`）；Balance 的 2.448 m/s 会算出 ≈95°，比静止还开。
因此新加一个收缩通道，走 `set_vault_roll()` / `set_roll_spin()` 那种「move 每帧
喂值给 rig」的既有形状，叠在速度 FOV **之后**。

只跟失衡量的绝对值走，稳住时为零。

### 动画路由

`character_animator.gd` 的 `_route()` 里各加一个 case。
⚠️ `tests/test_animation_routing.gd` 的 `test_every_move_has_its_own_case` 找的是
字面的 `Move.X:`，**两个 move 必须各有独立 case**，不许合并。

- Balance → `[&"Walk", &"walk", &"Idle", &"idle"]`。身体只是在慢走。
- LedgeWalk → 方向感知，沿用 `DIRECTION_SETS` 的 `Walk` 家族 `_L` / `_R` 后缀：
  向线的左端走取 `Walk_L`，右端取 `Walk_R`，静止取 `Walk` / `Idle`。
  ✅ `Walk_L_Loop` / `Walk_R_Loop`（UAL2 八方向全套，私仓层）就是走路节奏的侧向
  挪步，正是要的东西。

两条都是优先级列表，没挂模型时自然降级。

## 配置

两个新 `MoveConfig` 子类挂进 `MovementConfig`（`balance` / `ledge_walk`），
`presets/default.tres` 相应补两个子资源。

`MoveConfig` 的现成字段直接填，不新增机制：`speed_modifier`、`redo_move_time`、
`min_look_constraint` / `max_look_constraint`（弧度，authoring 时换算）、
`constrain_look`、`freeze_visual_yaw`（身体不该跟着视角转）、`allows_turn = false`
（MG_TwoHandsBusy / MG_OneHandBusy，没有余手转身）。

`BalanceConfig` 自己的数：

| 字段 | 初值 | 来源 |
|---|---|---|
| `divergence_time` | 0.8 | ✅ `TimeToCounter` |
| `correction_gain` | 1.5 | ✅ `ControlInfluence` |
| `entry_speed_influence` | 2.5 | ✅ `SpeedInfluence` |
| `camera_influence` | 0.3 | ✅ `CameraInfluence` |
| `gravity_influence` | 0.3 | ✅ 数值确证，语义为本设计推导 |
| `base_wobble` | 旋钮 | 站着不动也会失衡所需的非零初值 |
| `beam_half_width` | 旋钮 | 脚踩空的几何边界 |
| `body_yaw_offset` | 0° | 身体顺着线 |
| `foot_snap_height` | 旋钮 | 进入门：脚贴着线 |
| 倾斜/FOV 的角度上限与骨骼份额 | 旋钮 | 表现值 |

`LedgeWalkConfig` 只有 `body_yaw_offset = 90°`、`foot_snap_height`，以及基类那几个。

`TuningPanel` 接入这两组，运行时可拨，不必改 `.tres` 重启。

📌 表现值不写单测（`.claude/skills/tuning-dials-not-rules`）——上表里标「旋钮」的
都是拨的，改坏了一眼可见。写测试的是结构性不变量。

## 关卡与调试

- `scenes/debug_levels/balance_course.tscn`，从 `templates/base_level.tscn`
  **继承**（Scene > New Inherited Scene），几何加在子场景里。
- 内容：一根离地有落差的独木桥（进得去、摔得下去、走得完）、一段贴墙的窄檐、
  两者之间能连起来跑一趟。`base_level` 自带死亡体积与复活，摔下去免费可用。
- `DebugHud` 打出失衡量与其变化率的实时读数。⚠️ 倒立摆是**看不见的内部状态**，
  没有这个读数调参基本是瞎拧。

## 测试

结构性不变量，不测手感值：

- `LineWalkMove` 的沿线投影：Balance 按 D 沿线速度为零、LedgeWalk 按 W 为零
  （即「前后 / 左右」是同一个式子）。
- 进入门：从梁**旁边**（脚不在线高度上）走过不进入。
- 退出：走到端点回 `WALKING`；跳回 `FALLING`；`redo_move_time` 生效。
- 倒立摆的**发散性质**（不是具体数值）：无输入时失衡量的绝对值单调增；失衡量与
  其变化率同时为零时保持为零（不稳定平衡的顶点）；入场初值在 v=0 时非零。
- 檐走**没有**倒立摆状态。
- `test_every_move_has_its_own_case` 通过（两个 case 各自独立）。
- `MovementConfig` 布局测试（`test_config_layout.gd` 的既有形状）。

## 已知空白

- ❓ Balance 的 pitch 上限 25000（≈137°）含义不明，按 +90° 实现。
- ❓ 檐走能否从檐上主动翻下变成 Grab（吊挂）：CDO 只说 `MG_OneHandBusy`，原作行为
  未测。**本次不做。**
- ❓ 手部 IK（檐走扶墙的那只手、平衡木张开的双臂）：与滑索/单杠/梯子同属既有空白，
  **本次不做**。
- 🔶 `GravityInfluence` 的语义是本设计的推导，非原作读出。05 §5.6 的「不稳定系数」
  一句要相应改掉。
