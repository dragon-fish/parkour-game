# 滑索（Zipline）· 设计

日期：2026-08-24
证据基础：[`05-动作库总览.md`](../../mirrors-edge-deep-research/05-动作库总览.md) §5.5、§5.6.5；
方法论：[`docs/capsule-leads-presentation.md`](../../capsule-leads-presentation.md)、
[`docs/contact-drives-movement.md`](../../contact-drives-movement.md)

---

## 0. 结论先行

- 滑索是一个**自带状态的 Move**，自己积分沿缆绳的弧长；不是 `ScriptedMove`。
  时长由缆绳长度与坡度算出，**没有速度上限**（CDO 只有两个下限）。
- 进入靠**兴趣点体积**，不靠探针。本期同时引入共用的 `InterestLine` 标记，
  单杠与平衡木之后复用。
- 缆绳是一条 **`Curve3D`**，可以下垂；直线是两点的退化情形。
- **只能从空中挂上**；**蹲 = 松手**，保持当前速度进入 Falling；**没有跳**；到尽头自动松手。

## 1. 范围

包含：`InterestLine` 标记、Player 对体积的感知、`ZiplineMove`、`ZiplineConfig`、
HUD/F12 观测、测试、`main.tscn` 一条练习用缆绳。

不包含：单杠、平衡木（只预留 `kind` 枚举）；按缆绳区分的冷却；专用动画与手部 IK；
`ZipFadeOutTime`。

## 2. `InterestLine`（`scripts/level/interest_line.gd`）

`class_name InterestLine extends Path3D`。

导出：

| 字段 | 默认 | 含义 |
| --- | --- | --- |
| `kind` | `ZIPLINE` | 枚举 `ZIPLINE / SWING / BALANCE`，本期只实现 `ZIPLINE` |
| `reach_radius` | 0.6 | 缆绳周围多大半径算「够得着」 |

行为：

- `_ready()` 沿 `curve.get_baked_points()` 自动生成子节点 `Area3D`，每相邻两个烘焙点之间
  一个 `CapsuleShape3D`（半径 `reach_radius`）。关卡作者只摆曲线，不摆碰撞体。
- `Area3D` 的 `body_entered / body_exited` 转发给进入的 body：若 body 有
  `enter_interest_line(line)` / `exit_interest_line(line)` 方法则调用。
- 查询接口（Move 只认这两个）：
  - `closest_offset(world_pos: Vector3) -> float`：世界坐标到曲线的最近点弧长。
  - `sample(offset: float) -> Dictionary`：`{"position": Vector3, "tangent": Vector3}`，
    世界坐标，`tangent` 为单位向量、指向弧长增大的方向。
  - `length() -> float`。

## 3. 感知（`Player`）

- 新增 `interest_lines: Array[InterestLine]`，由 `enter_interest_line / exit_interest_line`
  维护。
- 新增 `nearest_interest_line(kind) -> InterestLine`（按 `closest_offset` 处采样点到身体的距离取最近，
  没有返回 null）。
- `reset_state()` 清空该数组（重生时体积信号不会重发）。

## 4. 入口（`AirborneMove`）

在 grab 判定**之前**加一条，仅 Jump / Falling 会经过这里：

```
if c.check_for_zipline
   and player.velocity.y > -cfg_all.zipline.fall_limit
   and player.nearest_interest_line(InterestLine.Kind.ZIPLINE) != null
   and player.move_manager.can_enter(ZIPLINE):
    return ZIPLINE
```

`check_for_zipline` 是 `MoveConfig` 的新字段（与 `check_for_grab` 同款），
`JumpConfig` / `FallingConfig` 置 true，其余默认 false。地面上走进体积不进入。

追加门槛（屋主：「对着绳索反着跳别触发」）：水平速度 > 0.5 m/s 时，其方向与行进方向
（§5 enter 4，经 `ZiplineMove.travel_direction()` 单一来源）的水平夹角 >
`catch_max_approach_angle` 则不进入；几乎垂直起跳（水平速度 ≤ 0.5）不受限。

## 5. `ZiplineMove`（`scripts/player/moves/zipline_move.gd`）

状态：`_line`、`_s`（弧长）、`_v`（沿线速度）、`_dir`（+1 / −1）、`_fade`（挂上插值计时）、
`_entry_pos`。

**enter**

1. `player.set_grounded(false)`。
2. `_line = nearest_interest_line(ZIPLINE)`；若 null → 标记 aborted，下一 tick 回 `FALLING`。
3. `_s = _line.closest_offset(身体位置)`。
4. 行进方向：朝**较低的那一端**。两端等高（差 ≤ 0.01 m）时退回远端规则：朝**离入点较远的那一端**，`_dir = +1` 若 `_s < length/2`，否则 `−1`。
5. 初速：`_v = max(min_velocity, 最后一次离地时的地速)`——✅ 作者实测：中途蹬墙跳不影响，二段绳重置回同一数值；不是当前空速、不是投影。
6. `player.velocity = ZERO`；`_fade = 0`。

**physics_update**

1. 蹲键按下（`input.crouch_pressed`）→ `_release()`。
2. 切线 `t = _dir · sample(_s).tangent`；加速度**随坡度线性**：`a = max(base + gain·(−t.y), 0)`
   ——✅ 作者两段实测拟合（61 m/19°→2.72，97 m/8°→1.96）得 base≈1.4、gain≈4.07，
   gain 与 CDO `MinZipAcceleration=400uu` 吻合到 2%（该字段的真实角色应是坡度系数）。
   上坡段无实测，线性外推并下夹到 0；`min_velocity` 保证不停。
3. `_v += a · dt`；`_v = max(_v, min_velocity)`；`_s += _dir · _v · dt`。
4. `_s` 越出 `[0, length]` → `_release()`。
5. 吊点 `hang = sample(_s).position − hang_offset · UP`。
   `_fade < fade_in_time` 时从 `_entry_pos` 线性插值到 `hang`，之后直接赋值。
   **直接写 `global_position`，不调 `move_and_slide()`**（对应 `PHYS_Flying`）。
6. 身体 yaw 锁向 `t` 的水平方向（`bDisableFaceRotation`）。
7. 每 tick `set_grounded(false)`。

**_release**

`player.velocity = _dir · _v · tangent`；返回 `FALLING`。速度全部保留，不叠加跳跃。

**exit**：无副作用。

## 6. `ZiplineConfig`（`scripts/player/config/moves/zipline_config.gd`）

| 字段 | 值 | 来源 |
| --- | --- | --- |
| `min_velocity` | 3.99 | ✅ 作者反复实测 14.36 km/h ≈ 400 uu/s——与坡度增益同落在 400，CDO 那对字段的命名存疑 |
| `base_acceleration` / `slope_acceleration` | 1.4 / 4.0 | ✅ 作者两段实测线性拟合；gain ≈ CDO `MinZipAcceleration` |
| `hang_offset` | 0.9 | ✅ `HangOffset = (0,0,-90)` |
| `fade_in_time` | 0.1 | ✅ `ZipFadeInTime` |
| `fall_limit` | 6.0 | ✅ `TdMove_IntoZipLine.ZVelocityFallLimit = -600` |
| `catch_max_approach_angle` | 100° | ⚠️ 项目自定义：只拦明显反向的进入，横穿仍可挂 |
| `same_line_redo_time` | 3.0 | ✅ `SameZipLineRedoMoveTime`，且作者实测确证按**缆绳**计：换绳即挂，仅刚离开的那根拒绝（Player 按 line 维护，move 级 redo=0） |
| `allows_turn` | false | 双手占用 |
| `constrain_look` / yaw ±90° / `freeze_visual_yaw = true` | | 复用 Grab 的 look-constraint 机制 |

注册：`MovementConfig.zipline`、`Move.ZIPLINE = &"Zipline"`、`Player` 注册表加一行。

## 7. 观测

- HUD 新增 `zip` 行：`s / length`、`v`（m/s 与 km/h）、`a`。
- F12 叠加：画当前缆绳的烘焙点列与吊点，数据直接读 `InterestLine.sample()`。
- 动画：`CharacterAnimator` 选片表加 `ZIPLINE → Jump`（包里没有滑索片段）。

## 8. 关卡内容

`scenes/main.tscn` 新增 `ZiplineArea`：一个起跳平台，一条三控制点的下垂缆绳
（起点高于平台 ≈ 2.4 m 使跳跃可及，终点落到远端地面上方 ≈ 2.4 m），
放在现有练习区之外的空地。

## 9. 测试

数值不上断言，只写结构性不变量（见 memory：表现值不写单测）。

`tests/test_interest_line.gd`

- 三点下垂曲线：任取弧长 `s`，`closest_offset(sample(s).position) ≈ s`。
- `_ready()` 后存在 `Area3D`，且曲线中点处的 shape 覆盖该点。

`tests/test_zipline_move.gd`（夹具：`TestWorld.build()` + 代码构造真实 `InterestLine`）

- 站在缆绳正下方不跳 → 不进入。
- 跳入体积 → 进入 `Zipline`。
- 以 > 6 m/s 下落穿过体积 → 不进入。
- 滑行中蹲 → `Falling`，且 `velocity` 与切线方向一致、模长 ≥ `min_velocity`。
- 滑到尽头 → `Falling`。
- 退出后 3 s 内再跳入 → 被 `can_enter` 拒绝。
- 下坡缆绳的加速度 ≥ 平缆绳的加速度（对比，不锁数）。

每条测试写完先用撤销验证会失败。

## 10. 已知缺口（本期不做）

- 专用滑索动画与手部 IK：`HandIK` 解算器仍差 1.32 m，接触 IK 单独立项；滑索是它第一个落点。
- `ZipFadeOutTime 0.5`：原版的松手动画混合时间，本项目由 animator 自管。
