# 空中状态链 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 按原作 CDO 1:1 拆出 `Jump` / `FallingUncontrolled` / `Landing` 三个真实状态，并加一层屏幕效果与一段死亡演出，使"哪些流转不存在"由状态归属保证而非散落的 if。

**Architecture:** 抽出 `AirborneMove` 基类承载三个空中状态的共享物理（重力、空中加速、落地判定），子类只声明"本状态允许哪些检查"与"落地后去哪"。屏幕效果做成 `CameraRig` 下的单层 shader，只暴露三个浮点数，不含时间逻辑。死亡演出归 `Arena`，不是 Move。

**Tech Stack:** Godot 4.7.1 / GDScript，headless 测试通过 `tools\run_tests.ps1`

**Spec:** `docs/superpowers/specs/2026-08-19-airborne-state-machine-design.md`
**Map:** `docs/mirrors-edge-deep-research/11-状态机全图.md`

## Global Constraints

- 所有测试通过 `.\tools\run_tests.ps1` 运行；**通过标准是 `failures: 0` 且无 `unexpected engine error` 行**。
- `checks:` 总数变化必须能被解释（逐 tick 断言的循环会随行为时长变化），不得默认接受。
- 每个 Move 的**每条返回路径**都必须调用 `player.set_grounded(...)`，否则 `MoveManager` 的声明不变量会报错。
- 数值来源标注沿用现有约定：`✅` 实测/照抄 CDO、`⚠️` 项目自定、`❓` 未知。
- 文件行尾为 CRLF，用 Python 改文件时须 `io.open(p,'rb')` 读取并保留行尾。
- 注释用英文（项目约定）。

---

### Task 1: 抽出 `AirborneMove`，拆出真正的 `JumpMove`

**Files:**
- Create: `scripts/player/moves/airborne_move.gd`
- Create: `scripts/player/moves/jump_move.gd`
- Modify: `scripts/player/moves/falling_move.gd`（改为继承 `AirborneMove`，删掉 `current_config()` 与临时速度守卫）
- Modify: `scripts/player/moves/move.gd`（加 `JUMP` 常量）
- Modify: `scripts/player/player.gd:465-472`（注册表加一行）
- Test: `tests/test_airborne_chain.gd`

**Interfaces:**
- Consumes: `Move` 基类（`player` / `config` / `cfg` / `current_config()` / `enter()` / `physics_update()`）；`MoveConfig.check_for_grab|check_for_vault_over|check_for_wall_climb`
- Produces:
  - `Move.JUMP: StringName = &"Jump"`
  - `AirborneMove.probe_transition() -> StringName` — 按 `current_config()` 的 `check_*` 依次探测 wall/vault/grab，返回目标状态名或 `KEEP`
  - `AirborneMove.settle_landing(delta) -> StringName` — 落地则结算并返回落点状态，否则 `KEEP`
  - `JumpMove` / `FallingMove` 均继承 `AirborneMove`

- [ ] **Step 1: 写失败测试**

新建 `tests/test_airborne_chain.gd`：

```gdscript
class_name TestAirborneChain
extends TestCase

const TestWorld = preload("res://tests/world_fixture.gd")

func _airborne_world() -> Dictionary:
	var world := TestWorld.build(tree, MovementConfig.new())
	return world

func test_a_jump_starts_in_the_jump_state() -> void:
	var world := _airborne_world()
	await step(1)
	TestWorld.place(world)
	await step(30)
	var player: Player = world["player"]
	world["input"].press_jump()
	await step(2)
	check(player.move_manager.current_name == Move.JUMP, \
		"leaving the ground did not enter Jump (got %s)" % player.move_manager.current_name)
	TestWorld.teardown(world)
	await step(1)

func test_jump_becomes_falling_at_the_measured_threshold() -> void:
	# I3: 单行线。速度掉破 EnterToFallingZSpeed 即转 Falling，且不可逆。
	var cfg := MovementConfig.new()
	var world := TestWorld.build(tree, cfg)
	await step(1)
	TestWorld.place(world)
	await step(30)
	var player: Player = world["player"]
	world["input"].press_jump()
	await step(2)
	check(player.move_manager.current_name == Move.JUMP, "test setup: not in Jump")
	for i in 200:
		await step(1)
		if player.move_manager.current_name != Move.JUMP:
			break
	check(player.move_manager.current_name == Move.FALLING, \
		"Jump never handed off to Falling")
	check_greater(cfg.pawn.enter_to_falling_z_speed + 0.5, player.velocity.y, \
		"handed off before the descent threshold")
	TestWorld.teardown(world)
	await step(1)
```

- [ ] **Step 2: 运行确认失败**

Run: `.\tools\run_tests.ps1`
Expected: `test_airborne_chain.gd` 报 `Move.JUMP` 未定义（Parse Error）

- [ ] **Step 3: 加 `JUMP` 常量**

`scripts/player/moves/move.gd`，在 `const FALLING` 之后加一行：

```gdscript
const JUMP: StringName = &"Jump"
```

- [ ] **Step 4: 建 `AirborneMove` 基类**

新建 `scripts/player/moves/airborne_move.gd`。把 `falling_move.gd` 现有的三段探测（行 ~60–130 的 wall / vault / grab）与落地结算（行 ~133–170）原样搬入，**逻辑不变**，只把入口条件换成读 `current_config()`：

```gdscript
class_name AirborneMove
extends Move

# Shared machinery for every airborne state. The original splits one airborne
# stretch into several TdMove classes that differ ONLY in which probes they
# run (11 §11.2); the physics is identical. Keeping the physics here and
# letting subclasses declare their probe set is what makes those differences
# enforceable instead of advisory.

## Gravity and air control, shared by every airborne state. Terminal velocity
## is clamped here rather than per-state so a subclass cannot forget it and
## produce a body that accelerates forever.
func apply_air_physics(delta: float, wish_dir: Vector3) -> void:
	player.air_accelerate(wish_dir, delta)
	player.velocity.y -= config.pawn.gravity * delta
	player.velocity.y = maxf(player.velocity.y, -config.pawn.terminal_velocity)

## Probes this state is allowed to run, in the original's own precedence
## order: wall, then vault, then grab (05 §5.7 -- an overshooting jump tries
## the vault table before falling through to the slowest path, the ledge hang).
## Returns a target state name, or KEEP when nothing fired.
func probe_transition() -> StringName:
	var c := current_config()
	if c.check_for_wall_climb and player.probes != null \
			and player.horizontal_speed() >= config.wall_run.wall_running_min_speed:
		var heading: Vector3 = Vector3(player.velocity.x, 0.0, player.velocity.z).normalized()
		var wall: Dictionary = player.probes.wall_query(heading)
		if wall["valid"] and player.move_manager.can_enter(WALL_RUN):
			var incidence: float = wall["incidence"]
			if incidence <= config.wall_run.wall_running_forward_max_start_angle \
					or incidence >= config.wall_run.wall_running_strafe_start_angle:
				return WALL_RUN

	if c.check_for_vault_over and player.probes != null:
		var hit: Dictionary = player.probes.vault_query()
		if hit["valid"]:
			var variant: Dictionary = config.speed_vault.pick_variant(
				hit["height"], hit["vault_over"], player.velocity.y, player.horizontal_speed())
			if config.speed_vault.should_commit(hit["distance"], player.horizontal_speed(), variant):
				player.pending_vault_variant = variant
				return SPEED_VAULT

	if c.check_for_grab and player.probes != null and player.move_manager.can_enter(GRAB):
		if player.probes.ledge_query()["valid"]:
			return GRAB

	return KEEP
```

⚠️ 搬运时**逐段比对原文件**，注释一并带走——那些注释记录了为什么 vault 排在 grab 之前、为什么 wall 每 tick 重新查询。

- [ ] **Step 5: 把落地结算也搬进基类**

同文件追加。这段来自 `falling_move.gd:133-170`，**一字不改地搬**，包括那段解释"为什么要多喂一次 fall_tracker"的长注释：

```gdscript
## Runs this tick's move_and_slide() and, if the body touched down, settles the
## landing. Returns the state to hand off to, or KEEP while still airborne.
func settle_landing(delta: float) -> StringName:
	var impact_speed := maxf(-player.velocity.y, 0.0)
	player.move_and_slide()
	if not player.is_on_floor():
		player.set_grounded(false)
		return KEEP
	player.fall_tracker.update(delta, -impact_speed, player.global_position.y)
	var fall_height: float = player.fall_tracker.fall_height
	var rolled: bool = fall_height >= config.pawn.skill_roll_landing_height \
		and player.consume_roll()
	player.last_landing_rolled = rolled
	player.last_landing_fall_height = fall_height
	_apply_landing_cost(fall_height, rolled)
	player.set_grounded(true)
	player.notify_landed(impact_speed)
	return landing_destination(fall_height, rolled)

## Where a landing from this state leads. Overridden by subclasses.
func landing_destination(_fall_height: float, _rolled: bool) -> StringName:
	return WALKING

func _apply_landing_cost(fall_height: float, rolled: bool) -> void:
	var keep: float = player.landing_keep_ratio(fall_height, rolled)
	player.velocity.x *= keep
	player.velocity.z *= keep
```

- [ ] **Step 6: 写 `JumpMove`**

新建 `scripts/player/moves/jump_move.gd`：

```gdscript
class_name JumpMove
extends AirborneMove

# The original's TdMove_Jump: the airborne stretch you still own. It is the
# only phase that may start a wall run -- seven states hold bCheckForWallClimb
# and every one of them is a deliberate launch (11 §11.2). A long descent that
# merely brushes a building is NOT one of them.

func physics_update(delta: float, input: MoveInput) -> StringName:
	apply_air_physics(delta, player.wish_direction(input))

	var probed := probe_transition()
	if probed != KEEP:
		player.set_grounded(false)
		return probed

	# Handing off downward is checked BEFORE this tick's landing settle, so a
	# tick that both crosses the threshold and touches down lands as Falling
	# would -- the descent is what the landing is judged on.
	if player.velocity.y <= config.pawn.enter_to_falling_z_speed:
		player.set_grounded(false)
		return FALLING

	return settle_landing(delta)
```

- [ ] **Step 7: 让 `FallingMove` 继承基类并删掉重复逻辑**

`scripts/player/moves/falling_move.gd` 改为：

```gdscript
class_name FallingMove
extends AirborneMove

# The original's TdMove_Falling: airborne, but no longer a launch. It cannot
# start a wall run (no bCheckForWallClimb), and it is one of only six states
# that can hand off to uncontrolled falling (11 §11.2).

func physics_update(delta: float, input: MoveInput) -> StringName:
	# Coyote time lives HERE and not in JumpMove: it exists for a player who
	# walked off a ledge without jumping, which is exactly the state Falling
	# describes. Player.consume_jump() already gates on the timer.
	if player.consume_jump():
		player.velocity.y = config.pawn.base_jump_z
		var facing: Vector3 = -player.global_transform.basis.z
		player.velocity.x += facing.x * config.pawn.jump_add_xy
		player.velocity.z += facing.z * config.pawn.jump_add_xy
		player.set_grounded(false)
		return JUMP

	apply_air_physics(delta, player.wish_direction(input))

	var probed := probe_transition()
	if probed != KEEP:
		player.set_grounded(false)
		return probed

	return settle_landing(delta)
```

**删除**：`current_config()` 覆写、`still_in_jump` 速度守卫、已搬到基类的三段探测与落地结算、`_apply_landing_cost()`。

**保留在 `FallingMove`**：`consume_jump()` 土狼时间分支（见上方代码）。它服务的是
"走出边缘但还没跳"的玩家，正是 `Falling` 描述的处境；`JumpMove` 里的人已经跳过了。
消费掉缓冲的跳跃后返回 `JUMP`,因为那一刻起他确实处在一次主动起跳中。

- [ ] **Step 8: 让 `JumpConfig` 不再检查 wall climb 之外的差异，并确认 `FallingConfig`**

`scripts/player/config/moves/falling_config.gd` 的 `_init()` 必须**不设** `check_for_wall_climb`，并补注释：

```gdscript
	# ✅ 11 §11.2: TdMove_Falling holds ForGrab and ForVaultOver but NOT
	# ForWallClimb. That single absence is the whole rule against a long drop
	# converting into a wall run -- it is enforced here, not by a speed guard.
	check_for_grab = true
	check_for_vault_over = true
```

- [ ] **Step 9: 注册 `JumpMove`**

`scripts/player/player.gd` 注册表加一行（在 WALKING 之后）：

```gdscript
		[Move.JUMP, JumpMove.new(), config.jump],
```

并把 `WalkingMove` 跳跃分支的 `return FALLING` 改为 `return JUMP`（`walking_move.gd:26`）。

- [ ] **Step 10: 运行测试**

Run: `.\tools\run_tests.ps1`
Expected: `failures: 0`。若 `test_wall_run_entry.gd::test_a_long_drop_cannot_convert_into_a_wall_run` 失败，说明 `FallingConfig` 仍带 `check_for_wall_climb`。

- [ ] **Step 11: 提交**

```bash
git add scripts/player/moves/ scripts/player/config/moves/ scripts/player/player.gd tests/test_airborne_chain.gd
git commit -m "refactor(moves): split Jump out of Falling behind a shared AirborneMove"
```

---

### Task 2: `FallUncontrolledMove` — 失控从布尔变成状态

**Files:**
- Create: `scripts/player/moves/fall_uncontrolled_move.gd`
- Create: `scripts/player/config/moves/fall_uncontrolled_config.gd`
- Modify: `scripts/player/movement_config.gd`（加 `fall_uncontrolled` 槽）
- Modify: `scripts/player/moves/move.gd`（加 `FALL_UNCONTROLLED` 常量）
- Modify: `scripts/player/moves/falling_move.gd`（加转出判断）
- Modify: `scripts/player/player.gd`（删 `uncontrolled_fall` 布尔与 `update_uncontrolled_fall()`，注册新状态）
- Modify: `tests/test_uncontrolled_fall.gd`（改为验证状态而非布尔）

**Interfaces:**
- Consumes: `AirborneMove.settle_landing()`、`Player.fall_tracker.fall_height`、`Player.died_from_fall` 信号
- Produces: `Move.FALL_UNCONTROLLED: StringName = &"FallUncontrolled"`

- [ ] **Step 1: 写失败测试**

替换 `tests/test_uncontrolled_fall.gd` 全文：

```gdscript
class_name TestUncontrolledFall
extends TestCase

# I1/I2/I4 (spec §3). Uncontrolled falling is a STATE, not a flag: the original
# gives it ControllerState = PlayerDying and strips every probe except soft
# landing, so nothing the player does can convert it into a grab, a vault or a
# wall run. A boolean cannot enforce that -- the probes simply keep running.

const TestWorld = preload("res://tests/world_fixture.gd")

func _falling_world() -> Dictionary:
	return TestWorld.build(tree, MovementConfig.new())

func test_a_deep_fall_enters_the_uncontrolled_state() -> void:
	var cfg := MovementConfig.new()
	var world := TestWorld.build(tree, cfg)
	await step(1)
	TestWorld.place(world)
	await step(30)
	var player: Player = world["player"]
	player.global_position.y += cfg.pawn.falling_uncontrolled_height + 3.0
	player.fall_tracker.reset(player.global_position.y)
	await step(1)
	for i in 240:
		await step(1)
		if player.move_manager.current_name == Move.FALL_UNCONTROLLED:
			break
	check(player.move_manager.current_name == Move.FALL_UNCONTROLLED, \
		"a fall past the threshold did not enter FallUncontrolled")
	TestWorld.teardown(world)
	await step(1)

func test_the_uncontrolled_state_runs_no_probes() -> void:
	# I1. The config is the enforcement point, so assert it directly: a future
	# edit that switches one of these back on fails here rather than being
	# discovered as "I grabbed a ledge while dying".
	var cfg := MovementConfig.new()
	check(not cfg.fall_uncontrolled.check_for_grab, "uncontrolled falling can grab")
	check(not cfg.fall_uncontrolled.check_for_vault_over, "uncontrolled falling can vault")
	check(not cfg.fall_uncontrolled.check_for_wall_climb, "uncontrolled falling can wall run")

func test_it_is_a_one_way_door() -> void:
	# I4. Regaining height mid-air must not hand control back.
	var cfg := MovementConfig.new()
	var world := TestWorld.build(tree, cfg)
	await step(1)
	TestWorld.place(world)
	await step(30)
	var player: Player = world["player"]
	player.global_position.y += cfg.pawn.falling_uncontrolled_height + 3.0
	player.fall_tracker.reset(player.global_position.y)
	await step(1)
	for i in 240:
		await step(1)
		if player.move_manager.current_name == Move.FALL_UNCONTROLLED:
			break
	check(player.move_manager.current_name == Move.FALL_UNCONTROLLED, "test setup: never entered")
	player.velocity.y = 8.0
	await step(5)
	check(player.move_manager.current_name == Move.FALL_UNCONTROLLED, \
		"climbing back up escaped the uncontrolled state")
	TestWorld.teardown(world)
	await step(1)
```

- [ ] **Step 2: 运行确认失败**

Run: `.\tools\run_tests.ps1`
Expected: Parse Error，`Move.FALL_UNCONTROLLED` 与 `cfg.fall_uncontrolled` 未定义

- [ ] **Step 3: 加常量与配置类**

`move.gd` 加：

```gdscript
const FALL_UNCONTROLLED: StringName = &"FallUncontrolled"
```

新建 `scripts/player/config/moves/fall_uncontrolled_config.gd`：

```gdscript
class_name FallUncontrolledConfig
extends MoveConfig

# The original's TdMove_FallingUncontrolled. ✅ Its CDO carries exactly one
# check -- bCheckForSoftLanding -- and ControllerState = PlayerDying. Every
# other probe is absent, which is what makes the outcome inevitable rather
# than merely likely (11 §11.2).

func _init() -> void:
	check_for_grab = false
	check_for_vault_over = false
	check_for_wall_climb = false
```

`movement_config.gd` 加槽（在 `falling` 之后）：

```gdscript
@export var fall_uncontrolled: FallUncontrolledConfig = FallUncontrolledConfig.new()
```

- [ ] **Step 4: 写 `FallUncontrolledMove`**

新建 `scripts/player/moves/fall_uncontrolled_move.gd`：

```gdscript
class_name FallUncontrolledMove
extends AirborneMove

# ControllerState = PlayerDying. Input is gone the moment this state is
# entered -- in the air, not on impact -- which is why a roll cannot save it.
# Entering is one-way: regaining height does not hand control back, because
# the original treats the outcome as already settled.

func physics_update(delta: float, _input: MoveInput) -> StringName:
	# No wish direction: the body falls, the player watches.
	apply_air_physics(delta, Vector3.ZERO)
	# No probe_transition() call at all -- the config forbids every probe, and
	# not calling it makes that structural rather than a matter of trusting
	# three booleans.
	return settle_landing(delta)

func landing_destination(_fall_height: float, _rolled: bool) -> StringName:
	player.died_from_fall.emit()
	return WALKING
```

- [ ] **Step 5: 从 `FallingMove` 转入**

`falling_move.gd` 的 `physics_update` 里，在 `probe_transition()` 之前插入：

```gdscript
	# Only Falling may hand off here: six states hold
	# bCheckExitToUncontrolledFalling and not one of them is a launch (I2).
	if player.fall_tracker.fall_height >= config.pawn.falling_uncontrolled_height:
		player.set_grounded(false)
		return FALL_UNCONTROLLED
```

- [ ] **Step 6: 删除布尔**

`player.gd` 删除：`var uncontrolled_fall`、`func update_uncontrolled_fall()`、`reset_state()` 与 `set_grounded()` 里对它的清除、`falling_move.gd` 里对它的引用。注册表加：

```gdscript
		[Move.FALL_UNCONTROLLED, FallUncontrolledMove.new(), config.fall_uncontrolled],
```

- [ ] **Step 7: 运行测试**

Run: `.\tools\run_tests.ps1`
Expected: `failures: 0`。`test_fatal_fall_respawn.gd` 应仍通过（它断言的是重生不崩溃，与状态名无关）。

- [ ] **Step 8: 提交**

```bash
git add scripts/ tests/
git commit -m "feat(moves): make uncontrolled falling a state instead of a flag"
```

---

### Task 3: `ScreenEffects` 屏幕效果层

**Files:**
- Create: `scripts/camera/screen_effects.gd`
- Create: `shaders/screen_effects.gdshader`
- Modify: `scenes/player/player.tscn`（`CameraRig` 下加 `CanvasLayer > ColorRect`）
- Modify: `tools/player_builder.gd`（生成器同步，否则 `test_generated_scenes` 会判定场景过期）
- Test: `tests/test_screen_effects.gd`

**Interfaces:**
- Produces:
  - `ScreenEffects.set_tint(color: Color, amount: float) -> void`
  - `ScreenEffects.set_desaturation(amount: float) -> void`
  - `ScreenEffects.set_blur(amount: float) -> void`
  - `ScreenEffects.tint_amount / desaturation / blur` 三个只读属性供测试断言

- [ ] **Step 1: 写失败测试**

新建 `tests/test_screen_effects.gd`：

```gdscript
class_name TestScreenEffects
extends TestCase

# The effect layer holds NO time logic: states drive it with plain numbers and
# do their own fading. That split is what keeps "how a landing feels" in the
# landing state instead of smeared across a shader wrapper.

func _effects() -> ScreenEffects:
	var fx := ScreenEffects.new()
	tree.root.add_child(fx)
	return fx

func test_it_starts_neutral() -> void:
	var fx := _effects()
	await step(1)
	check_approx(fx.tint_amount, 0.0, 0.0001, "tint is not neutral at rest")
	check_approx(fx.desaturation, 0.0, 0.0001, "desaturation is not neutral at rest")
	check_approx(fx.blur, 0.0, 0.0001, "blur is not neutral at rest")
	fx.queue_free()
	await step(1)

func test_each_channel_is_independent() -> void:
	var fx := _effects()
	await step(1)
	fx.set_desaturation(1.0)
	check_approx(fx.tint_amount, 0.0, 0.0001, "setting desaturation moved the tint")
	check_approx(fx.blur, 0.0, 0.0001, "setting desaturation moved the blur")
	check_approx(fx.desaturation, 1.0, 0.0001, "desaturation did not take")
	fx.queue_free()
	await step(1)

func test_values_are_clamped() -> void:
	# States interpolate these every tick; a caller that overshoots by a hair
	# must not produce an out-of-range uniform.
	var fx := _effects()
	await step(1)
	fx.set_desaturation(1.4)
	check_approx(fx.desaturation, 1.0, 0.0001, "desaturation exceeded 1")
	fx.set_blur(-0.2)
	check_approx(fx.blur, 0.0, 0.0001, "blur went below 0")
	fx.queue_free()
	await step(1)
```

- [ ] **Step 2: 运行确认失败**

Run: `.\tools\run_tests.ps1`
Expected: Parse Error，`ScreenEffects` 未定义

- [ ] **Step 3: 写 shader**

新建 `shaders/screen_effects.gdshader`：

```glsl
shader_type canvas_item;

// One material carries all three effects so a state only ever writes numbers.
// Order matters: blur samples the scene, desaturation acts on what was
// sampled, tint sits on top of the result.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec4 tint_color : source_color = vec4(1.0, 0.0, 0.0, 1.0);
uniform float tint_amount : hint_range(0.0, 1.0) = 0.0;
uniform float desaturation : hint_range(0.0, 1.0) = 0.0;
uniform float blur : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec3 col;
	if (blur > 0.001) {
		// Mip-based blur: cheap, and the radius maps linearly onto the knob.
		col = textureLod(screen_tex, SCREEN_UV, blur * 4.0).rgb;
	} else {
		col = texture(screen_tex, SCREEN_UV).rgb;
	}
	// Rec. 709 luma -- a plain average reads as muddy on skin and sky.
	float luma = dot(col, vec3(0.2126, 0.7152, 0.0722));
	col = mix(col, vec3(luma), desaturation);
	col = mix(col, tint_color.rgb, tint_amount);
	COLOR = vec4(col, 1.0);
}
```

- [ ] **Step 4: 写 `ScreenEffects`**

新建 `scripts/camera/screen_effects.gd`：

```gdscript
class_name ScreenEffects
extends CanvasLayer

# A full-screen shader owned by the PLAYER, not the level: these effects
# describe what happened to the body, so they must survive a level change and
# must not fight the level's own WorldEnvironment for the same knobs.
#
# Deliberately stateless in time. A caller sets a number; fading in and out is
# the caller's business. See spec §6.

const SHADER := preload("res://shaders/screen_effects.gdshader")

var tint_amount: float = 0.0
var desaturation: float = 0.0
var blur: float = 0.0

var _rect: ColorRect
var _material: ShaderMaterial

func _ready() -> void:
	layer = 100
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_rect = ColorRect.new()
	_rect.material = _material
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)
	_push()

func set_tint(color: Color, amount: float) -> void:
	tint_amount = clampf(amount, 0.0, 1.0)
	if _material != null:
		_material.set_shader_parameter("tint_color", color)
	_push()

func set_desaturation(amount: float) -> void:
	desaturation = clampf(amount, 0.0, 1.0)
	_push()

func set_blur(amount: float) -> void:
	blur = clampf(amount, 0.0, 1.0)
	_push()

func clear() -> void:
	tint_amount = 0.0
	desaturation = 0.0
	blur = 0.0
	_push()

func _push() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("tint_amount", tint_amount)
	_material.set_shader_parameter("desaturation", desaturation)
	_material.set_shader_parameter("blur", blur)
```

- [ ] **Step 5: 运行测试**

Run: `.\tools\run_tests.ps1`
Expected: `failures: 0`

- [ ] **Step 6: 挂进玩家场景**

`scripts/player/player.gd` 加导出（紧邻 `camera_rig` / `probes`，用同样的写法）：

```gdscript
## The player's own full-screen effect layer. Null in headless tests that build
## a bare Player, so every caller must guard.
@export var screen_effects: ScreenEffects
```

修改 `tools/player_builder.gd`，在 `CameraRig` 下增加 `ScreenEffects` 子节点，并把它
写进 `Player` 的 `node_paths`（与 `camera_rig` / `probes` 同一处）。然后重新生成：

```bash
.engine\Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tools/build_player_scene.gd
```

- [ ] **Step 7: 运行测试并提交**

Run: `.\tools\run_tests.ps1`
Expected: `failures: 0`，`test_generated_scenes` 通过

```bash
git add shaders/ scripts/camera/screen_effects.gd tools/player_builder.gd scenes/player/player.tscn tests/test_screen_effects.gd
git commit -m "feat(camera): add a player-owned screen effect layer"
```

---

### Task 4: `LandingMove` — 2 秒硬直

**Files:**
- Create: `scripts/player/moves/landing_move.gd`
- Modify: `scripts/player/config/moves/landing_config.gd`（加时长与视觉参数）
- Modify: `scripts/player/moves/move.gd`（加 `LANDING` 常量）
- Modify: `scripts/player/moves/airborne_move.gd`（`landing_destination` 默认实现判定硬着陆）
- Modify: `scripts/player/player.gd`（注册）
- Test: `tests/test_landing_lockout.gd`

**Interfaces:**
- Consumes: `Player.landing_keep_ratio()`、`CameraRig.set_crouch_amount()`、`ScreenEffects.set_tint()`
- Produces: `Move.LANDING: StringName = &"Landing"`；`LandingConfig.lockout_time / tint_color / camera_pitch_offset`

- [ ] **Step 1: 写失败测试**

新建 `tests/test_landing_lockout.gd`：

```gdscript
class_name TestLandingLockout
extends TestCase

# ✅ 2.00 s is MEASURED, not designed: six hard landings in the original,
# timed from the last Falling frame to the first Walking frame, read
# 2.03 / 2.00 / 2.00 / 2.00 / 2.00 / 2.02 (spec §时间轴).

const TestWorld = preload("res://tests/world_fixture.gd")

func test_the_lockout_is_the_measured_two_seconds() -> void:
	var cfg := MovementConfig.new()
	check_approx(cfg.landing.lockout_time, 2.0, 0.0001, \
		"the hard-landing lockout is not the measured 2.00 s")

func test_a_hard_unrolled_landing_enters_landing() -> void:
	var cfg := MovementConfig.new()
	var world := TestWorld.build(tree, cfg)
	await step(1)
	TestWorld.place(world)
	await step(30)
	var player: Player = world["player"]
	# Above hard_landing_height, below the death threshold, no roll input.
	player.global_position.y += cfg.pawn.hard_landing_height + 1.0
	player.fall_tracker.reset(player.global_position.y)
	await step(1)
	for i in 240:
		await step(1)
		if player.move_manager.current_name == Move.LANDING:
			break
	check(player.move_manager.current_name == Move.LANDING, \
		"a hard unrolled landing did not enter Landing")
	TestWorld.teardown(world)
	await step(1)

func test_a_soft_landing_skips_it_entirely() -> void:
	# Below hard_landing_height there is no penalty at all (03 §3.1), so there
	# must be no lockout either.
	var cfg := MovementConfig.new()
	var world := TestWorld.build(tree, cfg)
	await step(1)
	TestWorld.place(world)
	await step(30)
	var player: Player = world["player"]
	player.global_position.y += cfg.pawn.hard_landing_height - 2.0
	player.fall_tracker.reset(player.global_position.y)
	await step(1)
	for i in 240:
		await step(1)
		if player.grounded and player.move_manager.current_name != Move.FALLING:
			break
	check(player.move_manager.current_name != Move.LANDING, \
		"a landing below the hard threshold was locked out")
	TestWorld.teardown(world)
	await step(1)
```

- [ ] **Step 2: 运行确认失败**

Run: `.\tools\run_tests.ps1`
Expected: `cfg.landing.lockout_time` 未定义

- [ ] **Step 3: 补 `LandingConfig`**

`scripts/player/config/moves/landing_config.gd` 追加：

```gdscript
	# ✅ MEASURED: 2.00 s, six hard landings, timed from the last Falling frame
	# to the first Walking frame (2.03 / 2.00 / 2.00 / 2.00 / 2.00 / 2.02).
	# Do NOT measure the Landing state's own span -- the original's HUD misreads
	# the state name often enough to slice one lockout into several fragments.
@export var lockout_time: float = 2.0
## ⚠️ Project-defined. The original's knee-clutch is animation root motion;
## nothing in its data describes a screen tint.
@export var tint_color: Color = Color(0.6, 0.0, 0.0)
@export var camera_pitch_offset: float = 0.35
```

同时 `_init()` 里加视角锁定：

```gdscript
	constrain_look = true
	min_look_constraint = Vector3(-0.2, -0.2, 0.0)
	max_look_constraint = Vector3(0.2, 0.2, 0.0)
```

- [ ] **Step 4: 写 `LandingMove`**

新建 `scripts/player/moves/landing_move.gd`：

```gdscript
class_name LandingMove
extends Move

# The 2 s lockout after a hard landing taken without a roll. Input is refused
# for the whole duration -- that is the entire point -- and the camera plus the
# red tint recover across it so the player can see the penalty draining rather
# than merely waiting it out.

var _elapsed: float = 0.0

func enter(_previous: StringName) -> void:
	_elapsed = 0.0
	player.velocity = Vector3.ZERO

func physics_update(delta: float, _input: MoveInput) -> StringName:
	_elapsed += delta
	var t: float = clampf(_elapsed / maxf(cfg.lockout_time, 0.0001), 0.0, 1.0)

	# Recovering, not holding: 1 at touchdown falling to 0 at release.
	var severity: float = 1.0 - t
	if player.camera_rig != null:
		player.camera_rig.set_crouch_amount(severity)
		player.camera_rig.set_landing_pitch_offset(cfg.camera_pitch_offset * severity)
	if player.screen_effects != null:
		player.screen_effects.set_tint(cfg.tint_color, severity)

	player.velocity.y = -config.pawn.floor_snap_speed
	player.move_and_slide()
	player.set_grounded(player.is_on_floor())

	if t >= 1.0:
		return WALKING
	return KEEP

func exit() -> void:
	if player.camera_rig != null:
		player.camera_rig.set_landing_pitch_offset(0.0)
	if player.screen_effects != null:
		player.screen_effects.set_tint(cfg.tint_color, 0.0)
```

- [ ] **Step 5: 加 `CameraRig.set_landing_pitch_offset()`**

`scripts/camera/camera_rig.gd` 加一个成员与 setter，并在 `update_effects()` 末尾把它加到最终 pitch 上（与 `_dip` 同一层级）：

```gdscript
var _landing_pitch: float = 0.0

## An additive downward pitch owned by LandingMove. Separate from _dip because
## dip is a spring driven by impact speed and recovers on its own schedule;
## this one is driven explicitly by a state that knows how long it has left.
func set_landing_pitch_offset(radians: float) -> void:
	_landing_pitch = radians
```

并在 `reset_state()` 中清零。

- [ ] **Step 6: 路由到 `LandingMove`**

`airborne_move.gd` 的 `landing_destination()` 改为：

```gdscript
func landing_destination(fall_height: float, rolled: bool) -> StringName:
	# Only the hard, unrolled case is locked out. Below the threshold a landing
	# costs nothing at all, so pausing the player there would be a penalty the
	# original does not levy (03 §3.1).
	if fall_height >= config.pawn.hard_landing_height and not rolled:
		return LANDING
	return WALKING
```

`move.gd` 加常量，`player.gd` 注册表加 `[Move.LANDING, LandingMove.new(), config.landing]`。

- [ ] **Step 7: 运行测试并提交**

Run: `.\tools\run_tests.ps1`
Expected: `failures: 0`

```bash
git add scripts/ tests/test_landing_lockout.gd
git commit -m "feat(moves): add the measured 2s hard-landing lockout"
```

---

### Task 5: Arena 死亡演出

**Files:**
- Create: `scripts/level/death_sequence.gd`
- Modify: `scripts/level/arena.gd`（收到 `died_from_fall` 后先播演出再重生）
- Modify: `scripts/camera/camera_rig.gd`（加演出接管通道）
- Test: `tests/test_death_sequence.gd`

**Interfaces:**
- Consumes: `Player.died_from_fall`、`ScreenEffects.set_desaturation()`、`CameraRig.begin_cinematic()/set_cinematic_pose()/end_cinematic()`
- Produces: `DeathSequence.play(player) -> void`、`DeathSequence.finished` 信号

- [ ] **Step 1: 写失败测试**

新建 `tests/test_death_sequence.gd`：

```gdscript
class_name TestDeathSequence
extends TestCase

# Death is NOT a Move (spec §1): PlayerDying appears once in the whole CDO
# library, on FallingUncontrolled itself, and no Move succeeds it on landing.
# The sequence therefore belongs to the level, and this test pins that
# ownership -- if it ever needs a Move to run, the design drifted.

func test_the_sequence_reports_its_own_duration() -> void:
	var seq := DeathSequence.new()
	tree.root.add_child(seq)
	await step(1)
	check_greater(seq.total_duration(), 1.0, "the death sequence is too short to read")
	check_greater(3.0, seq.total_duration(), "the death sequence outstays its welcome")
	seq.queue_free()
	await step(1)

func test_it_finishes_and_says_so() -> void:
	var seq := DeathSequence.new()
	tree.root.add_child(seq)
	await step(1)
	var done := {"hit": false}
	seq.finished.connect(func() -> void: done["hit"] = true)
	seq.play(null)
	var ticks: int = int(seq.total_duration() * Engine.physics_ticks_per_second) + 20
	for i in ticks:
		await step(1)
		if done["hit"]:
			break
	check(done["hit"], "the death sequence never finished")
	seq.queue_free()
	await step(1)
```

- [ ] **Step 2: 运行确认失败**

Run: `.\tools\run_tests.ps1`
Expected: Parse Error，`DeathSequence` 未定义

- [ ] **Step 3: 写 `DeathSequence`**

新建 `scripts/level/death_sequence.gd`：

```gdscript
class_name DeathSequence
extends Node

# ⚠️ Every number here is project-defined. The original plays a cutscene at
# this point and its data says nothing about camera timing.
#
# Owned by the level rather than by a Move, because by the time this runs the
# body has no state left to be in -- see spec §1 on the two orthogonal state
# machines.

signal finished

const DROP_TIME := 0.35     ## eye height -> half crouch
const HOLD_TIME := 0.35     ## a beat on the ground before toppling
const TOPPLE_TIME := 0.70   ## quarter circle to the left, pivoting on the feet

var _player: Player
var _elapsed: float = 0.0
var _playing: bool = false
var _eye_height: float = 0.0

func total_duration() -> float:
	return DROP_TIME + HOLD_TIME + TOPPLE_TIME

func play(player: Player) -> void:
	_player = player
	_elapsed = 0.0
	_playing = true
	if _player != null:
		_eye_height = _player.config.camera.eye_height
		if _player.camera_rig != null:
			_player.camera_rig.begin_cinematic()
		if _player.screen_effects != null:
			_player.screen_effects.set_desaturation(1.0)

func _physics_process(delta: float) -> void:
	if not _playing:
		return
	_elapsed += delta
	if _player != null and _player.camera_rig != null:
		var pose := _pose_at(_elapsed)
		_player.camera_rig.set_cinematic_pose(pose[0], pose[1])
	if _elapsed >= total_duration():
		_playing = false
		if _player != null:
			if _player.camera_rig != null:
				_player.camera_rig.end_cinematic()
			if _player.screen_effects != null:
				_player.screen_effects.set_desaturation(0.0)
		finished.emit()

## Local camera offset and roll at time t. Returns [Vector3, float].
func _pose_at(t: float) -> Array:
	var half: float = _eye_height * 0.5
	if t < DROP_TIME:
		# Ease-out: the legs give way fast, then settle.
		var k: float = 1.0 - pow(1.0 - (t / DROP_TIME), 2.0)
		return [Vector3(0.0, lerpf(_eye_height, half, k) - _eye_height, 0.0), 0.0]
	if t < DROP_TIME + HOLD_TIME:
		return [Vector3(0.0, half - _eye_height, 0.0), 0.0]
	var k2: float = clampf((t - DROP_TIME - HOLD_TIME) / TOPPLE_TIME, 0.0, 1.0)
	# Pivot on the feet: the head sweeps a quarter circle of radius `half`
	# rather than sliding sideways at a fixed height.
	var angle: float = k2 * PI * 0.5
	var y: float = half * cos(angle) - _eye_height
	var x: float = -half * sin(angle)
	return [Vector3(x, y, 0.0), -angle]
```

- [ ] **Step 4: 加 `CameraRig` 演出通道**

`scripts/camera/camera_rig.gd`：

```gdscript
var _cinematic: bool = false
var _cinematic_offset: Vector3 = Vector3.ZERO
var _cinematic_roll: float = 0.0

## While cinematic, update_effects() yields entirely: bob, dip, crouch and the
## look constraint all step aside, and the pose comes from the caller. Without
## this the death sequence would fight running sway for the same transform.
func begin_cinematic() -> void:
	_cinematic = true

func set_cinematic_pose(offset: Vector3, roll: float) -> void:
	_cinematic_offset = offset
	_cinematic_roll = roll

func end_cinematic() -> void:
	_cinematic = false
	_cinematic_offset = Vector3.ZERO
	_cinematic_roll = 0.0
```

并在 `update_effects()` 开头插入：

```gdscript
	if _cinematic:
		position = Vector3(0.0, _config.camera.eye_height, 0.0) + _cinematic_offset
		rotation.z = _cinematic_roll
		return
```

`apply_look()` 开头也加 `if _cinematic: return`,并在 `reset_state()` 中调用 `end_cinematic()`。

- [ ] **Step 5: 接到 Arena**

`scripts/level/arena.gd`：把 `died_from_fall` 的接线改为播放演出，演出结束再重生。

```gdscript
@onready var _death_sequence: DeathSequence = DeathSequence.new()
```

在 `_ready()` 中：

```gdscript
	add_child(_death_sequence)
	_death_sequence.finished.connect(reset_player)
	if not player.died_from_fall.is_connected(_on_died_from_fall):
		player.died_from_fall.connect(_on_died_from_fall, CONNECT_DEFERRED)

func _on_died_from_fall() -> void:
	_death_sequence.play(player)
```

- [ ] **Step 6: 运行测试并提交**

Run: `.\tools\run_tests.ps1`
Expected: `failures: 0`；`test_fatal_fall_respawn.gd` 里的重生等待需放宽到覆盖演出时长（把循环上限从 180 提高到 400 tick）

```bash
git add scripts/level/ scripts/camera/camera_rig.gd tests/test_death_sequence.gd tests/test_fatal_fall_respawn.gd
git commit -m "feat(level): play a death sequence before respawning"
```

---

## 完成后

四条不变量（I1/I2/I4/I5）此时由**状态与配置**保证而非 if；I3/I6/I7 由 Task 1/2/4 的测试直接钉住。

`docs/mirrors-edge-deep-research/11-状态机全图.md` §11.7 的"已实现"表需要更新：新增 `Jump` `FallingUncontrolled` `Landing`,并删掉 §11.7 末尾关于"`Jump` 缺失的代价"的整段说明。
