# 平衡木与檐走 —— 实施交接

对应 spec `specs/2026-08-30-balance-and-ledge-walk-design.md` 与 plan
`plans/2026-08-30-balance-and-ledge-walk.md`。那两份是**定稿时的存档**，不回头改；
本文件记录实施过程中偏离它们的地方、原因，以及留给 owner 的决定。

分支 `feat/balance-and-ledge-walk`，22 个提交，48 个文件，+3896/−21。
全套测试 906/907（唯一失败是与本工作无关的 `test_hand_ik.gd` pending）。
`check_references.gd` 退出 0。整分支 review 结论：READY TO MERGE。

---

## ⚠️ 需要 owner 上机决定的一件事

**平衡木失衡时镜头 roll 的方向没有被选过。**

`camera_rig.gd` 自己的注释确认：正的 `rotation.z` 让视野向**左**倾。而正的失衡量
表示身体向**右**倒（`test_positive_lean_tips_the_torso_toward_the_bodys_right` 钉死了
这一点）。也就是说同一个 `_lean` 驱动的镜头与骨骼两个通道，**方向相反**。

这不一定是错的——墙跑的 roll 也是同样的反向关系，而那是 owner 实机确认过的。但本次
分支上没有任何东西记录过这个选择：`max_camera_roll_deg` 是 `CameraConfig` 里唯一没有
方向说明的 roll 幅度字段（`wall_camera_roll_deg` 和 `vault_roll_deg` 都有）。

它是纯手感值，没有测试可以断言，而且 `tools/capture.gd` 不驱动输入、够不到梁，所以
无头验证也拿不到。**走一趟 `scenes/debug_levels/balance_course.tscn` 就知道该不该翻**。
决定之后：要么翻转 `balance_move.gd` 里那一处符号，要么补一句说明两个方向都试过、
这个读起来对。

---

## 交付内容

| 位置 | 内容 |
|---|---|
| `scripts/player/moves/line_walk_move.gd` | 新中间层：站在线**上**沿线走（对应 zipline/swing 的挂在线**下**） |
| `scripts/player/moves/balance_move.gd` | 平衡木 + 倒立摆 |
| `scripts/player/moves/ledge_walk_move.gd` | 檐走，54 行薄壳，无平衡状态 |
| `scripts/player/config/moves/balance_config.gd` / `ledge_walk_config.gd` | 两组旋钮 |
| `scripts/player/balance_lean.gd` | 分段骨骼倾斜（Hips 小份额，Spine 起分大头） |
| `scripts/camera/camera_rig.gd` | 失衡驱动的 roll 与 FOV 收缩通道 |
| `scripts/player/character_animator.gd` | 两条动画路由 |
| `scenes/debug_levels/balance_course.tscn` | 调试关卡，继承 `base_level` |
| `scripts/debug/debug_hud.gd` | 失衡量实时读数 |

调参入口：关卡里的 TuningPanel 已自动收录两组 config（该面板零策展）。

---

## 偏离 spec / plan 的地方

按影响排序。每条都记了「判断错了的代价」。

### 1. plan 的沿线投影公式是错的（改了）

plan 给的 `project_input()` 与它自带的测试互相矛盾。根因：`atan2(x, z)` 重建出的 yaw
与 Godot 的局部 -Z 前向约定相反。第一轮的"加个负号"修复被 review 推翻——它满足了断言，
代价是破坏输入方向与身体朝向的一致。最终改法：`yaw_of()` 用 `atan2(-x, -z)`，
`tangent` 与 `normal` 按 `forward(yaw)` / `T × UP` 重建，不加负号。

**代价**：错了的话每条线上前进方向都是反的，两个 move 的测试会立刻抓到。

### 2. plan 的倒立摆纠正项符号是错的（改了）

plan 写 `accel = lean·rate² − gain·input`。`lateral` 是右手法线上的投影，纠正右倾要
按左（`input < 0`），减去负数等于加大发散——纠正键会**加速**摔倒。改成 `+`。

**代价**：A/D 在梁上反向，plan 自带的 `test_correction_opposes_the_lean` 会失败。

### 3. `GravityInfluence` 的语义是本设计的推导，不是原作读出的

CDO 只给名字和数值，没有公式。文档原先把它读作「不稳定系数」，与 `TimeToCounter`
的「发散特征时间」撞车——一个二阶系统只有一个发散速率。改读为：与 `CameraInfluence`
并列，两个都是 0.3、都是「把失衡量转成某个后果」的转换率，`GravityInfluence` 转成
**身体真的偏离梁中心线的横向位移**，偏出半宽即脚踩空。摔落因此是**几何结果**而非
阈值判定。`05-动作库总览.md` 已同步改写并标 🔶 推导。

**代价**：若原作另有其义，这个读法会让四个数里有一个用错；但它至少自洽，且让摔落
落在 `docs/contact-drives-movement.md` 上。

### 4. 拱顶小球模型降级为 [ME:INFERRED]

实测的是**观察**（站着不动也会失衡、晃动与速度无关、入场偏移随速度增大、熟练者后半程
不用管）；「它是一个倒立摆」是为解释这些观察而**拟合的模型**，原作里从没恢复出公式。
文档自己把由该模型推出的 CDO 映射标为「推导，非确证」——模型不可能比它推出的东西更
确证。`05` 的小节标题已改为「观察 ✅ 实测，模型 🔶 推导」。

**代价**：标签低估了确定性，这是安全的方向；反过来会污染整个证据体系。

### 5. 进入门原本用胶囊中心，改成脚（这是最实质的一处）

`foot_gate_at()` 比较的是 `global_position.y`（胶囊中心，站立时离脚 0.9 m）与线高，
容差 0.35 m。后果：**平地走上独木桥永远进不去平衡状态**，只能靠下落穿过高度窗口。
同一个文件里的休息姿势却是 `curve.y + 0.9`，两者差整整一个半身高。

spec 一直写的是脚（`abs(feet_y - line_y) <= foot_snap_height`），项目也早有
`probes.gd` 专门做这个转换。改为 `player.probes.feet_y()`。

**这个缺陷是被调试关卡逼出来的**——全套测试当时是绿的，因为测试把线建在了玩家胸口
高度。Task 9 最初把它当成关卡设计约束绕过去了（抬高出生点、给梁去掉碰撞），并写进了
`docs/level-templates.md`；那段指导已删除。同处还把 spec 的裁定引反了（写成"漏判的
代价大于误入"，spec 说的是反的），已更正。

**代价**：门变宽一点，站在梁**旁边**可能被吸上去；`foot_snap_height` 就是这个旋钮。

### 6. 檐走的朝向改由 `line.front()` 决定

spec 写了「节点 -Z 指向墙」的约定，但**没有任何代码读它**——朝向实际来自曲线的绘制
方向。调试关卡碰巧摆对了。现在 `_yaw_offset()` 从 `normal.dot(front())` 取符号，并有
测试钉住「反转曲线点序不改变朝向」。

### 7. 侧步动画的方向改为在身体坐标系里上报

承 6 而来，整分支 review 才看得见：`_shuffle_dir` 在**线**的坐标系里算，动画器把 +1
映射成 `Walk_R`——只在 `_yaw_offset()` 选 +90 时成立。墙在另一侧时按 D 会播向左的侧步。
**未来一半的檐会动画镜像**，而调试关卡恰好在正确分支上，实机也看不出来。已改为
`along * _facing_sign`，两个分支都有测试。

### 8. 入场偏移是**乘**不是加

plan 写 `base_wobble + entry_speed_influence · v/gs`，代码是
`base_wobble · (1 + entry_speed_influence · v/gs)`。plan 的加法形式会让满速入场得到
2.52 的失衡量，而梁半宽是 0.14——一上梁就掉。代码已注明理由，防止下一个人"改回去"。

### 9. FOV 收缩不再累积进镜头状态

plan 说「在速度 lerp 之后减去 squeeze」，但 `camera.fov` 是持久状态、lerp 读它自己的
上一帧值，于是减法逐帧复利：不动点 `T − S/k` = **−10°**。实测在持续满失衡约 1/3 秒后
fov 跌破 1，Godot 的 `set_fov` 触发 ERR_FAIL，视野塌成 2–11 度的针孔并每帧刷错误日志；
还会经 `mirror.gd` 外溢到关卡里所有镜子。改为 `_speed_fov` 独立状态 + 显示期偏移
+ `maxf(..., 1.0)` 下限。现在 `fov_squeeze_deg` 的文档说法才成立，且与帧率无关。

### 10. 其余较小的偏离

- `fade_in_time` 从硬编码 0.15 移到 config（ladder/swing/zipline 三个 config 早有这个字段）
- `entry_lean()` 接 ground_speed 参数，不硬编码 7.2
- 动画 fallback 名 `walk` / `Walk_Left` / `Walk_Right` 全部删除——项目里不存在，
  `_Left`/`_Right` 属于 Jog/Crouch 家族而非 Walk，照抄会破坏
  `test_every_routed_clip_has_a_node_in_the_graph`
- Task 7 的截图验证从原位置移到 Task 9（关卡当时还不存在）

---

## 已知空白

- **`tools/capture.gd` 够不到梁。** 出生点必须在梁的捕获体积**之外**（否则一进关卡
  就被夺走控制权、无法先站定调参），而 capture.gd 不驱动输入，所以自动截图管线拿不到
  平衡姿势了。要恢复需要给 capture.gd 接上 `scripts/player/input/` 里已有的
  `ScriptedInputSource`（测试早就在用）。本次范围外。
- **`HeadLook` 与 `BalanceLean` 在真实身体上的叠加未验证。** 架构论证成立（两者都是
  读-改-写、按子节点顺序链式调用、BalanceLean 挂在后面），但裸骨架跑不了 modifier，
  没有测试能证明。判据是「转头时倾斜仍在、倾斜时转头仍在」，需要实机看一眼。
- **曲线线上朝向不跟随。** 磁吸淡入结束后身体 yaw 锚定在入场切线，所以在弯曲或多段线
  上只有位移跟着曲线走、檐走的背不再随墙转。这是 `LineMove` 家族的既有约定，不是本次
  引入；已记入 `docs/feel-backlog.md`。spec 明确预期了多段管子拼接，将来要做。
- **手部 IK**（檐走扶墙的手、平衡木张开的双臂）与滑索/单杠/梯子同属既有空白，未做。
- **檐走能否从檐上主动翻下变成 Grab**：CDO 只说 `MG_OneHandBusy`，原作行为未测，未做。
- 原作的「屈膝跳上梁后立刻再跳可跳过 Balance」是 glitch，**本项目不复刻**，也不要把它
  的缺席当 bug 修。

---

## 过程中反复出现的一个模式，值得记一笔

这次有 **六次**「全套测试是绿的，但被测行为是坏的」：

1. 沿线投影符号反了，两个单元测试照样绿——因为线的朝向 φ 在 `project_input` 里被
   数学上消掉了，那两个测试从原理上就看不见符号错。
2. 端点进入当帧退出的 bug，测试把玩家放在线的**中点**，够不着端点。
3. `test_leaving_the_move_restores_the_camera` 从不构造也不退出 move——把
   `BalanceMove.exit()` 整个删掉它照样绿。
4. 骨骼倾斜的 fixture 把两个肩膀放在同一个 y/z 上，于是「从肩膀推出的轴」恰好等于
   「禁止使用的世界前向轴」，把 `_lean_axis()` 换成硬编码常量，四个测试全绿。
5. 进入门的每一个 fixture 都把线建在胸口高度，于是「走上去」这件事从来没被测过。
6. `note_travel()` 的调用点删掉全绿，而所有檐都会播 Idle。

对策是从第三次起把 **mutation 验证**定成硬性要求：**把代码改坏、确认测试真的失败、
再恢复**，并把 transcript 写进报告。后面每一条行为类断言都过了这一关，包括
reviewer 自己独立复现。建议以后碰到"断言的是行为而非数值"的测试时沿用。

---

## 一件与代码无关的事

有个 Godot 4.7.1 进程（PID 26808，非 console 版）从 2026-08-30 06:43 起一直在跑，
**不是本次会话启动的**，可能是你自己开着的编辑器。按仓库「不擅自 kill 非自己启动的
进程」的规矩没有动它。如果它其实是早期子代理留下的孤儿，它可能在拖慢所有 headless
运行，下次在机器前可以看一眼。
