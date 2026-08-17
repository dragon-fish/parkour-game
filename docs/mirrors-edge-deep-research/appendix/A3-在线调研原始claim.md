# 在线调研原始 claim 汇总（99 条去重后）

## C00  [supporting / primary]

存在一场 GDC 2009 的 DICE 一手开发者演讲《Creating First Person Movement for MIRROR'S EDGE》，主讲人是 Jonas Åberg 与 Tobias Dahl（DICE - EA），归类在 Visual Arts track；但该 session 的正文/视频在 GDC Vault 上需付费会员，本次抓取只拿到元数据，没有任何数值参数或设计论述。研究问题第 9 项常被假设的 Tom Farrer 并非此场演讲的署名讲者。

- 原文: > **Title:** Creating First Person Movement for MIRROR'S EDGE — **Speakers:** Jonas Aberg, Tobias Dahl — **Company:** DICE - EA — **Date/Year:** GDC 2009 — **Track:** Visual Arts … **Content Status:** This session is paywalled.

## C01  [supporting / secondary]

DICE 制作人 Nick Channon 明确表示：第一人称在《镜之边缘》中不是「类型选择」而是设计手段，其目的是传达游戏的流动感与动量（flow and momentum），并建立玩家与 Faith 的连接——这是关于「为什么这么设计」的开发者一手说明。

- 原文: > Channon explained how the studio was motivated to use the first person perspective in Mirror's Edge not as a genre, but simply as a design choice that communicates the game's flow and momentum

## C02  [central / secondary]

DICE 的原始设计目标被表述为「做一个完全关于移动的游戏」，且设定为都市环境；即移动系统本身（而非射击/战斗）是该作的设计核心。

- 原文: > we wanted to create something quite urban, and we wanted to create a game that was all about movement

## C03  [supporting / secondary]

DICE 主动拒绝第三人称视角，理由是第三人称会让玩家「观看 Faith」而非「成为 Faith」，官方类比是「置身于动作电影中，而不是玩一部动作电影」。

- 原文: > as soon as you get to third person, you would be watching Faith, whereas we want you to be connected to her. The analogy we give is 'being in an action movie, instead of playing it,'

## C04  [supporting / secondary]

游戏中玩家对 Faith 身体的可见性是通过反射与影子等间接方式实现的（而非第三人称镜头），这是被开发者明确认定为增强代入感的设计要素。

- 原文: > We think it's really cool, the way you get glimpses of Faith in the game world: You see her in reflections, you see her in shadow, and I think that gives a really nice feel to the game.

## C05  [tangential / secondary]

叙事过场不使用引擎内第三人称演出，而刻意采用 2D 卡通动画风格呈现 Faith，以避免破坏第一人称的连接感。

- 原文: > Obviously, in the storytelling we do, you see Faith, but we actually show her in a different way, so it's 2D, more cartoon animation.

## C06  [central / forum]

社区实测给出了一组以「游戏内速度单位」表示的相对速度基准：普通冲刺(sprint)上限约 26，coil boost（蜷腿跳+顺滑落地）可把速度推到约 30，而进入 coil boost 的门槛速度约为 20。这说明镜之边缘存在明确的「基础冲刺上限」与「技巧突破上限」两层速度天花板。

- 原文: > When your speed is around 20 (the more the better), do a coil-jump with a smooth landing … seems to max at 30 vs 26 for sprinting.

## C07  [central / forum]

Wall-run 结束时（跳离墙面或让 wall-run 自然结束）落地瞬间会立刻获得大幅动量提升，通常直接拉满到最大冲刺速度；该 wiki 将其称为游戏中最快的通用移动方式。

- 原文: > Wall-run and jump off (you can also just let the wall-run finish a lot of the time) while going straight and your momentum instantly boosts a lot when you land, to the maximum sprint speed a lot of the time.

## C08  [central / forum]

Skill roll 的损速并非无条件发生——只有在翻滚后继续向前移动才会掉速；同时 skill roll 提供的初始加速上限约为 24（低于 coil boost 的 30），且该数值作者自承未必测到极限。

- 原文: > You only lose momentum from a skill roll if you move forwards after … the initial boost seems to max at 24, but I may not have did it fast enough yet.

## C09  [central / forum]

存在「3-step Rule」：跳跃落地后必须先直行约 3 步再开始转向，否则转向会造成掉速。该规则由 PC 版玩家发现，主机版行为可能不同（即转向损速与落地后的时间窗口耦合）。

- 原文: > To not lose speed from turning in jumps you need to move around 3 steps after landing and then start turning, that was discovered for the PC version and may be different on Consoles.

## C10  [supporting / forum]

平衡木（balance beam）上的再次起跳存在极窄的帧窗口，且标准跳与 coil 技巧的时机不同，需要极高精度——说明游戏内多处动作衔接依赖帧级输入窗口而非宽容缓冲。

- 原文: > very small frame window where you can jump again

## C11  [supporting / primary]

DICE 有意识地把枪械/射击从核心玩法中移除，以确保玩家把《镜之边缘》读作「身体移动」游戏而非 FPS——这是移动系统成为唯一核心机制的设计前提（一手开发者说明，对应研究子问题 9「为什么这么设计」）。

- 原文: > if you give somebody a weapon straight out of the box, then they think it's a shooter. There is weapon combat in the game -- you can snatch weapons and use them -- but it's really not the focus. The focus is on the physical human being.

## C12  [supporting / primary]

移除枪械是开发中途做出的决定，此后团队再无「射击玩法」作为退路，被迫把移动机制本身做到能独立支撑整个游戏——说明移动系统的深度是被这一决策倒逼出来的。

- 原文: > Once we decided we were taking out the gun, then it was like, 'OK, so now we really have to make this work. We can't fall back.'

## C13  [supporting / primary]

「Runner Vision」（红色可交互物体）的显式设计目标是让玩家能以跑酷者的速度即时读解环境，且其强度可按玩家技能等级上下调节，而非固定的路径指引——这是把「高速移动下的可读性」工程化的感知层机制（对应子问题 10）。

- 原文: > We want the player to be able to move quickly through the world, and read the world as quickly as a runner would be able to read it.

## C14  [tangential / primary]

游戏刻意取消传统 HUD（包括血条），理由是世界本身承载了导航信息、且健康状态通过画面表现即可判读并自动回复——即信息呈现被移入世界与镜头表现，而非叠加 UI。

- 原文: > we've got a lot of stuff in the world that tells you the information you need to know, like where to go; and you don't need a health indicator because it's very obvious how healthy you are, and your health regenerates.

## C15  [tangential / primary]

《镜之边缘》基于 Unreal Engine 3 但经过大幅定制，并与 Illuminate Labs 合作采用 Beast 光照方案（软阴影与颜色反弹）以实现其视觉风格——确认了引擎基线为 UE3（与逆向 .ini/UE3 移动参数的可行性直接相关）。

- 原文: > soft shadows, and color bouncing

## C16  [central / primary]

DICE 制作人 Nick Channon 明确将 momentum（动量）定位为《镜之边缘》的核心设计支柱，称其为「驱动玩家通关的燃料」，并把「追求更快」当作游戏的主要驱动力——这是开发者一手确认「保速/积累速度」是本作本质机制而非附属系统的直接证据（但访谈未给出任何数值参数）。

- 原文: > momentum... is like the fuel that drives you through the game; that's the most important part.

## C17  [central / primary]

第一人称视角在《镜之边缘》中被 DICE 当作「设计选择」而非类型（genre）选择，目的是让玩家与 Faith 建立连接；一旦转为第三人称，玩家就变成「观看 Faith」而非「成为 Faith」。这为「镜之边缘-like 判定标准」中「第一人称是本质而非表层」提供了开发者一手依据。

- 原文: > you're playing the game through the eyes of Faith; as soon as you get to third person, you would be watching Faith, whereas we want you to be connected to her.

## C18  [supporting / primary]

开发者描述玩家对 Faith 身体的感知主要来自「反射与影子中的一瞥」，而非持续的全身可见——说明「看得到自己的脚/身体」并非官方在此访谈中强调的机制，官方强调的是间接的自我在场感（此点与社区常说的「full-body awareness」叙事存在侧重差异）。

- 原文: > you get glimpses of Faith in the game world: You see her in reflections, you see her in shadow.

## C19  [supporting / primary]

《镜之边缘》的操作被刻意压到极简：采访者称整段 demo 只用了三个按键，且跳跃是 context sensitive（上下文敏感）的单一动作，而非依赖大量独立招式——这意味着复刻时「动作库庞大」不是本质，「少量按键 + 上下文解析」才是。

- 原文: > I was really surprised that I used literally three buttons the entire time I played the demo.

## C20  [tangential / primary]

战斗被设计为可选内容而非必需环节：游戏内存在「全程不进入战斗即通关」的成就，官方定位战斗是游戏的一部分但不是全部——支持「跑酷/移动系统优先于战斗」的系统性判定。

- 原文: > there's actually an achievement in the game, to finish it without engaging in combat.

## C21  [central / forum]

Mirror's Edge (2008) 的地面最高跑速约为 16 mph（≈7.15 m/s / ≈281 uu/s，按 1 uu≈2.54 cm 估算），而跳跃状态下速度提升至 18 mph（≈8.05 m/s）——即跳跃本身带来约 +12.5% 的水平速度增益，因此在斜坡/楼梯上连续跳跃比跑上去更快。这是社区实测（游戏内速度表读数）而非官方或逆向数值，可信度：社区共识、未经逆向验证。

- 原文: > At top speed you run at 16mph, when you jump you go to 18mph.

## C22  [central / forum]

Wall boost（贴墙跑期间把视线转向所贴的墙面并按跳跃）可使速度突破 20 mph（≈8.94 m/s），高于常规跑速 16 mph 与跳跃速度 18 mph——说明 wallrun 退出时的踢墙冲量可以叠加出超过正常速度上限的水平速度。

- 原文: > During a wallrun, look at the wall you're running on and jump. … It'll propell you at an excess of 20mph.

## C23  [central / forum]

存在 side-jump boost 技巧：侧向行走时起跳、在空中转向 90 度（转向跳跃方向），可以瞬间获得最高速度，从而绕过正常的加速曲线（无需从静止逐步加速到 top speed）。这意味着一代的速度积累机制可被空中转向的速度重定向逻辑短路。

- 原文: > Walk sideways, and press "jump". While in the air, turn 90 degrees in the direction you jumped.

## C24  [central / forum]

滑铲（slide）在一代中并不提供速度增益，反而是全游戏最慢的移动方式，唯一例外是 slide-kick（撞门/踢击）和通过低矮通风管道等无法站立通行的场景——与「slide 应有速度收益」的常见假设相反。

- 原文: > I know it looks and feels awesome, but it's the slowest thing to do in the game.

## C25  [supporting / forum]

在需要攀上高处边缘时，coil（收腿）比 speedvault 更快，即不同的越障动作有明确的时间成本差异；同理，跳踢/滑踢开门比常规推门更快，springboard 常常可以跳过而走直线更快。

- 原文: > It's faster to coil up to that high ledge than to speedvault up to it.

## C26  [central / forum]

社区实测称《镜之边缘》从静止加速到全速冲刺需要约 7–10 秒，而 "Sidestep Boost"（按住侧向移动键起跳、空中转回正面）可让玩家瞬间达到全速跑动，绕过整个加速曲线。这是关于一代加速曲线时长最直接的社区数值陈述（未经逆向验证，且 7–10 秒明显长于常规体感，可能包含冲刺蓄速阶段）。

- 原文: > Sidestep Boost: Hold left in the direction you want to go and then jump! As soon as you jump, turn back to the direction you were facing and you'll find that you are instantly at full running speed, in contrast to the 7-10 second lead up from nothing to full sprint.

## C27  [central / forum]

"Wallrun Boost" 机制：在贴墙跑时尽量正面朝向墙面（但不是直接撞墙起跳）并迅速蹬墙跳离，可获得显著速度增益——即 wallkick 的离墙冲量大小取决于玩家视角/入射朝向与墙面的关系，且该增益足以把低速状态直接拉到跑动速度以上。

- 原文: > Wallrun Boost: Whenever you are near a wall, wallrunning on it, facing it as much as you can without jumping AT it, and quickly jumping off gains significant speed. This can be used to bring you to running speed and give you slight boost.

## C28  [central / forum]

"Ventkick"：在垂直下落过程中按踢击可重置游戏记录的坠落高度计数，因此能承受更长的坠落；玩家仍会受到坠落伤害，但不会触发落地损速（动量被完整保留）。这说明一代把「坠落伤害」与「落地减速」实现为两套可分离的判定。

- 原文: > you simply kick when falling straight down ... This kick resets the height you can fall down at. You'll still take damage but it doesn't slow down your momentum which is important.

## C29  [supporting / forum]

"Halfglitch"（作者对 kickglitch 变体的称呼）：从 wallrun 蹬墙踢出后，玩家会在数帧内落在一个不可见平台上，该接触同样重置坠落高度，使玩家可以继续下落更远距离——与 ventkick 效果类似。这是踢击与碰撞检测交互产生的可复现引擎行为。

- 原文: > When you kick off of a wallrun, you end up falling (as you could imagine) but then you land on this invisible platform for a few frames. This resets your height and allows you to fall further distances, similar to a vent kick.

## C30  [central / forum]

"Drop-Roll"：玩家在平台边缘极近处完成翻滚（roll）动画后立刻掉出边缘，此操作会重置坠落高度计数，使随后的坠落距离远超正常上限。这表明 roll 的「重置下落高度」效果在 roll 动画结束时结算，而非依赖落地瞬间。

- 原文: > a Drop-Roll consist of a player rolling on one surface so closely to the edge that they fall off of it after the rolling animation is complete. This resets the players drop height and can allow them to fall a significantly larger distance than usual.

## C31  [central / forum]

speedrun.com 的 Mirror's Edge「Glitchless Tutorial」指南把 wallboost（踢墙增速）当作 glitchless 分类内合法的常规移动技术，并区分出至少三种变体：Gap Wallboost、Double Wallboost、Pole Wallboost——说明「连续多次踢墙 / 对同一结构反复 boost」在一代中是可复现的系统性机制而非 bug。

- 原文: > 7:31 - 1E Gap Wallboost 8:15 - 1E Double Wallboost ... 21:32 - 8B Pole Wallboost

## C32  [central / forum]

该指南列出名为「Kick Momentum Cancel」的技术（5B 关卡），即踢击动作会取消/清除玩家已积累的水平动量，属于一代的显式损速来源之一。

- 原文: > 15:39 - 5B Kick Momentum Cancel

## C33  [supporting / forum]

「Sliding Wallclimb」（滑铲接爬墙）是被单独列为需要教学的技术，且在多个关卡（1E、3D）复现，表明 slide 状态可以与 wallclimb 衔接并影响爬墙结果，而非两个互斥动作。

- 原文: > 3:09 - 1E Sliding Wallclimb ... 10:51 - 3D Sliding Wallclimb

## C34  [supporting / forum]

该指南本身不包含任何可量化参数（速度值、时间窗口、角度阈值），全部内容为 YouTube 视频链接与时间戳索引；因此它只能作为「术语与技术清单」的来源，不能作为数值来源。

- 原文: > https://youtu.be/wQyMw-Bq5Ic ... Timestamps ----------------------------------------------------- 0:00 - Intro

## C35  [tangential / forum]

指南中出现「Reverse Angle KG」与「Corner Turn Jump」等以入射/转向角度命名的技术，暗示一代的墙面交互与转向存在明确的角度依赖判定。

- 原文: > 1:59 - Flight Reverse Angle KG / Landing Pad Skip ... 13:30 - Subway Corner Turn Jump

## C36  [central / forum]

存在名为 "Side-Jump Boost" 的速度获取技巧：向左或右侧跳后立即把镜头转向侧跳方向，可瞬间达到最高跑速——这意味着一代的加速曲线可被输入组合绕过，速度上限可被瞬时触及而非线性积累。

- 原文: > This is a simple matter of side jumping to the right or left, turning your camera in the direction you side-jumped, and you will be instantly at top running speed.

## C37  [central / forum]

执行 wall-run kick（贴墙跑踢墙）时，Faith 脚下会生成一个持续 1-2 帧的不可见平台，时机准确即可从该平台再次起跳（"Kickglitch"），构成事实上的二段跳——给出了帧级别的时机窗口数值。

- 原文: > Whenever a wall-run kick is performed, Faith will get an invisible platform underneath her for 1-2 frames, where it is possible to, if timed correctly, jump off of said platform.

## C38  [central / forum]

从 wallrun 状态起跳离墙会获得速度增益（"Wall Boosts"），即墙面动作是净加速手段而非仅是位移手段。

- 原文: > When you wallrun and jump off of the wallrun, you gain speed and go faster.

## C39  [central / forum]

wall-run kick 会重置下落高度累积（存在一个 "cushion"），因此踢墙可用来消除坠落高度带来的硬着陆/损速判定，而不必依赖 roll。

- 原文: > When wallrunning, kick off the wall and there will be a slight 'cushion' that will reset your falling height.

## C40  [supporting / forum]

垂直直线下坠时（如从通风管落下），落地前执行 kick 可替代 roll 来规避硬着陆动画（"Fall-Break Kick"），说明落地损速的规避手段不止 roll 一种。

- 原文: > If falling in a straight line (like from out of a vent), kick before landing instead of rolling.

## C41  [central / forum]

在 Mirror's Edge Catalyst 中，wallrun 刚进入时立即起跳可以获得一次速度加成（speed boost），随后用 bunny hop 连跳可以维持该速度——即 Catalyst 的墙面动作存在「越早离墙收益越高」的时序窗口，且跳跃本身不损速、可用于速度保持。

- 原文: > Jump out of a wallrun as soon as you start it to gain a speed boost, {Bunny Hop} to maintain that speed

## C42  [central / forum]

Catalyst 的 slide 可以通过在滑铲中按 [Movement Shift Key]（PC 右键 / 主机 R2、RT）转成 roll 来退出，从而获得额外动量；即 Catalyst 把「slide→roll」做成了显式的保速衔接输入，而非一代那样依赖落地时机窗口。

- 原文: > Remember to press [Movement Shift Key], Right Click for PC and R2/RT for Console, when sliding to roll out of it for extra momentum

## C43  [supporting / forum]

Catalyst 中落在可滑行的斜面（slope）上不会触发 hard landing（硬着陆损速/受伤），除非高度达到致死级别；即坠落惩罚的判定与落点表面类型挂钩，而不只与坠落高度挂钩。

- 原文: > Landing on a slidable surface (slope) will result in no hard landings, unless you are at bone breaking heights, then yes, you will DIE

## C44  [supporting / forum]

Catalyst 的 coil（收腿）动作会使跳跃略微增高，说明 coil 在 Catalyst 中不仅是过障碍的动画，还对有效跳跃净空/高度有实际影响。

- 原文: > Coil Jumping can make your jump slightly higher

## C45  [supporting / forum]

Catalyst 的 corner wallclimb（墙角连续爬墙）依赖 quickturn 与视角朝向的配合：换墙前先把视角朝反方向（右墙换左墙时先看右）再 quickturn 起跳，成功率更高——说明 quickturn 会消耗/重定向水平动量，视角预摆是对该机制的补偿操作。

- 原文: > For easier Corner Wallclimbs, look in the opposite direction before you quickturn and jump

## C46  [central / forum]

Mirror's Edge 的最高移动速度为 26 km/h（约 16 mph，≈7.2 m/s），且可通过侧跳（side-jump，即左右横向移动时起跳）直接达到该上限；达到后若转身面向目标方向，全部动量会被保留——这是「glitchless」范畴内的速度积累手段。

- 原文: > Side-jump boost (Glitchless): If you side-jump (walk to the left or right, and jump.) you go to max speed (26km/h, and 16mph.) If you turn and face toward a location you want to go to, you will keep all of this momentum.

## C47  [central / forum]

著名的 kick-glitch 具有明确的 3 帧输入窗口：wallrun 中踢腿产生的隐形平台是实心碰撞体，玩家有 3 帧时间从该平台再次起跳，实现二段跳（也可在该平台上做 slide 或 side-jump）。

- 原文: > Kick-glitch: Probably the most infamous glitch in all of Mirror’s Edge. Going back to the wallrun-kick, that small platform is completely solid. For 3 frames, you can jump off that platform, allowing you to double-jump. Very easy to do if jump is bound to scroll wheel up/down.

## C48  [central / forum]

wallrun 途中执行单腿踢（非双腿踢）会在下落中途生成一小块实心隐形平台，落在其上可重置累计坠落距离，从而安全承受更大的总落差——说明坠落伤害/损速是按「上一次落地后的下落高度」结算的。

- 原文: > Wallrun-kick: If you wallrun, and then kick in the middle of it, you will land on a small invisible platform mid-way through the fall. This platform is solid, allowing you to reset your falling distance, and fall greater heights. Note that the kick you do needs to be the kick with 1 leg, not 2.

## C49  [supporting / forum]

在完全垂直下落过程中执行踢击（drop-kick）可使落地不判定为 heavy landing，从而无需 roll 即可免除落地损速惩罚——这是绕过落地减速机制的一个 bug 路径。

- 原文: > Drop-kick: If you kick while falling perfectly vertical, you will land and not suffer a heavy landing. This allows you to skip rolling.

## C50  [supporting / forum]

存在 wallrun-boost：极短时间的 wallrun 后、在离墙瞬间视角尽量朝向墙面起跳，会获得额外速度增益（社区已知现象，但机制原因未知/未解释）。

- 原文: > Wallrun-boost: If you wallrun, for a very short amount of time, and when you jump off are facing as close as possible to the wall, you will for whatever reason gain speed.

## C51  [central / forum]

ME1 的 roll（翻滚落地）会造成速度损失，而 Catalyst 改动了这一机制使翻滚不再减速——帖内被当作 Catalyst 相对一代的机制层改进（可通过两作实测速度曲线证伪）。

- 原文: > Rolling does not make you slow down in real life（评论者以此为由，认为 Catalyst 修正了该机制；原帖作者承认这一更正并表示会补进视频）

## C52  [central / forum]

ME1 的加速/提速手段是「side-step boost」（侧步 boost），执行时伴随风险（打断动量、掉下边缘）；Catalyst 用即时 boost 取代，去掉了该风险—回报结构，但两者速度结果相同。

- 原文: > The side-step boost in ME1 "risked someone hindering their momentum, falling of a ledge"；both mechanics "give the same results" but differ in execution difficulty

## C53  [supporting / forum]

社区认为 Catalyst 的移动系统弱化了重量与动量表现，导致角色缺乏惯性反馈（"像 UFO 一样移动"），这被归因于机制层面而非单纯观感。

- 原文: > weight and momentum were poorly handled in Catalyst / the player moves like a UFO

## C54  [central / forum]

ME1 的核心手感来自「容易丢失动量」这一高惩罚设定，Catalyst 移除了这种基于技巧的风险—回报系统。

- 原文: > I didn't like how easy it was to lose momentum but when getting more skilled at the game it is rewarding

## C55  [supporting / forum]

两作的设计取向不同：ME1 追求贴近现实的电影化体验，Catalyst 转向更游戏化/幻想化且整体移动速度更快。

- 原文: > ME1 aimed for "a cinematic experience a bit more grounded in reality"；Catalyst adopted "a more gamey and fantasy feel" with faster movement speeds

## C56  [central / primary]

Mirror's Edge Catalyst 取消了专用跳跃键，改用上下文相关的 "Up Action"（左肩键 / PC 等价键）统一处理跳跃、wallrun、wallclimb 等向上类动作——这是与一代按键映射的一处机制层差异，意味着动作选择由游戏根据情境（速度、朝向、可交互面）判定而非玩家显式指定。

- 原文: > Sometimes this contextual intent is a jump. If you're running and reach a ledge, your instinct is to jump and that's precisely what the Up Action button will do.

## C57  [central / primary]

Catalyst 新增了绑定在右扳机的 "Shift" 动作，其两项明示功能是「更快地获得速度」以及「向任意侧向乃至后方位移」——即加速曲线不再只由持续直线奔跑决定，玩家可用一个独立输入主动压缩起速时间。

- 原文: > Shift lets you move sideways in any direction, and also backwards.

## C58  [central / primary]

Shift 兼作过弯手段：玩家可先略微朝转向方向偏头再触发 Sideshift 以完成 90 度急转（drifting），且 Shift 期间角色不会从无护栏的窄边缘掉落。这说明 Catalyst 用一个显式动作替代了一代中「靠转向角度与损速惩罚自然形成的过弯节奏」。

- 原文: > turn slightly towards the turn and activate a Sideshift to make a sharper turn

## C59  [supporting / primary]

Catalyst 的 Quickturn 存在两档精度：新手按预设方向（固定 180 度式转向），高阶玩家可用鼠标或摇杆微调转向后的确切朝向——即该动作的输出方向是可连续调节的，而非纯粹的离散翻转。

- 原文: > More advanced players can however use the mouse or analogue stick to adjust the exact direction.

## C60  [supporting / primary]

该文是 EA 官方发布、由 Catalyst 首席玩法设计师（Lead Gameplay Designer）Rickard Antroia 具名讲解移动系统的一手开发者材料，但全文只作定性描述，未给出任何速度、加速度、重力、时长等可量化参数。

- 原文: > Rickard Antroia (Lead Gameplay Designer)

## C61  [central / primary]

DICE 刻意把 Mirror's Edge 的视场角(FOV)开到「开始出现画面弯曲之前」的最大值，理由是窄 FOV（举例约 40 度）会造成方位感丧失与 simulation sickness；代价是渲染负担显著增加。这是「速度感/感知层被工程化」的一手开发者说明，但访谈未给出具体 FOV 数值。

- 原文: > A couple of years ago, I was playing a first-person game, which I won't mention, which had a really narrow field of view; it was something like 40 degrees. That's really, really tight so you would lose perception of where you are in relation to everything else and that can really make you feel lost, confused and nauseous. So we opened the field of view about as far as we could before it started to bend, which is good because you get a much better sense of peripheral vision and where you are in the world and in relation to everything else. The only problem is technical. The reason a lot of game

## C62  [central / primary]

Faith 使用的是带脊椎、颈部、肩部的专门第一人称骨骼绑定（"quite a different first-person rig"），摄像机运动由身体驱动；其中一套由肩部驱动头部的运动平面因为 15 秒内即引发晕动而被推翻替换。核心设计准则是「大脑预期什么发生，就必须发生」（expected outcome and degree of control），例如坠落时画面必须晃动。

- 原文: > The biggest thing, however, is the camera control. That's related to expected outcome and degree of control. So every time your mind expects something to happen, it needs to happen. For instance, if you're falling from a height and you expect the screen to move or bob and it does, that's good and the brain is happy and you can continue playing. ... Faith's got a spine, a neck and shoulders and we had to build quite a different first-person rig to get her to do all this stuff. So we worked with her shoulders and saw how it affected her head, and we quickly found that that plane of movement woul

## C63  [supporting / primary]

落地翻滚（parachute roll）的摄像机采用芭蕾 pirouette 的「spotting」原理：动作触发后头部会甩转并最终回到与触发前相同的注视方向，这是为避免翻滚镜头致晕而专门设计的。对 Godot 复刻而言，这意味着 roll 的镜头不是自由跟随身体旋转，而是有目标朝向锁定。

- 原文: > We were also worried about the parachute roll and that it would make people sick. Then we thought about ballet dancers; when they do pirouettes, they keep snapping their head back to a certain focal point. So we worked the animation in a way that when you triggered it, she would snap around and end up looking in the same place.

## C64  [supporting / primary]

游戏刻意没有 HUD，屏幕上唯一常驻元素是准心圆点；该圆点并非刚性绑定在摄像机中心，而是「部分绑定摄像机 + 由远处一个焦点控制」，以便在摄像机大幅动画化时仍保持稳定、供玩家聚焦视线。持枪时额外叠加一个圆圈；点和圈都可分别关闭。

- 原文: > The first thing was the reticule. In most first-person games it's just attached to the centre of the camera. We quickly found out that that wouldn't work because when we started animating the camera it started moving around and being really annoying and distracting. So now, it's partly attached to the camera controlled by a focal point in the distance, which kind of steadies it out but allows it to move.

## C65  [supporting / primary]

DICE 为 Faith 的腿部开发了一整套可与环境交互的系统，但因为工期不足在发售版本中被关闭（disabled），即成品中「看得见的脚」比原设计能力弱得多。同时制作人明确表示项目从未考虑过第三人称，第一人称的目的是「感受动作」而非「观看动作」。

- 原文: > we did a lot of systems for Faith's legs, but ended up not using them because we ran out of time. So we've disabled them, which is really frustrating. There were many ways we could get her legs to move and interact with the environment which is very, very cool, but we couldn't use it so we had to just switch it off.

## C66  [central / secondary]

DICE 在开发过程中移除了《镜之边缘》早期版本中的 head bobbing（头部晃动），并将设计目标重新表述为「从你的眼睛而非你的头部看世界」——即摄像机被绑定到视线/眼球位置而非头骨的物理摆动，用以降低前庭冲突导致的模拟晕动症。这直接反驳了「镜之边缘靠强烈 head bob 制造速度感」的常见假设。（注：原文未给出任何幅度/频率数值）

- 原文: > An important change involved removing head bobbing from earlier versions. According to the developer explanation, "they are now viewing the game from your eyes and not your head."

## C67  [supporting / secondary]

屏幕中央的白色准心点（focal point reticle / 焦点圆点）是作为抗晕动症机制被有意加入的，其设计灵感来自芭蕾舞者旋转时「盯住一个固定点」(spotting) 的技巧；该点在 Reaction Time（子弹时间）蓄满时变为蓝色，且玩家可以在设置中关闭它。

- 原文: > The developers added a white dot in the center of the screen to combat simulation sickness. This element "turns blue when it's charged for the slow motion action" and helps anchor the player's visual focus. The approach was inspired by techniques ballerinas use during spins—focusing on a fixed point prevents disorientation. Players can disable this feature if desired.

## C68  [supporting / secondary]

游戏刻意利用屏幕两侧边缘区域来模拟周边视觉（peripheral vision），这是感知层设计的一部分——意味着 FOV/画面边缘的处理在设计意图上服务于「自然视觉感」，而非单纯的视野宽度参数。

- 原文: > The "use of the sides of the screens provides a sense of peripheral vision in the game," which contributes to a more natural viewing experience.

## C69  [tangential / secondary]

截至 2008 年 7 月（游戏发售前约 4 个月），DICE 尚未决定是否为 4:3 电视输出采用信箱式（letterboxed）宽屏呈现，说明当时的视野/画幅方案仍在调整中，任何早期演示中的 FOV 数据不能直接代表最终版本。

- 原文: > The team had not yet determined whether to implement letterboxed widescreen formatting for 4:3 television displays.

## C70  [central / secondary]

DICE 在 Catalyst 中有意提高了操控响应度（controls more responsive）相对于初代《镜之边缘》，这是开放世界中玩家需要在移动途中随时改变方向所倒逼的设计决策——可作为「Catalyst 手感与一代不同」的开发者一手机制层解释（转向响应/惩罚被有意削弱）。

- 原文: > What we learned was that we needed to make the controls more responsive than the first game.

## C71  [central / secondary]

Catalyst 的移动系统是「情境化（contextual）」的：物体高度直接决定玩家可执行的越障动作类型（栏杆、通风系统等各自对应固定动作），即动作选择由环境几何高度自动派生，而非玩家显式输入选择。

- 原文: > Everything of a certain height is interactable in a certain way because the movement is contextual.

## C72  [supporting / secondary]

Runner's Vision 在 Catalyst 中不是手工标注的静态红色物体，而是可随时开关的元层系统：由算法从玩家当前位置到设定目的地实时生成一条绯红路径，并沿途高亮可通行物体。

- 原文: > The second, meta-layer is a 'Runner's Vision' mode that players can switch on at any time. The game then algorithmically generates a crimson path from the player's location to wherever they've set their destination, highlighting traversable objects along the way.

## C73  [supporting / secondary]

DICE 使用环境上的物理痕迹（墙上的刮痕、脚印）标记可执行 vertical run 的位置，属于「机制可读性靠美术语言而非 UI 提示」的一手设计说明。

- 原文: > scratch marks, foot marks on walls, to show that it's a suitable place for players to do a vertical run

## C74  [supporting / secondary]

Catalyst 刻意将主角能力限制在「不超人」范围（跑、跳、楼间摆荡），拒绝 Saints Row / Prototype 式超能力移动，且所有动作必须在第一人称视角下成立——这是移动系统设计的显式边界条件。

- 原文: > Unlike the Assassin's Creed team, the designers at DICE had to make all the jumping and swinging between buildings look good in first-person.

## C75  [central / primary]

UE3 has no single fixed Unreal-Unit-to-metric ratio: Unreal Tournament titles use 1 uu = 2 cm, while "most licensees" (which would include third-party UE3 games such as Mirror's Edge) use 1 uu = 1 cm. Any conversion of reverse-engineered Mirror's Edge uu/s values to m/s therefore depends on which scale DICE adopted and must be flagged as an assumption, not a certainty.

- 原文: > In all of the Unreal Tournament games, 1 Unreal Unit is equal to 2 cm. […] Most licensees use a scale of 1 Unreal Unit to 1 cm.

## C76  [central / primary]

The specific UE3 movement/gameplay properties that must be rescaled with the unit scale are MaxStepHeight, MaxJumpHeight, MaxOutOfWaterStepHeight, CrouchHeight, CrouchRadius, GroundSpeed, AirSpeed, JumpZ and DefaultGravityZ; gravity for a given scale is configured in defaultgame.ini and these defaults live in Pawn.uc / Scout.uc subclasses — i.e. the canonical parameter names and file locations to look for in any Mirror's Edge UE3 config/package dump.

- 原文: > You'll need to change a bunch of defaultproperties in scripted and defined properties in C++, such as MaxStepHeight, MaxJumpHeight, MaxOutOfWaterStepHeight, CrouchHeight, CrouchRadius, GroundSpeed, AirSpeed, JumpZ, DefaultGravityZ, GroundSpeed, etc. […] Your defaultgame.ini file is where you can set the appropriate gravity for your scale.

## C77  [supporting / primary]

UE3's engine source hardcodes an audio distance constant of 0.0127 m per Unreal Unit (2 uu = 1 inch), showing that at least some engine-level constants are tuned to the Gears-of-War-style ~1.27 cm/uu scale rather than to 1 cm or 2 cm per uu.

- 原文: > // 2 UU == 1" // <=> 1 UU == 0.0127 m #define AUDIO_DISTANCE_FACTOR ( 0.0127f )

## C78  [supporting / primary]

Epic states that many engine constants are tuned to the default scale and recommends against deviating from it by more than a factor of 2, meaning UE3 movement behavior is not scale-invariant — a Godot reimplementation cannot simply rescale UE3-derived numbers arbitrarily and expect identical feel.

- 原文: > Many of the constants in the Unreal Engine have been tweaked to achieve good results for the current scale. As a result, deviating from this scale by a factor of 2 should be fairly straightforward, but deviating by a factor of 10 might have some subtle and hard to track down side effects. In general, Epic does not recommend changing the Unreal Unit scale by more than a factor of 2.

## C79  [supporting / primary]

Gears of War's UE3 scale is anchored by concrete reference dimensions — characters 156 uu tall and a building floor 256 uu tall, giving roughly 2 uu per inch — which provides a usable method for inferring a UE3 game's unit scale from in-game geometry when no config data is available (e.g. measuring Faith's eye height or a story height in Mirror's Edge).

- 原文: > In Gears of War approximately 2 Unreal Units equal 1 inch, because the characters are 156 units tall and a floor of a building is 256 units tall. This was decided on for grid purposes and so our cover height worked out well.

## C80  [supporting / forum]

Mirror's Edge (2008 PC) 的用户可编辑配置文件位于 Documents\EA Games\Mirror's Edge\TdGame\Config（如 TdInput.ini），而非 Steam 安装目录下的 SteamApps\Common——这是逆向/查阅 UE3 .ini 参数时的正确落点。注意：Steam 版首次运行前可能只有 DefaultInput 类文件。

- 原文: > "c/Users/YouName/Documents/EA Games/Mirror's Edge/TdGame/Config"

## C81  [supporting / forum]

游戏保留了一组可通过 ini 按键绑定触发的 UE3 控制台/作弊命令，包括 god（无敌）、jesus（免坠落伤害/水面行走）、dropme、FreeFlightCamera（自由飞行摄像机）、loadfullinventory、Leipzig——说明 ME 保留了 UE3 控制台通路，可作为运行时探测移动参数的入口。

- 原文: > `"god"` - Invincibility mode (bound to F1) … `"jesus"` - Water walking (bound to F2) … `"dropme"` … `"FreeFlightCamera"` … `"loadfullinventory"` … `"Leipzig"`

## C82  [central / forum]

该帖给出的数值出自 [Engine.PlayerInput] 段（MoveForwardSpeed=1200.0、MoveStrafeSpeed=1200.0、LookRightScale=12000.0 等），属于输入轴缩放/鼠标灵敏度参数，并非 TdPawn 的 GroundSpeed/AirSpeed/AccelRate/JumpZ；即本帖不含任何角色移动物理数值。这一点很重要：MoveForwardSpeed=1200 极易被误读为 1200 uu/s 的跑步速度。

- 原文: > The relevant section header is: `"[Engine.PlayerInput]"` … `"MoveForwardSpeed=1200.000000"` … `"MoveStrafeSpeed=1200.000000"` … `"MouseSensitivity=27.999998"`

## C83  [tangential / forum]

社区多年反馈显示这些作弊绑定在 Steam 版上大多失效，只有摄像机相关命令（FreeFlightCamera/摄像机循环）可靠工作——因此不能把该方法当作稳定的运行时参数探测手段。

- 原文: > "The camera cycle cheat seems to be working but all the others don't work" (Kvark, 21 Jun, 2016)

## C84  [central / primary]

UELib（UE Explorer 的底层库）的核心功能是反编译 UnrealScript 字节码并重建原始 UnrealScript 源码，因此可用于从《镜之边缘》的 .u/.upk 脚本包中还原移动相关类（如 TdPlayerPawn/TdPlayerController 等）的实现与默认属性——这是获取一代移动系统「逆向数据」的可行技术路径。

- 原文: > The main goal of UELib is to decompile the UnrealScript byte-code, which is achieved by reconstructing the original UnrealScript source from Unreal data classes

## C85  [central / primary]

README 的兼容性表格明确列出 Mirror's Edge 为已支持标题，包版本号 3716、licensee 版本 536/043，状态标记为完全支持（✅），即该游戏的包文件可被本库正常解析。

- 原文: > Mirrors Edge | 3716 | 536/043 | | ✅

## C86  [supporting / primary]

UELib 覆盖 Unreal Engine 1、2、3 三代引擎，可处理 .upk、.u、.uasset 等包格式，兼容性表中列有 80 余款 UE3 游戏；但表中未出现 Mirror's Edge Catalyst（其基于 Frostbite 而非 Unreal），说明二代的对照数据无法用同一逆向工具链获取。

- 原文: > Mirror's Edge Catalyst is not mentioned in the compatibility table.

## C87  [supporting / primary]

实际操作时应使用 GUI 前端 UE Explorer（UELib 以子模块形式被其引用），而非直接改动库本身；UELib 以 MIT 协议发布，允许自由使用与再分发。

- 原文: > If you're looking to modify the library for the sole purpose of modding UE Explorer consider forking UE Explorer instead (UELib is linked as a sub-module)

## C88  [supporting / primary]

README 未声明支持读取/导出 defaultproperties 或 config（.ini）值，只提及可反序列化 UFont、USound、UPalette、UTexture 等数据类，因此「从包内直接抓取 GroundSpeed/JumpZ/AccelRate 等数值」这一步在官方文档层面无明确保证，需实测验证。

- 原文: > UELib is also capable of deserializing other Unreal data classes: UFont, USound, UPalette, UTexture

## C89  [central / primary]

《镜之边缘》PC 版用户侧配置目录（Documents\EA Games\Mirror's Edge\TdGame\Config）在此存档中仅包含 TdEngine.ini 与 TdInput.ini 两个真实 .ini（外加两个 .diff），不含 TdGame.ini。因此 UE3 角色移动的核心参数（GroundSpeed / AirSpeed / AccelRate / JumpZ / AirControl / 重力）并未以 .ini 形式暴露，无法从发行版配置文件直接读取，必须从编译后的 TdGame.u UnrealScript 包反编译获取。这是研究「可量化参数」时的关键负面结论。

- 原文: > | File Name | Size (bytes) | |-----------|--------------| | TdEngine.ini | 40,787 | | TdEngine.ini.diff | 505 | | TdInput.ini | 48,537 | | TdInput.ini.diff | 1,176 |

## C90  [central / primary]

TdInput.ini 中存在 MoveForwardSpeed=1200.000000 与 MoveStrafeSpeed=1200.000000。注意：这是 UE3 PlayerInput 的输入轴缩放常数（UT3/UE3 默认值同为 1200），代表原始输入映射强度，并非角色实际地面速度（uu/s）；把它直接当作「跑步速度 1200 uu/s = 12 m/s」是常见误读，需要与 Pawn.GroundSpeed 区分。

- 原文: > MoveForwardSpeed=1200.000000 MoveStrafeSpeed=1200.000000

## C91  [supporting / primary]

发行版 TdEngine.ini 的 [Engine.GameEngine] 默认开启帧率平滑并把上限锁在 62 fps（bSmoothFrameRate=TRUE、MinSmoothedFrameRate=22、MaxSmoothedFrameRate 默认 62，该存档把它改到了 120）。这对复刻很重要：ME 的移动/跳跃行为在 UE3 下与 tick 步长相关，速通社区对高帧率下手感与数值差异的讨论有直接的配置依据。

- 原文: > **Setting changed:** `MaxSmoothedFrameRate=62` → `MaxSmoothedFrameRate=120`  **Location:** `[Engine.GameEngine]` section

## C92  [supporting / primary]

TdInput.ini 的按键绑定给出了游戏内被引擎认可的完整「动作动词」集合：跳跃=GBA_Jump（SpaceBar / 手柄 LeftShoulder）、下蹲/滑铲与翻滚=GBA_Crouch（LeftShift / LeftTrigger）、慢走=GBA_WalkMod（LeftControl，按下/松开成对）、回头看=GBA_LookBehind（Q）、子弹时间=GBA_ReactionTime（R）。即跑酷系统在输入层只有「上/下两个上下文动作键 + 走路修饰键」，没有独立的 wallrun/wallclimb/roll 键——这些全部由速度与朝向上下文推导。

- 原文: > - `"SpaceBar",Command="GBA_Jump | SkipCutscene"` - `"LeftShift",Command="GBA_Crouch"` - `"LeftControl",Command="GBA_WalkMod | OnRelease StopWalkMod"` - `"Q",Command="GBA_LookBehind"` - `"R",Command="GBA_ReactionTime"`

## C93  [supporting / primary]

TdEngine.ini 显示 DICE 关闭了 UE3 自带的运动模糊而启用了自研实现（MotionBlur=false 同时 TdMotionBlur=True），并含 CameraRotationThreshold=45.0 / CameraTranslationThreshold=10000 等相机阈值项；编辑器 FOVAngle=90.000000。这些是「速度感知层」被工程化的间接证据，但配置文件中没有暴露随速度变化的 FOV 曲线或 head bob 参数。

- 原文: > - `MotionBlur=false` - `TdMotionBlur=True` ... `FOVAngle=90.000000` (Editor setting) - `CameraRotationThreshold=45.0` - `CameraTranslationThreshold=10000`

## C94  [central / secondary]

Mirror's Edge 的 PC 版默认帧率上限为 62 FPS，且玩家物理受帧率影响：帧率升高会同时提升玩家 friction，从而改变部分移动机制的速度；超过 150 FPS 后下坡滑铲（slide）会变得极难控制。这直接说明原作移动系统是帧率相关（frame-rate dependent）的，Godot 复刻若用固定 physics tick 会产生行为差异。

- 原文: > By default, Mirror's Edge's frame rate is capped at 62 FPS. […] As frame rate increases, so does player friction which can slightly alter the speed of certain movement mechanics and make downward slides exponentially more difficult to control at frame rates above 150 FPS (i.e. Chapter 1C RP&A building slide).

## C95  [central / secondary]

游戏默认 FOV 为 90°，但在玩家死亡后会被强制改成 85°（需第三方工具 Mirror's Edge Tweaks 修正）。这是可量化的感知层参数基线，并揭示原版 FOV 处理存在 bug 而非纯粹的动态速度 FOV 曲线。

- 原文: > |fov notes                  = Defaults to 90° but gets forced to 85° upon dying. Use [[#Mirror's Edge Tweaks|Mirror's Edge Tweaks]] to fix.

## C96  [central / secondary]

游戏的 UE3 配置文件（TdEngine.ini、TdInput.ini 等）位于 %userprofile%\Documents\EA Games\Mirror's Edge\TdGame\Config\，安装目录下 <game>\TdGame\Config 也有一份；但直接修改安装目录内的 INI 会导致游戏启动失败，必须用 Mirror's Edge Tweaks 的 "Allow config mods" 补丁或 MEMLA 内存注入绕过。这是获取 GroundSpeed/AccelRate/JumpZ 一类参数时必须先解决的工程前提。

- 原文: > Some settings can be also edited in the INI files stored in {{folder|{{p|game}}\TdGame\Config|folder}}, but the game will fail to launch when modifying these files. This can be bypassed with [[#Mirror's Edge Tweaks|Mirror's Edge Tweaks]] by applying the <code>Allow config mods</code> patch. [https://github.com/btbd/memla MEMLA] is another alternative, but is less stable due to its memory-based injection

## C97  [supporting / secondary]

DICE 有意把负责唤起控制台的输入处理函数留空，因此原版无法直接使用 UE3 控制台；Mirror's Edge Tweaks 通过自定义 MirrorsEdgeConsole 类覆盖该空函数来恢复完整控制台功能，配合 nulaft / softsoundd 整理的命令列表（托管于 archive.mirrorsedgearchive.org）可用于查询和改写运行时变量。这是逆向获取移动参数的可行路径。

- 原文: > The function responsible for handling input to open the console was intentionally left empty by DICE, [[#Mirror's Edge Tweaks|Mirror's Edge Tweaks]] introduces a custom MirrorsEdgeConsole class that extends the existing Console class, overriding the empty input function with the required code to restore full console functionality.

## C98  [supporting / secondary]

游戏使用 PhysX 2.8.0 作为物理中间件（仅用于可选的碎片/布料等特效层，可由 Nvidia GPU 加速），且其模拟 timestep 可被 mod 提高以获得更平滑的物理渲染。说明角色移动（character movement）与特效物理是两套系统，Godot 复刻只需还原 UE3 的 character movement，而非 PhysX 刚体。

- 原文: > |physics          = PhysX |physics notes    = Version 2.8.0. Nvidia GPUs can accelerate optional physics effects like detailed debris and cloth. The simulation timestep can be increased for smoother physics rendering with the following [...] mod.

