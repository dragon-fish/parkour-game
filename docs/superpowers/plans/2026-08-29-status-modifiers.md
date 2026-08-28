# 临时状态修饰（Status Modifiers）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给 Player 加一层可被关卡体积附加/解除的临时状态（限速、禁用动作、强制视角、禁用具体兴趣点、受伤硬直），各个 Move 对其无感知。

**Architecture:** 一个有限的 `Effect` 枚举 + 一个 `RefCounted` 的 `StatusList` 挂在 `Player.statuses` 上，键为 `(effect, subject)`，冲突由体积的 `priority` 图层裁定。每条状态只有一个 `seconds` 生命周期（`INF` 或有限）；区域性附着靠 `ModifierVolume` 每 `refresh_interval` 重施来实现，因此不需要追踪谁在体积内。各落点读 `StatusList` 的查询方法，全部是既有的单一读取点。

**Tech Stack:** Godot 4.7 / GDScript，GUT 测试框架（经 `bun tools/run_tests.ts`）。

**Spec:** [`docs/superpowers/specs/2026-08-29-status-modifiers-design.md`](../specs/2026-08-29-status-modifiers-design.md)

## Global Constraints

- **引擎二进制在 `.engine/`，绝不用 PATH 上的 `godot`。** 项目锁定 Godot **4.7**。
- **跑测试一律用 `bun tools/run_tests.ts`**，不要手搓 `gut_cmdln`。带参数可只跑匹配的文件：`bun tools/run_tests.ts status`。
- **代码注释一律英文，不得出现 emoji。**
- **唯一带标记的是关于原作的断言**，用 ASCII 标签：`[ME:CONFIRMED]` / `[ME:DERIVED]` / `[ME:INFERRED]` / `[ME:COMMUNITY]` / `[ME:UNKNOWN]`，出处写在标签内如 `[ME:CONFIRMED 12 §12.3]`。其余一律不加标记。
- **注释存在是为了不再犯同一个错，不是为了让人读历史。** 只写约束、坑、禁令；不写日期、不写 before/after、不写对话。逻辑变了就重写注释，不要追加。
- **表现值（手感数值）不写单元测试**，只测结构性不变量。见 `.claude/skills/tuning-dials-not-rules`。
- **Commit message 用英文，遵循 Conventional Commits。**
- 分支已存在：`feat/status-modifiers`。**不要合并到 master。**
- 新文件放在 `scripts/player/status/`（新目录）与 `scripts/level/`。**绝不创建名为 `local` 或 `local_*` 的目录。**
- **测试里造 Player 一律用 `tests/world_fixture.gd` 的 `TestWorld.build(get_tree(), MovementConfig.new())`，用完 `TestWorld.teardown(world)`。** 直接 `instantiate()` 得到的 Player 没有 config，也没有 `fall_tracker` / `speed_energy` / `statuses`——**`Player.setup()` 才是构造点，`_ready()` 不是。**

---

### Task 1: `Status` 枚举、`StatusSpec` 与 `StatusList` 核心

**Files:**
- Create: `scripts/player/status/status.gd`
- Create: `scripts/player/status/status_spec.gd`
- Create: `scripts/player/status/status_list.gd`
- Test: `tests/test_status_list.gd`

**Interfaces:**
- Consumes: 无
- Produces:
  - `Status.Effect`（枚举，见下）、`Status.View { NONE, FIRST, THIRD }`
  - `StatusSpec`（`Resource`）字段：`effect: Status.Effect`、`amount: float`、`subject: StringName`、`view: Status.View`、`seconds: float`
  - `StatusList.apply(spec: StatusSpec, source: Object, priority: int) -> bool`（施加成功返回 true）
  - `StatusList.remove(effect: int, subject: StringName) -> void`（`subject` 为空则删该 effect 的全部）
  - `StatusList.clear_all() -> void`
  - `StatusList.tick(delta: float) -> void`
  - `StatusList.has(effect: int, subject: StringName = &"") -> bool`
  - `StatusList.entry_count() -> int`
  - signals `status_applied(effect: int, subject: StringName)` / `status_removed(effect: int, subject: StringName)`

- [ ] **Step 1: 写失败的测试**

创建 `tests/test_status_list.gd`：

```gdscript
extends ParkourTest

# Pure logic, no physics world -- StatusList owns no node and does no queries,
# the same stance as FallTracker and SpeedEnergy.

func _spec(effect: int, seconds: float = INF, amount: float = 0.0, \
		subject: StringName = &"") -> StatusSpec:
	var s := StatusSpec.new()
	s.effect = effect
	s.seconds = seconds
	s.amount = amount
	s.subject = subject
	return s

func _source(name: String) -> Node:
	var n := Node.new()
	n.name = name
	autofree(n)
	return n

func test_two_subjects_of_the_same_effect_coexist() -> void:
	# The key is (effect, subject): blocking one rope must not unblock another.
	var list := StatusList.new()
	var a := _source("a")
	list.apply(_spec(Status.Effect.BLOCK_INTEREST_LINE, INF, 0.0, &"pipe1"), a, 0)
	list.apply(_spec(Status.Effect.BLOCK_INTEREST_LINE, INF, 0.0, &"pipe2"), a, 0)
	assert_eq(list.entry_count(), 2, "two subjects collapsed into one entry")
	assert_true(list.has(Status.Effect.BLOCK_INTEREST_LINE, &"pipe1"), "pipe1 missing")
	assert_true(list.has(Status.Effect.BLOCK_INTEREST_LINE, &"pipe2"), "pipe2 missing")

func test_the_same_key_never_stacks() -> void:
	var list := StatusList.new()
	var a := _source("a")
	list.apply(_spec(Status.Effect.SPEED_CAP, INF, 0.5), a, 0)
	list.apply(_spec(Status.Effect.SPEED_CAP, INF, 0.3), a, 0)
	assert_eq(list.entry_count(), 1, "same key stacked instead of replacing")

func test_the_same_source_always_refreshes() -> void:
	# A polling volume re-applies at its OWN priority every refresh_interval.
	# If equal priority were ignored across the board it would starve itself.
	var list := StatusList.new()
	var a := _source("a")
	list.apply(_spec(Status.Effect.SPEED_CAP, 0.5, 0.5), a, 0)
	list.tick(0.4)
	assert_true(list.apply(_spec(Status.Effect.SPEED_CAP, 0.5, 0.5), a, 0), \
		"a source could not refresh its own status")
	list.tick(0.4)
	assert_true(list.has(Status.Effect.SPEED_CAP), "the volume starved its own status")

func test_a_higher_layer_wins_and_a_lower_one_is_ignored() -> void:
	var list := StatusList.new()
	var low := _source("low")
	var high := _source("high")
	list.apply(_spec(Status.Effect.SPEED_CAP, INF, 0.5), low, 0)
	assert_true(list.apply(_spec(Status.Effect.SPEED_CAP, INF, 0.3), high, 1), \
		"a higher layer was refused")
	assert_almost_eq(list.amount_of(Status.Effect.SPEED_CAP), 0.3, 0.0001, \
		"the higher layer did not take effect")
	assert_false(list.apply(_spec(Status.Effect.SPEED_CAP, INF, 0.9), low, 0), \
		"a lower layer overwrote a higher one")
	assert_almost_eq(list.amount_of(Status.Effect.SPEED_CAP), 0.3, 0.0001, \
		"the lower layer changed the value anyway")

func test_equal_layers_from_different_sources_keep_the_incumbent() -> void:
	var list := StatusList.new()
	var a := _source("a")
	var b := _source("b")
	list.apply(_spec(Status.Effect.SPEED_CAP, INF, 0.5), a, 0)
	assert_false(list.apply(_spec(Status.Effect.SPEED_CAP, INF, 0.3), b, 0), \
		"an equal layer displaced the incumbent")
	assert_almost_eq(list.amount_of(Status.Effect.SPEED_CAP), 0.5, 0.0001, \
		"the incumbent's value changed")

func test_an_equal_layer_conflict_is_reported_once() -> void:
	# Polling would otherwise repeat the warning every refresh_interval and
	# make the console unusable.
	var list := StatusList.new()
	var a := _source("a")
	var b := _source("b")
	list.apply(_spec(Status.Effect.SPEED_CAP, INF, 0.5), a, 0)
	for i in 5:
		list.apply(_spec(Status.Effect.SPEED_CAP, INF, 0.3), b, 0)
	assert_eq(list.warning_count(), 1, "the same conflict was reported more than once")

func test_a_countdown_expires_and_infinity_does_not() -> void:
	var list := StatusList.new()
	var a := _source("a")
	list.apply(_spec(Status.Effect.BLOCK_JUMP, 1.0), a, 0)
	list.apply(_spec(Status.Effect.BLOCK_SLIDE, INF), a, 0)
	list.tick(0.9)
	assert_true(list.has(Status.Effect.BLOCK_JUMP), "expired early")
	list.tick(0.2)
	assert_false(list.has(Status.Effect.BLOCK_JUMP), "countdown did not expire")
	assert_true(list.has(Status.Effect.BLOCK_SLIDE), "INF expired")

func test_remove_without_a_subject_takes_every_subject() -> void:
	var list := StatusList.new()
	var a := _source("a")
	list.apply(_spec(Status.Effect.BLOCK_INTEREST_LINE, INF, 0.0, &"pipe1"), a, 0)
	list.apply(_spec(Status.Effect.BLOCK_INTEREST_LINE, INF, 0.0, &"pipe2"), a, 0)
	list.remove(Status.Effect.BLOCK_INTEREST_LINE, &"")
	assert_eq(list.entry_count(), 0, "a bare remove left subjects behind")

func test_remove_with_a_subject_takes_only_that_one() -> void:
	var list := StatusList.new()
	var a := _source("a")
	list.apply(_spec(Status.Effect.BLOCK_INTEREST_LINE, INF, 0.0, &"pipe1"), a, 0)
	list.apply(_spec(Status.Effect.BLOCK_INTEREST_LINE, INF, 0.0, &"pipe2"), a, 0)
	list.remove(Status.Effect.BLOCK_INTEREST_LINE, &"pipe1")
	assert_false(list.has(Status.Effect.BLOCK_INTEREST_LINE, &"pipe1"), "pipe1 survived")
	assert_true(list.has(Status.Effect.BLOCK_INTEREST_LINE, &"pipe2"), "pipe2 was taken too")

func test_clear_all_empties_the_list_and_the_warning_memory() -> void:
	var list := StatusList.new()
	var a := _source("a")
	var b := _source("b")
	list.apply(_spec(Status.Effect.SPEED_CAP, INF, 0.5), a, 0)
	list.apply(_spec(Status.Effect.SPEED_CAP, INF, 0.3), b, 0)
	list.clear_all()
	assert_eq(list.entry_count(), 0, "clear_all left entries")
	list.apply(_spec(Status.Effect.SPEED_CAP, INF, 0.5), a, 0)
	list.apply(_spec(Status.Effect.SPEED_CAP, INF, 0.3), b, 0)
	assert_eq(list.warning_count(), 2, "the warning memory survived clear_all")

func test_signals_report_what_arrived_and_what_left() -> void:
	var list := StatusList.new()
	var a := _source("a")
	watch_signals(list)
	list.apply(_spec(Status.Effect.BLOCK_JUMP, 1.0), a, 0)
	assert_signal_emitted(list, "status_applied", "no status_applied")
	list.tick(1.1)
	assert_signal_emitted(list, "status_removed", "no status_removed")
```

- [ ] **Step 2: 跑测试确认它失败**

Run: `bun tools/run_tests.ts status_list`
Expected: FAIL，报 `Identifier "StatusList" not declared`（三个类都还不存在）。

- [ ] **Step 3: 写实现**

创建 `scripts/player/status/status.gd`：

```gdscript
class_name Status

# The closed vocabulary of temporary modifications a level may put on the
# player. An enum rather than a class hierarchy: the set is small, fixed, and
# author-facing, and a value that does not exist cannot be authored by mistake.
#
# DO NOT add BLOCK_WALKING / BLOCK_FALLING / BLOCK_LANDING /
# BLOCK_FALL_UNCONTROLLED. Blocking any of those strands the state machine or
# leaves the body hanging in mid-air with nothing to run. Their absence from
# this enum IS the guard -- there is no validation to write, no warning to
# raise, and no error to report, because the mistake cannot be expressed.

## The three-valued answer StatusList.forced_view() gives, and the values
## StatusSpec.view may take. NONE is only ever RETURNED -- an author cannot
## write it, because "no FORCE_VIEW status" already means no override.
enum View { NONE, FIRST, THIRD }

## One effect does one thing. Payload fields are read per the table below;
## every effect not listed reads none of them.
##
##   effect                 reads
##   ---------------------  ------------------------------
##   SPEED_CAP              amount   = ceiling factor (0..1)
##   FORCE_VIEW             view     = View.FIRST / THIRD
##   BLOCK_INTEREST_LINE    subject  = InterestLine.tag
##   everything else        nothing
##
## DO NOT put a second meaning into any payload field. A new meaning is a new
## field -- see .claude/skills/naming-config-fields.
enum Effect {
	SPEED_CAP,
	FORCE_VIEW,
	BLOCK_JUMP,
	BLOCK_SLIDE,
	BLOCK_SKILL_ROLL,
	BLOCK_COIL,
	BLOCK_CROUCH,
	BLOCK_WALL_RUN,
	BLOCK_WALL_CLIMB,
	BLOCK_GRAB,
	BLOCK_SPEED_VAULT,
	BLOCK_LADDER,
	BLOCK_ZIPLINE,
	BLOCK_SWING,
	BLOCK_TURN_180,
	BLOCK_INTEREST_LINE,
	STAGGER,
}
```

创建 `scripts/player/status/status_spec.gd`：

```gdscript
class_name StatusSpec
extends Resource

# One line a level author fills in on a ModifierVolume: which effect, its
# payload, and how long it lasts. Which payload field an effect reads is
# documented once, above Status.Effect.

@export var effect: Status.Effect = Status.Effect.SPEED_CAP
## Ceiling factor for SPEED_CAP. Left at 0 by every other effect.
@export var amount: float = 0.0
## InterestLine.tag for BLOCK_INTEREST_LINE. Left empty by every other effect.
@export var subject: StringName = &""
## FORCE_VIEW only.
@export var view: Status.View = Status.View.FIRST
## How long this lasts. INF means "until something removes it".
@export var seconds: float = INF
```

创建 `scripts/player/status/status_list.gd`：

```gdscript
class_name StatusList
extends RefCounted

# The temporary modifications currently on the player.
#
# Deliberately RefCounted and fed plain values: it owns no node and does no
# queries, so the whole layer can be tested without a physics world -- the
# same stance as FallTracker and SpeedEnergy.
#
# KEYED BY (effect, subject), at most one entry per key. `subject` is part of
# the key because BLOCK_INTEREST_LINE must be able to forbid several ropes at
# once; keying on the effect alone would let a level block exactly one. Every
# other effect leaves subject empty and so degrades to one entry per effect.

## Reported so a HUD, a sound, or the debug panel can react. REPORT ONLY --
## nothing here votes on whether a status is applied. Godot signals cannot
## return a value, and their dispatch order follows connection order, which
## follows scene structure; "may the player jump" must not change because a
## node was dragged in the editor.
signal status_applied(effect: int, subject: StringName)
signal status_removed(effect: int, subject: StringName)

## key -> {effect, subject, amount, view, seconds_left, source, priority}
var _entries: Dictionary = {}
## Conflicts already reported, so polling cannot repeat one every refresh.
var _warned: Dictionary = {}

static func _key(effect: int, subject: StringName) -> String:
	return "%d|%s" % [effect, subject]

## Puts `spec` on the player, or refuses. Returns whether it took effect.
##
## The refusal rules exist because two volumes may legitimately overlap:
##   same source          -> always refreshes
##   higher priority      -> overwrites
##   lower priority       -> ignored
##   equal, different src -> incumbent keeps its place, reported once
##
## THE FIRST RULE IS LOAD-BEARING, not an optimisation. A volume with a
## refresh_interval re-applies at its OWN priority; if equal priority were
## ignored across the board it would ignore its own refresh, and the status
## would expire while the player is still standing inside the volume.
func apply(spec: StatusSpec, source: Object, priority: int) -> bool:
	var key := _key(spec.effect, spec.subject)
	var existing: Dictionary = _entries.get(key, {})
	if not existing.is_empty() and existing["source"] != source:
		var incumbent: int = existing["priority"]
		if priority < incumbent:
			return false
		if priority == incumbent:
			_warn_conflict(key, existing["source"], source)
			return false
	var fresh := existing.is_empty()
	_entries[key] = {
		effect = int(spec.effect),
		subject = spec.subject,
		amount = spec.amount,
		view = int(spec.view),
		seconds_left = spec.seconds,
		source = source,
		priority = priority,
	}
	if fresh:
		status_applied.emit(int(spec.effect), spec.subject)
	return true

## Takes `effect` off. An empty `subject` takes every subject of that effect;
## a named one takes only that entry.
func remove(effect: int, subject: StringName = &"") -> void:
	for key in _entries.keys():
		var e: Dictionary = _entries[key]
		if e["effect"] != effect:
			continue
		if subject != &"" and e["subject"] != subject:
			continue
		_entries.erase(key)
		status_removed.emit(effect, e["subject"])

func clear_all() -> void:
	for key in _entries.keys():
		var e: Dictionary = _entries[key]
		status_removed.emit(e["effect"], e["subject"])
	_entries.clear()
	# The warning memory goes with it: a fresh life should report a conflict
	# it meets again, or the second run of a level is silent about a real
	# authoring mistake.
	_warned.clear()

## Ages every countdown. INF entries are left alone.
func tick(delta: float) -> void:
	for key in _entries.keys():
		var e: Dictionary = _entries[key]
		if is_inf(e["seconds_left"]):
			continue
		e["seconds_left"] -= delta
		if e["seconds_left"] <= 0.0:
			_entries.erase(key)
			status_removed.emit(e["effect"], e["subject"])

func has(effect: int, subject: StringName = &"") -> bool:
	return _entries.has(_key(effect, subject))

## The payload of one entry, or 0.0 when it is not present.
func amount_of(effect: int, subject: StringName = &"") -> float:
	var e: Dictionary = _entries.get(_key(effect, subject), {})
	return e.get("amount", 0.0)

func entry_count() -> int:
	return _entries.size()

## Diagnostics for the tests -- how many DISTINCT conflicts have been reported.
func warning_count() -> int:
	return _warned.size()

func _warn_conflict(key: String, incumbent: Object, newcomer: Object) -> void:
	var mark := "%s|%d|%d" % [key, incumbent.get_instance_id(), newcomer.get_instance_id()]
	if _warned.has(mark):
		return
	_warned[mark] = true
	push_warning("StatusList: %s and %s both claim %s at the same priority; " % \
		[incumbent, newcomer, key] + "the first one keeps it. Give one a higher priority.")
```

- [ ] **Step 4: 跑测试确认通过**

Run: `bun tools/run_tests.ts status_list`
Expected: PASS，11 个测试全绿。

若 `test_a_countdown_expires_and_infinity_does_not` 失败并报"expired early"，检查 `tick()` 是否在同一次调用里既减了时间又立刻判过期——`0.9` 之后应当还剩 `0.1`。

- [ ] **Step 5: 提交**

```bash
git add scripts/player/status/ tests/test_status_list.gd
git commit -m "feat(status): a temporary modification keyed by effect and subject, settled by layer"
```

---

### Task 2: `StatusList` 的查询接口

**Files:**
- Modify: `scripts/player/status/status_list.gd`（追加查询方法与动作名映射表）
- Test: `tests/test_status_list.gd`（追加）

**Interfaces:**
- Consumes: Task 1 的 `StatusList._entries`、`Status.Effect`、`Status.View`
- Produces:
  - `StatusList.speed_scale() -> float`
  - `StatusList.is_move_blocked(move_name: StringName) -> bool`
  - `StatusList.is_line_blocked(line_tag: StringName) -> bool`
  - `StatusList.forced_view() -> int`

- [ ] **Step 1: 写失败的测试**

追加到 `tests/test_status_list.gd`：

```gdscript
func test_speed_scale_is_one_without_a_cap() -> void:
	var list := StatusList.new()
	assert_almost_eq(list.speed_scale(), 1.0, 0.0001, "an empty list scaled the cap")

func test_speed_scale_reports_the_cap_in_force() -> void:
	var list := StatusList.new()
	list.apply(_spec(Status.Effect.SPEED_CAP, INF, 0.5), _source("a"), 0)
	assert_almost_eq(list.speed_scale(), 0.5, 0.0001, "the cap was not reported")

func test_a_blocked_move_is_reported_by_its_own_name() -> void:
	var list := StatusList.new()
	list.apply(_spec(Status.Effect.BLOCK_JUMP), _source("a"), 0)
	assert_true(list.is_move_blocked(Move.JUMP), "JUMP was not blocked")
	assert_false(list.is_move_blocked(Move.SLIDE), "SLIDE was blocked too")

func test_a_move_with_no_effect_of_its_own_can_never_be_blocked() -> void:
	# WALKING / FALLING / LANDING / FALL_UNCONTROLLED have no enum value, so
	# the table has no row for them and the answer is always false. This is the
	# other half of the guard: the mistake cannot be authored, and it cannot be
	# reached by accident either.
	var list := StatusList.new()
	for name in [Move.WALKING, Move.FALLING, Move.LANDING, Move.FALL_UNCONTROLLED]:
		assert_false(list.is_move_blocked(name), "%s was blockable" % name)

func test_only_the_named_line_is_blocked() -> void:
	var list := StatusList.new()
	list.apply(_spec(Status.Effect.BLOCK_INTEREST_LINE, INF, 0.0, &"pipe1"), _source("a"), 0)
	assert_true(list.is_line_blocked(&"pipe1"), "pipe1 was not blocked")
	assert_false(list.is_line_blocked(&"pipe2"), "pipe2 was blocked too")
	assert_false(list.is_line_blocked(&""), "an untagged line was blocked")

func test_forced_view_is_none_until_something_forces_it() -> void:
	var list := StatusList.new()
	assert_eq(list.forced_view(), Status.View.NONE, "an empty list forced a view")

func test_forced_view_reports_which_view_is_forced() -> void:
	var list := StatusList.new()
	var spec := _spec(Status.Effect.FORCE_VIEW)
	spec.view = Status.View.FIRST
	list.apply(spec, _source("a"), 0)
	assert_eq(list.forced_view(), Status.View.FIRST, "the forced view was not reported")

func test_the_two_views_are_one_key_so_the_layer_decides() -> void:
	# First and third person are two VALUES of one effect, not two effects. As
	# two effects they would be two keys, could coexist, and the priority rule
	# -- which only compares within a key -- would never see them.
	var list := StatusList.new()
	var first := _spec(Status.Effect.FORCE_VIEW)
	first.view = Status.View.FIRST
	var third := _spec(Status.Effect.FORCE_VIEW)
	third.view = Status.View.THIRD
	list.apply(first, _source("low"), 0)
	list.apply(third, _source("high"), 1)
	assert_eq(list.entry_count(), 1, "the two views became two entries")
	assert_eq(list.forced_view(), Status.View.THIRD, "the higher layer did not win")
```

- [ ] **Step 2: 跑测试确认它失败**

Run: `bun tools/run_tests.ts status_list`
Expected: FAIL，报 `Invalid call. Nonexistent function 'speed_scale'`。

- [ ] **Step 3: 写实现**

追加到 `scripts/player/status/status_list.gd` 末尾：

```gdscript
# --- queries -----------------------------------------------------------------
#
# Read straight off the entry table rather than folded into a per-tick
# resolution object: at most one entry answers each question, so there is
# nothing to fold and nothing to allocate.

## Which move name maps to which blocking effect.
##
## A move absent from this table can never be blocked, whatever a caller asks.
## WALKING, FALLING, LANDING and FALL_UNCONTROLLED are absent on purpose -- see
## the note above Status.Effect.
const MOVE_EFFECTS: Dictionary = {
	Move.JUMP: Status.Effect.BLOCK_JUMP,
	Move.SLIDE: Status.Effect.BLOCK_SLIDE,
	Move.SKILL_ROLL: Status.Effect.BLOCK_SKILL_ROLL,
	Move.COIL: Status.Effect.BLOCK_COIL,
	Move.CROUCH: Status.Effect.BLOCK_CROUCH,
	Move.WALL_RUN: Status.Effect.BLOCK_WALL_RUN,
	Move.WALL_CLIMB: Status.Effect.BLOCK_WALL_CLIMB,
	Move.GRAB: Status.Effect.BLOCK_GRAB,
	Move.INTO_GRAB: Status.Effect.BLOCK_GRAB,
	Move.SPEED_VAULT: Status.Effect.BLOCK_SPEED_VAULT,
	Move.LADDER: Status.Effect.BLOCK_LADDER,
	Move.ZIPLINE: Status.Effect.BLOCK_ZIPLINE,
	Move.SWING: Status.Effect.BLOCK_SWING,
	Move.TURN_180: Status.Effect.BLOCK_TURN_180,
}

## The ground speed ceiling factor in force, or 1.0.
func speed_scale() -> float:
	var key := _key(Status.Effect.SPEED_CAP, &"")
	var e: Dictionary = _entries.get(key, {})
	return e.get("amount", 1.0) if not e.is_empty() else 1.0

func is_move_blocked(move_name: StringName) -> bool:
	if not MOVE_EFFECTS.has(move_name):
		return false
	return has(MOVE_EFFECTS[move_name])

## An untagged line is never blocked: BLOCK_INTEREST_LINE addresses by name,
## and a line the author did not name has no name to address.
func is_line_blocked(line_tag: StringName) -> bool:
	if line_tag == &"":
		return false
	return has(Status.Effect.BLOCK_INTEREST_LINE, line_tag)

func forced_view() -> int:
	var e: Dictionary = _entries.get(_key(Status.Effect.FORCE_VIEW, &""), {})
	return e.get("view", Status.View.NONE) if not e.is_empty() else Status.View.NONE
```

- [ ] **Step 4: 跑测试确认通过**

Run: `bun tools/run_tests.ts status_list`
Expected: PASS，19 个测试全绿。

`Move` 是全局 class_name，`bun tools/run_tests.ts` 会先刷新脚本类缓存，所以 `Move.JUMP` 可直接引用；若报 `Identifier "Move" not declared`，说明没走这个脚本。

- [ ] **Step 5: 提交**

```bash
git add scripts/player/status/status_list.gd tests/test_status_list.gd
git commit -m "feat(status): read the list directly, and let an absent enum value be the guard"
```

---

### Task 3: 挂到 Player，接上 `speed_cap()`

**Files:**
- Modify: `scripts/player/player.gd`（新增 `statuses` 字段；`_ready` 构造；`_physics_process` 里 tick；`speed_cap()` 乘系数）
- Test: `tests/test_status_player.gd`

**Interfaces:**
- Consumes: `StatusList`
- Produces: `Player.statuses: StatusList`

- [ ] **Step 1: 写失败的测试**

创建 `tests/test_status_player.gd`：

```gdscript
extends ParkourTest

# The wiring between StatusList and the single read points each effect lands
# on. Values (0.5, 2 s) are NOT asserted -- they are tuning dials. What is
# asserted is that the reading changes at all, and that it changes in the one
# place every caller already goes through.

const TestWorld = preload("res://tests/world_fixture.gd")

var _worlds: Array = []

# A Player does NOT configure itself: setup(config, input) has to be called
# after it enters the tree, or config, fall_tracker, speed_energy and statuses
# are all null. TestWorld.build() does that, and gives a floor to stand on.
func _player() -> Player:
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	_worlds.append(world)
	return world["player"]

func after_each() -> void:
	for world in _worlds:
		TestWorld.teardown(world)
	_worlds.clear()

func _cap_spec(scale: float) -> StatusSpec:
	var s := StatusSpec.new()
	s.effect = Status.Effect.SPEED_CAP
	s.amount = scale
	s.seconds = INF
	return s

func test_a_speed_cap_scales_what_every_move_asks_for() -> void:
	var p := _player()
	await step(1)
	var free_cap: float = p.speed_cap()
	p.statuses.apply(_cap_spec(0.5), p, 0)
	assert_almost_eq(p.speed_cap(), free_cap * 0.5, 0.0001, \
		"speed_cap() ignored the status")

func test_removing_the_cap_restores_the_ceiling_immediately() -> void:
	# The energy budget is deliberately NOT cleared while capped, so the
	# ceiling comes straight back rather than having to be re-earned.
	var p := _player()
	await step(1)
	var free_cap: float = p.speed_cap()
	p.statuses.apply(_cap_spec(0.5), p, 0)
	p.statuses.remove(Status.Effect.SPEED_CAP)
	assert_almost_eq(p.speed_cap(), free_cap, 0.0001, "the ceiling did not come back")

func test_the_player_ages_its_own_statuses() -> void:
	var p := _player()
	await step(1)
	var s := _cap_spec(0.5)
	s.seconds = 1.0 / 30.0
	p.statuses.apply(s, p, 0)
	assert_true(p.statuses.has(Status.Effect.SPEED_CAP), "the status never landed")
	await step(4)
	assert_false(p.statuses.has(Status.Effect.SPEED_CAP), \
		"nothing ticked the list down")
```

- [ ] **Step 2: 跑测试确认它失败**

Run: `bun tools/run_tests.ts status_player`
Expected: FAIL，报 `Invalid access to property or key 'statuses'`。

- [ ] **Step 3: 写实现**

在 `scripts/player/player.gd` 的 `var fall_tracker: FallTracker` 声明附近（约 195 行）加字段：

```gdscript
## Temporary modifications a level has put on this player -- speed caps,
## forbidden moves, a forced view. Read through the query methods; nothing
## outside StatusList interprets an entry.
var statuses: StatusList
```

在 **`setup()`**（1029 行起，*不是* `_ready()`）中，`fall_tracker = FallTracker.new()` / `speed_energy = SpeedEnergy.new(...)` 那两行之后加：

```gdscript
	statuses = StatusList.new()
```

把 `speed_cap()`（约 3519 行）改为：

```gdscript
func speed_cap() -> float:
	# Scaled HERE rather than at each caller: this is the one function every
	# move asks "how fast may I go", so a status applied to it reaches all of
	# them and none of them needs to know statuses exist. Same shape as
	# MoveConfig.speed_modifier, which the crouch already rides.
	return speed_energy.cap() * statuses.speed_scale()
```

在 `_physics_process` 中 `_tick_timers(delta, input)` 那一行之后加：

```gdscript
	# Aged alongside the other timers and BEFORE the moves run, so a status
	# that expires this tick is already gone by the time anything reads it.
	statuses.tick(delta)
```

- [ ] **Step 4: 跑测试确认通过**

Run: `bun tools/run_tests.ts status_player`
Expected: PASS，3 个测试全绿。

- [ ] **Step 5: 跑全套，确认没打破既有测试**

Run: `bun tools/run_tests.ts`
Expected: 与本任务开始前相同的通过数。`speed_cap()` 被所有移动测试读，是本计划里最容易产生回归的一处改动。

- [ ] **Step 6: 提交**

```bash
git add scripts/player/player.gd tests/test_status_player.gd
git commit -m "feat(status): the ceiling every move asks for now answers to the level"
```

---

### Task 4: `BLOCK_JUMP` / `BLOCK_SLIDE` / `BLOCK_SKILL_ROLL` 分路由

**Files:**
- Modify: `scripts/player/player.gd`（`consume_jump()`、`consume_buffered_jump()`）
- Modify: `scripts/player/moves/walking_move.gd`（滑铲入口）
- Modify: `scripts/player/moves/airborne_move.gd`（`settle_landing()` 的 `rolled` 判定）
- Test: `tests/test_status_player.gd`（追加）

**Interfaces:**
- Consumes: `Player.statuses.is_move_blocked()`
- Produces: 无新签名

- [ ] **Step 1: 写失败的测试**

追加到 `tests/test_status_player.gd`：

```gdscript
func _block_spec(effect: int) -> StatusSpec:
	var s := StatusSpec.new()
	s.effect = effect
	s.seconds = INF
	return s

func test_a_blocked_jump_never_applies_its_launch_velocity() -> void:
	# THE POINT OF THIS TEST. walking_move.gd sets velocity.y BEFORE it returns
	# JUMP, so refusing the transition in MoveManager.can_enter() would leave
	# the body launched but still Walking. The block has to land on the buffer.
	var p := _player()
	await step(1)
	p.statuses.apply(_block_spec(Status.Effect.BLOCK_JUMP), p, 0)
	assert_false(p.consume_jump(), "a blocked jump was still spendable")
	assert_false(p.consume_buffered_jump(), "a blocked buffered jump was spendable")

func test_a_blocked_jump_does_not_eat_the_buffered_press() -> void:
	# Refusing must not spend the press: the player let go of nothing, and the
	# press has to still be there the moment the block lifts.
	var p := _player()
	await step(1)
	p.statuses.apply(_block_spec(Status.Effect.BLOCK_JUMP), p, 0)
	p.arm_jump_buffer_for_test()
	assert_false(p.consume_jump(), "the block did not hold")
	p.statuses.remove(Status.Effect.BLOCK_JUMP)
	assert_true(p.consume_jump(), "the block swallowed the press")
```

`arm_jump_buffer_for_test()` 在 Step 3 一并加。

- [ ] **Step 2: 跑测试确认它失败**

Run: `bun tools/run_tests.ts status_player`
Expected: FAIL，`consume_jump()` 仍返回 true（或报 `arm_jump_buffer_for_test` 不存在）。

- [ ] **Step 3: 写实现**

在 `scripts/player/player.gd` 中，把 `consume_jump()` 与 `consume_buffered_jump()` 各自的第一行改为先问状态：

```gdscript
func consume_jump() -> bool:
	# REFUSED HERE, not in MoveManager.can_enter(). WalkingMove writes the
	# launch velocity and calls move_and_slide() BEFORE it returns JUMP, so a
	# refusal at the transition would leave the body in the air and the state
	# on the ground. Refusing the spend keeps the whole branch unentered.
	#
	# Returns false WITHOUT clearing the buffer: the player pressed, and the
	# press must still be there the moment the block lifts.
	if statuses.is_move_blocked(Move.JUMP):
		return false
	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0
		return true
	return false
```

`consume_buffered_jump()` 同样在函数体第一行加：

```gdscript
	if statuses.is_move_blocked(Move.JUMP):
		return false
```

在 `consume_jump()` 附近加测试用的挂钩：

```gdscript
## Arms the jump buffer directly. FOR TESTS: the keyboard path fills this from
## a press edge, which a headless test has no way to produce.
func arm_jump_buffer_for_test() -> void:
	_jump_buffer_timer = config.pawn.jump_buffer_time
	_coyote_timer = config.pawn.coyote_time
```

在 `scripts/player/moves/walking_move.gd` 中，把 `if player.consume_roll():`（约 69 行）改为：

```gdscript
		# Gated BEFORE consume_roll(), so a blocked slide does not spend the
		# press -- the same reason the jump block sits on the buffer rather
		# than on the transition.
		if not player.statuses.is_move_blocked(SLIDE) and player.consume_roll():
```

在 `scripts/player/moves/airborne_move.gd` 的 `settle_landing()` 中，把 `rolled` 的计算（约 318 行）改为：

```gdscript
	# The block is short-circuited BEFORE consume_roll() for two reasons: the
	# press is not swallowed (it can still open a slide on the next tick), and
	# _apply_landing_cost() below is charged as UNROLLED -- refusing the
	# SKILL_ROLL transition later would keep the roll's speed discount while
	# no roll ever happened.
	var rolled: bool = not player.statuses.is_move_blocked(SKILL_ROLL) \
		and fall_height >= config.pawn.skill_roll_landing_height \
		and player.consume_roll()
```

- [ ] **Step 4: 跑测试确认通过**

Run: `bun tools/run_tests.ts status_player`
Expected: PASS，5 个测试全绿。

- [ ] **Step 5: 跑全套**

Run: `bun tools/run_tests.ts`
Expected: 与 Task 3 结束时相同的通过数。若滑铲或落地相关测试红了，检查 `and` 的短路顺序——`is_move_blocked` 必须在 `consume_roll()` 左边。

- [ ] **Step 6: 提交**

```bash
git add scripts/player/player.gd scripts/player/moves/walking_move.gd scripts/player/moves/airborne_move.gd tests/test_status_player.gd
git commit -m "feat(status): block a move where it commits, not where it announces itself"
```

---

### Task 5: `MoveManager` 的 `can_enter()` 与 `STAGGER`

**Files:**
- Modify: `scripts/player/moves/move_manager.gd`
- Test: `tests/test_status_move_manager.gd`

**Interfaces:**
- Consumes: `Player.statuses.is_move_blocked()`、`Status.Effect.STAGGER`
- Produces: 无新签名（`can_enter()` 语义扩展）

- [ ] **Step 1: 写失败的测试**

创建 `tests/test_status_move_manager.gd`：

```gdscript
extends ParkourTest

const TestWorld = preload("res://tests/world_fixture.gd")

var _worlds: Array = []

# A Player does NOT configure itself: setup(config, input) has to be called
# after it enters the tree, or config, fall_tracker, speed_energy and statuses
# are all null. TestWorld.build() does that, and gives a floor to stand on.
func _player() -> Player:
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	_worlds.append(world)
	return world["player"]

func after_each() -> void:
	for world in _worlds:
		TestWorld.teardown(world)
	_worlds.clear()

func _spec(effect: int) -> StatusSpec:
	var s := StatusSpec.new()
	s.effect = effect
	s.seconds = INF
	return s

func test_a_blocked_move_cannot_be_entered() -> void:
	var p := _player()
	await step(1)
	assert_true(p.move_manager.can_enter(Move.WALL_RUN), "the fixture starts blocked")
	p.statuses.apply(_spec(Status.Effect.BLOCK_WALL_RUN), p, 0)
	assert_false(p.move_manager.can_enter(Move.WALL_RUN), "the block did not reach can_enter")

func test_an_unblockable_move_is_always_enterable() -> void:
	var p := _player()
	await step(1)
	for name in [Move.WALKING, Move.FALLING, Move.LANDING]:
		assert_true(p.move_manager.can_enter(name), "%s was refused" % name)

func test_a_stagger_puts_the_body_into_the_landing_lockout() -> void:
	# STAGGER says "go there"; the red tint, the camera dip and the 2 s lockout
	# all belong to LandingMove and come along for free.
	var p := _player()
	await step(1)
	p.move_manager.start(Move.WALKING)
	p.statuses.apply(_spec(Status.Effect.STAGGER), p, 0)
	await step(2)
	assert_eq(p.move_manager.current_name, Move.LANDING, \
		"a stagger did not reach the lockout")

func test_a_stagger_is_ignored_while_already_dying() -> void:
	var p := _player()
	await step(1)
	p.move_manager.start(Move.FALL_UNCONTROLLED)
	p.statuses.apply(_spec(Status.Effect.STAGGER), p, 0)
	await step(2)
	assert_eq(p.move_manager.current_name, Move.FALL_UNCONTROLLED, \
		"a stagger interrupted a death")
```

- [ ] **Step 2: 跑测试确认它失败**

Run: `bun tools/run_tests.ts status_move_manager`
Expected: FAIL，`can_enter` 仍返回 true，且状态停在 `WALKING`。

- [ ] **Step 3: 写实现**

在 `scripts/player/moves/move_manager.gd` 中给 `MoveManager` 加一个 player 引用（若已有则复用；`Move.player` 已存在，但管理器自身需要）。在类顶部字段区加：

```gdscript
## Set by Player at registration, for the two questions the manager itself
## asks about statuses. Untyped for the same reason Move.player is -- see the
## note above Move's own name constants.
var player
```

在 `scripts/player/player.gd` 注册 moves 的地方（`move_manager.register(...)` 附近）加一行 `move_manager.player = self`。

把 `can_enter()` 改为：

```gdscript
func can_enter(move_name: StringName) -> bool:
	if _redo_cooldowns.has(move_name):
		return false
	# A level may forbid a move outright. Asked HERE for the same reason the
	# cooldown is: no move can forget, and a refusal never drops the tick's
	# transition intent into some third state. The three moves that commit
	# before they announce themselves (JUMP, SLIDE, SKILL_ROLL) are refused
	# earlier instead -- see Player.consume_jump().
	if player != null and player.statuses.is_move_blocked(move_name):
		return false
	return true
```

在 `physics_update()` 中，把 `var next: StringName = _turn_requested(input)` 改为：

```gdscript
	# A stagger outranks the turn, and both are arbitrated here rather than
	# inside a move, for the same reason: they are facts about the whole move
	# set. FALL_UNCONTROLLED is exempt -- a body already dying has nothing
	# left to stumble.
	var next: StringName = Move.KEEP
	if player != null and player.statuses.has(Status.Effect.STAGGER) \
			and current_name != Move.FALL_UNCONTROLLED and current_name != Move.LANDING:
		player.statuses.remove(Status.Effect.STAGGER)
		next = Move.LANDING
	if next == Move.KEEP:
		next = _turn_requested(input)
```

- [ ] **Step 4: 跑测试确认通过**

Run: `bun tools/run_tests.ts status_move_manager`
Expected: PASS，4 个测试全绿。

- [ ] **Step 5: 跑全套**

Run: `bun tools/run_tests.ts`
Expected: 与 Task 4 结束时相同的通过数。

- [ ] **Step 6: 提交**

```bash
git add scripts/player/moves/move_manager.gd scripts/player/player.gd tests/test_status_move_manager.gd
git commit -m "feat(status): the manager refuses a forbidden move and honours a stagger"
```

---

### Task 6: `InterestLine.tag` 与 `nearest_interest_line()` 过滤

**Files:**
- Modify: `scripts/level/interest_line.gd`（新增 `tag` 导出）
- Modify: `scripts/player/player.gd`（`nearest_interest_line()`）
- Test: `tests/test_status_interest_lines.gd`

**Interfaces:**
- Consumes: `Player.statuses.is_line_blocked()`
- Produces: `InterestLine.tag: StringName`

- [ ] **Step 1: 写失败的测试**

创建 `tests/test_status_interest_lines.gd`：

```gdscript
extends ParkourTest

const TestWorld = preload("res://tests/world_fixture.gd")

var _worlds: Array = []

# A Player does NOT configure itself: setup(config, input) has to be called
# after it enters the tree, or config, fall_tracker, speed_energy and statuses
# are all null. TestWorld.build() does that, and gives a floor to stand on.
func _player() -> Player:
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	_worlds.append(world)
	return world["player"]

func after_each() -> void:
	for world in _worlds:
		TestWorld.teardown(world)
	_worlds.clear()

func _line(tag: StringName, at: Vector3) -> InterestLine:
	var l := InterestLine.new()
	l.kind = InterestLine.Kind.LADDER
	l.tag = tag
	l.curve = Curve3D.new()
	l.curve.add_point(Vector3.ZERO)
	l.curve.add_point(Vector3(0.0, 3.0, 0.0))
	add_child_autofree(l)
	l.global_position = at
	return l

func _block(tag: StringName) -> StatusSpec:
	var s := StatusSpec.new()
	s.effect = Status.Effect.BLOCK_INTEREST_LINE
	s.subject = tag
	s.seconds = INF
	return s

func test_a_blocked_line_is_skipped_and_its_sibling_is_not() -> void:
	# The point of the whole effect: the grain is the OBJECT, not the class.
	# Blocking one pipe must leave the other one climbable.
	var p := _player()
	await step(1)
	var near := _line(&"pipe1", p.global_position + Vector3(1.0, 0.0, 0.0))
	var far := _line(&"pipe2", p.global_position + Vector3(3.0, 0.0, 0.0))
	p.enter_interest_line(near)
	p.enter_interest_line(far)
	assert_eq(p.nearest_interest_line(InterestLine.Kind.LADDER), near, \
		"the fixture did not pick the nearer line")
	p.statuses.apply(_block(&"pipe1"), p, 0)
	assert_eq(p.nearest_interest_line(InterestLine.Kind.LADDER), far, \
		"a blocked line was still offered, or its sibling was blocked too")

func test_an_untagged_line_cannot_be_blocked() -> void:
	var p := _player()
	await step(1)
	var anon := _line(&"", p.global_position + Vector3(1.0, 0.0, 0.0))
	p.enter_interest_line(anon)
	p.statuses.apply(_block(&""), p, 0)
	assert_eq(p.nearest_interest_line(InterestLine.Kind.LADDER), anon, \
		"an untagged line was blocked by an empty subject")
```

- [ ] **Step 2: 跑测试确认它失败**

Run: `bun tools/run_tests.ts status_interest_lines`
Expected: FAIL，报 `Invalid assignment of property 'tag'`。

- [ ] **Step 3: 写实现**

在 `scripts/level/interest_line.gd` 的 `@export var reach_radius` 附近加：

```gdscript
## Lets a level forbid THIS line by name -- see Status.Effect.BLOCK_INTEREST_LINE.
## Empty means the line cannot be singled out; it still obeys a blanket ban on
## its whole kind.
@export var tag: StringName = &""
```

在 `scripts/player/player.gd` 的 `nearest_interest_line()` 循环体内，`if not is_instance_valid(line) or line.kind != kind:` 之后加一条：

```gdscript
		# A level may forbid one named line while its siblings stay usable.
		# Filtered HERE because this is the only place anything asks which
		# line is reachable; the six callers all come through it.
		#
		# ONLY THE CATCH IS REFUSED, never a ride already under way: LineMove
		# stores its line on entry and stops asking, so a rope forbidden under
		# a player already hanging from it does not drop them.
		if statuses.is_line_blocked(line.tag):
			continue
```

- [ ] **Step 4: 跑测试确认通过**

Run: `bun tools/run_tests.ts status_interest_lines`
Expected: PASS，2 个测试全绿。

- [ ] **Step 5: 跑全套**

Run: `bun tools/run_tests.ts`
Expected: 与 Task 5 结束时相同的通过数。

- [ ] **Step 6: 提交**

```bash
git add scripts/level/interest_line.gd scripts/player/player.gd tests/test_status_interest_lines.gd
git commit -m "feat(status): forbid one rope by name without forbidding rope"
```

---

### Task 7: `CameraRig` 的强制视角

**Files:**
- Modify: `scripts/camera/camera_rig.gd`
- Modify: `scripts/player/player.gd`（V 键）
- Test: `tests/test_status_forced_view.gd`

**Interfaces:**
- Consumes: `Player.statuses.forced_view()`
- Produces: `CameraRig.forced_view: int`、`CameraRig.in_third_person() -> bool`

- [ ] **Step 1: 写失败的测试**

创建 `tests/test_status_forced_view.gd`：

```gdscript
extends ParkourTest

const TestWorld = preload("res://tests/world_fixture.gd")

var _worlds: Array = []

# A Player does NOT configure itself: setup(config, input) has to be called
# after it enters the tree, or config, fall_tracker, speed_energy and statuses
# are all null. TestWorld.build() does that, and gives a floor to stand on.
func _player() -> Player:
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	_worlds.append(world)
	return world["player"]

func after_each() -> void:
	for world in _worlds:
		TestWorld.teardown(world)
	_worlds.clear()

func _force(view: int) -> StatusSpec:
	var s := StatusSpec.new()
	s.effect = Status.Effect.FORCE_VIEW
	s.view = view
	s.seconds = INF
	return s

func test_a_forced_view_overrides_the_preference() -> void:
	var p := _player()
	await step(1)
	p.camera_rig.third_person = true
	p.statuses.apply(_force(Status.View.FIRST), p, 0)
	await step(1)
	assert_false(p.camera_rig.in_third_person(), "the force did not take")

func test_the_saved_preference_is_not_touched() -> void:
	# The whole reason forced_view is its own field: toggle_third_person()
	# saves to disk on every change, so sharing the field would rewrite the
	# player's preference the first time they walk indoors.
	var p := _player()
	await step(1)
	p.camera_rig.third_person = true
	p.statuses.apply(_force(Status.View.FIRST), p, 0)
	await step(1)
	assert_true(p.camera_rig.third_person, "the force overwrote the preference")
	p.statuses.remove(Status.Effect.FORCE_VIEW)
	await step(1)
	assert_true(p.camera_rig.in_third_person(), "the preference did not come back")

func test_the_view_key_does_nothing_while_forced() -> void:
	var p := _player()
	await step(1)
	p.camera_rig.third_person = false
	p.statuses.apply(_force(Status.View.FIRST), p, 0)
	await step(1)
	p.camera_rig.toggle_third_person()
	assert_false(p.camera_rig.third_person, "the key changed the preference under a force")
```

- [ ] **Step 2: 跑测试确认它失败**

Run: `bun tools/run_tests.ts status_forced_view`
Expected: FAIL，报 `Invalid call. Nonexistent function 'in_third_person'`。

- [ ] **Step 3: 写实现**

在 `scripts/camera/camera_rig.gd` 的 `var third_person: bool = false`（约 148 行）之后加：

```gdscript
## A level's override of the viewing preference, or View.NONE.
##
## SEPARATE FROM third_person ON PURPOSE. toggle_third_person() writes the
## preference to disk every time it changes, so an override that shared the
## field would permanently rewrite what the player chose the first time they
## walked into a room that forces first person. Fed by Player each tick from
## the status list; nothing here reads the status list itself.
var forced_view: int = Status.View.NONE

## Which view is actually being rendered: the override if there is one, the
## saved preference otherwise. EVERY internal read of the view goes through
## this -- `third_person` alone means "what the player chose", which is not
## the same question.
func in_third_person() -> bool:
	if forced_view == Status.View.FIRST:
		return false
	if forced_view == Status.View.THIRD:
		return true
	return third_person
```

把 `camera_rig.gd` 中**除 `toggle_third_person()`、`save_preferences()`、`load_preferences()`、`third_person_debug()` 以外**的每一处 `third_person` 读取改为 `in_third_person()`。用以下命令逐处核对，共 6 处（497、649、673、852、1056-1057、1063 附近）：

```bash
grep -n "third_person" scripts/camera/camera_rig.gd | grep -v "third_person_back\|third_person_up\|third_person_right\|third_person_shoulder\|third_person_min\|third_person_max\|third_person_zoom\|third_person_drag\|third_person_debug\|_third_person_position\|toggle_third_person\|zoom_third_person\|nudge_third_person\|cycle_third_person"
```

在 `toggle_third_person()` 开头加：

```gdscript
func toggle_third_person() -> void:
	# Refused rather than queued: a level that forces a view is mid-scripted
	# moment, and a preference silently changed under the player would surface
	# only after they leave, which reads as the key having been eaten.
	if forced_view != Status.View.NONE:
		return
```

在 `scripts/player/player.gd` 的 `_physics_process` 中，喂给 `camera_rig` 的那一段加：

```gdscript
	if camera_rig != null:
		camera_rig.forced_view = statuses.forced_view()
```

- [ ] **Step 4: 跑测试确认通过**

Run: `bun tools/run_tests.ts status_forced_view`
Expected: PASS，3 个测试全绿。

- [ ] **Step 5: 跑全套**

Run: `bun tools/run_tests.ts`
Expected: 与 Task 6 结束时相同的通过数。相机测试若红，八成是漏改了某一处 `third_person` 读取。

- [ ] **Step 6: 提交**

```bash
git add scripts/camera/camera_rig.gd scripts/player/player.gd tests/test_status_forced_view.gd
git commit -m "feat(status): a room may force the view without rewriting what the player chose"
```

---

### Task 8: `ModifierVolume`

**Files:**
- Create: `scripts/level/modifier_volume.gd`
- Test: `tests/test_modifier_volume.gd`

**Interfaces:**
- Consumes: `StatusSpec`、`Player.statuses`
- Produces:
  - `ModifierVolume` 导出：`apply: Array[StatusSpec]`、`remove: Array[StatusSpec]`、`refresh_interval: float`、`priority: int`、`max_trigger_count: int`
  - `ModifierVolume.reset_trigger_count() -> void`
  - 组名 `"modifier_volumes"`

- [ ] **Step 1: 写失败的测试**

创建 `tests/test_modifier_volume.gd`：

```gdscript
extends ParkourTest

const TestWorld = preload("res://tests/world_fixture.gd")

var _worlds: Array = []

# A Player does NOT configure itself: setup(config, input) has to be called
# after it enters the tree, or config, fall_tracker, speed_energy and statuses
# are all null. TestWorld.build() does that, and gives a floor to stand on.
func _player() -> Player:
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	_worlds.append(world)
	return world["player"]

func after_each() -> void:
	for world in _worlds:
		TestWorld.teardown(world)
	_worlds.clear()

func _cap(scale: float, seconds: float) -> StatusSpec:
	var s := StatusSpec.new()
	s.effect = Status.Effect.SPEED_CAP
	s.amount = scale
	s.seconds = seconds
	return s

func _volume(at: Vector3) -> ModifierVolume:
	var v := ModifierVolume.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 4.0, 4.0)
	shape.shape = box
	v.add_child(shape)
	add_child_autofree(v)
	v.global_position = at
	return v

func test_walking_in_applies_and_walking_out_lets_it_lapse() -> void:
	var p := _player()
	await step(1)
	var v := _volume(p.global_position)
	v.apply = [_cap(0.5, 0.2)]
	v.refresh_interval = 0.1
	await step(20)
	assert_true(p.statuses.has(Status.Effect.SPEED_CAP), "the volume never applied")
	p.global_position += Vector3(50.0, 0.0, 0.0)
	await step(30)
	assert_false(p.statuses.has(Status.Effect.SPEED_CAP), \
		"the status outlived the volume it came from")

func test_an_infinite_status_survives_leaving_the_volume() -> void:
	var p := _player()
	await step(1)
	var v := _volume(p.global_position)
	v.apply = [_cap(0.5, INF)]
	await step(5)
	p.global_position += Vector3(50.0, 0.0, 0.0)
	await step(20)
	assert_true(p.statuses.has(Status.Effect.SPEED_CAP), \
		"an INF status was cleared by leaving")

func test_a_volume_may_both_apply_and_remove() -> void:
	# One volume, several changes -- the author must not have to place a
	# second box just to lift something.
	var p := _player()
	await step(1)
	var lock := StatusSpec.new()
	lock.effect = Status.Effect.BLOCK_JUMP
	lock.seconds = INF
	p.statuses.apply(lock, p, 0)
	var v := _volume(p.global_position)
	v.apply = [_cap(0.5, INF)]
	v.remove = [lock]
	await step(5)
	assert_false(p.statuses.has(Status.Effect.BLOCK_JUMP), "the volume did not remove")
	assert_true(p.statuses.has(Status.Effect.SPEED_CAP), "the volume did not apply")

func test_a_capped_volume_stops_after_its_last_entry() -> void:
	var p := _player()
	await step(1)
	var v := _volume(p.global_position)
	v.apply = [_cap(0.5, INF)]
	v.max_trigger_count = 1
	await step(5)
	p.statuses.remove(Status.Effect.SPEED_CAP)
	p.global_position += Vector3(50.0, 0.0, 0.0)
	await step(5)
	p.global_position = v.global_position
	await step(10)
	assert_false(p.statuses.has(Status.Effect.SPEED_CAP), \
		"a volume capped at one entry fired on the second")

func test_refreshing_does_not_spend_the_entry_count() -> void:
	# The count is about ENTRIES. A polling volume refreshes many times per
	# visit, and counting those would use the whole budget on the first tick.
	var p := _player()
	await step(1)
	var v := _volume(p.global_position)
	v.apply = [_cap(0.5, 0.2)]
	v.refresh_interval = 0.05
	v.max_trigger_count = 1
	await step(40)
	assert_true(p.statuses.has(Status.Effect.SPEED_CAP), \
		"the refreshes ate the entry budget")
```

- [ ] **Step 2: 跑测试确认它失败**

Run: `bun tools/run_tests.ts modifier_volume`
Expected: FAIL，报 `Identifier "ModifierVolume" not declared`。

- [ ] **Step 3: 写实现**

创建 `scripts/level/modifier_volume.gd`：

```gdscript
@tool
class_name ModifierVolume
extends Area3D

# A region that puts temporary statuses on whoever walks in, of any shape:
# give it whatever CollisionShape3D children the spot needs. The same stance
# as Checkpoint -- the volume carries the shape and the intent, and nothing
# else.
#
# [ME:CONFIRMED 12 §12.2] The original's own volumes carry no behaviour data
# at all: class plus Kismet is the whole story. This one carries data instead,
# because there is no Kismet graph here to carry it -- a deliberate departure,
# not an oversight.

## Put these on whoever enters.
@export var apply: Array[StatusSpec] = []
## Take these off whoever enters. Only `effect` and `subject` are read;
## `amount`, `view` and `seconds` are ignored. An empty `subject` takes every
## subject of that effect.
##
## StatusSpec rather than Array[Status.Effect] because the latter has nowhere
## to put a subject, and "unblock pipe A while pipe B stays blocked" would
## become inexpressible.
@export var remove: Array[StatusSpec] = []

## Above zero, re-apply `apply` this often while a body is inside. This is how
## a region-wide modification is expressed: pair it with a StatusSpec.seconds
## of the same length and the status is continually renewed while the player
## is in, and lapses on its own shortly after they leave.
##
## THE POINT IS THAT NOTHING TRACKS MEMBERSHIP. No body_exited handler, no
## list of who is inside, and therefore no overlap bookkeeping.
@export var refresh_interval: float = 0.0

## Which layer this volume speaks on. When two volumes claim the same status,
## the higher layer wins; equal layers keep the incumbent and report once.
## Leave at 0 unless volumes actually overlap.
@export var priority: int = 0

## How many ENTRIES this volume acts on, 0 for unlimited. Refreshes do not
## count -- a polling volume renews many times per visit, and charging those
## would spend the whole budget on the first tick.
##
## [ME:CONFIRMED 12 §12.3] An integer rather than a boolean because the
## original's own SequenceEvent carries MaxTriggerCount (0 = unlimited), and
## because a looping level is re-entered: "only on the first lap" and "every
## lap" are two different needs and a boolean covers neither middle.
@export var max_trigger_count: int = 0

var _entries_used: int = 0
var _refresh_owed: float = 0.0

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	add_to_group("modifier_volumes")
	body_entered.connect(_on_body_entered)
	set_physics_process(refresh_interval > 0.0)

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or refresh_interval <= 0.0:
		return
	_refresh_owed -= delta
	if _refresh_owed > 0.0:
		return
	_refresh_owed = refresh_interval
	for body in get_overlapping_bodies():
		if body.has_method("apply_status"):
			_push_apply(body)

func _on_body_entered(body: Node3D) -> void:
	# Duck-typed, the same stance as Checkpoint's volume: the volume tells
	# whoever can listen, and cares nothing for who else wanders in.
	if not body.has_method("apply_status"):
		return
	if max_trigger_count > 0 and _entries_used >= max_trigger_count:
		return
	_entries_used += 1
	for spec in remove:
		if spec != null:
			body.remove_status(spec.effect, spec.subject)
	_push_apply(body)
	# Renew immediately rather than waiting out a partial interval, so a body
	# that walks in just after a tick is not briefly unmodified.
	_refresh_owed = refresh_interval

func _push_apply(body: Node3D) -> void:
	for spec in apply:
		if spec != null:
			body.apply_status(spec, self, priority)

## Called on respawn. The count is about one life: a level that cripples the
## player at its start has to cripple them again after they die there.
func reset_trigger_count() -> void:
	_entries_used = 0
```

在 `scripts/player/player.gd` 的 `enter_interest_line()` 附近加两个 duck-typed 入口：

```gdscript
## Entry points for ModifierVolume, duck-typed the same way touch_checkpoint()
## and enter_interest_line() are: the volume does not know what a Player is.
func apply_status(spec: StatusSpec, source: Object, priority: int) -> void:
	statuses.apply(spec, source, priority)

func remove_status(effect: int, subject: StringName) -> void:
	statuses.remove(effect, subject)
```

- [ ] **Step 4: 跑测试确认通过**

Run: `bun tools/run_tests.ts modifier_volume`
Expected: PASS，5 个测试全绿。

若 `test_walking_in_applies_and_walking_out_lets_it_lapse` 失败并报"the volume never applied"，检查 Player 的 `collision_layer` 是否在 `ModifierVolume` 的 `collision_mask` 内——`Area3D` 默认 mask 是 1，Player 的 body layer 也应是 1。测试里直接改坐标而非 `move_and_slide()`，`Area3D` 需要一个物理帧才会报告重叠，所以 `await step()` 的帧数不能少。

- [ ] **Step 5: 跑全套**

Run: `bun tools/run_tests.ts`
Expected: 与 Task 7 结束时相同的通过数。

- [ ] **Step 6: 提交**

```bash
git add scripts/level/modifier_volume.gd scripts/player/player.gd tests/test_modifier_volume.gd
git commit -m "feat(level): a volume that renews what it applies, so nothing tracks who is inside"
```

---

### Task 9: 死亡复活的清理与重施

**Files:**
- Modify: `scripts/level/arena.gd`（`reset_player()`）
- Test: `tests/test_status_respawn.gd`

**Interfaces:**
- Consumes: `StatusList.clear_all()`、`ModifierVolume.reset_trigger_count()`
- Produces: 无新签名

- [ ] **Step 1: 写失败的测试**

创建 `tests/test_status_respawn.gd`：

```gdscript
extends ParkourTest

# The opening level puts INF statuses on a volume that covers the spawn. That
# shape is what these tests are about: a body that respawns INSIDE a volume
# never left it, so body_entered will not fire again on its own.

func _arena() -> Arena:
	var a: Arena = preload("res://scenes/main.tscn").instantiate()
	add_child_autofree(a)
	return a

func _cap(scale: float) -> StatusSpec:
	var s := StatusSpec.new()
	s.effect = Status.Effect.SPEED_CAP
	s.amount = scale
	s.seconds = INF
	return s

func test_a_respawn_clears_every_status() -> void:
	var a := _arena()
	await step(2)
	a.player.statuses.apply(_cap(0.5), a.player, 0)
	a.reset_player()
	await step(2)
	assert_false(a.player.statuses.has(Status.Effect.SPEED_CAP), \
		"a status survived the respawn")

func test_a_respawn_re_arms_a_capped_volume() -> void:
	var a := _arena()
	await step(2)
	var v := ModifierVolume.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, 6.0, 6.0)
	shape.shape = box
	v.add_child(shape)
	v.apply = [_cap(0.5)]
	v.max_trigger_count = 1
	a.add_child(v)
	v.global_position = a.spawn_point.global_position
	await step(5)
	assert_true(a.player.statuses.has(Status.Effect.SPEED_CAP), "the fixture never applied")
	a.reset_player()
	await step(5)
	assert_true(a.player.statuses.has(Status.Effect.SPEED_CAP), \
		"the player woke up cured: the count was not reset, or the overlap was not re-applied")
```

- [ ] **Step 2: 跑测试确认它失败**

Run: `bun tools/run_tests.ts status_respawn`
Expected: FAIL，第二个测试报"the player woke up cured"。

- [ ] **Step 3: 写实现**

在 `scripts/level/arena.gd` 的 `reset_player()` 中，`player.reset_state()` 那一行之后加：

```gdscript
	# EVERY temporary modification is a property of one life. Cleared here
	# rather than in reset_state() because the volumes that put them there are
	# a level concern, and the re-arming below needs the level anyway.
	player.statuses.clear_all()
	for volume in get_tree().get_nodes_in_group("modifier_volumes"):
		volume.reset_trigger_count()
	_reapply_overlapping_modifiers()
```

在 `reset_player()` 之后加：

```gdscript
## Re-applies every ModifierVolume the body is currently standing in.
##
## REQUIRED, NOT DEFENSIVE. A respawn teleports the body without the areas
## ever reporting an exit -- the same reason Player.reset_state() clears
## interest_lines by hand -- so a body that respawns INSIDE a volume has not
## left it and body_entered will never fire again. The opening level puts its
## permanent statuses on a volume covering the spawn point, so without this
## the player wakes up cured: able to run and jump after a death that should
## have changed nothing.
##
## Volumes with a refresh_interval would recover on their own at the next
## poll; INF ones never would. Both are covered here rather than relying on
## which kind a level happened to use.
func _reapply_overlapping_modifiers() -> void:
	if not is_instance_valid(player):
		return
	for volume in get_tree().get_nodes_in_group("modifier_volumes"):
		if volume.overlaps_body(player):
			volume.enter_body_after_respawn(player)
```

在 `scripts/level/modifier_volume.gd` 末尾加：

```gdscript
## Treats a respawn inside this volume as a fresh entry. See
## Arena._reapply_overlapping_modifiers() for why this cannot be left to the
## area's own signal.
func enter_body_after_respawn(body: Node3D) -> void:
	_on_body_entered(body)
```

- [ ] **Step 4: 跑测试确认通过**

Run: `bun tools/run_tests.ts status_respawn`
Expected: PASS，2 个测试全绿。

`overlaps_body()` 要求区域至少走过一个物理帧才有数据；`reset_player()` 本身会跳过一帧，若第二个测试仍红，把重施改为在那次 `await get_tree().physics_frame` 之后执行，并在此处注明原因。

- [ ] **Step 5: 跑全套**

Run: `bun tools/run_tests.ts`
Expected: 全绿，通过数 = Task 8 结束时的数目 + 本任务新增的 2。

- [ ] **Step 6: 提交**

```bash
git add scripts/level/arena.gd scripts/level/modifier_volume.gd tests/test_status_respawn.gd
git commit -m "fix(status): a body that respawns inside a volume never left it"
```

- [ ] **Step 7: 推送**

```bash
git push origin feat/status-modifiers
```

---

### Task 10: Inspector 里看得懂、填得快

**Files:**
- Modify: `scripts/player/status/status_spec.gd`
- Modify: `scripts/level/modifier_volume.gd`
- Test: `tests/test_status_spec_inspector.gd`

**Interfaces:**
- Consumes: Task 1 的 `StatusSpec`、Task 8 的 `ModifierVolume`
- Produces: `StatusSpec.summary() -> String`

**为什么需要**：`Array[StatusSpec]` 默认在检查器里显示成一排一模一样的 `StatusSpec`，
点开每一条才知道是什么；而且每种效果都会摊开全部四个载荷字段，其中三个对它无意义。
关卡作者摆十个体积就会开始出错。

- [ ] **Step 1: 写失败的测试**

创建 `tests/test_status_spec_inspector.gd`：

```gdscript
extends ParkourTest

# The editor-facing half of StatusSpec. Not a tuning value and not a visual --
# a wrong summary or a stray field is a level authored wrong, which is a
# structural problem.

func _spec(effect: int) -> StatusSpec:
	var s := StatusSpec.new()
	s.effect = effect
	return s

func test_the_summary_names_the_effect_and_its_payload() -> void:
	var cap := _spec(Status.Effect.SPEED_CAP)
	cap.amount = 0.5
	cap.seconds = 2.0
	var text := cap.summary()
	assert_string_contains(text, "SPEED_CAP", "the effect is not named")
	assert_string_contains(text, "0.5", "the payload is missing")
	assert_string_contains(text, "2", "the duration is missing")

func test_an_endless_status_says_so_rather_than_printing_inf() -> void:
	var block := _spec(Status.Effect.BLOCK_JUMP)
	block.seconds = INF
	assert_string_contains(block.summary(), "until removed", 		"an endless status printed a number")

func test_a_line_block_shows_which_line() -> void:
	var b := _spec(Status.Effect.BLOCK_INTEREST_LINE)
	b.subject = &"pipe1"
	assert_string_contains(b.summary(), "pipe1", "the subject is missing")

func test_only_the_fields_an_effect_reads_stay_visible() -> void:
	# _validate_property() hides the rest. Checked through the same reflection
	# the inspector uses, so this fails if the schema and the UI drift apart.
	var block := _spec(Status.Effect.BLOCK_JUMP)
	var hidden := []
	for prop in block.get_property_list():
		if prop["name"] in ["amount", "subject", "view"] 				and (prop["usage"] & PROPERTY_USAGE_EDITOR) == 0:
			hidden.append(prop["name"])
	assert_eq(hidden.size(), 3, "BLOCK_JUMP still shows payload it never reads")

	var cap := _spec(Status.Effect.SPEED_CAP)
	for prop in cap.get_property_list():
		if prop["name"] == "amount":
			assert_true((prop["usage"] & PROPERTY_USAGE_EDITOR) != 0, 				"SPEED_CAP hid the one field it does read")
```

- [ ] **Step 2: 跑测试确认它失败**

Run: `bun tools/run_tests.ts status_spec_inspector`
Expected: FAIL，报 `Nonexistent function 'summary'`。

- [ ] **Step 3: 写实现**

把 `scripts/player/status/status_spec.gd` 改为（保留 Task 1 的字段与注释，加上以下三段）：

```gdscript
@tool
class_name StatusSpec
extends Resource
```

在字段声明中给每个 setter 挂上刷新（Godot 只在 setter 里通知才会重画检查器）：

```gdscript
@export var effect: Status.Effect = Status.Effect.SPEED_CAP:
	set(value):
		effect = value
		# Both are needed: the first re-runs _validate_property() so the
		# irrelevant payload fields disappear, the second redraws the array
		# row's own label.
		notify_property_list_changed()
		_refresh_name()
@export var amount: float = 0.0:
	set(value):
		amount = value
		_refresh_name()
@export var subject: StringName = &"":
	set(value):
		subject = value
		_refresh_name()
@export var view: Status.View = Status.View.FIRST:
	set(value):
		view = value
		_refresh_name()
@export var seconds: float = INF:
	set(value):
		seconds = value
		_refresh_name()
```

追加：

```gdscript
## One line describing this entry, for a human reading a list of them.
##
## Shown as the array row's own label in the inspector: without it every row
## reads "StatusSpec" and a volume with four entries has to be opened four
## times to find out what it does.
func summary() -> String:
	var name := Status.Effect.keys()[effect]
	var payload := ""
	match effect:
		Status.Effect.SPEED_CAP:
			payload = " %.2f" % amount
		Status.Effect.FORCE_VIEW:
			payload = " %s" % Status.View.keys()[view]
		Status.Effect.BLOCK_INTEREST_LINE:
			payload = " %s" % subject
	var span := " (until removed)" if is_inf(seconds) else " (%.3g s)" % seconds
	return "%s%s%s" % [name, payload, span]

func _refresh_name() -> void:
	resource_name = summary()

## Hides the payload fields an effect does not read. The schema above
## Status.Effect is the authority; this keeps the inspector honest about it,
## so an author cannot fill in a number that will be ignored.
func _validate_property(property: Dictionary) -> void:
	var used := ""
	match effect:
		Status.Effect.SPEED_CAP:
			used = "amount"
		Status.Effect.FORCE_VIEW:
			used = "view"
		Status.Effect.BLOCK_INTEREST_LINE:
			used = "subject"
	if property.name in ["amount", "subject", "view"] and property.name != used:
		property.usage &= ~PROPERTY_USAGE_EDITOR
```

在 `scripts/level/modifier_volume.gd` 加编辑器侧的检查，让摆错的体积在场景树里就红：

```gdscript
func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	var has_shape := false
	for child in get_children():
		if child is CollisionShape3D and child.shape != null:
			has_shape = true
	if not has_shape:
		warnings.append("No CollisionShape3D with a shape: this volume can never be entered.")
	if apply.is_empty() and remove.is_empty():
		warnings.append("Neither apply nor remove is set: this volume does nothing.")
	for spec in apply:
		if spec == null:
			warnings.append("An empty row in `apply`.")
		elif spec.effect == Status.Effect.SPEED_CAP and spec.amount <= 0.0:
			warnings.append("SPEED_CAP with amount %.2f pins the player in place." % spec.amount)
		elif spec.effect == Status.Effect.BLOCK_INTEREST_LINE and spec.subject == &"":
			warnings.append("BLOCK_INTEREST_LINE with no subject blocks nothing.")
	if refresh_interval > 0.0:
		for spec in apply:
			if spec != null and is_inf(spec.seconds):
				warnings.append("refresh_interval is set but a status lasts forever: " 					+ "it will not lapse when the player leaves.")
	return warnings
```

并在 `apply` / `remove` / `refresh_interval` 的 setter 里调 `update_configuration_warnings()`，
否则改完属性警告不刷新。

- [ ] **Step 4: 跑测试确认通过**

Run: `bun tools/run_tests.ts status_spec_inspector`
Expected: PASS，4 个测试全绿。

- [ ] **Step 5: 跑全套**

Run: `bun tools/run_tests.ts`
Expected: 全绿。`@tool` 让 `StatusSpec` 在编辑器里也会跑，`_refresh_name()` 不得触碰场景树。

- [ ] **Step 6: 提交**

```bash
git add scripts/player/status/status_spec.gd scripts/level/modifier_volume.gd tests/test_status_spec_inspector.gd
git commit -m "feat(status): a volume's entries read as themselves in the inspector"
```

---

## 收尾核对

全部任务完成后：

- [ ] `bun tools/run_tests.ts` 全绿，把**实际输出**贴进汇报，不要只说"通过了"
- [ ] `<engine> --headless --script res://tools/check_references.gd` 无新增缺失引用
- [ ] `git log --oneline origin/master..HEAD` 每条 commit 意图单一
- [ ] **不合并到 master**，停在 `feat/status-modifiers` 等审阅
- [ ] 汇报里列出：实现过程中 spec 没有回答、而我自行假设的每一处，以及采取的假设
