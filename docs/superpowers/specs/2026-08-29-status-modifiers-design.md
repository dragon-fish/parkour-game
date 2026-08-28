# 临时状态修饰（Status Modifiers）· 设计

日期：2026-08-29
证据基础：[`A1-TdMove-CDO全量.md`](../../mirrors-edge-deep-research/appendix/A1-TdMove-CDO全量.md)
（`TdPawn` 的 Pawn 级运行时开关、`TdMovementExclusionVolume`）；
[`12-关卡标注与Kismet.md`](../../mirrors-edge-deep-research/12-关卡标注与Kismet.md)
（体积不带配置数据、`MaxTriggerCount`、`LOI` 逐个开关）。

---

## 0. 结论先行

- Player 身上挂一串 **Status**（RPG 的 buff/debuff 思路，形状接近 Minecraft 的
  `MobEffectInstance`）。每条是 `{effect, subject, amount, seconds_left, source, priority}`。
- **`effect` 是枚举，不是类。** 预定义一张有限的效果表，一种效果对应一件事。
- **生命周期只有一个 `seconds`。** `INF` = 挂到被解除；有限秒数 + 体积按 `refresh_interval`
  重复施加 = 区域性附着。没有第二种机制。
- **键是 `(effect, subject)`，同键至多一条。** 冲突不靠"谁更严格"，靠**图层优先级**。
- 施加者与效果解耦：`ModifierVolume` 只是众多施加者之一，脚本、Move、调试面板都能挂。
- 通知走 **signal**（`status_applied` / `status_removed`），只报告不投票。
- 死亡复活清空全部、重置入场计数，**并重新施加玩家当前重叠的体积**。

[ME:CONFIRMED 12 §12.2] 这个形状是原作自己的做法：体积本身不带任何行为参数，`TdPawn`
的 CDO 上挂着一批 Pawn 级运行时开关（`bTakeFallDamage`、`GravityModifier`、
`OverrideWalkingState`、`bAllowMoveChange`、`MinLookConstraint`/`MaxLookConstraint`），
体积和脚本翻转它们。各个 Move 读的始终是自己一直在读的那个字段，不知道修饰的存在。

## 1. 范围

**包含**：`Effect` 枚举、`StatusSpec`、`StatusList`、`ModifierVolume`、
`InterestLine.tag`、各落点接线、复活清理、观察 signal、测试。

**不包含**：

- **弹出对话、激活脚本**。它们不是"附加或解除状态"——用 buff 实现一句台词是错的抽象。
  `Notice.show_text()` 已经存在，等它有了真正的载体（剧情/教学系统）再接。
- **软垫 / `SoftLanding`**。实测推翻了"软垫是触发器"（见
  [12 §12.5](../../mirrors-edge-deep-research/12-关卡标注与Kismet.md)）：它是**碰撞箱属性
  + 失控期间的弹道预测改判**，与本批工作无关，单独立项。
- RPG 包袱：层数（amplifier）、驱散、免疫、状态图标 HUD。**"叠层"的需求已由优先级
  + 轮询覆盖**，见 §2.4。
- `WalkOnly`。`SPEED_CAP` 完全覆盖它（`pawn.walk_velocity` 0.5 m/s 即 `amount ≈ 0.07`）。
- 原作 `OverrideWalkingState` 的五档。[ME:INFERRED 02 §2.2] 除 Walk 外四档在语料里被判为
  动画混合阈值而非速度钳，照搬等于发明。

## 2. 类型

### 2.1 `Effect`（`scripts/player/status/status.gd`）

```gdscript
class_name Status

## forced_view() 的三值答案，也是 StatusSpec.view 的取值。NONE 只会由
## forced_view() 返回，作者填不出来——没有 FORCE_VIEW 就是没有覆盖。
enum View { NONE, FIRST, THIRD }

## 一种效果对应一件事。载荷字段按下表读，未列出的效果一个都不读。
##
##   effect                 读哪个载荷字段
##   ---------------------  ------------------------------
##   SPEED_CAP              amount   = 上限系数 (0..1)
##   FORCE_VIEW             view     = View.FIRST / THIRD
##   BLOCK_INTEREST_LINE    subject  = InterestLine.tag
##   其余                    一个都不读
##
## DO NOT 往任何一个载荷字段里塞第二个含义。新含义就是新字段。
enum Effect {
    SPEED_CAP,
    FORCE_VIEW,
    BLOCK_JUMP,
    BLOCK_SLIDE,
    BLOCK_SKILL_ROLL,
    BLOCK_COIL,
    BLOCK_CROUCH,
    BLOCK_WALL_RUN,
    BLOCK_WALL_CLIMB,
    BLOCK_GRAB,
    BLOCK_SPEED_VAULT,
    BLOCK_LADDER,
    BLOCK_ZIPLINE,
    BLOCK_SWING,
    BLOCK_TURN_180,
    BLOCK_INTEREST_LINE,
    STAGGER,
}
```

**枚举里没有 `BLOCK_WALKING` / `BLOCK_FALLING` / `BLOCK_LANDING` /
`BLOCK_FALL_UNCONTROLLED`，这是刻意的。** 锁住这四个会卡死状态机或让人凭空悬空。
早先的设计是列一张"不可锁清单"再加编辑器警告和运行时 `push_error`；枚举把那条规则变成
了**写不出来**，于是校验、警告、错误三样一起消失。DO NOT 为了"完整"把它们补进枚举。

`STAGGER` 在枚举里，是因为"硬直 2 秒"确实是一个有时长的状态。它的**表现**（红屏、镜头
下沉）不在枚举里——见 §3.3。

### 2.2 `StatusSpec`（作者在 Inspector 里填的那一条）

```gdscript
class_name StatusSpec
extends Resource

@export var effect: Status.Effect = Status.Effect.SPEED_CAP
## 见 Effect 上方的 schema。不读这个字段的效果留 0。
@export var amount: float = 0.0
## 同上。不读这个字段的效果留空。
@export var subject: StringName = &""
## 同上。FORCE_VIEW 专用。
@export var view: Status.View = Status.View.FIRST
## 持续秒数。INF = 挂到被解除。
@export var seconds: float = INF
```

### 2.3 `StatusList`（`scripts/player/status/status_list.gd`）

`RefCounted`，挂在 `Player.statuses`。**不碰场景树、不查询物理**，因此可以脱离物理世界
单测——与 `FallTracker`、`SpeedEnergy` 完全同构。

条目记录，全部字段具名：

```gdscript
{effect = <Effect>, subject = <StringName>, amount = <float>,
 seconds_left = <float，INF 表示不倒计时>, source = <Object>, priority = <int>}
```

**键是 `(effect, subject)`，同键至多一条。**

`subject` 参与键，是因为 `BLOCK_INTEREST_LINE` 必须能**同时**禁掉多根线（禁管子 A 也禁
管子 B）。若键只是 `effect`，它就只能禁一根。其余效果的 `subject` 为空，于是退化成
"每个 effect 至多一条"。

查询接口直接读列表，**不再每 tick 重建一份解析对象**：

```gdscript
func speed_scale() -> float                     # SPEED_CAP 的 amount，无则 1.0
func is_move_blocked(move_name: StringName) -> bool
func is_line_blocked(line_tag: StringName) -> bool
func forced_view() -> int                       # Status.View.NONE / FIRST / THIRD
```

**一人称与三人称是同一个 Effect 的两个取值，不是两个 Effect。** 若拆成
`FORCE_FIRST_PERSON` / `FORCE_THIRD_PERSON`，它们就是两个不同的键、可以同时存在，而
§2.4 的优先级只在同键之间生效——两个体积各挂一个，谁也管不着谁，`forced_view()` 得自己
再发明一套仲裁。合成一个键之后，冲突由 §2.4 统一处理，这里没有特例。

`is_move_blocked()` 内部是一张 `Move.JUMP -> Effect.BLOCK_JUMP` 的常量表。表里没有的
动作名一律返回 `false`——这正是 §2.1 那条"写不出来"的另一半。

### 2.4 冲突：图层优先级

`apply()` 遇到同键已存在时：

| 情况 | 结果 |
|---|---|
| **同一 `source`** | **永远刷新**（`seconds_left` 重置，`amount` 更新） |
| 不同 source，来者 `priority` 更高 | 覆盖 |
| 不同 source，来者 `priority` 更低 | 忽略 |
| 不同 source，`priority` 相同 | 忽略后来者 + `push_warning` |

**第一行是必需的，不是优化。** 区域体积每 `refresh_interval` 用**相同优先级**重施自己；
若同优先级一律忽略，它会忽略掉自己的刷新，状态到期而玩家人还站在体积里——**体积把自己
饿死**。所以条目必须记住 `source`，优先级规则只在不同来源之间生效。

**警告按 `(effect, subject, 两个 source)` 去重**，每对只报一次，复活时清空。不去重的话
轮询会让同一条冲突每 `refresh_interval` 刷一次屏，控制台没法用。

优先级同时解决了一件"谁更严格"根本表达不了的事：`FORCE_VIEW` 的一人称与三人称之间
没有更严格一说，只有图层高低。`SPEED_CAP` 那种"取更小的"只是碰巧对量值成立的特例，
不能当成通用规则。

**没有层数（amplifier）概念。** 两个体积都挂 `BLOCK_JUMP`、走出一个仍被另一个挡着——
这个需求由轮询覆盖：留下的那个体积下一次刷新就把状态续上了，不需要引用计数。

## 3. 落点表

每条效果接到**既有的单一读取点**，各个 Move 不知道 Status 存在。

| 查询 | 落点 |
|---|---|
| `speed_scale()` | `Player.speed_cap()`（`player.gd:3519`）末尾乘系数。所有问"极速是多少"的地方都走这里；`MoveConfig.speed_modifier`（下蹲 0.4）是同一形状的既有先例 |
| `forced_view()` | `CameraRig` 新增 `forced_view` 覆盖字段。**`third_person` 存盘偏好一字节不动**——`camera_rig.gd:1033` 的 `toggle_third_person()` 每次都 `save_preferences()`，共用字段会让玩家进一次室内偏好被永久改写。覆盖生效期间 V 键无效 |
| `is_move_blocked()` | 见 §3.1 分路由 |
| `is_line_blocked()` | `Player.nearest_interest_line()`（`player.gd:109`），见 §3.2 |
| `STAGGER` | `MoveManager`，见 §3.3 |

`speed_cap()` 被缩小时速度能量**不清空**：累积闸门本身就按
`speed_cap() * move_speed_modifier` 度量（`player.gd:3587`，注释里已写明下蹲的同款理由），
所以限速期间照常存能，解除瞬间即可恢复原速。

### 3.1 `is_move_blocked()` 必须分路由

**`MoveManager.can_enter()`（`move_manager.gd:30`）不是唯一闸门。** `physics_update()`
第 173 行确实让每一次转换都经过它，但有三个动作在**返回状态名之前**就已经把事做了，
在 `can_enter()` 拦下它们只会产生半完成状态：

- **`JUMP`** — `walking_move.gd:29` 先 `player.velocity.y = base_jump_z` 再 `return JUMP`。
  在 `can_enter()` 拦 = 人被弹上天但状态还是 Walking。
- **`SLIDE`** — `walking_move.gd:69` 先花掉 `consume_roll()` 的预输入、施加 floor-snap
  并 `move_and_slide()`，再 `return SLIDE`。
- **`SKILL_ROLL`** — `airborne_move.gd:318` 先消费预输入、再按 `rolled = true` 调
  `_apply_landing_cost()` 结算保速，最后才 `return SKILL_ROLL`。在 `can_enter()` 拦 =
  没翻滚但速度按翻滚保住了。

作者面向的词汇不受影响（枚举值照样叫 `BLOCK_JUMP`），路由在实现里：

| 效果 | 拦截点 |
|---|---|
| `BLOCK_JUMP` | `Player.consume_jump()` / `consume_jump_no_coyote()` 返回 false，整个分支不进 |
| `BLOCK_SLIDE` | `walking_move.gd` 的 `if player.consume_roll():` 之前加闸，预输入不花 |
| `BLOCK_SKILL_ROLL` | `airborne_move.gd` 的 `rolled` 判定，**短路在 `consume_roll()` 之前**，预输入不吞，落地后仍可接滑铲 |
| 其余 | `MoveManager.can_enter()` |

### 3.2 `BLOCK_INTEREST_LINE`：禁用具体的可交互物

[12 §12.3](../../mirrors-edge-deep-research/12-关卡标注与Kismet.md) 记录了原作成对出现的
21 组 `LOI xxx` / `NO LOI xxx` 远程事件——它**逐个**启用/停用兴趣点。这与 `BLOCK_LADDER`
是两个维度：一个禁**能力**（"不许爬梯子"），一个禁**具体物件**（"这一根管子不能爬，
那一根可以"）。

`InterestLine` 新增一个导出字段：

```gdscript
## 让 BLOCK_INTEREST_LINE 能指名道姓。留空 = 不可被单独禁用。
@export var tag: StringName = &""
```

这是本批工作唯一动到既有类的改动。

落点只有一处：`Player.nearest_interest_line()`（`player.gd:109`）评选"最近的那根"时跳过
被禁的线。六个调用点（`airborne_move` ×3、`walking_move`、`wall_run_move`、`line_move`）
全部经由它，`player.interest_lines` 在 `player.gd` 之外没有直接读者。

**只拦"抓上去"，不把正在用的人甩下来。** `LineMove.enter()` 取到线之后就存进自己的
`_line`，此后不再询问；禁用一根玩家正挂在上面的滑索不会让他中途掉下去。这是刻意的
——保护的触发条件若等于功能的使用场景，那是阉割不是保护。

### 3.3 `STAGGER`

在 `MoveManager.physics_update()` 里 `_turn_requested()` 的**同一个位置**检查该状态并转
`LANDING`。`_turn_requested()`（Q 键 → `TURN_180`）已经是"管理器自己发起一次转换"的既有
先例，不是新开的口子。来自 `FALL_UNCONTROLLED` 的不受理（已经在死了）。

**红屏和趔趄不进枚举。** `LandingMove` / `LandingConfig` 已经是那个复合体——
`lockout_time = 2.0`、`tint_color`、`camera_pitch_offset`，外加 `allows_turn = false` 和
绝对 yaw 扇形。`STAGGER` 只说"去那个状态"，表现免费到手。把红屏和镜头拆成
`TINT` / `CAMERA_SHAKE` 两个效果才是难走的那条路，且与"台词不是 buff"是同一个错误。

铁丝网该硬直多久，原作那边 [ME:UNKNOWN]。先复用 `LandingConfig.lockout_time` 的 2 s；
真到了"铁丝网和落地必须分开调"那天再拆 `StaggerMove`，不提前拆。

想要更轻的铁丝网，`apply: [SPEED_CAP amount=0.3 seconds=3]` **不需要任何新机制**，两者
可以挂在同一个体积上。

## 4. `ModifierVolume`（`scripts/level/modifier_volume.gd`）

`@tool` + `Area3D`，形状由作者挂 `CollisionShape3D` 子节点——与 `Checkpoint` 同款。
`_ready()` 里 `add_to_group("modifier_volumes")`，进出用 duck-typed 回调，与
`InterestLine` 维护 `Player.interest_lines` 同款。

```gdscript
## 进入时施加这些。
@export var apply: Array[StatusSpec] = []
## 进入时解除这些。只读 `effect` 与 `subject` 两个字段，`amount` / `seconds` 忽略。
## `subject` 留空 = 解除该 effect 的全部条目（不分 subject）。
##
## 用 StatusSpec 而不是 Array[Status.Effect]，是因为后者放不下 subject——
## "解开管子 A 的禁用、管子 B 仍禁着"就表达不出来了。
@export var remove: Array[StatusSpec] = []
## > 0 时每这么久重施一次 `apply`，用于区域性附着。0 = 只在入场时施加一次。
@export var refresh_interval: float = 0.0
## 图层。与其它体积冲突时高者胜；相同则忽略后来者并警告一次。
@export var priority: int = 0
## 最多触发几次，0 = 无限。计的是**入场次数**，不计 refresh_interval 的重施。
@export var max_trigger_count: int = 0
```

一个体积可以同时附加和解除多种效果——**不必为了多一条修饰就多摆一个体积**。

区域性附着的推荐摆法：`refresh_interval = 0.5`，`StatusSpec.seconds = 0.5`。玩家在体积
内时状态被不断续上，走出去后最多 0.5 s 自然到期。**不需要 `body_exited`，也不需要追踪
谁在体积里。**

### `max_trigger_count` 是整数而不是 `once: bool`

[ME:CONFIRMED 12 §12.3](../../mirrors-edge-deep-research/12-关卡标注与Kismet.md) 原作
`SeqEvent` 上的对应字段就是 `MaxTriggerCount`（0 = 无限），教程关那两个
`SeqEvent_TdTouch` 都取 0。

理由不只是同构：**教程关是一条回环**（12 §12.4），体积会被反复进入，而"只在第一圈锁"
和"每圈都锁"是两种需求——布尔盖不住中间地带，整数免费覆盖，实现成本一样。

## 5. 死亡与复活

`Arena.reset_player()` 是所有复活路径的唯一汇合点（R 键、掉出世界、`DeathSequence` 的
`finished`），在其中：

1. `player.statuses.clear_all()`（连同 §2.4 的已警告集合）
2. 遍历 `modifier_volumes` 组，把各自的入场计数清零
3. **重新施加玩家当前重叠的体积**

第 3 步是必需的，不是保险。开场关卡的病房把 `seconds = INF` 的状态盖在出生点上：玩家
出生在体积里，死一次后身体从未离开过该体积，`body_entered` 不会重放——不补这一步，
复活后玩家反而"痊愈"了。`reset_state()` 里 `interest_lines.clear()` 的注释已写明同一条
根因：复活是从体积里瞬移出去，区域永远不会报告离开。

用 `refresh_interval` 的区域体积不受这条影响（下一次轮询就补上了），`INF` 的会。两种都
要覆盖，所以第 3 步照做。

## 6. 观察 signal

`StatusList` 发 `status_applied(effect, subject)` / `status_removed(effect, subject)`。
**只报告，不投票。** HUD、音效、教程提示、调试面板挂这上面。

判定不走 signal：Godot 的 signal 不能返回值（`emit_signal()` 返回 `Error`），要否决就得
每次分配一个可变事件对象，而派发顺序取决于连接顺序、也就是取决于场景树结构——
"玩家能不能跳"会随着在编辑器里拖动节点而改变。这与 CLAUDE.md 的核心架构也冲突：
每一个"能不能从 X 到 Y"有且只有一个答案。判定用有序表（确定、可打印），通知用 signal。

## 7. 测试

按 `.claude/skills/tuning-dials-not-rules`：`SPEED_CAP` 的 0.5、硬直时长这类**表现值不写
断言**。写结构性不变量：

- 键：`BLOCK_INTEREST_LINE` 两个不同 `subject` **共存**；`SPEED_CAP` 两次施加只留一条
- 优先级：高覆盖低；低被忽略；**同 source 同优先级永远刷新**（专盯"体积饿死自己"）
- 警告：同一对冲突只 `push_warning` 一次
- 倒计时：`seconds` 到点自动移除；`INF` 不移除
- 轮询：`refresh_interval` 期间状态持续存在，停止重施后于 `seconds` 内消失
- `max_trigger_count`：取 1 时二次入场不触发；**轮询重施不计数**
- 复活：清空 + 入场计数归零 + **当前重叠的体积被重新施加**
- `forced_view` 生效并解除后，`camera_rig.third_person` 与进入前逐字节相同
- `BLOCK_JUMP` 时按跳跃键，`velocity.y` **不变**（专盯 §3.1 的半完成状态）
- `BLOCK_SKILL_ROLL` 落地后速度按**未翻滚**结算
- `BLOCK_INTEREST_LINE`：被禁 tag 的线不再被 `nearest_interest_line()` 选中；**同类未被禁
  的另一根仍能选中**（证明粒度是物件不是类别）；已挂在被禁线上的 `LineMove` 不被中断

前六组不需要物理世界（`StatusList` 是 `RefCounted`）。

## 8. 已知风险

- **首帧重叠**。玩家出生在体积内时 `body_entered` 是否在第一个物理帧触发，需实测确认；
  `Arena.reset_player()` 会跳过一个物理帧（`_resetting_physics`）。§5 第 3 步的主动重查是
  对这条的正面处理，不依赖信号时序。
- **`SPEED_VAULT` 被拦时 `pending_vault_variant` 不会被清**。该字段由读取方清除，拦下后
  无人读取。下一次合法翻越会在返回前覆写它，因此无害——但这是"一次性字段"约定的一个
  边角，实现时确认而非假设。
- **`refresh_interval` 与物理帧的对齐**。0.5 s 不是 tick 的整数倍时，续期与到期可能在同一
  帧内竞争。实现时让刷新先于倒计时；`seconds` 取与 `refresh_interval` 相等已留有一整个
  刷新周期的余量。
