# 跑酷动画包购物调研

调研时间：2026-08-26。目标：给 Godot 4.7 第一人称跑酷游戏（镜之边缘 like）补齐动画缺口。预算基准 ~$30（对标已购的 Quaternius UAL），上限 ~$60（覆盖特别好可以放宽）。

**关于价格的重要提醒**：本机 Chrome 被地理定位到香港，MoCap Online 的商品页会自动切换成 HKD 计价但仍显示 "$" 符号（例如 Ninja 包页面明确显示 "Hong Kong SAR (HKD $)"，Pro 档「$1,114」实为约 143 美元）。本报告中标注"（浏览器抓取，请核实币种）"的价格请在结账页确认币种为 USD 后再下单；标注"（WebFetch 抓取）"的价格与官方公开的美元定价吻合，可信度较高。Fab.com 未发现明显的货币切换入口，价格按 USD 处理，但仍建议下单前最后确认。

---

## 一、覆盖矩阵速查表

优先级缺口：wall run L/R、wall climb（贴墙竖直攀爬）、wall kick/跳墙、vault 变体（speed/safety/lazy）、combat roll/着地翻滚、slide（起/循环/收）、ladder 上下循环+扶梯手部姿势、hang/shimmy、mantle/多高度爬上、balance beam、jump 变体、软硬着地、180 转身。

| 候选 | 价格 | wall run | wall climb | wall kick | vault | roll | slide | ladder | hang/shimmy | mantle | beam | jump变体 | 落地 | 180转身 | 格式/骨架 | 引擎限制 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| MoCap Online - Ladder Climbing | $29.99 | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | FBX/多引擎，MotusMan骨架 | 无 |
| Mixamo（免费） | $0 | ✓ | ✓ | ✓ | 弱(仅1个) | ✓ | ✓ | ✓ | ✓✓ | 部分(braced hang to crouch) | ✗ | ✓ | ✓ | 未验证 | FBX，Mixamo骨架 | 无 |
| Quaternius UAL2（免费/随喜） | $0起 | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | 部分(CLIMB_UP_1M) | ✗ | ✗ | ✗ | ✗ | FBX/GLB/Blend，Godot官方导出 | 无(CC0) |
| Fab - Free Animation Library | $0（个人档） | ✗ | ✓✓(11个) | ✗ | 弱(1个) | 弱(1个) | 弱(1个) | ✓(3个) | ✗ | ✓(2个) | ✗ | ✗ | ✗ | ✗ | UE-only(需从UE导出FBX) | 需Fab标准许可(可) |
| Reallusion ActorCore - Parkour | $77.40(促销)/$129 | ✗ | ✓ | ✗ | ✓✓(safety/speed/两手) | ✓ | ✗ | ✗ | ✗ | ✓ | ✗ | 未验证 | 未验证 | ✗ | FBX/BVH，导出预设含Unity/UE | 无 |
| Fab - Urban Freerun Pro | $78.28 | ✓✓ | ✓✓ | ✓✓(TicTac) | ✓(BarVault) | 部分(Landing含roll) | ✓ | ✗ | ✓(BarMovement) | ✗ | ✗ | 未验证 | ✓ | ✗ | **UE-only无FBX** | Fab标准许可(可) |
| Fab - Action Adventure Parkour and Vaulting | $274.19起 | 未确认(列表被截断) | ✓✓✓(clamber多高度) | ✗ | ✓✓✓(多高度) | 部分 | ✓✓(start/loop/end) | ✗ | 部分(zipline) | ✓✓✓ | ✓(pivot to balancebeam) | ✓ | ✓✓ | ✗ | FBX + UE，root motion+in-place | Fab标准许可(可) |
| Fab - Climbing and Vaulting Animations | $117.46 | ✗ | ✓ | ✗ | ✓(多高度) | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | 未验证 | ✓ | ✗ | **UE-only无FBX** | Fab标准许可(可) |
| Fab - Parkour Animations (QwertNikol) | $470.09 | ✓✓ | ✓ | ✗ | ✓✓✓(10+变体) | ✓✓(dive roll等) | 部分(Slide_Vault) | ✗ | ✓(Ledge_Move) | ✓✓(Ledge_ClimbUp) | ✗ | ✓✓ | ✓✓ | ✓(Rotate180) | **UE-only无FBX** | Fab标准许可(可) |
| Fab - All-IN-ONE PARKOUR | $156.64起 | ✓ | ✓(Wall Attach) | ✓ | ✓(monkey/rollover/sprint) | ✗ | ✓ | ✗ | ✓(Ledge) | ✗ | ✗ | ✓(4种+2循环) | 未验证 | ✗ | **UE-only无FBX** | Fab标准许可(可) |
| Unity - Parkour (Free Running), RvR Gaming | $14.99 | ✗ | ✓(climb) | ✗ | ✓(fence/big vault) | ✓ | ✓ | ✗ | ✗ | ✓(step up) | ✗ | ✓ | ✗ | ✗ | 格式未验证(疑似Unity .anim非原始FBX) | 标准EULA，可用于其他引擎 |
| Unity - Parkour pack, FGDeveloper | $24.50 | 未验证 | 未验证 | 未验证 | 未验证 | 未验证 | 未验证 | 未验证 | 未验证 | 未验证 | 未验证 | 未验证 | 未验证 | 未验证 | 未验证 | 标准EULA，可用于其他引擎 |

（✓✓/✓✓✓ 表示该项覆盖尤其扎实；"未验证"表示商店页未展示足够信息确认。）

---

## 二、逐项详情

### 2.1 MoCap Online — Ladder Climbing Animations（首选，预算内）
- 链接：https://mocaponline.com/products/ladder
- 价格：**$29.99**（WebFetch 抓取，与官方常见定价吻合，可信）
- 内容：198+ 动画，覆盖 3 种真实梯子间距标准（OSHA 12"、ISO 230mm、ISO 400mm），含上/下爬、上梯/下梯、跳下、掉落、待机、小动作、倒放过渡；描述明确提到"mounting/dismounting"（即扶梯手部姿势）。
- 格式：FBX、BIP、Unreal、Unity、Blender、iClone；MotusMan v55 骨架（人形，可走 Godot BoneMap 重定向）。
- Root motion：官方页面写明"included as Root Motion and In-Place"。
- 许可：Standard License，"covers personal, indie, and commercial use up to 1M end users / $1M revenue. Royalty-free, perpetual."——商用无引擎限制，Godot 可用。
- 结论：精准命中梯子这一单项缺口，格式和许可都干净，价格也压线预算基准，**直接推荐购买**。

### 2.2 Reallusion ActorCore — Parkour（值得考虑的加量项）
- 链接：https://www.reallusion.com/ContentStore/iClone/pack/3D-Animation-Parkour/default.html
- 价格：**$77.40**（列表价 $129，页面显示"40% OFF"促销至 2026-08-31；浏览器抓取，非HKD问题，Reallusion站点本身按USD计价）——超出$60上限约$17。
- 内容：45 个专业动作捕捉动作，官方描述明确覆盖：wall climb（贴墙攀爬+drop+roll）、多种 vault（safety vault 新手向、speed vault 进阶保速、两手 vault 等）、combat roll、以及 front/back/side flip 等花式动作（nice-to-have）。动作可模块化拼接（sprint→vault→roll 之类的链式动作）。
- 格式：FBX 或 BVH 导出，官方标注兼容 Unity、Unreal、3ds Max、Maya、Blender、MotionBuilder，即通用人形骨架，Godot 可重定向。
- 许可：ActorCore 标准许可为一次性付费、royalty-free、可用于商业游戏（"full ownership and usage rights to... sell and redistribute those creations for use in commercial games"，来源：搜索结果转述自 Reallusion 官方 FAQ/EULA 页面，未能直接抓取 EULA 原文全文，**建议购买前自行打开 https://actorcore.reallusion.com/eula 核对一次**，因为部分 Reallusion 内容对"海量分发"游戏有额外的 mass distribution license 要求，需确认独立游戏体量是否触发该条款）。
- 结论：专业动捕质感明显好于大多数 Fab 独立开发者包，覆盖 vault/wall climb/roll 都扎实，但没有 slide、ladder、balance beam、180 转身。价格超预算上限但差距不大（$17），如果作者愿意为"专业质感"加钱，这是目前**性价比最高的超预算选项**。

### 2.3 Fab.com 专类跑酷包（普遍严重超预算）
Fab 上搜索 "parkour animations" / "freerun" / "vault animations" 能找到多个专门的跑酷包，但价格集中在 **$78 ~ $470**，全部远超预算上限；且除了 Motionbeats Studio 的一个包外，**其余全部只提供"虚幻引擎"格式，不含独立 FBX**（UE-project-only 发行方式）。作者有 UE 可以导出，但这是额外步骤，务必单独评估是否值得。

- **Urban Freerun Pro**（Wolff's Studio）https://www.fab.com/listings/e2157a3d-4032-45b1-86ed-3542efc1ccf0 —— $78.28，86个动画，8个文件夹：Bar Movement / Bar Vault / Landing / Slide / TicTac / WallClimb / WallJump / WallMovement。覆盖面和本项目缺口高度重合（wall run、wall climb、wall kick、vault、slide 全中），**但只有 UE 格式，无 FBX**，页面"包含格式"一栏仅显示虚幻引擎图标。
- **Action Adventure Parkour and Vaulting Animation Pack**（Motionbeats Studio）https://www.fab.com/listings/f6db4c87-6fd5-48c6-a874-b1d617e95a89 —— **个人许可 $274.19 / 专业许可 $822.73**（点开许可下拉确认，个人档定义为"过去12个月收入或资金不超过10万美元的个人创作者或小团队"）。80个动作捕捉动画，clamber(=mantle) 6种高度(50/80/100/120/150/200cm)、vault 多种高度和入口方向、slide 起/循环/收、balance beam（Relaxed_pivot90_to_balancebeam系列，**是本次调研唯一找到的balance beam覆盖**）、zipline。**明确标注 FBX included + root motion与in-place双版本**，是本次调研里格式最规范的付费包，可惜价格是预算的4~14倍。
- **Climbing and Vaulting Animations**（DeadPixelLabs）https://www.fab.com/listings/2b49b949-4d2a-4927-bcf2-8d2edf48c61e —— $117.46，围绕一个 Climb & Vaulting 组件的配套动画，覆盖不同高度/速度的墙、栏杆、栅栏。**只有UE格式**。
- **Parkour Animations**（QwertNikol）https://www.fab.com/listings/fdc9b1bb-c8f9-437c-b1ef-625fac9ad0cb —— $470.09，250+动画，是本次调研覆盖面最广的单包：wall run（4种）、ledge/mantle（30个ledge动画+多种ClimbUp变体）、vault（超过10种细分：safety/speed/thief/monkey/kong/kong360/dive roll等）、180转身（Rotate180_L/R）、landing roll、slide（作为vault的一个变体 Slide_L/R_Vault）。**唯独没有梯子和balance beam**。价格是预算的近16倍，**只有UE格式**，作为"如果预算完全不设限该买什么"的参考项列在这里，不建议购买。
- **All-IN-ONE PARKOUR**（FiftyFive Gaming Studio）https://www.fab.com/listings/9018f998-dd97-4e16-a8b3-b0900405b70f —— $156.64~195.82，覆盖 wall run/wall attach(含climb up/down/hanging)/8方向贴墙移动/vault(monkey/rollover/sprint)/slide/ledge grab。**只有UE格式**。评分偏低(3.8/5，4个评价)。

### 2.4 Unity Asset Store（便宜但内容/格式存疑）
已确认关键法律问题：**Unity Asset Store 的 Standard EULA 允许把资源用在其他引擎里**（Unity 官方支持文档明确写道："Unity Asset Store assets are not restricted to Unity projects. You can use them with other engines provided you follow the EULA guidelines."），限制主要是不能把原始文件当作可下载资源再分发、不能让购买成本被多人分摊使用。这解除了"Unity包能不能用在Godot"的顾虑，但要注意区分"Standard"和个别"Restricted"授权的包（本次未遇到 Restricted 类型的跑酷包）。

- **Parkour (Free Running) Animations**（RvR Gaming）https://assetstore.unity.com/packages/3d/animations/parkour-free-running-animations-168090 —— **$14.99**。页面文案称面向 Assassin's Creed 式写实跑酷，含 idle/walk/run、vault(围栏型和大跨越型)、slide、jump、roll、step up、swing、climb。**未能确认包内是否附原始 FBX**（Unity 动画包常见做法是只提供 .anim clip，需要在 Unity 里另存/转出 FBX，多一道转换工序）——购买前建议先看"Package Content"标签页核实。
- **Parkour pack**（FGDeveloper）https://assetstore.unity.com/packages/3d/animations/parkour-pack-168592 —— $24.50。页面加载不全，动画清单和格式细节**未验证**，只确认标准EULA、Single Entity License、124.8MB。
- **Heroic Traversal**（Unity论坛发布，200+动作，wall run/ledge traversal/ledge swing/wall climb）——**当前售价未验证**，社区帖子未显示具体数字，需要作者自行在 Asset Store 搜索确认是否仍在架上及现价。

### 2.5 Reallusion 之外的其他来源
- **itch.io**：专门搜索"parkour"标签后，找到的付费跑酷包多为 2D 像素风格（例如 Kainshiro 的 Basic Vault/Climbing Animation Pack $2.49，实为2D精灵图，不适用于3D第一人称项目，已排除）。MoCap Online 在 itch.io 上转卖的 Climbing Ladder Animation Pack 标价 **$49.99**，比官网直接购买（$29.99，见2.1）贵，**应从 mocaponline.com 官网下单而非 itch.io 转卖页**。

---

## 三、免费层（优先尝试，零成本先把能覆盖的填上）

### 3.1 Mixamo（Adobe，完全免费）
无需登录即可浏览/预览，下载需要免费 Adobe 账号。经关键词搜索确认的相关动画（人形骨架，FBX 导出，可走 Godot 重定向）：

- **wall run**：`Wall Run`(跑上墙到平台)、`Wall Run`(墙跑到跳跃姿势)、`Diagonal Wall Run`(斜向墙跑接跳跃) —— 覆盖尚可，但只找到统称"Wall Run"，未明确区分左右版本，需要在动画编辑器里镜像左右。
- **wall climb/kick**：`Climbing Up Wall`、`Climbing Down Wall`、`Sprint To Wall Climb`、`Jump From Wall`(扒墙起跳)、`Run To Flip`(跑动跳墙翻越)。
- **vault**：只有 `Vault Over Box` 一个，**覆盖很弱**，不含 speed/safety/lazy 等细分变体。
- **roll/落地**：`Falling To Roll`(两个版本)、`Quick Roll To Run`、`Sprinting Forward Roll`、`Hard Landing`、`Falling To Landing`、`Falling Idle`。
- **slide**：`Running Slide`(跑动接滑铲接回跑)、`Sprint To Backslide`。
- **ladder**：`Climbing Ladder`、`Start Climbing Ladder`、`Climbing`(单步爬梯)、`Climbing`(双步爬梯)、`Climbing To Top`——共5个，覆盖上/下、单双步节奏。
- **hang/shimmy**（这块 Mixamo 库存意外丰富，"hang"关键词有265条结果）：`Hanging Idle`(多种：扒墙/扒边缘/晃动)、`Braced Hang`系列(撑墙悬挂)、`Free Hang`系列(自由悬挂)、`Left/Right Shimmy`、`Braced Hang Shimmy`(左右)、`Hang Hop`(左右移位)、`Hang Drop`、`Jump To Hang`、`Braced Hang To Crouch`(**可当 mantle 用**：从悬挂直接爬上蹲姿)。
- **swing on bar**（nice-to-have）：`Swinging`(单手/双手)、`Start Swinging`、`Run And Swing`、`Rope Swinging`。
- **crouched locomotion**（nice-to-have）：`Crouched To Sprinting`。
- **未找到**：`mantle`/`balance`/`180`/`slide`/`roll` 作为独立关键词搜索均**零结果**（说明 Mixamo 内部标签系统对这几个词不敏感，但上面列出的同义描述实际存在，靠"parkour"这个大标签搜出来的）。
- 许可：官方明确"free, no licensing or royalty fees, for unlimited commercial or non commercial use"，不能把原始动画文件本身当资源包再分发/上架，其余商用无限制，Godot 使用无问题。

结论：Mixamo 免费库存意外地是本次调研里**综合覆盖面前三、且零成本**的选项，wall run/wall climb/ladder/hang shimmy/roll/slide/jump/landing 都有对应条目，主要短板是 vault 几乎空白、无 balance beam、无 mantle 专用词条（可用 hang-to-crouch 替代）、180转身未确认。建议作为**基础层**，配合下面的付费包补 vault 和梯子细节。

### 3.2 Quaternius Universal Animation Library 2（随喜付费，CC0）
- 链接：https://quaternius.itch.io/universal-animation-library-2 ／ https://quaternius.com/packs/universalanimationlibrary2.html
- 价格：Pay-what-you-want，**可以 $0 下载**；60-70% 内容免费，源文件（.blend）走随喜付费。
- 与已购的 UAL 第一代同一作者，是延续包，130+ 动画，官方描述包含"parkour movement"，但实际可确认的跑酷相关词条只有：`SLIDE`、`SLIDE_LOOP`、`CLIMB_UP_1M`，以及几个 ninja 主题的跳/斩/旋转动作（更偏战斗花活，不算严格跑酷）。
- 格式：FBX、GLB、Blend 源文件；官方**明确测试过 Godot 导出**，人形骨架且"compatible with other common rigs (Mixamo for example)"。v2.0 更新后locomotion类动画带 Root Motion 和无 Root Motion 两版本。
- 许可：**CC0**（等同公共领域），免费用于个人/教育/商业项目，是本次调研里许可条款最干净的选项。
- 结论：覆盖面比 Mixamo 窄很多，但因为是 CC0 + 官方 Godot 导出保证，摩擦最小，**值得顺手下载**，主要贡献 slide start/loop 和一个 mantle 替代动作。

### 3.3 Fab.com — Free Animation Library（voxel vision，免费个人档）
- 链接：https://www.fab.com/listings/481ef75b-892b-424f-a213-f1cc058c9c19
- 价格：许可下拉显示"从 **免费** 到 $78.28"，个人档为 $0。
- 内容：从作者多个付费包里精选的动画合集，跑酷相关：Wall Climbing 11个、Ledge Climb 6个、Pipe Climb 3个（水管，nice-to-have）、Ladder Climb 3个、Mantle 2个、Vault 1个、Slide 1个、Roll 1个。
- 格式：**只有虚幻引擎格式，无独立FBX**——要用到 Godot 需要作者自己在 UE 里把动画序列导出成 FBX（UE 本身支持导出 Skeletal Mesh 动画为 FBX，是可行但额外的步骤）。
- 许可：Fab 标准许可，个人免费档同样适用商用条款。
- 结论：如果作者愿意接受"在UE里转一道FBX"的摩擦，这是**免费**拿到 wall climb(11个之多)、ladder(3个)、mantle(2个) 的途径，性价比很高；如果嫌麻烦可以跳过，靠 Mixamo+Quaternius 已经覆盖同类内容的大头。

---

## 四、许可与格式的通用结论

1. **Fab.com Standard License**：官方原文"use is not limited to Unreal Engine"，本次遇到的所有 Fab 包均为标准许可（未遇到限制性许可），Godot 商用无障碍。**但格式是另一回事**——多数 Fab 独立开发者上传的跑酷动画包只打包了 UE 工程格式，不含裸 FBX，这是本次调研最大的意外发现，务必在"包含格式"一栏确认是否有 fbx 图标（只有 Motionbeats Studio 的 Action Adventure Parkour 系列明确带 FBX）。
2. **Unity Asset Store Standard EULA**：官方支持文档确认可用于非Unity引擎，限制是不能把原始资源再分发/共享购买成本。但 Unity 包同样存在"是否含裸FBX"的不确定性，需要在下单前查看 Package Content。
3. **MoCap Online**：自营站点销售，明确标注多格式（含FBX）+ Standard License（商用+版税全免，1M用户/100万美元营收以下），是本次所有来源里格式和许可最透明的一家。
4. **Reallusion ActorCore**：官方FAQ/EULA摘要显示商用游戏可以合法使用，但完整EULA条文本次未能逐字抓取核实（页面加载为空），建议购买前自行打开EULA页确认是否有"大规模分发需额外授权"的门槛。
5. **Mixamo**：Adobe 官方免费商用授权，条款清晰，唯一限制是不能把动画原始文件当作可下载资源包再次分发。

---

## 五、推荐购物车

### 方案A：紧贴预算基准（~$30-45，稳妥）
| 项目 | 价格 | 理由 |
|---|---|---|
| MoCap Online - Ladder Climbing Animations | $29.99 | 唯一预算内、格式/许可都干净的梯子专项包 |
| Unity - Parkour (Free Running), RvR Gaming | $14.99 | 便宜补充 vault/slide/roll/climb 的第二来源，但购买前务必核实是否含原始FBX |
| **小计** | **$44.98** | |
| + Mixamo（免费下载） | $0 | wall run/wall climb/hang-shimmy/ladder/roll/slide/jump/landing 基础层 |
| + Quaternius UAL2（免费下载） | $0 | slide start/loop、mantle替代动作，CC0最干净 |

### 方案B：放宽到~$60-80（追加专业质感）
在方案A基础上追加：
| 项目 | 价格 | 理由 |
|---|---|---|
| Reallusion ActorCore - Parkour | $77.40（促销价，截至2026-08-31，需自行核实是否仍在架） | 专业动捕质感的 vault(safety/speed/两手)/wall climb/roll，明显高于独立开发者UE包的动作质量 |
| **方案B总计** | **约 $122.38** | |

若只能二选一加购，**优先选 A 方案里的 MCO Ladder（刚需梯子）**，Unity RvR Gaming 包因格式未完全验证，建议先去 Asset Store 详情页确认 Package Content 里有无 .fbx 文件再决定是否下单；ActorCore 是"锦上添花"项，超预算但差距可接受。

### 未能在预算内解决的缺口
- **Balance beam**：本次调研唯一覆盖它的是 Fab 的 Action Adventure Parkour and Vaulting Animation Pack（$274.19起），远超预算。建议先用现有 walk/idle 动画临时拼凑，或后续单独评估这个包是否值得为了一个动作花$274。
- **180 转身**：只在 QwertNikol 的 $470 UE-only包里明确看到（Rotate180_L/R）。这类转身动画在几乎所有通用locomotion包（包括作者已有的 Quaternius UAL1、MoCap Online Mobility系列）里大概率也有等价物，建议先翻查已购资源，不必为此单独购买跑酷专包。
- **Vault 细分变体（speed/safety/lazy）**：预算内最佳答案是 ActorCore（方案B），预算内(A方案)只能靠 Mixamo 的单一 `Vault Over Box` 和 Unity RvR Gaming 包的"围栏/大跨越"两种凑合。

---

## 六、结论排序（性价比从高到低）

1. **MoCap Online - Ladder Climbing Animations（$29.99）**——预算内刚需缺口的最优解，格式/许可最干净。
2. **Mixamo（免费）**——零成本情况下覆盖面最广的基础层，wall run/climb/hang-shimmy/ladder/roll/slide/jump 都有真实存在的对应动画，唯独 vault 和 balance beam 缺失。
3. **Quaternius Universal Animation Library 2（免费/随喜）**——许可最干净（CC0）、官方保证Godot导出，作为已购UAL的延续顺手拿。
4. **Reallusion ActorCore - Parkour（$77.40促销价）**——超预算上限但幅度可接受，vault/wall climb/roll 的专业动捕质量明显优于独立开发者的Fab UE包，值得作为"加购项"考虑。
5. **Unity - Parkour (Free Running), RvR Gaming（$14.99）**——预算内的补充选项，但格式（是否含裸FBX）需下单前自行核实，不确定性较大，故排在ActorCore之后。
6. 其余 Fab.com 专类跑酷包（$78~$470）——覆盖面通常很好（尤其 QwertNikol 的 $470 包近乎覆盖了整个优先清单），但价格是预算的3~16倍，且多数只提供 UE 工程格式、需要额外导出步骤，仅作为"预算完全放开时"的参考，不建议现阶段购买。
