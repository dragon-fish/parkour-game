# 平衡木（Balance）与檐走（LedgeWalk）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 复刻 ME 的平衡木与檐走：两者共用「站在线上沿线走」的骨架，差别只在身体
相对线转了多少度；Balance 在其上多一套倒立摆，失衡由模型分段倾斜 + 镜头 roll +
FOV 收缩表现。

**Architecture:** `InterestLine` 家族第四、五个客户。新抽 `LineWalkMove` 中间层
（站在线**上**，对应 Zipline/Swing 的挂在线**下**），`LedgeWalkMove` 是它的薄壳，
`BalanceMove` 在它之上加倒立摆。倒立摆是一个无阻尼二阶发散系统，唯一的随机数在
入场。失衡量是单一数据源，喂三个表现通道。

**Tech Stack:** Godot 4.7.1 GDScript，GUT 测试（`bun tools/run_tests.ts <pattern>`）。

**Spec:** `docs/superpowers/specs/2026-08-30-balance-and-ledge-walk-design.md`
（本 plan 的唯一权威；冲突以 spec 为准）。

## Global Constraints

- 分支 `feat/balance-and-ledge-walk`；提交信息纯英文 Conventional Commits。
- Godot 一律用 `.engine/Godot_v4.7.1-stable_win64_console.exe`，**只许 headless**；
  测试跑 `bun tools/run_tests.ts <pattern>`，绝不打开带窗编辑器。
- 代码注释英文，无 emoji；作者裁定引用可保留中文原话（现有文件通例）。
- 关于原作的论断用 ASCII 标签 `[ME:CONFIRMED|DERIVED|INFERRED|COMMUNITY|UNKNOWN]`，
  其余一律不加标签。
- 所有新旋钮进 `BalanceConfig` / `LedgeWalkConfig` / `CameraConfig`，不许硬编码散落。
- **表现值不写断言**：测试只钉结构不变量，不断言具体速度/角度/时长。
- ⛔ **倒立摆不许加阻尼**，⛔ **随机只在入场一次**，⛔ **檐走不许有平衡状态**。
- 不碰 `me_level*` 与 `.private/`。
- 每个 Task 结束前 `bun tools/run_tests.ts` 相关子集必须绿。

---

### Task 1: 验证两个 SkeletonModifier3D 能否叠加

spec 标注的技术风险，结果决定 Task 7 的形态。这是 spike：产出是一个答案，不是留
下的代码。

**Files:**
- Create（临时，验完即删）: `tools/probe_modifier_stack.gd`

- [ ] **Step 1: 写探针脚本**

```gdscript
# THROWAWAY. Answers one question: do two SkeletonModifier3D that both call
# set_bone_global_pose on overlapping bones compose, or does the later one
# overwrite the earlier?
extends SceneTree

func _init() -> void:
	var skel := Skeleton3D.new()
	var root := skel.add_bone("Hips")
	var spine := skel.add_bone("Spine")
	skel.set_bone_parent(spine, root)
	skel.set_bone_rest(spine, Transform3D(Basis(), Vector3(0, 0.2, 0)))
	skel.reset_bone_poses()
	get_root().add_child(skel)

	var a := _Mod.new()
	a.bone = spine
	a.axis = Vector3.RIGHT
	skel.add_child(a)
	var b := _Mod.new()
	b.bone = spine
	b.axis = Vector3.FORWARD
	skel.add_child(b)

	await process_frame
	await process_frame
	var pose: Basis = skel.get_bone_global_pose(spine).basis
	print("euler after two modifiers: ", pose.get_euler())
	print("x rotated: ", absf(pose.get_euler().x) > 0.01)
	print("z rotated: ", absf(pose.get_euler().z) > 0.01)
	quit()

class _Mod extends SkeletonModifier3D:
	var bone: int = -1
	var axis: Vector3 = Vector3.RIGHT

	func _process_modification() -> void:
		var skel := get_skeleton()
		if skel == null or bone < 0:
			return
		var pose := skel.get_bone_global_pose(bone)
		pose.basis = Basis(axis, deg_to_rad(20.0)) * pose.basis
		skel.set_bone_global_pose(bone, pose)
```

- [ ] **Step 2: 跑它**

Run: `.engine/Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tools/probe_modifier_stack.gd`

两个 `true` = 能叠加，Task 7 写独立 modifier。任何一个 `false` = 后者覆盖前者，
Task 7 改为把 roll 并进 `HeadLook`。

- [ ] **Step 3: 把结论写进 spec，删掉探针**

在 spec 的「分段倾斜」小节把那条 ⚠️ 技术风险改写成结论（一句话，说明实测结果与
由此选定的形态）。

```bash
rm tools/probe_modifier_stack.gd
git add docs/superpowers/specs/2026-08-30-balance-and-ledge-walk-design.md
git commit -m "docs(spec): record whether two skeleton modifiers compose"
```

---

### Task 2: 类别、名字与两个 Config

**Files:**
- Modify: `scripts/level/interest_line.gd`（`Kind` 枚举）
- Modify: `scripts/player/moves/move.gd`（两个名字常量）
- Create: `scripts/player/config/moves/balance_config.gd`
- Create: `scripts/player/config/moves/ledge_walk_config.gd`
- Modify: `scripts/player/config/move_config.gd`（两个 check_for_* 开关）
- Modify: `scripts/player/movement_config.gd`（两个字段）
- Modify: `presets/default.tres`
- Test: `tests/test_config_layout.gd`

**Interfaces:**
- Produces: `InterestLine.Kind.LEDGE_WALK`；`Move.BALANCE = &"Balance"`；
  `Move.LEDGE_WALK = &"LedgeWalk"`；`BalanceConfig`；`LedgeWalkConfig`；
  `MovementConfig.balance`；`MovementConfig.ledge_walk`；
  `MoveConfig.check_for_balance`；`MoveConfig.check_for_ledge_walk`。

- [ ] **Step 1: 先写失败的测试**

追加到 `tests/test_config_layout.gd`：

```gdscript
func test_balance_and_ledge_walk_are_on_the_aggregate() -> void:
	var config := MovementConfig.new()
	assert_not_null(config.balance, "MovementConfig must carry a BalanceConfig")
	assert_not_null(config.ledge_walk, "MovementConfig must carry a LedgeWalkConfig")
	assert_true(config.balance is BalanceConfig)
	assert_true(config.ledge_walk is LedgeWalkConfig)

func test_the_two_line_walks_declare_the_original_speed_modifiers() -> void:
	var config := MovementConfig.new()
	# [ME:CONFIRMED] TdMove_Balance 0.34, TdMove_LedgeWalk 0.10.
	assert_almost_eq(config.balance.speed_modifier, 0.34, 0.001)
	assert_almost_eq(config.ledge_walk.speed_modifier, 0.10, 0.001)

func test_the_beam_faces_along_the_line_and_the_ledge_across_it() -> void:
	var config := MovementConfig.new()
	assert_almost_eq(config.balance.body_yaw_offset_deg, 0.0, 0.001)
	assert_almost_eq(config.ledge_walk.body_yaw_offset_deg, 90.0, 0.001)
```

- [ ] **Step 2: 跑，确认失败**

Run: `bun tools/run_tests.ts config_layout`
Expected: FAIL，`Identifier "BalanceConfig" not declared`。

- [ ] **Step 3: 加枚举与名字常量**

`scripts/level/interest_line.gd`：

```gdscript
enum Kind { ZIPLINE, SWING, BALANCE, LADDER, LEDGE_WALK }
```

⚠️ 追加在**末尾**：枚举值序号写进了已存在的 `.tscn`，插在中间会让现有的线改变
类别。

`scripts/player/moves/move.gd`，接在 `LADDER` 之后：

```gdscript
const BALANCE: StringName = &"Balance"
const LEDGE_WALK: StringName = &"LedgeWalk"
```

- [ ] **Step 4: 写两个 Config**

`scripts/player/config/moves/ledge_walk_config.gd`：

```gdscript
class_name LedgeWalkConfig
extends MoveConfig

# The original's TdMove_LedgeWalk. Shuffling along a narrow ledge with your
# back to the wall.
#
# THERE IS NO BALANCE HERE, and that is the whole point of the move. The CDO
# carries none of TdMove_Balance's five pendulum fields -- no GravityInfluence,
# ControlInfluence, SpeedInfluence, TimeToCounter or CameraInfluence -- so a
# ledge cannot be fallen off. All it does is take the speed down to a tenth,
# lock the view and lock the facing. [ME:CONFIRMED] the dumped CDO; see
# docs/mirrors-edge-deep-research/appendix/A1-TdMove-CDO全量.md.
#
# It is a LEVEL PACING TOOL rather than a movement ability: the geometry is
# walkable anyway, and the interest point exists to force the player to slow
# down. SpeedModifier 0.1 is the harshest in the game.

## How far the body is turned off the line's own tangent, degrees. 90 puts the
## shoulders across the line -- back to the wall, shuffling sideways -- which is
## what makes A/D the travel keys here without a single branch in LineWalkMove.
## [ME:CONFIRMED] the first game's LedgeWalk always faces AWAY from the wall;
## only Catalyst added a facing-the-wall variant.
@export var body_yaw_offset_deg: float = 90.0

## How close the feet must be to the line's own height for a catch, metres.
## The reach volume alone is not enough -- InterestLine's radius would swallow a
## body running PAST the ledge at ground level.
@export var foot_snap_height: float = 0.35

func _init() -> void:
	# [ME:CONFIRMED] SpeedModifier 0.10 -> 720 * 0.1 = 72 uu/s = 2.59 km/h.
	speed_modifier = 0.10
	constrain_look = true
	# [ME:CONFIRMED] MinLookConstraint (-14000, -10000, -32768),
	# MaxLookConstraint (16384, 10000, 32768), UE3 angles where 65536 = 360 deg:
	# pitch -76.9..+90.0, yaw +-54.93, roll unconstrained.
	min_look_constraint = Vector3(deg_to_rad(-76.9), deg_to_rad(-54.93), -PI)
	max_look_constraint = Vector3(deg_to_rad(90.0), deg_to_rad(54.93), PI)
	# The body must not swivel to follow the view: the shoulders are square to
	# the wall and a hand is on it. [ME:CONFIRMED] bDisableFaceRotation.
	freeze_visual_yaw = true
	# [ME:CONFIRMED] MG_OneHandBusy -- no spare limbs to spin on.
	allows_turn = false
```

`scripts/player/config/moves/balance_config.gd`：

```gdscript
class_name BalanceConfig
extends MoveConfig

# The original's TdMove_Balance. Walking a pipe or a beam.
#
# The five pendulum fields below are the ones LedgeWalkConfig does NOT have,
# and they are the whole difference between the two moves.

## How far the body is turned off the line's own tangent, degrees. 0 puts the
## shoulders along the beam, which is what makes W/S the travel keys here and
## leaves A/D free to be the correction. See LedgeWalkConfig for the other case.
@export var body_yaw_offset_deg: float = 0.0

@export var foot_snap_height: float = 0.35

## Seconds for the lean to grow by a factor of e.
##
## [ME:CONFIRMED] TimeToCounter = 0.8. READ AS A DIVERGENCE TIME CONSTANT, not
## as a "window to correct in": exponential divergence has no grace period, only
## a time constant, and that is what explains why being a fraction late is
## hopelessly late.
@export var divergence_time: float = 0.8

## Correction authority of A/D against the lean.
## [ME:CONFIRMED] ControlInfluence = 1.5.
@export var correction_gain: float = 1.5

## How much the ENTRY speed magnifies the one-off starting lean.
## [ME:CONFIRMED] SpeedInfluence = 2.5. It magnifies the entry offset ONLY --
## the divergence afterwards is speed-independent, which is what reconciles
## "faster is harder" with the owner's own measurement that the wobble itself
## has nothing to do with speed.
@export var entry_speed_influence: float = 2.5

## The starting lean a body gets even at a standstill.
##
## MUST STAY NON-ZERO. An inverted pendulum sitting exactly on its apex never
## falls, and the owner measured that standing still on a beam DOES lose
## balance. This is what denies the player that perfect apex.
@export var base_wobble: float = 0.02

## Lean turned into real lateral displacement off the beam's centreline,
## metres per unit of lean.
##
## [ME:INFERRED] The CDO's GravityInfluence = 0.3. The dump gives names and
## numbers but no formulae, and read as "instability coefficient" this field
## would be a second name for the divergence rate divergence_time already sets.
## Taken instead as the sibling of CameraInfluence -- both 0.3, both the rate
## that turns lean into one of its consequences. That makes falling off a
## GEOMETRIC result (the feet leave the beam) rather than one more threshold.
## See docs/superpowers/specs/2026-08-30-balance-and-ledge-walk-design.md.
@export var gravity_influence: float = 0.3

## How far the body may drift off the centreline before the feet miss, metres.
@export var beam_half_width: float = 0.14

## Largest camera roll the lean may reach in first person, degrees.
##
## THIS IS WHAT CameraInfluence BECAME. [ME:CONFIRMED] the CDO's
## CameraInfluence = 0.3 is a rate from lean to roll, but the lean this move
## reports is already normalised against beam_half_width, so a second rate
## multiplying it would just be a smaller number to reach the same angle. One
## angle you can dial beats two coefficients whose product you have to work out.
@export var max_camera_roll_deg: float = 12.0

## Largest body lean the skeleton shows, degrees.
@export var max_body_lean_deg: float = 18.0

## Share of that lean the HIPS take. Small on purpose: everything below the
## waist hangs off this bone, so a large share swings the feet off the beam.
## The project has no leg IK, so this is what stands in for planted feet.
@export var hips_lean_share_deg: float = 4.0

## How far the FOV closes in at full lean, degrees. Subtracted from whatever
## the speed-driven FOV asks for.
@export var fov_squeeze_deg: float = 10.0

func _init() -> void:
	# [ME:CONFIRMED] SpeedModifier 0.34 -> 720 * 0.34 = 244.8 uu/s = 8.81 km/h,
	# which matches the owner's own HUD reading to two decimals. The multiplier
	# applies to the GroundSpeed CONSTANT, not to the speed carried in: arriving
	# at 25.9 km/h still drops you to 8.8.
	speed_modifier = 0.34
	# [ME:CONFIRMED] RedoMoveTime = 0.5 -- half a second before a beam may be
	# re-entered, so jumping off does not get you sucked straight back on.
	redo_move_time = 0.5
	constrain_look = true
	# [ME:CONFIRMED] MinLookConstraint (-13000, -6000, -32768) -> pitch -71.4,
	# yaw +-32.96. NARROWER THAN THE LEDGE'S OWN FAN, matching "the camera runs
	# along the beam". MaxLookConstraint's pitch of 25000 (~137 deg) is outside
	# UE3's own +-16384 pitch range and its meaning is unknown -- capped at 90
	# here. DO NOT put 137 back without evidence.
	min_look_constraint = Vector3(deg_to_rad(-71.4), deg_to_rad(-32.96), -PI)
	max_look_constraint = Vector3(deg_to_rad(90.0), deg_to_rad(32.96), PI)
	freeze_visual_yaw = true
	# [ME:CONFIRMED] MG_TwoHandsBusy.
	allows_turn = false
```

- [ ] **Step 5: 挂上聚合根与开关**

`scripts/player/movement_config.gd`，接在 `ladder` 之后：

```gdscript
@export var balance: BalanceConfig = BalanceConfig.new()
@export var ledge_walk: LedgeWalkConfig = LedgeWalkConfig.new()
```

`scripts/player/config/move_config.gd`，接在 `check_for_ladder` 之后：

```gdscript
## Whether this move may hand off to Balance when the body is standing on a
## BALANCE InterestLine. Airborne moves only -- the ground entry asks
## BalanceMove's own static gate directly, the same split check_for_ladder
## documents.
@export var check_for_balance: bool = false

## Whether this move may hand off to LedgeWalk. Same shape as check_for_balance.
@export var check_for_ledge_walk: bool = false
```

- [ ] **Step 6: 跑测试，确认通过**

Run: `bun tools/run_tests.ts config_layout`
Expected: PASS

- [ ] **Step 7: 补 preset 并验引用完整性**

在 `presets/default.tres` 里为两个新字段各补一个 `SubResource`，照 `ladder` 那条
的写法。然后：

Run: `.engine/Godot_v4.7.1-stable_win64_console.exe --headless --script res://tools/check_references.gd`
Expected: 无缺失引用报错

- [ ] **Step 8: 提交**

```bash
git add scripts/level/interest_line.gd scripts/player/moves/move.gd \
  scripts/player/config/ scripts/player/movement_config.gd \
  presets/default.tres tests/test_config_layout.gd
git commit -m "feat(config): declare the balance and ledge-walk moves"
```

---

### Task 3: `LineWalkMove` 基类 + `LedgeWalkMove`

先做简单的那个客户，基类因此一开始就被真实使用而不是凭空设计。

**Files:**
- Create: `scripts/player/moves/line_walk_move.gd`
- Create: `scripts/player/moves/ledge_walk_move.gd`
- Modify: `scripts/player/player.gd`（`_build_moves()` 注册）
- Test: `tests/test_line_walk.gd`（新建）

**Interfaces:**
- Consumes: Task 2 的 `Move.LEDGE_WALK`、`LedgeWalkConfig`、`InterestLine.Kind.LEDGE_WALK`。
- Produces: `LineWalkMove`，带
  `func kind() -> InterestLine.Kind`（子类必须覆写）、
  `func line_offset() -> float`、
  `static func foot_gate_at(line: InterestLine, body_pos: Vector3, snap_height: float) -> bool`、
  `static func project_input(move: Vector2, line_yaw: float, yaw_offset: float) -> Vector2`、
  `static func yaw_of(tangent: Vector3) -> float`、
  `func note_travel(along: float) -> void`（基类空实现，Task 8 的 `LedgeWalkMove` 覆写）、
  `func _along_and_lateral(input: MoveInput, tangent: Vector3) -> Vector2`；
  `LedgeWalkMove`。

- [ ] **Step 1: 先写失败的测试**

`tests/test_line_walk.gd`（照 `tests/test_ladder_move.gd` 的搭台方式建 Player 与
线；若那里有 helper 就复用，不要另起一套）：

```gdscript
extends ParkourTest

# The projection is the whole point of the tier: "a beam is forward/back and a
# ledge is left/right" must fall out of ONE line of code plus one angle, not out
# of two key mappings.

func test_a_beam_travels_on_w_and_ignores_a_and_d() -> void:
	var cfg := BalanceConfig.new()
	var out := LineWalkMove.project_input(
		Vector2(0.0, 1.0), 0.0, deg_to_rad(cfg.body_yaw_offset_deg))
	assert_almost_eq(out.x, 1.0, 0.001, "W must drive travel along the beam")
	out = LineWalkMove.project_input(
		Vector2(1.0, 0.0), 0.0, deg_to_rad(cfg.body_yaw_offset_deg))
	assert_almost_eq(out.x, 0.0, 0.001, "D must not walk you off the beam")
	assert_almost_eq(out.y, 1.0, 0.001, "D is the correction instead")

func test_a_ledge_travels_on_a_and_d_and_ignores_w() -> void:
	var cfg := LedgeWalkConfig.new()
	var out := LineWalkMove.project_input(
		Vector2(1.0, 0.0), 0.0, deg_to_rad(cfg.body_yaw_offset_deg))
	assert_almost_eq(out.x, 1.0, 0.001, "D must shuffle along the ledge")
	out = LineWalkMove.project_input(
		Vector2(0.0, 1.0), 0.0, deg_to_rad(cfg.body_yaw_offset_deg))
	assert_almost_eq(out.x, 0.0, 0.001, "W must not walk you off the ledge")

func test_the_foot_gate_refuses_a_body_running_past_at_ground_level() -> void:
	var line := _make_line(InterestLine.Kind.LEDGE_WALK,
		Vector3(0, 3, 0), Vector3(0, 3, 4))
	var body_on_it := Vector3(0, 3, 2)
	var body_below := Vector3(0, 0, 2)
	assert_true(LineWalkMove.foot_gate_at(line, body_on_it, 0.35))
	assert_false(LineWalkMove.foot_gate_at(line, body_below, 0.35),
		"the reach volume alone would swallow a body running past below")
```

- [ ] **Step 2: 跑，确认失败**

Run: `bun tools/run_tests.ts line_walk`
Expected: FAIL，`LineWalkMove` 未声明。

- [ ] **Step 3: 写 `LineWalkMove`**

```gdscript
class_name LineWalkMove
extends LineMove

# The half of the "along a line" family that stands ON the line, as opposed to
# the half that hangs UNDER it (zipline, swing) and the ladder's own vertical
# climb. 05 §5.6.5 draws exactly this line: a zipline hangs below and slides
# along, a bar hangs below and swings across, a beam STANDS ON TOP and walks
# along.
#
# Two subclasses: BalanceMove adds an inverted pendulum, LedgeWalkMove adds
# nothing at all. DO NOT collapse them into one move with a switch -- the ledge
# would then carry a whole pendulum pinned at zero, and this project answers
# every "can I go from X to Y" in exactly one place.

## Arc length along the line, metres.
var _offset_along: float = 0.0
## The body's yaw while on the line: the line's own heading turned by the
## config's body_yaw_offset_deg. Captured on entry and NOT re-derived per tick,
## for the reason project_input() documents.
var _walk_yaw: float = 0.0

## Which kind of line this move rides. Subclasses MUST override.
func kind() -> InterestLine.Kind:
	push_error("LineWalkMove subclass must declare its kind()")
	return InterestLine.Kind.BALANCE

## Input mapped onto the LINE rather than onto a key.
##
## Returns (along, lateral): the input direction projected on the line's own
## tangent, and on its horizontal normal. Everything about "a beam is W/S and a
## ledge is A/D" lives in body_yaw_offset -- a beam's shoulders are along the
## line so W projects fully and A/D project to nothing, a ledge's are across it
## so the same arithmetic hands travel to A/D. There is no branch anywhere.
##
## THE BASIS IS THE LINE'S, NOT THE BODY'S. Player.wish_direction() turns the
## input by the CURRENT body basis, and the body still yaws with the view inside
## the look constraint -- a glance 33 degrees off the beam would then multiply
## walking speed by cos(33). The heading captured on entry has no such drift.
static func project_input(move: Vector2, line_yaw: float, yaw_offset: float) -> Vector2:
	var body := Basis(Vector3.UP, line_yaw + yaw_offset)
	var world: Vector3 = body * Vector3(move.x, 0.0, -move.y)
	var tangent := Vector3(sin(line_yaw), 0.0, cos(line_yaw))
	var normal := Vector3(tangent.z, 0.0, -tangent.x)
	return Vector2(world.dot(tangent), world.dot(normal))

## Yaw of a line tangent, in the same convention _target_yaw is built with.
static func yaw_of(tangent: Vector3) -> float:
	var flat := Vector3(tangent.x, 0.0, tangent.z)
	if flat.length_squared() < 0.0001:
		return 0.0
	flat = flat.normalized()
	return atan2(flat.x, flat.z)

## Whether the FEET are at the line's own height -- the extra condition every
## entry gate in this tier asks on top of the reach volume.
##
## InterestLine's reach_radius is 0.6 m by default, which is wide enough to
## catch a body running PAST a beam at ground level. Balance is a state that
## takes control away and cannot be walked out of sideways, so a false catch
## costs far more than a missed one.
static func foot_gate_at(line: InterestLine, body_pos: Vector3, snap_height: float) -> bool:
	var at: Vector3 = line.sample(line.closest_offset(body_pos))["position"]
	return absf(body_pos.y - at.y) <= snap_height

func enter(_previous: StringName) -> void:
	# DECLARED, never inferred: a scripted move never calls move_and_slide(),
	# so MoveManager's grounded invariant is satisfied here and nowhere else.
	player.set_grounded(true)
	_aborted = not acquire_line(kind())
	if _aborted:
		return
	_offset_along = _line.closest_offset(player.global_position)
	var s: Dictionary = _line.sample(_offset_along)
	_walk_yaw = LineWalkMove.yaw_of(s["tangent"])
	_target_yaw = _walk_yaw + deg_to_rad(_yaw_offset())
	# The multiplier applies to the GroundSpeed constant, not to what was
	# carried in: arriving fast must not survive the step onto the line.
	player.velocity = Vector3.ZERO
	_fade = 0.0
	_entry_pos = player.global_position
	_entry_yaw = player.rotation.y
	_fan_centred = false

func physics_update(delta: float, input: MoveInput) -> StringName:
	if _aborted or not is_instance_valid(_line):
		return FALLING
	player.set_grounded(true)
	player.fall_tracker.reset(player.global_position.y)
	if input.jump_pressed:
		player.consume_roll()
		return FALLING
	if input.crouch_pressed:
		player.consume_roll()
		return FALLING
	var s: Dictionary = _line.sample(_offset_along)
	_walk_yaw = LineWalkMove.yaw_of(s["tangent"])
	var projected := LineWalkMove.project_input(
		input.move, _walk_yaw, deg_to_rad(_yaw_offset()))
	var speed: float = config.pawn.ground_speed * cfg.speed_modifier
	_offset_along += projected.x * speed * delta
	note_travel(projected.x)
	# Walking off either end is how you leave: the line ran out, so the body is
	# simply standing on whatever is there.
	if _offset_along <= 0.0 or _offset_along >= _line.length():
		_offset_along = clampf(_offset_along, 0.0, _line.length())
		return WALKING
	var next := lateral_update(delta, projected.y)
	if next != KEEP:
		return next
	var stand: Vector3 = _line.sample(_offset_along)["position"] \
		+ Vector3.UP * (player.standing_height() * 0.5) \
		+ lateral_offset() * _normal_at(_walk_yaw)
	_fade += delta
	if _fade < fade_in_time():
		var t: float = _fade / fade_in_time()
		player.global_position = _entry_pos.lerp(stand, t)
		_turn_body_to(lerp_angle(_entry_yaw, _target_yaw, t))
	else:
		slide_to(stand)
		if not _fan_centred:
			_centre_fan()
	return KEEP

func exit() -> void:
	note_left(cfg.redo_move_time, true)

## Arc length along the line, metres. Read by the HUD and by tests.
func line_offset() -> float:
	return _offset_along

## Hook for a subclass that has lateral state of its own (BalanceMove's
## pendulum). Returns a move name to leave, or KEEP. The base tier has none.
func lateral_update(_delta: float, _lateral_input: float) -> StringName:
	return KEEP

## How far off the line's centreline the body currently stands, metres.
func lateral_offset() -> float:
	return 0.0

## Hook for a subclass that needs to know which way along the line the last tick
## travelled. LedgeWalkMove picks its sidestep clip off this; a beam does not
## care, since Walk is the clip either way.
func note_travel(_along: float) -> void:
	pass

func _yaw_offset() -> float:
	return cfg.get("body_yaw_offset_deg")

func fade_in_time() -> float:
	return 0.15

func _normal_at(line_yaw: float) -> Vector3:
	var tangent := Vector3(sin(line_yaw), 0.0, cos(line_yaw))
	return Vector3(tangent.z, 0.0, -tangent.x)
```

- [ ] **Step 4: 写 `LedgeWalkMove`**

```gdscript
class_name LedgeWalkMove
extends LineWalkMove

# The original's TdMove_LedgeWalk: shuffling a narrow ledge with your back to
# the wall at a tenth of walking speed.
#
# IT IS THIS SHORT ON PURPOSE. The CDO carries no balance fields at all, so
# there is nothing to fall off and nothing to correct -- every difference from
# BalanceMove is declared in LedgeWalkConfig rather than written here. See that
# file's own header.

func kind() -> InterestLine.Kind:
	return InterestLine.Kind.LEDGE_WALK

## THE ONE ENTRY GATE, static so every entry site asks the same question before
## transitioning -- no enter-then-abort flutter. Mirrors LadderMove.catch_gate().
static func catch_gate(player: Player, line: InterestLine, snap_height: float) -> bool:
	if not player.line_ready(line):
		return false
	return LineWalkMove.foot_gate_at(line, player.global_position, snap_height)
```

- [ ] **Step 5: 注册**

`scripts/player/player.gd` 的 `_build_moves()`，接在 LADDER 那行之后：

```gdscript
[Move.LEDGE_WALK, LedgeWalkMove.new(), config.ledge_walk],
```

- [ ] **Step 6: 跑测试**

Run: `bun tools/run_tests.ts line_walk config_layout`
Expected: PASS

- [ ] **Step 7: 跑既有家族测试，确认没碰坏**

Run: `bun tools/run_tests.ts zipline swing ladder`
Expected: 与改动前逐条同绿

- [ ] **Step 8: 提交**

```bash
git add scripts/player/moves/line_walk_move.gd scripts/player/moves/ledge_walk_move.gd \
  scripts/player/player.gd tests/test_line_walk.gd
git commit -m "feat(moves): add the standing-on-a-line tier and the ledge walk"
```

---

### Task 4: 进入门接线

**Files:**
- Modify: `scripts/player/moves/walking_move.gd`
- Modify: `scripts/player/moves/airborne_move.gd`
- Test: `tests/test_line_walk.gd`

**Interfaces:**
- Consumes: Task 3 的 `LedgeWalkMove.catch_gate()`；Task 2 的
  `MoveConfig.check_for_ledge_walk`。

- [ ] **Step 1: 先写失败的测试**

```gdscript
func test_walking_onto_a_ledge_line_enters_the_move() -> void:
	var player := _spawn_player()
	var line := _make_line(InterestLine.Kind.LEDGE_WALK,
		Vector3(0, 1, 0), Vector3(0, 1, 4))
	player.global_position = Vector3(0, 1, 2)
	await _tick(player)
	assert_eq(player.move_manager.current_name, Move.LEDGE_WALK)

func test_running_past_below_a_ledge_line_does_not_enter() -> void:
	var player := _spawn_player()
	var line := _make_line(InterestLine.Kind.LEDGE_WALK,
		Vector3(0, 1, 0), Vector3(0, 1, 4))
	player.global_position = Vector3(0, 0, 2)
	await _tick(player)
	assert_eq(player.move_manager.current_name, Move.WALKING)
```

- [ ] **Step 2: 跑，确认失败**

Run: `bun tools/run_tests.ts line_walk`

- [ ] **Step 3: 接 `WalkingMove`**

紧跟现有 LADDER 那段之后（顺序即优先级，兴趣点先于普通地面）：

```gdscript
	if player.grounded and player.move_manager.can_enter(LEDGE_WALK):
		var ledge: InterestLine = player.nearest_interest_line(InterestLine.Kind.LEDGE_WALK)
		if ledge != null and LedgeWalkMove.catch_gate(
				player, ledge, config.ledge_walk.foot_snap_height):
			return LEDGE_WALK
```

- [ ] **Step 4: 接 `AirborneMove`**

紧跟现有 `check_for_ladder` 那段之后：

```gdscript
	if c.check_for_ledge_walk and player.move_manager.can_enter(LEDGE_WALK):
		var ledge: InterestLine = player.nearest_interest_line(InterestLine.Kind.LEDGE_WALK)
		if ledge != null and LedgeWalkMove.catch_gate(
				player, ledge, config.ledge_walk.foot_snap_height):
			return LEDGE_WALK
```

并在 `FallingConfig` / `JumpConfig` / `CoilConfig` 里把 `check_for_ledge_walk`
置 true（跳上檐、落到檐上都要能接住），`FallUncontrolledConfig` 保持 false（失控
下坠没有接住的余地，与 zipline 同规矩）。

- [ ] **Step 5: 跑测试**

Run: `bun tools/run_tests.ts line_walk airborne`
Expected: PASS

- [ ] **Step 6: 提交**

```bash
git add scripts/player/moves/walking_move.gd scripts/player/moves/airborne_move.gd \
  scripts/player/config/moves/ tests/test_line_walk.gd
git commit -m "feat(moves): let walking and airborne bodies catch a ledge line"
```

---

### Task 5: `BalanceMove` 与倒立摆

**Files:**
- Create: `scripts/player/moves/balance_move.gd`
- Modify: `scripts/player/player.gd`（注册）
- Modify: `scripts/player/moves/walking_move.gd`、`airborne_move.gd`（进入门）
- Test: `tests/test_balance.gd`（新建）

**Interfaces:**
- Consumes: Task 3 的 `LineWalkMove.lateral_update()` / `lateral_offset()` 钩子。
- Produces: `BalanceMove`，带 `func lean() -> float`、`func lean_rate() -> float`、
  `static func catch_gate(player, line, snap_height) -> bool`。

- [ ] **Step 1: 先写失败的测试**

```gdscript
extends ParkourTest

# STRUCTURAL PROPERTIES ONLY. The dials (base_wobble, beam_half_width, the lean
# and FOV limits) are judged by eye and carry no assertions -- see
# .claude/skills/tuning-dials-not-rules.

func test_lean_diverges_when_nobody_corrects() -> void:
	var move := BalanceMove.new()
	move.cfg = BalanceConfig.new()
	move.seed_lean(0.01, 0.0)
	var first := absf(move.lean())
	for i in 10:
		move.integrate_lean(1.0 / 60.0, 0.0)
	assert_gt(absf(move.lean()), first,
		"an inverted pendulum with no correction must run away from its apex")

func test_the_apex_is_stationary() -> void:
	var move := BalanceMove.new()
	move.cfg = BalanceConfig.new()
	move.seed_lean(0.0, 0.0)
	for i in 60:
		move.integrate_lean(1.0 / 60.0, 0.0)
	assert_almost_eq(move.lean(), 0.0, 0.0001,
		"zero lean AND zero rate is the unstable equilibrium: it must sit still")

func test_a_standstill_entry_still_leans() -> void:
	var cfg := BalanceConfig.new()
	var lean := BalanceMove.entry_lean(cfg, 0.0, 7.2, 1)
	assert_gt(absf(lean), 0.0,
		"the owner measured that standing still on a beam still loses balance")

func test_entry_lean_grows_with_entry_speed() -> void:
	var cfg := BalanceConfig.new()
	var slow := absf(BalanceMove.entry_lean(cfg, 0.0, 7.2, 1))
	var fast := absf(BalanceMove.entry_lean(cfg, 7.2, 7.2, 1))
	assert_gt(fast, slow, "SpeedInfluence magnifies the ENTRY offset")

func test_correction_opposes_the_lean() -> void:
	var move := BalanceMove.new()
	move.cfg = BalanceConfig.new()
	move.seed_lean(0.05, 0.0)
	var free := move.duplicate_lean_after(0.2, 0.0)
	var corrected := move.duplicate_lean_after(0.2, -1.0)
	assert_lt(corrected, free, "A/D must fight the lean, not steer")

func test_the_ledge_walk_has_no_pendulum() -> void:
	var move := LedgeWalkMove.new()
	assert_false(move.has_method("lean"),
		"LedgeWalk carries none of TdMove_Balance's five pendulum fields")
```

- [ ] **Step 2: 跑，确认失败**

Run: `bun tools/run_tests.ts balance`

- [ ] **Step 3: 写 `BalanceMove`**

```gdscript
class_name BalanceMove
extends LineWalkMove

# The original's TdMove_Balance: walking a pipe at a third of walking speed
# while an inverted pendulum tries to tip you off it.
#
# THE MODEL IS A BALL ON A DOME, and the owner measured it against the original
# rather than reading it off field names -- twice the field names gave the wrong
# answer. Entering, the game drops the ball a little off the apex, to the left
# or the right at random, further the faster you came in. Everything after that
# is the ball rolling off a dome it was never stable on. Get the offset AND its
# rate to zero early and it sits at the apex for the rest of the beam, which is
# why an expert barely touches A/D after the first moment.
#
# See docs/mirrors-edge-deep-research/05-动作库总览.md §5.6.

## Lean off the beam's centreline, in the pendulum's own units. Positive is
## toward the line's right-hand normal.
var _lean: float = 0.0
var _lean_rate: float = 0.0

func kind() -> InterestLine.Kind:
	return InterestLine.Kind.BALANCE

static func catch_gate(player: Player, line: InterestLine, snap_height: float) -> bool:
	if not player.line_ready(line):
		return false
	return LineWalkMove.foot_gate_at(line, player.global_position, snap_height)

## The ONE random draw of the whole move.
##
## DO NOT ADD A SECOND. Shoving the body every few seconds destroys the exact
## thing this move rewards: the stable stretch an expert earns by zeroing the
## offset early. The owner's measurement is explicit that the wobble is NOT a
## series of random pushes.
static func entry_lean(cfg: BalanceConfig, entry_speed: float,
		ground_speed: float, sign_pick: int) -> float:
	var reference: float = maxf(ground_speed, 0.0001)
	var magnitude: float = cfg.base_wobble \
		+ cfg.entry_speed_influence * cfg.base_wobble * (entry_speed / reference)
	return magnitude * float(sign_pick)

func enter(previous: StringName) -> void:
	var entry_speed: float = Vector3(player.velocity.x, 0.0, player.velocity.z).length()
	super.enter(previous)
	if _aborted:
		return
	var pick: int = 1 if randf() < 0.5 else -1
	seed_lean(BalanceMove.entry_lean(cfg, entry_speed, config.pawn.ground_speed, pick), 0.0)

## Test seam and entry seam both: sets the pendulum's two numbers outright.
func seed_lean(lean: float, rate: float) -> void:
	_lean = lean
	_lean_rate = rate

## One tick of the pendulum.
##
## NO DAMPING TERM, NOT ONE. Nothing in here may pull _lean_rate back toward
## zero on the player's behalf: "the expert zeroes the offset AND its rate" only
## means anything while no one else is doing it for them. A damping term is the
## system steadying the player, and it takes the reward with it.
func integrate_lean(delta: float, lateral_input: float) -> void:
	var rate: float = 1.0 / maxf(cfg.divergence_time, 0.0001)
	var accel: float = _lean * rate * rate - cfg.correction_gain * lateral_input
	_lean_rate += accel * delta
	_lean += _lean_rate * delta

func lateral_update(delta: float, lateral_input: float) -> StringName:
	integrate_lean(delta, lateral_input)
	# Falling off is GEOMETRIC: the lean is a real displacement off the
	# centreline, and past the beam's half width the feet have nothing under
	# them. Not a separate threshold that happens to be checked here.
	if absf(lateral_offset()) > cfg.beam_half_width:
		player.consume_roll()
		return FALLING
	return KEEP

func lateral_offset() -> float:
	return _lean * cfg.gravity_influence

## Read by the camera, the skeleton lean, the FOV squeeze and the debug HUD --
## one source, several presentations.
func lean() -> float:
	return _lean

func lean_rate() -> float:
	return _lean_rate

## Normalised 0..1 severity, which is what every presentation channel actually
## wants. 1 means the feet are about to miss.
func lean_severity() -> float:
	var edge: float = maxf(cfg.beam_half_width, 0.0001)
	return clampf(absf(lateral_offset()) / edge, 0.0, 1.0)

## Signed version of the above, for channels that need a direction (camera
## roll, body lean).
func signed_severity() -> float:
	return lean_severity() * signf(_lean)

## Test helper: how far the lean gets in `seconds` under a held input, without
## disturbing this instance's own state.
func duplicate_lean_after(seconds: float, lateral_input: float) -> float:
	var probe := BalanceMove.new()
	probe.cfg = cfg
	probe.seed_lean(_lean, _lean_rate)
	var step: float = 1.0 / 60.0
	var t: float = 0.0
	while t < seconds:
		probe.integrate_lean(step, lateral_input)
		t += step
	return absf(probe.lean())
```

- [ ] **Step 4: 注册与接入进入门**

`player.gd` 的 `_build_moves()`：

```gdscript
[Move.BALANCE, BalanceMove.new(), config.balance],
```

`walking_move.gd` 与 `airborne_move.gd` 各加一段，与 Task 4 的檐走那段同形，
换成 `BALANCE` / `InterestLine.Kind.BALANCE` / `BalanceMove.catch_gate` /
`config.balance.foot_snap_height` / `check_for_balance`；同样在 Falling / Jump /
Coil 的 config 里把 `check_for_balance` 置 true。

- [ ] **Step 5: 跑测试**

Run: `bun tools/run_tests.ts balance line_walk`
Expected: PASS

- [ ] **Step 6: 提交**

```bash
git add scripts/player/moves/balance_move.gd scripts/player/player.gd \
  scripts/player/moves/walking_move.gd scripts/player/moves/airborne_move.gd \
  scripts/player/config/moves/ tests/test_balance.gd
git commit -m "feat(moves): walk a beam on an inverted pendulum"
```

---

### Task 6: 镜头 roll 与 FOV 收缩

**Files:**
- Modify: `scripts/camera/camera_rig.gd`
- Modify: `scripts/player/config/camera_config.gd`
- Modify: `scripts/player/moves/balance_move.gd`（每帧喂值）
- Test: `tests/test_camera_constraints.gd`

**Interfaces:**
- Consumes: Task 5 的 `BalanceMove.signed_severity()` / `lean_severity()`。
- Produces: `CameraRig.set_balance_lean(roll_radians: float, squeeze_deg: float)`；
  `CameraConfig.third_person_balance_roll_scale`。

⚠️ 角度由 **move 侧**算好（`signed_severity() * max_camera_roll_deg`），rig 只负责
第三人称缩放与合成。rig 不读 `BalanceConfig`——它一贯只接收**值**，不接场景引用，
也不该知道哪个 move 在驱动它。

- [ ] **Step 1: 先写失败的测试**

```gdscript
func test_third_person_softens_the_balance_roll() -> void:
	var rig := _make_rig()
	rig.set_balance_lean(1.0, 0.0)
	rig.set_third_person(false)
	await _tick(rig)
	var first_person_roll := absf(rig.camera.rotation.z)
	rig.set_third_person(true)
	await _tick(rig)
	var third_person_roll := absf(rig.camera.rotation.z)
	assert_lt(third_person_roll, first_person_roll,
		"an outside view tilting with the body is nauseating, not informative")

func test_the_squeeze_closes_the_fov_rather_than_opening_it() -> void:
	var rig := _make_rig()
	rig.set_balance_lean(0.0, 0.0)
	await _tick(rig)
	var calm := rig.camera.fov
	rig.set_balance_lean(1.0, 10.0)
	await _tick(rig)
	assert_lt(rig.camera.fov, calm,
		"the speed-driven FOV opens with speed; this must close against it")
```

- [ ] **Step 2: 跑，确认失败**

Run: `bun tools/run_tests.ts camera_constraints`

- [ ] **Step 3: `CameraConfig` 加字段**

```gdscript
## How much of the balance roll survives in third person.
##
## SMALL ON PURPOSE. In first person the roll IS the feedback -- the horizon
## tipping is what tells you which way you are going over. Seen from outside,
## the same roll tips the whole world around a character who is visibly leaning
## anyway, which reads as nausea rather than as information. The body's own lean
## carries the signal there; see BalanceConfig.max_body_lean_deg.
@export var third_person_balance_roll_scale: float = 0.15
```

- [ ] **Step 4: `CameraRig` 加通道**

```gdscript
## Fed every tick by BalanceMove: the roll the lost balance asks for, in
## RADIANS, already scaled by that move's own limit; and how many degrees of FOV
## the squeeze wants. Values only, like every other channel here -- this rig
## does not know what a beam is.
##
## The squeeze is SUBTRACTED after the speed-driven FOV has been computed, not
## folded into it: that channel opens the view as you go faster, and the beam is
## slow, so leaving this to the speed curve would widen the view at exactly the
## moment it should be closing in.
func set_balance_lean(roll_radians: float, squeeze_deg: float) -> void:
	_balance_roll = roll_radians
	_balance_squeeze = squeeze_deg
```

在 roll 的合成处叠上（与 `_vault_roll` 同一处）：

```gdscript
	var balance_roll: float = _balance_roll
	if _third_person:
		balance_roll *= _config.camera.third_person_balance_roll_scale
```

在 FOV 那几行（`camera_rig.gd:778-781`）之后：

```gdscript
	camera.fov -= _balance_squeeze
```

- [ ] **Step 5: `BalanceMove` 每帧喂值**

在 `lateral_update()` 末尾（返回 KEEP 之前）：

```gdscript
	if player.camera_rig != null:
		player.camera_rig.set_balance_lean(
			deg_to_rad(signed_severity() * cfg.max_camera_roll_deg),
			lean_severity() * cfg.fov_squeeze_deg)
```

并在 `exit()` 里归零（离开梁后镜头必须立刻恢复）：

```gdscript
func exit() -> void:
	super.exit()
	if player.camera_rig != null:
		player.camera_rig.set_balance_lean(0.0, 0.0)
```

- [ ] **Step 6: 跑测试**

Run: `bun tools/run_tests.ts camera balance`
Expected: PASS

- [ ] **Step 7: 提交**

```bash
git add scripts/camera/camera_rig.gd scripts/player/config/camera_config.gd \
  scripts/player/moves/balance_move.gd tests/test_camera_constraints.gd
git commit -m "feat(camera): roll and close the view as balance is lost"
```

---

### Task 7: 分段身体倾斜

形态由 Task 1 的结论决定：能叠加就写独立 modifier，不能就并进 `HeadLook`。以下按
能叠加写；不能叠加时把同样的链分配逻辑搬进 `HeadLook`，字段与方法名保持不变。

**Files:**
- Create: `scripts/player/balance_lean.gd`（或并入 `scripts/player/head_look.gd`）
- Modify: `scripts/player/player.gd`（挂载与每帧喂值）
- Test: `tests/test_balance_lean.gd`（新建）

**Interfaces:**
- Consumes: Task 5 的 `BalanceMove.signed_severity()`；Task 2 的
  `BalanceConfig.max_body_lean_deg` / `hips_lean_share_deg`。
- Produces: `BalanceLean.request_lean(signed: float, max_deg: float, hips_deg: float)`。

- [ ] **Step 1: 先写失败的测试**

```gdscript
func test_the_hips_take_far_less_of_the_lean_than_the_torso() -> void:
	var rig := _make_skeleton_with_humanoid_bones()
	var lean := BalanceLean.new()
	rig.add_child(lean)
	lean.request_lean(1.0, deg_to_rad(18.0), deg_to_rad(4.0))
	await _tick(rig)
	var hips := absf(_roll_of(rig, &"Hips"))
	var chest := absf(_roll_of(rig, &"UpperChest"))
	assert_lt(hips, chest,
		"the feet stay on the beam; the torso is what shows the wobble")

func test_no_lean_leaves_the_skeleton_alone() -> void:
	var rig := _make_skeleton_with_humanoid_bones()
	var lean := BalanceLean.new()
	rig.add_child(lean)
	lean.request_lean(0.0, deg_to_rad(18.0), deg_to_rad(4.0))
	await _tick(rig)
	assert_almost_eq(_roll_of(rig, &"Spine"), 0.0, 0.0001)

func test_a_missing_bone_is_skipped_rather_than_fatal() -> void:
	var rig := _make_skeleton_missing(&"UpperChest")
	var lean := BalanceLean.new()
	rig.add_child(lean)
	lean.request_lean(1.0, deg_to_rad(18.0), deg_to_rad(4.0))
	await _tick(rig)
	assert_true(true, "body_scene is optional; no bone may be assumed to exist")
```

- [ ] **Step 2: 跑，确认失败**

Run: `bun tools/run_tests.ts balance_lean`

- [ ] **Step 3: 写 `BalanceLean`**

```gdscript
class_name BalanceLean
extends SkeletonModifier3D

# Shows a balance wobble as a body leaning, not as a whole model tipping over.
#
# THE FEET MUST STAY ON THE BEAM. Rolling the model's root swings the feet off
# the pipe it is standing on, which is the one thing the pose has to sell. This
# project has no leg IK, so the stand-in is where the lean ORIGINATES: the hips
# take a token share and the spine chain takes the rest, so the displacement
# that reaches the feet is only what the hips' few degrees carry down.
#
# Built on HeadLook's arithmetic, one axis over. Everything that file says about
# set_bone_global_pose applies here unchanged: a humanoid bone's local axes are
# whatever its rest pose made them, so a local rotation bends the body somewhere
# unrelated -- which this project cannot see, only measure.
#
# DO NOT reach for the packs' lean clips (Jog_Fwd_LeanL/R) instead. They are
# authored for leaning into a full-speed run, and the owner ruled them out here.
# On a beam the body is simply walking at 8.81 km/h; Walk is the clip.

## Takes the share named by the caller. Same chain, same reasoning as
## HeadLook.SPINE_CHAIN: Spine's origin sits just above the hips, which is where
## a person bends from. Starting at Chest reads as a shrug.
const SPINE_CHAIN: Array[StringName] = [&"Spine", &"Chest", &"UpperChest"]
## Everything below the waist hangs off this one bone.
const HIPS_CHAIN: Array[StringName] = [&"Hips"]

var _lean: float = 0.0
var _max_lean: float = 0.0
var _hips_lean: float = 0.0

## Signed -1..1, plus the two limits in radians. Fed every tick by Player while
## BalanceMove is active, and zeroed the moment it is not.
func request_lean(signed: float, max_lean: float, hips_lean: float) -> void:
	_lean = clampf(signed, -1.0, 1.0)
	_max_lean = max_lean
	_hips_lean = hips_lean

# THE 4.7 SIGNATURE IS _with_delta. head_look.gd uses the same one; a plain
# _process_modification() is never called and the lean silently does nothing.
func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	if is_zero_approx(_lean):
		return
	var total: float = _lean * _max_lean
	var hips: float = _lean * _hips_lean
	_roll_chain(skeleton, HIPS_CHAIN, hips)
	# Parent to child, poses accumulate: the spine chain must carry only what
	# the hips did not, or the torso overshoots by exactly the hips' share.
	_roll_chain(skeleton, SPINE_CHAIN, total - hips)

## Splits `radians` evenly across whichever of `chain`'s bones this skeleton
## actually has. A missing bone is skipped, never assumed: body_scene is
## optional and the whole suite runs with nothing attached.
func _roll_chain(skeleton: Skeleton3D, chain: Array[StringName], radians: float) -> void:
	var present: Array[int] = []
	for name in chain:
		var idx: int = skeleton.find_bone(name)
		if idx >= 0:
			present.append(idx)
	if present.is_empty():
		return
	var each: float = radians / float(present.size())
	var axis: Vector3 = _lean_axis(skeleton)
	for idx in present:
		var pose: Transform3D = skeleton.get_bone_global_pose(idx)
		# READ-MODIFY-WRITE, never an absolute pose. HeadLook runs in the same
		# modifier chain and multiplies onto whatever it reads; writing an
		# absolute pose here would erase its work for the frame. This is what
		# makes the two compose -- see the spec's own section on it.
		var turn := Basis(axis, each)
		skeleton.set_bone_global_pose(idx, Transform3D(turn * pose.basis, pose.origin))

## The axis a sideways lean turns about: the character's own FORWARD.
##
## DO NOT use Vector3.FORWARD, and DO NOT take it from a bone's own -Z.
## head_look.gd's _pitch_axis() carries the warning this copies: a VRM faces +Z
## by specification, so a bone's -Z points out of its back, and a check written
## against that same -Z agrees with itself. The mistake therefore survives every
## headless verification and only shows up in play. Derive it from the SHOULDERS,
## which do not care which way the format decided forward is.
func _lean_axis(skeleton: Skeleton3D) -> Vector3:
	var left: int = skeleton.find_bone(&"LeftUpperArm")
	var right: int = skeleton.find_bone(&"RightUpperArm")
	if left < 0 or right < 0:
		return Vector3.FORWARD
	var across: Vector3 = skeleton.get_bone_global_pose(left).origin 		- skeleton.get_bone_global_pose(right).origin
	across.y = 0.0
	if across.length_squared() < 0.000001:
		return Vector3.FORWARD
	return Vector3.UP.cross(across.normalized()).normalized()
```

⚠️ `_lean_axis()` 的**符号**（左肩减右肩，还是反过来）决定倾斜朝哪边。照
`head_look.gd:_pitch_axis()` 的既有取法核对一遍，并让 Step 1 的测试钉住方向：
`request_lean(+1, ...)` 必须把上半身倒向线的**右侧**，与 `BalanceMove` 里
「正 = 线的右手法线」的约定一致。

- [ ] **Step 4: 挂载并喂值**

`player.gd` 里 `HeadLook` 挂载处旁边加 `BalanceLean`，并在每帧驱动处：

```gdscript
	if _balance_lean != null:
		var move = move_manager.move_for(Move.BALANCE)
		var active: bool = move_manager.current_name == Move.BALANCE
		_balance_lean.request_lean(
			move.signed_severity() if active else 0.0,
			deg_to_rad(config.balance.max_body_lean_deg),
			deg_to_rad(config.balance.hips_lean_share_deg))
```

- [ ] **Step 5: 跑测试**

Run: `bun tools/run_tests.ts balance_lean balance`
Expected: PASS

- [ ] **Step 6: 无头截图确认姿势**

按 `.claude/skills/verifying-visuals-headlessly` 的做法，用 `tools/capture.gd`
在最大失衡处截一张第三人称图，确认脚仍在梁上、上半身承担倾斜。

Run: `.engine/Godot_v4.7.1-stable_win64_console.exe --path . --resolution 960x540 --quit-after 300 --script res://tools/capture.gd -- res://scenes/debug_levels/balance_course.tscn /tmp/lean.png 200`

（本步依赖 Task 9 的关卡；若先做到这里，可临时用 `animation_lab.tscn`。）

- [ ] **Step 7: 提交**

```bash
git add scripts/player/balance_lean.gd scripts/player/player.gd tests/test_balance_lean.gd
git commit -m "feat(animation): lean the torso, keep the feet on the beam"
```

---

### Task 8: 动画路由

**Files:**
- Modify: `scripts/player/character_animator.gd`
- Test: `tests/test_animation_routing.gd`

**Interfaces:**
- Consumes: Task 3 的 `LineWalkMove.project_input()` 结果方向（檐走取左右）。
- Produces: `LedgeWalkMove.shuffle_direction() -> int`（-1 左 / 0 静止 / +1 右）。

- [ ] **Step 1: 先写失败的测试**

```gdscript
func test_the_beam_walks_rather_than_leans() -> void:
	var animator := _make_animator_with_clips([&"Walk", &"Idle"])
	assert_eq(animator.clip_for(Move.BALANCE), &"Walk",
		"the body is simply walking at 8.81 km/h; the wobble is camera and bones")

func test_the_ledge_shuffles_sideways() -> void:
	var animator := _make_animator_with_clips([&"Walk_L", &"Walk_R", &"Walk", &"Idle"])
	_set_shuffle(animator, -1)
	assert_eq(animator.clip_for(Move.LEDGE_WALK), &"Walk_L")
	_set_shuffle(animator, 1)
	assert_eq(animator.clip_for(Move.LEDGE_WALK), &"Walk_R")

func test_both_fall_back_when_the_pack_is_absent() -> void:
	var animator := _make_animator_with_clips([&"idle"])
	assert_eq(animator.clip_for(Move.BALANCE), &"idle")
	assert_eq(animator.clip_for(Move.LEDGE_WALK), &"idle")
```

- [ ] **Step 2: 跑，确认失败**

Run: `bun tools/run_tests.ts animation_routing`

- [ ] **Step 3: `LedgeWalkMove` 暴露方向**

```gdscript
## -1 (toward the line's start), 0 (still), +1 (toward its end) -- what the last
## tick's input actually asked for. CharacterAnimator picks Walk_L/Walk_R off it.
var _shuffle_dir: int = 0

func shuffle_direction() -> int:
	return _shuffle_dir
```

在 `physics_update()` 的投影之后记录（需在 `LineWalkMove` 里提供一个
`func note_travel(along: float) -> void` 钩子，基类空实现，`LedgeWalkMove` 覆写为
`_shuffle_dir = int(signf(along)) if absf(along) > 0.1 else 0`）。

- [ ] **Step 4: `_route()` 各加一个 case**

⚠️ 必须是两个**独立**的 `Move.X:` case，`test_every_move_has_its_own_case` 找的是
字面量，合并会让后一个名字失踪。

```gdscript
		Move.BALANCE:
			# The wobble is carried entirely by the camera roll and the skeleton
			# lean (BalanceLean) -- the body itself is just walking slowly, so
			# Walk is the honest clip. The owner ruled out the packs' lean
			# variants (Jog_Fwd_LeanL/R): those are authored for leaning into a
			# full-speed run.
			return _first_available([&"Walk", &"walk", &"Idle", &"idle"])
		Move.LEDGE_WALK:
			# Direction-aware, off the Walk family's own _L/_R suffixes (see
			# DIRECTION_SETS). UAL2's Walk_L_Loop / Walk_R_Loop are a walking
			# cadence sidestep, which is exactly what a ledge shuffle is.
			var ledge = player.move_manager.move_for(Move.LEDGE_WALK)
			var dir: int = ledge.shuffle_direction() if ledge != null else 0
			if dir < 0:
				return _first_available([&"Walk_L", &"Walk_Left", &"Walk", &"idle"])
			if dir > 0:
				return _first_available([&"Walk_R", &"Walk_Right", &"Walk", &"idle"])
			return _first_available([&"Idle", &"Walk", &"idle"])
```

- [ ] **Step 5: 跑测试**

Run: `bun tools/run_tests.ts animation`
Expected: PASS

- [ ] **Step 6: 提交**

```bash
git add scripts/player/character_animator.gd scripts/player/moves/ tests/test_animation_routing.gd
git commit -m "feat(animation): route the beam to Walk and the ledge to the sidestep"
```

---

### Task 9: 调试关卡、HUD 读数与调参面板

**Files:**
- Create: `scenes/debug_levels/balance_course.tscn`（继承 `templates/base_level.tscn`）
- Modify: `scripts/debug/debug_hud.gd`
- Modify: `scripts/debug/tuning_panel.gd`

- [ ] **Step 1: 建关卡**

从 `templates/base_level.tscn` **继承**（不要复制），照
`docs/level-templates.md` 的规矩：几何一律加在子场景里，不动 `Sun` /
`WorldEnvironment` / `Player` / `DebugHud` / `TuningPanel`，`SpawnPoint` 可移。

放三样东西：

1. 一根架空的独木桥：两端各有一个可站的台子，中间一根细梁（跨度足够走出
   `divergence_time` 的好几个倍数），下方留空好摔。梁上盖一条
   `InterestLine`，`kind = BALANCE`，曲线沿梁的中轴。
2. 一段贴墙窄檐：一面墙，墙上一条窄台。盖一条 `InterestLine`，
   `kind = LEDGE_WALK`，**节点 -Z 指向墙**。
3. 一条把两者串起来的路线，好一趟跑完。

⚠️ 手写 `.tscn` 之前读 `.claude/skills/authoring-godot-scene-files`。

- [ ] **Step 2: HUD 打出摆的两个数**

```gdscript
	if player.move_manager.current_name == Move.BALANCE:
		var move = player.move_manager.move_for(Move.BALANCE)
		lines.append("lean %.3f  rate %+.3f  severity %.2f" % [
			move.lean(), move.lean_rate(), move.lean_severity()])
```

⚠️ 倒立摆是看不见的内部状态，没有这行读数调参基本是瞎拧。

- [ ] **Step 3: 调参面板接两组旋钮**

照 `tuning_panel.gd` 现有分组的写法，把 `BalanceConfig` 与 `LedgeWalkConfig`
各加一组。⚠️ 读 `.claude/skills/godot-ui-layout-traps` 与
`.claude/skills/naming-config-fields` 再动手。

- [ ] **Step 4: 跑全套**

Run: `bun tools/run_tests.ts`
Expected: 全绿

Run: `.engine/Godot_v4.7.1-stable_win64_console.exe --headless --script res://tools/check_references.gd`
Expected: 无缺失引用

- [ ] **Step 5: 提交**

```bash
git add scenes/debug_levels/balance_course.tscn scripts/debug/
git commit -m "feat(debug): a beam-and-ledge course with the pendulum on the HUD"
```

---

### Task 10: 回填研究文档

spec 推翻了 05 的一处字面解释，代码落地后要让文档与之一致——否则下一个读到 05 的
人会照「不稳定系数」再实现一遍。

**Files:**
- Modify: `docs/mirrors-edge-deep-research/05-动作库总览.md`
- Modify: `docs/mirrors-edge-deep-research/11-状态机全图.md`

- [ ] **Step 1: 改 05 §5.6 的 `GravityInfluence` 解释**

把「不稳定系数——偏移把自己推得更远的强度」改成本设计裁定的读法（θ → 横向位移的
转换率，与 `CameraInfluence` 并列），标 🔶 推导，并指向 spec。同时补一句：与
`TimeToCounter` 的「发散特征时间」并存会重复描述同一件事，这是改读的原因。

- [ ] **Step 2: 更新 11 号文档的状态清单**

`PlayerBalanceWalk` 与 `PlayerLedgeWalking` 两行从「待办」改成已实现，指向
`scripts/player/moves/balance_move.gd` / `ledge_walk_move.gd` 与 spec。

- [ ] **Step 3: 提交**

```bash
git add docs/mirrors-edge-deep-research/
git commit -m "docs(research): re-read GravityInfluence as a consequence rate"
```

---

## 完成判据

- `bun tools/run_tests.ts` 全绿。
- `check_references.gd` 无报错。
- `balance_course.tscn` 里：走得上梁、走得完、摔得下去；檐走进得去出得来；
  两者能连起来跑一趟。
- 第一人称与第三人称都看过一遍（CLAUDE.md：镜头改动两个视角都要确认）。
- 倒立摆里没有阻尼项，入场之外没有第二个随机数，檐走里没有平衡状态。
