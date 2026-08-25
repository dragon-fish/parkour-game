# 单杠摇摆（Swing）· 设计

日期：2026-08-25
证据基础：[`05-动作库总览.md`](../../mirrors-edge-deep-research/05-动作库总览.md) §5.4、§5.5b、§5.6.5；
作者 2026-08-25 实测口径（吸附进入、定角跳出）。

---

## 0. 结论先行

- Swing 是**自带状态的 Move**（同滑索）：自己积分摆角，不是 `ScriptedMove`。
- 进入靠 `InterestLine`（`kind = SWING`）体积，**吸附式**：空中进体积即挂，短插值拉上吊点
  ——作者实测补偿①「快要碰到横杆时会帮你吸附上去」。
- 摆锤 1.2 m（✅ `SwingPendulumLength = 120`），本项目 g=16 下周期 1.72 s，
  挂上到第一个前摆极点仅 0.43 s——高手第一摆即可跳出，机制上天然成立。
- **跳出是定角的**：|角速度| ≥ 宽松阈值 且 正在**前摆**时按跳 → 沿前方斜 45° 飞出，
  每次一致——作者实测补偿②。MVP 不做 `TargetVolumeOffset` 目标体积（二期）。
- 蹲 = 松手坠落。脱手后 0.7 s 内重力 ×0.75（✅ CDO，两处几乎相同的数）。

## 1. 范围

包含：`SwingMove`、`SwingConfig`、进入吸附、W/S 泵能量、定角跳出、脱手低重力机制
（Player 级临时重力修改，swing/barge/coil 共用）、HUD `swing` 行、animator 选片、
测试、练习场一根横杆。

不包含：`TargetVolumeOffset` 目标体积跳（二期）；起跳窗口的角度偏置
（`SwingAngleTimingOffset`，等作者实测）；专用摇摆动画；横杆间连跳关卡内容。

## 2. `SwingMove`（`scripts/player/moves/swing_move.gd`）

状态：`_line`、`_pivot`（杆上定点，进入时 `closest_offset` 取得后**固定**）、
`_axis`（杆切线，水平化）、`_forward`（摆动平面内的"前"，进入时由水平速度或朝向定side）、
`_theta`（摆角，0=竖直下垂，前摆为正）、`_omega`（角速度）、`_fade`。

**enter（吸附）**

1. `set_grounded(false)`；取最近 SWING 线；null → abort 回 FALLING。
2. `_pivot = line.sample(closest_offset(身体))`，沿杆夹到线段内；`_axis` 水平化切线。
3. `_forward` = 入场水平速度在垂直于 `_axis` 方向上的投影方向（无速度则用可见朝向）。
4. 初始 `_theta` 由身体当前位置反解（clamp ±25°）；初始 `_omega` = 入场速度切向分量 / L。
5. `fade_in_time`（0.1 s）内从入点插值到摆链位置——这就是"吸附"。
6. 身体 yaw 锁向 `_forward`；look 扇区复用 Grab 机制；`freeze_visual_yaw = true`。

**physics_update**

1. 积分：`_omega += (−g/L)·sin(_theta)·dt + 泵`；`_theta += _omega·dt`。
   泵：W（前）在 `_omega·输入方向 > 0` 时加角加速度 `pump_accel`（顺摆才加得进能量），S 反之。
2. 上限：切向速度 `|_omega|·L ≤ max_swing_velocity(4.25)`，超出截断 `_omega`。
3. 位置：`pivot + L·(sin_theta·_forward − cos_theta·UP)`，直接写 `global_position`。
4. 每 tick `set_grounded(false)`、`fall_tracker.reset(y)`（同滑索：杆在支撑你）。
5. **跳出**（`jump_pressed`）：仅当 `_omega > jump_min_omega`（宽松，前摆方向为正）
   → `velocity = 45° 前上方 · exit_speed`，启动低重力窗，进 FALLING。
   不满足窗口的跳按键**忽略**。
6. **松手**（`crouch_pressed`）：`velocity = 当前切向速度`，正常重力，进 FALLING。
7. 摆角越限自然回摆，无出界脱手；`exit()` 时按线记 `same_line_redo_time` 冷却（复用
   `Player.note_zipline_left` 机制改名通用化为 `note_line_left`）。

## 3. 脱手低重力（Player 级，通用）

`player.apply_gravity_window(multiplier, seconds)`：窗口内 `effective_gravity()`
= `pawn.gravity × multiplier`，由 AirborneMove 的重力施加处消费；到时自动复原。
✅ 研究文档明示这类局部重力修改是 ME"飘但可控"的来源，swing/barge/coil 共用，务必保留。
Swing 跳出与松手均触发：`0.75 × 0.7 s`（✅ `SwingExitGravityModifier/Time`）。

## 4. `SwingConfig`

| 字段 | 值 | 来源 |
| --- | --- | --- |
| `pendulum_length` | 1.2 | ✅ `SwingPendulumLength = 120` |
| `max_swing_velocity` | 4.25 | ✅ CDO（切向上限，与滑索相反——摇摆有上限） |
| `exit_speed` | 6.0 | ✅ `ExitVelocityModifier = 600` |
| `exit_angle_deg` | 45 | ⚠️ 作者 MVP 口径：每次同角，先固定前上 45° |
| `jump_min_omega` | 0.8 | ⚠️ 项目自定义，「很宽松」，作者拨 |
| `pump_accel` | 3.0 | ⚠️ 项目自定义，W/S 泵力度，作者拨 |
| `fade_in_time` | 0.1 | 同滑索吸附手感 |
| `fall_limit` | 6.0 | 沿用滑索（CDO 无 swing 项） |
| `exit_gravity_multiplier / _time` | 0.75 / 0.7 | ✅ CDO 两处相同的数 |
| `same_line_redo_time` | 1.0 | ⚠️ 项目自定义（防松手即重挂），作者拨 |
| look 扇区 / `freeze_visual_yaw` / `allows_turn=false` | | 双手占用，同 Grab/滑索 |

注册：`Move.SWING`、`MovementConfig.swing`、Airborne 入口在 zipline 判定之后
（`check_for_swing`，Jump/Falling 置 true；`nearest_interest_line(SWING)` + 逐线冷却
+ fall_limit；无角度门槛——吸附本来就该宽）。

## 5. 观测 / 动画 / 关卡

- HUD `swing` 行：θ、ω、切向速度、泵方向、跳出窗口开/关。
- animator：`Move.SWING → Climb_Idle` 兜底（吊挂姿势），包里无摇摆片段，已知缺口。
- 练习场 `SwingArea`：起跳台 + 一根水平 `InterestLine(kind=SWING)`（生成器，照 Zipline 模式，
  地板并集已含 InterestLine 端点）。

## 6. 测试（结构不变量）

- 空中进体积 → SWING；地面走过不进；>fall_limit 不进。
- 无输入自由摆：能量单调不增（幅度不自发增长）；W 顺摆泵入后幅度增大（对比，不锁数）。
- 切向速度封顶 max_swing_velocity。
- 前摆 + ω 达标按跳 → velocity 与 `_forward` 水平夹角 45°（按配置断言）、低重力窗生效
  （窗内 effective_gravity = 0.75g，0.7 s 后复原）；后摆按跳被忽略。
- 蹲 → FALLING、速度=切向、正常重力。
- 同线冷却拒绝、异线立即可挂（通用化 note_line_left 后 zipline 测试保持绿）。
- kind 过滤：SWING 线不触发 zipline 入口，反之亦然。

## 7. 已知缺口

- `SwingAngleTimingOffset`（起跳窗口角度偏置）——等作者 ME 实测。
- `TargetVolumeOffset` 目标体积跳——二期。
- 摇摆专用动画与手部 IK 上杆。
