# I1 · 原版移植的核心切片：框架、物理底座、Walking / Falling / Jump / Landing

> 上位文档：[spec](../specs/2026-10-12-me-faithful-port-design.md)。证据：
> [语料 15](../../mirrors-edge-deep-research/15-原版逻辑反编译.md)，以及本机
> `_local/me-re/findings/{N1-ground,N2-air,N4-framework}.md`（反编译原始结论，未入库）。
> 原版脚本一律读 `_local/me-re/script_paren/`（运算符全部带括号）。

## 目标

把模拟层换成原版的结构，先打通最常用的四个动作，确保整套骨架可行：
在平地上起跑、冲刺、转向、点按急停、跳跃、下落、落地，数值与原版代码一致。

做完以后，其余动作的移植就是"照原版写一个 move 文件"的并行工作。

## 原版结构 → 本项目

### 1. Pawn 状态（`Player` 上的字段，snake_case）

`movement_state` / `old_movement_state` / `pending_movement_state`（move 名）、`move_action_hint`
（NONE/UP/DOWN/LEFT/RIGHT）与 `move_action_max`、`sprint_energy`（`SpeedSprintEnergy`，m/s）、
`enter_falling_height`、`last_jump_location`、`illegal_ledge_timer` / `illegal_ledge_normal`、
`evade_timer`、`move_normal`、`floor_normal`（`Pawn.Floor`）、`move_ledge_result` / `move_ledge_location` /
`move_ledge_normal`、`found_ledge`、`gravity_modifier` / `gravity_modifier_timer`、`physics`（物理模式）。

### 2. Move API（`Move`）

| 原版 | 本项目 | 说明 |
| --- | --- | --- |
| `CanDoMove()` | `can_do_move() -> bool` | 基类：`RedoMoveTime` 从本 move 的 `last_stop_move_time` 起算；死亡时 false |
| `StartMove()` | `enter(previous)` | 基类先做 `TdMove.StartMove` / `TdPhysicsMove.StartMove` 的通用部分：`move_active_time = 0`、`DisableMovementTime`、`DisableLookTime`、设置物理模式（`pawn_physics`）与控制器状态 |
| `StopMove()` | `exit()` | 基类记下 `last_stop_move_time`，解除输入屏蔽，清计时器，控制器状态回 `PlayerWalking` |
| `PostStopMove()` | `post_exit()` | |
| `HandleMoveAction(a)` | `handle_move_action(a)` | 当前 move 先处理；状态没变才查仲裁表 |
| `Landed(n, a)` | `landed(normal)` | 基类：`Landing.can_do_move()` 则 `set_move(LANDING)` |
| `HitWall`、`Bump`、`ReachedWall`、`ReachedPreciseLocation` | 同名 snake_case | |
| `SetTimer(t)` / `OnTimer()` | `set_timer(t)` / `on_timer()` | 在 tick_move（物理之后）里倒数 |
| `SetMoveTimer(t, loop, name)` | `set_move_timer(t, loop, callable)` | 在物理之前倒数 |
| 原生 0x124 `CheckAutoMoves` | `check_auto_moves()` | 只有 TdPhysicsMove 系有，按 N4 §2.2 的顺序 |
| 原生 0x118 `PrePhysics(dt)` | `pre_physics(dt)` | 精确定位插值 + TdPhysicsMove 的落出检查（N4 §2.3） |
| 原生 0x11c `TickMove(dt)` | `tick_move(dt)` | `Timer` 倒数 → `on_timer`；`move_active_time += dt` |

现有的 `physics_update(delta, input) -> StringName` 在移植完成的 move 里不再承担物理推进与按键处理；
返回值仍可用于"本帧要切到哪个状态"，由管理器转成 `set_move`。

### 3. `MoveManager`

- `set_move(name, check_can_do := false) -> bool`：原版顺序（15.4 / N4 §1.2）：同名或 `bAllowMoveChange`
  为 false 则拒绝；`pending = name`；可选 `can_do_move`；旧 move `exit()`；`old = 当前`；切换；旧 move
  `post_exit()`；新 move `enter(old)`；`move_changed` 信号。**可重入**：`enter()` 里再 `set_move` 是合法的
  （Landing → SkillRoll 就是这样）。
- `handle_move_action(action)`：15.3 的整张表。表里引用到、但本切片还没移植的 move，`can_do_move()` 一律 false。
- 本项目自己的功能（关卡状态效果、踉跄、击倒、`statuses.is_move_blocked`）保留，挂在原来的位置。

### 4. 每帧顺序（N4 §1.1）

```
Player._physics_process:
  1. 控制器：读输入 -> set_input_hint（原始轴，屏蔽前）-> 输入缩放/屏蔽
            -> 控制器状态的 player_move()：算 Acceleration
            -> check_crouch / check_jump_pressed / check_jump_released / look_behind / attack_press
               （每个都可能 handle_move_action -> set_move，立即生效）
  2. Pawn 物理前：set_move_timer 的计时器
  3. performPhysics：current.check_auto_moves(); current(重新读取).pre_physics(dt); 物理推进（按 player.physics 分派）
  4. Pawn 物理后（TickSpecial）：evade_timer、illegal_ledge_timer 倒数；gravity_modifier_timer；
     current.tick_move(dt)
```

### 5. 物理底座（`PawnPhysics`，新文件）

建在 `CharacterBody3D.move_and_collide` 上，复刻 UE3 的 `MoveActor`（返回 Hit.Time = 实际位移 / 请求位移、
Hit.Normal）。碰撞体改成**圆柱，半径 0.30 m、高 1.80 m**（`TdPawn` CDO：CollisionRadius 30、CollisionHeight 90）。

- `set_physics(mode)`：进入 Falling 时 `enter_falling_height = 脚底高度`（原版是 `Location.Z`，即圆柱中心；
  本项目的原点约定见 `Probes`，统一换算）；进入 Walking 时记录地面平滑高度；离开 12/13 清墙走标记。
- `phys_falling(dt)`：N2 §2 全文照搬：加速度上限（153.6 / +(10−v)/dt / ≥720 时为 1）、0.05 s 子步、
  `V1 = V0 + (A+g)dt` → 移动 → 撞墙 `compute_slide_vector`（N2 §2b）→ 地面：落地（剩余时间、速度取本子步）→
  `process_landed` → 否则**速度重建** `V = 2·dLoc/dt − V0`（条件见 N2）→ 终端速度 35 m/s。
  重力：`gravity_z = -8 m/s² × gravity_modifier`，**不要**再写 16。
- `process_landed(normal, remaining)`：N2 §3：`floor_normal = normal`；`landed` 事件交给当前 move；
  然后进入 Walking；`Acceleration` 归一化；剩余时间继续走 `phys_walking`。
- `phys_walking(dt)`：**以 N1 的结论为准**（`_local/me-re/findings/N1-ground.md`）：坡度摩擦修正、
  `CalcVelocity`、子步、跟地、跨台阶、走出边缘 → `set_physics(FALLING)` + `set_move(FALLING, true)`。

### 6. 本切片的四个 move

照原版脚本 + 原生覆盖（`_local/me-re/native/move_natives.c`）移植：

- **Walking**（`TdMove_Walking`，TdPhysicsMove 系但不设任何自动转移开关）：`StartMove` 清 `illegal_ledge_timer`；
  闲置动画计时与本项目表现层的接口保留。
- **Jump**（`TdMove_Jump`）：N2 §6：`PreJumpMomentum`；向前已有速度时 +1 m/s 前向；`Vz = 6.3 × 机动性倍率`；
  `found_ledge` 时的抓边辅助（预测用**脚本重力 8**，原版如此）；`StartJump` 切 Falling。
- **Falling**（`TdMove_Falling`）：`PreviousMove`；以 Walking 为前驱且倒退时清水平速度；
  原生 TickMove 的 CloseToGround 探测；PrePhysics 的 AirTime。
- **Landing**（`TdMove_Landing`）：15.6 的 `SubtractLandingSpeed` 全部条件、`LandNormal/LandHard/LandBackwards/
  LandOnSoftObject`、SkillRoll / SoftLanding 分支（目标 move 尚未移植时 `can_do_move` 为 false，自然落回别的分支）。

控制器状态 `PlayerWalking.PlayerMove`（15.2）：冲刺判定、点按急停、空中走 `GetSprintAcceleration`。
`aTurn` = 本物理帧的视角偏航增量换算成旋转单位并截断（`PawnAcceleration.turn_units`）。

### 7. 要删掉的推理产物（仅限本切片覆盖的部分）

`SpeedEnergy` 的"能量=秒数"模型、`speed_curve_smooth_fit`、`turn_rate_cost_curve`、`ground_accelerate` /
`air_accelerate`、土狼时间、跳跃缓冲、`jump_add_xy` 的推理用法、落地保留比例（`landing_keep_ratio`）等。
删除前确认没有表现层在读（镜头 FOV、头部晃动读的是 `travel_speed()`，保留）。

### 8. 验证

- 纯函数部分（加速度、落地减速、跳跃速度）用黄金用例（原版机器码在模拟器中的输出）钉住。
- 场景测试只测结构性不变量：仲裁顺序、`old_movement_state` 分支、强制 Walking 帧、物理模式切换、
  原版公式给出的可解析结果（例如平地跳跃顶点 1.24 m、滞空 0.7875 s；从静止冲刺到 7.2 m/s 的时间来自 SpeedCurve）。
- 旧测试里钉住推理行为的，随推理代码一起删除或改写。不跑全量套件，只跑相关文件。
