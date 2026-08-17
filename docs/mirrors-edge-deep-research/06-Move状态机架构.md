# 06 · Move 状态机架构

← [README](README.md) · 上一篇 [05-动作库总览](05-动作库总览.md)

前面几章讲的是**数值**。这一章讲**结构**——而结构比数值更值得抄。数值可以调，结构错了整个项目就废了。

---

## 6.1 全貌

`TdGame.u` 里有 **916 个类**，其中移动相关的约 **114 个**（见 [附录 A1](appendix/A1-TdMove-CDO全量.md)）。继承结构：

```
Object
└── TdMove                        ← 所有动作的基类
    ├── TdMove_Walking
    ├── TdMove_180Turn
    ├── TdMove_Falling
    ├── TdMove_Landing
    ├── TdMove_Balance
    └── TdPhysicsMove             ← 带环境探测能力的中间层
        ├── TdMove_Jump
        ├── TdMove_WallRun
        ├── TdMove_WallClimb
        ├── TdMove_WallKick
        ├── TdMove_Slide
        ├── TdMove_Grab / IntoGrab / GrabJump / GrabPullUp / GrabTransfer
        ├── TdMove_SpeedVault / StepUp / AutoStepUp
        ├── TdMove_Swing / SwingJump
        ├── TdMove_ZipLine / IntoZipLine
        ├── TdMove_Coil / SpringBoard / Barge / AirBarge
        ├── TdMove_Climb / IntoClimb / LedgeWalk / RumpSlide
        └── TdMove_Bot*           ← AI 复用同一套框架
```

驱动它的是 `TdPawn.MoveManagerClass = TdPlayerMoveManager`，可用动作注册在 `TdPawn.MoveClasses` 数组里。

**第一个关键架构决策**：每个动作是一个**独立的类**，不是 `_physics_process` 里的一个 `elif` 分支。动作自带参数、自带进入/退出条件、自带对角色状态的声明。

**第二个关键架构决策**：**AI 和玩家共用同一套 Move 框架**（`TdMove_Bot*` 与玩家 move 并列在同一继承树下）。追击你的警察用的是同一个跑酷系统。

---

## 6.2 每个 Move 声明什么

`TdMove` 基类（所有动作都继承）：

| 字段 | 作用 |
|---|---|
| `SpeedModifier` | 该状态下的速度倍率 |
| `FrictionModifier` | 该状态下的摩擦力倍率 |
| `RedoMoveTime` | **冷却**：多久内不能重复触发同一动作 |
| `bTriggersCompliment` | 是否触发"漂亮！"的正反馈 |
| `AiAimPenalties` / `AiAimOneShotPenalties` | **该动作让敌人多难瞄准你** |
| `StickyAngle` / `bStickyAim` | 瞄准粘滞 |

`TdPhysicsMove` 追加的**环境探测开关**：

| 字段 | 作用 |
|---|---|
| `bCheckForGrab` | 该状态下是否检测可抓边缘 |
| `bCheckForVaultOver` | 是否检测可翻越物 |
| `bCheckForWallClimb` | 是否检测可爬墙面 |
| `bCheckForEdgeInVelDir` | 是否沿速度方向检测边缘 |
| `HandPlantCheckDistance/Height` | 手撑点探测（200 / 112 uu） |
| `ContextMoveDistanceMultiplier` | 1.8 — 上下文动作的探测距离放大系数 |

具体 Move 还会声明：

| 字段 | 例子 |
|---|---|
| `PawnPhysics` | `PHYS_Falling`（WallKick、Coil） |
| `ControllerState` | `PlayerWalking` / `PlayerWallWalking`（WallRun） |
| `MinLookConstraint` / `MaxLookConstraint` | 该状态下的**镜头活动范围**（见 [04.1](04-墙面动作.md#镜头约束)） |
| `bConstrainLook` / `bDisableFaceRotation` | 是否锁视角 / 是否禁用身体转向 |
| `*BlendInTime` / `*BlendOutTime` | 动画混合 |

**这套设计的精髓**：一个动作不只是"改变速度"，它同时接管了 **摩擦力、镜头约束、环境探测策略、动画混合、AI 感知难度**。所有这些都是**声明式**的、写在类的默认属性里、可以被 `.ini` 覆盖——**不用改代码就能调整整个游戏的手感**。

⚠️ 特别注意 `AiAimPenalties`：跑酷动作**同时是战斗机制**。做 wallrun 时敌人瞄准难度是 `(Easy=0.4, Medium=0.5, Hard=0.7)`，做 springboard 时是 `(0.3, 0.4, 0.6)`，`AiAimOneShotPenalties` 还会在动作开始瞬间一次性扣掉 75–200 点敌人瞄准精度。**"跑得漂亮"直接等于"更难被打中"**——移动系统和战斗系统在这里是同一个系统。这是很多复刻会忽略的一层。

---

## 6.3 Movement String：显式的动作连携系统

✅ **确证**：

```
TdPlayerPawn.MovementStringAllowedGap = 0.9      ← 秒
TdMove_SpeedVault.VaultTypes[...].bIsStringable = true   ← 只有部分动作可连携
```

游戏内部有一个叫 **"movement string"（动作串）** 的概念：动作之间间隔不超过 **0.9 秒**就算连上了一串。而 `bIsStringable` 标志决定了哪些动作可以入串——[05.7](05-动作库总览.md#57-vault翻越) 里只有中等高度的 `vaultOnto` / `vaultOver` 是可连携的。

⚠️ 连成串的具体收益未确证（可能关联 `bTriggersCompliment` 的正反馈、成就、或时间试炼评分）。但**"连携"是一等公民概念，而不是玩家自己脑补的"手感流畅"**，这一点是确证的。

---

## 6.4 输入层：只有两个上下文动作键

📣 **确证（TdInput.ini 绑定）**：

| 键 | 命令 | 作用 |
|---|---|---|
| Space / LB | `GBA_Jump` | **向上类**上下文动作 |
| LShift / LT | `GBA_Crouch` | **向下类**上下文动作（下蹲/滑铲/翻滚） |
| LCtrl | `GBA_WalkMod` | 走路修饰键 |
| Q | `GBA_LookBehind` | 回头看 |
| R | `GBA_ReactionTime` | 子弹时间 |

**没有独立的 wallrun / wallclimb / vault / roll / coil 按键。** 那 114 个 Move 类全部由**速度 + 朝向 + 环境探测**推导出来。

🎯 与开发者一手说明吻合——记者试玩后写道：

> 「我很惊讶，整段 demo 我只用了三个按键。」

**这才是"镜之边缘-like"在输入层的定义**：动作库可以很大，但按键必须很少；复杂度在**上下文解析**里，不在按键组合里。

---

## 6.5 对 Godot 的架构建议

不要写成一个巨大的 `Player.gd`。对应实现：

| ME (UE3) | Godot 对应 |
|---|---|
| `TdMove` 基类 | 一个 `Move` 抽象基类（`RefCounted` 或 `Node`） |
| `MoveClasses` 数组 | `Dictionary[StringName, Move]` 注册表 |
| `TdPlayerMoveManager` | 一个 `MoveManager` 节点，持有当前 move、处理转移 |
| `.ini` 覆盖 | `Resource`（`.tres`）—— **每个 Move 一份可视化编辑的参数资源** |
| `RedoMoveTime` | 每个 move 一个冷却计时器 |
| `MinLookConstraint` / `MaxLookConstraint` | 由当前 move 提供给相机脚本的视角钳制范围 |
| `bCheckForGrab` 等 | 当前 move 声明本帧要做哪些 shapecast |

**`.tres` 那一行是重点**：DICE 把所有手感参数放进可热改的 `.ini`，这就是他们能把这套系统调到那个程度的原因。在 Godot 里用 `Resource` 复刻这个能力，你才有机会调出接近的手感。手感是**调**出来的，不是**写**出来的——而调的前提是改一个数字不用重新编译。

---

← [05-动作库总览](05-动作库总览.md) · 下一篇 → [07-Catalyst对照](07-Catalyst对照.md)
