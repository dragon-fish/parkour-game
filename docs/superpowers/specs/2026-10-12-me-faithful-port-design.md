# ME 原版逻辑复刻：设计与执行清单

> 目标只有一个：**手感几乎一比一复刻 Mirror's Edge**，包括本项目尚未实现的动作。
> 纯战斗动作（踢腿类）只做移动与动画，不做攻击判定。动画素材用 UAL 1 / UAL 2 完整版。
> 验收方式：所有者最后做一次真人冒烟测试。
>
> 本文同时是执行清单与审计记录，供上下文压缩后续接。勾选状态随进度更新。

## 1. 原则

1. **移植逻辑，不移植现象。** 以反编译出的原版代码为准，原样搬运它的结构、
   判定顺序与瑕疵。速通 glitch 不是要实现的功能，是逻辑原样搬过来以后自然出现的
   结果。DO NOT 为某个 glitch 单独写规则；DO NOT 顺手"修正"原版的 bug
   （例如 `TdMove_WallrunJump` 里结果被丢弃的 `FMax(0, PushSpeed)`）。
2. **原版证据压过推理。** 现有实现中凡是推理所得的机制（包括转向损速、
   `look_redirect` 等），一旦拿到原版逻辑就以原版为准替换。
3. **单位换算是唯一的翻译。** 1 uu = 1 cm；UE3 旋转单位 65536 = 360°；
   UE3 Z 轴向上，Godot Y 轴向上。公式、常数、判定顺序保持原样。
4. **证据分级沿用 `[ME:...]` 标签**。读自反编译代码的结论标 `[ME:CONFIRMED decompile]`，
   附上类名/函数名（脚本层）或地址（原生层）。
5. **版权边界。** 反编译的原始输出留在 `_local/me-re/`（不入库、可随时重生成）。
   公开仓库只写推导后的公式、常数和行为描述。

## 2. 证据来源与工具链（已建成）

| 层 | 来源 | 工具 | 输出 |
| --- | --- | --- | --- |
| 脚本层 | `TdGame.u` / `Engine.u` / `Core.u` 的 UnrealScript 字节码 | `_local/me-re/uedump`（UELib 1.13.7，`BuildName.MirrorsEdge`） | `_local/me-re/script/`（运算符已解析）、`script_raw/`（运算符保留为 `__NFUN_n__`） |
| 原生层 | `MirrorsEdge.exe`（SteamStub 2.1 壳，`.text` 未加密，基址 0x400000） | Ghidra 12.1.4 持久化工程 `_local/me-re/ghidra/`，脚本 `ghidra_scripts/{DecompileTree,StringRefs}.java`，包装 `native/decomp.ps1`、`native/run_script.ps1` | `_local/me-re/native/*.c` |

已知陷阱：

- UELib 美化输出**丢括号**。凡是 `&&` / `||` 混用的条件，必须用 `script_raw/` 核对。
  已经抓到一例：`TdMove_WallClimbDodgeJump.CanDoMove` 的真实结构是
  `State==6 && (Hint==2 || Hint==1)`。
- 原生 exec 函数的注册名是 UTF-16 的 `int<Class>exec<Func>`，`.data` 段里是
  `{名字指针, 函数指针}` 表。exec 外壳只负责解析参数，真正的实现是虚函数：
  例如 `ATdPawn` 的虚表在 `0x01d05268`，`GetSprintAcceleration` 在槽位 `0x418`。
- 原生代码按**偏移**访问字段。要把偏移还原成属性名，必须先算出类的内存布局
  （见 Phase 0）。
- 安装目录中的 `MirrorsEdge.exe`、`TdGame.u`、`Engine.u` 于 2026-08-17 被
  Mirror's Edge Tweaks 改过。反编译出的脚本里没有任何 Tweaks 引用，逻辑看起来
  未被改动，但 `[ME:CONFIRMED]` 的数值仍应在可获得原件时复核。

## 3. 原版结构（复刻的骨架）

脚本层已经确认：

- **按键动作仲裁**：`TdPlayerMoveManager.HandleMoveAction(Action)`。
  先交给当前 move 的 `HandleMoveAction`；如果状态没变，再按
  `switch(当前状态)` × `Action` 依次询问候选 move 的 `CanDoMove()`，第一个返回
  true 的执行 `SetMove`。这张表就是按键语义的全部来源。
- **自动转移**（`bCheckForGrab`、`bCheckForVaultOver`、`bCheckForWallClimb`、
  `bCheckForEdgeInVelDir`、`bCheckExitToFalling` 等）在脚本里只声明不读取，
  **由原生层消费**。仲裁顺序要从原生 tick 里读出来。
- **`OldMovementState` / `PendingMovementState`** 被大量 `StartMove` 用来分支
  （Landing 8 处、Falling 5 处、IntoClimb 4 处……）。许多动作在结束时会**强制进入一帧
  Walking**（`SetMove(1)`），这一帧会改写 `OldMovementState`，并执行
  `Walking.StartMove`（例如清零 `bIllegalLedgeTimer`）。复刻必须保留这个语义。
- **控制器状态**（`PlayerWalking`、`PlayerWallWalking`、`PlayerGrabbing`……）由 move 的
  `ControllerState` 切换，`PlayerMove` 在其中计算加速度：冲刺判定、点按急停，以及
  在 `PHYS_Falling` 下走 `GetSprintAcceleration`。
- **视角约束**：`TdMove.ConstrainAxis`。超出范围时按 `超出量 × dt / 0.2` 往回拉，
  期间朝外的输入照常生效、朝内的输入被吃掉。

本项目现有的架构写在 `CLAUDE.md` 里："X→Y 的唯一答案写在 X 的 `physics_update` 里"。
这和原版不同构。复刻时改成：

- `MoveManager` 持有一张从 `TdPlayerMoveManager` 搬来的**动作仲裁表**；
  每个 move 提供 `can_do_move()` 与 `handle_move_action()`。
- 自动转移按原生层读出的顺序，统一由 `MoveManager` 或物理 tick 询问开关。
- move 上提供 `old_movement_state` 语义，以及"强制一帧 Walking"的语义。
- `CLAUDE.md` 的 Architecture 一节随之改写。

## 3.1 Godot 侧的移植架构

**只替换模拟层，表现层原样保留。** 镜头（`CameraRig`）、动画（`CharacterAnimator`）、身体朝向、
关卡标注（InterestLine、状态效果、踉跄/击倒）继续消费模拟层给出的速度、状态名和事件；
它们不是原版逻辑的移植对象。

模拟层按原版的分层重组：

| 原版 | 本项目 |
| --- | --- |
| `TdPawn` 的移动字段（`MovementState`/`OldMovementState`/`PendingMovementState`、`MoveActionHint`、`SpeedSprintEnergy`、`EnterFallingHeight`、`LastJumpLocation`、`bIllegalLedgeTimer`、`MoveNormal`、`Floor`……） | `Player` 上同名（snake_case）字段 |
| `TdPawn.SetMove`（Pending → 旧 move `StopMove` → Old = 旧 → 切换 → 旧 move `PostStopMove` → 新 move `StartMove`，可在 `StartMove` 里重入） | `MoveManager.set_move()`，与现有"`physics_update` 返回下一个状态名"并存：返回值等价于一次 `set_move` |
| `TdMove.CanDoMove`（`RedoMoveTime` 从 `LastStopMoveTime` 起算）及各子类覆盖 | `Move.can_do_move()` |
| `TdPlayerMoveManager.HandleMoveAction` | `MoveManager.handle_move_action(action)`，整张表照搬（15.3） |
| `TdPlayerController` 的按键函数（`CheckJumpPressed`、`CheckJumpReleased`、`CheckCrouch`、`LookBehind`、`AttackPress`） | `Player` 每帧把按键翻译成 `MA_*` 动作；新增近战键 |
| 控制器状态里的 `PlayerMove`（`PlayerWalking`、`PlayerWallWalking`、`PlayerGrabbing`……） | 按 move 的 `controller_state` 选择的加速度计算，地面/空中用 `PawnAcceleration` |
| 原生物理模式（walking / falling / 墙跑 / 蹬墙 / 无物理的精确定位） | `Player` 上的物理推进函数，按 move 的 `pawn_physics` 分派，建在 `move_and_collide` 之上 |
| `TdMove.ConstrainAxis` | `CameraRig` 的视角约束，按原版 0.2 s 指数回拉改写 |

本项目自创、原版没有的机制（土狼时间、跳跃缓冲、`look_redirect`、拟合出来的能量曲线等）
在对应部分移植完成时一并删除。删除前确认它不是表现层的东西。

## 4. 阶段与清单

### Phase 0 — 原生层逆向（关键路径）

- [x] 脚本层全量反编译（Core / Engine / TdGame）
- [x] Ghidra 持久化工程、批量反编译与字符串反查脚本
- [x] 定位 `ATdPawn` 的注册（对象大小 0x8f8）、构造器、虚表 0x01d05268
- [x] 反编译 `GetSprintAcceleration`、`GetWalkAcceleration`、`GetMobilityMultiplier`、
      `UpdateWalkingState`、`UpdateVelocityVariables` 的实现
- [ ] **布局计算器**：从反编译出的 `.uc` 变量声明，按 UE3 链接规则算出
      Object → Actor → Pawn → GamePawn → TdPawn（以及 TdMove 家族）的字段偏移。
      用已知偏移校验：`Actor.Physics = 0x68`、`Actor.Velocity = 0x100`、`sizeof(ATdPawn) = 0x8f8`
- [ ] 读出原生常数（`DAT_*` 浮点数）
- [ ] 改写成可读的公式：加速度、转向惩罚、能量曲线的用法、`UpdateWalkingState`、
      `UpdateVelocityVariables`
- [ ] 找到原生物理：`physWalking`（UE3 标准 + DICE 改动）、`physFalling`（空中操控）、
      `PHYS_WallRunning`（12）、`PHYS_WallClimbing`，以及重力倍率
- [ ] 找到自动转移的仲裁顺序（`bCheckFor*` 的消费点）
- [ ] 原生探测函数：`FindWallSide`、`FindWallForward`、`FindLedge(Ex)`、
      `FindLedgeInFrontOfPlayer`、`MovementTrace*`、`IsOkToJump`、`IsLandingOnSoftObject`、
      `FloorDeclineTooSteep`、`CheckDoubleJump`、`DetectPossibleHandPlant`、`IsHangingFree`、
      `CheckWallLegPlacement`、`CheckValidFloor`、`CheckAgainstWall`
- [ ] `bIllegalLedgeTimer` 的消费者
- [ ] 结论写入 `docs/mirrors-edge-deep-research/15-原版逻辑反编译.md`（只写公式与行为）

### Phase 1 — 移动内核

- [ ] 地面：`PlayerWalking.PlayerMove`（冲刺判定 0.7/0.7、点按急停 35 uu/s、
      `StoppingVelocity`）+ `GetWalk/SprintAcceleration` + `physWalking`
- [ ] 空中：`PHYS_Falling` 的加速度来源与原生空中操控
- [ ] 速度能量、转向惩罚：用原版公式替换 `SpeedEnergy` 中推理出来的部分
- [x] 视角约束：`ConstrainAxis` 的 0.2 s 指数回拉（已移植的墙面家族走原版 `UpdateViewRotation`）

### Phase 2 — 仲裁与状态语义

- [ ] `MoveManager` 动作仲裁表（`TdPlayerMoveManager` 全表）
- [ ] 每个 move 的 `can_do_move()` 按原版 `CanDoMove` 改写
- [ ] `old_movement_state`、"强制一帧 Walking"、`RedoMoveTime`、`DisableMovementTime`
- [ ] 自动转移开关与仲裁顺序（来自 Phase 0）

### Phase 3 — 墙面家族

- [x] WallRun（左/右，`FindWallSide` / `FindWallForward`，连续滑墙计数，`ReachedWall`）
- [x] WallRunJump（独立状态 12；`p` 不钳制）
- [x] WallRunDodgeJump（34）
- [x] WallClimb（6）与 WallClimbDodgeJump（49；51/52 无人设置，不注册）
- [x] WallClimb180TurnJump（50）
- [x] MeleeWallrun（62：速度旋转 ±6000、×1.2，结束时强制 Walking）
- [x] 墙面物理 `physWallRunning` / `physWallClimbing`、原生探测（`FindLedgeEx` / `FindLedge` /
      `FindAutoMoveLedge` / `CalculateRelativeExtent` / `MovementTrace*`）、完整的 `CheckAutoMoves` 顺序、
      `bIllegalLedgeTimer` 的三个消费者、`PlayerWallWalking`、`ConstrainAxis`（W2a）

### Phase 4 — 踢腿类（无攻击判定）

- [ ] Melee（17）、MeleeAir（32，含落地直接进 Walking）、MeleeSlide（48）、
      MeleeCrouch（63）、MeleeVault（53）、MeleeAirAbove（82，需要目标，可先只保留移动）
- [ ] Barge（19）/ AirBarge（85）：撞门

### Phase 5 — 其余跑酷动作

- [ ] 逐项对照原版重写现有动作：Walking、Falling、Jump、Landing、SoftLanding、
      SkillRoll、Coil、Slide、Crouch、SpeedVault、VaultOver（9）、IntoGrab、Grab、
      GrabPullUp（10）、180Turn、180TurnInAir、ZipLine、Swing、Ladder（IntoClimb/Climb）、
      Balance、LedgeWalk、SpringBoard、DodgeJump、FallingUncontrolled、LayOnGround
- [ ] 新增：GrabJump（13）、GrabTransfer（31）、JumpIntoGrab（67）、SwingJump（73）、
      StepUp（37）、AutoStepUp（81）、RumpSlide（38）、Stumble（35）、StumbleHard（55）、
      StumbleFalling（77）、Vertigo（47）、Interact（39）
- [ ] WallKick（23）：原版 `CanDoMove()` 恒为 false，是死代码。保留同样的结论，不实现

### Phase 6 — 动画

- [ ] 为新增动作在 UAL 1/2 中挑 clip，接入 `CharacterAnimator` 的 priority list
      （body 可选，任何 clip 都不能假定存在）

### Phase 7 — 收尾

- [ ] 结构性测试（不变量，不测调参值）：仲裁表顺序、强制 Walking 帧、
      `OldMovementState` 分支
- [ ] 更新 `CLAUDE.md`、`docs/feel-backlog.md`（标注被原版逻辑取代的条目）、语料各章的"未确证"项
- [ ] 合并前跑一次全量测试（已知有 4 条常驻失败）

## 5. 已从脚本层读出的关键事实（Phase 0 之前的发现）

- `TdMove_Landing.SubtractLandingSpeed`：水平速度压到 `PreJumpMomentum − LandingSpeedReduction(65)`。
  条件是上一个状态为起跳类（Falling 且前驱是 Jump 或 MeleeAir、Coil、MeleeAir）、
  当前速度更高、武器类型不是 1。`PreJumpMomentum` 只有 `TdMove_Jump` 会写。
- `TdMove_WallrunJump`：`p = 墙法线 · 镜头水平朝向`（按过 Q 时取墙法线本身）；
  竖直速度由跳高 `100 + 60p` 换算，再除以 `1 + ConsequtiveWallruns`；
  水平速度 = `法线 × (120 + 400p) + 沿墙速度 × (0.1 + 0.9(1 − p))`。`FMax` 的结果被丢弃。
- `TdMove_WallRun.HandleMoveAction(MA_Turn)`：镜头 0.15 s 转到墙法线，`bTurned90FromWall`。
- `TdMove_MeleeWallrun`（无目标时）：速度绕竖直轴旋转 ±6000（约 32.96°）离开墙面，再 ×1.2。
- `TdMove_MeleeAir.Landed`：没有超过硬着陆高度就直接 `SetMove(Walking)`，跳过 Landing。
- `TdMove_WallKick.CanDoMove()` 恒为 false。
- 墙跑中按跳：先问 WallRunDodgeJump，不行再问 WallRunJump。
  垂直蹬墙中按跳是 WallClimbDodgeJump，按转身是 WallClimb180TurnJump。
- `PlayerWalking.PlayerMove`：冲刺要求 `aForward > 0.7 && InputSize > 0.7 && 速度·输入方向 > 0`；
  起步 0.15 s 内松手，速度直接设为 35 并进入 0.25 s 的 `PlayStop`。
- `GetSprintAcceleration`（原生）：按当前水平速度对 `FInterpCurveFloat` 求值；
  转向惩罚是 `− Velocity × F[0x6d0] × |aTurn| × 常数`，最后 `floor(x + 0.5)` 取整。
  字段名待布局计算器确认。
