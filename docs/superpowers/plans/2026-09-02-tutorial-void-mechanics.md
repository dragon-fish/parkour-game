# 教程关「虚空」机制骨架 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 搭出虚空教程关前半段的全部机制——环面循环、教学进度、障碍摆放与生长、
不会死的救援模式——使作者可以在里面手工调地图。

**Architecture:** 全部是挂在关卡上的独立节点，互不知道对方存在，只通过 `Player`
的既有信号和字段通信。`TorusWrap` 每帧检查坐标；`TutorialDirector` 监听
`MoveManager.move_changed` 推进进度；障碍是极小的 `.tscn`，由 Director 按表激活。
没有一个模块需要修改 `Move` 家族的转换逻辑。

**Tech Stack:** Godot 4.7.1（用 `.engine/` 里的二进制，不用 PATH 上的）、GDScript、
GUT（`bun tools/run_tests.ts`）。

**Spec:** `docs/superpowers/specs/2026-09-02-tutorial-void-design.md`

## Global Constraints

- **测试一律用 `bun tools/run_tests.ts`**，不要直接调 gut_cmdln：它会先刷新
  global script class cache（新增 `class_name` 后不刷新，每个测试都会死在
  `Identifier "Xxx" not declared`），并以 `--fixed-fps 60` 运行。
- **引擎二进制是 `.engine/Godot_v4.7.1-stable_macos.universal.app/Contents/MacOS/Godot`**，
  不要用 PATH 上的 `godot`。
- **代码注释一律英文，不许出现 emoji，不许引用对话。** 注释写成约束（"现在是什么 +
  不要改成什么"），不写变更史。
- **只有关于原版《镜之边缘》的断言才带标签**，用 ASCII 五级制
  （`[ME:CONFIRMED]` / `[ME:DERIVED]` / `[ME:INFERRED]` / `[ME:COMMUNITY]` /
  `[ME:UNKNOWN]`）。其余一律不加标签。
- **表现值不写单测**，结构性不变量才写。几何尺寸、动画时长、颜色一律不断言。
- **禁止创建名为 `local` 或 `local_*` 的目录。**
- **`.uid` 文件必须一起提交**（新建 `.gd` 会生成同名 `.uid`）。
- Commit message 用英文，Conventional Commits。
- 会长大的配置用**具名字段的字典**，不用位置数组；GDScript 字典字面量的键用 `=`。

---

## File Structure

| 文件 | 职责 |
|---|---|
| `scripts/player/moves/move_manager.gd`（改） | 新增一个公开查询：当前 move 是不是 `ScriptedMove` |
| `scripts/level/torus_wrap.gd`（新） | 环面循环。跨界时平移玩家，并广播位移量 |
| `scripts/level/arena.gd`（改） | 新增 `rescue_below_hp`，把三条通往死亡的路径改判为白幕救援 |
| `scripts/level/tutorial_director.gd`（新） | 教学进度：一张表、一个索引、由 `move_changed` 推进 |
| `scripts/level/tutorial_obstacle.gd`（新） | 单个障碍的摆放状态机：摆放 / 跟随 / 锁定 |
| `scripts/level/growing_solid.gd`（新） | 生长时序：视觉先用 alpha，碰撞在生长完成时一次性启用 |
| `tests/test_torus_wrap.gd`（新） | Task 1 |
| `tests/test_rescue_mode.gd`（新） | Task 2 |
| `tests/test_tutorial_director.gd`（新） | Task 3 |
| `tests/test_tutorial_obstacle.gd`（新） | Task 4 |
| `tests/test_growing_solid.gd`（新） | Task 5 |

---

## Task 1: 环面循环

**Files:**
- Modify: `scripts/player/moves/move_manager.gd`
- Create: `scripts/level/torus_wrap.gd`
- Test: `tests/test_torus_wrap.gd`

**Interfaces:**
- Consumes: `Player.global_position`, `Player.move_manager`
- Produces:
  - `MoveManager.current_is_scripted() -> bool`
  - `TorusWrap.player: Player`（`@export`）
  - `TorusWrap.period: float`（`@export`，默认 100.0）
  - `TorusWrap.wrapped(offset: Vector3)`（signal，Task 6 消费）

- [ ] **Step 1: 写失败的测试**

创建 `tests/test_torus_wrap.gd`：

```gdscript
extends ParkourTest

# The plain is a torus: all four edges join. What is asserted here is the
# contract -- where the body lands, and the one state that forbids the move.
# The period itself is a tuning value and is not asserted.

const TestWorld = preload("res://tests/world_fixture.gd")

var _world: Dictionary = {}
var _wrap: TorusWrap

func after_each() -> void:
	if is_instance_valid(_wrap):
		_wrap.queue_free()
	_wrap = null
	if _world.is_empty():
		return
	TestWorld.teardown(_world)
	_world = {}

func _wrapped_world(period: float) -> Player:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(10)
	var player: Player = _world["player"]
	_wrap = TorusWrap.new()
	_wrap.player = player
	_wrap.period = period
	get_tree().root.add_child(_wrap)
	return player

func test_crossing_the_east_edge_lands_you_in_the_west() -> void:
	var player: Player = await _wrapped_world(100.0)
	var height: float = player.global_position.y
	player.global_position = Vector3(51.0, height, 0.0)
	await step(2)
	assert_almost_eq(player.global_position.x, -49.0, 0.01,
		"crossing +x did not put the body one period back")
	assert_almost_eq(player.global_position.z, 0.0, 0.01,
		"the crossing moved the body on an axis it should not touch")

func test_the_north_edge_wraps_the_same_way() -> void:
	var player: Player = await _wrapped_world(100.0)
	var height: float = player.global_position.y
	player.global_position = Vector3(0.0, height, -51.0)
	await step(2)
	assert_almost_eq(player.global_position.z, 49.0, 0.01,
		"crossing -z did not put the body one period back")

func test_height_is_never_touched() -> void:
	# Only the plain wraps. The tower rises out of it, and a body climbing
	# must not be dragged back down to where it started.
	var player: Player = await _wrapped_world(100.0)
	player.global_position = Vector3(51.0, 40.0, 0.0)
	await step(2)
	assert_almost_eq(player.global_position.y, 40.0, 0.01,
		"the wrap moved the body vertically")

func test_a_scripted_move_forbids_the_wrap() -> void:
	# A scripted move holds WORLD-SPACE target points -- a vault's curve, a
	# line's rail. Teleporting mid-move tears the body off its own path.
	var player: Player = await _wrapped_world(100.0)
	var height: float = player.global_position.y
	player.move_manager.start(Move.SPEED_VAULT)
	await step(1)
	player.global_position = Vector3(51.0, height, 0.0)
	await step(2)
	assert_almost_eq(player.global_position.x, 51.0, 0.01,
		"the body was teleported while a scripted move was driving it")

func test_the_offset_is_announced() -> void:
	# Task 6 moves locked obstacles by this offset, so it has to be exact.
	var player: Player = await _wrapped_world(100.0)
	var seen: Array[Vector3] = []
	_wrap.wrapped.connect(func(offset: Vector3) -> void: seen.append(offset))
	player.global_position = Vector3(51.0, player.global_position.y, 0.0)
	await step(2)
	assert_eq(seen.size(), 1, "the wrap did not announce itself exactly once")
	assert_almost_eq(seen[0].x, -100.0, 0.01, "the announced offset is wrong")
```

- [ ] **Step 2: 跑测试，确认它失败**

```sh
bun tools/run_tests.ts torus_wrap
```

预期：`Parse Error: Identifier "TorusWrap" not declared in the current scope.`

- [ ] **Step 3: 给 MoveManager 一个公开查询**

在 `scripts/player/moves/move_manager.gd` 里，`current_config()` 之后加：

```gdscript
## True while a ScriptedMove is driving the body along a computed path.
## ANYTHING THAT MOVES THE BODY FROM OUTSIDE MUST ASK THIS FIRST: a scripted
## move holds world-space target points, so a teleport mid-move tears the body
## off its own path and it finishes somewhere it was never sent.
func current_is_scripted() -> bool:
	return _current is ScriptedMove
```

- [ ] **Step 4: 写 TorusWrap**

创建 `scripts/level/torus_wrap.gd`：

```gdscript
class_name TorusWrap
extends Node

# The plain has no edges: all four join, so running in any direction never
# reaches a wall and never reaches a horizon. Crossing an edge shifts the body
# one period back along that axis.
#
# THE VOID IS WHAT MAKES THIS INVISIBLE. There is no skyline to disagree after
# the shift, and geometry beyond the collapse radius is not drawn, so the
# player has nothing to compare against. DO NOT give this level a skybox.
#
# Height is never touched. The tower rises out of the plain, and a body
# climbing it must not be dragged back to where it started.

## The body to wrap. Assigned by the level scene.
@export var player: Player

## Distance between opposite edges, in metres. Ground speed is 7.2 m/s
## (sprint is higher), so this is roughly how many seconds of running fit
## between crossings. Tuning value -- drag it in the F1 panel.
@export var period: float = 100.0

## Emitted with the shift that was just applied. Anything holding a world
## position that must stay put RELATIVE TO THE PLAYER listens to this.
signal wrapped(offset: Vector3)

func _physics_process(_delta: float) -> void:
	if player == null or period <= 0.0:
		return
	# THE ONE STATE THAT FORBIDS A WRAP. See MoveManager.current_is_scripted().
	# Scripted moves are short, so waiting one out costs nothing -- and in a
	# void the player cannot tell he was held.
	if player.move_manager != null and player.move_manager.current_is_scripted():
		return
	var offset := _offset_for(player.global_position)
	if offset == Vector3.ZERO:
		return
	player.global_position += offset
	wrapped.emit(offset)

## How far to shift a position to bring it back inside the period. Zero when
## it is already inside.
func _offset_for(position: Vector3) -> Vector3:
	var half: float = period * 0.5
	var offset := Vector3.ZERO
	if position.x > half:
		offset.x = -period
	elif position.x < -half:
		offset.x = period
	if position.z > half:
		offset.z = -period
	elif position.z < -half:
		offset.z = period
	return offset
```

- [ ] **Step 5: 跑测试，确认通过**

```sh
bun tools/run_tests.ts torus_wrap
```

预期：5 passing。

- [ ] **Step 6: 跑全量，确认没有回归**

```sh
bun tools/run_tests.ts
```

预期：全部通过（除既有的 1 个 pending：`test_hand_ik` 的求解器过冲）。

- [ ] **Step 7: 提交**

```sh
git add scripts/level/torus_wrap.gd scripts/level/torus_wrap.gd.uid \
        scripts/player/moves/move_manager.gd \
        tests/test_torus_wrap.gd tests/test_torus_wrap.gd.uid
git commit -m "feat(level): a plain whose four edges join, and the one move that forbids the seam"
```

---

## Task 2: 她不会死

**Files:**
- Modify: `scripts/level/arena.gd`
- Test: `tests/test_rescue_mode.gd`

**Interfaces:**
- Consumes: `Player.health`, `Player.move_manager.current_name`, `Arena.respawn_at_checkpoint()`
- Produces: `Arena.rescue_below_hp: float`（`@export`，默认 0.0 = 关闭）

**背景（spec「这一关里角色永远不会死」）：** 三条通往死亡的路径都要在起点被拦截。
只拦血量是不够的——`[ME:CONFIRMED 13 §13.2]` 10 m 以上必死与血量无关，跨线即进入
`FallUncontrolled`，那 −100 只是给表演收尾。教程关掉进虚空必然超过 10 m，所以血量那
条线根本不会被触碰，ragdoll 会先接管。

- [ ] **Step 1: 写失败的测试**

创建 `tests/test_rescue_mode.gd`：

```gdscript
extends ParkourTest

# Arena.rescue_below_hp turns every route to death into a white-curtain
# respawn. Asserted here: that each of the three routes is actually
# intercepted, and that zero leaves the ordinary behaviour alone.

var _arena: Arena

func after_each() -> void:
	if is_instance_valid(_arena):
		_arena.queue_free()
	_arena = null

func _arena_with(threshold: float) -> Arena:
	var scene: PackedScene = load("res://scenes/main.tscn")
	_arena = scene.instantiate() as Arena
	_arena.rescue_below_hp = threshold
	add_child_autofree(_arena)
	await step(10)
	return _arena

func test_a_wound_below_the_threshold_is_rescued() -> void:
	var arena: Arena = await _arena_with(30.0)
	var player: Player = arena.player
	assert_gt(player.health.hp, 30.0, "test setup: the player did not start healthy")
	player.take_damage(80.0, Health.Cause.HAZARD)
	await step(2)
	assert_true(arena.rescued_count > 0, "dropping below the threshold did not rescue")

func test_zero_leaves_the_ordinary_behaviour_alone() -> void:
	# A level that never sets the field must behave exactly as before.
	var arena: Arena = await _arena_with(0.0)
	var player: Player = arena.player
	player.take_damage(80.0, Health.Cause.HAZARD)
	await step(2)
	assert_eq(arena.rescued_count, 0, "a level with rescue off performed a rescue")

func test_entering_fall_uncontrolled_is_rescued() -> void:
	# THE ROUTE THAT ACTUALLY FIRES IN THIS LEVEL. Falling into the void is
	# well past the uncontrolled height, so the ragdoll takes over while
	# health is still full -- the health threshold never gets a chance.
	var arena: Arena = await _arena_with(30.0)
	var player: Player = arena.player
	player.move_manager.start(Move.FALL_UNCONTROLLED)
	await step(2)
	assert_true(arena.rescued_count > 0,
		"the ragdoll was allowed to take over in a level where she cannot die")

func test_falling_out_of_the_level_is_rescued_not_killed() -> void:
	var arena: Arena = await _arena_with(30.0)
	var player: Player = arena.player
	player.global_position = Vector3(0.0, -arena.config.pawn.fall_recovery_depth - 10.0, 0.0)
	await step(2)
	assert_true(arena.rescued_count > 0, "falling out of the level was not rescued")
```

- [ ] **Step 2: 跑测试，确认它失败**

```sh
bun tools/run_tests.ts rescue_mode
```

预期：`Invalid assignment of property 'rescue_below_hp'`。

- [ ] **Step 3: 加字段与计数器**

在 `scripts/level/arena.gd` 的 `@export var fog: FogConfig` 之后加：

```gdscript
## Health below which the level rescues instead of killing: white curtain,
## respawn at the ranked checkpoint, no death sequence, no ragdoll. It also
## reclassifies the OTHER TWO routes to death -- entering FallUncontrolled and
## falling out of the level.
##
## SHE DOES NOT DIE IN THE TUTORIAL. A death cutscene says "that was serious",
## and the tutorial's whole point is that it was not. Zero (the default) means
## this level kills normally, so no existing level changes.
##
## A LEVEL PROPERTY, NOT A PLAYER ONE, for the same reason fog is: one
## MovementConfig travels between levels, and the tutorial and the first level
## must be able to disagree about this.
@export var rescue_below_hp: float = 0.0

## How many rescues have happened. Read by tests; a level never needs it.
var rescued_count: int = 0
```

- [ ] **Step 4: 写拦截**

在 `arena.gd` 的 `_physics_process` 里，`if not is_instance_valid(player): return` 之后加：

```gdscript
	if rescue_below_hp > 0.0 and not _death_sequence.is_covering():
		# All three routes to death, intercepted at their own start. Health
		# alone is not enough: [ME:CONFIRMED 13 §13.2] a fall past
		# falling_uncontrolled_height enters FallUncontrolled with health
		# still full, so the ragdoll would take over before the bar ever
		# moved.
		var hurt: bool = player.health != null and player.health.hp < rescue_below_hp
		var ragdolling: bool = player.move_manager != null \
			and player.move_manager.current_name == Move.FALL_UNCONTROLLED
		if hurt or ragdolling:
			_rescue()
			return
```

并把落出关卡那一段的 `respawn_under_cover(Color.BLACK)` 改成：

```gdscript
	if depth < -config.pawn.fall_recovery_depth:
		# A DEATH, not a rescue -- unless this level says otherwise. Falling
		# out of the world is falling to your death by any reading the player
		# has, and teleporting them back with no curtain reads as the level
		# catching a bug rather than as an outcome. No cutscene either -- there
		# is no floor down there to topple onto.
		if rescue_below_hp > 0.0:
			_rescue()
			return
		respawn_under_cover(Color.BLACK)
```

在 `respawn_at_checkpoint()` 附近加：

```gdscript
## The tutorial's answer to everything that would otherwise be a death: full
## health, white curtain, back to the highest checkpoint reached. Costs time
## and nothing else -- which is what makes daring a shortcut the rational
## choice rather than a gamble.
func _rescue() -> void:
	rescued_count += 1
	if player.health != null:
		player.health.reset()
	respawn_at_checkpoint()
```

- [ ] **Step 5: 跑测试，确认通过**

```sh
bun tools/run_tests.ts rescue_mode
```

预期：4 passing。

- [ ] **Step 6: 跑全量**

```sh
bun tools/run_tests.ts
```

- [ ] **Step 7: 提交**

```sh
git add scripts/level/arena.gd tests/test_rescue_mode.gd tests/test_rescue_mode.gd.uid
git commit -m "feat(arena): a level where she cannot die, intercepted on all three routes"
```

---

## Task 3: 教学进度

**Files:**
- Create: `scripts/level/tutorial_director.gd`
- Test: `tests/test_tutorial_director.gd`

**Interfaces:**
- Consumes: `Player.move_manager`（`move_changed(from, to)` 信号）
- Produces:
  - `TutorialDirector.player: Player`（`@export`）
  - `TutorialDirector.lessons: Array[Dictionary]` —— 每项 `{teaches = StringName}`
  - `TutorialDirector.index: int`（只读语义）
  - `TutorialDirector.lesson_passed(index: int)`（signal）
  - `TutorialDirector.finished()`（signal，最后一课通过时发出一次）

**背景（spec「教学序列」）：** 骨架是一条心态曲线，动作只是载体。推进的信号是现成的
——`MoveManager` 已经有 `move_changed`。障碍的显隐与摆放不在本任务，见 Task 4。

- [ ] **Step 1: 写失败的测试**

创建 `tests/test_tutorial_director.gd`：

```gdscript
extends ParkourTest

# Progress is a line: it advances when the player performs the move the
# current lesson teaches, and it never goes backwards. What the lesson LOOKS
# like is Task 4's business; this asserts only the counting.

const TestWorld = preload("res://tests/world_fixture.gd")

var _world: Dictionary = {}
var _director: TutorialDirector

func after_each() -> void:
	if is_instance_valid(_director):
		_director.queue_free()
	_director = null
	if _world.is_empty():
		return
	TestWorld.teardown(_world)
	_world = {}

func _directed(lessons: Array[Dictionary]) -> Player:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(10)
	var player: Player = _world["player"]
	_director = TutorialDirector.new()
	_director.player = player
	_director.lessons = lessons
	get_tree().root.add_child(_director)
	await step(1)
	return player

func test_performing_the_taught_move_advances() -> void:
	var player: Player = await _directed([
		{teaches = Move.CROUCH},
		{teaches = Move.SLIDE},
	])
	assert_eq(_director.index, 0, "test setup: the director did not start at the first lesson")
	player.move_manager.start(Move.CROUCH)
	await step(2)
	assert_eq(_director.index, 1, "performing the taught move did not advance")

func test_an_unrelated_move_does_not_advance() -> void:
	var player: Player = await _directed([
		{teaches = Move.SLIDE},
	])
	player.move_manager.start(Move.CROUCH)
	await step(2)
	assert_eq(_director.index, 0, "an unrelated move advanced the lesson")

func test_a_lesson_passes_only_once() -> void:
	# Doing it twice is practice, not progress. Without this the second entry
	# would skip the NEXT lesson, which the player has not seen yet.
	var player: Player = await _directed([
		{teaches = Move.CROUCH},
		{teaches = Move.SLIDE},
	])
	player.move_manager.start(Move.CROUCH)
	await step(2)
	player.move_manager.start(Move.WALKING)
	await step(2)
	player.move_manager.start(Move.CROUCH)
	await step(2)
	assert_eq(_director.index, 1, "repeating a passed lesson advanced past an unseen one")

func test_the_last_lesson_announces_the_end_once() -> void:
	var player: Player = await _directed([
		{teaches = Move.CROUCH},
	])
	var ends: int = 0
	_director.finished.connect(func() -> void: ends += 1)
	player.move_manager.start(Move.CROUCH)
	await step(2)
	player.move_manager.start(Move.WALKING)
	await step(2)
	player.move_manager.start(Move.CROUCH)
	await step(2)
	assert_eq(ends, 1, "the end of the tutorial fired %d times" % ends)

func test_an_empty_table_finishes_immediately_without_crashing() -> void:
	# A level under construction has no lessons yet. It must still run.
	var player: Player = await _directed([])
	player.move_manager.start(Move.CROUCH)
	await step(2)
	assert_eq(_director.index, 0, "an empty table moved its index")
```

- [ ] **Step 2: 跑测试，确认它失败**

```sh
bun tools/run_tests.ts tutorial_director
```

预期：`Identifier "TutorialDirector" not declared`。

- [ ] **Step 3: 写 TutorialDirector**

创建 `scripts/level/tutorial_director.gd`：

```gdscript
class_name TutorialDirector
extends Node

# Teaching progress. The spine of the tutorial is a curve of ATTITUDES (see
# the spec); this class only counts where along it the player is.
#
# The signal that advances it already exists: MoveManager announces every
# transition. So a lesson is passed by DOING the thing, never by walking into
# a trigger volume and never on a timer.
#
# WHAT A LESSON LOOKS LIKE IS NOT HERE. Obstacle geometry, placement and the
# growth show belong to TutorialObstacle -- this class hands out an index and
# says when it changed.

## The body being taught. Assigned by the level scene.
@export var player: Player

## One entry per lesson, in order. Named fields rather than a positional
## array because this table will grow more of them (a hint line, an obstacle
## scene, a shortcut flag):
##   teaches  StringName -- the Move whose first performance passes this lesson
@export var lessons: Array[Dictionary] = []

## How far along the player is. The lesson at this index is the one currently
## being taught; equal to lessons.size() once every lesson is passed.
var index: int = 0

signal lesson_passed(passed_index: int)
signal finished

var _finished_announced: bool = false

func _ready() -> void:
	if player != null and player.move_manager != null:
		player.move_manager.move_changed.connect(_on_move_changed)

func _on_move_changed(_from: StringName, to: StringName) -> void:
	if index >= lessons.size():
		return
	var lesson: Dictionary = lessons[index]
	if to != lesson.get("teaches", &""):
		return
	# ONE STEP PER LESSON, NEVER TWO. Doing it a second time is practice, not
	# progress -- advancing again would skip the next lesson, which the player
	# has not been shown yet.
	var passed: int = index
	index += 1
	lesson_passed.emit(passed)
	if index >= lessons.size() and not _finished_announced:
		_finished_announced = true
		finished.emit()
```

- [ ] **Step 4: 跑测试，确认通过**

```sh
bun tools/run_tests.ts tutorial_director
```

预期：5 passing。

- [ ] **Step 5: 跑全量并提交**

```sh
bun tools/run_tests.ts
git add scripts/level/tutorial_director.gd scripts/level/tutorial_director.gd.uid \
        tests/test_tutorial_director.gd tests/test_tutorial_director.gd.uid
git commit -m "feat(level): teaching progress advances by doing, never by a trigger"
```

---

## Task 4: 障碍的摆放、跟随与锁定

**Files:**
- Create: `scripts/level/tutorial_obstacle.gd`
- Test: `tests/test_tutorial_obstacle.gd`

**Interfaces:**
- Consumes: `Player.global_position`，玩家朝向取 `-player.global_transform.basis.z`
- Produces:
  - `TutorialObstacle.player: Player`（`@export`）
  - `TutorialObstacle.spawn_distance: float`（`@export`，默认 30.0）
  - `TutorialObstacle.follow_angle_deg: float`（`@export`，默认 25.0）
  - `TutorialObstacle.min_separation: float`（`@export`，默认 12.0）
  - `TutorialObstacle.locked: bool`（只读语义）
  - `TutorialObstacle.lock()` —— 由生长开始时调用（Task 5 接上）
  - `TutorialObstacle.shift_by(offset: Vector3)` —— 由 `TorusWrap.wrapped` 调用（Task 6）
  - `TutorialObstacle.avoid: Array[TutorialObstacle]`

**背景（spec「障碍是长出来的」）：** 三条规则——摆放在玩家前方、生长未开始时跟着朝向
重摆、生长一开始就永久钉死。锁定是硬要求：少了它玩家一转头就看见障碍在虚空里飘。

- [ ] **Step 1: 写失败的测试**

创建 `tests/test_tutorial_obstacle.gd`：

```gdscript
extends ParkourTest

# Placement, following and locking. Distances and angles are tuning values and
# are not asserted -- what is asserted is that the obstacle is IN FRONT, that
# it follows only while unlocked, and that locking is absolute.

const TestWorld = preload("res://tests/world_fixture.gd")

var _world: Dictionary = {}
var _extra: Array[Node] = []

func after_each() -> void:
	for node in _extra:
		if is_instance_valid(node):
			node.queue_free()
	_extra.clear()
	if _world.is_empty():
		return
	TestWorld.teardown(_world)
	_world = {}

func _obstacle_for(player: Player) -> TutorialObstacle:
	var obstacle := TutorialObstacle.new()
	obstacle.player = player
	get_tree().root.add_child(obstacle)
	_extra.append(obstacle)
	return obstacle

func _standing_player() -> Player:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(10)
	return _world["player"]

func test_it_is_placed_in_front_of_the_player() -> void:
	var player: Player = await _standing_player()
	var obstacle := _obstacle_for(player)
	await step(2)
	var forward: Vector3 = -player.global_transform.basis.z
	var to_obstacle: Vector3 = obstacle.anchor - player.global_position
	to_obstacle.y = 0.0
	assert_gt(forward.normalized().dot(to_obstacle.normalized()), 0.9,
		"the obstacle was not placed ahead of the player")

func test_it_follows_the_player_turning_while_unlocked() -> void:
	var player: Player = await _standing_player()
	var obstacle := _obstacle_for(player)
	await step(2)
	var before: Vector3 = obstacle.anchor
	player.rotate_y(PI)
	await step(2)
	assert_gt(before.distance_to(obstacle.anchor), 1.0,
		"turning around did not move the unlocked obstacle")

func test_locking_pins_it_for_good() -> void:
	# THE HARD REQUIREMENT. Without it the player turns his head and watches
	# the obstacle drift through the void, and the level stops reading as a
	# place.
	var player: Player = await _standing_player()
	var obstacle := _obstacle_for(player)
	await step(2)
	obstacle.lock()
	var pinned: Vector3 = obstacle.anchor
	player.rotate_y(PI)
	await step(4)
	assert_almost_eq(obstacle.anchor.distance_to(pinned), 0.0, 0.001,
		"a locked obstacle moved")

func test_it_keeps_its_distance_from_one_that_is_still_leaving() -> void:
	# The player finishing an obstacle and immediately turning round makes
	# "in front" point at the one that is still collapsing.
	var player: Player = await _standing_player()
	var leaving := _obstacle_for(player)
	await step(2)
	leaving.lock()
	var arriving := _obstacle_for(player)
	arriving.avoid = [leaving]
	player.rotate_y(PI)
	await step(4)
	assert_gt(arriving.anchor.distance_to(leaving.anchor), arriving.min_separation - 0.01,
		"a new obstacle was placed on top of one that had not left yet")

func test_a_wrap_carries_a_locked_obstacle_with_it() -> void:
	# Task 6 wires TorusWrap.wrapped to this. Asserted here because the
	# contract belongs to the obstacle.
	var player: Player = await _standing_player()
	var obstacle := _obstacle_for(player)
	await step(2)
	obstacle.lock()
	var before: Vector3 = obstacle.anchor
	obstacle.shift_by(Vector3(-100.0, 0.0, 0.0))
	assert_almost_eq(obstacle.anchor.x, before.x - 100.0, 0.01,
		"a locked obstacle did not travel with the wrap")
```

- [ ] **Step 2: 跑测试，确认它失败**

```sh
bun tools/run_tests.ts tutorial_obstacle
```

预期：`Identifier "TutorialObstacle" not declared`。

- [ ] **Step 3: 写 TutorialObstacle**

创建 `scripts/level/tutorial_obstacle.gd`：

```gdscript
class_name TutorialObstacle
extends Node3D

# Where one lesson's obstacle stands. Three rules, and the third is not
# negotiable:
#
#   PLACE   anchor = player position + facing * spawn_distance
#   FOLLOW  while growth has not started, re-place it as the player turns --
#           he never sees this happen, because it only happens out where
#           nothing is drawn yet
#   LOCK    the instant growth starts, the anchor is pinned for good
#
# WITHOUT THE LOCK the player turns his head and watches the obstacle drift
# through the void, and everything this level builds up about the world being
# a real place collapses in one shot.
#
# Standing still and spinning keeps it following forever and growth never
# starts -- that is correct. It only means the player is not running yet.

## The body this obstacle places itself in front of.
@export var player: Player

## How far ahead to stand. Near enough that the growth show can be READ --
## an early design put obstacles beyond the collapse radius so the placement
## would be invisible, which hid the best-looking thing in the level. Tuning
## value.
@export var spawn_distance: float = 30.0

## Re-place once the player's facing has turned this far off the anchor.
@export var follow_angle_deg: float = 25.0

## Never stand this close to an obstacle in `avoid`.
@export var min_separation: float = 12.0

## Obstacles that still exist and must not be overlapped -- typically the one
## currently collapsing.
var avoid: Array[TutorialObstacle] = []

## Where it stands. Equal to global_position; kept as its own name because
## "anchor" is what the placement rules talk about.
var anchor: Vector3:
	get:
		return global_position

## True once growth has begun. A locked obstacle never moves again.
var locked: bool = false

func _ready() -> void:
	_place()

func _physics_process(_delta: float) -> void:
	if locked or player == null:
		return
	var forward: Vector3 = _facing()
	var to_anchor: Vector3 = anchor - player.global_position
	to_anchor.y = 0.0
	if to_anchor.length() < 0.001:
		_place()
		return
	if forward.angle_to(to_anchor.normalized()) > deg_to_rad(follow_angle_deg):
		_place()

## Pins the anchor. Called when growth starts -- see GrowingSolid.
func lock() -> void:
	locked = true

## Moves with the world. TorusWrap shifts the player one period on a crossing;
## a locked obstacle must take the same step or it lands a period behind the
## body it was placed for.
func shift_by(offset: Vector3) -> void:
	global_position += offset

func _facing() -> Vector3:
	if player == null:
		return Vector3.FORWARD
	var forward: Vector3 = -player.global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.001:
		return Vector3.FORWARD
	return forward.normalized()

func _place() -> void:
	if player == null:
		return
	var base: Vector3 = player.global_position
	var forward: Vector3 = _facing()
	var distance: float = spawn_distance
	# Pushed further out until it clears everything still standing. Safe at
	# any distance: this happens before the obstacle is drawn.
	for _attempt in 8:
		var candidate: Vector3 = base + forward * distance
		if not _too_close(candidate):
			global_position = candidate
			return
		distance += min_separation
	global_position = base + forward * distance

func _too_close(candidate: Vector3) -> bool:
	for other in avoid:
		if is_instance_valid(other) and other.anchor.distance_to(candidate) < min_separation:
			return true
	return false
```

- [ ] **Step 4: 跑测试，确认通过**

```sh
bun tools/run_tests.ts tutorial_obstacle
```

预期：5 passing。

- [ ] **Step 5: 跑全量并提交**

```sh
bun tools/run_tests.ts
git add scripts/level/tutorial_obstacle.gd scripts/level/tutorial_obstacle.gd.uid \
        tests/test_tutorial_obstacle.gd tests/test_tutorial_obstacle.gd.uid
git commit -m "feat(level): an obstacle stands ahead, follows until it is seen, then never moves"
```

---

## Task 5: 生长的时序

**Files:**
- Create: `scripts/level/growing_solid.gd`
- Test: `tests/test_growing_solid.gd`

**Interfaces:**
- Consumes: `TutorialObstacle.lock()`
- Produces:
  - `GrowingSolid.grow_time: float`（`@export`，默认 1.2）
  - `GrowingSolid.body: CollisionObject3D`（`@export`）
  - `GrowingSolid.obstacle: TutorialObstacle`（`@export`，可空）
  - `GrowingSolid.begin()` / `GrowingSolid.collapse()`
  - `GrowingSolid.solid: bool`
  - `GrowingSolid.progress: float`（0..1）
  - `GrowingSolid.grown()` / `GrowingSolid.gone()`（signals）

**背景（spec「演出可以先简陋，时序不能」）：** MVP 用 alpha，不做 shader。但时序契约
从第一版就要成立：碰撞在生长完成的那一刻一次性启用，绝不让碰撞面跟着生长面爬。

- [ ] **Step 1: 写失败的测试**

创建 `tests/test_growing_solid.gd`：

```gdscript
extends ParkourTest

# The TIMING contract, which is all that is asserted. What growth LOOKS like
# is alpha today and a shader later, and neither is tested: the point of
# separating them is that the look can change without touching this.

var _solid: GrowingSolid
var _body: StaticBody3D

func after_each() -> void:
	if is_instance_valid(_solid):
		_solid.queue_free()
	_solid = null
	_body = null

func _growing(seconds: float) -> GrowingSolid:
	_solid = GrowingSolid.new()
	_solid.grow_time = seconds
	_body = StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 1.0, 2.0)
	shape.shape = box
	_body.add_child(shape)
	_solid.add_child(_body)
	_solid.body = _body
	add_child_autofree(_solid)
	await step(1)
	return _solid

func test_it_is_not_solid_before_it_has_finished_growing() -> void:
	# THE WHOLE POINT. A player who arrives early must pass through, not
	# stumble into a half-built wall he cannot see.
	var solid: GrowingSolid = await _growing(1.0)
	solid.begin()
	await step(10)
	assert_gt(solid.progress, 0.0, "test setup: growth did not start")
	assert_lt(solid.progress, 1.0, "test setup: growth finished too fast to observe")
	assert_false(solid.solid, "the obstacle was solid while still growing")

func test_it_becomes_solid_when_growth_completes() -> void:
	var solid: GrowingSolid = await _growing(0.1)
	solid.begin()
	await step(20)
	assert_true(solid.solid, "growth finished without the obstacle becoming solid")

func test_growth_announces_itself_once() -> void:
	var solid: GrowingSolid = await _growing(0.1)
	var grown: int = 0
	solid.grown.connect(func() -> void: grown += 1)
	solid.begin()
	await step(30)
	assert_eq(grown, 1, "growth announced itself %d times" % grown)

func test_collapse_gives_up_solidity_immediately() -> void:
	# Collapsing geometry must stop blocking the moment it starts to go --
	# a player running through the space it used to occupy is the whole
	# reason it is leaving.
	var solid: GrowingSolid = await _growing(0.1)
	solid.begin()
	await step(20)
	assert_true(solid.solid, "test setup: it never became solid")
	solid.collapse()
	await step(1)
	assert_false(solid.solid, "a collapsing obstacle was still blocking")

func test_beginning_locks_the_obstacle_it_belongs_to() -> void:
	# Growth starting IS the moment the anchor is pinned -- see
	# TutorialObstacle's own note on why the lock is not negotiable.
	var solid: GrowingSolid = await _growing(0.5)
	var obstacle := TutorialObstacle.new()
	add_child_autofree(obstacle)
	solid.obstacle = obstacle
	assert_false(obstacle.locked, "test setup: it was locked before growth began")
	solid.begin()
	await step(1)
	assert_true(obstacle.locked, "growth began without pinning the anchor")
```

- [ ] **Step 2: 跑测试，确认它失败**

```sh
bun tools/run_tests.ts growing_solid
```

预期：`Identifier "GrowingSolid" not declared`。

- [ ] **Step 3: 写 GrowingSolid**

创建 `scripts/level/growing_solid.gd`：

```gdscript
class_name GrowingSolid
extends Node3D

# The world builds itself in front of the player: an obstacle is drawn into
# existence rather than switched on. This class owns the TIMING of that; what
# it LOOKS like is deliberately separate.
#
# THE SHOW MAY START CRUDE, THE TIMING MAY NOT. Today growth is an alpha fade
# and collapse is a fade out. The wireframe, the advancing cut plane, the lit
# seam and the feathers all come later, and none of them changes a line here.
# Doing it the other way round -- look first, timing after -- leaves the
# hardest part until the geometry is buried under art.
#
# COLLISION TURNS ON IN ONE STEP, AT THE END. Never let the collision surface
# follow the growth surface: that is another order of complexity, and it is
# unnecessary as long as the level keeps
#
#     grow_time * sprint speed < placement distance - margin
#
# so the player cannot reach a half-built obstacle in the first place.

## How long the growth takes. Must satisfy the inequality above against
## TutorialObstacle.spawn_distance.
@export var grow_time: float = 1.2

## How long the collapse takes once it starts.
@export var collapse_time: float = 0.6

## The thing that blocks. Disabled until growth completes, and again the
## moment collapse begins.
@export var body: CollisionObject3D

## The placement this belongs to. Pinned when growth starts. Optional: a
## fixed piece of scenery that grows has no anchor to pin.
@export var obstacle: TutorialObstacle

## 0 before growth, 1 once fully grown.
var progress: float = 0.0

## Whether it currently blocks.
var solid: bool = false

signal grown
signal gone

enum Phase { DORMANT, GROWING, STANDING, COLLAPSING, DONE }

var _phase: int = Phase.DORMANT
var _elapsed: float = 0.0

func _ready() -> void:
	_apply_alpha(0.0)
	_set_solid(false)

func _physics_process(delta: float) -> void:
	match _phase:
		Phase.GROWING:
			_elapsed += delta
			progress = clampf(_elapsed / maxf(grow_time, 0.001), 0.0, 1.0)
			_apply_alpha(progress)
			if progress >= 1.0:
				_phase = Phase.STANDING
				_set_solid(true)
				grown.emit()
		Phase.COLLAPSING:
			_elapsed += delta
			var k: float = clampf(_elapsed / maxf(collapse_time, 0.001), 0.0, 1.0)
			_apply_alpha(1.0 - k)
			if k >= 1.0:
				_phase = Phase.DONE
				gone.emit()

## Starts growing, and pins the anchor -- growth beginning is exactly the
## moment the player can see it, which is what the lock is defined by.
func begin() -> void:
	if _phase != Phase.DORMANT:
		return
	_phase = Phase.GROWING
	_elapsed = 0.0
	if obstacle != null:
		obstacle.lock()

## Starts collapsing. Solidity is given up on the spot, not at the end: a
## player running through the space it is vacating is the reason it leaves.
func collapse() -> void:
	if _phase == Phase.COLLAPSING or _phase == Phase.DONE:
		return
	_phase = Phase.COLLAPSING
	_elapsed = 0.0
	_set_solid(false)

func _set_solid(on: bool) -> void:
	solid = on
	if body != null:
		body.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
		for child in body.get_children():
			if child is CollisionShape3D:
				(child as CollisionShape3D).disabled = not on

## MVP: plain transparency. Replaced by the dissolve shader later; nothing
## outside this function knows which is in use.
func _apply_alpha(k: float) -> void:
	for node in find_children("*", "GeometryInstance3D", true, false):
		(node as GeometryInstance3D).transparency = clampf(1.0 - k, 0.0, 1.0)
```

- [ ] **Step 4: 跑测试，确认通过**

```sh
bun tools/run_tests.ts growing_solid
```

预期：5 passing。

- [ ] **Step 5: 跑全量并提交**

```sh
bun tools/run_tests.ts
git add scripts/level/growing_solid.gd scripts/level/growing_solid.gd.uid \
        tests/test_growing_solid.gd tests/test_growing_solid.gd.uid
git commit -m "feat(level): growth owns the clock, the look is only alpha for now"
```

---

## Task 6: 把三者接起来

**Files:**
- Modify: `scripts/level/tutorial_director.gd`
- Test: `tests/test_tutorial_director.gd`（追加）

**Interfaces:**
- Consumes: Task 1 的 `TorusWrap.wrapped`、Task 4 的 `TutorialObstacle`、Task 5 的 `GrowingSolid`
- Produces:
  - `TutorialDirector.wrap: TorusWrap`（`@export`，可空）
  - `lessons` 新增可选字段 `scene: PackedScene`
  - `TutorialDirector.current_obstacle() -> TutorialObstacle`

**背景：** 到这里三个模块各自可测但互不相识。本任务只做**一条**接线：环面传送时把
已经站住的障碍一起搬走。

**为什么不在这里接「生长 / 崩塌」：** 那需要 `TutorialObstacle` 反过来持有它的
`GrowingSolid`，而 `GrowingSolid` 已经持有 `obstacle` —— 两个 `class_name` 互相
typed 引用会形成解析环，GDScript 在 parse 期就会失败（同 CLAUDE.md 里
`Player -> moves -> Move` 必须单向的那条）。正确的方向要看障碍 `.tscn` 的实际结构，
而那还没定。放进下一份计划。

- [ ] **Step 1: 追加失败的测试**

在 `tests/test_tutorial_director.gd` 末尾追加：

```gdscript
func test_a_wrap_carries_the_standing_obstacle() -> void:
	# The body is shifted one period on a crossing. An obstacle already
	# growing in front of it must take the same step, or what was dead ahead
	# is suddenly a hundred metres behind.
	var player: Player = await _directed([{teaches = Move.CROUCH}])
	var wrap := TorusWrap.new()
	wrap.player = player
	wrap.period = 100.0
	get_tree().root.add_child(wrap)
	_extra_free(wrap)
	_director.wrap = wrap
	_director.attach_wrap()

	var obstacle := TutorialObstacle.new()
	obstacle.player = player
	get_tree().root.add_child(obstacle)
	_extra_free(obstacle)
	await step(2)
	obstacle.lock()
	_director.adopt(obstacle)
	var before: Vector3 = obstacle.anchor

	player.global_position = Vector3(51.0, player.global_position.y, 0.0)
	await step(2)
	assert_almost_eq(obstacle.anchor.x, before.x - 100.0, 0.01,
		"the standing obstacle did not travel with the wrap")
```

并在该文件顶部的 `var _director: TutorialDirector` 之后加：

```gdscript
var _loose: Array[Node] = []

func _extra_free(node: Node) -> void:
	_loose.append(node)
```

在 `after_each()` 开头加：

```gdscript
	for node in _loose:
		if is_instance_valid(node):
			node.queue_free()
	_loose.clear()
```

- [ ] **Step 2: 跑测试，确认它失败**

```sh
bun tools/run_tests.ts tutorial_director
```

预期：`Invalid call. Nonexistent function 'attach_wrap'`。

- [ ] **Step 3: 在 TutorialDirector 上加接线**

在 `tutorial_director.gd` 的 `@export var lessons` 之后加：

```gdscript
## The level's wrap, if it has one. A standing obstacle must take the same
## step the body takes when it crosses an edge.
@export var wrap: TorusWrap
```

`lessons` 的注释表格补一行：

```gdscript
##   scene    PackedScene -- optional; the obstacle instanced for this lesson
```

在 `_ready()` 里追加：

```gdscript
	attach_wrap()
```

并在文件末尾加：

```gdscript
## Connects the level's wrap. Idempotent, and safe with no wrap at all -- a
## level without one simply never shifts.
func attach_wrap() -> void:
	if wrap != null and not wrap.wrapped.is_connected(_on_wrapped):
		wrap.wrapped.connect(_on_wrapped)

## Takes ownership of an obstacle already in the scene, so it travels on a
## wrap. Used by the level builder and by tests.
func adopt(obstacle: TutorialObstacle) -> void:
	if obstacle != null and not _standing.has(obstacle):
		_standing.append(obstacle)

## The obstacle for the lesson currently being taught, or null.
func current_obstacle() -> TutorialObstacle:
	for obstacle in _standing:
		if is_instance_valid(obstacle) and not obstacle.locked:
			return obstacle
	return _standing.back() if not _standing.is_empty() else null

func _on_wrapped(offset: Vector3) -> void:
	for obstacle in _standing:
		if is_instance_valid(obstacle):
			obstacle.shift_by(offset)
```

以及成员：

```gdscript
## Obstacles currently in the world, oldest first. They travel together on a
## wrap, so this list is what the wrap talks to.
var _standing: Array[TutorialObstacle] = []
```

- [ ] **Step 4: 跑测试，确认通过**

```sh
bun tools/run_tests.ts tutorial_director
```

预期：6 passing。

- [ ] **Step 5: 跑全量**

```sh
bun tools/run_tests.ts
```

- [ ] **Step 6: 提交**

```sh
git add scripts/level/tutorial_director.gd tests/test_tutorial_director.gd
git commit -m "feat(level): standing obstacles travel with the body across a seam"
```

---

## 交付后作者要做的事（不在本计划内）

这份计划交付的是**机制**，不是关卡。搭完之后地图仍然要手工调，而下列决定只能在灰盒里
用眼睛拨定：

- `TorusWrap.period` 的实际值（约束是 `2 x 崩塌半径 < period`）
- `TutorialObstacle.spawn_distance` 与 `GrowingSolid.grow_time` 的配比，必须满足
  `grow_time x 冲刺速度 < spawn_distance - 余量`
- `lessons` 表的实际条目——曲线八段已定，每段用什么障碍承载没定
- 每个障碍的 `.tscn` 几何

## 本计划**不**包含（下一份计划）

- 螺旋塔的逐段揭示、地板塌陷与下方光海
- 音乐的乐句对齐（塔等乐句边界）
- 开场分流与 `progress.cfg`
- 生长/崩塌的 shader 与羽毛粒子
- **`TutorialDirector` 与 `GrowingSolid` 的接线**（一课开始时生长、通过时崩塌）。
  依赖障碍 `.tscn` 的实际结构，且要先定 `TutorialObstacle` 与 `GrowingSolid` 之间
  哪一边持有哪一边——两边互相 typed 引用会形成 `class_name` 解析环。
- 三句开场提示与卡住后的第二次提示（文案里禁止出现字面键名，见 spec）
