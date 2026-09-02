# 教程关「一课一块场景」实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让教学循环完整跑通——一课的场景在玩家前方长出来，他做出那个动作，它整块
崩塌，下一课长出来，全程可以一直往前跑。

**Architecture:** 每一课是一个能单独打开游玩的 `.tscn`（继承 `templates/base_level.tscn`），
真正的内容放在约定的 `Content` 节点下。教程关**实例化但不加进树**，只取走 `Content`，
其余（地板、环境、玩家）丢弃。`TutorialDirector` 把取来的 `Content` 挂在
`TutorialObstacle` 摆放锚点下、交给 `GrowingSolid` 生长；一课通过时整块崩塌。引用方向
一律 `场景块 -> 摆放锚点`，单向，不形成 `class_name` 解析环。

**Tech Stack:** Godot 4.7.1（用 `.engine/` 里的二进制，不用 PATH 上的）、GDScript、
GUT（`bun tools/run_tests.ts`）。

**Spec:** `docs/superpowers/specs/2026-09-02-tutorial-void-design.md`

**前一份计划:** `docs/superpowers/plans/2026-09-02-tutorial-void-mechanics.md`（已完成，
交付了 `TorusWrap` / `Arena.rescue_below_hp` / `TutorialDirector` / `TutorialObstacle` /
`GrowingSolid`）

## Global Constraints

- **测试一律用 `bun tools/run_tests.ts`**，不要直接调 gut_cmdln：它会先刷新 global
  script class cache（新增 `class_name` 后不刷新，每个测试都会死在
  `Identifier "Xxx" not declared`），并以 `--fixed-fps 60` 运行。
- **引擎二进制是 `.engine/Godot_v4.7.1-stable_macos.universal.app/Contents/MacOS/Godot`**，
  不要用 PATH 上的 `godot`。
- **代码注释一律英文，不许 emoji，不许引用对话。** 注释写成约束（现在是什么 + 不要改成
  什么），不写变更史。
- **只有关于原版《镜之边缘》的断言才带 ASCII 标签**（`[ME:CONFIRMED]` 等）。其余不加。
- **表现值不写单测**，结构性不变量才写。距离、时长、颜色一律不断言。
- **`.uid` 文件必须一起提交。**
- Commit message 用英文，Conventional Commits。
- 会长大的配置用**具名字段的字典**，GDScript 字典字面量的键是 `StringName`，读取时用
  `dict.get(&"key", default)`。
- **GDScript lambda 按值捕获局部原始类型**：闭包里累加计数要用单元素 `Array`
  （见 `tests/test_ragdoll.gd` / `tests/test_tutorial_director.gd`）。
- **教学文案里禁止出现字面键名**，一律经查表取（Task 2 建的 `InputNames`）。

---

## File Structure

| 文件 | 职责 |
|---|---|
| `scripts/level/lesson_content.gd`（新） | 从一课的 `.tscn` 里取出 `Content` 子树，绝不 add_child 整个场景 |
| `scripts/player/input/input_names.gd`（新） | 动作 -> 当前绑定的键名。今天返回硬编码值，将来读映射表 |
| `scripts/level/growing_solid.gd`（改） | 生长/崩塌作用于一整棵子树的碰撞，而不是单个碰撞体 |
| `scripts/level/tutorial_director.gd`（改） | 每课的生长/崩塌接线；`_standing` 从「锚点数组」改为「每课一条记录」 |
| `scripts/level/tutorial_opening.gd`（新） | 开场三句，键名经 InputNames 取 |
| `tools/build_lesson_sample.gd`（新） | 生成一块最小示例课程场景，供端到端跑通与测试用 |
| `tests/test_lesson_content.gd`（新） | Task 1 |
| `tests/test_input_names.gd`（新） | Task 2 |
| `tests/test_tutorial_director.gd`（改） | Task 4 追加 |
| `tests/test_growing_solid.gd`（改） | Task 3 追加 |
| `tests/test_lesson_loop.gd`（新） | Task 5 端到端 |
| `tests/test_tutorial_opening.gd`（新） | Task 6 |

---

## Task 1: 取出一课的内容

**Files:**
- Create: `scripts/level/lesson_content.gd`
- Test: `tests/test_lesson_content.gd`

**Interfaces:**
- Produces: `LessonContent.take(scene: PackedScene) -> Node3D`（static）

**背景（spec「每一课都是一个能单独打开游玩的关卡」）：** 一课的 `.tscn` 继承
`templates/base_level.tscn`，所以它带着 `Sun` / `WorldEnvironment` / `SpawnPoint` /
`Floor` / `Player` / `DebugHud` / `TuningPanel`。教程关一个都不要，只要 `Content`。

**INSTANTIATE 但绝不 ADD_CHILD。** `_ready()` 只在节点进入场景树时运行。把整个场景加
进树再删多余节点是同一件事的错误做法：那时 `Arena._ready()` 已经跑过，会多出一个
`Player`、一个抢 F1 的 `TuningPanel`，还有几百毫秒的身体加载。

- [ ] **Step 1: 写失败的测试**

创建 `tests/test_lesson_content.gd`：

```gdscript
extends ParkourTest

# Taking one lesson's content out of a scene that is also a playable level.
# What is asserted is the contract: the Content subtree arrives detached and
# alive, and nothing else in the file was ever brought to life.

## Builds a stand-in for a lesson scene: a root carrying arena.gd (as an
## inherited lesson scene would), a Content node, and a sibling that must be
## discarded.
func _lesson_scene() -> PackedScene:
	var root := Node3D.new()
	root.name = "Arena"
	root.set_script(load("res://scripts/level/arena.gd"))

	var content := Node3D.new()
	content.name = "Content"
	var wall := StaticBody3D.new()
	wall.name = "Wall"
	content.add_child(wall)
	root.add_child(content)

	var scaffolding := Node3D.new()
	scaffolding.name = "Floor"
	root.add_child(scaffolding)

	content.owner = root
	wall.owner = root
	scaffolding.owner = root

	var packed := PackedScene.new()
	assert_eq(packed.pack(root), OK, "test setup: could not pack the stand-in")
	root.free()
	return packed

func test_it_returns_the_content_subtree() -> void:
	var content := LessonContent.take(_lesson_scene())
	assert_not_null(content, "no Content came back")
	assert_eq(content.name, &"Content", "something other than Content came back")
	assert_not_null(content.get_node_or_null("Wall"),
		"the content arrived without its own children")
	content.free()

func test_the_content_arrives_detached() -> void:
	# It has to be free to be reparented into the tutorial, so it must not
	# still belong to the scene it came out of.
	var content := LessonContent.take(_lesson_scene())
	assert_null(content.get_parent(), "the content is still parented to its scene")
	content.free()

func test_nothing_else_from_the_scene_survives() -> void:
	# The scaffolding a lesson carries so it can be played on its own -- floor,
	# light, player -- must not follow it into the tutorial.
	var before: int = _live_node_count()
	var content := LessonContent.take(_lesson_scene())
	content.free()
	await step(2)
	assert_eq(_live_node_count(), before,
		"the discarded half of the lesson scene was left alive")

func test_a_scene_without_content_returns_null_instead_of_crashing() -> void:
	# A level author who has not added the node yet gets nothing, not a crash.
	var root := Node3D.new()
	root.name = "Arena"
	var packed := PackedScene.new()
	assert_eq(packed.pack(root), OK, "test setup: could not pack")
	root.free()
	assert_null(LessonContent.take(packed), "a scene with no Content returned something")

func _live_node_count() -> int:
	return Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
```

- [ ] **Step 2: 跑测试，确认它失败**

```sh
bun tools/run_tests.ts lesson_content
```

预期：`Identifier "LessonContent" not declared in the current scope.`

- [ ] **Step 3: 写 LessonContent**

创建 `scripts/level/lesson_content.gd`：

```gdscript
class_name LessonContent
extends RefCounted

# Takes one lesson's geometry out of a scene that is ALSO a playable level.
#
# A lesson inherits templates/base_level.tscn so the author can open it and
# run around in it while shaping the geometry. That gives every lesson a Sun,
# a WorldEnvironment, a SpawnPoint, a Floor, a Player, a DebugHud and a
# TuningPanel -- scaffolding for editing, none of which belongs in the
# tutorial. Only the Content subtree does.

## The node a lesson puts its own geometry under. Everything else in the file
## is there so the lesson can be played on its own.
const CONTENT := &"Content"

## Returns the lesson's Content subtree, detached and ready to be reparented,
## or null if the scene has none.
##
## INSTANTIATED BUT NEVER ADDED TO THE TREE. _ready() runs on entering a scene
## tree, so nothing in the discarded half ever wakes up: no second Player, no
## second TuningPanel fighting over F1, no several hundred milliseconds of
## body loading. Adding the whole scene and then deleting the extra nodes
## looks equivalent and is not -- by then every _ready() has already run.
static func take(scene: PackedScene) -> Node3D:
	if scene == null:
		return null
	var whole: Node = scene.instantiate()
	var content: Node = whole.get_node_or_null(NodePath(CONTENT))
	if content == null:
		whole.free()
		return null
	whole.remove_child(content)
	whole.free()
	return content as Node3D
```

- [ ] **Step 4: 跑测试，确认通过**

```sh
bun tools/run_tests.ts lesson_content
```

预期：4 passing。

- [ ] **Step 5: 跑全量并提交**

```sh
bun tools/run_tests.ts
git add scripts/level/lesson_content.gd scripts/level/lesson_content.gd.uid \
        tests/test_lesson_content.gd tests/test_lesson_content.gd.uid
git commit -m "feat(level): take a lesson's content without waking the level it lives in"
```

---

## Task 2: 键名查表

**Files:**
- Create: `scripts/player/input/input_names.gd`
- Test: `tests/test_input_names.gd`

**Interfaces:**
- Produces:
  - `InputNames.MOVE` / `.JUMP` / `.CROUCH` / `.WALK` / `.TURN`（`StringName` 常量）
  - `InputNames.label(action: StringName) -> String`

**背景（spec「文案里不许出现字面的键名」）：** 按键目前硬编码在
`keyboard_input_source.gd`（`KEY_SPACE` / `KEY_SHIFT` / `KEY_CTRL` / `KEY_Q`），重绑定
以后再做。但教学文案现在就必须按「将来会重绑定」来写：键名从查表取，写死的话将来补
重绑定时要在所有文案里做全文搜索，而漏掉的那句会在玩家把蹲改到 C 之后继续教他按 shift。

- [ ] **Step 1: 写失败的测试**

创建 `tests/test_input_names.gd`：

```gdscript
extends ParkourTest

# The seam tutorial copy names keys through. Today it answers from the
# hardcoded bindings; when rebinding lands it answers from the map, and not
# one line of copy changes. What is asserted is that seam, not the strings --
# those are content and will be reworded.

func test_every_action_has_a_label() -> void:
	for action in [InputNames.MOVE, InputNames.JUMP, InputNames.CROUCH,
			InputNames.WALK, InputNames.TURN]:
		assert_false(InputNames.label(action).is_empty(),
			"action %s has no label" % action)

func test_an_unknown_action_does_not_crash_or_lie() -> void:
	# Copy asking for a key that does not exist should be obvious on screen,
	# not silently plausible.
	var label: String = InputNames.label(&"NoSuchAction")
	assert_false(label.is_empty(), "an unknown action produced an empty label")
	assert_true(label.contains("?"), "an unknown action produced a plausible-looking key: %s" % label)

func test_the_labels_match_what_the_input_source_actually_reads() -> void:
	# THE POINT OF THE TABLE. If these drift apart, the tutorial teaches keys
	# the game does not listen to.
	assert_eq(InputNames.label(InputNames.JUMP), OS.get_keycode_string(KEY_SPACE),
		"jump's label does not match the key KeyboardInputSource polls")
	assert_eq(InputNames.label(InputNames.CROUCH), OS.get_keycode_string(KEY_SHIFT),
		"crouch's label does not match the key KeyboardInputSource polls")
	assert_eq(InputNames.label(InputNames.TURN), OS.get_keycode_string(KEY_Q),
		"turn's label does not match the key KeyboardInputSource polls")
```

- [ ] **Step 2: 跑测试，确认它失败**

```sh
bun tools/run_tests.ts input_names
```

预期：`Identifier "InputNames" not declared`。

- [ ] **Step 3: 写 InputNames**

创建 `scripts/player/input/input_names.gd`：

```gdscript
class_name InputNames
extends RefCounted

# What a key is CALLED, for anything that has to say so on screen.
#
# TUTORIAL COPY MUST NAME KEYS THROUGH HERE, NEVER AS LITERALS. Rebinding is
# not built yet -- KeyboardInputSource reads fixed physical keycodes and says
# so in its own header -- but copy written with "Shift" spelled into it will
# keep telling a player to press Shift after he has moved crouch to C, and
# finding every such line later means a full-text search that will miss one.
# Going through this table costs nothing today and makes that search
# unnecessary.
#
# When rebinding lands, only _BINDINGS changes.

const MOVE := &"move"
const JUMP := &"jump"
const CROUCH := &"crouch"
const WALK := &"walk"
const TURN := &"turn"

## The keys KeyboardInputSource actually polls. DO NOT let these drift from
## it -- a tutorial that names a key the game does not listen to is worse than
## one that names none.
const _BINDINGS: Dictionary = {
	JUMP: KEY_SPACE,
	CROUCH: KEY_SHIFT,
	WALK: KEY_CTRL,
	TURN: KEY_Q,
}

## Movement is four keys, so it has no single keycode and carries its own
## label.
const _MOVE_LABEL := "WASD"

## Shown when copy asks for an action that does not exist. DELIBERATELY UGLY:
## a missing binding should be visible on screen during the first playtest,
## not read as a plausible key.
const _UNKNOWN := "???"

static func label(action: StringName) -> String:
	if action == MOVE:
		return _MOVE_LABEL
	if not _BINDINGS.has(action):
		return _UNKNOWN
	return OS.get_keycode_string(_BINDINGS[action])
```

- [ ] **Step 4: 跑测试，确认通过**

```sh
bun tools/run_tests.ts input_names
```

预期：3 passing。

- [ ] **Step 5: 跑全量并提交**

```sh
bun tools/run_tests.ts
git add scripts/player/input/input_names.gd scripts/player/input/input_names.gd.uid \
        tests/test_input_names.gd tests/test_input_names.gd.uid
git commit -m "feat(input): name keys through a table so copy survives rebinding"
```

---

## Task 3: 生长作用于一整棵子树

**Files:**
- Modify: `scripts/level/growing_solid.gd`
- Test: `tests/test_growing_solid.gd`（追加）

**Interfaces:**
- Produces: `GrowingSolid.body` 的语义从「那一个碰撞体」改为「这一块的碰撞根」

**背景：** `GrowingSolid` 建于前一份计划，当时一个障碍被设想成一个物件，所以
`body: CollisionObject3D` 指向唯一的碰撞体。现在一课是**一整块场景**（spec
「一课 = 一整块场景」），里面可以有任意多个碰撞体。照原样接线，「碰撞在生长完成的那一刻
一次性启用」这条契约对课程场景根本不生效——几何一出现就是实心的，玩家会撞上一堵还在
淡入的墙。

**改的是遍历范围，不是时序。** 仍然一次性启用、崩塌时立刻放弃，仍然不让碰撞面跟着
生长面爬。

- [ ] **Step 1: 追加失败的测试**

在 `tests/test_growing_solid.gd` 末尾追加：

```gdscript
func test_every_collision_shape_under_the_block_waits_for_growth() -> void:
	# A lesson is a whole block of scenery, not one object: several bodies,
	# each with its own shapes. If only the first waits, the player runs into
	# a wall that is still fading in.
	var solid: GrowingSolid = await _growing(1.0)
	var second := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 1.0, 1.0)
	shape.shape = box
	second.add_child(shape)
	_body.add_child(second)
	await step(1)

	solid.begin()
	await step(10)
	assert_false(solid.solid, "test setup: it finished growing too fast to observe")
	assert_true(shape.disabled,
		"a collision shape deeper in the block was live while the block was still growing")

	await step(80)
	assert_true(solid.solid, "test setup: it never finished growing")
	assert_false(shape.disabled, "a collision shape deeper in the block never woke up")
```

- [ ] **Step 2: 跑测试，确认它失败**

```sh
bun tools/run_tests.ts growing_solid
```

预期：失败在第一个 `assert_true(shape.disabled, ...)` —— 深一层的碰撞体从未被关掉。

- [ ] **Step 3: 让 `_set_solid()` 走整棵子树**

把 `growing_solid.gd` 的 `_set_solid()` 换成：

```gdscript
func _set_solid(on: bool) -> void:
	solid = on
	if body == null:
		return
	body.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	# THE WHOLE SUBTREE, not just this node's own children. A lesson is a block
	# of scenery with as many bodies as it needs; if only the first level of
	# shapes waits for growth, the player runs into something that is still
	# fading in.
	for node in body.find_children("*", "CollisionShape3D", true, false):
		# DEFERRED: a direct write can land mid-physics-query. Growth has
		# metres of margin, so a frame's delay costs nothing.
		(node as CollisionShape3D).set_deferred("disabled", not on)
	if body is CollisionShape3D:
		(body as CollisionShape3D).set_deferred("disabled", not on)
```

同时把 `body` 的文档改成描述新语义：

```gdscript
## The root of everything in this block that collides. Every CollisionShape3D
## underneath it is disabled until growth completes and again the moment
## collapse begins -- a block may hold any number of bodies.
@export var body: CollisionObject3D
```

- [ ] **Step 4: 跑测试，确认通过**

```sh
bun tools/run_tests.ts growing_solid
```

预期：6 passing（原 5 条 + 新 1 条）。

- [ ] **Step 5: 跑全量并提交**

```sh
bun tools/run_tests.ts
git add scripts/level/growing_solid.gd tests/test_growing_solid.gd
git commit -m "feat(level): growth gates every shape in the block, not just the first"
```

---

## Task 4: 一课的生长与崩塌

**Files:**
- Modify: `scripts/level/tutorial_director.gd`
- Test: `tests/test_tutorial_director.gd`（追加）

**Interfaces:**
- Consumes: `LessonContent.take()`（Task 1）、`TutorialObstacle`、`GrowingSolid`
- Produces:
  - `lessons` 表新增可选字段 `scene: PackedScene`
  - `TutorialDirector.obstacle_template: PackedScene`（可空，未给则运行时新建裸 `TutorialObstacle`）
  - `TutorialDirector.grow_time: float` / `collapse_time: float`
  - `TutorialDirector.live_count() -> int`

**背景：** 前一份计划刻意没接这条线，因为当时不知道 `TutorialObstacle` 与
`GrowingSolid` 谁持有谁——两个 `class_name` 互相 typed 引用会在 parse 期形成解析环。
现在方向定了：

```
TutorialObstacle (摆放锚点)
  └ GrowingSolid  (整块的生长/崩塌，@export var obstacle 指回锚点)
      └ Content   (这一课的几何，来自它自己的 .tscn)
```

**引用只向下和向后指**：`GrowingSolid -> TutorialObstacle` 这条已经存在，
`TutorialObstacle` 不得反向引用 `GrowingSolid`。Director 同时持有两者。

**一课是一个单位**：生长与崩塌作用在 `GrowingSolid` 上，它下面整棵 `Content` 一起
淡入淡出，不是每个几何体各自来。

- [ ] **Step 1: 追加失败的测试**

在 `tests/test_tutorial_director.gd` 末尾追加：

```gdscript
## A stand-in lesson scene: a root plus the Content node the tutorial takes.
func _lesson_scene(child_name: String) -> PackedScene:
	var root := Node3D.new()
	root.name = "Arena"
	var content := Node3D.new()
	content.name = "Content"
	var mesh := MeshInstance3D.new()
	mesh.name = child_name
	mesh.mesh = BoxMesh.new()
	content.add_child(mesh)
	root.add_child(content)
	content.owner = root
	mesh.owner = root
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	return packed

func test_the_first_lesson_grows_its_own_scene_in_front_of_the_player() -> void:
	var player: Player = await _directed([
		{teaches = Move.CROUCH, scene = _lesson_scene("Wall")},
	])
	await step(3)
	assert_eq(_director.live_count(), 1, "the first lesson did not build anything")
	var obstacle: TutorialObstacle = _director.current_obstacle()
	assert_not_null(obstacle, "no obstacle was placed")
	assert_not_null(obstacle.find_child("Wall", true, false),
		"the lesson's own geometry is not under the obstacle")
	var forward: Vector3 = -player.global_transform.basis.z
	var to_it: Vector3 = obstacle.anchor - player.global_position
	to_it.y = 0.0
	assert_gt(forward.normalized().dot(to_it.normalized()), 0.9,
		"the lesson was not built ahead of the player")

func test_passing_a_lesson_collapses_it_and_builds_the_next() -> void:
	var player: Player = await _directed([
		{teaches = Move.CROUCH, scene = _lesson_scene("First")},
		{teaches = Move.SLIDE, scene = _lesson_scene("Second")},
	])
	await step(3)
	player.move_manager.start(Move.CROUCH)
	await step(3)
	assert_not_null(_director.find_child("Second", true, false),
		"the next lesson was not built")
	# The old one is on its way out, not gone on the same frame: the player is
	# meant to see it go.
	assert_not_null(_director.find_child("First", true, false),
		"the passed lesson vanished instantly instead of collapsing")

func test_a_lesson_without_a_scene_still_advances() -> void:
	# The table is authored a row at a time; a row with no scene yet must not
	# stop the sequence from being testable.
	var player: Player = await _directed([
		{teaches = Move.CROUCH},
		{teaches = Move.SLIDE},
	])
	await step(3)
	player.move_manager.start(Move.CROUCH)
	await step(3)
	assert_eq(_director.index, 1, "a sceneless lesson blocked the sequence")
```

- [ ] **Step 2: 跑测试，确认它失败**

```sh
bun tools/run_tests.ts tutorial_director
```

预期：`Nonexistent function 'live_count'`（以及 `current_obstacle`，Task 6 里删掉过）。

- [ ] **Step 3: 改写 TutorialDirector 的持有结构**

把 `var _standing: Array[TutorialObstacle] = []` 换成一条记录一课：

```gdscript
## One entry per lesson currently in the world, oldest first. Named fields
## because this grows: see naming-config-fields.
##   obstacle  TutorialObstacle -- the placement anchor
##   growth    GrowingSolid -- owns this block's grow/collapse timing
##   leaving   true once it has been told to collapse
var _live: Array[Dictionary] = []
```

`adopt()` 与 `_on_wrapped()` 改为走 `_live`：

```gdscript
## Takes ownership of an obstacle already in the scene so it travels on a
## wrap. Used by the level builder and by tests.
func adopt(obstacle: TutorialObstacle, growth: GrowingSolid = null) -> void:
	if obstacle == null:
		return
	for entry in _live:
		if entry.get(&"obstacle") == obstacle:
			return
	_live.append({obstacle = obstacle, growth = growth, leaving = false})

## The anchor of the lesson currently being taught, or null.
func current_obstacle() -> TutorialObstacle:
	for entry in _live:
		if not entry.get(&"leaving", false):
			return entry.get(&"obstacle")
	return null

## How many lessons are in the world, including one still collapsing.
func live_count() -> int:
	return _live.size()

func _on_wrapped(offset: Vector3) -> void:
	# EVERYTHING STILL VISIBLE TAKES THE SAME STEP THE BODY TAKES. A block left
	# behind lands a period away from where the player last saw it, and the
	# crossing announces itself.
	for entry in _live:
		var obstacle: TutorialObstacle = entry.get(&"obstacle")
		if is_instance_valid(obstacle):
			obstacle.shift_by(offset)
```

- [ ] **Step 4: 建一课，接上生长**

在 `tutorial_director.gd` 里加：

```gdscript
## Optional. A scene whose root is a TutorialObstacle, used as the placement
## anchor so a level can preset spawn_distance and friends. Without one a bare
## TutorialObstacle is built at runtime with its own defaults.
@export var obstacle_template: PackedScene

@export var grow_time: float = 1.2
@export var collapse_time: float = 0.9

## Builds the lesson at `at` and starts it growing. Silently does nothing for
## a row with no scene yet -- the table is authored a row at a time, and a
## half-filled table must still be walkable.
func _build_lesson(at: int) -> void:
	if at < 0 or at >= lessons.size():
		return
	var scene: PackedScene = lessons[at].get(&"scene")
	if scene == null:
		return
	var content: Node3D = LessonContent.take(scene)
	if content == null:
		push_error("TutorialDirector: lesson %d has a scene with no Content node" % at)
		return

	var obstacle: TutorialObstacle
	if obstacle_template != null:
		obstacle = obstacle_template.instantiate() as TutorialObstacle
	else:
		obstacle = TutorialObstacle.new()
	obstacle.name = "Lesson%d" % at
	obstacle.player = player
	# Keep clear of whatever is still leaving, so a player who turns round
	# right after finishing does not get the next block on top of the last.
	var avoid: Array[TutorialObstacle] = []
	for entry in _live:
		var other: TutorialObstacle = entry.get(&"obstacle")
		if is_instance_valid(other):
			avoid.append(other)
	obstacle.avoid = avoid
	add_child(obstacle)

	var growth := GrowingSolid.new()
	growth.name = "Growth"
	growth.grow_time = grow_time
	growth.collapse_time = collapse_time
	growth.obstacle = obstacle
	obstacle.add_child(growth)
	growth.add_child(content)

	_live.append({obstacle = obstacle, growth = growth, leaving = false})
	growth.gone.connect(_on_block_gone.bind(obstacle))
	growth.begin()

## Sends a lesson's block away. It stays in _live until it has finished
## leaving, because it is still visible and still has to travel on a wrap.
func _collapse_lesson(at: int) -> void:
	var name_wanted := "Lesson%d" % at
	for entry in _live:
		var obstacle: TutorialObstacle = entry.get(&"obstacle")
		if is_instance_valid(obstacle) and obstacle.name == name_wanted:
			entry[&"leaving"] = true
			var growth: GrowingSolid = entry.get(&"growth")
			if is_instance_valid(growth):
				growth.collapse()
			return

func _on_block_gone(obstacle: TutorialObstacle) -> void:
	for i in _live.size():
		if _live[i].get(&"obstacle") == obstacle:
			_live.remove_at(i)
			break
	if is_instance_valid(obstacle):
		obstacle.queue_free()
```

- [ ] **Step 5: 把它接到进度上**

`_ready()` 末尾追加第一课的建造：

```gdscript
	_build_lesson(index)
```

`_on_move_changed()` 里推进之后追加：

```gdscript
	_collapse_lesson(passed)
	_build_lesson(index)
```

（`passed` 是原有的那个局部变量，`index` 已经在它之后自增。）

- [ ] **Step 6: 跑测试，确认通过**

```sh
bun tools/run_tests.ts tutorial_director
```

预期：9 passing（原 6 条 + 新 3 条）。

- [ ] **Step 7: 跑全量并提交**

```sh
bun tools/run_tests.ts
git add scripts/level/tutorial_director.gd tests/test_tutorial_director.gd
git commit -m "feat(level): a lesson grows as one block and leaves as one block"
```

---

## Task 5: 一块示例课程，端到端跑通

**Files:**
- Create: `tools/build_lesson_sample.gd`
- Create（生成物）: `scenes/levels/lessons/sample_wall.tscn`
- Test: `tests/test_lesson_loop.gd`

**Interfaces:**
- Consumes: Task 1-4 全部

**背景：** 作者会在编辑器里手工建真正的课程场景（继承 `templates/base_level.tscn`，
几何要反复调）。本任务只生成**一块最小的示例**，让整条链有东西可跑、可测，并作为
作者建第一块真场景时的形状参考。

**示例场景不继承 base_level**，因为「继承场景」在代码里无法可靠地构造（Godot 的
inherited scene 是编辑器概念）。它只有一个根和一个 `Content`，因此不能单独游玩——
这一点写在它的生成脚本头部，免得被当成模板照抄。

- [ ] **Step 1: 写生成脚本**

创建 `tools/build_lesson_sample.gd`：

```gdscript
extends SceneTree

# Generates scenes/levels/lessons/sample_wall.tscn: the smallest thing that
# proves the lesson loop runs end to end.
#
# NOT A TEMPLATE FOR REAL LESSONS. A real lesson inherits
# templates/base_level.tscn so its author can open it and run around in it
# while shaping the geometry (see docs/level-templates.md and the spec's
# 「每一课都是一个能单独打开游玩的关卡」). An inherited scene cannot be built
# from code -- inheritance is an editor concept -- so this sample carries only
# a root and a Content node, and cannot be played on its own.
#
# Run with:
#   .engine/Godot_v4.7.1-stable_macos.universal.app/Contents/MacOS/Godot \
#       --headless --path . --script res://tools/build_lesson_sample.gd

const OUTPUT := "res://scenes/levels/lessons/sample_wall.tscn"

func _initialize() -> void:
	var root := Node3D.new()
	root.name = "SampleWall"

	var content := Node3D.new()
	content.name = "Content"
	root.add_child(content)

	# A waist-high wall: high enough to want vaulting, low enough that failing
	# to costs nothing.
	var wall := StaticBody3D.new()
	wall.name = "Wall"
	wall.position = Vector3(0.0, 0.5, 0.0)
	var size := Vector3(6.0, 1.0, 0.6)

	var shape := CollisionShape3D.new()
	shape.name = "Collision"
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	wall.add_child(shape)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.55, 0.60, 0.68)
	# Growth and collapse are alpha for now, so the material has to be able to
	# express transparency at all.
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = material
	wall.add_child(mesh_instance)

	content.add_child(wall)

	for node in [content, wall, shape, mesh_instance]:
		node.owner = root

	DirAccess.make_dir_recursive_absolute("res://scenes/levels/lessons")
	var packed := PackedScene.new()
	var pack_error := packed.pack(root)
	assert(pack_error == OK, "pack failed: %d" % pack_error)
	var save_error := ResourceSaver.save(packed, OUTPUT)
	assert(save_error == OK, "save failed: %d" % save_error)
	print("wrote ", OUTPUT)
	quit(0)
```

- [ ] **Step 2: 生成场景**

```sh
.engine/Godot_v4.7.1-stable_macos.universal.app/Contents/MacOS/Godot \
    --headless --path . --script res://tools/build_lesson_sample.gd
```

预期输出 `wrote res://scenes/levels/lessons/sample_wall.tscn`。

- [ ] **Step 3: 写端到端测试**

创建 `tests/test_lesson_loop.gd`：

```gdscript
extends ParkourTest

# The whole loop, on the real sample scene rather than a stand-in: a lesson is
# built ahead of the player, doing the move it teaches sends it away and brings
# the next, and a crossing changes nothing about where any of it stands
# relative to him.

const TestWorld = preload("res://tests/world_fixture.gd")
const SAMPLE := "res://scenes/levels/lessons/sample_wall.tscn"

var _world: Dictionary = {}
var _loose: Array[Node] = []

func after_each() -> void:
	for node in _loose:
		if is_instance_valid(node):
			node.queue_free()
	_loose.clear()
	if _world.is_empty():
		return
	TestWorld.teardown(_world)
	_world = {}

func _running_tutorial() -> Dictionary:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(10)
	var player: Player = _world["player"]

	var wrap := TorusWrap.new()
	wrap.player = player
	wrap.period = 100.0
	get_tree().root.add_child(wrap)
	_loose.append(wrap)

	var director := TutorialDirector.new()
	director.player = player
	director.wrap = wrap
	var sample: PackedScene = load(SAMPLE)
	director.lessons = [
		{teaches = Move.CROUCH, scene = sample},
		{teaches = Move.SLIDE, scene = sample},
	]
	get_tree().root.add_child(director)
	_loose.append(director)
	await step(3)
	return {player = player, director = director, wrap = wrap}

func test_the_sample_scene_carries_a_content_node() -> void:
	# Guards the convention itself: a lesson whose geometry is not under
	# Content contributes nothing and does so silently.
	var content := LessonContent.take(load(SAMPLE))
	assert_not_null(content, "the sample lesson has no Content node")
	content.free()

func test_the_first_lesson_stands_in_front_of_the_player() -> void:
	var live: Dictionary = await _running_tutorial()
	var director: TutorialDirector = live["director"]
	assert_eq(director.live_count(), 1, "the loop did not build the first lesson")
	assert_not_null(director.find_child("Wall", true, false),
		"the sample lesson's geometry is not in the world")

func test_a_crossing_does_not_move_the_lesson_relative_to_the_player() -> void:
	# THE INVARIANT. A teleport may not change any relative position; only
	# distance may retire a block.
	var live: Dictionary = await _running_tutorial()
	var player: Player = live["player"]
	var director: TutorialDirector = live["director"]
	var obstacle: TutorialObstacle = director.current_obstacle()
	var before: Vector3 = obstacle.anchor - player.global_position

	player.global_position = Vector3(51.0, player.global_position.y, 0.0)
	await step(3)

	var after: Vector3 = obstacle.anchor - player.global_position
	assert_almost_eq(after.distance_to(before), 0.0, 0.01,
		"the crossing moved the lesson relative to the player: %s -> %s" % [before, after])
```

- [ ] **Step 4: 跑测试，确认通过**

```sh
bun tools/run_tests.ts lesson_loop
```

预期：3 passing。若第一条就失败，说明生成脚本没跑或路径不对，回到 Step 2。

- [ ] **Step 5: 跑全量并提交**

```sh
bun tools/run_tests.ts
git add tools/build_lesson_sample.gd tools/build_lesson_sample.gd.uid \
        scenes/levels/lessons/sample_wall.tscn \
        tests/test_lesson_loop.gd tests/test_lesson_loop.gd.uid
git commit -m "feat(level): a sample lesson, and the loop proved end to end on it"
```

---

---

## Task 6: 开场三句

**Files:**
- Create: `scripts/level/tutorial_opening.gd`
- Test: `tests/test_tutorial_opening.gd`

**Interfaces:**
- Consumes: `InputNames`（Task 2）、`Subtitle`
- Produces:
  - `TutorialOpening.subtitle: Subtitle`（`@export`）
  - `TutorialOpening.hold: float` / `gap: float`
  - `TutorialOpening.lines() -> PackedStringArray`
  - `TutorialOpening.play()`、signal `spoken(index: int)`、signal `done`

**背景（spec「文字提示：三句，然后闭嘴」）：** 开局只说三句，此后再不教任何动作。这三句
教的不是三个动作，是**整套操作哲学**：两个键、两个方向、上下文决定具体是什么
（`10-镜之边缘-like判定标准.md` ⑥）。玩家学会「对着墙按上」之后，墙跑、蹬墙跳、攀墙都
不必再教。

**键名一律经 `InputNames.label()` 取**，不许写字面量——见 Task 2 的理由。

- [ ] **Step 1: 写失败的测试**

创建 `tests/test_tutorial_opening.gd`：

```gdscript
extends ParkourTest

# The only three lines the tutorial ever says about controls. What is asserted
# is that they exist, arrive in order, stop, and name keys through the table --
# not their wording, which is content and will be reworded.

var _opening: TutorialOpening
var _subtitle: Subtitle

func _built() -> TutorialOpening:
	_subtitle = Subtitle.new()
	add_child_autofree(_subtitle)
	_opening = TutorialOpening.new()
	_opening.subtitle = _subtitle
	_opening.hold = 0.05
	_opening.gap = 0.05
	add_child_autofree(_opening)
	await step(1)
	return _opening

func test_there_are_exactly_three_lines() -> void:
	# Three, and this number is the design: move, up, down. A fourth means
	# something is being taught that the two directions should have covered.
	var opening: TutorialOpening = await _built()
	assert_eq(opening.lines().size(), 3, "the opening is not three lines")

func test_every_line_names_its_key_through_the_table() -> void:
	# Copy with a key spelled into it keeps telling the player to press Shift
	# after he has rebound crouch. This catches the literal at authoring time.
	var opening: TutorialOpening = await _built()
	var text: String = " ".join(opening.lines())
	for action in [InputNames.MOVE, InputNames.JUMP, InputNames.CROUCH]:
		assert_true(text.contains(InputNames.label(action)),
			"no line names %s through InputNames" % action)

func test_the_lines_arrive_in_order_and_then_stop() -> void:
	var opening: TutorialOpening = await _built()
	var seen: Array[int] = []
	opening.spoken.connect(func(i: int) -> void: seen.append(i))
	var ended := [0]
	opening.done.connect(func() -> void: ended[0] += 1)

	opening.play()
	await step(60)

	assert_eq(seen, [0, 1, 2] as Array[int], "the lines did not arrive in order: %s" % [seen])
	assert_eq(ended[0], 1, "the opening announced its end %d times" % ended[0])

func test_it_says_nothing_without_a_subtitle_layer() -> void:
	# A level built without one (every test world is) must not crash.
	var opening := TutorialOpening.new()
	add_child_autofree(opening)
	await step(1)
	opening.play()
	await step(10)
	assert_eq(opening.lines().size(), 3, "the lines went missing without a subtitle")
```

- [ ] **Step 2: 跑测试，确认它失败**

```sh
bun tools/run_tests.ts tutorial_opening
```

预期：`Identifier "TutorialOpening" not declared`。

- [ ] **Step 3: 写 TutorialOpening**

创建 `scripts/level/tutorial_opening.gd`：

```gdscript
class_name TutorialOpening
extends Node

# The only three lines this tutorial ever says about controls.
#
# THEY TEACH THE GRAMMAR, NOT THREE ACTIONS. Two keys, two directions, and
# context decides what happens -- [ME:CONFIRMED 10] the original's own
# "few keys plus contextual resolution". A player who has understood "press up
# at a wall" needs no further lesson for wall runs, wall kicks or climbs, which
# is why nothing after this says anything about controls at all.
#
# A FOURTH LINE MEANS SOMETHING IS WRONG. If an action cannot be reached
# through up or down, it does not belong in the mandatory set -- it belongs on
# a shortcut, where discovering it is the reward.

## Where the lines go. Optional: a level built without one simply stays quiet.
@export var subtitle: Subtitle

## How long a line stays lit, and the pause after it.
@export var hold: float = 3.0
@export var gap: float = 0.6

signal spoken(index: int)
signal done

var _at: int = -1
var _timer: float = 0.0
var _running: bool = false

## The lines, built fresh each call so a rebind is picked up without anything
## having to invalidate a cache. KEYS COME FROM InputNames -- never spell one
## into the text.
func lines() -> PackedStringArray:
	return PackedStringArray([
		"%s  移动" % InputNames.label(InputNames.MOVE),
		"%s  跳跃 / 向上的动作" % InputNames.label(InputNames.JUMP),
		"%s  蹲下 / 向下的动作" % InputNames.label(InputNames.CROUCH),
	])

func play() -> void:
	if _running:
		return
	_running = true
	_at = -1
	_timer = 0.0
	_advance()

func _process(delta: float) -> void:
	if not _running:
		return
	_timer -= delta
	if _timer <= 0.0:
		_advance()

func _advance() -> void:
	_at += 1
	var all := lines()
	if _at >= all.size():
		_running = false
		done.emit()
		return
	if subtitle != null:
		subtitle.show_text(all[_at], hold)
	spoken.emit(_at)
	_timer = hold + gap
```

- [ ] **Step 4: 跑测试，确认通过**

```sh
bun tools/run_tests.ts tutorial_opening
```

预期：4 passing。

- [ ] **Step 5: 跑全量并提交**

```sh
bun tools/run_tests.ts
git add scripts/level/tutorial_opening.gd scripts/level/tutorial_opening.gd.uid \
        tests/test_tutorial_opening.gd tests/test_tutorial_opening.gd.uid
git commit -m "feat(level): three lines that teach the grammar, then silence"
```

## 交付后作者要做的事（不在本计划内）

- 在编辑器里建第一块**真正的**课程场景：Scene > New Inherited Scene 选
  `templates/base_level.tscn`，加一个 `Content` 节点，几何放进去。
- `lessons` 表的实际条目——曲线八段已定（见 spec），每段用什么几何承载没定。
- `grow_time` 与 `TutorialObstacle.spawn_distance` 的配比，必须满足
  `grow_time x 冲刺速度 < spawn_distance - 余量`。

## 本计划**不**包含（第三份计划）

- 螺旋塔的逐段揭示、地板塌陷与下方光海
- 音乐的乐句对齐（塔等乐句边界）
- 开场分流与 `progress.cfg`
- 生长/崩塌的 shader 与羽毛粒子（现在是 alpha，时序契约已经成立）
- 卡住太久后的第二次提示（需要先有真实课程场景来定「多久算卡住」）
- 把 `TutorialOpening` 接到教程关的开场时序上（要等开场分流做完才知道它在哪一拍播）
- 清理调试脚手架（`VoidProbe`、`RoamingProps`、主菜单里指向虚空场地的临时目标）
