# 踏板跳（SpringBoard）设计

复刻原版 `TdMove_SpringBoard`：两次蹬踏、无重力窗口、全游戏最大的纵向冲量。
忠实 ME1 —— 不采用 Catalyst「StepUp 顶点前按空格」的规则（那会让每一处
矮台都变成二段跳点，关卡语言割裂），触发由**地形**决定，和原作一样。

## 证据与裁定

### CDO（A1 附录，✅ 全量已核对）

```
SpringBoardJumpZ             950 uu/s  →  9.5 m/s
SpringBoardJumpXYAdd        -100 uu/s  → -1.0 m/s   （负数：用水平速度换高度）
SpringBoardJumpXYMin         400 uu/s  →  4.0 m/s
SpringBoardMinHeight          80 uu    →  0.80 m    ┐ 第二个落脚点相对脚的高度范围
SpringBoardMaxHeight         148 uu    →  1.48 m    ┘
IntermediateFootPlantHeight   64 uu    →  0.64 m    第一个落脚点相对脚的高度
IntermediateFootPlantDistance 112 uu   →  1.12 m    两个落脚点的水平间距
StepTime1 / StepTime2         0.2 s / 0.2 s         两次蹬踏
PawnPhysics                   PHYS_Flying           蹬踏期无重力
bCheckForGrab / VaultOver / WallClimb   True        起跳后仍检查
bCheckExitToFalling           True
CheckDistanceTime             1.0 s                 ❓ 无释义，本设计不用
```

🔶 g = 16 时 9.5 m/s 峰高 2.82 m；✅ owner 实测「可以跳 2 米多」吻合。

### ✅ owner 实机探明：触发是地形组合，不是触发器

原作没有 SpringBoard 触发器体积。满足条件的**两个落脚点**本身就是踏板：

- 两个可踩点，高差 0.6 m、水平间距 1 m；**没有宽度或踏面深度要求**——
  两根相距 1 m 的柱子，一根 0.6 m 一根 1.2 m，也能触发。
- 面朝方向偏离两点连线 53° 以内。
- 按空格触发。

两个 CDO 参数由此对上：`IntermediateFootPlant*` 就是「第二只脚踩在哪」——
这一跳有两次蹬踏，第一次在近的那点，第二次在远的那点。

⚠️ 53° 在 CDO 里没有对应字段，标 `[ME:COMMUNITY]`（owner 实测行为，无出处）。

### 项目自定

- **触发距离 1.2 m**：脚距第一个落脚点的水平距离上限。`CheckDistanceTime = 1.0 s`
  字面是「一秒路程内」，全速下 7 m，明显不是触发距离；owner 未量过，裁定 1.2 m，
  做成旋钮。
- 各容差与采样密度（见探测）。
- 每段弧线的小顶点高度。

## 探测规则：`Probes.springboard_query()`

找的是**两个落脚点**，不是立面 + 踏面。

1. **第一个落脚点 `plant_1`**：沿身体前向、脚前 0 ~ `trigger_distance`（1.2 m）
   逐点采样（步长 0.1 m），每点从高处向下做一次**形状投射**（脚掌大小的球，
   `SphereShape3D`，半径 `plant_probe_radius` 0.12 m）——柱子可能比胶囊细，
   射线会从旁边穿过去。取第一个顶面高出脚 `plant_1_height ± plant_height_tolerance`
   （0.64 ± 0.2 m）的点。
2. **第二个落脚点 `plant_2`**：以 `plant_1` 为圆心，在半径
   `plant_spacing ± plant_spacing_tolerance`（1.12 ± 0.3 m，取 3 圈）、
   身体前向 ±`approach_angle_deg`（53°）的扇形内采样 7 个方位，同样向下投射，
   找顶面高出脚 `plant_2_min_height ~ plant_2_max_height`（0.8 ~ 1.48 m）的点。
   扇形就是「角度对了才触发」：两点连线必须落在面朝方向 53° 以内。
3. **站得住**：`plant_1`、`plant_2` 都过 `Player.fits_standing_at()`
   （`ShapeCast3D`，身体有宽度）。Probes 只回答几何，「身体放不放得下」是
   Player 的事——与 §34 的分层一致。
4. 返回 `{valid, plant_1, plant_2}`（两个世界坐标脚落点）；任一环节不命中返回
   `_no_hit()`。

不做的：不检测宽度/深度；不做触发器；不在空中问（`AirborneMove` 不调用它，
原作只从 Walking 进入）。

## `SpringBoardMove`

新文件 `scripts/player/moves/spring_board_move.gd`，`Move.SPRING_BOARD`，
继承 `ScriptedMove`（与 `SpeedVaultMove` 同族）。

### 进入

`WalkingMove` 在处理 `consume_jump()` 之前：`grounded`、`input.jump_pressed`
（含缓冲的按下）、`can_enter(SPRING_BOARD)` 时问一次 `springboard_query()`。
命中则：

- `player.pending_spring_board = hit`（一次性字段，读取方清空，与
  `pending_vault_variant` 同一约定）；
- 消耗这次跳跃（`consume_jump()`，缓冲不得留到落地再蹦一次）；
- 返回 `SPRING_BOARD`。

没命中照旧走 JUMP。

### 两次蹬踏

进入时**先**读水平速度 `h`（`LineWalkMove.enter` 同一个坑：归零之后就读不到了），
`lock_input()` 0.4 s，`set_grounded(true)`——脚在东西上，声明而不是推断。

- 段 1（`step_time_1` 0.2 s）：脚从当前位置到 `plant_1`，`ScriptedMove.begin()`
  贝塞尔，顶点 `plant_arc_height`（0.15 m，项目旋钮）高于两端较高者，
  `control_bias` 取「先起后送」。
- 段 2（`step_time_2` 0.2 s）：`plant_1 → plant_2`，同样一段弧。

胶囊位置 = 脚落点 + 半身高，直接写位置（`SpeedVaultMove` 的做法）；无重力——
蹬踏期完全由脚本驱动，这就是 `PHYS_Flying`。模型 `pin_visual_yaw` 朝
`plant_1 → plant_2` 的水平方向；胶囊与视线不动（原作 `ControllerState =
PlayerWalking`，视角自由，无视线约束）。

### 抛出

段 2 结束那一帧：

```
dir      = (plant_2 - plant_1) 水平归一
xy       = max(h + xy_add, xy_min)        = max(h - 1.0, 4.0)
velocity = dir * xy + UP * jump_z         jump_z = 9.5
```

`fall_tracker.reset(当前高度)`；`unlock_input()`；返回 **`JUMP`**。
空中由 `JumpMove` 接管：coil、grab、vault、wallclimb 检查与落地判定全部现成，
对应 CDO 的 `bCheckForGrab / VaultOver / WallClimb / bCheckExitToFalling`。

### 中断

- `_aborted`（`pending_spring_board` 为空）→ 第一帧返回 WALKING。
- 蹬踏期不接受任何输入（已锁），不检查 grab / vault（原作那三个 `bCheckFor*`
  是起跳后的事，起跳后已交给 `JumpMove`）。
- 无 `redo_move_time`（CDO 无此字段）。

## 配置：`SpringBoardConfig`

`scripts/player/config/moves/spring_board_config.gd`，挂进 `MovementConfig`
聚合根（`spring_board`），`presets/default.tres` 加子资源。

| 字段 | 值 | 标记 |
|---|---|---|
| `jump_z` | 9.5 | `[ME:CONFIRMED]` |
| `xy_add` | -1.0 | `[ME:CONFIRMED]` |
| `xy_min` | 4.0 | `[ME:CONFIRMED]` |
| `plant_1_height` | 0.64 | `[ME:CONFIRMED]` |
| `plant_spacing` | 1.12 | `[ME:CONFIRMED]` |
| `plant_2_min_height` / `plant_2_max_height` | 0.8 / 1.48 | `[ME:CONFIRMED]` |
| `step_time_1` / `step_time_2` | 0.2 / 0.2 | `[ME:CONFIRMED]` |
| `approach_angle_deg` | 53 | `[ME:COMMUNITY]` |
| `trigger_distance` | 1.2 | 项目自定 |
| `plant_height_tolerance` | 0.2 | 项目自定 |
| `plant_spacing_tolerance` | 0.3 | 项目自定 |
| `plant_probe_radius` | 0.12 | 项目自定 |
| `plant_arc_height` | 0.15 | 项目自定 |

`MoveConfig` 的行为开关：`constrain_look = false`、`freeze_visual_yaw = true`
（蹬踏期模型钉在两点连线方向）、`allows_turn = false`。

## 表现层

- **动画**：`CharacterAnimator` 加 `Move.SPRING_BOARD` 分支——蹬踏期
  `_first_available([&"StepUp", &"Jump_Start", &"jump"])`，`scripted_duration()`
  返回 0.4 s 由 `_scripted_fit()` 拟合（`StepUp` 0.67 s → 1.7×）。起跳后是
  `JumpMove` 自己的空中片段。库里没有专门的踏板跳片段，以后可换。
- **镜头**：不加滚转、不加 FOV；脚本驱动的位移由现有镜头规则处理
  （docs/camera-authority.md）。
- **调试 HUD**：`scripted` 行通过 `path_debug()` 显示当前段路径。

## 关卡与调试

`balance_course.tscn` 或新白盒里摆两根柱子（0.64 m 与 1.24 m 高，相距 1.12 m），
第一/第三人称各跑一遍。不需要任何标记节点。

## 测试

`tests/test_spring_board.gd`，全部用 `TestWorld` + 两根柱子（StaticBody 盒子）：

1. 面朝两柱、脚距第一根 ≤ 1.2 m、按空格 → 进入 `SPRING_BOARD`，不是 `JUMP`。
2. 只有一根柱子 → 普通 `JUMP`。
3. 两柱连线偏离面朝 70° → 普通 `JUMP`。
4. 脚距第一根 2 m → 普通 `JUMP`。
5. 蹬踏期：0.2 s 时脚在第一根柱顶、0.4 s 时脚在第二根柱顶（容差 5 cm），
   期间 `grounded` 为真、输入被锁。
6. 抛出：交给 `JUMP` 那一帧 `velocity.y == jump_z`，水平速度 =
   `max(进入速度 - 1.0, 4.0)`，方向为两柱连线；`fall_tracker` 已重置。
7. 柱顶放不下身体（`fits_standing_at` 假）→ 普通 `JUMP`。
8. 动画路由：`SPRING_BOARD` 分支存在（`test_every_move_has_its_own_case`
   自动覆盖），蹬踏期请求 `StepUp`，`scripted_duration()` = 0.4。
9. `test_config_layout` / 生成场景测试因新增 `MovementConfig.spring_board`
   需要更新的一并更新；`check_references.gd` 过一遍 `default.tres`。

不测的：弧线顶点高度、手感数值——这些是旋钮。

## 已知空白

- `CheckDistanceTime = 1.0 s` 含义未明；触发距离 1.2 m 是裁定值，等 owner 实测
  后改旋钮即可。
- 53° 是实测行为，无 CDO 出处。
- 无专门动画片段。
