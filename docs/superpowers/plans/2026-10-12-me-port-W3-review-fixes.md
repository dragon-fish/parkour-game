# W3 · 第二波移植的审查修复

> 来源：两份独立审查（墙面 + 地面、边缘 + 器械/近战），每条都对照了原版证据与移植代码。
> 上位文档：[spec](../specs/2026-10-12-me-faithful-port-design.md)、[W2](2026-10-12-me-port-W2.md)。
> 所有者试玩反馈的三个问题（被小凸起卡住、上翻穿墙、悬挂不上翻）以及"`Physics == None` 时不应跑自动转移"
> 由单独的调试任务处理，不在本清单内。

## 影响手感

1. [x] `presets/default.tres:43-45` 把 Crouch 的 `speed_modifier` 设成 0.4；原版 ini `[TdMove_Crouch] SpeedModifier=0.2`。
   同一预设里 Slide 的 `redo_move_time = 0.5`，原版是 0。预设值要和原版 ini 一致。
2. [x] 滑铲结束后视角限制残留（`player.gd` `residual_look_config`，由 `slide_move.gd` / `ramp_slide_move.gd` 设置）：
   原版 `TdMove.StopMove` 立即解除 Slide 的 ±10000 限制。删除这个推理产物。
3. [x] 铁丝网（`move_manager.gd:470-505`）：原版每次**进入**体积只踉跄一次（`TdBarbedWireVolume.Touch`）；每秒的伤害走
   `TdPawn.TakeDamage` → 空的 `BulletDamage`，不会再次踉跄；Landing 期间的触碰直接丢失；有 0.1 s 的
   `LastResetTimeStamp` 宽限；伤害位置用的是体积而不是身体自己（决定向前还是向后踉跄）。按原版重写。
   踉跄的位置：Touch 的 HitLocation 是扫掠中身体碰到体积时的位置（不是体积的 Location——那是每秒伤害 CausePainTo 的，且不影响踉跄），这里取上一帧开始时的身体位置，方向与原版一致。每秒伤害的节奏仍由本项目的免疫窗口计时（原版是体积自己的 1 s VolumeTimer）。
4. [x] Q（回头，`player.gd:4437`）没有原版的门槛：`IsButtonInputIgnored()`，或当前 move 的 `MovementGroup >= 3`（不可交互）时直接返回。
5. [x] 玻璃（`scripts/level/breakable_glass.gd:52-63`）按接近速度破碎是推理产物：原版只在受到 `TdDmgType_Barge` 时破碎，
   来源是 Barge 的 `BargeHitNotify` / `TryGiveBargeDamage`、AirBarge、MeleeAir 的 `Bump`、MeleeSlide 0.33 s 后的
   `OnFindBargeTargetTimer`、MeleeCrouch 的 `TestHit` → `FindBargeTarget` → `HitObject`。普通奔跑撞上去应该被挡住。
   一并补上 `Bump` 钩子（MeleeAir、Barge、AirBarge）和 MeleeSlide / MeleeCrouch 的冲撞计时与命中。
6. [x] IntoGrab 的最后一道检查（`into_grab_move.gd:83`、`player.gd` `movement_volume_at`）：原版拒绝落在**任意**
   `TdMovementVolume` 内的边缘点，包括 `TdFallHeightVolume`、`TdBarbedWireVolume`。

## 次要

7. [x] 缩小碰撞体（`ShrinkCollision`）时原版把 Actor 向下移 29 uu（`TdMove.uc:992-1004`），移植只移了形状节点：
   Crouch / Slide / Coil / LayOnGround / 180TurnInAir / AirBarge 期间所有读 Location.Z 的地方都高了 29 uu
   （落地边缘测试的落差、从滑铲/蹲伏走下边缘时的 EnterFallingHeight、Coil 的失控下落出口、软着陆探测、落地伤害）。
8. [x] 恢复站立高度（`EnlargeCollision`）原版是立即恢复、被挡住则 `SetLocation`、着地时 +2 uu 再向下跨台阶；移植是延迟到有净空。
   被挡住时（头顶没有空间）不做 +2 uu 与下跨台阶：Godot 的 move_and_collide 会先把身体从天花板推进地面。
9. [x] `CanSkillRoll` 缺两道门槛：上一个动作是近战时拒绝（`TdPawn.uc:2529`）；处于 UncontrolledFall 状态时拒绝（`TdPlayerPawn.uc:1930`）。
10. [x] `FindLedgeEx`（`move_traces.gd:130-135`）的 Actor 与排除标记应取**最后一次**（向下的）探测，未命中时写 None。
11. [ ] 在凹面关卡几何内部起始的探测：Jolt 在 4.7.1 下返回无命中，原版是 Time 0 命中；`FindLedgeEx` 的步骤 a 和重试分支依赖它。
   跳过：Jolt 确实对凹面体内部起始的探测返回无命中（已实测），但 FindLedgeEx 里两处依赖都不改变结果——步骤 a 本来就忽略 Time 0 命中；重试分支在凹面实心内同样得到结果 1。唯一差别是 BSP 墙内的结果 1 MovementActor 为空（原版为关卡本身）。
12. [x] Slide 的 `StopMove` 漏了 `FaceRotationTimeLeft = 0.4`。
13. [x] 视角复位：LayOnGround 起身 `ResetCameraLook(1.0)`（GetUpBack 另有 `SetLookAtTargetLocation`）、SkillRoll `ResetCameraLook(0.2)`、
    Turn180InAir 转向起跳点。它们决定之后的前进方向，属于移动结果，不是镜头设计。
14. [x] Turn180InAir 根旋转时序（原版约 0.283 s 到 180.9°；根旋转在 0.6 s 结束是推断）。
   转身时序改为根轨迹的 0.283 s；OnCeaseRelevantRootMotion 何时触发仍未读到，保留在序列末尾。
15. [ ] 墙面物理里原版没有的 `not _recovered` 保护（`pawn_physics.gd:1596/1695`）。
   跳过：`_recovered` 是移植对 Godot 推出（depenetration）的适配，原版 MoveActor 从不推人；走路、下落物理里有同一保护，只在墙面物理里去掉会让一次推出变成速度。
16. [x] 移动的墙：墙跑/蹬墙没有设置 Base，墙面侧闪跳漏了 `Base.Velocity.Z`。
   Base.Velocity.Z：原版在 super.StartMove 设 PHYS_Falling 之后才读 Base，setPhysics 已清空 Base，所以这段加法是死代码，不移植（注释已改）。
17. [x] `move_traces.gd:220/225` 用当前半径而非类默认半径（`R_def − 5`）。
18. [x] `max_step_height`（40 uu）被用在原版读 `Pawn.MaxStepHeight`（35 uu）的地方：`grab_pull_up_move.gd`、`into_grab_move.gd:190`。
   41d030c 已修，核对无误。
19. [x] Grab `UpdateGrabType` 切换横移动画时应沿用上一段动画的归一化位置。
20. [x] 原版各 move 的 `HandleDeath`（Grab、GrabPullUp、IntoGrab、IntoClimb、Climb、SpeedVault）都没有移植。
   另补了 WallClimb、WallRun、ZipLine、IntoZipLine、Jump、LayOnGround、SpringBoard 的 HandleDeath；死亡体积走 FellOutOfWorld，不经 HandleDeath。
21. [x] ZipLine 的 `HitWall` 漏设 Stumble 的 `InstigatorLocation` / `damageMomentum`。
22. [x] ZipLine、Interact 缺 `bDisableFaceRotation`；IntoZipLine 写的是视角偏航，原版只设 Pawn 朝向。
   Barge（AirBarge 随之继承）、MeleeVault 一并补上。
23. [x] Interact 到达后漏了 Flying → Walking 的物理重置（清 Base 与 SlideOffLedge 计时）。
24. [x] `against_wall_state()` 漏了原版离墙后 0.15 s 的尾巴。
25. [~] 项目自加、被许多 move 继承的东西：`td_can_do_move` 里的 `statuses.is_move_blocked`（关卡功能，保留但注明）、
    `fall_counts_from_exit`（已失效，删除）、基类 `constrains_look()` 没有 OR 上 `PawnOwner.bConstrainLook`。
   25a 已注明；25b 已删除；25c 未做：PawnOwner.bConstrainLook 只由 UpdateAgainstWall 打开，其约束一半未读清（N3 §6），配合 TdMove 为零的 Min/MaxLookConstraint 会把视角钉死。

## 表面

- [x] MeleeWallrun 改为随动画结束；下落重试补上 `GPhysFallingDepth < 2`；几处过时注释已改（`move.gd` 头部、`wall_climb_config.gd`、`interest_line.gd`、`phys_flying`——后者的整段反编译在 native/N5_b.c，标注改为分开引用）。
- [ ] `int()` 截断：逐处核对，所有截断都在 uu 下做，未找到米制截断。
- [x] `slide_move.gd` 已经继承 Move，无需改动。
- [x] 追加：薄栅栏（< 4 uu 厚）在原版里同样走 WallClimb（FindLedgeEx 向下探测在墙面后 4 uu，探不到顶就是结果 1，跳过 MinWallHeight 检查）；视角一直向上的原因是 Falling.StartMove 漏了 `ResetCameraLook(0.5)`。第三人称不再应用移动的 look-at 与视角复位。


`int()` 截断在米制下做；MeleeWallrun 用计时器结束；下落重试丢了 `GPhysFallingDepth < 2`；`slide_move.gd` 继承
PhysicsMove（原版 TdMove）；几处过时注释（`move.gd` 头部、`wall_climb_config.gd:44-46`、`interest_line.gd` 引用的
`LineMove.approach_seconds()`、`phys_flying` 的 `[ME:CONFIRMED]` 只覆盖到 CalcVelocity）。
