# 14 · 信使视觉：LOI

← [README](README.md) · 上一篇 [13-生命值与伤害](13-生命值与伤害.md)

玩家管它叫 Runner Vision，游戏自己不这么叫。红色那套在引擎里的名字是 **LOI**，而
`RunnerVision` 是另一半——玩家开关与敌人高亮。两者分属不同的包，混为一谈会找错地方。

---

## 14.1 两套东西，别搞混

| | 在哪 | 管什么 |
| --- | --- | --- |
| **LOI** | `Engine.u` | 世界物件上的那层红：谁会红、什么时候红、怎么淡入淡出 |
| **RunnerVision** | `TdGame.u` | 玩家侧的开关、以及敌人身上的高亮 |

✅ LOI 在 `Engine.u` 而不是 `TdGame.u`——DICE 把它做进了引擎层，`StaticMeshActor`
这种引擎自带类的**类默认值里就带着 LOI 字段**。这不是游戏脚本往上贴的一层。

`TdGame.u` 那半边的符号：`bUseRunnerVision`、`SetRunnerVisionEnabled`、
`UpdateRunnerVision`、`bPawnRunnerVision`、`bIsRunnerVisionEnabled`、
`IsAiRunnerVisionEnabled`，以及一个独立的 `TdAI_RunnerVisionEffect`——**敌人的高亮
和世界的红走的是两条路**。`TdGameInfo` 的 CDO 里 `bEnableLOI = True`，那就是设置
菜单里的那个开关。

---

## 14.2 标记在 actor 身上

✅ 从 `Engine.u` 的类默认值读出，`StaticMeshActor` / `InterpActor` / `KActor` /
`SkeletalMeshActor` 都有：

| 字段 | 默认值 | 含义 |
| --- | --- | --- |
| `bLOIObject` | false | 这个物件参与信使视觉 |
| `LOIDistance` | 1500 uu = **15 m** | 多近才亮 |
| `LOIMinDuration` | 1.5 s | 亮起来之后至少保持这么久 |
| `LOIProximityDelay` | — | 进入范围后等多久才亮（关卡里见到 1.0 / 3.0） |
| `LOILookAtDelay` | −1（关闭） | 看着它多久才亮（关卡里见到 0.2） |
| `LOIUse2DDistance` | false | 算距离时忽略高度差 |
| `LOIDirection` | (0, 1, 0) | 从哪一侧看过去才算数 |
| `LOIGroups` | 空 | 组名，Kismet 可以整组点亮 |

⚠️ `LOIDirection` 的具体语义（朝向锥的半角是多少、是否与 `LOILookAtDelay` 联动）
没有验证，只是从命名和用法推断。

干活的是 `TdLOIAddOnObject`（按 actor 类型分出 `TdLOIAddOnStaticMeshActor` 等四个
子类），外加一个 `TdLOIGroupManager`。它的节奏写在 `TdGame/Config/DefaultLOI.ini`
里，整份文件只有三行：

```ini
[Engine.TdLOIAddOnObject]
FadeInSpeed=1.0f;
FadeOutSpeed=4.0f;
```

✅ **亮得慢、灭得快**——淡入 1.0/s，淡出 4.0/s，差四倍。CDO 里还有
`MinDuration = 0.5`。Kismet 侧是 `SeqAct_ActivateLOI` 与 `SeqAct_DeactivateLOI`，
各自带着同样的两个速度。

---

## 14.3 红色是材质参数，不是后处理

✅ `bLOIObject` 的物件持有 `LOIMaterialInstances` 数组，由 `InitLOIMtrlInstances`
在初始化时建立——**每个物件为自己的材质做一份材质实例，然后动它的参数**。材质那边
暴露两个参数：

- `LOI_Color`，默认 **(1.5, 0, 0)**——超过 1 的红，故意打爆
- `LOI_Strength`，0..1，就是淡入淡出动的那个值

`M_Line` 是最干净的例子，它的表达式图是：

```
DiffuseColor  = lerp(0.005, LOI_Color + 0.005, LOI_Strength)
EmissiveColor = LOI_Strength × DiffuseColor × 0.1
```

所以一条没亮的信使视觉线**本身就是近黑色**（0.005），亮起来不只是变红，还会微微
自发光。

> 📌 本项目的材质烘焙里，`M_Line` 这类材质烘出来是 0.005 的近黑色——那不是 bug，
> 是 `LOI_Strength = 0` 的静止状态。要红，就得在运行时驱动这个参数。

---

## 14.4 关卡里的规模：全是手工标的

统计自各章的 cooked 包，`bLOIObject = True` 的 actor：

| 章节 | 标记数 | 章节 | 标记数 |
| --- | ---: | --- | ---: |
| sp00 教程 | 94 | sp05 商场 | 127 |
| sp01a 序章 | 59 | sp06 工厂 | 98 |
| sp01b 逃脱 | 28 | sp07 货船 | 54 |
| sp02 排水渠 | 255 | sp08 车队 | 91 |
| sp03 吊车 | 213 | sp09 摩天楼 | 108 |
| sp04 地铁 | 141 | **合计** | **1268** |

`LOIGroups` 的组名把制作过程暴露得很彻底：`balance walk`、`slide planks`、
`Plaza_Ladder`、`bosspipes`，也有 `stupidpipesthatwontwork`、`ziiiiiiip`、
`sluice pipessssss`。⚠️ 由此推断：**这是逐个物件手工标注的，没有自动化**——命名
风格、拼写和重复程度都不像工具生成的产物。少数章节出现 `LOI_Roof_Pipes_02` 这类
规整命名，说明约定存在过但没贯彻。

`LOIDistance` 的分布也全是手调：0（取 15 m 默认）到 10670 uu（107 m）都有，广场
对面才看得见的东西给了大距离。

---

## 14.5 移到本项目要做什么

这套东西可以整体照搬，因为它的数据就在我们已经解析的包里：

1. **提取**：`bLOIObject` 和它那几个字段是 actor 的 tagged property，和碰撞类别一样
   读出来放进 manifest。
2. **材质**：烘焙时保留 `LOI_Color`，并把 `LOI_Strength` 做成运行时可动的参数——
   目前它被当成常量 0 烘死了，红色无从谈起。
3. **运行时**：一个管理器按距离 / 朝向 / 延迟决定谁该亮，用 1.0 与 4.0 的速度驱动
   材质参数。分组点亮对应 Kismet 的两个 SeqAct。

🔶 **推导**：淡出比淡入快四倍这件事值得照抄。信使视觉要在你**跑过去之前**给出提示，
又不能在你已经做出决定之后还挂在屏幕上——慢进快出正是这个意思。
