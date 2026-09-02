# 教程关「第零关」闭环实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让玩家能从「点击屏幕开始游戏」一路走到「感谢试玩」再回到主菜单，中间没有任何
死路：首次启动直接进教程关、以第三人称在无缝平地上逐课学会必学动作、通天塔升起、踏塔即
存档且地板解体、触碰塔顶光球通关并记录进度。

**Architecture:** 进度落在一个新的 `user://` ConfigFile（`ProgressStore`，抄
`SettingsStore` 的静态形状）。主菜单的第一次点击按这份进度分岔：没通关过就复用现有的起身
节拍把镜头绕到角色身后并加载教程关，通关过则维持今天的行为。教程关是一个由
`tools/build_level_0.gd` 生成的 Arena 场景，Arena 新增 `start_in_third_person` 开关（写
`camera_rig.third_person`，**不写** `forced_way`/不落盘）。课程各自是一个能单独打开游玩的
`.tscn`，教程关只取其 `Content` 子树。塔由 `SpiralTower` 的算术生成，`LevelZero` 负责
「教学走完 → 塔升起 → 踏塔 → 地板解体 → 光球 → 白幕 → 感谢试玩」这条链。方块的生长/崩塌
换成 `CubeSwarm`（MultiMesh 体素化 + 一个 `progress` uniform），地板不参与，仍用 acrylic
的点阵。

**Tech Stack:** Godot 4.7.1（用 `.engine/` 里的二进制，不用 PATH 上的 `godot`）、GDScript、
GUT（`bun tools/run_tests.ts`）、MultiMesh + `.gdshader`。

**Spec:** `docs/superpowers/specs/2026-09-02-tutorial-void-design.md`

**前置事实来源:** `.superpowers/sdd/_shared/level0-survey.md`（逐行读源码核过的现状盘点）

**前一份计划:** `docs/superpowers/plans/2026-09-03-tutorial-lesson-loop.md`（已完成，交付了
`LessonContent` / `InputNames` / `TutorialDirector` 的生长-崩塌接线 / `tools/build_lesson_sample.gd`）

## Global Constraints

- **测试一律 `bun tools/run_tests.ts [filter]`**，绝不直接调 gut_cmdln：它会先刷新 global
  script class cache（新增 `class_name` 后不刷新，每个测试都会死在
  `Identifier "Xxx" not declared`），并以 `--fixed-fps 60` 运行。
- **引擎二进制是 `.engine/Godot_v4.7.1-stable_macos.universal.app/Contents/MacOS/Godot`。**
- **实现者不许开带窗 Godot。** 所有验证步骤只许是 headless 脚本或单测。带窗验证归作者。
- **绿色测试不等于没问题。** `.gutconfig.json` 的 `failure_error_types` 不含 `"engine"`，
  GDScript 运行时错误只打印 `SCRIPT ERROR:` 而**不会让测试失败**。凡是本计划里标了
  「读输出找 `SCRIPT ERROR`」的步骤，必须真的翻一遍输出。**不要改 `.gutconfig.json`。**
- **`git add` 必须逐个指名文件**，绝不 `-A`、绝不加目录：工作区里有作者不想入库的未跟踪
  文件。新脚本/新场景的 `.uid` 一起提交（若引擎生成了的话，`ls` 一下确认）。
- **代码注释一律英文，不许 emoji，不许引用对话。** 注释写成约束（现在是什么 + 不要改成
  什么），不写变更史、不写日期、不写前后对比。
- **只有关于原版《镜之边缘 2008》的断言才带 ASCII 证据标签**（`[ME:CONFIRMED]` 等）。本计划
  里没有一处该带。
- **表现值不写单测**，结构性不变量才写。几何尺寸、时长、颜色、亮度一律不断言。
- **每个测试都要能因真实 bug 而失败**，本计划里每个测试都写明了它拦的是哪个 bug。写不出来
  就不要写这个测试。
- **不给玩家够不到的状态写防护。** 塔在隐藏期玩家跑得到，所以「隐藏即无碰撞」是必须的；
  别再往外扩。
- 会长大的配置用**具名字段的字典**（`.claude/skills/naming-config-fields`），GDScript 字典
  字面量用 `=` 写键，读取用 `dict.key` 或 `dict.get(&"key", default)`。
- **手写 `.tscn` 绝不编造 `uid://`**（`.claude/skills/authoring-godot-scene-files`）。省略该
  字段，让引擎自己分配。能生成就生成，不要手写。
- **基线：1072 tests, 1071 passing, 1 known pending (`test_hand_ik`), 32 orphans。** 每个
  Task 结束时这条基线只许增不许破。
- Commit message 用英文，Conventional Commits。

---

## File Structure

| 文件 | 职责 |
|---|---|
| `scripts/ui/progress_store.gd`（新） | `user://progress.cfg` 的静态读写；「教程通关没有」这个问题唯一的答案处 |
| `scripts/ui/pause_ui.gd`（改） | 菜单项改成「标签 + 处理函数」的表，按身份派发；未通关时不出「回主菜单」 |
| `scripts/ui/settings_menu.gd`（改） | 新增第三种行：动作行；「重玩新手教程」 |
| `scripts/ui/main_menu.gd`（改） | 首次点击分岔；镜头绕到身后；`_target_scene` 指向真关卡 |
| `scripts/ui/thanks_screen.gd`（新） | 「感谢试玩」页，任意键回主菜单 |
| `scenes/ui/thanks_for_playing.tscn`（新，手写单节点） | 上面那个脚本的挂载点 |
| `scripts/camera/camera_rig.gd`（改） | `PREFS_PATH` 常量改成可注入的 `prefs_path` 静态变量 |
| `scripts/level/arena.gd`（改） | `start_in_third_person` 开关 |
| `scripts/level/cube_swarm.gd`（新） | 一个盒子的体素化蜂群，单一 `progress` 驱动 |
| `shaders/cube_swarm.gdshader`（新） | 位移、收缩、发光；与 `CubeSwarm.cube_origin()` 是同一条算式的两份拷贝 |
| `scripts/level/growing_solid.gd`（改） | 有蜂群就驱动蜂群，没有就退回今天的 alpha 淡入淡出 |
| `scripts/level/spiral_tower.gd`（新） | 塔的形状，纯算术；`.tscn` 由它生成 |
| `scripts/level/level_zero.gd`（新） | 教学走完 → 塔升起 → 踏塔 → 地板解体 → 光球 → 白幕 |
| `tools/build_level_0_lessons.gd`（新） | 生成四个课程场景 |
| `tools/build_level_0_tower.gd`（新） | 生成 `tower.tscn` |
| `tools/build_level_0.gd`（新） | 生成 `level_0.tscn` |
| `scenes/levels/level_0/lesson_{vault,slide,wall_run,grab}.tscn`（新，生成） | 四课 |
| `scenes/levels/level_0/tower.tscn`（新，生成） | 螺旋塔 + 沿途存档点 + 塔顶光球 |
| `scenes/levels/level_0/level_0.tscn`（新，生成） | 教程关本体 |
| `tests/test_progress_store.gd`（新） | Task 1 |
| `tests/test_menu.gd`（改） | Task 2 / 3 / 12 / 13 |
| `tests/test_third_person_start.gd`（新） | Task 4 |
| `tests/test_cube_swarm.gd`（新） | Task 5 |
| `tests/test_growing_solid.gd`（改） | Task 6 |
| `tests/test_level_0_lessons.gd`（新） | Task 7 |
| `tests/test_spiral_tower.gd`（新） | Task 8 |
| `tests/test_thanks_screen.gd`（新） | Task 9 |
| `tests/test_level_zero.gd`（新） | Task 10 |
| `tests/test_level_0.gd`（新） | Task 11 |

### 已定、不再讨论的决定

1. **第三人称开场是旋钮不是强制。** `Arena.start_in_third_person` 写
   `camera_rig.third_person = true`，**不调 `save_preferences()`**，**不写 `forced_view`**
   （`Player._push_forced_view()` 每帧从 statuses 重算那个字段，外部赋值不会留下）。教程关
   里 `V` 必须照常好使。
2. **教程关的所有子场景放 `scenes/levels/level_0/`。** 唯一例外是已入库的
   `scenes/levels/lessons/sample_wall.tscn`（`tests/test_lesson_loop.gd` 的夹具），原地不动。
3. **地板的消失复用 acrylic 的既有点阵，不写新的溶解 shader。** 地板是一整块 680 m 的盒子，
   顶点级溶解要先细分网格。做法：把 `base_color` 淡到虚空色（背后就是这个颜色，于是表面
   自己没了边），点阵留着；然后整块地板往下沉、点阵随之远去。**`CubeSwarm` 与地板不共用
   任何实现。**
4. **本计划不做羽毛粒子。** 留挂载点即可（`Content` 下随时可以加）。
5. **音乐不在范围内。**
6. **暂停菜单的按序号派发必须先改掉，再谈隐藏任何一项。**
7. **`MeMenuList` 不重写。** 它的 `set_items(Array[String])` / `chosen(index)` 契约主菜单也在
   用；从条目表生成标签数组，再用同一个下标索引回那张表。
8. **不改 `.gutconfig.json`。**

### 选了哪四课，为什么

心态曲线八段里，本次只做顶得住塔的那几段，其余留给作者：

| # | 课 | `teaches` | 顶曲线哪一段 | 为什么进 |
|---|---|---|---|---|
| 0 | 空平地（无场景） | `Move.JUMP` | 一 · 苏醒 / 没有风险 | 表里 `scene = null` 是 `TutorialDirector` 已支持的写法；第一次起跳就过，教的是「我能动、跑不到头」 |
| 1 | 齐腰墙 | `Move.SPEED_VAULT` | 二 · 按一下就行 | 塔上每圈都有矮墙 |
| 2 | 低矮开口 | `Move.SLIDE` | 三 · 要注意时机 | 必学动作里**唯一**要用到跳以外按键（蹲）的那个 |
| 3 | 长墙 | `Move.WALL_RUN` | 三 · 要注意时机 | 塔上宽缺口的唯一解 |
| 4 | 高台抓边 | `Move.GRAB` | 五 · 组合按键 | 跳 → 抓边 → 爬上 → 再跳，塔的主要串联 |

**没做第 4 段（要有耐心 / 平衡木）和第 7 段（路线是你自己选的 / 捷径）**：平衡木教不出塔要
用的任何动作，捷径是塔上的摆放问题、要等作者把塔调顺了再撒。两者都不影响闭环，删掉曲线也
不断（第 5 段的对比暂时由第 3 段承担）。

### 明确的已知缺口（写在这里，不要当成疏漏）

- **光球不是「从第一秒就可见」**，而是随塔一起出现。原因是不变量：平地阶段是环面循环，一个
  钉在世界坐标上的物体会在跨界那一帧整体跳一个周期，把传送暴露掉。让塔和光球跟着跨界又会
  让它们无限漂出地板范围。塔改成「教学走完时在玩家正前方立起」，问题一并消失。美术方向的
  「有一个正在前往的东西」留给作者。
- **每一课一个动作一个单测（spec「测试」一节）本次不做。** 那类测试断言的是几何尺寸能不能
  让某个 move 触发，而尺寸正是作者要逐个重调的；现在写下去就是 change detector。等尺寸定
  下来再补。
- 第一关（医院）不存在，光球之后落在「感谢试玩」页。

---

## Task 1: 进度存档

**Files:**
- Create: `scripts/ui/progress_store.gd`
- Create: `tests/test_progress_store.gd`

**Interfaces:**
- Consumes: 无（`SettingsStore` 只是形状参照，不产生依赖）
- Produces:
  - `class_name ProgressStore extends RefCounted`
  - `static var path: String` （默认 `"user://progress.cfg"`）
  - `static var replay_requested: bool`
  - `static func defaults() -> Dictionary`
  - `static func load_progress() -> Dictionary`
  - `static func save_progress(p: Dictionary) -> void`
  - `static func tutorial_finished() -> bool`
  - `static func mark_tutorial_finished() -> void`

- [ ] **Step 1: 写下会失败的测试**

创建 `tests/test_progress_store.gd`：

```gdscript
extends ParkourTest

# The tutorial-finished flag, which three different screens ask about. Only
# the round trip is asserted: what the flag MEANS is decided elsewhere.

## Per PROCESS, not a fixed name: user:// is per project, so two runs of this
## suite at once would otherwise trample each other's file. Same reasoning
## as tests/test_menu.gd's settings path.
var _test_path: String
var _real_path: String

func before_all() -> void:
	_test_path = "user://progress_test_%d.cfg" % OS.get_process_id()
	_real_path = ProgressStore.path
	ProgressStore.path = _test_path

func after_all() -> void:
	_delete_file()
	ProgressStore.path = _real_path

func before_each() -> void:
	_delete_file()

func after_each() -> void:
	_delete_file()
	ProgressStore.replay_requested = false

func _delete_file() -> void:
	if FileAccess.file_exists(ProgressStore.path):
		DirAccess.remove_absolute(ProgressStore.path)

func test_a_first_run_has_not_finished_the_tutorial() -> void:
	# The first launch is the ONE case the whole feature turns on. A store
	# that read a missing file as "finished" would send a new player straight
	# to a main menu he has never earned.
	assert_false(ProgressStore.tutorial_finished(),
		"a machine with no progress file claims the tutorial is already done")

func test_finishing_the_tutorial_survives_a_round_trip() -> void:
	# The silent failure this catches: a key that defaults() does not list is
	# dropped by load_progress(), so the flag is written and never read back.
	ProgressStore.mark_tutorial_finished()
	assert_true(ProgressStore.tutorial_finished(),
		"the tutorial was marked finished and did not read back that way")

func test_the_replay_request_is_never_written_to_disk() -> void:
	# It is a "play it again NOW" request, not a preference. Persisting it
	# would put the player back into the tutorial on every launch, forever.
	ProgressStore.replay_requested = true
	ProgressStore.mark_tutorial_finished()
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(ProgressStore.path), OK, "test setup: nothing was written")
	assert_false(cfg.has_section_key("progress", "replay_requested"),
		"the session-only replay request was written to disk")
```

- [ ] **Step 2: 跑测试确认它失败**

```sh
bun tools/run_tests.ts progress_store
```

Expected: FAIL，报 `Identifier "ProgressStore" not declared`（类还不存在）。

- [ ] **Step 3: 写实现**

创建 `scripts/ui/progress_store.gd`：

```gdscript
class_name ProgressStore
extends RefCounted

# What the player has already been through. Same static, stateless shape as
# SettingsStore (scripts/ui/settings_store.gd) and it lives beside it for
# that reason -- this class is never instantiated.
#
# A KEY MISSING FROM defaults() IS SILENTLY DROPPED by load_progress(), which
# only copies keys it already knows about. Add the key here first, always.

## Injectable rather than a const, for the same reason SettingsStore.path is:
## a test points this at its own file so the suite never reads, writes or
## deletes the player's real progress.
static var path := "user://progress.cfg"

const _SECTION := "progress"

## True when the next visit to the front door goes straight into the tutorial
## instead of opening the menu.
##
## PER SESSION AND NEVER WRITTEN TO DISK. The settings row that sets it is a
## request to play the tutorial now; persisted, it would send the player back
## into the tutorial on every launch with no way out.
static var replay_requested: bool = false

## The full progress blob with every key at its shipped default.
static func defaults() -> Dictionary:
	return {
		tutorial_finished = false,
	}

## Reads the blob from disk, merging in defaults() for any key the file is
## missing -- including "no file at all", which is every first launch.
static func load_progress() -> Dictionary:
	var progress := defaults()
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return progress
	for key in progress:
		progress[key] = cfg.get_value(_SECTION, key, progress[key])
	return progress

static func save_progress(progress: Dictionary) -> void:
	var cfg := ConfigFile.new()
	for key in progress:
		cfg.set_value(_SECTION, key, progress[key])
	cfg.save(path)

## The one question the pause menu, the front door and the tutorial level all
## ask, answered in one place.
static func tutorial_finished() -> bool:
	return bool(load_progress().get("tutorial_finished", false))

## Records the tutorial as finished, keeping every other key already on disk.
static func mark_tutorial_finished() -> void:
	var progress := load_progress()
	progress.tutorial_finished = true
	save_progress(progress)
```

- [ ] **Step 4: 跑测试确认通过**

```sh
bun tools/run_tests.ts progress_store
```

Expected: PASS，3 passing。输出里搜一遍 `SCRIPT ERROR` —— 静态成员拼错不会让测试红。

- [ ] **Step 5: 提交**

```sh
ls scripts/ui/progress_store.gd.uid tests/test_progress_store.gd.uid
git add scripts/ui/progress_store.gd scripts/ui/progress_store.gd.uid \
        tests/test_progress_store.gd tests/test_progress_store.gd.uid
git commit -m "feat(progress): record whether the tutorial has been finished"
```

---

## Task 2: 暂停菜单改成条目表（纯结构，行为不变）

**Files:**
- Modify: `scripts/ui/pause_ui.gd:104-119`（`_build_ui()` 的 `set_items` 那段）、`280-293`（`_on_chosen`）、`350`（`_go_to_main_menu` 改名）
- Modify: `tests/test_menu.gd:273-292`（跟着改名）
- Test: `tests/test_menu.gd`（追加两个）

**Interfaces:**
- Consumes: `MeMenuList.set_items(items: Array[String])`、`MeMenuList.chosen(index: int)`（都不改）
- Produces:
  - `PauseUi._ENTRIES: Array`（const，元素是 `{label: String, handler: StringName}`）
  - `PauseUi._entries: Array[Dictionary]`（当前在屏上的那几行）
  - `PauseUi._refresh_entries() -> void`
  - `PauseUi.go_to_main_menu() -> void`（由 `_go_to_main_menu` 改名而来，公开）

- [ ] **Step 1: 写下会失败的测试**

在 `tests/test_menu.gd` 末尾追加：

```gdscript
# ---------------------------------------------------------------------------
# The pause menu's rows. MeMenuList only ever reports an INDEX into the labels
# it was handed, so the table that produced those labels is the only thing
# that can say what an index means.
# ---------------------------------------------------------------------------

func test_every_pause_row_names_a_method_that_exists() -> void:
	# A typo'd handler is SILENT: call() on a missing method logs an engine
	# error, and this suite's failure_error_types does not include those, so
	# the row would simply do nothing forever.
	for entry in PauseUi._ENTRIES:
		assert_true(PauseUi.has_method(entry.handler),
			"pause row %s points at a method that does not exist: %s" % [entry.label, entry.handler])

func test_choosing_a_row_runs_that_rows_handler() -> void:
	# Dispatch wired to the wrong index puts 退出游戏 on 设置. Found by name,
	# never by a hardcoded number -- that is the whole point of the table.
	PauseUi.toggle_pause()
	var settings_at := -1
	for i in PauseUi._entries.size():
		if PauseUi._entries[i].handler == &"_show_settings":
			settings_at = i
	assert_gt(settings_at, -1, "test setup: no 设置 row on the pause menu")
	PauseUi._on_chosen(settings_at)
	assert_true(PauseUi._showing_settings,
		"choosing 设置 did not open the settings page")
	PauseUi._on_settings_closed()
	PauseUi._resume()
```

同时把现有的 `test_go_to_main_menu_unpauses_before_requesting_the_scene_change`（`tests/test_menu.gd:286`）里的
`PauseUi._go_to_main_menu()` 改成 `PauseUi.go_to_main_menu()`。

- [ ] **Step 2: 跑测试确认它失败**

```sh
bun tools/run_tests.ts menu
```

Expected: FAIL —— `_ENTRIES` / `_entries` 不存在，`go_to_main_menu` 不存在。

- [ ] **Step 3: 写实现**

`scripts/ui/pause_ui.gd`，在 `var _pending_scene_change` 之前插入表与状态：

```gdscript
## The pause menu's rows, in order. Named fields rather than a positional
## array because this table will grow more of them; see
## .claude/skills/naming-config-fields.
##   label    String -- what the row says
##   handler  StringName -- the method on this node the row runs
const _ENTRIES := [
	{label = "继续游戏", handler = &"_resume"},
	{label = "上一检查点", handler = &"_respawn_at_checkpoint"},
	{label = "重新开始", handler = &"_restart_from_spawn"},
	{label = "设置", handler = &"_show_settings"},
	{label = "回主菜单", handler = &"go_to_main_menu"},
	{label = "退出游戏", handler = &"_show_quit_confirm"},
]

## The rows currently on screen, in the order MeMenuList was handed them.
##
## DISPATCH IS BY IDENTITY, NOT BY POSITION. MeMenuList reports an index into
## the labels it was given and nothing else, so leaving a row out used to
## renumber every handler below it with no error anywhere: 退出游戏 moved up
## onto 回主菜单's number and quit the game.
var _entries: Array[Dictionary] = []
```

把 `_build_ui()` 里的这一行

```gdscript
	_menu_list.set_items(["继续游戏", "上一检查点", "重新开始", "设置", "回主菜单", "退出游戏"])
```

换成

```gdscript
	_refresh_entries()
```

（`_menu_list.chosen.connect(_on_chosen)` 那行保持在它后面不动。）

在 `_set_shown()` 之前加：

```gdscript
## Rebuilds the row list from _ENTRIES. Rebuilt rather than diffed: MeMenuList
## resets its selection on set_items(), and a pause that opens on the top row
## is what a fresh pause should do anyway.
func _refresh_entries() -> void:
	_entries = []
	var labels: Array[String] = []
	for entry in _ENTRIES:
		_entries.append(entry)
		labels.append(entry.label)
	_menu_list.set_items(labels)
```

`_on_chosen()` 整个换成：

```gdscript
func _on_chosen(index: int) -> void:
	if index < 0 or index >= _entries.size():
		return
	call(_entries[index].handler)
```

`_go_to_main_menu()` 改名为 `go_to_main_menu()`（公开：设置页的「重玩新手教程」要走同一条
路，而它可能挂在主菜单下也可能挂在暂停菜单下），并把它的文档注释首行改成：

```gdscript
## Sends the game back to the front door. PUBLIC because the settings page's
## 重玩新手教程 row needs this exact route from either of its two hosts.
func go_to_main_menu() -> void:
```

- [ ] **Step 4: 跑测试确认通过**

```sh
bun tools/run_tests.ts menu
```

Expected: PASS，`menu` 这一组全绿（含新加的两个）。输出里搜 `SCRIPT ERROR` —— `call()` 打
不到方法只会打印引擎错误，不会红。

- [ ] **Step 5: 全量回归**

```sh
bun tools/run_tests.ts
```

Expected: 1074 tests, 1073 passing, 1 pending, 32 orphans（比基线多两个新测试）。

- [ ] **Step 6: 提交**

```sh
git add scripts/ui/pause_ui.gd tests/test_menu.gd
git commit -m "refactor(pause): dispatch menu rows by identity instead of position"
```

---

## Task 3: 未通关时不显示「回主菜单」

**Files:**
- Modify: `scripts/ui/pause_ui.gd`（`_ENTRIES` 加一个字段、`_refresh_entries()` 过滤、`_pause()` 调用）
- Test: `tests/test_menu.gd`（追加两个）

**Interfaces:**
- Consumes: `ProgressStore.tutorial_finished() -> bool`（Task 1）、`PauseUi._ENTRIES` / `_entries` / `_refresh_entries()`（Task 2）
- Produces: `_ENTRIES` 的可选字段 `needs_tutorial: bool`（默认 false）

- [ ] **Step 1: 写下会失败的测试**

在 `tests/test_menu.gd` 末尾追加。注意 `ProgressStore.path` 要按进程重定向，和这个文件已有的
`SettingsStore.path` 一个套路 —— 在文件已有的 `before_all()` / `after_all()` 里各加两行：

```gdscript
# before_all() 里追加：
	_test_progress_path = "user://progress_test_%d.cfg" % OS.get_process_id()
	_real_progress_path = ProgressStore.path
	ProgressStore.path = _test_progress_path

# after_all() 里追加：
	_delete_progress_file()
	ProgressStore.path = _real_progress_path
```

在文件的成员变量区加：

```gdscript
var _test_progress_path: String
var _real_progress_path: String

func _delete_progress_file() -> void:
	if FileAccess.file_exists(ProgressStore.path):
		DirAccess.remove_absolute(ProgressStore.path)
```

然后追加测试：

```gdscript
func test_the_main_menu_row_is_absent_until_the_tutorial_is_finished() -> void:
	# Until it has been finished once the tutorial IS the front door, so there
	# is nothing behind it to go back to.
	_delete_progress_file()
	PauseUi.toggle_pause()
	for entry in PauseUi._entries:
		assert_ne(entry.handler, &"go_to_main_menu",
			"回主菜单 is on the pause menu before the tutorial has ever been finished")
	PauseUi._resume()

func test_hiding_the_main_menu_row_does_not_renumber_the_rows_below_it() -> void:
	# THE BUG THE WHOLE TABLE EXISTS FOR. With positional dispatch, omitting
	# 回主菜单 moved 退出游戏 up onto its number, so the last row quit to the
	# main menu -- or, the other way round, quit the game outright.
	_delete_progress_file()
	PauseUi.toggle_pause()
	var last: int = PauseUi._entries.size() - 1
	assert_eq(PauseUi._entries[last].handler, &"_show_quit_confirm",
		"the last pause row is no longer 退出游戏 once a row above it is hidden")
	PauseUi._resume()

func test_the_main_menu_row_comes_back_once_the_tutorial_is_finished() -> void:
	# Rebuilt on every pause rather than only at boot: the tutorial is finished
	# DURING a session, and the row has to appear without a restart.
	ProgressStore.mark_tutorial_finished()
	PauseUi.toggle_pause()
	var found := false
	for entry in PauseUi._entries:
		if entry.handler == &"go_to_main_menu":
			found = true
	assert_true(found, "回主菜单 never came back after the tutorial was finished")
	PauseUi._resume()
	_delete_progress_file()
```

- [ ] **Step 2: 跑测试确认它失败**

```sh
bun tools/run_tests.ts menu
```

Expected: FAIL —— 三个新测试里至少两个红（行还在、行没回来）。

- [ ] **Step 3: 写实现**

`scripts/ui/pause_ui.gd`：`_ENTRIES` 的文档注释追加一条字段说明，并给「回主菜单」加字段。

```gdscript
##   needs_tutorial  bool, default false -- the row is left out entirely until
##                   the tutorial has been finished once
const _ENTRIES := [
	{label = "继续游戏", handler = &"_resume"},
	{label = "上一检查点", handler = &"_respawn_at_checkpoint"},
	{label = "重新开始", handler = &"_restart_from_spawn"},
	{label = "设置", handler = &"_show_settings"},
	{label = "回主菜单", handler = &"go_to_main_menu", needs_tutorial = true},
	{label = "退出游戏", handler = &"_show_quit_confirm"},
]
```

`_refresh_entries()` 换成：

```gdscript
## Rebuilds the row list from _ENTRIES. Rebuilt rather than diffed: MeMenuList
## resets its selection on set_items(), and a pause that opens on the top row
## is what a fresh pause should do anyway.
##
## THE ROW IS LEFT OUT, NOT DISABLED. Until the tutorial has been finished once
## the tutorial IS the front door, and a greyed row would promise a way back
## that does not exist.
func _refresh_entries() -> void:
	var finished: bool = ProgressStore.tutorial_finished()
	_entries = []
	var labels: Array[String] = []
	for entry in _ENTRIES:
		if entry.get(&"needs_tutorial", false) and not finished:
			continue
		_entries.append(entry)
		labels.append(entry.label)
	_menu_list.set_items(labels)
```

`_pause()` 在显示之前刷新：

```gdscript
func _pause() -> void:
	get_tree().paused = true
	# BEFORE _set_shown(). The tutorial can be finished during a session, and
	# the row it unlocks has to appear on the very next pause.
	_refresh_entries()
	_set_shown(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
```

- [ ] **Step 4: 跑测试确认通过**

```sh
bun tools/run_tests.ts menu
```

Expected: PASS。搜输出里的 `SCRIPT ERROR`。

- [ ] **Step 5: 提交**

```sh
git add scripts/ui/pause_ui.gd tests/test_menu.gd
git commit -m "feat(pause): hide the main-menu row until the tutorial is finished"
```

---

## Task 4: `Arena.start_in_third_person`

**Files:**
- Modify: `scripts/camera/camera_rig.gd:1402`（`PREFS_PATH` 常量 → 静态变量）、`1413`、`1419`
- Modify: `scripts/level/arena.gd`（新增 export；`_ready()` 在 `load_preferences()` 之后应用）
- Create: `tests/test_third_person_start.gd`

**Interfaces:**
- Consumes: `CameraRig.third_person: bool`、`CameraRig.load_preferences()`、`Status.View.NONE`
- Produces:
  - `Arena.start_in_third_person: bool`（`@export`，默认 `false`）
  - `CameraRig.prefs_path: String`（`static var`，默认 `"user://camera_prefs.cfg"`）

- [ ] **Step 1: 写下会失败的测试**

创建 `tests/test_third_person_start.gd`：

```gdscript
extends ParkourTest

# A level that hands control over from behind the body. Two things are
# asserted and both are structural: WHICH field carries the view, and that
# saying so does not rewrite what the player chose.

## Per PROCESS: user:// is per project, so two concurrent runs of this suite
## would otherwise write each other's camera preferences.
var _test_prefs: String
var _real_prefs: String
var _arena: Arena

func before_all() -> void:
	_test_prefs = "user://camera_prefs_test_%d.cfg" % OS.get_process_id()
	_real_prefs = CameraRig.prefs_path
	CameraRig.prefs_path = _test_prefs

func after_all() -> void:
	_delete_prefs()
	CameraRig.prefs_path = _real_prefs

func after_each() -> void:
	if is_instance_valid(_arena):
		_arena.queue_free()
	_arena = null
	_delete_prefs()

func _delete_prefs() -> void:
	if FileAccess.file_exists(CameraRig.prefs_path):
		DirAccess.remove_absolute(CameraRig.prefs_path)

func _arena_starting_in(third: bool) -> Arena:
	var arena: Arena = preload("res://scenes/main.tscn").instantiate()
	arena.start_in_third_person = third
	add_child_autofree(arena)
	await step(2)
	_arena = arena
	return arena

func test_a_level_can_start_the_camera_behind_the_body() -> void:
	var arena: Arena = await _arena_starting_in(true)
	assert_true(arena.player.camera_rig.third_person,
		"start_in_third_person did not put the rig in third person")

func test_starting_behind_the_body_does_not_pin_the_view() -> void:
	# THE FIELD MATTERS. forced_view is re-derived from the status list by
	# Player._push_forced_view() every tick, so a level that wrote it would be
	# overwritten within a frame -- and while it held, V would refuse to work.
	var arena: Arena = await _arena_starting_in(true)
	assert_eq(arena.player.camera_rig.forced_view, Status.View.NONE,
		"the level pinned the view instead of setting the preference, so V is dead")

func test_starting_behind_the_body_does_not_rewrite_the_saved_preference() -> void:
	# The player's own choice outlives a visit to a level that starts him
	# somewhere else. Saving here would silently flip it for every other level.
	var before := ConfigFile.new()
	before.set_value("third_person", "on", false)
	before.save(CameraRig.prefs_path)
	await _arena_starting_in(true)
	var after := ConfigFile.new()
	assert_eq(after.load(CameraRig.prefs_path), OK, "the preferences file disappeared")
	assert_false(bool(after.get_value("third_person", "on", true)),
		"the level saved its own view over the player's saved preference")

func test_a_level_that_says_nothing_leaves_the_preference_alone() -> void:
	# Every existing level must be untouched by this feature.
	var saved := ConfigFile.new()
	saved.set_value("third_person", "on", true)
	saved.save(CameraRig.prefs_path)
	var arena: Arena = await _arena_starting_in(false)
	assert_true(arena.player.camera_rig.third_person,
		"a level with the flag off overrode the saved preference")
```

- [ ] **Step 2: 跑测试确认它失败**

```sh
bun tools/run_tests.ts third_person_start
```

Expected: FAIL —— `CameraRig.prefs_path` 与 `Arena.start_in_third_person` 都不存在。

- [ ] **Step 3: 把 `PREFS_PATH` 改成可注入的静态变量**

`scripts/camera/camera_rig.gd`，把 1402 行附近的常量换掉：

```gdscript
## Where the viewing preference is remembered between sessions.
##
## user:// rather than the project, because it is one person's preference about
## one machine's screen, not a fact about the game. Nothing here affects
## movement, so a missing or corrupt file just means the defaults.
##
## Injectable rather than a const, the same way SettingsStore.path is: a test
## points this at its own file so the suite never reads, writes or deletes the
## player's real preferences.
static var prefs_path := "user://camera_prefs.cfg"
```

并把 `save_preferences()` 里的 `file.save(PREFS_PATH)` 改成 `file.save(prefs_path)`，
`load_preferences()` 里的 `file.load(PREFS_PATH)` 改成 `file.load(prefs_path)`。

- [ ] **Step 4: 给 Arena 加开关**

`scripts/level/arena.gd`，在 `@export var view_distance` 之后加：

```gdscript
## Start this level with the camera behind the body rather than at the eye.
##
## THE PREFERENCE, NOT A PIN. This writes CameraRig.third_person, which is the
## field V toggles, so the player can go back to first person immediately. DO
## NOT route this through forced_view: Player._push_forced_view() re-derives
## that field from the status list every tick and would overwrite it inside a
## frame, and while it held, V would be refused.
##
## AND IT DOES NOT SAVE. The player's own saved preference is read a line
## earlier in _ready() and has to survive a visit to a level that starts him
## somewhere else.
@export var start_in_third_person: bool = false
```

在 `_ready()` 里，紧跟在 `player.camera_rig.load_preferences()` 之后（`_mark.call("camera_rig.setup+prefs")` 之前）插入：

```gdscript
		if start_in_third_person:
			player.camera_rig.third_person = true
```

- [ ] **Step 5: 跑测试确认通过**

```sh
bun tools/run_tests.ts third_person_start
```

Expected: PASS，4 passing。搜 `SCRIPT ERROR`。

- [ ] **Step 6: 全量回归（相机偏好的读写路径被动过，必须整跑）**

```sh
bun tools/run_tests.ts
```

Expected: 1078 tests, 1077 passing, 1 pending, 32 orphans。

- [ ] **Step 7: 提交**

```sh
ls tests/test_third_person_start.gd.uid
git add scripts/camera/camera_rig.gd scripts/level/arena.gd \
        tests/test_third_person_start.gd tests/test_third_person_start.gd.uid
git commit -m "feat(level): let a level start the camera behind the body"
```

---

## Task 5: `CubeSwarm` —— 盒子散成发光小方块

**Files:**
- Create: `scripts/level/cube_swarm.gd`
- Create: `shaders/cube_swarm.gdshader`
- Create: `tests/test_cube_swarm.gd`

**Interfaces:**
- Consumes: 无
- Produces:
  - `class_name CubeSwarm extends MultiMeshInstance3D`
  - `@export box_size: Vector3` / `cube_size: float` / `travel: float` / `base_color: Color` / `glow_color: Color` / `random_seed: int`
  - `var progress: float`（带 setter，0 = packed，1 = gone）
  - `func build() -> void`
  - `func grid_counts() -> Vector3i`
  - `func cube_origin(index: int, at: float) -> Vector3`

**为什么这在本项目里是精确的而不是近似：** 教程里每一块课程几何**本来就是盒子**，所以把它
体素化成一格一格的小方块是**恰好填满**，不是逼近。挤在一起就是原来那个盒子，散开就是移动
每个方块。

- [ ] **Step 1: 写下会失败的测试**

创建 `tests/test_cube_swarm.gd`：

```gdscript
extends ParkourTest

# The swarm's PLACEMENT, which is the half that lives on the CPU. What it
# looks like leaving -- how far, how bright, how fast -- is the author's to
# judge and is asserted nowhere.

var _swarm: CubeSwarm

func after_each() -> void:
	if is_instance_valid(_swarm):
		_swarm.queue_free()
	_swarm = null

func _swarm_of(size: Vector3, cube: float) -> CubeSwarm:
	var swarm := CubeSwarm.new()
	swarm.box_size = size
	swarm.cube_size = cube
	add_child_autofree(swarm)
	await step(1)
	_swarm = swarm
	return swarm

func test_the_grid_fills_the_box_it_stands_in_for() -> void:
	# A wrong grid derivation is silent and total: one cube where a wall
	# should be, or a hundred thousand where two hundred belong.
	var swarm: CubeSwarm = await _swarm_of(Vector3(6.0, 1.0, 0.5), 0.25)
	assert_eq(swarm.grid_counts(), Vector3i(24, 4, 2),
		"the grid does not divide the box by cube_size")
	assert_eq(swarm.multimesh.instance_count, 24 * 4 * 2,
		"the multimesh holds a different number of cubes than the grid says")

func test_the_swarm_material_finds_its_shader() -> void:
	# The path is a string. A wrong one loads nothing and the swarm renders as
	# untouched grey boxes that never move.
	var swarm: CubeSwarm = await _swarm_of(Vector3.ONE, 0.5)
	var material := (swarm.multimesh.mesh as BoxMesh).material as ShaderMaterial
	assert_not_null(material, "the swarm's mesh carries no ShaderMaterial")
	assert_not_null(material.shader, "the swarm's material has no shader resource")

func test_a_packed_swarm_sits_inside_the_box() -> void:
	# Off-by-one centring puts the swarm half a box away from the collision it
	# stands in for, so the block you see is not the block you hit.
	var swarm: CubeSwarm = await _swarm_of(Vector3(2.0, 1.0, 1.0), 0.25)
	var half: Vector3 = swarm.box_size * 0.5
	for i in swarm.multimesh.instance_count:
		var origin: Vector3 = swarm.cube_origin(i, 0.0)
		assert_true(absf(origin.x) <= half.x + 0.001 \
			and absf(origin.y) <= half.y + 0.001 \
			and absf(origin.z) <= half.z + 0.001,
			"cube %d starts outside the box it fills: %s" % [i, origin])

func test_a_finished_swarm_has_left_the_box() -> void:
	# A zero or degenerate direction makes the block collapse in place instead
	# of dispersing -- it just shrinks and winks out, which is the fade this
	# class exists to replace.
	var swarm: CubeSwarm = await _swarm_of(Vector3(2.0, 1.0, 1.0), 0.25)
	var half: Vector3 = swarm.box_size * 0.5
	for i in swarm.multimesh.instance_count:
		var origin: Vector3 = swarm.cube_origin(i, 1.0)
		assert_true(absf(origin.x) > half.x or absf(origin.y) > half.y \
			or absf(origin.z) > half.z,
			"cube %d never left the box: %s" % [i, origin])
```

- [ ] **Step 2: 跑测试确认它失败**

```sh
bun tools/run_tests.ts cube_swarm
```

Expected: FAIL，`Identifier "CubeSwarm" not declared`。

- [ ] **Step 3: 写 shader**

创建 `shaders/cube_swarm.gdshader`：

```glsl
shader_type spatial;
// depth_draw_always keeps the packed box writing depth. At progress 0 this
// material has to read as the solid it replaces, and a transparent surface
// that skips the depth buffer sorts wrong against everything around it.
render_mode blend_mix, depth_draw_always, cull_back;

// 0 = the packed box, 1 = fully dispersed. Driven by GrowingSolid.
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 base_color : source_color = vec4(0.93, 0.95, 0.97, 1.0);
uniform vec4 glow_color : source_color = vec4(0.85, 0.92, 1.0, 1.0);
// Metres a cube travels by the time it is gone.
uniform float travel = 3.0;
uniform float glow_strength = 3.0;

varying float leaving;

void vertex() {
	// INSTANCE_CUSTOM carries this cube's own direction (rgb) and the point in
	// the run at which it starts moving (a), so the block does not leave on
	// one frame.
	//
	// THIS IS THE SAME ARITHMETIC AS CubeSwarm.cube_origin(). Those two are
	// the only copies of it: change one and change the other, or the swarm on
	// screen stops matching the swarm the tests describe.
	float delay = INSTANCE_CUSTOM.a;
	float k = clamp((progress - delay) / max(1.0 - delay, 0.0001), 0.0, 1.0);
	leaving = k;
	// Shrink about the cube's own centre, then carry it off. At k = 0 the
	// scale is 1 and the offset is 0, which is what makes the packed grid
	// indistinguishable from the solid box it stands in for.
	VERTEX *= 1.0 - k;
	VERTEX += normalize(INSTANCE_CUSTOM.rgb + vec3(1e-5)) * travel * k;
}

void fragment() {
	ALBEDO = mix(base_color.rgb, glow_color.rgb, leaving);
	EMISSION = glow_color.rgb * glow_strength * leaving;
	ALPHA = 1.0 - leaving * leaving;
	ROUGHNESS = 0.6;
}
```

- [ ] **Step 4: 写实现**

创建 `scripts/level/cube_swarm.gd`：

```gdscript
class_name CubeSwarm
extends MultiMeshInstance3D

# A solid box that comes apart into a swarm of small glowing cubes, and goes
# back together again.
#
# EXACT, NOT AN APPROXIMATION. Every lesson block in the tutorial IS a box, so
# a regular grid of cubes filling its AABB is the box: packed tight and wearing
# one material, it reads as the original solid, and dispersing is nothing more
# than moving each cube.
#
# ONE NUMBER DRIVES IT. progress 0 is packed, 1 is gone, and growth is the same
# animation run backwards -- deliberately the same code path, not a second one.
#
# NOT FOR THE FLOOR. The tutorial's plain is hundreds of metres across and
# would voxelise into millions of instances. It leaves by fading into the void
# and dropping its dot field instead; see LevelZero. DO NOT make the two share
# an implementation.

const SHADER := "res://shaders/cube_swarm.gdshader"

## The box this stands in for, metres. The grid fills exactly this.
@export var box_size: Vector3 = Vector3.ONE

## Edge length of one cube. 0.25 m puts a waist-high 6 x 1 x 0.6 m wall at
## 24 x 4 x 2 = 192 instances -- chunky on purpose, and nowhere near a count
## that costs anything.
@export var cube_size: float = 0.25

## How far a cube has travelled once it is gone, metres. Tuning value.
@export var travel: float = 3.0

@export var base_color: Color = Color(0.93, 0.95, 0.97)
@export var glow_color: Color = Color(0.85, 0.92, 1.0)

## Fixed so a rebuild lands the same cubes in the same places. A swarm that
## reshuffled on every load could not be judged by eye at all.
@export var random_seed: int = 20260903

## 0 = the packed box, 1 = fully dispersed. The only thing anything outside
## this class touches.
var progress: float = 0.0:
	set(value):
		progress = clampf(value, 0.0, 1.0)
		if _material != null:
			_material.set_shader_parameter("progress", progress)

var _material: ShaderMaterial
## Per cube, in instance order. Named fields because this will grow more of
## them (a spin, a per-cube tint); see .claude/skills/naming-config-fields.
##   direction  Vector3 -- unit, the way this cube leaves
##   delay      float, 0..1 -- how far into the run it starts moving
var _cubes: Array[Dictionary] = []

func _ready() -> void:
	build()

## Lays out the grid. Idempotent: calling it again rebuilds from whatever
## box_size/cube_size currently say.
func build() -> void:
	var counts := grid_counts()
	var cell := Vector3(box_size.x / float(counts.x),
		box_size.y / float(counts.y), box_size.z / float(counts.z))

	_material = ShaderMaterial.new()
	_material.shader = load(SHADER)
	_material.set_shader_parameter("base_color", base_color)
	_material.set_shader_parameter("glow_color", glow_color)
	_material.set_shader_parameter("travel", travel)
	_material.set_shader_parameter("progress", progress)

	var cube_mesh := BoxMesh.new()
	cube_mesh.size = cell
	cube_mesh.material = _material

	var mesh := MultiMesh.new()
	mesh.transform_format = MultiMesh.TRANSFORM_3D
	mesh.use_custom_data = true
	mesh.mesh = cube_mesh
	mesh.instance_count = counts.x * counts.y * counts.z

	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	_cubes.clear()
	var index := 0
	for ix in counts.x:
		for iy in counts.y:
			for iz in counts.z:
				var origin := Vector3(
					(float(ix) + 0.5) * cell.x - box_size.x * 0.5,
					(float(iy) + 0.5) * cell.y - box_size.y * 0.5,
					(float(iz) + 0.5) * cell.z - box_size.z * 0.5)
				# Biased upwards: a block that comes apart should read as
				# rising light, not as rubble.
				var direction := Vector3(rng.randf_range(-1.0, 1.0),
					rng.randf_range(-0.2, 1.0), rng.randf_range(-1.0, 1.0))
				if direction.length() < 0.001:
					direction = Vector3.UP
				direction = direction.normalized()
				var delay := rng.randf_range(0.0, 0.6)
				_cubes.append({direction = direction, delay = delay})
				mesh.set_instance_transform(index, Transform3D(Basis.IDENTITY, origin))
				mesh.set_instance_custom_data(index,
					Color(direction.x, direction.y, direction.z, delay))
				index += 1
	multimesh = mesh

## How many cubes along each axis. At least one per axis, so a box thinner
## than a cube still gets a slab rather than nothing at all.
func grid_counts() -> Vector3i:
	var edge: float = maxf(cube_size, 0.001)
	return Vector3i(
		maxi(1, int(round(box_size.x / edge))),
		maxi(1, int(round(box_size.y / edge))),
		maxi(1, int(round(box_size.z / edge))))

## Where cube `index` stands at `at` progress, in this node's own space.
##
## THIS IS THE SAME ARITHMETIC shaders/cube_swarm.gdshader runs on the GPU, and
## those two are the only copies of it. Change one and change the other.
func cube_origin(index: int, at: float) -> Vector3:
	var base: Vector3 = multimesh.get_instance_transform(index).origin
	var cube: Dictionary = _cubes[index]
	var delay: float = cube.delay
	var k: float = clampf((at - delay) / maxf(1.0 - delay, 0.0001), 0.0, 1.0)
	return base + (cube.direction as Vector3) * travel * k
```

- [ ] **Step 5: 跑测试确认通过**

```sh
bun tools/run_tests.ts cube_swarm
```

Expected: PASS，4 passing。**读输出找 `SCRIPT ERROR`** —— shader 编译失败会打在 stderr 上
而不会让测试变红。

- [ ] **Step 6: headless 验证 shader 真的编译了**

shader 只在被真正绘制时才编译，测试是 headless 的，所以额外跑一次带渲染的截图脚本（**不加
`--headless`**，但也不打开交互窗口 —— `tools/capture.gd` 自带 `--quit-after`）：

```sh
.engine/Godot_v4.7.1-stable_macos.universal.app/Contents/MacOS/Godot --path . \
    --resolution 640x360 --quit-after 180 \
    --script res://tools/capture.gd -- res://scenes/levels/lessons/sample_wall.tscn \
    /tmp/cube_swarm_smoke.png 60
```

Expected: 命令退出码 0，输出里没有 `Shader compilation failed` / `error(s)`。这一步只看
日志，图给作者自己看。

- [ ] **Step 7: 提交**

```sh
ls scripts/level/cube_swarm.gd.uid tests/test_cube_swarm.gd.uid
git add scripts/level/cube_swarm.gd scripts/level/cube_swarm.gd.uid \
        shaders/cube_swarm.gdshader \
        tests/test_cube_swarm.gd tests/test_cube_swarm.gd.uid
git commit -m "feat(level): voxelise a block into a swarm of glowing cubes"
```

---

## Task 6: `GrowingSolid` 有蜂群就驱动蜂群

**Files:**
- Modify: `scripts/level/growing_solid.gd`（`_ready()`、`_apply_alpha` 改名为 `_apply_visual`、三处调用点）
- Test: `tests/test_growing_solid.gd`（追加两个）

**Interfaces:**
- Consumes: `CubeSwarm.progress`（Task 5）
- Produces: `GrowingSolid._swarms: Array[CubeSwarm]`、`GrowingSolid._apply_visual(k: float) -> void`

- [ ] **Step 1: 写下会失败的测试**

在 `tests/test_growing_solid.gd` 末尾追加：

```gdscript
func test_a_block_with_a_swarm_drives_the_swarm_rather_than_its_alpha() -> void:
	# The wiring bug this catches: a CubeSwarm IS a GeometryInstance3D, so an
	# unfiltered find_children() sweeps it into the fade list. The block then
	# fades out with all its cubes standing still -- the exact effect the
	# swarm exists to replace, and no error anywhere.
	var solid := GrowingSolid.new()
	solid.grow_time = 1.0
	var swarm := CubeSwarm.new()
	swarm.box_size = Vector3.ONE
	swarm.cube_size = 0.5
	solid.add_child(swarm)
	add_child_autofree(solid)
	await step(1)
	assert_almost_eq(swarm.progress, 1.0, 0.01,
		"a block that has not grown yet is not fully dispersed")
	assert_almost_eq(swarm.transparency, 0.0, 0.01,
		"the swarm was faded instead of dispersed")

func test_a_block_with_no_swarm_still_fades() -> void:
	# The fallback must keep working: not everything in this game is a box,
	# and a lesson without a swarm may not simply stop appearing.
	var solid := GrowingSolid.new()
	solid.grow_time = 1.0
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	solid.add_child(mesh)
	add_child_autofree(solid)
	await step(1)
	assert_almost_eq(mesh.transparency, 1.0, 0.01,
		"a block with no swarm is visible before it has grown")
```

- [ ] **Step 2: 跑测试确认它失败**

```sh
bun tools/run_tests.ts growing_solid
```

Expected: FAIL —— `swarm.progress` 是 0.0（蜂群被当成普通几何、只被设了 transparency）。

- [ ] **Step 3: 写实现**

`scripts/level/growing_solid.gd`：在 `_geometry` 声明下方加：

```gdscript
# The block's cube swarms, if it has any. A block made of boxes takes itself
# apart into glowing cubes; anything else falls back to the alpha fade, which
# is what everything used before and what non-box geometry still gets.
var _swarms: Array[CubeSwarm] = []
```

`_ready()` 换成：

```gdscript
func _ready() -> void:
	for node in find_children("*", "CubeSwarm", true, false):
		_swarms.append(node as CubeSwarm)
	for node in find_children("*", "GeometryInstance3D", true, false):
		# A CubeSwarm IS a GeometryInstance3D. It is driven by its own progress,
		# and driving its transparency as well would fade it out from under its
		# own animation.
		if node is CubeSwarm:
			continue
		_geometry.append(node as GeometryInstance3D)
	_apply_visual(0.0)
```

把 `_apply_alpha` 整个换成：

```gdscript
## `k` is how much of the block EXISTS: 0 nothing, 1 whole. A swarm reads the
## complement -- how far it has dispersed -- which is what makes growth and
## collapse the same animation run in opposite directions.
##
## MVP for anything that is not a box: plain transparency. Nothing outside this
## function knows which of the two is in use.
func _apply_visual(k: float) -> void:
	for node in _geometry:
		node.transparency = clampf(1.0 - k, 0.0, 1.0)
	for swarm in _swarms:
		swarm.progress = 1.0 - clampf(k, 0.0, 1.0)
```

把 `_physics_process()` 里的两处 `_apply_alpha(...)` 改成 `_apply_visual(...)`
（`_apply_alpha(progress)` → `_apply_visual(progress)`，`_apply_alpha(1.0 - k)` → `_apply_visual(1.0 - k)`）。

顺带把文件头注释里 "Today growth is an alpha fade and collapse is a fade out." 那句改成：

```
# THE SHOW MAY START CRUDE, THE TIMING MAY NOT. A block made of boxes carries
# CubeSwarm children and comes apart into glowing cubes; anything else falls
# back to an alpha fade. Neither of them changes a line of the timing here.
```

- [ ] **Step 4: 跑测试确认通过**

```sh
bun tools/run_tests.ts growing_solid lesson_loop tutorial
```

Expected: PASS。`lesson_loop` 与 `tutorial_director` 是这段代码的真实调用方，一起跑。搜
`SCRIPT ERROR`。

- [ ] **Step 5: 提交**

```sh
git add scripts/level/growing_solid.gd tests/test_growing_solid.gd
git commit -m "feat(level): let a block come apart into cubes instead of fading"
```

---

## Task 7: 四个课程场景

**Files:**
- Create: `tools/build_level_0_lessons.gd`
- Create（生成物）: `scenes/levels/level_0/lesson_vault.tscn`、`lesson_slide.tscn`、`lesson_wall_run.tscn`、`lesson_grab.tscn`
- Create: `tests/test_level_0_lessons.gd`

**Interfaces:**
- Consumes: `CubeSwarm`（Task 5）、`LessonContent.CONTENT`、`arena.gd`、`spawn_point.gd`、`res://presets/default.tres`、`res://scenes/player/player.tscn`、`res://materials/acrylic_void.tres`
- Produces: 四个 `.tscn`，每个的根是一个可直接游玩的 Arena，几何全部在名为 `Content` 的直接子节点下

- [ ] **Step 1: 写下会失败的测试**

创建 `tests/test_level_0_lessons.gd`：

```gdscript
extends ParkourTest

# The tutorial's lesson scenes. Two conventions are asserted and both are
# structural; the geometry's SIZES are the author's to tune and are asserted
# nowhere.

const LESSONS := [
	"res://scenes/levels/level_0/lesson_vault.tscn",
	"res://scenes/levels/level_0/lesson_slide.tscn",
	"res://scenes/levels/level_0/lesson_wall_run.tscn",
	"res://scenes/levels/level_0/lesson_grab.tscn",
]

func test_every_lesson_hands_over_a_content_subtree() -> void:
	# Geometry that escaped Content contributes NOTHING to the tutorial and
	# does so silently -- the lesson simply never appears in front of the
	# player, and the level sits there waiting for a move he cannot make.
	for path in LESSONS:
		assert_true(ResourceLoader.exists(path), "missing lesson scene: %s" % path)
		var content := LessonContent.take(load(path))
		assert_not_null(content, "%s has no Content node" % path)
		assert_gt(content.get_child_count(), 0, "%s has an empty Content node" % path)
		content.free()

func test_every_lesson_can_be_opened_and_played_on_its_own() -> void:
	# The whole reason a lesson is its own file: the author shapes the geometry
	# by running around in it. A scene missing its scaffolding cannot be opened
	# for that, and the loss shows up as "why does nothing happen when I press
	# play" rather than as an error.
	for path in LESSONS:
		var whole: Node = load(path).instantiate()
		assert_not_null(whole.get_node_or_null("Player"),
			"%s has no Player, so it cannot be played on its own" % path)
		assert_not_null(whole.get_node_or_null("SpawnPoint"),
			"%s has no SpawnPoint, so Arena.reset_player() would crash in it" % path)
		assert_not_null(whole.get_node_or_null("Floor"),
			"%s has no floor to stand on" % path)
		whole.free()

func test_every_lesson_block_is_solid_and_made_of_cubes() -> void:
	# Two failures at once, both silent: geometry with no collision is scenery
	# the player runs through, and a block with no swarm falls back to the
	# alpha fade in a level where every other block comes apart.
	for path in LESSONS:
		var content := LessonContent.take(load(path))
		for body in content.find_children("*", "StaticBody3D", true, false):
			assert_gt(body.find_children("*", "CollisionShape3D", true, false).size(), 0,
				"%s: block %s has no collision" % [path, body.name])
			assert_gt(body.find_children("*", "CubeSwarm", true, false).size(), 0,
				"%s: block %s has no CubeSwarm" % [path, body.name])
		content.free()
```

- [ ] **Step 2: 跑测试确认它失败**

```sh
bun tools/run_tests.ts level_0_lessons
```

Expected: FAIL，`missing lesson scene: ...`。

- [ ] **Step 3: 写生成器**

创建 `tools/build_level_0_lessons.gd`：

```gdscript
extends SceneTree

# Generates the tutorial's lesson scenes under scenes/levels/level_0/.
#
# A LESSON IS ALSO A PLAYABLE LEVEL. The author shapes this geometry by running
# around in it, so every lesson carries its own Sun, WorldEnvironment,
# SpawnPoint, floor and Player. The tutorial takes ONLY the Content subtree
# (LessonContent.take) and throws the rest away, so none of that scaffolding
# ever reaches the real level.
#
# BLOCKS ARE BOXES, AND A BOX GETS A CubeSwarm INSTEAD OF A MeshInstance3D. The
# swarm is what comes apart when the lesson is passed; a plain mesh would fall
# back to the alpha fade and read as a different system from everything around
# it.
#
# EVERY NUMBER IN _LESSONS IS A TUNING VALUE. They are the author's to drag;
# nothing asserts on them.
#
# Run with:
#   .engine/Godot_v4.7.1-stable_macos.universal.app/Contents/MacOS/Godot \
#       --headless --path . --script res://tools/build_level_0_lessons.gd

const OUT_DIR := "res://scenes/levels/level_0"

## The lit end of the palette, and the horizon. Same pair the void plain uses,
## so a lesson opened on its own looks like the level it belongs to.
const PALE := Color(0.93, 0.96, 0.98)
const COOL := Color(0.78, 0.86, 0.93)
## The guide colour. Red is what the player is meant to reach for.
const GUIDE := Color(0.91, 0.02, 0.0)

## The lessons. Named fields; see .claude/skills/naming-config-fields.
##   file    String -- the .tscn basename under OUT_DIR
##   root    String -- the scene root's node name
##   spawn   Vector3 -- where the body starts, body centre
##   blocks  Array of {name, size, at, colour}
##           name    String -- the StaticBody3D's node name
##           size    Vector3 -- metres
##           at      Vector3 -- centre of the box, level space
##           colour  Color -- the swarm's packed colour
const _LESSONS := [
	{
		file = "lesson_vault", root = "LessonVault", spawn = Vector3(0.0, 0.95, 16.0),
		blocks = [
			{name = "Wall", size = Vector3(9.0, 1.0, 0.6), at = Vector3(0.0, 0.5, 0.0), colour = PALE},
			{name = "Lip", size = Vector3(9.0, 0.08, 0.7), at = Vector3(0.0, 1.04, 0.0), colour = GUIDE},
		],
	},
	{
		file = "lesson_slide", root = "LessonSlide", spawn = Vector3(0.0, 0.95, 20.0),
		blocks = [
			# The opening is 1.1 m: a standing body does not fit, a sliding one
			# does, and the run-up is what turns the crouch into a slide.
			{name = "Roof", size = Vector3(7.0, 0.7, 5.0), at = Vector3(0.0, 1.45, 0.0), colour = PALE},
			{name = "LegLeft", size = Vector3(0.8, 1.1, 5.0), at = Vector3(-3.1, 0.55, 0.0), colour = PALE},
			{name = "LegRight", size = Vector3(0.8, 1.1, 5.0), at = Vector3(3.1, 0.55, 0.0), colour = PALE},
			{name = "Lintel", size = Vector3(7.0, 0.1, 0.2), at = Vector3(0.0, 1.16, 2.6), colour = GUIDE},
		],
	},
	{
		file = "lesson_wall_run", root = "LessonWallRun", spawn = Vector3(0.0, 0.95, 22.0),
		blocks = [
			{name = "Wall", size = Vector3(14.0, 4.5, 0.9), at = Vector3(0.0, 2.25, 0.0), colour = PALE},
			{name = "Line", size = Vector3(14.0, 0.12, 0.95), at = Vector3(0.0, 1.7, 0.0), colour = GUIDE},
		],
	},
	{
		file = "lesson_grab", root = "LessonGrab", spawn = Vector3(0.0, 0.95, 18.0),
		blocks = [
			# Too tall to vault, low enough that a jump puts the hands on the
			# lip: the block is read as a ledge, not as a wall.
			{name = "Block", size = Vector3(7.0, 2.4, 4.0), at = Vector3(0.0, 1.2, 0.0), colour = PALE},
			{name = "Edge", size = Vector3(7.0, 0.1, 0.3), at = Vector3(0.0, 2.45, 1.85), colour = GUIDE},
		],
	},
]

## Wide enough that the author cannot run off it while shaping a block.
const FLOOR_SPAN := 120.0
const FLOOR_THICKNESS := 2.0

var _root: Node3D

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	for lesson in _LESSONS:
		_write(lesson)
	quit(0)

func _write(lesson: Dictionary) -> void:
	var root := Node3D.new()
	root.name = lesson.root
	_root = root
	root.set_script(load("res://scripts/level/arena.gd"))
	root.set("config", load("res://presets/default.tres"))
	# She cannot die in a lesson either -- same contract the tutorial runs
	# under, so a lesson opened on its own behaves the way it will in place.
	root.set("rescue_below_hp", 30.0)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(-30.0), 0.0)
	# NO SHADOWS. A shadow is a statement about the floor being a surface, and
	# this one is not meant to read as one.
	sun.shadow_enabled = false
	root.add_child(sun)

	root.add_child(_environment())

	var spawn := Marker3D.new()
	spawn.name = "SpawnPoint"
	spawn.set_script(load("res://scripts/level/spawn_point.gd"))
	spawn.position = lesson.spawn
	root.add_child(spawn)

	root.add_child(_floor())

	# BEFORE anything that reads player.move_manager. Siblings run _ready() in
	# tree order, so a node placed above Player would find no manager to
	# connect to. Nothing here does, but the order is the level's contract.
	var player: Node = load("res://scenes/player/player.tscn").instantiate()
	player.name = "Player"
	root.add_child(player)
	root.set("player", player)
	root.set("spawn_point", spawn)

	var content := Node3D.new()
	content.name = "Content"
	root.add_child(content)
	for block in lesson.blocks:
		content.add_child(_block(block))

	_claim(root)

	var packed := PackedScene.new()
	var pack_error := packed.pack(root)
	assert(pack_error == OK, "pack failed: %d" % pack_error)
	var path: String = "%s/%s.tscn" % [OUT_DIR, lesson.file]
	var save_error := ResourceSaver.save(packed, path)
	assert(save_error == OK, "save failed: %d" % save_error)
	print("wrote ", path)

func _environment() -> WorldEnvironment:
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	var environment := Environment.new()
	var sky_material := ProceduralSkyMaterial.new()
	# THE HORIZON PAIR MUST MATCH. Sky and ground meeting at the same value is
	# what deletes the horizon; the gradient lives above and below it.
	sky_material.sky_horizon_color = PALE
	sky_material.ground_horizon_color = PALE
	sky_material.sky_top_color = COOL
	sky_material.ground_bottom_color = COOL
	sky_material.sun_angle_max = 0.0
	sky_material.sun_curve = 0.0
	var sky := Sky.new()
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.223529, 0.466667, 0.741176)
	# The acrylic ground is glossy; without this it reflects nothing.
	environment.ssr_enabled = true
	environment.ssr_max_steps = 32
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	world_env.environment = environment
	return world_env

func _floor() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Floor"
	body.position = Vector3(0.0, -FLOOR_THICKNESS * 0.5, 0.0)
	var size := Vector3(FLOOR_SPAN, FLOOR_THICKNESS, FLOOR_SPAN)

	var shape := CollisionShape3D.new()
	shape.name = "Collision"
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	# THE SHARED ACRYLIC PRESET, not a fresh material: a lesson should look
	# like the level it is going to be dropped into.
	mesh_instance.material_override = load("res://materials/acrylic_void.tres")
	body.add_child(mesh_instance)
	return body

## One block: collision, and a swarm INSTEAD OF a mesh. The swarm is the only
## visible geometry, so nothing is drawn twice while it comes apart.
func _block(block: Dictionary) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = block.name
	body.position = block.at

	var shape := CollisionShape3D.new()
	shape.name = "Collision"
	var box := BoxShape3D.new()
	box.size = block.size
	shape.shape = box
	body.add_child(shape)

	var swarm := MultiMeshInstance3D.new()
	swarm.name = "Swarm"
	swarm.set_script(load("res://scripts/level/cube_swarm.gd"))
	swarm.set("box_size", block.size)
	swarm.set("base_color", block.colour)
	body.add_child(swarm)
	return body

## Hands every descendant of the scene root its ownership. Godot only
## serialises a node whose owner is the scene root, and a node cannot be given
## one before it is inside that root's tree -- so this runs once, at the end,
## over the assembled tree. Nodes that already have an owner (an instanced
## sub-scene's children) are left alone.
func _claim(node: Node) -> void:
	for child in node.get_children():
		if child.owner == null:
			child.owner = _root
		_claim(child)
```

- [ ] **Step 4: 跑生成器**

```sh
.engine/Godot_v4.7.1-stable_macos.universal.app/Contents/MacOS/Godot \
    --headless --path . --script res://tools/build_level_0_lessons.gd
```

Expected: 四行 `wrote res://scenes/levels/level_0/lesson_*.tscn`，退出码 0。输出里不该有
`SCRIPT ERROR`。

- [ ] **Step 5: 跑测试确认通过**

```sh
bun tools/run_tests.ts level_0_lessons
```

Expected: PASS，3 passing。

- [ ] **Step 6: 引用完整性检查**

```sh
.engine/Godot_v4.7.1-stable_macos.universal.app/Contents/MacOS/Godot \
    --headless --script res://tools/check_references.gd
```

Expected: 没有报告缺失的 ext_resource。

- [ ] **Step 7: 提交**

```sh
ls tools/build_level_0_lessons.gd.uid tests/test_level_0_lessons.gd.uid
git add tools/build_level_0_lessons.gd tools/build_level_0_lessons.gd.uid \
        scenes/levels/level_0/lesson_vault.tscn \
        scenes/levels/level_0/lesson_slide.tscn \
        scenes/levels/level_0/lesson_wall_run.tscn \
        scenes/levels/level_0/lesson_grab.tscn \
        tests/test_level_0_lessons.gd tests/test_level_0_lessons.gd.uid
git commit -m "feat(level0): four lesson scenes, each playable on its own"
```

---

## Task 8: 螺旋塔

**Files:**
- Create: `scripts/level/spiral_tower.gd`
- Create: `tools/build_level_0_tower.gd`
- Create（生成物）: `scenes/levels/level_0/tower.tscn`
- Create: `tests/test_spiral_tower.gd`

**Interfaces:**
- Consumes: `Checkpoint`（`scripts/level/checkpoint.gd`）
- Produces:
  - `class_name SpiralTower extends RefCounted`
  - `const SpiralTower.DEFAULT_SHAPE: Dictionary`（`turns` / `radius` / `rise_per_turn` / `platform_length` / `platform_width` / `gap` / `thickness`）
  - `static func SpiralTower.per_turn(shape: Dictionary) -> int`
  - `static func SpiralTower.platform_count(shape: Dictionary) -> int`
  - `static func SpiralTower.platform_origin(shape: Dictionary, index: int) -> Vector3`
  - `static func SpiralTower.platform_yaw(shape: Dictionary, index: int) -> float`
  - `static func SpiralTower.summit_origin(shape: Dictionary) -> Vector3`
  - `scenes/levels/level_0/tower.tscn`，根节点 `Tower`（Node3D），子节点 `Platform%02d`、`Checkpoint%02d`、`Orb`（Area3D）

- [ ] **Step 1: 写下会失败的测试**

创建 `tests/test_spiral_tower.gd`：

```gdscript
extends ParkourTest

# The tower's SHAPE is arithmetic, and only the arithmetic is asserted. How
# many turns, how wide the gaps and how tall the rise are the author's, and
# nothing here pins any of them.

const TOWER := "res://scenes/levels/level_0/tower.tscn"

func test_the_spiral_goes_up() -> void:
	# A height derived from the wrong index gives a flat ring: it still looks
	# like a tower in the file, it still passes a count check, and the player
	# walks round and round arriving nowhere.
	var shape := SpiralTower.DEFAULT_SHAPE
	var previous: float = -INF
	for i in SpiralTower.platform_count(shape):
		var height: float = SpiralTower.platform_origin(shape, i).y
		assert_gt(height, previous,
			"platform %d does not stand higher than the one below it" % i)
		previous = height

func test_a_wider_gap_puts_fewer_platforms_on_a_turn() -> void:
	# Catches a per_turn() that ignores its arguments -- a hardcoded count
	# looks right at the default shape and stops responding to every dial.
	var tight := SpiralTower.DEFAULT_SHAPE.duplicate()
	var loose := SpiralTower.DEFAULT_SHAPE.duplicate()
	tight.gap = 1.0
	loose.gap = 12.0
	assert_gt(SpiralTower.per_turn(tight), SpiralTower.per_turn(loose),
		"widening the gap did not thin out the platforms")

func test_the_summit_is_above_the_last_platform() -> void:
	# The orb hangs at the summit. Below the top platform it is unreachable
	# from the tower and the level has no ending.
	var shape := SpiralTower.DEFAULT_SHAPE
	var last: int = SpiralTower.platform_count(shape) - 1
	assert_gt(SpiralTower.summit_origin(shape).y,
		SpiralTower.platform_origin(shape, last).y,
		"the summit is not above the top platform")

func test_every_platform_wears_the_same_material() -> void:
	# A pipeline is compiled the first time a material is actually DRAWN. One
	# material per platform means one compiled pipeline per reveal, and the
	# symptom is a single dropped frame on one particular lap.
	var tower: Node = load(TOWER).instantiate()
	var shared: Material = null
	var seen := 0
	for mesh in tower.find_children("*", "MeshInstance3D", true, false):
		if not (mesh.get_parent().name as String).begins_with("Platform"):
			continue
		seen += 1
		if shared == null:
			shared = mesh.material_override
		assert_eq(mesh.material_override, shared,
			"%s carries a material of its own" % mesh.get_parent().name)
	assert_gt(seen, 0, "the tower scene has no platforms")
	tower.free()

func test_the_tower_carries_a_checkpoint_at_its_base() -> void:
	# The base checkpoint is what the floor's disappearance hangs off, and it
	# is the only thing standing between a fall and restarting the whole level.
	var tower: Node = load(TOWER).instantiate()
	var base := tower.get_node_or_null("Checkpoint00")
	assert_not_null(base, "the tower has no Checkpoint00 at its base")
	assert_gt(base.find_children("*", "CollisionShape3D", true, false).size(), 0,
		"the base checkpoint has no shape, so nothing can enter it")
	tower.free()

func test_the_tower_carries_an_orb_at_its_summit() -> void:
	# The orb is the level's only exit. Without it the player climbs to the
	# top of a tower and there is nothing there.
	var tower: Node = load(TOWER).instantiate()
	var orb := tower.get_node_or_null("Orb")
	assert_not_null(orb, "the tower has no Orb")
	assert_true(orb is Area3D, "the Orb is not an Area3D, so it cannot be touched")
	tower.free()
```

- [ ] **Step 2: 跑测试确认它失败**

```sh
bun tools/run_tests.ts spiral_tower
```

Expected: FAIL，`Identifier "SpiralTower" not declared`。

- [ ] **Step 3: 写形状**

创建 `scripts/level/spiral_tower.gd`：

```gdscript
class_name SpiralTower
extends RefCounted

# The tutorial tower's shape, as arithmetic. tools/build_level_0_tower.gd
# generates the .tscn from these functions; nothing places a platform by hand,
# so re-proportioning the whole tower is a change to five numbers.
#
# THE SHORT TOWER IS THE POINT. Every extra turn is cheap to add and its cost
# only shows up after the player has already formed his first impression of
# what this game is. Turns few rather than many.
#
# A PLATFORM'S ORIGIN IS ITS RUNNING SURFACE, not the centre of its slab, so
# platform 0 sits flush with the plain and stepping onto the tower is a step
# rather than a hop.

## The shipped proportions. Named fields; see naming-config-fields.
##   turns            how many times round
##   radius           metres from the axis to a platform's centre
##   rise_per_turn    metres gained each time round
##   platform_length  metres along the direction of travel
##   platform_width   metres across it
##   gap              metres of nothing between one platform and the next
##   thickness        metres of slab under the running surface
const DEFAULT_SHAPE := {
	turns = 3,
	radius = 9.0,
	rise_per_turn = 6.0,
	platform_length = 5.0,
	platform_width = 3.0,
	gap = 2.2,
	thickness = 0.4,
}

## Platforms on one turn, rounded so they close the circle exactly. THE GAP IS
## THEREFORE HONOURED ONLY TO WITHIN THAT ROUNDING -- which is what a spiral
## that has to meet itself costs. Never fewer than three, or the "circle" is a
## line.
static func per_turn(shape: Dictionary) -> int:
	var spacing: float = float(shape.platform_length) + float(shape.gap)
	return maxi(3, int(round(TAU * float(shape.radius) / maxf(spacing, 0.001))))

static func platform_count(shape: Dictionary) -> int:
	return int(shape.turns) * per_turn(shape)

## The centre of platform `index`'s running surface, in the tower's own space.
static func platform_origin(shape: Dictionary, index: int) -> Vector3:
	var count: float = float(per_turn(shape))
	var angle: float = TAU * float(index) / count
	var height: float = float(shape.rise_per_turn) * float(index) / count
	return Vector3(cos(angle) * float(shape.radius), height,
		sin(angle) * float(shape.radius))

## Which way platform `index` runs: tangential, so a body crossing it is
## already pointed at the next one.
static func platform_yaw(shape: Dictionary, index: int) -> float:
	return -TAU * float(index) / float(per_turn(shape))

## Where the orb hangs: over the axis, clear of the top platform.
static func summit_origin(shape: Dictionary) -> Vector3:
	return Vector3(0.0, float(shape.rise_per_turn) * float(shape.turns) + 4.0, 0.0)
```

- [ ] **Step 4: 写生成器**

创建 `tools/build_level_0_tower.gd`：

```gdscript
extends SceneTree

# Generates scenes/levels/level_0/tower.tscn from SpiralTower's arithmetic.
#
# ONE MATERIAL FOR EVERY PLATFORM. A material's GPU pipeline is compiled the
# first time it is actually drawn, so a platform with a material of its own
# costs a frame the moment it comes into view -- and the symptom is "only the
# seventh lap stutters". DO NOT give a platform a special material.
#
# Run with:
#   .engine/Godot_v4.7.1-stable_macos.universal.app/Contents/MacOS/Godot \
#       --headless --path . --script res://tools/build_level_0_tower.gd

const OUTPUT := "res://scenes/levels/level_0/tower.tscn"

## The lit end of the palette; the same near-white the plain is.
const PALE := Color(0.93, 0.96, 0.98)
## The orb: the one bright thing in the level, and the way out of it.
const ORB_COLOUR := Color(1.0, 0.98, 0.92)
const ORB_RADIUS := 1.2
## Reach, not size: the ball a body has to touch is bigger than the ball it
## can see, so the ending is not a pixel-perfect landing.
const ORB_REACH := 2.2

var _root: Node3D

func _initialize() -> void:
	var shape := SpiralTower.DEFAULT_SHAPE
	var root := Node3D.new()
	root.name = "Tower"
	_root = root

	var surface := StandardMaterial3D.new()
	surface.resource_name = "TowerSurface"
	surface.albedo_color = PALE
	surface.metallic = 0.2
	surface.roughness = 0.35

	var per_turn: int = SpiralTower.per_turn(shape)
	for index in SpiralTower.platform_count(shape):
		root.add_child(_platform(shape, index, surface))
		if index % per_turn == 0:
			root.add_child(_checkpoint(shape, index, index / per_turn))

	root.add_child(_orb(shape))

	# OWNERSHIP IS CLAIMED ONCE, OVER THE ASSEMBLED TREE. Godot only serialises
	# a node whose owner is the scene root, and a node cannot be given an owner
	# before it is inside that root's tree.
	_claim(root)

	DirAccess.make_dir_recursive_absolute("res://scenes/levels/level_0")
	var packed := PackedScene.new()
	var pack_error := packed.pack(root)
	assert(pack_error == OK, "pack failed: %d" % pack_error)
	var save_error := ResourceSaver.save(packed, OUTPUT)
	assert(save_error == OK, "save failed: %d" % save_error)
	print("wrote ", OUTPUT)
	quit(0)

func _platform(shape: Dictionary, index: int, surface: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Platform%02d" % index
	var size := Vector3(float(shape.platform_length), float(shape.thickness),
		float(shape.platform_width))
	# The origin SpiralTower reports is the running surface, so the slab hangs
	# below it.
	body.position = SpiralTower.platform_origin(shape, index) \
		- Vector3(0.0, float(shape.thickness) * 0.5, 0.0)
	body.rotation = Vector3(0.0, SpiralTower.platform_yaw(shape, index), 0.0)

	var shape_node := CollisionShape3D.new()
	shape_node.name = "Collision"
	var box := BoxShape3D.new()
	box.size = size
	shape_node.shape = box
	body.add_child(shape_node)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	# ON THE NODE, not on the mesh: material_override is a top-level property,
	# and reaching a material through Mesh in the inspector takes the editor
	# down (see .claude/skills/authoring-godot-scene-files).
	mesh_instance.material_override = surface
	body.add_child(mesh_instance)
	return body

## One checkpoint per turn. Ranked so a fall back through the ones already
## climbed cannot undo the climb; numbered in tens so a point can be inserted
## later without renumbering.
func _checkpoint(shape: Dictionary, index: int, turn: int) -> Area3D:
	var area := Area3D.new()
	area.name = "Checkpoint%02d" % index
	area.set_script(load("res://scripts/level/checkpoint.gd"))
	area.set("index", (turn + 1) * 10)
	area.set("display_name", "塔 第%d圈" % (turn + 1))
	# Origin = BODY CENTRE, the convention Checkpoint and SpawnPoint share.
	area.position = SpiralTower.platform_origin(shape, index) + Vector3(0.0, 0.95, 0.0)
	area.rotation = Vector3(0.0, SpiralTower.platform_yaw(shape, index), 0.0)

	var shape_node := CollisionShape3D.new()
	shape_node.name = "Collision"
	var box := BoxShape3D.new()
	box.size = Vector3(float(shape.platform_length), 2.4, float(shape.platform_width))
	shape_node.shape = box
	area.add_child(shape_node)
	return area

func _orb(shape: Dictionary) -> Area3D:
	var area := Area3D.new()
	area.name = "Orb"
	area.position = SpiralTower.summit_origin(shape)

	var shape_node := CollisionShape3D.new()
	shape_node.name = "Collision"
	var sphere := SphereShape3D.new()
	sphere.radius = ORB_REACH
	shape_node.shape = sphere
	area.add_child(shape_node)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	var mesh := SphereMesh.new()
	mesh.radius = ORB_RADIUS
	mesh.height = ORB_RADIUS * 2.0
	mesh_instance.mesh = mesh
	var material := StandardMaterial3D.new()
	# UNSHADED AND EMISSIVE. The orb is a light, not a lit object -- a shaded
	# ball in a shadowless level reads as a prop.
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = ORB_COLOUR
	material.emission_enabled = true
	material.emission = ORB_COLOUR
	material.emission_energy_multiplier = 3.0
	mesh_instance.material_override = material
	area.add_child(mesh_instance)

	var light := OmniLight3D.new()
	light.name = "Glow"
	light.light_color = ORB_COLOUR
	light.omni_range = 24.0
	light.light_energy = 3.0
	light.shadow_enabled = false
	area.add_child(light)
	return area

func _claim(node: Node) -> void:
	for child in node.get_children():
		if child.owner == null:
			child.owner = _root
		_claim(child)
```

- [ ] **Step 5: 跑生成器**

```sh
.engine/Godot_v4.7.1-stable_macos.universal.app/Contents/MacOS/Godot \
    --headless --path . --script res://tools/build_level_0_tower.gd
```

Expected: `wrote res://scenes/levels/level_0/tower.tscn`，退出码 0，输出无 `SCRIPT ERROR`。

- [ ] **Step 6: 跑测试确认通过**

```sh
bun tools/run_tests.ts spiral_tower
```

Expected: PASS，6 passing。

- [ ] **Step 7: 提交**

```sh
ls scripts/level/spiral_tower.gd.uid tools/build_level_0_tower.gd.uid tests/test_spiral_tower.gd.uid
git add scripts/level/spiral_tower.gd scripts/level/spiral_tower.gd.uid \
        tools/build_level_0_tower.gd tools/build_level_0_tower.gd.uid \
        scenes/levels/level_0/tower.tscn \
        tests/test_spiral_tower.gd tests/test_spiral_tower.gd.uid
git commit -m "feat(level0): generate the spiral tower from its own arithmetic"
```

---

## Task 9: 「感谢试玩」页

**Files:**
- Create: `scripts/ui/thanks_screen.gd`
- Create: `scenes/ui/thanks_for_playing.tscn`
- Create: `tests/test_thanks_screen.gd`

**Interfaces:**
- Consumes: `MeTheme.ui_theme()` / `MeTheme.footer_label()` / `MeTheme.dress_over_anything()` / `MeTheme.paper_noise_layer()`、`PauseUi.run_white_transition(packed, fade_in)`
- Produces:
  - `class_name ThanksScreen extends Control`
  - `ThanksScreen.MAIN_MENU_SCENE: String`
  - `ThanksScreen._change_scene: Callable`（测试用的接缝，形状同 `MainMenu._change_scene`）
  - `scenes/ui/thanks_for_playing.tscn`

- [ ] **Step 1: 写下会失败的测试**

创建 `tests/test_thanks_screen.gd`：

```gdscript
extends ParkourTest

# The last screen of the tutorial. One thing is asserted, and it is the only
# thing that can go catastrophically wrong: a dead end.

func test_a_key_press_leaves_for_the_main_menu() -> void:
	# A screen with no way off it strands the player at the end of the one
	# path the whole feature exists to complete.
	var screen := ThanksScreen.new()
	add_child_autofree(screen)
	await step(1)
	var requested := [""]
	screen._change_scene = func(path): requested[0] = path

	var key := InputEventKey.new()
	key.physical_keycode = KEY_SPACE
	key.pressed = true
	key.echo = false
	screen._unhandled_input(key)
	await step(1)

	assert_eq(requested[0], ThanksScreen.MAIN_MENU_SCENE,
		"the thanks page did not ask for the main menu")

func test_a_second_press_does_not_ask_twice() -> void:
	# The white transition spans several frames, and a second scene change
	# requested underneath one already in flight swaps the tree twice.
	var screen := ThanksScreen.new()
	add_child_autofree(screen)
	await step(1)
	var asked := [0]
	screen._change_scene = func(_path): asked[0] += 1

	var key := InputEventKey.new()
	key.physical_keycode = KEY_SPACE
	key.pressed = true
	key.echo = false
	screen._unhandled_input(key)
	screen._unhandled_input(key)
	await step(1)

	assert_eq(asked[0], 1, "the thanks page asked to leave %d times" % asked[0])
```

- [ ] **Step 2: 跑测试确认它失败**

```sh
bun tools/run_tests.ts thanks_screen
```

Expected: FAIL，`Identifier "ThanksScreen" not declared`。

- [ ] **Step 3: 写实现**

创建 `scripts/ui/thanks_screen.gd`：

```gdscript
class_name ThanksScreen
extends Control

# The end of the tutorial: a held card, then back to the front door. Built in
# code like every other screen in this project (pause_ui.gd, settings_menu.gd,
# main_menu.gd); scenes/ui/thanks_for_playing.tscn is a one-node root with this
# script attached.
#
# THIS SCENE IS NEITHER A LEVEL NOR THE MAIN MENU, and two things that every
# other screen gets for free therefore have to be said here:
#
#   The mouse. Only MainMenu._ready() and Arena.capture_mouse set the mode, so
#   arriving here from a level would leave the cursor captured.
#
#   Esc. PauseUi's own guard exempts the main menu by type, not this, so Esc
#   would open a pause menu over a scene with no player -- every row of which
#   does nothing. Esc is treated as "leave" instead, and consumed.

const MAIN_MENU_SCENE := "res://scenes/ui/main_menu.tscn"

## Seam for the exit, same shape as MainMenu._change_scene: a test can observe
## the request without a real change_scene_to_file() swapping GUT's own runner
## scene out mid-suite.
var _change_scene: Callable = Callable(self, "_real_change_scene")

## Set the moment leaving starts. The white transition spans several frames,
## and a second request underneath one already in flight swaps the tree twice.
var _leaving: bool = false

func _real_change_scene(path: String) -> void:
	get_tree().change_scene_to_file(path)

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = MeTheme.ui_theme()
	# The ROOT must not eat clicks: a full-rect Control defaults to
	# MOUSE_FILTER_STOP and would consume every press as GUI input before
	# _unhandled_input ever saw it.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()

func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color(0.96, 0.96, 0.94)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	add_child(MeTheme.paper_noise_layer())

	var title := Label.new()
	title.text = "感谢试玩"
	title.add_theme_font_size_override("font_size", 64)
	MeTheme.dress_over_anything(title)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_left = 0.0
	title.anchor_right = 1.0
	title.anchor_top = 0.42
	title.anchor_bottom = 0.42
	title.offset_bottom = 90.0
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)

	var line := Label.new()
	line.text = "她还在跑。"
	line.add_theme_font_size_override("font_size", 22)
	MeTheme.dress_over_anything(line)
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.anchor_left = 0.0
	line.anchor_right = 1.0
	line.anchor_top = 0.56
	line.anchor_bottom = 0.56
	line.offset_bottom = 40.0
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(line)

	add_child(MeTheme.footer_label("按任意键返回主菜单"))

func _unhandled_input(event: InputEvent) -> void:
	var is_key_press := event is InputEventKey \
		and (event as InputEventKey).pressed and not (event as InputEventKey).echo
	var is_click := event is InputEventMouseButton \
		and (event as InputEventMouseButton).pressed
	if not (is_key_press or is_click):
		return
	get_viewport().set_input_as_handled()
	_leave()

func _leave() -> void:
	if _leaving:
		return
	_leaving = true
	# Normal transitions are WHITE (the transition-colour convention; black is
	# reserved for a death). Headless keeps the bare seam for the tests.
	if DisplayServer.get_name() == "headless":
		_change_scene.call(MAIN_MENU_SCENE)
		return
	PauseUi.run_white_transition(load(MAIN_MENU_SCENE), 0.5)
```

- [ ] **Step 4: 写场景**

创建 `scenes/ui/thanks_for_playing.tscn`。**不要编造 `uid://`** —— 省略该字段，引擎自己会
在导入时分配：

```
[gd_scene format=3]

[ext_resource type="Script" path="res://scripts/ui/thanks_screen.gd" id="1_thanks"]

[node name="ThanksScreen" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
script = ExtResource("1_thanks")
```

- [ ] **Step 5: 跑测试确认通过**

```sh
bun tools/run_tests.ts thanks_screen
```

Expected: PASS，2 passing。搜 `SCRIPT ERROR` —— `MeTheme` 的某个工厂名字打错只会打印引擎
错误，不会红。

- [ ] **Step 6: 验证场景真的能加载**

**不要读文件确认，要加载它**（`.claude/skills/authoring-godot-scene-files`）：

```sh
.engine/Godot_v4.7.1-stable_macos.universal.app/Contents/MacOS/Godot \
    --headless --script res://tools/check_references.gd
```

Expected: 没有 `invalid UID` / 缺失 ext_resource 的报告。

- [ ] **Step 7: 提交**

```sh
ls scripts/ui/thanks_screen.gd.uid tests/test_thanks_screen.gd.uid
git add scripts/ui/thanks_screen.gd scripts/ui/thanks_screen.gd.uid \
        scenes/ui/thanks_for_playing.tscn \
        tests/test_thanks_screen.gd tests/test_thanks_screen.gd.uid
git commit -m "feat(ui): a thanks-for-playing page that leads back to the menu"
```

---

## Task 10: `LevelZero` —— 塔升起、地板解体、光球通关

**Files:**
- Create: `scripts/level/level_zero.gd`
- Create: `tests/test_level_zero.gd`

**Interfaces:**
- Consumes: `TutorialDirector.finished`、`TorusWrap`、`Checkpoint`（`Area3D.body_entered`）、
  `ProgressStore.mark_tutorial_finished()`（Task 1）、`ThanksScreen`（Task 9 的场景路径）、
  `PauseUi.run_white_transition(packed, fade_in)`
- Produces:
  - `class_name LevelZero extends Node`
  - `@export player: Player` / `director: TutorialDirector` / `wrap: TorusWrap` / `tower: Node3D` /
    `tower_checkpoint: Area3D` / `orb: Area3D` / `plain: StaticBody3D` /
    `plain_mesh: MeshInstance3D` / `plain_collision: CollisionShape3D`
  - `@export tower_distance: float` / `void_colour: Color` / `floor_fade_time: float` /
    `floor_drop_time: float` / `floor_drop_depth: float` / `floor_dots_remaining: float`
  - `LevelZero.THANKS_SCENE: String`
  - `LevelZero._change_scene: Callable`
  - `func raise_tower() -> void`

- [ ] **Step 1: 写下会失败的测试**

创建 `tests/test_level_zero.gd`：

```gdscript
extends ParkourTest

# The tutorial's own chain: the tower is not there, then it is; reaching it
# retires the wrap; touching the orb records the run and leaves. What any of
# it LOOKS like is asserted nowhere.

var _test_progress: String
var _real_progress: String

func before_all() -> void:
	_test_progress = "user://progress_test_%d.cfg" % OS.get_process_id()
	_real_progress = ProgressStore.path
	ProgressStore.path = _test_progress

func after_all() -> void:
	_delete_progress()
	ProgressStore.path = _real_progress

func before_each() -> void:
	_delete_progress()

func after_each() -> void:
	_delete_progress()

func _delete_progress() -> void:
	if FileAccess.file_exists(ProgressStore.path):
		DirAccess.remove_absolute(ProgressStore.path)

## A LevelZero with just enough around it: a tower with one solid slab in it,
## a wrap, and a plain whose collision can be watched.
func _level() -> Dictionary:
	var level := LevelZero.new()

	var tower := Node3D.new()
	tower.name = "Tower"
	var slab := StaticBody3D.new()
	slab.name = "Platform00"
	slab.collision_layer = 1
	tower.add_child(slab)
	level.tower = tower

	var wrap := TorusWrap.new()
	wrap.name = "TorusWrap"
	level.wrap = wrap

	var plain := StaticBody3D.new()
	plain.name = "Plain"
	var collision := CollisionShape3D.new()
	collision.shape = BoxShape3D.new()
	plain.add_child(collision)
	level.plain = plain
	level.plain_collision = collision

	var orb := Area3D.new()
	orb.name = "Orb"
	level.orb = orb

	var checkpoint := Area3D.new()
	checkpoint.name = "Checkpoint00"
	level.tower_checkpoint = checkpoint

	add_child_autofree(tower)
	add_child_autofree(wrap)
	add_child_autofree(plain)
	add_child_autofree(orb)
	add_child_autofree(checkpoint)
	add_child_autofree(level)
	await step(1)
	return {level = level, tower = tower, slab = slab, wrap = wrap,
		plain = plain, collision = collision, orb = orb, checkpoint = checkpoint}

func test_a_tower_that_is_not_there_yet_is_also_intangible() -> void:
	# HIDING IS NOT ENOUGH. The tower stands where the lessons are taught, so a
	# tower that is merely invisible is an invisible wall in the middle of the
	# plain -- and the player has no way to understand what he just ran into.
	var live: Dictionary = await _level()
	assert_false((live.tower as Node3D).visible, "the tower is visible before it rises")
	assert_eq((live.slab as StaticBody3D).collision_layer, 0,
		"the hidden tower is still solid")

func test_raising_the_tower_gives_it_back_its_collision() -> void:
	# The other half of the same bug: a tower that comes back visible but not
	# solid drops the player straight through the thing he just climbed onto.
	var live: Dictionary = await _level()
	(live.level as LevelZero).raise_tower()
	await step(1)
	assert_true((live.tower as Node3D).visible, "the tower did not become visible")
	assert_eq((live.slab as StaticBody3D).collision_layer, 1,
		"the raised tower did not get its collision layer back")

func test_reaching_the_tower_retires_the_wrap() -> void:
	# A wrap still running while the player is on the tower teleports him off
	# it the moment he crosses a period boundary in mid-climb.
	var live: Dictionary = await _level()
	var level: LevelZero = live.level
	level._on_tower_reached(null)
	await step(1)
	assert_false((live.wrap as TorusWrap).is_physics_processing(),
		"the wrap is still running after the tower was reached")

func test_touching_the_orb_records_the_tutorial_and_leaves() -> void:
	# Both halves matter and both are invisible when they fail: without the
	# record the player can never reach the main menu, and without the scene
	# change he stands on the summit with nothing happening.
	var live: Dictionary = await _level()
	var level: LevelZero = live.level
	var requested := [""]
	level._change_scene = func(path): requested[0] = path
	level._on_orb_entered(null)
	await step(1)
	assert_true(ProgressStore.tutorial_finished(),
		"reaching the orb did not record the tutorial as finished")
	assert_eq(requested[0], LevelZero.THANKS_SCENE,
		"reaching the orb did not ask for the thanks page")

func test_the_orb_only_ends_the_level_once() -> void:
	# The orb's volume is bigger than the ball, so a body drifting through it
	# can report more than one entry; a second white transition on top of the
	# first swaps the tree twice.
	var live: Dictionary = await _level()
	var level: LevelZero = live.level
	var asked := [0]
	level._change_scene = func(_path): asked[0] += 1
	level._on_orb_entered(null)
	level._on_orb_entered(null)
	await step(1)
	assert_eq(asked[0], 1, "the orb ended the level %d times" % asked[0])
```

- [ ] **Step 2: 跑测试确认它失败**

```sh
bun tools/run_tests.ts level_zero
```

Expected: FAIL，`Identifier "LevelZero" not declared`。

- [ ] **Step 3: 写实现**

创建 `scripts/level/level_zero.gd`：

```gdscript
class_name LevelZero
extends Node

# The tutorial's own chain, and nothing else: the lessons run out, the tower
# stands up, stepping onto it takes the plain away, and the orb at the top ends
# the level. Everything below this is either Arena's or TutorialDirector's.
#
# THE TOWER APPEARS IN FRONT OF THE BODY, not at a fixed spot. The plain is a
# torus: a body that has crossed a few boundaries is nowhere in particular, and
# a tower nailed to the world origin would ALSO give the wrap away, because
# every crossing would jump it a whole period sideways in his view. Standing it
# up where he is looking, at the moment the wrap retires, costs nothing and
# removes both problems.
#
# THE FLOOR DOES NOT USE THE CUBE SWARM. It is hundreds of metres across and
# would voxelise into millions of instances. It leaves the way the spec asks
# for instead: the sheet is painted the colour of the void behind it, which
# takes its surface away while its dot field is still there, and then the whole
# slab sinks -- so the light the floor turned into is still in view, further
# away every second, and reads as an altimeter. DO NOT reach for CubeSwarm here.

## Where the thanks page lives. The first level does not exist yet, so this is
## the tutorial's landing spot.
const THANKS_SCENE := "res://scenes/ui/thanks_for_playing.tscn"

@export var player: Player
@export var director: TutorialDirector
@export var wrap: TorusWrap
## The whole tower, hidden and intangible until the lessons run out.
@export var tower: Node3D
## The checkpoint at the tower's foot. Touching it is what starts the floor
## leaving -- one node, two consumers, so the save and the show cannot disagree
## about when the climb began.
@export var tower_checkpoint: Area3D
## The light at the summit. Touching it ends the level.
@export var orb: Area3D
@export var plain: StaticBody3D
@export var plain_mesh: MeshInstance3D
@export var plain_collision: CollisionShape3D

## How far ahead of the body the tower stands up. Far enough to see all of it,
## near enough to run to. Tuning value.
@export var tower_distance: float = 45.0

## What the sheet is painted as it goes: the colour of the void behind it, so
## a floor painted this has no edge left. Tuning value -- keep it equal to the
## level's own horizon colour.
@export var void_colour: Color = Color(0.93, 0.96, 0.98)

## Seconds the surface takes to go. Tuning value.
@export var floor_fade_time: float = 3.0
## Seconds the dot field takes to sink, and how far it sinks. Tuning values.
@export var floor_drop_time: float = 6.0
@export var floor_drop_depth: float = 90.0
## What is left of the dots at the bottom. Zero puts them out entirely; a
## little is what leaves the player something to read his height against.
@export var floor_dots_remaining: float = 0.12

## Seam for the exit, same shape as MainMenu._change_scene and
## ThanksScreen._change_scene: a test observes the request without a real
## scene swap under GUT's runner.
var _change_scene: Callable = Callable(self, "_real_change_scene")

## Each of the three beats happens exactly once. The orb's volume is wider than
## the ball, and a checkpoint reports every entry, so all three are reachable
## twice by an ordinary player.
var _tower_up: bool = false
var _floor_leaving: bool = false
var _finished: bool = false

## The collision layer each of the tower's bodies had before it was hidden.
## Remembered rather than assumed: guessing a layer number here would quietly
## move the whole tower onto a layer nothing collides with.
var _tower_layers: Dictionary = {}

func _real_change_scene(path: String) -> void:
	get_tree().change_scene_to_file(path)

func _ready() -> void:
	if director != null:
		director.finished.connect(raise_tower)
	if tower != null:
		_remember_tower_layers()
		_set_tower_solid(false)
	if tower_checkpoint != null:
		tower_checkpoint.body_entered.connect(_on_tower_reached)
	if orb != null:
		orb.body_entered.connect(_on_orb_entered)

func _remember_tower_layers() -> void:
	for body in tower.find_children("*", "CollisionObject3D", true, false):
		_tower_layers[body] = (body as CollisionObject3D).collision_layer

func _set_tower_solid(solid: bool) -> void:
	tower.visible = solid
	for body in _tower_layers:
		if not is_instance_valid(body):
			continue
		(body as CollisionObject3D).collision_layer = _tower_layers[body] if solid else 0

## The lessons ran out. The tower stands up in front of the body and the wrap
## retires -- the two are one event, because a tower standing on a plain that
## still wraps is a tower that jumps a period sideways every crossing.
func raise_tower() -> void:
	if _tower_up or tower == null:
		return
	_tower_up = true
	if wrap != null:
		wrap.set_physics_process(false)
	if player != null:
		var forward: Vector3 = -player.global_transform.basis.z
		forward.y = 0.0
		if forward.length() < 0.001:
			forward = Vector3.FORWARD
		var here: Vector3 = player.global_position
		tower.global_position = Vector3(here.x, 0.0, here.z) \
			+ forward.normalized() * tower_distance
	_set_tower_solid(true)

## The first step onto the tower. Everything below is taken away.
func _on_tower_reached(_body: Node3D) -> void:
	if _floor_leaving:
		return
	_floor_leaving = true
	# BELT TO raise_tower()'s BRACE. The wrap is retired when the tower goes
	# up; a level whose director never announced it still must not teleport a
	# climbing body.
	if wrap != null:
		wrap.set_physics_process(false)
	_dissolve_floor()

func _dissolve_floor() -> void:
	if plain_mesh == null or not (plain_mesh.material_override is ShaderMaterial):
		return
	# THE MATERIAL IS DUPLICATED FIRST. materials/acrylic_void.tres is shared
	# with the debug plain, and tweening the shared resource would repaint
	# every other scene that loads it in this session.
	var material := (plain_mesh.material_override as ShaderMaterial).duplicate() as ShaderMaterial
	plain_mesh.material_override = material
	var from_colour: Color = material.get_shader_parameter("base_color")
	var from_dots: float = float(material.get_shader_parameter("dot_opacity"))

	var tween := create_tween()
	# THE SURFACE GOES FIRST AND THE DOTS STAY. Painted the colour of the void
	# behind it, the sheet has no edge left; the dots are what the floor turns
	# into, so they are still there when it starts to fall.
	tween.tween_method(func(colour: Color) -> void:
		material.set_shader_parameter("base_color", colour),
		from_colour, void_colour, floor_fade_time)
	# NOT BEFORE THE FADE. The player is standing on the tower's first platform
	# by now, but a body still crossing the last few metres of plain must not
	# drop through it mid-stride. Deferred because a body may be resting on
	# this shape in the physics step that is running.
	tween.tween_callback(func() -> void:
		if plain_collision != null:
			plain_collision.set_deferred("disabled", true))
	if plain != null:
		tween.tween_property(plain, "position:y",
			plain.position.y - floor_drop_depth, floor_drop_time) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.parallel().tween_method(func(opacity: float) -> void:
		material.set_shader_parameter("dot_opacity", opacity),
		from_dots, floor_dots_remaining, floor_drop_time)

func _on_orb_entered(_body: Node3D) -> void:
	if _finished:
		return
	_finished = true
	ProgressStore.mark_tutorial_finished()
	# The replay request is spent the moment the tutorial is played again.
	ProgressStore.replay_requested = false
	if player != null:
		# The white spans several frames with the level still live underneath
		# it; nothing should be able to run off the summit during them.
		player.lock_input()
	# WHITE, per the transition-colour convention: this is a chosen ending, not
	# a death. Headless keeps the bare seam for the tests.
	if DisplayServer.get_name() == "headless":
		_change_scene.call(THANKS_SCENE)
		return
	PauseUi.run_white_transition(load(THANKS_SCENE), 0.9)
```

- [ ] **Step 4: 跑测试确认通过**

```sh
bun tools/run_tests.ts level_zero
```

Expected: PASS，5 passing。**读输出找 `SCRIPT ERROR`** —— 这个文件里有一堆
`get_shader_parameter` / `find_children` 调用，拼错只会打印。

- [ ] **Step 5: 提交**

```sh
ls scripts/level/level_zero.gd.uid tests/test_level_zero.gd.uid
git add scripts/level/level_zero.gd scripts/level/level_zero.gd.uid \
        tests/test_level_zero.gd tests/test_level_zero.gd.uid
git commit -m "feat(level0): tower, floor dissolve and the orb that ends the run"
```

---

## Task 11: 生成教程关本体

**Files:**
- Create: `tools/build_level_0.gd`
- Create（生成物）: `scenes/levels/level_0/level_0.tscn`
- Create: `tests/test_level_0.gd`

**Interfaces:**
- Consumes: 前面所有 Task 的产物 —— `Arena.start_in_third_person`、`CubeSwarm`、四个课程场景、
  `tower.tscn`、`LevelZero`、`TutorialDirector`、`TorusWrap`
- Produces: `scenes/levels/level_0/level_0.tscn`，根节点名 `Level0`

- [ ] **Step 1: 写下会失败的测试**

创建 `tests/test_level_0.gd`：

```gdscript
extends ParkourTest

# The tutorial level as a whole. Everything asserted here is a wiring fact
# whose failure is SILENT: an unresolved export or a lesson table that did not
# survive the scene file both leave a level that simply sits there.

const LEVEL := "res://scenes/levels/level_0/level_0.tscn"

var _level: Node

func after_each() -> void:
	if is_instance_valid(_level):
		_level.queue_free()
	_level = null

func _loaded() -> Node:
	var level: Node = load(LEVEL).instantiate()
	add_child_autofree(level)
	await step(2)
	_level = level
	return level

func test_the_level_starts_the_camera_behind_the_body() -> void:
	# The tutorial hands over control in third person. A level that came up in
	# first person would hand the player a view he never chose and no reason
	# to know V exists.
	var level: Node = await _loaded()
	assert_true(level.start_in_third_person,
		"level_0 does not declare start_in_third_person")
	assert_true(level.player.camera_rig.third_person,
		"level_0 did not actually start behind the body")

func test_the_lesson_table_survived_the_scene_file() -> void:
	# An exported Array[Dictionary] that does not round-trip through .tscn
	# leaves the director with nothing to teach. The level then never finishes,
	# the tower never rises, and no error is printed anywhere.
	var level: Node = await _loaded()
	var director: TutorialDirector = level.get_node("TutorialDirector")
	assert_false(director.lessons.is_empty(),
		"the exported lesson table did not survive the scene file")
	for row in director.lessons:
		assert_true(row.has(&"teaches"), "a lesson row lost its teaches field")
		var scene: PackedScene = row.get(&"scene")
		if scene == null:
			continue
		var content := LessonContent.take(scene)
		assert_not_null(content, "a lesson row points at a scene with no Content")
		content.free()

func test_level_zero_found_every_node_it_drives() -> void:
	# Node-path exports that point into an INSTANCED sub-scene are the fragile
	# ones here. Any of them coming back null makes the chain stop at that
	# link, with the level still perfectly playable up to it.
	var level: Node = await _loaded()
	var chain: LevelZero = level.get_node("LevelZero")
	assert_not_null(chain.player, "LevelZero has no player")
	assert_not_null(chain.director, "LevelZero has no director")
	assert_not_null(chain.wrap, "LevelZero has no wrap")
	assert_not_null(chain.tower, "LevelZero has no tower")
	assert_not_null(chain.tower_checkpoint, "LevelZero has no base checkpoint")
	assert_not_null(chain.orb, "LevelZero has no orb")
	assert_not_null(chain.plain, "LevelZero has no plain")
	assert_not_null(chain.plain_mesh, "LevelZero has no plain mesh")
	assert_not_null(chain.plain_collision, "LevelZero has no plain collision")

func test_the_director_and_the_wrap_both_have_the_body() -> void:
	# Both are wired by NodePath and both fail the same silent way: a director
	# with no player never hears a move happen, a wrap with no player never
	# wraps, and the level looks like a plain with nothing on it.
	var level: Node = await _loaded()
	assert_not_null((level.get_node("TutorialDirector") as TutorialDirector).player,
		"the director has no player, so no lesson can ever be passed")
	assert_not_null((level.get_node("TorusWrap") as TorusWrap).player,
		"the wrap has no player, so the plain has edges")

func test_the_tower_is_not_in_the_way_before_it_rises() -> void:
	# The lessons are taught on the ground the tower stands on. A tower that is
	# only hidden is an invisible wall in the middle of the teaching field.
	var level: Node = await _loaded()
	var tower: Node3D = level.get_node("Tower")
	assert_false(tower.visible, "the tower is visible before the lessons are done")
```

- [ ] **Step 2: 跑测试确认它失败**

```sh
bun tools/run_tests.ts test_level_0
```

Expected: FAIL —— 场景不存在。

> 注意过滤词用 `test_level_0`：`level_0` 会同时命中 `test_level_0_lessons.gd`，这里想单独跑。

- [ ] **Step 3: 写生成器**

创建 `tools/build_level_0.gd`：

```gdscript
extends SceneTree

# Generates scenes/levels/level_0/level_0.tscn: the tutorial.
#
# NO DEBUG SCAFFOLDING. RoamingProps and VoidProbe belong to
# scenes/debug_levels/void_plain.tscn, which exists so a wrap can be judged by
# hand -- scattered furniture in every direction is the OPPOSITE of what this
# level wants, which is one thing growing in front of the player at a time.
#
# NODE ORDER IS A CONTRACT. Siblings run _ready() in tree order, and both
# TutorialDirector and LevelZero reach into the Player during theirs, so both
# must come AFTER it. LevelZero comes last of all: it connects to the
# director's own signal.
#
# Run with:
#   .engine/Godot_v4.7.1-stable_macos.universal.app/Contents/MacOS/Godot \
#       --headless --path . --script res://tools/build_level_0.gd

const OUTPUT := "res://scenes/levels/level_0/level_0.tscn"
const LESSON_DIR := "res://scenes/levels/level_0"

## How far the player runs before the plain repeats him back. Tuning value; the
## only thing that depends on it is materials/acrylic_void.tres's phase_wrap,
## which must stay equal to PERIOD / its own dot spacing or every dot in sight
## changes its blink on a crossing.
const PERIOD := 100.0

## How far the camera draws. Free of the period: nothing out there is a copy of
## anything, so a long view exposes nothing.
const VIEW_DISTANCE := 240.0

## Wide enough that the body is always inside the centre period, so this only
## has to cover sight plus one period.
const FLOOR_SPAN := (VIEW_DISTANCE + PERIOD) * 2.0
const FLOOR_THICKNESS := 2.0

const PALE := Color(0.93, 0.96, 0.98)
const COOL := Color(0.78, 0.86, 0.93)

var _root: Node3D

func _initialize() -> void:
	var root := Node3D.new()
	root.name = "Level0"
	_root = root
	root.set_script(load("res://scripts/level/arena.gd"))
	root.set("config", load("res://presets/default.tres"))
	root.set("load_calibration_course", false)
	# SHE DOES NOT DIE HERE. Every route to a death becomes a white curtain and
	# a respawn at the highest checkpoint reached.
	root.set("rescue_below_hp", 30.0)
	root.set("view_distance", VIEW_DISTANCE)
	# The tutorial hands control over from behind the body. The preference, not
	# a pin: V still works, and nothing is written to disk.
	root.set("start_in_third_person", true)

	var fog := FogConfig.new()
	fog.resource_local_to_scene = true
	# FOG IS THE SEAM'S COVER, not weather. The end distance stays under the
	# far plane so geometry is already opaque by the time it reaches the cut --
	# otherwise things wink out at a fixed radius.
	fog.enabled = true
	fog.fade_begin_distance = VIEW_DISTANCE * 0.4
	fog.fade_end_distance = VIEW_DISTANCE * 0.95
	fog.max_opacity = 1.0
	# The horizon's own value, so anything the fog swallows arrives at exactly
	# the colour behind it.
	fog.tint = PALE
	root.set("fog", fog)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(-30.0), 0.0)
	# NO SHADOWS. She should look like she is standing on nothing; a cast
	# shadow is a statement that the void has a ground.
	sun.shadow_enabled = false
	root.add_child(sun)

	root.add_child(_environment())

	var spawn := Marker3D.new()
	spawn.name = "SpawnPoint"
	spawn.set_script(load("res://scripts/level/spawn_point.gd"))
	spawn.position = Vector3(0.0, 0.95, 25.0)
	root.add_child(spawn)

	var plain := _plain()
	root.add_child(plain)

	var player: Node = load("res://scenes/player/player.tscn").instantiate()
	player.name = "Player"
	root.add_child(player)
	root.set("player", player)
	root.set("spawn_point", spawn)

	var wrap := Node.new()
	wrap.name = "TorusWrap"
	wrap.set_script(load("res://scripts/level/torus_wrap.gd"))
	wrap.set("period", PERIOD)
	root.add_child(wrap)
	wrap.set("player", player)

	var director := Node.new()
	director.name = "TutorialDirector"
	director.set_script(load("res://scripts/level/tutorial_director.gd"))
	root.add_child(director)
	director.set("player", player)
	director.set("wrap", wrap)
	director.set("lessons", _lessons())

	var tower: Node = load("%s/tower.tscn" % LESSON_DIR).instantiate()
	tower.name = "Tower"
	root.add_child(tower)

	# LAST. It connects to the director's `finished` and reaches into the
	# tower's own children.
	var chain := Node.new()
	chain.name = "LevelZero"
	chain.set_script(load("res://scripts/level/level_zero.gd"))
	root.add_child(chain)
	chain.set("player", player)
	chain.set("director", director)
	chain.set("wrap", wrap)
	chain.set("tower", tower)
	chain.set("tower_checkpoint", tower.get_node("Checkpoint00"))
	chain.set("orb", tower.get_node("Orb"))
	chain.set("plain", plain)
	chain.set("plain_mesh", plain.get_node("Mesh"))
	chain.set("plain_collision", plain.get_node("Collision"))
	chain.set("void_colour", PALE)

	_claim(root)

	DirAccess.make_dir_recursive_absolute(LESSON_DIR)
	var packed := PackedScene.new()
	var pack_error := packed.pack(root)
	assert(pack_error == OK, "pack failed: %d" % pack_error)
	var save_error := ResourceSaver.save(packed, OUTPUT)
	assert(save_error == OK, "save failed: %d" % save_error)
	print("wrote ", OUTPUT)
	quit(0)

## The teaching order. One row per lesson; see TutorialDirector.lessons for the
## schema.
##
## ROW 0 HAS NO SCENE ON PURPOSE. The first stretch of this level is an empty
## plain and its whole job is that the player discovers he cannot fall off it
## and cannot reach the end of it. The first jump anywhere passes it.
func _lessons() -> Array[Dictionary]:
	return [
		{teaches = Move.JUMP, scene = null},
		{teaches = Move.SPEED_VAULT, scene = load("%s/lesson_vault.tscn" % LESSON_DIR)},
		{teaches = Move.SLIDE, scene = load("%s/lesson_slide.tscn" % LESSON_DIR)},
		{teaches = Move.WALL_RUN, scene = load("%s/lesson_wall_run.tscn" % LESSON_DIR)},
		{teaches = Move.GRAB, scene = load("%s/lesson_grab.tscn" % LESSON_DIR)},
	]

func _environment() -> WorldEnvironment:
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	var environment := Environment.new()
	# A SKY THAT IS ONE FLAT COLOUR, not the absence of one. The floor is
	# nearly a mirror and a metal surface has no colour of its own -- with no
	# radiance map every direction that misses geometry reflects black and the
	# white floor comes out charcoal. And sky and ground meeting at the same
	# value is what deletes the horizon.
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_horizon_color = PALE
	sky_material.ground_horizon_color = PALE
	sky_material.sky_top_color = COOL
	sky_material.ground_bottom_color = COOL
	# The sun disc is off: a bright spot in the sky is the one landmark this
	# level must not have.
	sky_material.sun_angle_max = 0.0
	sky_material.sun_curve = 0.0
	var sky := Sky.new()
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.223529, 0.466667, 0.741176)
	environment.ssr_enabled = true
	environment.ssr_max_steps = 32
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	world_env.environment = environment
	return world_env

## The plain. Named `Plain` rather than `Floor` because LevelZero takes it away
## and the node it drives should say which one it is.
func _plain() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Plain"
	body.position = Vector3(0.0, -FLOOR_THICKNESS * 0.5, 0.0)
	var size := Vector3(FLOOR_SPAN, FLOOR_THICKNESS, FLOOR_SPAN)

	var shape := CollisionShape3D.new()
	shape.name = "Collision"
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	# THE SHARED ACRYLIC PRESET. Its phase_wrap is already PERIOD / spacing,
	# which is what keeps every dot's blink from being replaced on a crossing.
	# LevelZero duplicates this material before it touches it.
	mesh_instance.material_override = load("res://materials/acrylic_void.tres")
	body.add_child(mesh_instance)
	return body

func _claim(node: Node) -> void:
	for child in node.get_children():
		if child.owner == null:
			child.owner = _root
		_claim(child)
```

- [ ] **Step 4: 跑生成器**

```sh
.engine/Godot_v4.7.1-stable_macos.universal.app/Contents/MacOS/Godot \
    --headless --path . --script res://tools/build_level_0.gd
```

Expected: `wrote res://scenes/levels/level_0/level_0.tscn`，退出码 0，输出无 `SCRIPT ERROR`。

- [ ] **Step 5: 跑测试确认通过**

```sh
bun tools/run_tests.ts test_level_0
```

Expected: PASS，5 passing。**读输出找 `SCRIPT ERROR`** —— 这个测试把整关加进树跑了
`Arena._ready()`，那里的任何运行时错误都只会打印。

- [ ] **Step 6: 引用完整性检查**

```sh
.engine/Godot_v4.7.1-stable_macos.universal.app/Contents/MacOS/Godot \
    --headless --script res://tools/check_references.gd
```

Expected: 无缺失 ext_resource、无 `invalid UID`。

- [ ] **Step 7: 提交**

```sh
ls tools/build_level_0.gd.uid tests/test_level_0.gd.uid
git add tools/build_level_0.gd tools/build_level_0.gd.uid \
        scenes/levels/level_0/level_0.tscn \
        tests/test_level_0.gd tests/test_level_0.gd.uid
git commit -m "feat(level0): generate the tutorial level"
```

---

## Task 12: 主菜单的首次启动分岔

**Files:**
- Modify: `scripts/ui/main_menu.gd:26-31`（常量）、`218-220`（`_target_scene`）、`943-959`（`_unhandled_input`）、`1081-1103`（`_poll_loading`），并新增几个方法
- Test: `tests/test_menu.gd`（追加三个）

**Interfaces:**
- Consumes: `ProgressStore.tutorial_finished()` / `ProgressStore.replay_requested`（Task 1）、
  `scenes/levels/level_0/level_0.tscn`（Task 11）、`MainMenu._place_cam` / `_stand_up_delay` /
  `_start_stand_up` / `_start_walk_loop` / `_track` / `_poll_loading` / `PauseUi.run_white_transition`
- Produces:
  - `MainMenu.LEVEL_0_SCENE: String`
  - `MainMenu.BEHIND_AZIMUTH_DEG`（const）
  - `MainMenu.SHOULDER_DISTANCE_SCALE: float`（`@export`）
  - `MainMenu.TUTORIAL_HOLD: float`（`@export`）
  - `MainMenu._entering_tutorial: bool`
  - `MainMenu._should_enter_tutorial() -> bool`
  - `MainMenu._begin_tutorial_opening() -> void`

- [ ] **Step 1: 写下会失败的测试**

在 `tests/test_menu.gd` 末尾追加：

```gdscript
# ---------------------------------------------------------------------------
# The first click. It means one of two entirely different things depending on
# whether the tutorial has ever been finished, and the wrong one is a player
# either dumped into a menu he has not earned or trapped in a tutorial he has
# already done.
# ---------------------------------------------------------------------------

func test_the_first_ever_click_goes_straight_into_the_tutorial() -> void:
	_delete_progress_file()
	var menu := MainMenu.new()
	add_child_autofree(menu)
	await step(3)
	var requested := [""]
	menu._change_scene = func(path): requested[0] = path
	menu._prompt_shown = true

	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	menu._unhandled_input(click)
	await step(2)

	assert_true(menu._entering_tutorial,
		"the first click did not take the tutorial branch")
	assert_false(menu._menu_list.visible,
		"the menu list appeared on a launch that should have had no menu at all")

func test_the_first_click_opens_the_menu_once_the_tutorial_is_finished() -> void:
	ProgressStore.mark_tutorial_finished()
	var menu := MainMenu.new()
	add_child_autofree(menu)
	await step(3)
	menu._prompt_shown = true

	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	menu._unhandled_input(click)
	await step(2)

	assert_false(menu._entering_tutorial,
		"a finished player was sent back into the tutorial")
	assert_true(menu._beat_rise_fired,
		"the ordinary entrance did not play")
	_delete_progress_file()

func test_a_replay_request_takes_the_tutorial_branch_even_when_finished() -> void:
	ProgressStore.mark_tutorial_finished()
	ProgressStore.replay_requested = true
	var menu := MainMenu.new()
	add_child_autofree(menu)
	await step(3)
	menu._change_scene = func(_path): pass
	menu._prompt_shown = true

	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	menu._unhandled_input(click)
	await step(2)

	assert_true(menu._entering_tutorial,
		"重玩新手教程 did not survive the trip back to the front door")
	ProgressStore.replay_requested = false
	_delete_progress_file()
```

- [ ] **Step 2: 跑测试确认它失败**

```sh
bun tools/run_tests.ts menu
```

Expected: FAIL，`_entering_tutorial` 不存在。

- [ ] **Step 3: 换掉目标场景常量**

`scripts/ui/main_menu.gd`，把 26-31 行的两个常量和那段 TEMPORARY 注释整个换成：

```gdscript
const MAIN_SCENE := "res://scenes/main.tscn"

## What 开始 loads, and where the first-ever click goes. The tutorial is the
## first level as well as the game's front door.
const LEVEL_0_SCENE := "res://scenes/levels/level_0/level_0.tscn"
```

把 218-220 行的 `_target_scene` 换成：

```gdscript
## Which scene the start entry loads. A field rather than the constant used
## directly, so it can be retargeted in one place instead of at each of the
## four sites the threaded load touches.
var _target_scene: String = LEVEL_0_SCENE
```

- [ ] **Step 4: 加身后镜头与教程开场**

在 `FAR_X_FRAC` 那一组常量后面加：

```gdscript
## Where the camera ends up when the click leads into the tutorial: BEHIND
## her, not in front. The body faces world +Z and never turns, so azimuth 90 is
## the lens in her face and 270 is over her shoulder -- the orbit runs
## 180 -> 270, round her left side, rather than the menu's 180 -> 90.
const BEHIND_AZIMUTH_DEG := 270.0
## How close the over-the-shoulder shot sits, as a fraction of the settled
## full-body distance. Tuning value.
@export var SHOULDER_DISTANCE_SCALE: float = 0.75
## Seconds the shoulder shot is held before the white takes over, however fast
## the level loads. Tuning value; a click during it drops it to zero.
@export var TUTORIAL_HOLD: float = 2.6
```

在 `var _loading := false` 附近加：

```gdscript
## Set while this click is taking the player straight into the tutorial: no
## menu, and the hand-over holds the over-the-shoulder shot instead of diving
## into her eye.
var _entering_tutorial: bool = false
## TUTORIAL_HOLD's live copy, so an impatient press can zero it.
var _tutorial_hold: float = 0.0
```

在 `_begin_show()` 后面加：

```gdscript
## Whether this click goes straight into the tutorial rather than opening the
## menu. Two ways in: it has never been finished -- until then the tutorial IS
## the front door -- or the settings page asked to play it again this session.
func _should_enter_tutorial() -> bool:
	return ProgressStore.replay_requested or not ProgressStore.tutorial_finished()

## The click, on a launch with no menu in it. The rise beat, unchanged, except
## that the camera comes to rest BEHIND her and the level starts loading
## underneath it.
##
## THE MUSIC STAYS ON ITS LOOP. There is no menu to arrive, so there is no drop
## to enter -- the chorus belongs to the tower, and used twice it is heavy
## neither time.
func _begin_tutorial_opening() -> void:
	_prompt_shown = false
	_entering_tutorial = true
	_tutorial_hold = TUTORIAL_HOLD
	if _prompt_tween != null and _prompt_tween.is_valid():
		_prompt_tween.kill()
	var fade := _track(create_tween())
	fade.tween_property(_click_prompt, "modulate:a", 0.0, 0.2)

	var logo_fade := _track(create_tween())
	logo_fade.tween_property(_logo_mark, "modulate:a", 0.0, LOGO_FADE_TIME) \
		.set_ease(Tween.EASE_IN)

	var floor_fade := _track(create_tween())
	floor_fade.tween_property(_floor, "modulate:a", 1.0, FLOOR_FADE_TIME)

	# Camera leads, body follows -- the same rule as the menu's own rise. The
	# body only stands; every degree of turning is the camera's.
	var cam := _track(create_tween())
	cam.tween_method(_apply_shoulder_cam, 0.0, 1.0, RISE_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

	var body := _track(create_tween())
	body.tween_interval(_stand_up_delay())
	body.tween_callback(_start_stand_up)

	var walk := _track(create_tween())
	walk.tween_interval(RISE_TIME)
	walk.tween_callback(_start_walk_loop)

	_begin_tutorial_load()

## Places the camera for a blend factor t: 0 = the crouched close profile, 1 =
## the over-the-shoulder shot the tutorial hands over from.
func _apply_shoulder_cam(t: float) -> void:
	_place_cam(lerpf(CLOSE_AZIMUTH_DEG, BEHIND_AZIMUTH_DEG, t),
		lerpf(_d_close, _d_far * SHOULDER_DISTANCE_SCALE, t),
		_head_point.lerp(_body_centre, t),
		Vector2((HEAD_X_FRAC - 0.5) * 2.0, (0.5 - HEAD_Y_FRAC) * 2.0) \
			.lerp(Vector2.ZERO, t))

## Starts the threaded load under the shoulder shot. Same machinery as
## _on_start_pressed(); what differs is that no menu has to leave first.
func _begin_tutorial_load() -> void:
	if _loading:
		return
	if DisplayServer.get_name() == "headless":
		_change_scene.call(_target_scene)
		return
	_loading = true
	if _music != null:
		_music.fade_out()
	_load_min_elapsed = 0.0
	_load_started_ms = Time.get_ticks_msec()
	ResourceLoader.load_threaded_request(_target_scene)
	print("[load] threaded request sent (tutorial opening)")
```

- [ ] **Step 5: 改分岔与交接**

`_unhandled_input()` 的分支整个换成：

```gdscript
	if _prompt_shown:
		# The invited click on the held title shot. What it means depends on
		# whether this player has ever finished the tutorial.
		if _should_enter_tutorial():
			_begin_tutorial_opening()
		else:
			_begin_show()
	elif _entering_tutorial:
		# A REPEATED SHOW MUST BE SKIPPABLE. On a replay this opening has been
		# watched before, and holding the shot for someone in a hurry is only
		# an insistence he watch it again.
		_tutorial_hold = 0.0
	else:
		# Mid-show impatience: jump straight to the settled menu.
		_skip_entrance()
```

`_poll_loading()` 里，把最小时长那一行和 dive 那一段改成：

```gdscript
	_load_min_elapsed += delta
	var status := ResourceLoader.load_threaded_get_status(_target_scene)
	# The shoulder shot is held on its own clock: the menu's run-up has a shape
	# that has to finish, the tutorial's opening only has to breathe.
	var minimum: float = _tutorial_hold if _entering_tutorial else LOAD_MIN_RUN
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS or _load_min_elapsed < minimum:
		return
```

以及（保留 print，替换 dive 那三行）：

```gdscript
	# NO DIVE ON THE TUTORIAL PATH. The push into her eye is a hand-over to
	# FIRST person; the tutorial hands over from behind her, and diving in only
	# to reappear over her shoulder reads as two different cuts.
	if not _entering_tutorial:
		var dive := _track(create_tween())
		dive.tween_method(_fp_dive, 0.0, 1.0, 0.8) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	PauseUi.run_white_transition(packed, 0.7)
```

- [ ] **Step 6: 跑测试确认通过**

```sh
bun tools/run_tests.ts menu
```

Expected: PASS。既有的 `test_start_pressed_requests_the_scene_change_via_the_seam` 断言的是
`menu._target_scene` 本身，改了目标也照样绿。**搜 `SCRIPT ERROR`。**

- [ ] **Step 7: 提交**

```sh
git add scripts/ui/main_menu.gd tests/test_menu.gd
git commit -m "feat(menu): send a first-time player straight into the tutorial"
```

---

## Task 13: 设置页的「重玩新手教程」

**Files:**
- Modify: `scripts/ui/settings_menu.gd:43-50`（`_ROWS`）、`146-167`（构建循环）；新增动作行的构造与处理
- Test: `tests/test_menu.gd`（追加一个）

**Interfaces:**
- Consumes: `ProgressStore.replay_requested`（Task 1）、`PauseUi.go_to_main_menu()`（Task 2）
- Produces:
  - `MeSettingsMenu._build_action(line: HBoxContainer, key: String, desc: String) -> void`
  - `MeSettingsMenu._ACTION_KEYS: Array`
  - `MeSettingsMenu._ACTION_LABELS: Dictionary`
  - `MeSettingsMenu._on_replay_tutorial_pressed() -> void`

- [ ] **Step 1: 写下会失败的测试**

在 `tests/test_menu.gd` 末尾追加：

```gdscript
func test_replaying_the_tutorial_arms_it_and_returns_to_the_front_door() -> void:
	# Both halves fail silently. Without the flag the click sends the player to
	# a main menu he then clicks past into the menu again -- nothing happens,
	# twice. Without the scene change he stays on the settings page.
	ProgressStore.mark_tutorial_finished()
	ProgressStore.replay_requested = false
	var page := MeSettingsMenu.new()
	add_child_autofree(page)
	await step(1)
	var requested := [""]
	PauseUi._change_scene = func(path): requested[0] = path

	page._on_replay_tutorial_pressed()
	await step(1)

	assert_true(ProgressStore.replay_requested,
		"重玩新手教程 did not arm the next click on the front door")
	assert_eq(requested[0], PauseUi.MAIN_MENU_SCENE,
		"重玩新手教程 did not send the game back to the front door")
	PauseUi._change_scene = Callable(PauseUi, "_real_change_scene")
	PauseUi._pending_scene_change = false
	ProgressStore.replay_requested = false
	_delete_progress_file()

func test_the_settings_page_still_builds_every_row() -> void:
	# The build loop routes a row by key. A key with no branch falls through to
	# _build_slider(), which has no min/max for it -- the row comes up as a
	# 0..100 slider that writes nonsense into the settings file.
	var page := MeSettingsMenu.new()
	add_child_autofree(page)
	await step(1)
	for row in MeSettingsMenu._ROWS:
		var key: String = row["key"]
		var built: bool = page._sliders.has(key) \
			or page._stepper_value_labels.has(key) \
			or key in MeSettingsMenu._ACTION_KEYS
		assert_true(built, "settings row %s was not built as any known kind" % key)
```

- [ ] **Step 2: 跑测试确认它失败**

```sh
bun tools/run_tests.ts menu
```

Expected: FAIL，`_on_replay_tutorial_pressed` / `_ACTION_KEYS` 不存在。

- [ ] **Step 3: 写实现**

`scripts/ui/settings_menu.gd`，在 `_ROWS` 之前加：

```gdscript
## Rows that are a BUTTON rather than a value: they do something once and have
## nothing to save. THE THIRD ROW KIND -- before this there were only steppers
## and sliders, and the build loop below routes on this list.
const _ACTION_KEYS := ["replay_tutorial"]
const _ACTION_LABELS := {"replay_tutorial": "重玩新手教程"}
```

在 `_ROWS` 末尾追加一行：

```gdscript
	{"key": "replay_tutorial", "label": "新手教程", "desc": "回到开场画面重玩一次新手教程。这不会清除任何已保存的进度。"},
```

把构建循环里的路由（164-167 行）换成：

```gdscript
		if key in _ACTION_KEYS:
			_build_action(line, key, desc)
		elif key in ["window_mode", "window_size", "antialiasing"]:
			_build_stepper(line, key, desc)
		else:
			_build_slider(line, key, desc)
```

在 `_build_slider()` 后面加：

```gdscript
## An action row: one red button, no value, nothing saved. It runs the moment
## it is pressed -- 保存设置 has nothing to do with it.
func _build_action(line: HBoxContainer, key: String, desc: String) -> void:
	var button := _make_bottom_button(_ACTION_LABELS.get(key, key), _action_handler(key))
	button.custom_minimum_size = Vector2(200.0, _ROW_HEIGHT)
	button.mouse_entered.connect(_show_description.bind(desc))
	line.add_child(button)

func _action_handler(key: String) -> Callable:
	if key == "replay_tutorial":
		return _on_replay_tutorial_pressed
	return func() -> void: pass

## 重玩新手教程: back to the click-to-start screen, with the next click there
## pointed at the tutorial instead of the menu.
##
## THE ARMING IS PER SESSION, NEVER SAVED. Written to disk it would send the
## player into the tutorial on every launch from then on, with the settings row
## that caused it three screens away.
func _on_replay_tutorial_pressed() -> void:
	ProgressStore.replay_requested = true
	closed.emit()
	# The same route the pause menu's own row takes, so there is one way back
	# to the front door rather than two that can drift apart.
	PauseUi.go_to_main_menu()
```

- [ ] **Step 4: 跑测试确认通过**

```sh
bun tools/run_tests.ts menu
```

Expected: PASS。**搜 `SCRIPT ERROR`** —— 设置页构建时的任何空引用都只会打印。

- [ ] **Step 5: 全量回归**

```sh
bun tools/run_tests.ts
```

Expected: 全绿，1 pending（`test_hand_ik`），orphans 仍为 32；总数比基线 1072 多出本计划新增的
测试数。任何一个 orphan 增加都说明有新脚本没被任何测试碰过 —— 检查一遍是不是漏了接线。

- [ ] **Step 6: 提交**

```sh
git add scripts/ui/settings_menu.gd tests/test_menu.gd
git commit -m "feat(settings): add a row that replays the tutorial"
```

---

## 交付后由作者亲自验的三件事（实现者不许开带窗 Godot）

1. 删掉 `user://progress.cfg` 与 `user://camera_prefs.cfg`，从头点一遍：点击 → 起身 → 镜头
   到身后 → 白幕 → 教程关第三人称。
2. 走完五课 → 塔在正前方立起 → 踏上塔底 → 地板褪色下沉 → 爬到顶碰光球 → 白幕 → 感谢试玩 →
   任意键 → 主菜单。这一遍结束后暂停菜单里应当出现「回主菜单」。
3. 设置 → 重玩新手教程 → 回到点击画面 → 点击进教程关（而不是主菜单）。

---

## Self-Review

**1. 目标逐句对照**

| 目标里的分句 | 落在哪 |
|---|---|
| 首次打开「点击屏幕开始游戏」 | Task 12 `_should_enter_tutorial()` |
| 左下角蹲着的剪影站起身 | Task 12 复用 `_stand_up_delay()` / `_start_stand_up()` |
| 镜头来到角色身后 | Task 12 `_apply_shoulder_cam()` / `BEHIND_AZIMUTH_DEG` |
| 直接以第三人称操作 | Task 4 `Arena.start_in_third_person` + Task 11 关卡置 true |
| 无缝地图里移动 | Task 11 `TorusWrap` period 100 + acrylic `phase_wrap` |
| 独立小教学一个个出现、达成即消失 | 已有 `TutorialDirector`；Task 7 提供课程、Task 5/6 提供崩塌演出 |
| 最后通天塔出现 | Task 8 塔 + Task 10 `raise_tower()`（挂 `director.finished`） |
| 踏上通天塔、激活第一个存档点 | Task 8 `Checkpoint00` + Task 10 同一个节点的 `body_entered` |
| 地板变成光点消失 | Task 10 `_dissolve_floor()`（表面褪成虚空色、点阵留下并下沉） |
| 顺着塔逐步攀登 | Task 8 螺旋 3 圈 24 台，每圈一个存档点 |
| 触碰终点光球 | Task 8 `Orb` + Task 10 `_on_orb_entered()` |
| 白幕转场到「感谢试玩」，然后返回主菜单 | Task 9 `ThanksScreen` + Task 10 `run_white_transition` |
| 下次打开就是正常主菜单 | Task 1 `tutorial_finished` + Task 12 分岔 |
| 设置界面可再玩教程，回到点击画面再进教程 | Task 13 + Task 1 `replay_requested` + Task 12 |
| 未通关时暂停菜单没有「回主菜单」，通关后随时可回 | Task 2 + Task 3 |
| 子场景统一放 `scenes/levels/level_0` | Task 7 / 8 / 11 |
| 关卡细节不必打磨 | 每个数都在 `@export` 或生成器顶部的具名常量里 |

**缺口（已在正文「明确的已知缺口」里写明，不是遗漏）：** 光球不在开场就可见（改为随塔出现，
理由是环面不变量）；每课一个动作一个单测本次不做（现在写就是 change detector）；羽毛粒子、
音乐、捷径不做。

**2. 占位符扫描**

全文无 TBD / TODO / 「同 Task N」/「加上适当的错误处理」。每个代码步骤都是可直接粘贴的完整
代码；`_action_handler()` 里那个 `return func() -> void: pass` 是 `_ACTION_KEYS` 只有一项时的
真实兜底，不是占位。

**3. 命名一致性核对**

`ProgressStore.tutorial_finished()` / `.replay_requested` / `.path`（T1 定义，T3/T10/T12/T13 使用）；
`PauseUi.go_to_main_menu()`（T2 改名，T13 使用，T2 同时改了 `tests/test_menu.gd` 的旧调用）；
`PauseUi._ENTRIES` / `_entries` / `_refresh_entries()`（T2 定义，T3 扩展）；
`CameraRig.prefs_path`（T4 定义，T4 测试使用）；
`Arena.start_in_third_person`（T4 定义，T11 生成器与测试使用）；
`CubeSwarm.progress` / `.box_size` / `.cube_size` / `.base_color` / `.cube_origin()` / `.grid_counts()`
（T5 定义，T6 与 T7 生成器使用）；
`GrowingSolid._apply_visual()`（T6 由 `_apply_alpha` 改名，三处调用点一并改）；
`SpiralTower.DEFAULT_SHAPE` / `.per_turn()` / `.platform_count()` / `.platform_origin()` /
`.platform_yaw()` / `.summit_origin()`（T8 定义，T8 生成器与测试使用）；
`ThanksScreen.MAIN_MENU_SCENE` / `._change_scene`（T9 定义，T9 测试使用）；
`LevelZero.THANKS_SCENE` / `.raise_tower()` / `._on_tower_reached()` / `._on_orb_entered()` /
`._change_scene` / 九个 `@export`（T10 定义，T10 测试与 T11 生成器逐个使用，名字一致）；
`MainMenu.LEVEL_0_SCENE` / `._entering_tutorial` / `._tutorial_hold` / `._should_enter_tutorial()` /
`._begin_tutorial_opening()` / `._apply_shoulder_cam()` / `._begin_tutorial_load()`（T12 定义，T12 测试使用）；
`MeSettingsMenu._ACTION_KEYS` / `._ACTION_LABELS` / `._build_action()` / `._on_replay_tutorial_pressed()`
（T13 定义，T13 测试使用）。

场景路径统一为 `res://scenes/levels/level_0/{lesson_vault,lesson_slide,lesson_wall_run,lesson_grab,tower,level_0}.tscn`，
在 T7 生成、T8 生成、T11 引用、T12 常量四处拼写一致。
