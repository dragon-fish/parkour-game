# 12 · 关卡标注与 Kismet

← 返回 [README](README.md)

关卡里那些体积（触发器、复活点、空气墙、兴趣点）**各自是什么、用途写在哪**。

对象是 SP00 教程关（`Tutorial_p.me1` 等一组 `.me1`）。提取路线与 01 相同：
`ue3_decompress.py` → `ue3parse.py` → `mapdump.py` 的 `MapReader`。

**一句话结论：体积本身不带任何配置数据。** 用途 100% 由**类**决定，行为写在 C++
或 **Kismet** 里。所以作弊工具的体积可视化只能给出不同颜色的框——确实没有别的东西
可显示。

---

## 12.1 actor 类普查

✅ `Tutorial_p.me1` 中带 `Location` 的全部 actor（`tools/survey_actors.py`）：

| 类 | 数量 | 是什么 |
|---|---|---|
| `DecalActor` | 395 | 贴花，与玩法无关 |
| `TdTutorialCheckpoint` | **159** | 教学**进度**点 |
| `AmbientSound` | 74 | 环境音 |
| `BlockingVolume` | 59 | 空气墙 |
| `TdCheckpointVolume` | 57 | **复活**体积 |
| `PrefabInstance` | 41 | 预制体摆放 |
| `TdTutorialStart` | 23 | 教学段起点 |
| `CullDistanceVolume` | 12 | 渲染剔除 |
| `TdLookAtPoint` | 10 | 视线引导 |
| `Brush` | 9 | 编辑器画刷 |
| `InterpActor` | 6 | 会动的物件（门等） |
| `PathNode` | 5 | AI 导航 |
| `BookMark` | 4 | 关卡设计师的编辑器视角书签 |
| `TdLadderVolume` | 4 | 兴趣点 · 梯子 |
| `JuicePerformancePoint` | 2 | 性能采样点 |
| `TdLedgeWalkVolume` | 2 | 兴趣点 · 檐走 |
| `TdSwingVolume` | 2 | 兴趣点 · 单杠 |
| `TdTriggerVolume` | **2** | 通用触发 |
| `TdBalanceWalkVolume` | 1 | 兴趣点 · 平衡木 |
| `TdBarbedWireVolume` | 1 | 铁丝网 |
| `TdZiplineVolume` | 1 | 兴趣点 · 滑索 |
| `TdCheckpoint` | 1 | 复活点 |
| `Trigger` | 1 | 引擎原生触发 |
| `HeightFog` / `TdDirectionalFlareEmitter` | 1 / 3 | 大气 |

### ⚠️ 修正一处既有错误

`_local/me-reference/tutorial-blockout/` 的 README 写着「217 个检查点坐标，勾勒出
教程关玩家实际走的路线」。**这条是错的。**

`tools/build_blockout.py` 的 `PATH_CLASSES = ('checkpoint',)` 做的是**子串匹配**，于是
`TdTutorialCheckpoint`(159) + `TdCheckpointVolume`(57) + `TdCheckpoint`(1) = **217** 被
混成同一团点云。它画的不是路线，是整套检查点系统——进度点与复活点两套不同的东西被
叠在了一起。

## 12.2 体积不带配置数据

✅ 每一个体积（129 个，含空气墙）的 tagged property 只有：

```
Brush               Model(...)
BrushComponent      BrushComponent(...)
CollisionComponent  同上
Location            (x, y, z)
Tag                 '<类名>'          ← UE3 默认值，不是作者填的
SavedSelections     <编辑器选区残留，32 个体积上有>
```

**没有任何行为参数。** 没有「这个触发器做什么」的字段，没有时长、没有强度、没有目标。
`TdBarbedWireVolume` 就是 `TdBarbedWireVolume`，它伤人这件事写在 C++ 里。

这与 `TdPawn` 的 CDO 是同一套设计：Pawn 上挂一批运行时开关（`bTakeFallDamage`、
`GravityModifier`、`OverrideWalkingState`、`bAllowMoveChange`、`MinLookConstraint` /
`MaxLookConstraint`，见 [appendix/A1](appendix/A1-TdMove-CDO全量.md)），体积和脚本
翻转它们，各个 Move 读的始终是自己一直在读的那个字段。

### ✅ 体积的真实形状是可提取的

`BrushComponent` 上有 **`BrushAggGeom`**，即 `FKAggregateGeom`——与 `tools/hulls.py`
已经在解析的 `RB_BodySetup.AggGeom` **是同一个结构**，`ConvexElems` → `VertexData` /
`FaceTriData` 的走法完全一样。

以此路线对上表全部体积做提取：**129 / 129 成功**，每个 1 个凸包 8 个顶点（都是盒子）。

`build_blockout.py` 目前只为 marker 输出 `pos`，没有尺寸——不是解不出来，是没接这根线。

## 12.3 Kismet 才是「用途」所在

`TheWorld.PersistentLevel.Main_Sequence` 有 **876 个节点**，其中 **422 个带
`ObjComment`**（关卡设计师自己写的注释）。`mapdump.py` 原本不解 `StrProperty`，补上
四行就能读到。

### 远程事件词汇表

✅ 74 个 `EventName`，构成「关卡能对玩家做什么」的完整动词表。与本项目相关的：

| 事件 | 次数 | 说明 |
|---|---|---|
| `DISABLE_INPUT` / `ENABLE_INPUT` | 9 / 9 | **临时锁操作**。原作的做法是 Kismet 动作（`SeqAct_TdDisablePlayerInput` ×13 / `TdEnablePlayerInput` ×14），不是体积属性 |
| `LOI xxx` / `NO LOI xxx` | **21 组成对** | **逐个启用/停用兴趣点**：`swing` `zipline` `slide` `coiljump` `softlanding` `fence` `pipe1` `pipe2` `ramp` `springboard` `speedvault` `hwallrun` `balancewalk` `heaveup` `ljump` `jump` `jump2` `firstjump` `jumptoceleste` … |
| `ANIM_*` | 16 种 | 教学演示 NPC 的动画段落，含 `ANIM_stand_after_softlanding`、`ANIM_zipline_softlanding` |
| `FADE_IN_CHALLENGE` / `START_COMBAT_CHALLENGE` | 7 / 7 | 教学挑战段落 |
| `TutorialResetEvent` / `restart_tutorial` | 3 / 1 | 教学复位 |

⚠️ `LOI` 读作 Location/Line Of Interest，由命名和成对出现推断，未经字节码验证。

**这是一个我们此前没有的维度**：禁用**具体的可交互物**，而不是禁用**动作类别**
（后者是 `TdMovementExclusionVolume` 的 `bExcludeFootMoves` / `bExcludeHandMoves`）。
教程关「到这一步之前那根管子抓不住」就是靠前者做的。

### 两个 `TdTriggerVolume` 的实际用途

✅ 二者各自被一个 `SeqEvent_TdTouch` 的 `Originator` 引用：

| 触发器 | Godot 坐标 (m) | 设计师注释 | `MaxTriggerCount` |
|---|---|---|---|
| `TdTriggerVolume_0` | (-45.14, 49.63, 37.56) | `Activate` | 0 |
| `TdTriggerVolume_1` | (-41.54, 40.19, 27.48) | `Land` | 0 |

两点垂直落差 **9.44 m**。

⚠️ [03 §3.1](03-损速机制.md) 用「正式流程中那处 **9.5 m** 的跳跃」反证了坠落高度按
离地点（`SZD`）而非最高点计算。两者数值只差 0.06 m，**很可能是同一处**——但这是由
坐标相近推断的，没有直接证据把这对触发器和那次跳跃绑定。要坐实，需要在游戏里跑到
(-45.14, 49.63, 37.56) 附近确认那里就是那个跳点。

### ✅ `MaxTriggerCount` 是整数，不是布尔

UE3 `SequenceEvent.MaxTriggerCount`：**0 = 无限次**，N = 最多触发 N 次。上面两个都是 0。

「只触发一次」在原作里是这个整数的一个取值，不是一个独立的布尔开关。本项目
`ModifierVolume` 的对应字段应当同构（见
`docs/superpowers/specs/2026-08-29-status-modifiers-design.md`）。

另有两个名为 `OnceSwitch_0` / `OnceSwitch_2` 的子序列，用 `SeqAct_Switch` + `SeqAct_SetInt`
实现「只走一次」的分支——同一需求的另一种表达，用在序列而非事件上。

## 12.4 教程关是一条回环

⚠️ 结构由所有者在导入的 blockout 顶视图上梳理得出：**主线是一条回环**，跑完剧情后
转入自由探索，另有几条捷径和一条额外回环。以下是数据侧能对上的部分。

### ✅ 踹开后自动关上的门

`Main_Sequence.Prefabs.SPT_OnewayDoor_Seq`，15 个节点：

| 节点 | 作用 |
|---|---|
| `SeqEvent_TakeDamage` | **踹门的判定入口**——撞门在原作里是对门造成伤害 |
| `SeqAct_ChangeCollision` ×3 | `COLLIDE_BlockAll` → `COLLIDE_NoCollision` → `COLLIDE_BlockAll`，即**关 → 开 → 自己关上** |
| `SeqAct_Interp` ×3 | 门扇与闭门器的动画 |
| `SeqEvent_LevelReset` · `SeqEvt_TTRaceStarted` · `SeqEvt_TTRaceFinished` | 重开与计时赛时复位成「关」 |

引用到的 actor：

| actor | Godot 坐标 (m) | 网格 |
|---|---|---|
| `InterpActor_4` | (-41.9, 42.2, 63.1) | **`S_DoorMaintenanceD1Barge_02`** |
| `InterpActor_9` | (-41.8, 44.6, 63.1) | **`S_DoorClosingMech_02`** |
| `InterpActor_5` | (-41.9, 42.2, 63.0) | `S_DoorClosingMech_01` |

网格名自己就说明了机制：`Barge` 是原作对撞击动作的称呼（`TdMove_Barge`、
`ANIM_stand_after_barge`），`ClosingMech` 是自动闭门器。

**门不是「单向碰撞」，是「踹开后自动关上」。** 回不去是因为另一侧没有可踹的把手，
而不是因为挡了一层空气墙。前者比后者干净，也更好移植。

### ✅ 回环与计时赛复用同一份几何

门的复位由 `TTRaceStarted` / `TTRaceFinished` 驱动——同一份关卡几何，靠门的碰撞状态
区分「剧情/自由探索」与「计时赛」两种模式。

### 与本项目的对照

`scripts/level/checkpoint.gd` 的「LAST TOUCHED WINS」是对着这条回环验证的：当时用
noclip 飞回起点自杀，确认仍在**最后触碰**的检查点复活，而非最近的——看起来像「最近点」
的行为，只是第二圈走回第一圈的触发器、把它们重新标记为最后触碰。地图数据反过来印证了
这条回环确实存在。

⚠️ **回环意味着体积会被反复进入**，这是 12.3 那条「`MaxTriggerCount` 是整数」在设计上
真正要紧的原因：「只在第一圈放这段台词」和「每圈都放」是两种需求，布尔盖不住。

## 12.5 `SoftLanding` 是一个独立状态

来源 D（所有者 2026-08-29 在原作内实测）+ CDO。

✅ `TdMove_SoftLanding` 的 CDO（[appendix/A1](appendix/A1-TdMove-CDO全量.md)）：

```
PawnPhysics            PHYS_Falling        ← 下落物理
ControllerState        PlayerWalking       ← 玩家有控制权
bCheckExitToFalling    True
bCheckForSoftLanding   True
bConstrainLook         True
bDisableFaceRotation   True
DisableMovementTime    -1.0                ← 不禁移动
MinLookConstraint      (-16384, -5000, 0)  ← pitch ±90°, yaw ±27.5°, roll 锁死
MaxLookConstraint      ( 16384,  5000, 0)
```

✅ [11-状态机全图](11-状态机全图.md) §11.2 的能力表里，`bCheckForSoftLanding` 属于四个
状态：`180TurnInAir`、`Falling`、**`FallingUncontrolled`**、`SoftLanding`。

**死亡状态自己带着软着陆检查**——意味着失控坠落是**可以被改判**的。

### 软垫不是触发器

⚠️ 所有者实测：关卡里另有一个软垫，附近**没有任何触发器**；且从不致死高度落到软垫上
**可以正常翻滚**。

由此得出的模型：软垫是**带特殊属性的碰撞箱**。玩家进入 `FallingUncontrolled` 后失去
控制权，接下来的运动轨迹是纯弹道、因而**可预测**；若预测落点命中软垫，状态机被改判为
`SoftLanding`——仍锁操作，但落地不死。

这个模型能一次解释掉三处观察：第二个软垫没有触发器（机制在碰撞箱上）；低处落到垫子上
能正常翻滚（从未进入失控，机制根本没启动，垫子此时就是一块普通地板）；`bCheckForSoftLanding`
出现在 `FallingUncontrolled` 上（那就是「我预测的落点是不是软的」这个检查本身）。

❓ 那片贴着垫面的薄触发器是做什么的，仍然未知。曾假设它清除翻滚预输入，已被上述实测
推翻。

### 移植注记

`maximum_speed_for_roll_landing`（✅ `MaximumSpeedForRollLanding = -5000` → -50 m/s）
**不是**软垫拒绝翻滚的机制：在本项目重力 16.0 下要约 78 m 自由落体才够得到。它在
`pawn_config.gd` 里被记录但从未读取，见 `docs/final-review-findings.md` §1.6。

移植时检查应插在 `falling_move.gd` 判 `fall_height >= falling_uncontrolled_height`
**之前**。本项目的 `FallUncontrolledMove.enter()` 一进去就启动布娃娃并停住胶囊，从里面
捞人极难；在进失控之前先问一句「预测落点是不是软面」，就完全不用碰布娃娃。原作的
`FallingUncontrolled` 也带这个检查，但没有必要复刻那条更难的路径。

✅ **已实现**（`Probes.predicted_landing()` + `Probes.SOFT_LANDING_GROUP`）。落地做法：

- 软面的标记是**组名** `soft_landing`，不是节点类型——原作的垫子就是带属性的碰撞箱，
  没有对应的 actor 类可仿；用组还能让 CSG 和 GridMap 一样能当垫子。
- 弹道从**脚底**起步逐段射线，忽略尚未发生的空中输入。
- **不锁存**：坠落态仍有空中操控，所以每 0.2 s 重问一次，玩家能主动飘上垫子，也能飘走。
- 落到垫子上**整段落差按 0 计**，不是只免死。一条规则而不是两条，也顺带解释了「从低处
  落到垫子上一切正常」——那高度本来就没东西可吸收。

`docs/level-templates.md` 有面向地编的那一份。

---

## 复现

```sh
# 关卡包（软链接指向本机正版安装）
_local/mirrors\ edge/TdGame/CookedPC/Maps/SP00/Tutorial_p.me1

# 依赖：lzallright
python tools/ue3_decompress.py <map>.me1 <map>.dec
python tools/survey_actors.py <map>.dec          # 12.1 的类普查
```

12.2 的凸包提取、12.3 的 `StrProperty` 解码、Kismet 注释导出都是在
`tools/hulls.py` 与 `tools/mapdump.py` 之上的几十行，**尚未落进 `tools/`**——
接进 `build_blockout.py` 是「把体积导入成真节点」那批工作的一部分。
