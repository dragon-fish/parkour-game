class_name MoveManager
extends Node

signal move_changed(from: StringName, to: StringName)

var current_name: StringName = &""

## Set by Player at registration, for the two questions the manager itself
## asks about statuses. Untyped for the same reason Move.player is -- see the
## note above Move's own name constants.
var player

var _current: Move = null
var _moves: Dictionary = {}

## Seconds of cooldown still owed per move name. An entry only exists while a
## move is actually cooling down.
var _redo_cooldowns: Dictionary = {}

func register(move_name: StringName, move: Move) -> void:
	_moves[move_name] = move

## The registered instance for a move name, or null. Read every physics tick
## by CharacterAnimator (to reach GrabMove.is_mantling()), and by tests that
## need to observe a move's own internals — SlideMove.is_crawling(), which
## nothing outside the move can otherwise distinguish from ordinary sliding.
func move_for(move_name: StringName) -> Move:
	return _moves.get(move_name)

## False while `move_name`'s own redo_move_time is still running. The original
## declares this per move (TdMove.RedoMoveTime) rather than scattering it
## across the callers, which is what lets Player stop carrying three separate
## hand-rolled cooldowns of its own (the ledge regrab timer, the recent-wall
## list, and the wall reattach window).
func can_enter(move_name: StringName) -> bool:
	if _redo_cooldowns.has(move_name):
		return false
	# A level may forbid a move outright. Asked HERE for the same reason the
	# cooldown is: no move can forget, and a refusal never drops the tick's
	# transition intent into some third state. The moves that commit before
	# they announce themselves are refused earlier instead, each at its own
	# commit point:
	#
	#   JUMP        Player.consume_jump() / consume_buffered_jump()
	#   SLIDE       WalkingMove.physics_update(), before consume_roll()
	#   SKILL_ROLL  AirborneMove.settle_landing(), before consume_roll()
	#   GRAB        IntoGrabMove._settle(), before the body is squared up
	#
	# A refusal here would still leave the body launched, snapped or the press
	# spent.
	if player != null and player.statuses.is_move_blocked(move_name):
		# A CROUCH THE BODY CANNOT AVOID IS NOT A TECHNIQUE. What a level
		# forbids is the player CHOOSING to duck; being unable to stand is the
		# geometry talking, and refusing it would leave SlideMove with no exit
		# under a low ceiling -- a slide that cannot end and cannot be steered
		# out of. Asked here rather than passed down from the caller because
		# the answer is an objective fact about where the body is standing, so
		# no move has to remember to declare which kind of crouch it meant.
		if move_name == Move.CROUCH and not player.has_headroom():
			return true
		return false
	return true

## The active move's own friction multiplier, or 1.0 when there is no move or
## no config. Read by Player.ground_accelerate() so braking respects whatever
## move is in force without Player having to know which one that is.
## The active move's config, or null when there is no move. The two
## *_modifier() helpers below read it for one field each; this exists for
## callers that want a different one -- Player._drive_body_yaw() asks about
## freeze_visual_yaw -- rather than growing a helper per field.
func current_config() -> MoveConfig:
	return _current.current_config() if _current != null else null

## True while the active move is steering the body toward a position it
## computed in world space -- see MoveConfig.holds_world_path for the full
## list and why each one is on it. Read off the CONFIG, not off the move's
## class, so a move that composes a ScriptedMove internally (SpringBoard's
## two steps) or holds a world-space anchor without being one at all
## (WallClimb's drift check) is covered the same way a straight ScriptedMove
## subclass is.
func current_holds_world_path() -> bool:
	var active: MoveConfig = current_config()
	return active != null and active.holds_world_path

func current_move_friction_modifier() -> float:
	if _current == null:
		return 1.0
	var active: MoveConfig = _current.current_config()
	return active.friction_modifier if active != null else 1.0

## The active move's own speed ceiling multiplier. Read by Player when it
## decides whether the body is travelling fast enough to bank energy: the
## question is "fast enough for what this move can DO", and a crouch that
## tops out at 40% of the cap can never satisfy a threshold measured against
## the standing one.
func current_move_speed_modifier() -> float:
	if _current == null:
		return 1.0
	var active: MoveConfig = _current.current_config()
	return active.speed_modifier if active != null else 1.0

func _tick_cooldowns(delta: float) -> void:
	for key in _redo_cooldowns.keys():
		var remaining: float = _redo_cooldowns[key] - delta
		if remaining <= 0.0:
			_redo_cooldowns.erase(key)
		else:
			_redo_cooldowns[key] = remaining

func _arm_cooldown(move_name: StringName, move: Move) -> void:
	# Asked of the move, not read off its config: a move may know that THIS
	# exit is not the kind its cooldown is for. See Move.redo_cooldown().
	var seconds: float = move.redo_cooldown()
	if seconds > 0.0:
		_redo_cooldowns[move_name] = seconds

# --- grounded-declaration invariant ------------------------------------------
#
# EVERY MOVE MUST CALL player.set_grounded(), in enter() or in its
# physics_update(). Scripted moves drive the body directly and never call
# move_and_slide(), so is_on_floor() reports whatever the previous move left
# behind -- which is why the flag is declared and never inferred. A move that
# forgets inherits the OUTGOING move's value, and inheriting `true` refills
# coyote time every tick in Player._tick_timers(): infinite jumps.
#
# DO NOT "simplify" this by defaulting `grounded` to false before delegating.
# WalkingMove reads its own previously-declared value -- its slide and vault
# gates are `if player.grounded`, meaning "a move_and_slide() verified this, on
# this tick or an earlier one". Defaulting every tick pins those gates shut
# forever; defaulting on entry discards AirborneMove's landing declaration on
# the very tick it is made, which defers every landing-into-slide by a tick and
# changes the feel.
#
# REPORT ONLY: push_error() fires and shows in the log, but nothing fails a
# run on it. DO NOT trust a green test suite to catch a move that forgot to
# declare grounded-ness -- read the log.
#
# The rule checked is "the ACTIVE move has declared at least once since it was
# entered", evaluated only on ticks where the move stays active:
#   * enter() counts -- SpeedVaultMove and GrabMove declare there and never
#     again, which is correct for them (their value cannot change mid-move);
#   * a move that transitions AWAY on a given tick is exempt for that tick,
#     because the incoming move's enter()/first update owns the flag from then
#     on. WalkingMove's vault branch returns without declaring and is
#     legitimately covered by SpeedVaultMove.enter().
var _entry_declarations: int = -1
## Set by start(), cleared by the next declaration check, which that check then
## skips.
##
## start() re-arms the declaration baseline, so a caller that restarts the
## manager from INSIDE a move's own physics_update() -- Arena.reset_player()
## does this on every respawn -- leaves the finishing tick unable to exceed a
## baseline captured after its only chance to declare had passed, and a
## perfectly well-behaved move gets reported.
##
## EXACTLY ONE TICK, and do not widen it: the invariant exists to catch a move
## that NEVER declares, and only the first tick after a restart is
## indistinguishable from that. The next tick tests it again.
var _restarted_this_tick: bool = false
var _reported_missing_declaration: bool = false

func start(move_name: StringName) -> void:
	assert(_moves.has(move_name), "unknown state: %s" % move_name)
	if not _moves.has(move_name):
		push_error("MoveManager.start: unknown state: %s" % move_name)
		return
	# A live manager can already be mid-move when start() is called again
	# (e.g. Arena.reset_player() restarting into Walking while the manager is
	# still in Falling). Exit the outgoing move first so moves with exit side
	# effects (SlideMove restoring the standing collision shape) do not get
	# skipped and leave the player stuck in a partial move.
	#
	# Deliberately NOT paired with _arm_cooldown(), unlike the exit() call in
	# physics_update() below: a restart is not the move choosing to leave, it
	# is being interrupted from outside, so it must not be penalised with a
	# cooldown on top of that. Whatever the interrupted move was, its next
	# life should be free to re-enter it immediately.
	if _current != null:
		_current.exit()
	# Same reasoning Player.reset_state() applies to its own per-life timers:
	# a cooldown left over from the previous life must not withhold the new
	# life's first attempt at a move. Without this, a WallRun or Grab
	# cooldown still ticking down at the moment of death or reset would
	# silently refuse the very first entry into that move on the fresh life.
	_redo_cooldowns.clear()
	_current = _moves[move_name]
	current_name = move_name
	# Snapshot BEFORE enter(), so a declaration made in enter() counts.
	_arm_declaration_check()
	_restarted_this_tick = true
	_current.enter(&"")
	_clear_stale_grounded_after_start()
	move_changed.emit(&"", move_name)
	_push_look_constraint()

func physics_update(delta: float, input: MoveInput) -> void:
	if _current == null:
		return
	_tick_cooldowns(delta)
	# Q is arbitrated HERE, not inside each move, because the owner's rule is
	# about the whole move set rather than about any one move: "Q works almost
	# everywhere -- anywhere the legs are not tied up". A move opts OUT through
	# its own allows_turn, so a move added later gets the turn for free and a
	# move that must not have it says so beside its other facts. Checked before
	# the active move runs, so the tick a turn starts is the turn's tick.
	# A stagger outranks the turn, and both are arbitrated here rather than
	# inside a move, for the same reason: they are facts about the whole move
	# set. FALL_UNCONTROLLED is exempt -- a body already dying has nothing
	# left to stumble.
	#
	# ON CONTACT, INCLUDING IN MID-AIR. Barbed wire cuts you when you touch
	# it, not when you next happen to be standing on something, so a volume
	# tall enough to cover a fence charges the vault at the moment it is
	# taken. LandingMove applies gravity while it is off the floor for
	# exactly this: the body crumples where it was hit and drops.
	#
	# What stops that becoming a trap is Player.is_stagger_immune(), armed
	# when the lockout releases. A wire volume that renews its STAGGER would
	# otherwise re-stagger on the tick the lockout ends, and the lockout
	# refuses movement input, so there would be no tick in which to walk out.
	var next: StringName = Move.KEEP
	var staggering := false
	# [13.3] What the hazard costs, read off the spec that put the status
	# there. A dial rather than a constant: [ME:CONFIRMED] wire is 35 in the
	# original and does not vary with difficulty, but a laser is the same
	# volume with a different number, and a trip hazard is the same volume with
	# no number at all.
	#
	# READ HERE, not after the transition: the status is removed once the
	# transition commits, and by then there is nothing left to ask.
	var stagger_damage: float = 0.0
	var knocking_down: bool = player != null and player.statuses.has(Status.Effect.KNOCKDOWN) \
			and current_name != Move.FALL_UNCONTROLLED and current_name != Move.LAY_ON_GROUND \
			and _moves.has(Move.LAY_ON_GROUND)
	if player != null and player.statuses.has(Status.Effect.STAGGER) \
			and current_name != Move.FALL_UNCONTROLLED and current_name != Move.LANDING:
		# EATEN, NOT QUEUED, while immune. Spending it here is what the
		# window means: the hit landed and the body shrugged it off. Leaving
		# it in the list would fire it the instant the window closed, which
		# is the chain the window exists to break.
		if player.is_stagger_immune():
			player.statuses.remove(Status.Effect.STAGGER)
		elif current_name == Move.LAY_ON_GROUND:
			# ALREADY DOWN. It costs what it costs and changes nothing else:
			# a lockout on the feet means nothing to a body on its back.
			var cost: float = player.statuses.amount_of(Status.Effect.STAGGER)
			player.statuses.remove(Status.Effect.STAGGER)
			if cost > 0.0:
				player.take_damage(cost, Health.Cause.HAZARD)
		elif knocking_down:
			# Going down with it: the knock-down below takes the body, and the
			# hit's tint rides LayOnGroundMove's. Charged once that commits.
			staggering = true
			stagger_damage = player.statuses.amount_of(Status.Effect.STAGGER)
			player.pending_stagger_tint = player.statuses.tint_of(Status.Effect.STAGGER)
		else:
			# NO LOCKOUT. [ME:CONFIRMED] unpacked, the original forces none on a
			# cut: the hit hurts, flashes and empties the speed budget, and the
			# body keeps its feet. See Player.take_hazard_hit().
			player.take_hazard_hit(player.statuses.amount_of(Status.Effect.STAGGER),
				player.statuses.tint_of(Status.Effect.STAGGER))
			player.statuses.remove(Status.Effect.STAGGER)
			# Holding on to something, it lets go. See MoveConfig.hit_knocks_off.
			var holding: MoveConfig = _current.current_config()
			if holding != null and holding.hit_knocks_off:
				next = Move.FALLING
	# A KNOCK-DOWN OUTRANKS A STAGGER. Both at once is one body going down --
	# the original's falling lift pairs a CauseDamage with its TdFallOnBack --
	# so the stagger is still spent and still charged, below, and only where
	# the body ends up changes. Its tint stays pending for LayOnGroundMove.
	var knocked_down := false
	if knocking_down:
		knocked_down = true
		next = Move.LAY_ON_GROUND
	if next == Move.KEEP:
		next = _turn_requested(input)
	if next == Move.KEEP:
		next = _current.physics_update(delta, input)
	if next == Move.KEEP or next == current_name:
		_check_declared_grounded()
		_push_look_constraint()
		return
	# A move that asks for a target still cooling down simply stays put. Done
	# here rather than in each caller so no move can forget, and so the
	# refusal never silently drops the tick's own transition INTENT into some
	# third state.
	if not can_enter(next):
		_check_declared_grounded()
		_push_look_constraint()
		return
	assert(_moves.has(next), "transition to unknown state: %s" % next)
	if not _moves.has(next):
		push_error("MoveManager.physics_update: transition to unknown state: %s" % next)
		# The manager stays on the current move, so it is still the one whose
		# declaration matters this tick.
		_check_declared_grounded()
		_push_look_constraint()
		return
	var from := current_name
	var leaving: MoveConfig = _current.current_config()
	_current.exit()
	_arm_cooldown(from, _current)
	# See MoveConfig.fall_counts_from_exit.
	if player != null and leaving != null and leaving.fall_counts_from_exit:
		player.fall_tracker.reset(player.global_position.y)
	_current = _moves[next]
	current_name = next
	_arm_declaration_check()
	_current.enter(from)
	# SPENT ONLY ONCE THE TRANSITION HAS COMMITTED. Removing it where the
	# stagger was chosen would let a redo cooldown on LANDING refuse the
	# transition after the status had already been consumed, so the stagger
	# would vanish without ever having staggered anyone.
	if knocked_down:
		player.statuses.remove(Status.Effect.KNOCKDOWN)
	# The flight a back landing was armed for ended some other way.
	if player != null and player.pending_back_landing \
			and not (_current is AirborneMove) and next != Move.LAY_ON_GROUND:
		player.pending_back_landing = false
	if staggering:
		player.statuses.remove(Status.Effect.STAGGER)
		# Charged with the same commitment as the status is spent: a stagger
		# that was refused a transition never happened, and must not bill for it.
		if stagger_damage > 0.0:
			player.take_damage(stagger_damage, Health.Cause.HAZARD)
	move_changed.emit(from, next)
	_push_look_constraint()

## Fail-safe half only, no reporting: start() can be the FIRST tick of a
## move's life, so its own first physics_update() has not run yet -- a move
## whose enter() legitimately defers declaring (WalkingMove is exactly this
## shape) has not yet violated the invariant, and _check_declared_grounded()'s
## "did not declare" report would be a false positive here.
##
## But Player._physics_process() calls _tick_timers() BEFORE
## move_manager.physics_update() every frame, and _tick_timers() reads
## `grounded` to refill coyote time. Without this, a restart whose new move
## does not declare in enter() would leave whatever `grounded` held a moment
## earlier -- the OUTGOING move's value, or older still -- readable by
## _tick_timers() for one whole tick before the new move's first
## physics_update() ever gets a chance to correct it. Real play was covered
## only by a coincidence of caller order (Arena.reset_player() clears
## `grounded` via reset_state() before calling start()); this closes the gap
## in start() itself so the guarantee no longer depends on that order.
##
## Mirrors the fail-safe half of _check_declared_grounded() exactly -- a move
## that DID declare in enter() (SpeedVaultMove, GrabMove) is untouched,
## since the count comparison below then differs.
func _clear_stale_grounded_after_start() -> void:
	if _entry_declarations < 0:
		return
	if _declaration_count() > _entry_declarations:
		return
	_current.player.clear_grounded_undeclared()

## Player's declaration counter, or -1 when there is no player to read it from
## (tests/test_move_manager.gd drives this manager with bare stub moves that
## have none). -1 disables the invariant for that manager entirely.
func _declaration_count() -> int:
	if _current == null or _current.player == null:
		return -1
	return _current.player.grounded_declarations

func _arm_declaration_check() -> void:
	_entry_declarations = _declaration_count()
	_reported_missing_declaration = false

## See the invariant note at the top of this file.
func _check_declared_grounded() -> void:
	if _restarted_this_tick:
		_restarted_this_tick = false
		return
	if _entry_declarations < 0:
		return
	if _declaration_count() > _entry_declarations:
		return

	# Fail-safe first, and every tick it keeps not declaring: whatever the
	# previous move left in `grounded` must not be believed. false is the safe
	# value — it withholds coyote time rather than granting it.
	_current.player.clear_grounded_undeclared()

	# Reported once per entry, not once per tick: a move that never declares
	# never will, and 60 identical lines a second buries the one that matters.
	if _reported_missing_declaration:
		return
	_reported_missing_declaration = true
	var message := "state %s did not declare grounded-ness: every state must call player.set_grounded() in enter() or in its physics_update()" % current_name
	assert(false, message)
	push_error("MoveManager: " + message)

## Pushes the ACTIVE move's look clamp to the camera every tick. The original
## makes this per-move data (MinLookConstraint / MaxLookConstraint /
## bConstrainLook, see 06 §6.2 and 04 §4.1), and it is an INPUT constraint,
## not an animation effect -- "the view swings to face along the wall" is this
## and nothing else. Pushed every tick rather than only on transition because
## it reads through Move.current_config(), an overridable hook for a move
## whose own config can legitimately change mid-move without a state
## transition. No move overrides it today, but the every-tick read is what
## makes the hook actually usable rather than merely declared -- a future
## override would otherwise need to also hunt down and fix a transition-only
## call site.
func _push_look_constraint() -> void:
	if _current == null or _current.player == null:
		return
	var rig = _current.player.camera_rig
	if rig == null:
		return
	var active: MoveConfig = _current.current_config()
	# A slide's stand-up keeps the slide's clamp after SlideMove has gone --
	# see Player.residual_look_config(). Applied over current_config() rather
	# than instead of it, so a move that composes phases still picks its own.
	var residual: MoveConfig = _current.player.residual_look_config()
	if residual != null:
		active = residual
	# Pushed here, every tick, for the same reason the look constraint is:
	# no move can forget to hand the shoulder back on the way out.
	rig.set_shoulder_centred(active != null and active.centre_shoulder)
	if active == null or not active.constrain_look:
		rig.clear_look_constraint()
		return
	if active.third_person_frees_look and rig.in_third_person():
		rig.clear_look_constraint()
		return
	var low: Vector3 = active.min_look_constraint
	var high: Vector3 = active.max_look_constraint
	# A one-sided yaw fan is declared for a wall on the LEFT and flipped for one
	# on the right. See MoveConfig.mirror_yaw_by_wall_side: the original ships
	# two moves whose only difference is this mirroring, and this project has
	# one.
	if active.mirror_yaw_by_wall_side and _current.player.wall_side > 0:
		var flipped_low: float = -high.y
		var flipped_high: float = -low.y
		low.y = flipped_low
		high.y = flipped_high
	# A move may name its own yaw width for this tick -- see
	# Move.look_yaw_half_span(). Symmetric, so it cannot be combined with the
	# one-sided fans above; none of the moves that answer have one.
	var half_span: float = _current.look_yaw_half_span()
	if not is_nan(half_span):
		low.y = -absf(half_span)
		high.y = absf(half_span)
	# See Move.third_person_pitch_limits(). The relaxing floor is pitch too, so
	# it goes with the band.
	var pitch_relaxes: bool = active.pitch_relaxes_with_yaw
	if rig.in_third_person():
		var band: Vector2 = _current.third_person_pitch_limits()
		if not is_nan(band.x):
			low.x = band.x
			high.x = band.y
			pitch_relaxes = false
	rig.set_look_constraint(low, high, \
		active.absolute_yaw_constraint, pitch_relaxes, \
		active.pitch_min_turned_away, active.pitch_relax_yaw_threshold, \
		active.pitch_recover_speed)

## TURN_180 if Q was pressed and the active move will allow it, KEEP otherwise.
func _turn_requested(input: MoveInput) -> StringName:
	if not input.turn_pressed or current_name == Move.TURN_180 or current_name == Move.TURN_180_IN_AIR:
		return Move.KEEP
	var active: MoveConfig = _current.current_config()
	if active == null or not active.allows_turn:
		# Where the body cannot turn, Q may still swing the view -- see
		# MoveConfig.q_flicks_view. No transition either way, and so no turn's
		# cooldown to wait out.
		if _current.can_flick_view() and player != null and player.camera_rig != null:
			player.camera_rig.flick_half_turn()
		return Move.KEEP
	# A flight off no wall turns as a passenger -- see Turn180InAirMove. With
	# a wall to turn on, a climb's or a jump's alike, it is Turn180's wall turn.
	var turn: StringName = Move.TURN_180
	var flying: bool = _current is AirborneMove and player != null and not player.grounded
	if flying and Turn180Move.find_wall(player)["normal"] == Vector3.ZERO:
		turn = Move.TURN_180_IN_AIR
	if not _moves.has(turn) or not can_enter(turn):
		return Move.KEEP
	return turn
