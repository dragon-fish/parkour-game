# hud_ocr.py — 把镜之边缘的调试 HUD 逐帧读成 CSV

Mirror's Edge Tweaks mod 自带一个调试 HUD，显示坐标、状态机状态、速度、峰值记录。
`hud_ocr.py` 把录像逐帧解析成 CSV，用来做定量测量——它是本仓库里绝大多数「✅ 实测确证」
结论的来源（见 [02-速度系统.md](../02-速度系统.md)、[03-损速机制.md](../03-损速机制.md)）。

游戏本身没有任何日志或 CSV 导出：`TdGame` 目录下没有 `Logs/`，且 `TdEngine.ini` 用
`Suppress=Dev*` 关掉了开发期日志分类。录像 + 逐帧识别是唯一可行的取数路径。

## 为什么是模板匹配而不是 OCR

HUD 是**固定位置、固定字体**的覆盖层，只需要分辨约 50 个已知位图，不需要通用 OCR 去
应付任意字体。通用 OCR 反而会被身后渲染的游戏画面干扰。

## 环境

```powershell
python -m venv .venv
.venv\Scripts\python.exe -m pip install opencv-python numpy
```

另需 **ffmpeg** 在 PATH 中（解码走 ffmpeg，不走 OpenCV，原因见下）。

## 三步流程

```powershell
# 1. 先看分割对不对，再信任任何数字
python hud_ocr.py probe frame.png

# 2. 建字形库：给一帧 + 手抄的该帧文本
python hud_ocr.py calib frame.png truth.txt --out hud_ocr_data/glyphs.npz

# 3. 出 CSV
python hud_ocr.py run capture.mp4 --glyphs hud_ocr_data/glyphs.npz --stride 2
```

真值文件每行对应 HUD 的一行；写 `-` 表示「这行我没抄」，用于只补某一行
（例如补一个字形库没见过的状态名）。`--append` 把新样本并入已有库——
**单帧不可能覆盖全部字符**，数字 9 和各种状态名都要靠多帧累积。

## 录制要求

- **分辨率必须和标定帧一致**。字形按像素宽度参与匹配，缩放会让整套模板失效。
- 帧率不必是 62。游戏跑 62 fps，录 120 fps 时每个游戏帧被录约两次，`--stride 2`
  几乎无损且省一半时间。
- H.264 和 AV1 都可以。

## CSV 字段

`frame`、`line_count`、`by_position`、`worst_score`，加 HUD 的 15 个字段
（`t_rta` `t_igt` `health` `reaction` `move_state` `v_kmh` `vt_kmh` `x` `y` `z`
`zt` `sz` `szd` `yaw_deg` `pitch_deg`），外加 `move_state_raw`、`raw_unmatched`。

HUD 字段含义（实测确认，非文档记载）：

| 字段 | 含义 |
|---|---|
| `SZ` | Start Z，本次离地的起点高度 |
| `SZD` | `Z - SZ`，相对起跳点的高度；**任何原因离地都开始计数** |
| `ZT` | Z Top，本次离地到过的最高点 → **跳跃高度 = `ZT - SZ`** |
| `VT` | Velocity Top，速度峰值记录（不是当前总速度） |
| `T (RTA)` / `T (IGT)` | 速通计时器。**要过关卡起跑触发器才启动**，自由跑时恒为 0 |

`SZD == Z - SZ` 是个恒等式，可以拿来交叉校验、自动修掉个别误识别帧。
`move_state` 会吸附到 `TdMove_*` 类名集合（见 `KNOWN_STATES`）；原始识别结果保留在
`move_state_raw` 里备查。

## ⚠️ noclip 会污染数据

Tweaks 的 noclip 期间 `MS` 恒为 `Walking`，飞行速度可达 80+ km/h、`Z` 任意变化，
而且**在半空中关闭 noclip 也不会进入 `Falling`**——落地判定不触发，`SZ`/`SZD` 同时失真。

因此：

- 分析时必须剔除 noclip 段。状态字段帮不上忙，要靠**物理不可能的值**来判别：
  `V > 35 km/h`（地面上限 25.92 + 跳跃加成 ~29.9 已是极限）或 `|SZD| > 12 m`
  （超过 10 m 死亡线的坠落不可能被走完）。
- **坠落相关的测量不能用 noclip 制造高度**，只能用真实地形。
- 若要在 noclip 之后恢复 `SZD` 基准，原地起跳一次即可（owner 实测有效）。

## 踩过的坑（改参数前先读）

1. **`WHITE_MIN = 245` 是整套方案成立的关键。** HUD 是纯白 255，游戏里最亮的建筑约 250。
   卡在这 5 级差上，非 HUD 噪声从 716 个连通域降到 15 个（−98%），同时字形数反而从
   81 升到 173——原先是亮背景把相邻字符桥接在了一起。
2. **top-hat 量的是「比周围亮多少」，不是绝对亮度。** 阈值设到 100 会在背景变亮时
   整块 HUD 消失（实测浅灰墙前纯白字的响应只有 ~90）。噪声抑制交给 `WHITE_MIN`。
3. **字形按基线对齐切割，不按行的 ink 范围。** 行高会随有无下伸字母在 13–17px 之间变，
   按行高缩放会让同一字符在不同行呈现不同大小——匹配置信度中位数曾因此只有 0.125。
4. **字符间距只有 1 像素**，任何「间隙小于 N 就合并」的缝合都会把 `100%` 粘成两块。
5. **解码走 ffmpeg 不走 `cv2.VideoCapture`。** OpenCV 自带的 libaom 拒绝较新的 AV1 流
   （NVIDIA 录制会产出这种），ffmpeg 有 dav1d。顺便用 crop 滤镜只解 HUD 那一块。
6. **相邻两行偶尔被背景 ink 桥接**成一个 35px 高的块，既读成乱码又让后续所有行错位。
   `_unbridge()` 在块内提高 ink 阈值来断开——桥总比它连接的文字行更细。

## hud_ocr_data/

字形库和真值文件放在 `hud_ocr_data/`，**该目录不入库**（见仓库根 `.gitignore`）:
字形模板是从游戏画面提取的位图，属于游戏素材的派生物。用上面的 `calib` 流程
在本地重建即可。
