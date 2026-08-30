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

### ✅ 2026-08-31 录像实测（`tools/hud_ocr.py`，两次有效踏板跳）

同一处踏板（前低后高两个帆布箱，立面在 X ≈ -33.7，地面 Z = 43.17），
HUD 单位为米，帧率 120：

| 阶段 | 第 1 次 | 第 2 次 | 结论 |
|---|---|---|---|
| 触发点距低箱立面 | 1.2 m | 0.45 m | ≥ 1.2 m 处按空格可触发 |
| 触发 → 到达立面 | 0.20 s，行走速度 5.4 m/s | 0.10 s | 先照常走到立面 |
| 爬升（`PHYS_Flying`） | 0.40 s，Z +1.22，X +1.9 | 0.40 s，Z +1.27，X +2.15 | = StepTime1 + StepTime2 |
| 起跳高度（SZ 重置值） | 44.39 ~ 44.45 | 44.44 | 第二落脚点 ≈ +1.24 m |
| 起跳 → 顶点 | 0.60 s，+2.82 m | 0.60 s，+2.82 m | 9.5 m/s、g = 16 |
| 起跳后水平速度 | 4.5 m/s（行走 5.75 − 1.0） | 4.5 m/s | `XYAdd = -1.0`，高于 `XYMin` |
| 状态 | `SpringBoarding` 持续到顶点才转 `Falling` | 同 | 爬升与上升段都归本 Move |

爬升段 Z 近似匀速上升，没有在 0.64 m 处停顿——两次蹬踏在数据上是一段连续的
0.4 s 爬升，落脚点只决定终点。

🔶 g = 16 时 9.5 m/s 峰高 2.82 m；✅ 实测 2.82 m，两次一致。

### ✅ owner 实机探明：触发是地形组合，不是触发器

原作没有 SpringBoard 触发器体积。满足条件的**两个落脚点**本身就是踏板：

- 两个可踩点，高差 0.6 m、水平间距 1 m；**没有宽度或踏面深度要求**——
  两根相距 1 m 的柱子，一根 0.6 m 一根 1.2 m，也能触发。
- 面朝方向偏离两点连线 53° 以内。
- 按空格触发。

两个 CDO 参数由此对上：`IntermediateFootPlant*` 就是「第二只脚踩在哪」——
这一跳有两次蹬踏，第一次在近的那点，第二次在远的那点。

53° 在 CDO 里没有对应字段，是 owner 实机反复确认的行为，标 `[ME:CONFIRMED]`
（同 05 §5.6 的 owner 实测例）。

### ✅ owner 补充确认（2026-08-31）

- 离地后不触发：只从地面进入。
- 慢走能触发；离 1.2 m 刚起步就按也能触发；紧贴着立面按 W + 空格也能触发
  （触发距离下界是 0）。
- 太远就是普通跳。
- 起跳后按住 W 的空中加速与普通跳一样；**不按 W 飞出时 V = 14.4 km/h = 4.0 m/s**，
  就是 `XYMin`（也是倒走/横走的基础速度）。
- 第二段录像（01.42.53）：蹬踏期扭头 180°，起跳后往镜头方向飞。
- **抛出方向是起跳那一瞬间的镜头方向**，不是两级的法线：斜着进就斜着出。
  两步蹬踏是脚本移动，一旦触发就沿路径走，但期间视角不受限——鼠标转得够快，
  可以在 0.4 s 里扭头 180° 往后面飞出去（社区已知 glitch，照抄）。

### 项目自定

- **触发距离 1.2 m**：脚距第一个落脚点的水平距离上限。录像证明 1.2 m 处按空格
  被接受；更远没有测过，`CheckDistanceTime = 1.0 s` 字面「一秒路程」全速下 7 m
  明显不是。取 1.2 m 做旋钮，是实测下界。
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
   **从面朝方向 0° 开始向两侧交替采样，取第一个命中**：宽台阶上就是面朝方向
   这条线与第二级的交点（斜着进就斜着穿过去），只有两根柱子时才会落到扇形
   边缘。扇形就是「角度对了才触发」：两点连线必须落在面朝方向 53° 以内。
3. **站得住**：`plant_1`、`plant_2` 都过 `Player.fits_standing_at()`
   （`ShapeCast3D`，身体有宽度）。Probes 只回答几何，「身体放不放得下」是
   Player 的事——与 §34 的分层一致。
4. 返回 `{valid, plant_1, plant_2}`（两个世界坐标脚落点）；任一环节不命中返回
   `_no_hit()`。

不做的：不检测宽度/深度；不做触发器；不在空中问（`AirborneMove` 不调用它，
原作只从 Walking 进入）。

## `SpringBoardMove`

新文件 `scripts/player/moves/spring_board_move.gd`，`Move.SPRING_BOARD`。
**继承 `AirborneMove`**（上升段要它的空气物理和探针），**组合一个 `ScriptedMove`
子节点**跑两段弧——`LadderMove._top_exit` 的同一做法（GDScript 单继承）。
一个 Move 走完四个阶段：走到立面 → 两次蹬踏 → 抛出 → 上升到顶点。

### 进入

`WalkingMove` 在处理 `consume_jump()` 之前：`grounded`、`input.jump_pressed`
（含缓冲的按下）、`can_enter(SPRING_BOARD)` 时问一次 `springboard_query()`。
命中则：

- `player.pending_spring_board = hit`（一次性字段，读取方清空，与
  `pending_vault_variant` 同一约定）；
- 消耗这次跳跃（`consume_jump()`，缓冲不得留到落地再蹦一次）；
- 返回 `SPRING_BOARD`。

没命中照旧走 JUMP。

### 阶段 1：走到立面（实测 0.1–0.2 s）

进入时**先**读水平速度 `h`（`LineWalkMove.enter` 同一个坑），`lock_input()`。
身体以进入时的水平速度继续前进（`carry_ballistically`，`SpeedVaultMove` 的
接近段），`set_grounded(true)`，直到脚的水平位置到达 `plant_1` 前
`plant_reach`（0.35 m，项目旋钮）以内；超过 `approach_timeout`（0.6 s）还没到
→ 交还 WALKING。

### 阶段 2：两次蹬踏（各 `step_time_1/2` 0.2 s，无重力）

- 段 1：脚从当前位置到 `plant_1`，`ScriptedMove.begin()` 贝塞尔，顶点
  `plant_arc_height`（0.15 m，项目旋钮）高于两端较高者，`control_bias` 取
  「先起后送」。
- 段 2：`plant_1 → plant_2`，同样一段弧。

胶囊位置 = 脚落点 + 半身高，由 `ScriptedMove.advance()` 直接写位置；
`set_grounded(true)`——脚在东西上，声明而不是推断。模型 `pin_visual_yaw` 朝
进入时的面朝方向；胶囊与视线照常跟鼠标（原作 `ControllerState =
PlayerWalking`，CDO 无 `bConstrainLook`），路径不受视角影响。实测这 0.4 s 里 Z 近似匀速上升 1.2 m、
前进约 2 m，两段小弧只是让脚落到点上，不必刻意做出停顿。

### 阶段 3：抛出

段 2 结束那一帧：

```
dir      = 抛出这一帧的镜头 yaw（水平归一）  ✅ owner：斜着进就斜着出，扭头 180° 就往后飞
xy       = max(h + xy_add, xy_min)        = max(h - 1.0, 4.0)
velocity = dir * xy + UP * jump_z         jump_z = 9.5
```

`fall_tracker.reset(当前高度)`，`set_grounded(false)`，`unlock_input()`。

### 阶段 4：上升到顶点（实测 0.6 s）

**不交给 `JumpMove`。** 原作在整段上升期都停留在 `SpringBoarding`，到顶点
（`bCheckExitToFalling`：垂直速度归零）才转 `Falling`。本 Move 用继承来的
`apply_air_physics()`（重力、空中操控）和 `probe_transition()`（按配置的
`check_for_grab / check_for_vault_over / check_for_wall_climb`）跑这一段；
`velocity.y <= 0` 时返回 `FALLING`。

这样做而不是交给 JUMP 的两个后果都是原作的：**不能 coil**（Coil 只从 Jump 进入，
05 §5.2），空中检查的是 SpringBoard 自己的三个 `bCheckFor*`。

### 中断

- `_aborted`（`pending_spring_board` 为空）→ 第一帧返回 WALKING。
- 蹬踏期不接受移动/跳跃输入（已锁），鼠标视角照常；不检查 grab / vault。
- 无 `redo_move_time`（CDO 无此字段）。

## 配置：`SpringBoardConfig`

`scripts/player/config/moves/spring_board_config.gd`，挂进 `MovementConfig`
聚合根（`spring_board`），`presets/default.tres` 加子资源。

| 字段 | 值 | 标记 |
|---|---|---|
| `jump_z` | 9.5 | `[ME:CONFIRMED]` CDO + 录像 |
| `xy_add` | -1.0 | `[ME:CONFIRMED]` CDO + 录像 |
| `xy_min` | 4.0 | `[ME:CONFIRMED]` CDO + 录像（不按 W 时 14.4 km/h） |
| `plant_1_height` | 0.64 | `[ME:CONFIRMED]` |
| `plant_spacing` | 1.12 | `[ME:CONFIRMED]` |
| `plant_2_min_height` / `plant_2_max_height` | 0.8 / 1.48 | `[ME:CONFIRMED]`（录像 1.24） |
| `step_time_1` / `step_time_2` | 0.2 / 0.2 | `[ME:CONFIRMED]` CDO + 录像 0.4 |
| `approach_angle_deg` | 53 | `[ME:CONFIRMED]` owner 实测 |
| `trigger_distance` | 1.2 | 项目自定（录像实测下界） |
| `plant_reach` | 0.35 | 项目自定 |
| `approach_timeout` | 0.6 | 项目自定 |
| `plant_height_tolerance` | 0.2 | 项目自定 |
| `plant_spacing_tolerance` | 0.3 | 项目自定 |
| `plant_probe_radius` | 0.12 | 项目自定 |
| `plant_arc_height` | 0.15 | 项目自定 |

`MoveConfig` 的行为开关：`constrain_look = false`、`freeze_visual_yaw = true`
（蹬踏期模型钉在两点连线方向）、`allows_turn = false`、
`check_for_grab = check_for_vault_over = check_for_wall_climb = true`（上升段），
不开 coil。

## 表现层

- **动画**：`CharacterAnimator` 加 `Move.SPRING_BOARD` 分支——走到立面与蹬踏期
  `_first_available([&"StepUp", &"Jump_Start", &"jump"])`，`scripted_duration()`
  返回 0.4 s 由 `_scripted_fit()` 拟合（`StepUp` 0.67 s → 1.7×）；抛出后走
  空中循环（`AIRBORNE_LOOP`）。库里没有专门的踏板跳片段，以后可换。
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
5. 蹬踏期：到达立面后 0.2 s 脚在第一根柱顶、0.4 s 在第二根柱顶（容差 5 cm），
   期间 `grounded` 为真、输入被锁。
6. 抛出：段 2 结束那一帧 `velocity.y == jump_z`，水平速度 =
   `max(进入速度 - 1.0, 4.0)`，方向为该帧的镜头 yaw——蹬踏期把视角扭到
   180° 的用例里，人往后飞；`fall_tracker` 已重置；
   之后仍是 `SPRING_BOARD`，`velocity.y` 过零那一帧才转 `FALLING`。
7. 柱顶放不下身体（`fits_standing_at` 假）→ 普通 `JUMP`。
8. 上升段按下蹲不 coil（`SPRING_BOARD` 不会转 `COIL`）。
9. 动画路由：`SPRING_BOARD` 分支存在（`test_every_move_has_its_own_case`
   自动覆盖），蹬踏期请求 `StepUp`，`scripted_duration()` = 0.4。
10. `test_config_layout` / 生成场景测试因新增 `MovementConfig.spring_board`
    需要更新的一并更新；`check_references.gd` 过一遍 `default.tres`。

不测的：弧线顶点高度、手感数值——这些是旋钮。

## 已知空白

- 触发距离上限没有扫过，1.2 m 是实测下界；`CheckDistanceTime = 1.0 s` 含义未明。
- 53° 无 CDO 出处，只有实测。
- 无专门动画片段。
- 录像里的字形库对这次 HUD（14 行、无 IGT 行）识别偏差较大，数值靠逐帧肉眼读取；
  下次先用一帧 `calib --append` 补字形。
- 探测采样越带外读数（`continue`）继续向前，会接受矮墙背后的落脚点：进入后驶向墙、
  最长 1.0 s 超时，白吞一次跳跃键。这是撤掉兜底检测（见下）的既知残余代价，不是新
  bug；若实际玩到，几何解法是进入时从脚到落脚点补一条遮挡射线，不是加旋钮。

## 实现期修订（2026-08-31）

- 阶段 1 的"以进入时的水平速度继续前进"实现为"以不低于 `xy_min` 的速度主动驶向
  第一落脚点"。原地按空格也应触发（owner 实测），身体必须自己走过去；照原文
  coast 的话，站定起步会滑不动而超时，蹬踏就成了只有跑动才有的动作。
- 蹬踏期不再调用 `lock_input()`。移动/跳跃输入在结构上被忽略（各阶段都不读
  `input.move`），鼠标视角保持鲜活——这正是"蹬踏期扭头改变抛出方向"可达的前提，
  而 lock 会连同视角一起冻住。
- `trigger_distance` 1.2 -> 2.4，`approach_timeout` 0.6 -> 1.0（owner 实测 1.2 太短，
  瞄不准；2.4 m 以 `xy_min` 4 m/s 走完正好 0.6 s，旧的 0.6 s 超时会卡在边界上把最长的
  合法助跑判死）。`plant_reach` 0.35 -> 0.55 -> 0.8：0.35 是本文的原值，Task 3 落地时
  即按 0.55 交付（胶囊半径让脚停在立面外 0.4 m，0.35 根本够不着）；随后"走离棱边"又把
  落脚点挪进立面 0.1-0.2 m，两者之和得包得住，于是 0.8。
- 助跑段曾加过"身体被顶住就开蹬"的兜底（连续 3 帧水平位移 < 0.005 m），实测后撤掉：
  它以"什么东西顶住了身体"为准，而顶住的不一定是落脚点——身体与落脚点之间隔着一堵墙
  时会就地开蹬，把身体沿弧线送穿墙。助跑仍然只以 `plant_reach` 结束。
