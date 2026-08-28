# 临时状态修饰（Status Modifiers）· 设计

日期：2026-08-29
证据基础：[`A1-TdMove-CDO全量.md`](../../mirrors-edge-deep-research/appendix/A1-TdMove-CDO全量.md)
（`TdPawn` 的 Pawn 级运行时开关、`TdMovementExclusionVolume`）；
[`11-状态机全图.md`](../../mirrors-edge-deep-research/11-状态机全图.md) §11.2 能力表；
作者 2026-08-29 在原作内的实测（软垫、`SoftLanding`）。

---

## 0. 结论先行

- Player 身上挂一串 **Status**（RPG 的 buff/debuff 思路）。每条 Status 是一个
  `Resource`，描述**一项修改**，不描述谁挂的。
- 施加者与 Status 解耦：`ModifierVolume`（Area3D）只是众多施加者之一，脚本、Move、
  调试面板都能挂。
- 判定走**确定性折叠**，不走事件否决。每 tick 把列表折成一份 `StatusResolution`，
  各处读它。速度取 min、禁用取并集、视角取最后加入者——与施加顺序无关的通道天然
  无关，有关的那一条显式声明。
- 通知走 **signal**（`status_applied` / `status_removed`），只报告不投票。
- 三种生命周期：**跟随来源**（在体积内）、**挂到被解除**（LATCH）、**倒计时**。
- 死亡复活清空全部 Status、重置 `once`，**并重新施加玩家当前重叠的体积**。

[ME:CONFIRMED] 这个形状是原作自己的做法：`TdPawn` 的 CDO 上就挂着一批 Pawn 级运行时
开关（`bTakeFallDamage`、`GravityModifier`、`OverrideWalkingState` /
`PendingOverrideWalkingState`、`bAllowMoveChange`、`MinLookConstraint` /
`MaxLookConstraint`），而 `TdMovementExclusionVolume` 带 `bExcludeFootMoves` /
`bExcludeHandMoves`——**一个按类别禁用动作的体积**。各个 Move 读的始终是自己一直在读
的那个字段，不知道修饰的存在。

## 1. 范围

**包含**：`Status` 基类与六个子类、`StatusList`、`StatusResolution`、
`ModifierVolume`、各落点接线、复活清理、观察 signal、测试。

**不包含**：

- **软垫 / `SoftLanding`**。作者 2026-08-29 实测推翻了"软垫是触发器"这一假设：关卡里
  另有一个软垫附近没有任何触发器，且从不致死高度落到软垫上可以正常翻滚（说明机制在
  失控状态下才启动）。当前模型是**碰撞箱属性 + 失控期间的弹道预测改判**，与本批工作
  无关，单独立项。`FallCounterReset` 随之取消——它唯一的用途就是软垫。
- RPG 包袱：层数（stack count）、驱散、免疫、状态图标 HUD。
- `WalkOnly`。`SpeedCap` 完全覆盖它（`pawn.walk_velocity` 0.5 m/s 即 `scale ≈ 0.07`），
  两个旋钮干一件事。
- 原作 `OverrideWalkingState` 的五档（Sneak/Walk/Jog/Run/Sprint）。[ME:INFERRED 02 §2.2]
  除 Walk 外四档在语料里被判为动画混合阈值而非速度钳，照搬等于发明；任意上限用
  `SpeedCap` 表达。

## 2. 类型

### `Status`（`scripts/player/status/status.gd`）

```gdscript
class_name Status
extends Resource

## 解除时的寻址依据。空 tag 的 Status 只能靠来源或"清空全部"移除。
@export var tag: StringName = &""

## 瞬时钩子：施加那一刻执行一次。
func fire(_player) -> void:
    pass

## 持续钩子：每 tick 把自己折进解析结果。
func resolve(_into: StatusResolution) -> void:
    pass

## 施加后是否留在列表里。fire-only 的返回 false，施加即弃。
func is_sustained() -> bool:
    return false
```

一个基类、两个可选钩子，不是两套继承体系。`fire` 与 `resolve` 都不重写的 Status 是
无意义的，但不构成错误。

### `StatusResolution`（`scripts/player/status/status_resolution.gd`）

`RefCounted`，每 tick 重建一次，全部字段具名：

```gdscript
var speed_scale: float = 1.0
## 当集合用：StringName -> true。Dictionary 而非 Array，因为读取端问的是"在不在里面"。
var blocked_moves: Dictionary = {}
var forced_view: int = ForcedView.NONE   # NONE | FIRST | THIRD
```

### `StatusList`（`scripts/player/status/status_list.gd`）

`RefCounted`，挂在 `Player.statuses`。**不碰场景树、不查询物理**，因此可以脱离物理世界
单测——与 `FallTracker`、`SpeedEnergy` 完全同构。

条目记录同样具名：

```gdscript
{status = <Status>, source = <Object 或 null>, seconds_left = <float，-1 表示不倒计时>}
```

三个施加入口，生命周期由**调用哪个方法**决定，而不是由 Status 自己声明——同一条
`SpeedCap` 可以被体积按住、被剧情锁死、或被某个 Move 挂 0.7 秒：

| 方法 | 生命周期 |
|---|---|
| `apply_held(status, source)` | 跟随来源。`source` 撤销或失效即移除 |
| `apply_latched(status)` | 挂到被解除。只有 `Unlock` 或复活能拿掉 |
| `apply_timed(status, seconds)` | 倒计时归零自动移除 |

移除：`remove_by_tag(tag)`、`remove_by_source(source)`、`clear_all()`。

**重复施加按 `(status, source)` 去重**，不叠加。同一个 `Status` 资源被同一个来源再次施加
是 no-op；`apply_timed` 是唯一的例外，它刷新 `seconds_left`（重复触碰铁丝网应当续上硬直，
而不是排队）。没有层数概念——`SpeedCap(0.5)` 挂两次仍是 0.5。

不去重的话，一个 `once = false` 的 LATCH 体积被反复进出会把同一条 Status 无限追加进
列表；`min` / 并集折叠看不出差别，但列表会无界增长，而 `remove_by_tag` 只拿掉一条。

`resolve()` 按**施加顺序**遍历，返回新的 `StatusResolution`。

## 3. Status 清单

| 类 | 类型 | 字段 |
|---|---|---|
| `LineStatus` | fire-only | `text: String` |
| `StaggerStatus` | fire-only | （无） |
| `UnlockStatus` | fire-only | `target_tag: StringName`，空 = 清空全部 |
| `SpeedCapStatus` | 持续 | `scale: float = 1.0` |
| `BlockMovesStatus` | 持续 | `moves: Array[StringName]` |
| `ForceViewStatus` | 持续 | `view: int`（FIRST / THIRD） |

合并规则（写在 `StatusResolution` 的类注释里，作为读者查阅的唯一出处）：

| 通道 | 规则 | 为什么 |
|---|---|---|
| `speed_scale` | `min` | 从 0.3 的窄道踏进重叠的 0.5 大厅体积不该变快 |
| `blocked_moves` | 并集 | 禁用是单向的，任何一条说禁就是禁 |
| `forced_view` | 最后加入者 | 一人称与三人称之间没有"更严格"一说。顺序是显式的施加顺序，与场景结构无关 |

## 4. 落点表

每条持续 Status 接到**既有的单一读取点**，各个 Move 不知道 Status 存在。

| 通道 | 落点 |
|---|---|
| `speed_scale` | `Player.speed_cap()`（`player.gd:3519`）末尾乘系数。所有问"极速是多少"的地方都走这里；`MoveConfig.speed_modifier`（下蹲 0.4）是同一形状的既有先例 |
| `forced_view` | `CameraRig` 新增 `forced_view` 覆盖字段。**`third_person` 存盘偏好一字节不动**——`camera_rig.gd:1033` 的 `toggle_third_person()` 每次都 `save_preferences()`，共用字段会让玩家进一次室内偏好被永久改写。覆盖生效期间 V 键无效 |
| `blocked_moves` | 见下方分路由 |

`speed_cap()` 被缩小时，速度能量**不清空**：能量的累积闸门本身就按
`speed_cap() * move_speed_modifier` 度量（`player.gd:3587`，注释里已写明下蹲的同款理由），
所以限速期间照常存能，解除瞬间即可恢复原速。

### 4.1 `blocked_moves` 必须分路由

**`MoveManager.can_enter()`（`move_manager.gd:30`）不是唯一闸门。** `physics_update()`
第 173 行确实让每一次转换都经过它，但有三个动作在**返回状态名之前**就已经把事做了，
在 `can_enter()` 拦下它们只会产生半完成状态：

- **`JUMP`** — `walking_move.gd:29` 先 `player.velocity.y = base_jump_z` 再
  `return JUMP`。在 `can_enter()` 拦 = 人被弹上天但状态还是 Walking。
- **`SLIDE`** — `walking_move.gd:69` 先花掉 `consume_roll()` 的预输入、施加 floor-snap
  并 `move_and_slide()`，再 `return SLIDE`。
- **`SKILL_ROLL`** — `airborne_move.gd:318` 先消费预输入、再按 `rolled = true` 调
  `_apply_landing_cost()` 结算保速，最后才 `return SKILL_ROLL`。在 `can_enter()` 拦 =
  没翻滚但速度按翻滚保住了。

作者面向的词汇保持统一（数组里照样写动作名），路由在实现里：

| 动作 | 拦截点 |
|---|---|
| `JUMP` | `Player.consume_jump()` / `consume_jump_no_coyote()` 直接返回 false，整个分支不进 |
| `SLIDE` | `walking_move.gd` 的 `if player.consume_roll():` 之前加闸，预输入不花 |
| `SKILL_ROLL` | `airborne_move.gd` 的 `rolled` 判定，**短路在 `consume_roll()` 之前**，预输入不吞，落地后仍可接滑铲 |
| 其余（`WALL_RUN` `WALL_CLIMB` `GRAB` `LADDER` `ZIPLINE` `SWING` `TURN_180` `COIL` `SPEED_VAULT` `CROUCH`） | `MoveManager.can_enter()` |

**不可锁清单**：`WALKING` / `FALLING` / `LANDING` / `FALL_UNCONTROLLED`。锁了会卡死状态机
或让人凭空悬空。`ModifierVolume` 在 `_get_configuration_warnings()` 里报（编辑器可见），
`StatusList` 在运行时 `push_error`。

### 4.2 `StaggerStatus`

在 `MoveManager.physics_update()` 里 `_turn_requested()` 的**同一个位置**检查
`player.pending_stagger` 并转 `LANDING`——`_turn_requested()`（Q 键 → `TURN_180`）已经是
"管理器自己发起一次转换"的既有先例，不是新开的口子。

复用 `LandingMove` 及其 `LandingConfig`（2 s 锁定、红 tint、低头）。铁丝网吃 2 秒可能偏
长，但那是 `LandingConfig.lockout_time` 上的旋钮；等它真的需要和落地分家时再拆
`StaggerMove`。来自 `FALL_UNCONTROLLED` 的不受理（已经在死了）。

## 5. `ModifierVolume`（`scripts/level/modifier_volume.gd`）

`@tool` + `Area3D`，形状由作者自己挂 `CollisionShape3D` 子节点——与 `Checkpoint` 同款。
`_ready()` 里 `add_to_group("modifier_volumes")`，进出用 duck-typed 回调，与
`InterestLine` 维护 `Player.interest_lines` 同款。

```gdscript
@export var statuses: Array[Status] = []
@export var mode: Mode = Mode.WHILE_INSIDE   # WHILE_INSIDE | LATCH | TIMED
@export var duration: float = 0.0            # 仅 TIMED
@export var once: bool = false
```

- `mode` 只管持续型 Status，映射到 `StatusList` 的三个施加入口
  （`WHILE_INSIDE` → `apply_held(status, self)`）。
- fire-only 的 Status（台词、硬直、解锁）无视 `mode`，进入即触发一次。
- `once`：触发过就不再触发，直到复活重置。

体积上的 `tag` **不单独存在**——tag 是 Status 自己的字段。逐个技巧解锁需要各自的 tag，
把它放在体积上会强迫作者为每个 tag 拆一个体积。

## 6. 死亡与复活

`Arena.reset_player()` 是所有复活路径的唯一汇合点（R 键、掉出世界、`DeathSequence` 的
`finished`），在其中：

1. `player.statuses.clear_all()`
2. 遍历 `modifier_volumes` 组，清 `once` 已触发标记
3. **重新施加玩家当前重叠的体积**

第 3 步是必需的，不是保险。开场关卡的病房把 LATCH 状态盖在出生点上：玩家出生在体积
里，死一次后身体从未离开过该体积，`body_entered` 不会重放——不补这一步，复活后玩家
反而"痊愈"了。`reset_state()` 里 `interest_lines.clear()` 的注释已经写明了同一条根因：
复活是从体积里瞬移出去，区域永远不会报告离开。

## 7. 观察 signal

`StatusList` 发 `status_applied(status)` / `status_removed(status)`。**只报告，不投票。**
HUD、音效、教程提示、调试面板挂这上面。

判定不走 signal：Godot 的 signal 不能返回值（`emit_signal()` 返回 `Error`），要否决就得
每次分配一个可变事件对象，而派发顺序取决于连接顺序、也就是取决于场景树结构——
"玩家能不能跳"会随着在编辑器里拖动节点而改变。而且这与 CLAUDE.md 的核心架构冲突：
每一个"能不能从 X 到 Y"有且只有一个答案。判定用折叠（确定、可打印、顺序无关），
通知用 signal（松耦合、随便加）。

## 8. 测试

按 `.claude/skills/tuning-dials-not-rules`：`SpeedCap` 的 0.5、硬直时长这类**表现值不写
断言**。写结构性不变量：

- 折叠：两条 `SpeedCap` 重叠取 min；`blocked_moves` 取并集；`forced_view` 取最后加入者
- 生命周期：`WHILE_INSIDE` 出体积必还原；`LATCH` 出体积不还原；`apply_timed` 到点自动消失
- `once`：触发后不再触发
- 复活：`clear_all()` 后列表为空、`once` 已重置、**且当前重叠的体积被重新施加**
- `ForceView` 生效并解除后，`camera_rig.third_person` 与进入前逐字节相同
- `BlockMovesStatus([JUMP])` 时按跳跃键，`velocity.y` **不变**（专盯 4.1 的半完成状态）
- `BlockMovesStatus([SKILL_ROLL])` 落地后速度按**未翻滚**结算
- 不可锁清单里的名字进数组会 `push_error`

前四组不需要物理世界（`StatusList` 是 `RefCounted`）。

## 9. 已知风险

- **`ModifierVolume` 的首帧重叠**。玩家出生在体积内时 `body_entered` 是否在第一个物理帧
  触发，需实测确认；`Arena.reset_player()` 会跳过一个物理帧
  （`_resetting_physics`），第 6 节第 3 步的主动重查是对这条的正面处理，不依赖信号时序。
- **`SPEED_VAULT` 被拦时 `pending_vault_variant` 不会被清**。该字段由读取方清除，拦下后
  无人读取。下一次合法翻越会在返回前覆写它，因此无害——但这是"一次性字段"约定的一个
  边角，实现时确认而非假设。
