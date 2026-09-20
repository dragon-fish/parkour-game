# 镜之边缘关卡流式在场设计

让导入的章节在任何时刻只有原版此刻加载着的那些包在场，时机取自原版自己的 Kismet。

产物照旧只进 `.private`；提取器、生成器、运行时进公开仓。

## 背景与已测得的事实

原版每章是一个常驻关卡加几十个流式包。包的粒度比分段细：同一路段的几何、美术、远景
（`_Bac`）、建筑外壳（`_Building`）、灯（`_Lgts`）各是一个包，各自进出。关卡设计依赖
“这两个包从不同时加载”：远景外壳立在下一段走廊的位置上，等走廊要加载时外壳已经卸掉。

本项目把全部包一次性实例化，于是：

- sp07 追逐段走廊被一块墙板堵死。它是 `boat_cont_art` 的 `S_SP07_BoatBDInterior_01`，
  只属于开头的检查点；走廊属于 `boat_chase`，只属于后段。原版里两者从不共存。
- 多个场景异常地暗：从不共存的外壳叠在一起，挡住了阳光。
- README 记录过的 Escape St1 外壳盖住 R1 走廊，当时靠 `collision_overrides` 手工绕开。

spike（分支 `spike/me-package-presence`）验证了：按包隐藏并移出物理空间，上述问题消失。
spike 只用检查点快照切换，时机不对——前方路段要摸到下一个检查点才出现。本设计补上时机。

对全部 10 章常驻关卡及其子包的普查：

| 对象 | 事实 |
|---|---|
| `LevelStreamingVolume` | 全部 `bDisabled`，编辑器遗留，不驱动任何东西 |
| `SeqAct_StreamingZone`（121 个） | **没有任何东西触发它**，设计期账本，忽略 |
| `SeqAct_MultiLevelStreaming`（约 150 个） | 真正的驱动。输入 `Load` / `Unload`，属性 `Levels` 是包列表，输出 `Finished` |
| `SeqAct_LevelStreaming`（sp08 子包里 3 个） | 同上，单个包 |
| `TdCheckpoint.StreamingLevels` | 从该检查点读档时加载的包，即该处的世界快照 |

典型形态只有一种：`触碰 → Unload 一批 → Finished → Load 下一批`，先卸后装。
流式动作的根事件：

| 根事件 | 数量 | 位置 |
|---|---|---|
| `SeqEvent_Touch` / `SeqEvent_TdTouch`，发起者 `Trigger` / `TdTriggerVolume` / `TriggerVolume` | 约 95 | 多在常驻关卡 |
| `SeqEvent_TdUsed`，发起者 `TdTrigger` / `TdTrigger_Dynamic` | 27 | 全在子包，经远程事件传回 |
| `SeqEvt_TdCheckpointLoaded` | 15 | 读档路径 |
| `SeqEvent_TakeDamage`（sp05）、`SeqEvt_TdPlayerDeath`（sp01b）、`SeqEvent_SequenceActivated`（sp02） | 11 | 子包 |

路径上经过的节点：`SeqAct_DisableLoadFromLastCheckpoint` 100、远程事件 76、
`SeqAct_Switch` 47、`SeqAct_Delay` 38、`SeqAct_Interp` 36、`SeqAct_Gate` 23，其余零星。

远程事件的发送者可能在配置未列出的包里：sp08 的 `Remove_sluice_interior` 由
`Convoy_SB01_Mus`（音乐包）发出。只扫描配置里的包会把这些步骤判成“无人触发”。

## 范围

**做：**
- 提取器沿 Kismet 图把每个流式动作拍平成“流式步骤”，连同检查点快照写进 manifest。
- 生成器给每个节点标上所属包；BSP 与遮挡体按包拆分；流式触发体随章节几何生成。
- 运行时按快照与步骤维护在场集合；不在场的包隐藏并移出物理空间。
- 外壳场景里的体积（空气墙、阻挡、死亡、伤害体积等）同样按包切换。
- 调试显示。
- 全部开了 `split_sections` 的章节按新流程重建。

**不做：**
- 真正的加载/卸载（不在场的包不占内存、后台线程加载、分帧实例化）。在场集合的接口
  为它留位：将来只替换“隐藏/显示”这一处。
- `Gate` / `Switch` 的状态模拟（见下）。
- 音频、音乐、本地化包的流式（`_Aud` / `_Mus` / `_Loc_`）：它们没有几何。
  但它们的 Kismet 要读，因为几何步骤的触发链会穿过它们。
- 未开 `split_sections` 的单场景关卡：全部包常驻，行为不变。
- 把后几章尚未转换的原版电梯配置成 `Lift`。它们现在不能运转、卡住流程，那是各章
  `lifts` 配置的活，与本设计正交：未配置的电梯，其按钮的步骤走 `UseZone` 加路径延迟，
  在场集合照常切换；配置之后自动改由 `doors_closed` 触发，无需再动这里。

## 流式步骤

拍平的产物，一条记录对应“一个根事件到一个流式动作的一条路径”：

```jsonc
{
  "source": {                       // 根事件
    "kind": "touch",                // touch | used | checkpoint_loaded | damage
    "package": "Convoy_p.me1",
    "trigger": { "name": "Trigger_18", "class": "Trigger", "position": [...],
                 "radius": 1.5, "height": 1.5 }   // 或 hull + basis，同 level_end
  },
  "delay": 0.0,                     // 路径上累计的秒数
  "order": 0,                       // 同一根事件下的先后：Finished 链的深度
  "op": "unload",                   // load | unload
  "packages": ["convoy_snipe", "convoy_snipe_art", ...],   // 小写、无扩展名
  "through": ["SeqAct_Gate"]        // 路径上未模拟的节点类；空表示路径是干净的
}
```

**向上走的规则**（`streaming.py`，与 `matinee.level_end_links` 同一套链路读取）：

- 起点是每个 `SeqAct_MultiLevelStreaming` / `SeqAct_LevelStreaming`，被激活的输入下标
  决定 `op`。
- 上游是另一个流式动作的 `Finished`：继续向上，`order + 1`。同一根事件的步骤按
  `order` 执行，于是“先卸后装”的次序得以保留。
- `SeqAct_Delay`：`delay += Duration`（`Duration` 有随机范围时取均值，同 `_delay_seconds`）。
- `SeqAct_Interp`：只有从 `Completed` 输出走出来的路径才 `delay += 过场长度 / PlayRate`；
  从 `Out` 走出来的不加。原版“按下电梯按钮 → 关门动画播完 → 卸载身后”的等待
  就是这样编码的，照此累加，身后的路不会在门关上之前消失。
- `SeqEvent_RemoteEvent`：到**章节目录下全部包**里找同名的 `SeqAct_ActivateRemoteEvent`，
  逐个继续向上。名字比较不区分大小写。无人发送的记入报告 `streaming.unsent`。
- `SeqAct_Gate` / `SeqAct_Switch` 及其它未识别的动作：穿过（对 Gate 只穿过 `In`，
  不穿过 `Open` / `Close` / `Toggle`，同 `level_end`），类名记入 `through`。
- 到达事件即停。发起者不是关卡里的 Actor 的事件（`SequenceActivated`、`PlayerDeath`、
  `LevelLoaded` 等）不产生步骤，记入报告 `streaming.unhandled_roots`。
- 走到没有上游的动作：记入报告 `streaming.dead_ends`。
- 深度上限与 `LEVEL_END_WALK_DEPTH` 同值；已访问集合防环。

**为什么不模拟 Gate / Switch：** Load 与 Unload 对在场集合是幂等的，多触发一次通常
无害；而模拟需要在 Godot 里实现这些节点的完整语义和初始状态。`through` 让每条不干净
的路径可查：某处加载错了，先看报告里它是不是穿过了 Gate。哪条路径确实出了错，
再决定要不要模拟，那是另一次设计。

**根事件的种类：**

| `kind` | 来源 | 运行时 |
|---|---|---|
| `touch` | `SeqEvent_Touch` / `SeqEvent_TdTouch` 的发起者 | `Area3D`，玩家进入即触发 |
| `used` | `SeqEvent_TdUsed` 的发起者 | `UseZone`：停留满 `dwell` 才触发，离开清零。本项目没有“使用”键，电梯已是这个约定 |
| `damage` | `SeqEvent_TakeDamage` 的发起者（sp05 的可破坏物） | 同 `used`：按发起者的包围盒建 `UseZone`。本项目没有射击 |
| `checkpoint_loaded` | `SeqEvt_TdCheckpointLoaded` | 不建触发体。读档时在场集合直接取快照，见下 |

`used` 的触发体若落在某部已配置电梯（配置 `lifts`）的轿厢内部或其呼叫区内，则不另建
`UseZone`，该步骤改由电梯“门已关上”的时刻触发：`Lift` 新增信号 `doors_closed`，
在 `CLOSING → MOVING` 时发出。此时步骤自身的 `delay` 记为 0——电梯的关门时间已经
替代了原版的关门过场。

## 检查点快照

`manifest["checkpoints"][i]["streaming"]`：该检查点 `StreamingLevels` 引用的
`LevelStreaming*` 对象的 `PackageName`，小写。spike 已实现。

`SeqAct_DisableLoadFromLastCheckpoint` 在路径上出现 100 次，它是存档系统的开关，
与在场集合无关，按普通动作穿过，但**不**记入 `through`。

## 包的键

一律小写、去掉 `.me1`：`convoy_roof-conv_slc`。原版自己的拼写大小写不一
（`Convoy_Roof-Conv_slc_lgts`），不能按原样比较。Python 侧 `streaming.package_key()`，
GDScript 侧 `MeLevelCommon.package_key()`，是同一条规则的两份实现。

**一个包是否受流式管辖：** 它出现在任意快照或任意步骤里。其余的包（章节总包、
配置 `packages` 里手工追加的）常驻，永不隐藏。

## manifest 与报告

```jsonc
"streaming": {
  "steps": [ ... ],
  "managed": ["convoy_roof", ...]      // 受管辖的包，排序
}
```

报告 `report["streaming"]`：步骤数、按 `kind` 计数、`through` 非空的步骤数及其类名计数、
`unsent`、`unhandled_roots`、`dead_ends`。

`manifest["checkpoints"][i]["streaming"]` 已在上文。

## 生成器

- 每个摆放节点、每盏灯：`set_meta("me_package", key)`。
- BSP：每个包一个 `StaticBody3D`，各带标记。不在场的包的 BSP 不能挡路。
- 遮挡体：每个包一个 `OccluderInstance3D`，各带标记。不在场的包的遮挡体不能剔除
  它后面的东西。
- 章节几何（`<id>_geometry.scn`，每次重建）携带：
  - 元数据 `me_streaming`：`{snapshots: {检查点标签: [键]}, start: 标签, managed: [键]}`。
    `start` 是配置的 `initial_spawn`，否则是 `DefaultCheckpoint`。
  - 节点 `StreamingTriggers`：每个不同的根事件触发体一个子节点（`Area3D` 或 `UseZone`，
    脚本 `streaming_trigger.gd` / 复用 `use_zone.gd`），其上 `steps` 是该根事件的步骤，
    已按 `order` 排好。形状的建法与 `LevelEnds` 相同（圆柱或凸包）。
- 步骤和触发体随章节几何走，不进外壳：外壳是手改过的，几何每次重建。

## 外壳里的体积

空气墙、阻挡体积、死亡体积、伤害体积、铁丝网、玻璃在分段外壳 `.tscn` 里，
由 `shell_builder.gd` 从 manifest 的标注生成，标注带 `package`。

- 新生成的外壳：生成时直接打 `me_package` 标记。
- 已存在的外壳：`build_level.gd` 新增一步 `--stamp-packages`，载入外壳，把带标注来源的
  节点按“节点名 + 位置”对上 manifest 的标注，打标记，原地保存。对不上的逐条报告，
  不猜。这一步只写元数据，不动任何手改过的属性。
- 检查点、出生点、`LevelEnds` 不受管辖。

## 运行时

`scripts/level/package_presence.gd`（spike 的同名文件重写）：

- `SectionLoader` 实例化全部分段后，若章节几何带 `me_streaming`，则建立
  `PackagePresence`，把全场景树里带 `me_package` 的节点按键索引一次。
- **在场集合**的状态只有一个：`present: Dictionary`（键 → true）。
  - 玩家的 `active_checkpoint` 变化为“读档”（重生、调试跳转、关卡开始）时：
    `present = 该检查点的快照`。走着碰到检查点**不**重置——那时步骤已经把世界
    带到了正确的状态，快照只是读档用的。区分办法：监听 `Arena` 的重生，而不是轮询
    检查点。
  - 触发体触发：按 `order` 依次、各自等够 `delay` 后，`load` 把键加入、`unload` 把键移出。
    重生时取消所有在途的延迟步骤。
  - 每次集合变化后，只对**变化了的键**应用显示/隐藏。
- **不在场** = `visible = false` + `process_mode = DISABLED`（`CollisionObject3D` 以
  从物理空间移除来响应）。不受管辖的键永远在场。
- 灯由 `me_lights.gd` 分批点亮，它也写 `visible`。暖机结束后再应用一次。
- 触发体一次性：触发过的不再触发，重生时复位（加入 `Arena.RESET_ON_RESPAWN`）。

将来做真正的加载/卸载时，替换的只有“应用到节点”这一个函数。

## 调试

- HUD 一行：在场包数 / 受管辖包数，最近触发的根事件名。
- F3 触发体显示里画出流式触发体，与其它触发体同一套画法。
- `[presence]` 日志：每次集合变化打印加了什么、减了什么、由谁触发。

## 验证

`verify_level.gd` 新增：

- 每个检查点脚下地板所属的包在它自己的快照里（配置 `floating_checkpoints` 里的除外）。
- 每个步骤的每个键都是某个已建节点的键，或属于没有几何的包（`_aud` / `_mus`）；
  拼写错了的键会在这里现形。
- 快照之间的差集被步骤覆盖：按检查点顺序，后一个快照比前一个多出的键必须出现在某个
  `load` 步骤里，少掉的键必须出现在某个 `unload` 步骤里。这是弱性质——manifest 里没有
  玩家的路线，无法验证“哪个步骤在哪两个检查点之间触发”——但它能指出缺失的步骤。
  覆盖不了的键逐条报告：它们要么来自 `unhandled_roots`，要么数据如此。

公开仓测试（不依赖私仓数据）：

- 拍平算法：手工构造的小图——直连、`Finished` 链、`Delay`、`Interp` 的 `Completed` 与
  `Out`、跨包远程事件、Gate 的 `In` 与 `Open`、环。Python，与 `test_annotations.py` 同一种跑法。
- `PackagePresence`：重生后集合等于快照；`unload` 后节点隐藏且不在物理空间；
  同一根事件下步骤按 `order` 执行；重生取消在途步骤；不受管辖的键不被隐藏。
- `package_key` 两份实现对同一组输入给出相同结果（输入表写在两边的测试里）。

人进游戏：sp07 从头跑到追逐段走廊，sp08 从头跑到 Conv，确认前方按时出现、身后按时消失、
电梯关门前身后不消失。

## 未核实、需在实现中确认

- `SeqEvent_TdTouch` 与 `SeqEvent_Touch` 是否都只认玩家。步骤触发体只认玩家，
  若原版某个流式触发体是给 AI 或载具碰的，会表现为“永远不触发”，验证的差集覆盖会指出来。
- sp08 `atrium_3`（权重 0，站在风管上）脚下的包不在它的快照里。先看是不是地板判错了，
  再决定是否进 `floating_checkpoints`。
- `--stamp-packages` 按“名 + 位置”能对上多少手改过的体积。被拖动过的体积位置已变，
  只能靠名字；同名的靠最近距离。对不上的数量决定这一步是否够用。
- `Interp` 从 `Completed` 走出的路径里，过场长度是否总是可读（`matinee.py` 已有读法）。
