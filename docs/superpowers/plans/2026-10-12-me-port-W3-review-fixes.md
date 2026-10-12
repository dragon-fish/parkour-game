# W3 · 第二波移植的审查修复

> 来源：两份独立审查（墙面 + 地面、边缘 + 器械/近战），每条都对照了原版证据与移植代码。
> 上位文档：[spec](../specs/2026-10-12-me-faithful-port-design.md)、[W2](2026-10-12-me-port-W2.md)。
> 所有者试玩反馈的三个问题（被小凸起卡住、上翻穿墙、悬挂不上翻）以及"`Physics == None` 时不应跑自动转移"
> 由单独的调试任务处理，不在本清单内。

## 影响手感

1. `presets/default.tres:43-45` 把 Crouch 的 `speed_modifier` 设成 0.4；原版 ini `[TdMove_Crouch] SpeedModifier=0.2`。
   同一预设里 Slide 的 `redo_move_time = 0.5`，原版是 0。预设值要和原版 ini 一致。
2. 滑铲结束后视角限制残留（`player.gd` `residual_look_config`，由 `slide_move.gd` / `ramp_slide_move.gd` 设置）：
   原版 `TdMove.StopMove` 立即解除 Slide 的 ±10000 限制。删除这个推理产物。
3. 铁丝网（`move_manager.gd:470-505`）：原版每次**进入**体积只踉跄一次（`TdBarbedWireVolume.Touch`）；每秒的伤害走
   `TdPawn.TakeDamage` → 空的 `BulletDamage`，不会再次踉跄；Landing 期间的触碰直接丢失；有 0.1 s 的
   `LastResetTimeStamp` 宽限；伤害位置用的是体积而不是身体自己（决定向前还是向后踉跄）。按原版重写。
4. Q（回头，`player.gd:4437`）没有原版的门槛：`IsButtonInputIgnored()`，或当前 move 的 `MovementGroup >= 3`（不可交互）时直接返回。
5. 玻璃（`scripts/level/breakable_glass.gd:52-63`）按接近速度破碎是推理产物：原版只在受到 `TdDmgType_Barge` 时破碎，
   来源是 Barge 的 `BargeHitNotify` / `TryGiveBargeDamage`、AirBarge、MeleeAir 的 `Bump`、MeleeSlide 0.33 s 后的
   `OnFindBargeTargetTimer`、MeleeCrouch 的 `TestHit` → `FindBargeTarget` → `HitObject`。普通奔跑撞上去应该被挡住。
   一并补上 `Bump` 钩子（MeleeAir、Barge、AirBarge）和 MeleeSlide / MeleeCrouch 的冲撞计时与命中。
6. IntoGrab 的最后一道检查（`into_grab_move.gd:83`、`player.gd` `movement_volume_at`）：原版拒绝落在**任意**
   `TdMovementVolume` 内的边缘点，包括 `TdFallHeightVolume`、`TdBarbedWireVolume`。

## 次要

7. 缩小碰撞体（`ShrinkCollision`）时原版把 Actor 向下移 29 uu（`TdMove.uc:992-1004`），移植只移了形状节点：
   Crouch / Slide / Coil / LayOnGround / 180TurnInAir / AirBarge 期间所有读 Location.Z 的地方都高了 29 uu
   （落地边缘测试的落差、从滑铲/蹲伏走下边缘时的 EnterFallingHeight、Coil 的失控下落出口、软着陆探测、落地伤害）。
8. 恢复站立高度（`EnlargeCollision`）原版是立即恢复、被挡住则 `SetLocation`、着地时 +2 uu 再向下跨台阶；移植是延迟到有净空。
9. `CanSkillRoll` 缺两道门槛：上一个动作是近战时拒绝（`TdPawn.uc:2529`）；处于 UncontrolledFall 状态时拒绝（`TdPlayerPawn.uc:1930`）。
10. `FindLedgeEx`（`move_traces.gd:130-135`）的 Actor 与排除标记应取**最后一次**（向下的）探测，未命中时写 None。
11. 在凹面关卡几何内部起始的探测：Jolt 在 4.7.1 下返回无命中，原版是 Time 0 命中；`FindLedgeEx` 的步骤 a 和重试分支依赖它。
12. Slide 的 `StopMove` 漏了 `FaceRotationTimeLeft = 0.4`。
13. 视角复位：LayOnGround 起身 `ResetCameraLook(1.0)`（GetUpBack 另有 `SetLookAtTargetLocation`）、SkillRoll `ResetCameraLook(0.2)`、
    Turn180InAir 转向起跳点。它们决定之后的前进方向，属于移动结果，不是镜头设计。
14. Turn180InAir 根旋转时序（原版约 0.283 s 到 180.9°；根旋转在 0.6 s 结束是推断）。
15. 墙面物理里原版没有的 `not _recovered` 保护（`pawn_physics.gd:1596/1695`）。
16. 移动的墙：墙跑/蹬墙没有设置 Base，墙面侧闪跳漏了 `Base.Velocity.Z`。
17. `move_traces.gd:220/225` 用当前半径而非类默认半径（`R_def − 5`）。
18. `max_step_height`（40 uu）被用在原版读 `Pawn.MaxStepHeight`（35 uu）的地方：`grab_pull_up_move.gd`、`into_grab_move.gd:190`。
19. Grab `UpdateGrabType` 切换横移动画时应沿用上一段动画的归一化位置。
20. 原版各 move 的 `HandleDeath`（Grab、GrabPullUp、IntoGrab、IntoClimb、Climb、SpeedVault）都没有移植。
21. ZipLine 的 `HitWall` 漏设 Stumble 的 `InstigatorLocation` / `damageMomentum`。
22. ZipLine、Interact 缺 `bDisableFaceRotation`；IntoZipLine 写的是视角偏航，原版只设 Pawn 朝向。
23. Interact 到达后漏了 Flying → Walking 的物理重置（清 Base 与 SlideOffLedge 计时）。
24. `against_wall_state()` 漏了原版离墙后 0.15 s 的尾巴。
25. 项目自加、被许多 move 继承的东西：`td_can_do_move` 里的 `statuses.is_move_blocked`（关卡功能，保留但注明）、
    `fall_counts_from_exit`（已失效，删除）、基类 `constrains_look()` 没有 OR 上 `PawnOwner.bConstrainLook`。

## 表面

`int()` 截断在米制下做；MeleeWallrun 用计时器结束；下落重试丢了 `GPhysFallingDepth < 2`；`slide_move.gd` 继承
PhysicsMove（原版 TdMove）；几处过时注释（`move.gd` 头部、`wall_climb_config.gd:44-46`、`interest_line.gd` 引用的
`LineMove.approach_seconds()`、`phys_flying` 的 `[ME:CONFIRMED]` 只覆盖到 CalcVelocity）。
