# 跟着 mover 走的体积：致命箱、报信箱、震动圆柱、车头灯

原作把「一列疾驰而过、撞上就死的地铁」拆成了四件挂在车头上的东西，没有一件是车本身。
本设计让提取器读出这种挂接关系，让生成的关卡把这些体积送上车，并补齐它们落地所需的
运行时通道（致命、音效、镜头震动、车头灯）。

产物照旧只进 `.private`；提取器、生成器、运行时节点、CC0 音效进公开仓。

## 背景与已测得的事实

第一目标是第五章商场（SP05）开场段 `Mall_HW_Spt.me1` 里的两列地铁。

### 列车本体

| 项 | 值 | 依据 |
|---|---|---|
| 编组 | 车头 `InterpActor_3` / `InterpActor_21`，各拖 3 节 `bHardAttach` 车厢 | `[ME:CONFIRMED]` |
| 车厢间距 | 22.72 m，全长约 91 m | `[ME:CONFIRMED]` |
| 网格 | `S_Subwaytrain_01a`（首尾）/ `01b`（中间） | `[ME:CONFIRMED]` |
| 碰撞类 | `none` —— 车体是纯视觉件，撞不到 | `[ME:CONFIRMED]` |
| 行程 | 键长 17.3333 s，`PlayRate 1.5`，位移 588.28 m | `[ME:CONFIRMED]` |
| 实际速度 | 588.28 / (17.3333 / 1.5) = **50.9 m/s** | `[ME:DERIVED]` |
| 循环 | `Completed` → `SeqAct_Delay`（`Duration` 接 `SeqVar_RandomFloat` 5.0~10.0）→ 自身重播 | `[ME:CONFIRMED]` |
| 行驶音 | `SeqAct_Interp` 的 `soundon` / `soundoff` 输出接 `subway`，淡入 1.0 s、淡出 2.0 s | `[ME:CONFIRMED]` |

两列方向相反，各自独立随机，所以间隔不同步。

### 挂在车头上的四件东西

`Base` 指向车头且 `bHardAttach` 为真（车灯例外，见下）。

| actor | 形状 | 相对车头 | Kismet 走向 |
|---|---|---|---|
| `DynamicTriggerVolume_4` / `_7` | 盒 4.16 × 4.64 × **92.72** m | 罩住整列四节车 | `SeqAct_TdPlayerFail` + `Death_Train`；另一条 Touch 走 `SeqAct_CauseDamage` 1000 点，类型 `TdDmgType_Fell` |
| `DynamicTriggerVolume_6` / `_8` | 盒 4.16 × 4.16 × 47.84 m | actor 在车头前 **48 m** | `SeqAct_RandomSwitch`（`LinkCount 2`）→ `Horn_Short` 或 `Horn_Long` |
| `Trigger_16` / `_17` | 圆柱 r = 28.52 m，h = 9.81 m | 车头附近 6.6 m | `SeqAct_ForceFeedback` + `SeqAct_TdCameraShake`；一条 `SeqAct_Delay`（2.0 s）触发震动的停止输入 |
| `LensFlareSource` ×2 | —— | 前 11.52 m，左右 ±1.28 m，高 +1.92 m | 车头灯光晕 |

震动参数：`Amplitude 1500.0`，`Frequency 0.003`（1 号车）/ `0.005`（2 号车）。
`[ME:UNKNOWN]` 这两个数的单位。**两列车 0.005 / 0.003 的比值是有意义的，绝对值不是** ——
落到本项目时经 `CameraConfig` 的旋钮换算，不去推导。

死法走 `TdDmgType_Fell`：`[ME:CONFIRMED]` 被列车撞死和摔死是同一种死法，不是专门的撞击死亡。

### 这个模式的覆盖面

扫全部 9 个章节，硬挂在 Matinee 驱动 actor 上的体积共 **40 个 `DynamicTriggerVolume`、
265 个 `Trigger`、1 个 `DynamicBlockingVolume`**，分布在 SP01a、SP01b、SP02、SP03、SP04、
SP05、SP06、SP08、SP09。第四章地铁有 5 列车（`Train_Spt`、`Plat_Spt` ×2、`Tunnel_Spt` ×2），
每列同样是「致命箱 + 报信箱」两件；第九章电梯井、第六章追逐段用的是同一套挂接，但都不是车。

**所以这不是「列车」，是「挂在 mover 上的体积」。** 造一个原作没有的 `Train` 概念，
等于在该给旋钮的地方加规则（`.claude/skills/tuning-dials-not-rules`）。

### 本项目现状的两个缺口

`.private/.../sp05_mall_hw.tscn` 里的 `Mall_HW_Spt_me1_7853` 节点证实：

1. 四节车厢已经会跟着 Matinee 一起动（`pivots` 机制管用），**但两个体积一个都没上车** ——
   `annotations.py` 的 `VOLUME_KINDS` 里没有 `DynamicTriggerVolume`，
   `Base` / `bHardAttach` 只在 `collect_placements()` 里读，标注从不带这个字段。
2. `followers` 的 `delay` 是 **1.0**（`SeqVar_RandomFloat` 没被读），而且这个 Matinee
   **只有自己当自己的 follower，没有任何东西启动它** —— 现在这两列车根本不会动。

## 范围

**做：**

- 提取器：标注读 `Base` / `bHardAttach`；`DynamicTriggerVolume` 和骑乘的 `Trigger`、
  `LensFlareSource` 纳入提取；窄读这些体积的 Kismet 去向（致命 / 音效 / 震动）。
- 提取器：`SeqAct_Delay` 读 `SeqVar_RandomFloat`；matinee 的纯自循环标 `autostart`；
  读 `SeqAct_Interp` 的 `soundon` / `soundoff`。
- 生成器：把这些体积注册成 Matinee 的 target，复用现有 `pivots`。
- 运行时：新增 `EffectVolume`；`Matinee` 支持自启、随机间隔、行驶循环音；
  `CameraRig` 新增震动通道；新增 `Headlight`。
- 会移动的音源开多普勒。Godot 原生支持，代价只是两个开关。
- 公开仓收一批 CC0 音效，四个槽：`horn_short`、`horn_long`、`death_train`、`subway_roll`。
- `verify_level.gd` 新增一条：带 `base` 的体积必须是某个 Matinee 的 target。

**不做：**

- 通用 Kismet 复现。只认上表四种结局，其余照现有惯例计入 report 后跳过。
- 手柄震动（`SeqAct_ForceFeedback`）。本项目没有手柄通道。
- 从原作提取音频。音效另找 CC0 素材。
- 车体碰撞。原作的车体碰撞类就是 `none`，致命完全由体积负责，照抄。
- 环境音床与粒子特效。两者都已量过规模，见文末「后续」，各自另起设计。

## 设计

### 一、提取器

#### `annotations.py`

`VOLUME_KINDS` 新增 `'DynamicTriggerVolume': 'effect'`。kind 叫 `effect` 而不是按类名叫，
因为**它是什么由 Kismet 决定，不由类名决定** —— 同一个类既做致命箱也做鸣笛箱。

新增 rider 扫描：一个标注若能沿 `Base` 上溯（**至多 4 跳**，因为体积可能挂在车厢上、
车厢再挂车头）到达某个 actor，就带上 `base`（终点的 `package.name`）和 `hard`
（`bHardAttach` 是否为真）。

**`LensFlareSource` 的 `bHardAttach` 是空的**，所以 rider 扫描接受「有 `Base` 但没
`bHardAttach`」的情况。按类白名单收：volume 类、`Trigger`、`LensFlareSource`；
不收 `PathNode` 一类。

#### `matinee.py`

新增 `rider_effects(packages, mr)`：对每个 Originator 是骑乘体积的
`SeqEvent_Touch` / `SeqEvent_TdTouch`，向下走（穿过 `SeqAct_RandomSwitch`、
`SeqAct_Gate`、`SeqAct_Switch`），只记四种结局：

| 走到 | 记成 |
|---|---|
| `SeqAct_TdPlayerFail` 或 `SeqAct_CauseDamage` | `kill` |
| `SeqAct_TdPlaySound` | `sound: {choices: [name...], fade_in, fade_out}`；上游有 `RandomSwitch` 就是多选一 |
| `SeqAct_TdCameraShake` | `shake: {amplitude, frequency, hold}`，`hold` 取触发其停止输入的 `Delay` 时长 |
| 其他 | report 计数，跳过 |

同时补三处：

- `SeqAct_Delay` 的 `Duration` 若接了 `SeqVar_RandomFloat`，读出 `Min` / `Max`，
  沿用到 `starts[].delay_min` / `delay_max`（震动的 `hold` 同理）。
- matinee 新增 `autostart`：当全部 starts 都是 `after` 且 source 都是它自己时置真。
  **口径刻意收窄** —— 只认纯自循环。一个由别的包发来的 RemoteEvent 启动的序列不在此列，
  因为提取器本来就不跟踪跨包远程事件，猜它等于编故事。
- `SeqAct_Interp` 的 `soundon` / `soundoff` 输出 → matinee 的 `sound: {name, fade_in, fade_out}`。

#### `packages.py`

`CONFIG_DEFAULTS` 新增 `sounds`（默认 `{}`）：原作音效名 → `res://` 路径的映射。
放在关卡配置里而不是新开文件，因为原作的名字本来就只能待在 `.private`。

### 二、生成器

`shell_builder.gd` 现在的 `riders` 映射只从 `manifest["placements"]` 建。改动：

1. 先建 `DeathVolumes`、新的 `EffectVolumes`、新的 `Headlights` 三组节点，
   过程中记下 `annotation id → NodePath`。
2. 把这张表交给 `_matinees()`，与现有 mesh rider 合并进同一个 `riders` 字典，
   走**同一条 `pivots` 路径**。

运行时 `Matinee._apply()` 一行不用改 —— 它移动的是 `Node3D`，不关心那是网格还是 `Area3D`。

`kind` 为 `effect` 的标注按 `rider_effects` 的结果分流：带 `kill` 的建成 `DeathVolume`，
带 `sound` 或 `shake` 的建成 `EffectVolume`。**原作的致命箱两样都带**（撞上既死又播
`Death_Train`），这种情况下**建两个节点共用同一个 hull**，各做各的一件事。

不要把音效字段加到 `DeathVolume` 上。它的源码注释写明「它一个设置都没有，
这就是它接口的全部」，那句话是它能被随便丢在任何致命处的原因；开了这个口子，
下一个会是震动，再下一个是延迟。

体积的形状看来源：`DynamicTriggerVolume` 走 `BrushComponent` 的 hull，
`Trigger` 走 `CylinderComponent` 的半径与半高（`_matinee_trigger()` 已经在这么读了）。

音效映射查不到就**不建音源、不报错**：公开仓在没有私仓的情况下必须照样能跑，
这是现有的底线，音频不该成为第一个例外。

### 三、运行时

#### `scripts/level/effect_volume.gd`（新）

`Area3D`。exports 即接口，没有别的开关：

- `sounds: Array[String]` —— `res://` 路径，多于一条就随机挑一条
- `shake_amplitude` / `shake_frequency` / `shake_hold`

碰到玩家（鸭子类型，与 `DeathVolume` 同一立场）就在自身位置播一条一次性
`AudioStreamPlayer3D`，并向镜头要一次震动。

音源开 `doppler_tracking = DOPPLER_TRACKING_PHYSICS_STEP`。**相机那一侧也要开**，
否则只有音源动时才有多普勒，玩家跑向静止音源时没有 —— 这是 Godot 里两个独立的开关，
只开一个是常见的半成品状态。

#### `Matinee`

- `followers` 条目支持 `delay_min` / `delay_max`，**每圈重摇**。恒定间隔的列车会让
  这一段读起来像节拍器，原作特意没这么做。
- 新增 `autostart`：`_ready()` 里起播。`reset_for_respawn()` 之后也要重新起播，
  否则死一次列车就再也不来了。
- 新增行驶循环音：一个跟着首个 target 的 `AudioStreamPlayer3D`，起播时按 `fade_in`
  淡入、跑完按 `fade_out` 淡出，同样开多普勒 —— 一列 50.9 m/s 的车驶过，音高该变。

#### `CameraRig`

新增一条震动通道：`add_shake(amplitude, frequency, hold)`，在 `update_effects()` 里
作为附加位移叠加，**缓出而非硬切**。

原作的 `1500.0` / `0.003` 按 `[ME:CONFIRMED]` 原样进配置，经 `CameraConfig` 两个新旋钮
（`shake_amplitude_scale`、`shake_frequency_scale`）换算成米和 Hz。单位不明就给旋钮，
不去推导 —— 这是 `.claude/skills/tuning-dials-not-rules` 的正例。

这是关卡在动眼睛，不是玩家在动，按 `docs/camera-authority.md` 该平滑该滞后。

#### `scripts/level/headlight.gd`（新，很小）

`OmniLight3D` + 一片 additive、unlit 的 billboard。位置是量出来的，亮度和尺寸是旋钮。

### 四、音效

`assets/audio/` + `LICENSE.txt`，照搬 `assets/animations/` 的做法，`NOTICE.md` 加一段。

**优先 CC0**；实在只有 CC BY 才用，并在 `NOTICE.md` 落来源与许可。**SA 和 NC 一律不收** ——
本仓库是 AGPL-3.0-only 加商用双授权，ShareAlike 会和商用授权打架，NonCommercial
连 AGPL 这一侧都过不去（`NOTICE.md` 已有这段推理）。

**判据是听感，不是型号。** 找不到火车鸣笛就用卡车鸣笛，听着对就行 —— 这里要的是
「身后有个大家伙要来了」这个信息，不是声学考据。

配置里的映射表**以原作的 cue 名为键**（`Horn_Short` → `res://assets/audio/...`）。
这不是为本期方便，是为了后面那 46 种环境音床能沿用同一张表，不必重新设计接缝。

## 测试

数值不写断言（`.claude/skills/tuning-dials-not-rules`）：震动幅度、灯光亮度、音量
都是会频繁调且改坏了一眼可见的东西。写结构性不变量：

- `tests/test_matinee_riders.gd`：手搓一个 `Matinee` 加一个挂接的 `Area3D`，验证
  它跟着走、`reset_for_respawn()` 后回位且重新起播、`autostart` 会自启、
  随机间隔落在 `[delay_min, delay_max]` 内。
- `verify_level.gd` 新增一条闸：**每个带 `base` 的体积都必须是某个 Matinee 的 target**。
  漏掉就是「一个致命箱子杵在轨道上不动」—— 正好是当前这个 bug 的形态，这条挡它复发。
- 提取器侧沿用 `test_annotations.py` 的无素材回归风格，对 `Base` 上溯链做一条纯数据测试。

## 分期

每期独立可验：

1. **提取器**：标注读 `base`、收 `DynamicTriggerVolume`、`rider_effects` 窄读、
   随机 `Delay`、`autostart`、`soundon`/`soundoff`。验收：重跑 SP05 提取，
   manifest 里两个箱子带上正确的 `base` 和 effects。
2. **上车**：生成器把体积注册成 Matinee target；`Matinee` 自启与随机间隔；
   `verify_level.gd` 新闸。验收：进 Mall HW 段，列车会开、撞上会死。
3. **EffectVolume 与镜头震动**：`EffectVolume`、`CameraRig` 震动通道与两个旋钮。
   验收：车经过时镜头抖，两列车的抖法不同。
4. **音效与车头灯**：CC0 素材入库、映射表、`Headlight`。
   验收：远处先听见鸣笛、看见车灯，再看见车。

## 后续（不在本设计内，规模已量过）

两件事在调查途中被量出了规模，都比本设计大，各自该另起一份。记在这里是为了
**不让它们悄悄爬进这一份**。

### 环境音床

全部 11 章共 **6,991 个 `AmbientSound` 摆放，但只有 46 种 cue**，且前 20 种覆盖 95% 以上：
`A_Prop_FanLarge200`（1,062）、`A_Prop_ACSmallRattle`（1,014）、`A_Prop_AirVentRattle`（524）、
`A_Prop_AirValve`（524）、`A_Prop_ACAiry`（521）……几乎全是风机、通风口、空调、变压器的嗡鸣。

**好消息**：约 20 条 CC0 循环音就能铺满全游戏的环境层。
**难点**：单章约 600 个音源，Godot 不可能同时挂 600 个 `AudioStreamPlayer3D` 都在响 ——
需要一套按距离择近启用的发声体系。那是这件事的真正内容，不是找素材。

Kismet 播放的一次性音效另有 498 种名字，但长尾极长，且大半是枪械与语音（本项目两样都没有）。
真正用得上的集中在门、电梯、玻璃、鸽子几类，而这些机制本项目**已经有了**
（`BreakableGlass`、`Lift`、门的 Matinee），所以是「给已有机制配音」，不是新系统。

### 粒子与动态材质

全部章节共 **21,228 个 Emitter 摆放，261 种粒子模板**。可辨认的大头是
`PS_FX_LevelFX_Smoke_VentSmoke_*`（通风口白烟）、`PS_FX_LevelFX_Sparks_SmallSparksDirected_01`
（定向小火花，即铁轨下那种）、`PS_FX_FlyingTrash_Random_01`（飞舞的垃圾）、
`PS_FX_LevelFX_Water_*Dripping*`（滴水）。

动态材质另计：`MaterialExpressionPanner` 3,170 个、`MaterialExpressionTime` 2,210 个、
`MaterialExpressionRotator` 1,257 个，遍布 12 个章节 —— 第二章的瀑布水流是这一类，
不是粒子，是**材质在滚 UV**。

现有的 `materials.py` 只求值到 `DiffuseColor` 和 `Opacity` 的静态部分，
把 Panner 当常量。要做动的，得让材质烘焙保留一条时间轴，这是材质管线的改动，
与粒子是两件独立的事。
