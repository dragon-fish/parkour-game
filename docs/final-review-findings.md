# 终审发现（2026-08-18）

16 个任务全部完成后，对整批次（`2fdd754..322474d`，44 个 commit）做的三路独立终审。每路各带一个视角，互不重叠：

- **A 运行时正确性** —— 十个 move 与五个共享组件**组合起来**是否成立（各任务是孤立审的，接缝没人看过）
- **B 参数保真度** —— 每条 `## Source:` 引文是否属实、单位换算、确证标记是否诚实
- **C 测试可信度** —— 578 个断言到底约束了什么

**这些不是"手感不对"。** 手感问题指数值需要调；下面大部分条目是**机制根本没跑到玩家面前**，或者**测试没有约束住已经写好的代码**。

分类标记：

- 🔧 **判据明确** —— 只有一个正确答案，不涉及手感取舍
- ⚖️ **需你定夺** —— 修法会改变手感，属于你保留的决定权

---

## 第一部分：机制未到达玩家

### 1.1 ⚖️ 超出速度上限的部分会在一个物理帧内被抹平

`player.gd:1092`：

```gdscript
horizontal = horizontal.move_toward(wish_dir * target_speed, config.pawn.accel_rate * delta)
```

`move_toward` 是**对称**的。它不只把低于目标的速度拉上来，也把**高于**目标的速度按 `accel_rate = 61.44 m/s²` 砸回去——比五行之外的刹车路径（`base_friction 40 × braking_friction_strength 0.5 = 20 m/s²`）**狠三倍**。

后果是游戏里每一个"超速奖励"来源都活不过一两帧：

| 来源 | 设计意图 | 实际存活 |
|---|---|---|
| Vault 甜区 +0.8 m/s | "补偿已经掉速的玩家" | **16 ms**（一帧） |
| 下坡滑铲净收益（9 m/s） | 下坡值得滑 | 1.8 帧 |
| 墙跳推离 | 技巧梯度的回报 | 同上 |

具体：能量 3.5 → `speed_cap()` 6.5，以 6.5 m/s 冲 0.9 m 障碍，`SpeedVaultMove.enter()` 算出 `_exit_speed = clampf(6.5 + 0.8, 0, 7.2) = 7.2`。空中能量冻结，落地时上限仍是 6.5，下一帧预算 1.024 m/s——**一帧到位**。而在玩家**没有**掉速的情况下，`clamp_speed_max` 等于 `ground_speed`，加成本来就是 no-op。所以这个加成在两种情况下都不存在。

附带一个反向怪现象：**按着 W 比松开 W 掉速快三倍**。

**修法方向**：驱动分支只应加速，不应减速；超速部分交给摩擦路径按 `braking_friction_strength` 衰减。这是原版的结构（加速与摩擦是两条独立通道）。**衰减速率本身是手感旋钮**，所以标 ⚖️。

---

### 1.2 🔧 Vault 表六行里有两行是死代码

`probes.gd:214`：

```gdscript
if _vault_high.is_colliding():
    return _no_hit()
```

`VaultHigh` 建在 `y = 0.45`（`player_builder.gd:135`），胶囊高 1.8、原点在中心，所以这条射线在**脚上方 1.35 m**。凡是高于 1.35 m 的障碍**按定义**挡住它 → 直接 `_no_hit()`。

于是 Task 14 忠实转写的 `vault_over_high` / `vault_onto_high` 两行——各自带着独立的时长、2–4 m/s 速度钳制和 `reset_camera` 标志——**永远无法被选中**。`table_ceiling()` 返回的 1.92 作为 `vault_query()` 的上界是死代码，该查询实际只能返回 `(0.35, 1.35]`。

Task 14 的测试（`test_vault_variants.gd:40-46`）直接调 `pick_variant(1.7, ...)`，**不经过探针**，所以抓不到。

**连带**：1.35–1.8 m 这个高度带**没有任何通过手段**——vault 被胸高射线拒绝，抓边要求 `min_wall_height = 1.8` 也拒绝。玩家唯一选择是原地跳（顶点 1.96 m）落到上面。而跳起来只会更糟，因为 `height` 是从**正在上升的脚**量起的。

---

### 1.3 🔧 Vault 的顶面探针用的是常量距离——和刚修好的抓边是同一个 bug

`probes.gd:217`：`_query_surface(_config.speed_vault.vault_reach)`。

我们在 Task 16 修复轮刚把 `ledge_query()` 从"按搜索半径发射"改成"按前向射线**实际命中的面**发射"（`probes.gd:365`，`face_distance + LEDGE_ANCHOR_MARGIN`）。**`vault_query()` 里的同一个错误没有一起修。**

后果：向下射线只有在障碍深度 ≥ `1.4 − d` 时才落在障碍上，有效窗口是 `d ∈ [1.4 − depth, 1.4]`；而 `should_commit()` 要求 `d ≤ max_distance_time × speed`。**低速变体的两个窗口不相交。**

具体：以 1.5 m/s 走向一个高 0.9 m、深 0.4 m 的栏杆。`step_up_right_leg_88` 在每个轴上都匹配（高度 0.48–1.48、`entry_speed_max` 2.0、`speed_z` 0.0）。探针有效窗口 `d ∈ [1.0, 1.4]`，提交要求 `d ≤ 0.4 × 1.5 = 0.6`——**无交集**。玩家撞死在一个表格说他应该踩上去的栏杆前。

一般地：`step_up_right_leg_88` 需要深度 ≥ 0.6 m 才可能触发，`auto_step_up_right_leg` 需要 ≥ 0.8 m（1 m/s 时需 ≥ 1.2 m）。

**这个缺陷在测试里已经以"迁就"的形式留下了痕迹**：`tests/test_probes_vault.gd:12-17` 记录说 brief 给的箱子"整个落在那个点之前，所以顶面射线从它们上方飞过去打到了空地板"，于是**每个 fixture 都被挪到跨越 z = −1.4**。当时把它当环境问题绕过去了。

⚠️ 修这条要小心：`vault_query()` 里含有你并行开发的自动上台阶下界，不要动那部分。

---

### 1.4 🔧 站立下蹲无法进入，且会攒出一次"迟到的滑铲"

`walking_move.gd:41-68` **从不返回 `CROUCH`**。spec §5.3 的确证 GBA_Crouch 表有五个出口，接了四个；"地面 + 无水平速度 → Crouch"这一行**没有任何进入路径**。`CrouchMove` 已注册，但只能从衰减掉的 `SlideMove` 进入。

更糟的是那次按键**没有被消费**：站定按 Shift，`horizontal_speed() 0 < slide_abort_speed 2.5` 短路，`consume_roll()` 从未被调用。`roll_trigger_time` 是 1.0 s，所以这次按键仍然有效。此时按 W，`accel_rate = 61.44 m/s²` 在约 0.04 s 内到 2.5 m/s，第三帧闸门用**一秒前那次按键**通过——玩家莫名其妙滑出去。

**所以现状是：没有办法下蹲，却有办法意外滑铲。**

---

### 1.5 ⚖️ 落地四档惩罚完全无效——最重的落地代价不到十分之一秒

`falling_move.gd:144-147` 只扣 `velocity`，**不扣 `speed_energy`**。第一层立刻从第二层重新收敛回来。

具体：6 m 高、7.2 m/s、能量 7.0 落地。`TIER_HARD` → `keep = 0.35` → 2.52 m/s。然后 `_update_speed_energy()` 什么也不做（2.52 < `speed_cap() × 0.9 = 6.48` 走 `pass` 分支，`wish != ZERO` 又跳过 `decay()`），能量仍是 7.0、上限仍是 7.2。`ground_accelerate` 用 4.6 帧把 2.52 拉回 7.2——**76 ms**。

这与 backlog 第 2 条是同一机制（撞墙速度归零但能量完好），但后果更重：**Task 6 整套落地分档系统是惰性的**，不是"偏松"。

标 ⚖️ 因为"落地该扣多少能量"是手感取舍。但注意 backlog 第 2 条提的对称修法（主动移动时实际速度远低于上限就扣能量）会一并覆盖这条。

---

### 1.6 🔧 翻滚在 5.2 m 有用、5.4 m 突然无用

`player.gd:167-168`：`landing_keep_ratio()` 的 `TIER_HARD` 分支**无条件**返回 `hard_keep`，完全不看 `rolled`。

- 落 5.2 m 并翻滚 → `TIER_ROLLABLE`，`keep = lerpf(1.0, 0.35, 0.35) = 0.774`
- 落 5.4 m 并翻滚 → `TIER_HARD`，`keep = 0.35`

**0.2 m 的高度差把一次同样成功的翻滚回报砍掉一半以上。** 而 `FallingMove:130-132` 仍然记 `rolled = true` 并消费掉缓冲按键——玩家看见翻滚动作触发了，却什么也没得到。

`maximum_speed_for_roll_landing`（−50 m/s，约 156 m 落差）被记录但从未读取，所以也没有别的东西界定"翻滚从哪里开始不管用"。

---

### 1.7 🔧 墙跳把未压平的墙法线加进速度，斜墙上超高 71%

`wall_run_move.gd:202-203` 与 `:240`：

```gdscript
velocity.y = <由高度换算的上升速度>
velocity += _normal * wall_jump_push_away(...)
```

`wall_jump_quality()` 和 `wall_jump_push_away()` 内部都**刻意**把法线压平成水平（`Vector3(n.x, 0.0, n.z)`），但调用处用的是**未压平的 `_normal`**，于是推离力漏进了垂直预算。而 `Probes.MAX_WALL_NORMAL_Y = 0.3` 明确允许最多约 17.5° 偏离垂直的墙。

具体：法线 `(0.954, 0.3, 0)`、quality 1.0。上升速度先被设为 `sqrt(2 × 8.0 × 1.6) = 5.06` m/s（对应设计的 1.6 m），然后 `+= 0.3 × 5.2 = 1.56` → 6.62 m/s，顶点 **2.74 m 而非 1.6 m，超出 71%**。

**这条特别要紧**：墙跑无限连跳的风险当初是以"每次跳跃的上升被 `JumpOffZHeight` 约束"为前提被接受的（spec §8）。这个前提在斜墙上不成立。

同一行 `:240` 的 `velocity -= _normal * wall_stick_force` 在同一面墙上每帧额外加 −0.15 m/s 垂直分量；而且它**没有乘 delta**，所以其等效 30 m/s² 会随物理帧率变化。

---

### 1.8 ⚖️ 摩擦力的整条坡度链只在松开按键时生效

`Friction.walk_friction()` 只有一个调用点：`ground_accelerate()` 里 `wish_dir == Vector3.ZERO` 的分支。**按着任何移动键的玩家永远碰不到它。**

于是 `upward_walk_friction_scale`、`downward_walk_friction_scale`、`min_walk_friction_modify`、`max_walk_friction_modify` 整条链只调制**松开按键的玩家**——与 `friction.gd` 自己头部写的"下坡是免费加速道、上坡是税"正好相反。`WalkingMove` 也没有 `SlideMove:163` 那样的沿坡重力项。

具体：按住 W 上下跑 25° 斜坡。两个方向的目标都是 `speed_cap() × 1.0`，收敛预算都是 `accel_rate × delta`，**代码路径里没有任何地方读 grade**。松开按键，坡度突然开始起作用。（实测上下坡速度的残余差异来自 `move_and_slide()` 自己的斜面投影，不来自这条参数链。）

标 ⚖️ 因为"走路要不要加沿坡重力项"是设计决定。

---

### 1.9 🔧 滑铲声明的 yaw 约束永远不会绑定

`camera_rig.gd:144-148`：非绝对分支里 `reference = body.rotation.y`——**当前** yaw，所以 `relative` 塌缩成 `yaw_delta`，钳制退化为**每帧速率限制**而非扇形。

`SlideConfig` 是唯一的消费者（`constrain_look = true`、±54.9° yaw、`absolute_yaw_constraint = false`）。按 `mouse_sensitivity = 0.0022 rad/px`，要在一个物理帧内绑定 ±0.958 rad 需要 **435 px** 的鼠标位移。实际上滑铲中可以转满 360°。

俯仰那一半是好的（它对着持久的 `_pitch` 钳制），**只有 yaw 是死的**。修法就在上面两行：绝对分支已经正确地只捕获一次基准。

⚠️ 这与 backlog 第 0 条（身体/视角解耦）**无关**，不需要动那个。

---

### 1.10 🔧 双墙同时命中时靠求值顺序决定贴哪面

`probes.gd:432-448`：`wall_query()` 先测左、再测右，返回第一个命中。在竞技场的 zig-zag 走廊里（半宽 0.45、射线长 0.5）**两侧同时命中**，于是 `player.wall_side`——以及由它决定的镜头滚转和跳跃推离方向——**由求值顺序而非几何决定**，与朝向和远近无关。第一次推离后会自我修正，但初次贴墙和滚转是任意的。

---

## 第二部分：测试覆盖的真实边界

**审查者注入六个独立的错误实现，六次全部 578 断言 / 0 失败通过。** 以下每条都附了"什么样的错误实现能通过"。

### 2.1 整体判断

套件**不是灌水**：runner 强制每个 `test_` 方法必须断言，没有人往 `tests/` 下加子目录（那会因为发现逻辑非递归而静默隐藏测试），`run_tests.ps1` 的 `SCRIPT ERROR` 扫描推理正确、白名单窄且诚实标注，漂移守卫确实无法洗白自己。`SpeedEnergy`、`FallTracker`、`Friction`、vault 表、墙跳梯度这些**纯算术层被钉得很硬很诚实**。

问题在于**它在代码"纯"的地方厚，在代码"接线"的地方薄**：

> 578 是一个强算术套件加一层薄接线，不是对游戏行为的 578 条约束。

### 2.2 已证明能通过套件的六个错误实现

| # | 注入的错误 | 结果 |
|---|---|---|
| 1 | `_apply_landing_cost` 改成 no-op（落地不扣速） | 578 / 0 绿 |
| 2 | `Player.ground_grade()` 直接 `return 0.0` | 578 / 0 绿 |
| 3 | `_incidence()` 换成注释明确说错的 `asin(dot)` | 578 / 0 绿 |
| 4 | `CrouchMove` 同时去掉胶囊收缩与速度修正 | 578 / 0 绿 |
| 5 | `air_accelerate` 的上限换成平的 `air_speed` | 578 / 0 绿 |
| 6 | `WalkingMove` 起跳处的 `jump_add_xy` 归零 | 578 / 0 绿 |

第 3 条尤其讽刺：那个公式的注释写着"已数值验证过，优于被否决的 `asin(dot)`"，但把被否决的版本换回去，套件毫无反应——04 §4.1 的 57°/60° 迟滞带对测试而言是装饰品。

第 6 条也有反讽：协程起跳点之所以有覆盖，正因为审查发现那里漏了；**一直正确的另外两个起跳点反而没人看着**。

### 2.3 零覆盖的两个 move

- **`CrouchMove`** —— 唯一涉及它的断言是 `config.crouch.speed_modifier == 0.4` 这个字面量比对（`test_config_layout.gd:54`）。胶囊收缩（镜头的下蹲提示通过 `current_capsule_height()` 读它）、0.4 速度上限、净空门控的起身、以及"按住蹲的滑铲衰减后是否真能到达这个 move"——全部无约束。
- **`GrabMove`** —— 没有任何测试提到 `Move.GRAB` 或构造 `GrabMove`。能通过的错误实现：`physics_update` 无条件返回 `FALLING`；把注释里长篇描述过的 `top -= basis.z * 0.4` 符号反转改回去（落点比墙面**短 0.3 m**，脚踩空）；在 `enter()` 而不是在提交时刻捕获 `_exit_direction`。

`test_probes_ledge.gd` 覆盖了 `GrabMove` 消费的那个锚点——这也是锚点 bug 被抓到的原因——**但消费者本身没有覆盖**。

### 2.4 验收清单文件本身最不具行为性

这是全套里最声称"证明了重做成立"的文件，而它的断言最不涉及行为：

- `test_10_a_flat_jump_hangs_for_about_one_and_a_half_seconds` —— **方法名是一个行为声明，方法体是两个 config 字段的算术**（`2.0 * base_jump_z / gravity`），没有 `Player`、没有物理帧、没有跳跃。能通过的错误实现：`FallingMove` 用 `gravity * 0.5 * delta`，或 `WalkingMove` 设 `velocity.y = base_jump_z * 0.5`——滞空时间减半或加倍，都是绿的。
- `test_2` —— 两个纯 config 比较。其行为性的那一半（空中速度不被钳到接近地面速度）正是注入 5 推翻掉的。
- `test_5` —— 两个字面量的算术。`wall_jump_push_away` 完全无视 `cfg` 返回常量也能过；抓到它的是**另一个文件**。
- `test_8` —— 三次布尔字段读取。`MoveManager._push_look_constraint()` 整个删掉也能过。

**同一文件里的 `test_8b`（绝对 yaw 扇形）是全套最强的测试**，它明确击败了"只断言停在某处"的陷阱。那才是其余七条应该达到的标准。

清单还**静默漏掉了第 4 项**（"落地/vault/踢墙都要花速度"）——覆盖了 1、2、3、5、6、8、10，丢掉 4、7、9、11 且没说明丢了哪些、为什么。7/9/11 确实无法在无头环境判定；**4 可以，而且正是它能抓到 2.2 表里的第 1 条**。

### 2.5 归档里丢失且从未替换的守卫

Task 1 归档 20 个文件时，连同丢掉了几个**其行为并未改变**的守卫。这和竞技场漂移守卫是同一个模式，但那个已经恢复了，这些没有：

- **主场景从未在任何测试里启动过。** `tests/legacy/test_arena.gd` 曾钉住 `Arena._ready()` 会跑、导出会解析、config 注入会到达 player 与面板、玩家会在出生点稳定、HUD 接线正确。`arena.gd` 本批次改了 28 行，那些行为一条也没变。`test_generated_scenes.gd` 虽然 *instantiate* 了 `main.tscn` 但**从不加入场景树**，所以 `_ready()` 从不执行。结合 2.6，**"游戏能启动"目前是无断言的**。
- **`tests/legacy/test_grounded_oracle.gd`**（5 个测试）钉住的不变量被 `MoveManager` **逐字保留**了下来（`run_tests.ps1:66-69` 明说），却没有测试。见 2.7。
- **`tests/legacy/test_state_machine.gd`** 钉住 exit-then-enter 顺序、KEEP 不重触发 `enter()`、变更信号载荷、重启会退出当前状态。`MoveManager` 全部保留，`test_move_manager.gd` 一条也没覆盖。
- **`tests/legacy/test_input.gd:15`** 钉住 `jump_pressed` 是只持续一次轮询的边沿。套件里每个驱动型测试都依赖这条，没有任何断言。
- **`tests/legacy/test_player_scene.gd:20`**（`test_player_scene_never_references_the_licensed_model`）—— **授权合规的绊线**，`player_builder.gd:54-70` 说它的缺失"弄坏过每一次 clone"。已归档、未替换。那个 gitignore 掉的模型场景仍在磁盘上（每次跑套件都产生 `invalid UID` 警告），而漂移守卫只比对 `player.tscn` 与 `PlayerBuilder`。
- **`tests/legacy/test_probes.gd:235`** 钉住"抓边距离不得支配 vault 的胸高测试"——正是 `probes.gd:133-142` 说那套按查询重新瞄准的机制存在的理由。未替换。

### 2.6 漂移守卫仍抓不到什么

守卫在"能否洗白自己"这个问题上是**可靠的**：不写任何文件、内存树对已提交文件、报告首个分歧的两侧、config 默认值变了而没重新生成也能抓到。但它抓不到：

- **脚本导出属性，任何节点上的。** `arena_builder.gd:858-866` 设置 `_root.player`、`_root.spawn_point`、`hud.player`。删掉 `_root.player = player` 再重新生成：签名比对的是节点路径、原生类、脚本 `resource_path`、transform 和少数资源字段——**没有一项会变**——守卫保持绿色，而游戏在 `Arena._ready()` 崩溃。`Player.body_scene`（授权敏感的那个）、`camera_rig`、`probes` 同理。
- **非 `Node3D` 节点只比对路径 + 类 + 脚本。** 那就是 `WorldEnvironment` 及其整个 `Environment`（背景模式、天空、环境光源），加上 `DebugHud` 与 `TuningPanel` 两个 `CanvasLayer`。
- `DirectionalLight3D.shadow_enabled`、光照强度与颜色。
- **`CollisionShape3D.disabled`** —— 文件头声称比对了 enabled 标志，对 `ShapeCast3D` 和 `RayCast3D` 成立，对 `CollisionShape3D` 不成立。
- 第二个及以后的表面材质（只取 `get_active_material(0)`）。
- 任何刚体或射线的碰撞层/掩码。

### 2.7 接地声明不变量在八个 MoveManager 测试里全程关闭

`test_move_manager.gd:8-24` 的 `StubMove` 从不设置 `player`，于是 `MoveManager._declaration_count()` 返回 `-1`，**接地声明不变量在全部八个测试里被禁用**——这是 `move_manager.gd:186-191` 的设计。

而那正是这个管理器里最安全攸关的机制（它自己的注释：一个忘记 `set_grounded()` 的 move 会继承 `true` 并每帧续满协程时间，**即无限跳**）。它有失效保护路径（`clear_grounded_undeclared()`）、报告路径（`assert` + `push_error`）、启动路径（`_clear_stale_grounded_after_start()`）——**三条都没有覆盖**。`run_tests.ps1:70-73` 的两条白名单条目正是为它们准备的，而如其自己的注释所承认，它们是休眠的。

能通过的错误实现：把 `_check_declared_grounded()` 的函数体整个删掉。

### 2.8 名不副实的测试

- `test_wallrun_jump.gd:44-52`（`test_the_gradient_is_continuous_not_stepped`）断言的是 `push + 0.0001 > previous`——**单调不减，不是连续**。一个量化成三档的 quality 函数是单调不减的，能通过一个名字承诺它不可能通过的测试。那个 `+ 0.0001` 补偿（因为 harness 没有 `check_less`/`check_ge`）还放行了**完全平坦**的段。
- `test_speed_energy_wiring.gd:58-69`（`test_the_walk_modifier_caps_speed_and_banks_almost_nothing`）只断言了"限速"这一半，方法名里的"几乎不攒能量"从未检查。能通过的错误实现：`Player._energy_mode()` 无条件返回 `SPRINT`——因为走路限速来自 `WalkingMove` 里的 `config.pawn.walk_velocity`，不来自能量模式，所以三个累积因子的**接线**（区别于 `SpeedEnergy.accumulate` 的算术，那部分测得很好）是无约束的。
- `test_wall_run_entry.gd:24-31`（`test_a_wall_run_has_no_duration_cap`）遍历 `get_property_list()` 断言没有属性名含 `"duration"`。它钉的是**命名约定**：把时长上限改名叫 `wall_running_max_time`、或在 `WallRunMove.physics_update` 里写死一个字面量，都能通过。

### 2.9 人类试玩三次跑赢了套件

backlog 里三条试玩发现的缺陷，**每一条旁边都有一个几乎抓到它的测试**：

- **第 0 条**（墙跳梯度两端够不到）：梯度作为纯算术在整个 `[0,1]` 定义域上被测过，唯一的实时测试（`test_wallrun_jump.gd:98`）还长篇记录了真实玩家只能到 quality ≈ 0.5。实现者如实报告而没有伪造端点——这是好的操守——但**没有任何断言陈述"可达区间"**，而那正是坏掉的东西。
- **第 1 条**（空中转向免费）：被 `test_turn_deceleration.gd:143` **主动钉成了正确行为**。这是同步编写的套件所携带风险的最干净的例证：**一个设计错误变成了一条需求。**
- **第 2 条**（撞墙后能量完好）：`test_speed_energy_wiring.gd:71-94` 驱动的**正是这个场景**——五秒钟顶着墙推——却只断言 `energy < 1.0`，即"没有攒到能量"。你发现的那个不对称（守卫阻止累积却从不扣减）**距离已写下的代码只差一条断言**。测试停在了 bug 的门口。

---

## 第三部分：参数与出处

拟合与换算层状况很好：**36 处单位换算全部精确**，vault 表 78 个值连 `ledge_offset_z` 都对得上，⚠️/❓ 标记反复且诚实地镜像了手册自己的措辞（`SpeedMaxBaseVelocity` 角色不明、`LandingSpeedReduction` 单位未验证、三个加速因子方向未验证）。

**曲线独立验算通过**：

| E | 目标 | 实算 | 残差 |
|---|---|---|---|
| 0.0 | 0.0 | 0.000000 | 0 |
| 0.4 | 4.0 | 4.000042 | +4.162e-05 |
| 1.0 | 5.2 | 5.200041 | +4.133e-05 |
| 3.5 | 6.5 | 6.500059 | +5.940e-05 |
| 7.0 | 7.2 | 7.200067 | +6.749e-05 |

最大 |残差| = 6.749e-05，**7e-5 的声称成立**，但只剩 4% 余量——config 自己写的"低于 1e-4"是更稳妥的说法。衰减 `k = 2√7/3` 的闭式解 `t = 2√E₀/k` 给出**恰好 3.000000 s**。

### 3.1 🔧 一个 ✅ 标在原版没有的开关上

`walking_config.gd:10`：`## Source: 06 §6.2 bCheckForVaultOver on TdMove_Walking. ✅`

三条独立证据反驳这个归属：

1. A1 的 `TdMove_Walking` CDO 块只有六行，**不含任何探测开关**（`ControllerState`、`bShouldUnzoom`、`bUseCameraCollision`、`bEnableFootPlacement`、`bEnableAgainstWall`、`bAllowPickup`）。
2. A2 的 `[TdGame.TdMove_Walking]` 只有 `FrictionModifier`、两个待机动画计时和三行 `UnarmedIdleAnims`。
3. **06 §6.2 把这个字段归给另一个类**——它的小节标题是"`TdPhysicsMove` 追加的**环境探测开关**"，而同章 §6.1 的继承树把 `TdMove_Walking` 放在 `TdMove` 的直属子类、**在 `TdPhysicsMove` 之外**。05 §5.7 也称它为 `TdPhysicsMove.bCheckForVaultOver`。

行为本身站得住（地面奔跑当然需要 vault 探测，原版一定通过别的途径到达 vault 表），**但标记不站得住**。应改为 ⚠️ 并注明原版通过 `TdPhysicsMove` 表达，而 `TdMove_Walking` 不是其子类。

### 3.2 🔧 支撑抓边冷却偏离的那个数字是编的

`grab_config.gd:61` 与 spec §10.6 都写 `TdMove_GrabTransfer` 自己的 `RedoMoveTime` 是 0.5。**两份源里都没有这个字段**：A1 的该类只有 `Allowed2DTransferDistance`、`AllowedZTransferDistance`、`PawnPhysics`、`ControllerState`、`bShouldHolsterWeapon`、`bDisableFaceRotation`、`AiAimOneShotPenalties`、`AimMode`、`DisableMovementTime`、`DisableLookTime`；A2 只有三项；`TdMove_GrabPullUp` 同样没有。**全库只有 `TdMove_Grab` 有，值 0.15。**

0.45 这个值本身是已定案的偏离，不是问题；问题是**让它显得合理的论据没有出处**。`docs/feel-backlog.md` 第 6 条也重复了这个 0.5，需一并修正。

### 3.3 🔧 第二个无出处且在跑的数值

`pawn_config.gd:34`：`@export var terminal_velocity: float = 60.0`——`PawnConfig` 里**唯一没有任何注释**的字段。全手册搜 `terminal` / `TerminalVelocity` / `MaxFallSpeed` 零命中。但它不是惰性的：`falling_move.gd:32` 每帧用它钳制下落速度。

所以"除了 `base_friction` 还有没有别的无据数值"的答案是：**有，一个**，而且不像 `base_friction` 那样被记录过。

### 3.4 🔧 滑铲的滚转约束被静默放宽

`slide_config.gd:39-40` 的注释只引了俯仰和偏航，两者都对（10000/65536×360 = 54.93°）。但源在**两端都把滚转锁死为零**——A1：`MinLookConstraint (-10000, -10000, 0)` / `MaxLookConstraint (10000, 10000, 0)`——而 config 传的是 `-PI`/`+PI`，即完全不约束。对照墙跑：源的 `-32768/32768` 确实是 ±180°，`-PI/PI` 转写正确。

### 3.5 🔧 spec 偏离记录（§10）缺的条目

1. **`CrouchConfig.speed_modifier = 0.4` 覆盖了一个确证的 per-move 值。** `TdMove_Crouch.SpeedModifier = 0.2` 被**两处**确证（A1 `0.20000000298023224`、A2 `SpeedModifier=0.2f`）。本项目刻意改用 Pawn 级的 `CrouchedPct = 0.4`。config 注释里的理由成立，但这是一个 per-move config 字段**明知故犯地不转写它的 per-move 源**，且是 **2× 的行为差异**。
2. 滑铲滚转约束（3.4）。
3. `check_for_vault_over` 根本没有原版对应物（3.1）——标记改正后即成为一条偏离。
4. `terminal_velocity = 60.0`（3.3）。
5. `speed_turn_deceleration_factor = 2.2282` vs 原版的 10 —— 已知且刻意，但 §10 正是未来读者会去查的地方，那里没有。

### 3.6 ⚠️ 调参地雷图（对你接下来的手感调整直接有用）

**`ground_speed = 7.2` 是枢纽，四个字段依赖它，只有一个写明了：**

| 依赖方 | 耦合关系 | 有无标注 |
|---|---|---|
| `camera_config.gd:49` `fov_speed_ref = 7.2` | 必须跟随 `ground_speed`，否则"满速 105°"失效 | ✅ 有文档——**而且已经过期过一次**（曾停在 9.0） |
| `camera_config.gd:87` `bob_frequency = 2.618` | `= 2π/(ground_speed/3.0)`，实算 2.6180 | ❌ 推导写了，依赖关系没标 |
| `pawn_config.gd:170` `speed_turn_deceleration_factor = 2.2282` | `= 7.0/π`，其中 7.0 是**曲线的 X 端点**，不是 `ground_speed` | ❌ 未标；改动节点表会静默失效 |
| `speed_vault_config.gd:132,140` `clamp_speed_max = 7.2` | 源注明 `ClampSpeedMax = 720` "恰好等于 GroundSpeed 上限" | ❌ 未标为项目不变量 |

**另外两处：**

- **`base_jump_z` / `gravity` / `skill_roll_landing_height` 三角。** 顶点 = 5.6²/(2×8.0) = **1.96 m**，距 2.0 m 的翻滚阈值**只差 4 cm**。注释解释了，但没有任何东西强制。把 `base_jump_z` 调过 5.657 m/s 或调低重力，**每一次平地跳都会开始扣速**——09 §9.1 对此的警告是"游戏立刻不能玩"。既然 `slide_camera_drop` 拿到了测试钉，这个三角也该有一个。
- **`slide_camera_drop` 还有第二个未记录的依赖。** 注释指明了 `slide_camera_drop >= eye_height`，但推导还假设**下蹲胶囊顶面位于 body 原点**——即它同时耦合到 `CrouchConfig.crouch_capsule_height` / `SlideConfig.slide_capsule_height`（都是 0.9）。单独改胶囊高度会移动这条不变量所保护的天花板，而没有注释或测试会抓到。

### 3.7 🔧 小项

- `wallrun_jump_config.gd:4` 表头写"✅ **ALL FOUR CONFIRMED**"，其下是**五个**确证字段（五个都核对通过，只是计数过期）。
- `camera_config.gd:104` `land_dip_speed_ref = 18.0` 没有 source 行，而 09 §9.1 的 Landing 表恰好标了这个数：`land_cost_speed_ref | 18.0 | HardLandingHeight 530 → 落地速度 9.21 | 你的阈值高一倍`。它是感知旋钮不是物理量，偏离没问题，但该有其他相机字段那样的一行"项目值，原版等价物是 9.21"。
- `tools/arena_builder.gd:803` 裸引用 `test_practice_areas_do_not_overlap_each_other`，它只存在于 `tests/legacy/test_arena.gd:617`；上面三行的"已归档且无人执行"声明贴的是"包含性测试"，没盖到这条。
- 五个测试文件把 `world_fixture.gd` `preload` 进一个 `const TestWorld`，遮蔽了该文件自己的 `class_name TestWorld`；另外三个直接用全局名。今天无害，以后会让人困惑。

---

## 处置建议

按"能否被自动化证伪"和"是否影响你试玩判断"排序：

**先修，否则你的试玩会得出错误结论**（🔧 判据明确）：

1. **1.2 胸高射线** —— 否则 vault 表六行里两行永远试不到，1.35–1.8 m 高度带完全不可通过
2. **1.3 vault 顶面探针** —— 否则低速矮障碍会莫名撞停
3. **1.4 下蹲接线 + 消费按键** —— 否则没法下蹲，且会随机滑铲
4. **1.7 墙跳法线压平** —— 否则斜墙上超高 71%，而 spec §8 接受无限连跳风险的前提正是这个高度受约束
5. **1.6 翻滚阈值断崖** —— 否则你在 5.2/5.4 m 之间会得到自相矛盾的体验
6. **1.9 滑铲 yaw 约束** —— 否则该约束根本不存在
7. **1.10 双墙求值顺序**

**先记，等你试玩后定夺**（⚖️ 影响手感）：

- 1.1 超速衰减速率
- 1.5 落地该扣多少能量（与 backlog 第 2 条同源）
- 1.8 走路要不要读坡度 / 加沿坡重力

**文档与出处**（🔧，无行为影响）：3.1 / 3.2 / 3.3 / 3.4 / 3.5 / 3.7，以及修正 `docs/feel-backlog.md` 第 6 条里那个编造的 0.5。

**测试**（按审查者给的优先级）：

1. 断言落地真的扣速（2.2 表第 1 条 + 补上验收清单漏掉的第 4 项）
2. 把 `main.tscn` 加进场景树跑一帧（同时补上漂移守卫的导出属性盲区，以及"游戏能启动"这条目前无断言的保证）
3. 接地声明不变量（同时唤醒 `run_tests.ps1` 那两条休眠白名单）
4. `CrouchMove` 与 `GrabMove` 各一个行为测试
5. 斜坡上钉住 `ground_grade()`
6. 正对与平行两个角度钉住 `_incidence()`
7. 墙跳的水平推离、墙跑的退出速度
8. 恢复授权绊线（`test_player_scene_never_references_the_licensed_model`）
