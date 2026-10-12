class_name MoveManager
extends Node

# The original's move switching: TdPawn.SetMove, TdPawn.CanDoMove and
# TdPlayerMoveManager.HandleMoveAction, plus the per-tick native calls into the
# current move (CheckAutoMoves, PrePhysics, TickMove). [ME:CONFIRMED decompile
# 15.3, 15.4, 15.8]
#
# The moves not yet ported from the original still run their own
# physics_update(); what it returns is turned into a set_move() here, and the
# project's own whole-move-set rules (a level's stagger and knock-down, the
# per-move cooldown dictionary, the turn arbitration) keep applying to them.

## Emitted once per change of move. A chain of changes made inside one
## set_move() (Landing entering Walking from its own StartMove) is reported in
## the order the switches happened, once the outermost one has finished, so a
## listener always reads the moves' state after every enter() has run.
signal move_changed(from: StringName, to: StringName)

var current_name: StringName = &""

## Set by Player at registration, for the two questions the manager itself
## asks about statuses. Untyped for the same reason Move.player is -- see the
## note above Move's own name constants.
var player

var _current: Move = null
var _moves: Dictionary = {}

## Seconds of cooldown still owed per move name, for the moves not yet ported
## (a ported move's RedoMoveTime is its own CanDoMove). An entry only exists
## while a move is actually cooling down.
var _redo_cooldowns: Dictionary = {}

## TdPawn.bAllowMoveChange.
var allow_move_change: bool = true

## Bumped on every switch, so a caller can tell whether a call it made changed
## the move -- including from somewhere deep inside that call.
var change_serial: int = 0

var _switch_depth: int = 0
var _queued_changes: Array = []

func register(move_name: StringName, move: Move) -> void:
	_moves[move_name] = move
	move.move_name = move_name

## The registered instance for a move name, or null.
func move_for(move_name: StringName) -> Move:
	return _moves.get(move_name)

func current_move() -> Move:
	return _current

## Moves[n].CanDoMove(): false for a move this project does not have.
func can_do(move_name: StringName) -> bool:
	var move: Move = _moves.get(move_name)
	return move != null and move.can_do_move()

## TdPawn.CanDoMove: refused while move changes are off, and while a
## SetMove(..., bCheckCanDo) that failed has left PendingMovementState behind
## -- [ME:CONFIRMED decompile N4 §1.2] that refuses every move until the next
## successful SetMove. The action table asks Moves[n].CanDoMove() directly
## (can_do()); on the player's side the original asks this only for a level's
## knock-down (TdPlayerPawn.OnTdFallOnBack) and its barbed wire's stumble
## (Player.touch_barbed_wire()).
func pawn_can_do(move_name: StringName) -> bool:
	if not allow_move_change:
		return false
	if player != null and player.pending_movement_state != current_name:
		return false
	return can_do(move_name)

## False while `move_name`'s own redo_move_time is still running, or a level
## forbids it. The gate the moves not yet ported answer can_do_move() with.
func can_enter(move_name: StringName) -> bool:
	if _redo_cooldowns.has(move_name):
		return false
	if player != null and player.statuses.is_move_blocked(move_name):
		# A CROUCH THE BODY CANNOT AVOID IS NOT A TECHNIQUE. What a level
		# forbids is the player CHOOSING to duck; being unable to stand is the
		# geometry talking.
		if move_name == Move.CROUCH and not player.has_headroom():
			return true
		return false
	return true

## The active move's config, or null when there is no move.
func current_config() -> MoveConfig:
	return _current.current_config() if _current != null else null

## True while the active move is steering the body toward a position it
## computed in world space -- see MoveConfig.holds_world_path.
func current_holds_world_path() -> bool:
	var active: MoveConfig = current_config()
	return active != null and active.holds_world_path

func current_move_friction_modifier() -> float:
	var active: MoveConfig = current_config()
	return active.friction_modifier if active != null else 1.0

func current_move_speed_modifier() -> float:
	var active: MoveConfig = current_config()
	return active.speed_modifier if active != null else 1.0

func _tick_cooldowns(delta: float) -> void:
	for key in _redo_cooldowns.keys():
		var remaining: float = _redo_cooldowns[key] - delta
		if remaining <= 0.0:
			_redo_cooldowns.erase(key)
		else:
			_redo_cooldowns[key] = remaining

func _arm_cooldown(move_name: StringName, move: Move) -> void:
	var seconds: float = move.redo_cooldown()
	if seconds > 0.0:
		_redo_cooldowns[move_name] = seconds

# --- switching ------------------------------------------------------------------

## TdPawn.SetMove. [ME:CONFIRMED decompile N4 §1.2] Refused when it is already
## the move or move changes are off. PendingMovementState is written BEFORE the
## optional CanDoMove, so a refused check leaves it behind (see pawn_can_do()).
## Then: the old move stops, OldMovementState takes the old move,
## MovementState the new one, the old move's PostStopMove, the new move's
## StartMove. Re-entrant: a StartMove may set another move, and that is how
## Landing hands straight on to Walking.
func set_move(move_name: StringName, check_can_do: bool = false) -> bool:
	if move_name == current_name:
		return false
	if not allow_move_change:
		return false
	if not _moves.has(move_name):
		return false
	# TdPlayerPawn's UncontrolledFall state overrides SetMove: only Landing and
	# SoftLanding get through. [ME:CONFIRMED decompile N5 §7]
	if player != null and player.uncontrolled_fall \
			and move_name != Move.LANDING and move_name != Move.SOFT_LANDING:
		return false
	if player != null:
		player.pending_movement_state = move_name
	if check_can_do and not _moves[move_name].can_do_move():
		return false
	_switch(move_name, true)
	return true

func _switch(next: StringName, arm_cooldown: bool) -> void:
	var from: StringName = current_name
	var leaving: Move = _current
	if leaving != null:
		leaving.exit()
		leaving.end_move()
		if arm_cooldown and not leaving.is_ported():
			_arm_cooldown(from, leaving)
	if player != null:
		player.old_movement_state = from
		player.movement_state = next
		player.pending_movement_state = next
	_current = _moves[next]
	current_name = next
	change_serial += 1
	if leaving != null:
		leaving.post_exit()
	_arm_declaration_check()
	_switch_depth += 1
	_queued_changes.append([from, next])
	_current.begin_move()
	_current.enter(from)
	if player != null:
		# The flight a back landing was armed for ended some other way.
		if player.pending_back_landing and not (_current is AirborneMove) \
				and next != Move.LAY_ON_GROUND and next != Move.LANDING:
			player.pending_back_landing = false
		# The moves not yet ported still read the old speed budget. Handing
		# one the body re-derives that budget from the speed it arrives with.
		if leaving != null and leaving.is_ported() and not _current.is_ported():
			player.seed_legacy_energy()
	_switch_depth -= 1
	if _switch_depth == 0:
		var changes: Array = _queued_changes
		_queued_changes = []
		for change in changes:
			move_changed.emit(change[0], change[1])
		_push_look_constraint()

## Puts the body into `move_name` from outside the move layer: a respawn, a
## reset, the noclip toggle. The outgoing move is stopped (no cooldown -- it is
## being interrupted, not leaving), every cooldown is cleared, and the new move
## starts as if from nothing.
func start(move_name: StringName) -> void:
	assert(_moves.has(move_name), "unknown state: %s" % move_name)
	if not _moves.has(move_name):
		push_error("MoveManager.start: unknown state: %s" % move_name)
		return
	allow_move_change = true
	if player != null:
		player.uncontrolled_fall = false
		# What the outgoing move's StopMove reads as the move to come.
		player.pending_movement_state = move_name
	if _current != null:
		_current.exit()
		_current.end_move()
	# A life's cooldowns do not outlive it: the first attempt at any move on
	# the fresh life is free.
	_redo_cooldowns.clear()
	for move in _moves.values():
		(move as Move).last_stop_move_time = -10.0
	if player != null:
		player.old_movement_state = &""
		player.movement_state = move_name
		player.pending_movement_state = move_name
	_current = _moves[move_name]
	current_name = move_name
	change_serial += 1
	_arm_declaration_check()
	_restarted_this_tick = true
	_current.begin_move()
	_current.enter(&"")
	_clear_stale_grounded_after_start()
	move_changed.emit(&"", move_name)
	_push_look_constraint()

# --- actions --------------------------------------------------------------------

## TdPlayerMoveManager.HandleMoveAction. [ME:CONFIRMED decompile 15.3] The
## current move sees the action first; if it changed the move, that is the
## answer. Otherwise the table below names, for the current move and the
## action, the moves to ask in order, and the first whose CanDoMove() is true
## is set. Returns whether the move changed.
func handle_move_action(action: int) -> bool:
	if _current == null:
		return false
	var serial: int = change_serial
	var before: StringName = current_name
	_current.handle_move_action(action)
	if change_serial != serial:
		return true
	# A stumble hit again stumbles again: the row for Stumble starts the move
	# over without a SetMove. [ME:CONFIRMED decompile 15.3]
	if before == Move.STUMBLE and action == Move.MA_STUMBLE:
		if can_do(Move.STUMBLE):
			_current.begin_move()
			_current.enter(current_name)
		return false
	_stumble_in_air = false
	for candidate in _candidates(current_name, action):
		if can_do(candidate):
			# The air rows mark the stumble as taken in the air before setting it.
			if candidate == Move.STUMBLE and _stumble_in_air:
				var stumble = _moves.get(Move.STUMBLE)
				if stumble != null:
					stumble.in_air = true
			set_move(candidate)
			return change_serial != serial
	return false

## Set by _candidates() for the rows that take a stumble in the air.
var _stumble_in_air: bool = false

## The action table, one row per case of the original's switch. Moves the
## project does not have are named anyway and simply fail can_do().
func _candidates(state: StringName, action: int) -> Array:
	match state:
		Move.WALKING, Move.TURN_180, Move.VERTIGO:
			match action:
				Move.MA_JUMP:
					# FindLedgeInFrontOfPlayer before the jump candidates, so
					# SpringBoard and Jump both see this press's ledge.
					player.find_ledge_in_front_of_player()
					return [Move.DODGE_JUMP, Move.SPRING_BOARD, Move.JUMP]
				Move.MA_CROUCH:
					return [Move.SLIDE, Move.CROUCH]
				Move.MA_MELEE:
					return [Move.BARGE, Move.MELEE]
				Move.MA_SNATCH:
					return [Move.SNATCH]
				Move.MA_TURN:
					return [Move.TURN_180]
				Move.MA_STUMBLE:
					return [Move.STUMBLE]
				Move.MA_STUMBLE_HARD:
					return [Move.STUMBLE_HARD]
		Move.TURN_180_IN_AIR:
			if action == Move.MA_TURN:
				return [Move.TURN_180]
		Move.SPRING_BOARD:
			if action == Move.MA_CROUCH:
				return [Move.COIL]
		Move.INTO_GRAB, Move.JUMP, Move.WALLRUN_JUMP, Move.GRAB_JUMP, Move.SWING_JUMP, \
				Move.WALLCLIMB_180_TURN_JUMP, Move.FALLING:
			match action:
				Move.MA_CROUCH:
					return [Move.COIL]
				Move.MA_JUMP:
					return [Move.WALL_KICK]
				Move.MA_MELEE:
					return [Move.AIR_BARGE, Move.MELEE_AIR]
				Move.MA_TURN:
					return [Move.TURN_180_IN_AIR]
				Move.MA_STUMBLE, Move.MA_STUMBLE_HARD:
					_stumble_in_air = true
					return [Move.STUMBLE]
		Move.STUMBLE:
			if action == Move.MA_STUMBLE_HARD:
				return [Move.STUMBLE_HARD]
		Move.DODGE_JUMP:
			if action == Move.MA_STUMBLE:
				_stumble_in_air = true
				return [Move.STUMBLE]
		Move.SLIDE:
			match action:
				Move.MA_STOP_CROUCH:
					var slide: Move = _moves.get(Move.SLIDE)
					if slide != null and slide.can_stop_move():
						return [Move.WALKING, Move.CROUCH]
				Move.MA_MELEE:
					return [Move.MELEE_SLIDE]
		Move.RAMP_SLIDE:
			if action == Move.MA_JUMP:
				return [Move.JUMP]
		Move.CROUCH:
			match action:
				Move.MA_STOP_CROUCH:
					if player.physics == Move.PHYS_FALLING:
						return [Move.FALLING]
					return [Move.WALKING]
				Move.MA_MELEE:
					return [Move.MELEE_CROUCH]
				Move.MA_STUMBLE:
					return [Move.STUMBLE]
				Move.MA_STUMBLE_HARD:
					return [Move.STUMBLE_HARD]
		Move.MELEE_CROUCH:
			# Listed twice in the original's switch; the first case wins, and it
			# has only the stumble.
			if action == Move.MA_STUMBLE:
				return [Move.STUMBLE]
		Move.MELEE:
			match action:
				Move.MA_SNATCH:
					return [Move.SNATCH]
				Move.MA_STUMBLE:
					return [Move.STUMBLE]
				Move.MA_STUMBLE_HARD:
					return [Move.STUMBLE_HARD]
		Move.MELEE_AIR:
			match action:
				Move.MA_STUMBLE:
					return [Move.STUMBLE]
				Move.MA_STUMBLE_HARD:
					return [Move.STUMBLE_HARD]
		Move.GRAB:
			match action:
				Move.MA_JUMP:
					return [Move.GRAB_TRANSFER, Move.GRAB_PULL_UP, Move.GRAB_JUMP]
				Move.MA_CROUCH:
					# Not a candidate: the table calls the hang's RequestDropDown.
					var grab: Move = _moves.get(Move.GRAB)
					if grab != null and grab.has_method("request_drop_down"):
						grab.request_drop_down()
				Move.MA_CLIMB_UP_LONG:
					return [Move.GRAB_PULL_UP]
		Move.CLIMB:
			if action == Move.MA_JUMP:
				return [Move.GRAB_TRANSFER, Move.GRAB_JUMP]
		Move.WALL_RUN:
			match action:
				Move.MA_JUMP:
					return [Move.WALLRUN_DODGE_JUMP, Move.WALLRUN_JUMP]
				Move.MA_CLIMB_DOWN, Move.MA_CROUCH:
					return [Move.FALLING]
				Move.MA_MELEE:
					return [Move.MELEE_WALLRUN]
		Move.WALL_CLIMB:
			match action:
				Move.MA_JUMP:
					return [Move.WALLCLIMB_DODGE_JUMP]
				Move.MA_TURN:
					return [Move.WALLCLIMB_180_TURN_JUMP]
		Move.ZIPLINE:
			if action == Move.MA_CROUCH:
				return [Move.FALLING]
	return []

# --- the tick -------------------------------------------------------------------

## The Actor timers' phase, before the physics: SetMoveTimer timers, and the
## per-move cooldowns of the moves not yet ported.
func tick_timers(delta: float) -> void:
	if _current == null:
		return
	_tick_cooldowns(delta)
	_current.tick_move_timers(delta)

## ATdPawn::performPhysics. [ME:CONFIRMED decompile N4 §1.1] A ported move
## gets CheckAutoMoves, then -- the current move read again, since that may
## have switched -- PrePhysics, then the physics. A move not yet ported runs
## its own physics_update() instead, and so does one the automatic
## transitions just handed the body to: the original runs the physics after
## them whatever they chose, so the frame of the hand-over still moves.
##
## Only with physics: the actor tick calls performPhysics when Physics !=
## PHYS_None, so a body without physics -- an idle hang -- gets neither
## CheckAutoMoves nor PrePhysics. DO NOT run them anyway: Grab's PrePhysics
## probes the ledge to its right, and an idle hang near a ledge's end then
## starts the corner shimmy by itself, its root motion shutting out the stick
## that would climb. A shimmy is PHYS_Flying, so that is when it probes.
func perform_physics(delta: float, input: MoveInput) -> void:
	if _current == null:
		return
	# A hazard that hands the body to a ported move (the wire's stumble) lets
	# that move's frame run as any other's.
	if _apply_level_hazards() and not _current.is_ported():
		_check_declared_grounded()
		return
	if _current.is_ported():
		if player.physics != Move.PHYS_NONE:
			_current.check_auto_moves()
			_current.pre_physics(delta)
		if _current.is_ported():
			player.phys.perform(delta)
			_check_declared_grounded()
			return
	# bUncontrolledSlide is the walking and falling physics' finding, and
	# they do not run under a move not yet ported: that move finds its own
	# chutes.
	if player != null:
		player.uncontrolled_slide = false
	var serial: int = change_serial
	var next: StringName = _current.physics_update(delta, input)
	if change_serial != serial:
		_check_declared_grounded()
		return
	if next == Move.KEEP or next == current_name:
		_check_declared_grounded()
		_push_look_constraint()
		return
	if not can_enter(next):
		_check_declared_grounded()
		_push_look_constraint()
		return
	assert(_moves.has(next), "transition to unknown state: %s" % next)
	if not _moves.has(next):
		push_error("MoveManager: transition to unknown state: %s" % next)
		_check_declared_grounded()
		return
	if next == Move.JUMP:
		# A move not yet ported that hands to Jump has launched the body itself
		# (a wall kick, a slide jump). Jump must keep that launch, not make its
		# own: see JumpMove.enter().
		player.pending_legacy_launch = current_name
	set_move(next)

## ATdPawn::TickSpecial. [ME:CONFIRMED decompile N4 §1.1] After the physics:
## the pawn's timers, the uncontrolled slide forcing RumpSlide, and the current
## move's TickMove.
func tick_special(delta: float) -> void:
	if _current == null:
		return
	player.tick_special_timers(delta)
	if player.uncontrolled_slide and current_name != Move.RAMP_SLIDE:
		set_move(Move.RAMP_SLIDE, true)
	# The pawn's animation, with the mesh: its ends and its root motion.
	player.tick_anim_slot(delta)
	_current.tick_move(delta)
	_push_look_constraint()

## A level's stagger and knock-down -- this project's hazards, which the
## original applies through damage types this port does not have. Applied
## before the physics to every move alike. Returns true when a hazard took the
## body this tick.
##
## A STAGGER is the original's TdBarbedWireVolume: the body inside it holds
## the status, renewed by the volume. [ME:CONFIRMED decompile] Walking in is
## Touch -- the stumble, and with it PhysicsVolume.Touch's CausePainTo -- once
## per entry, and lost when its gates refuse it (Player.touch_barbed_wire()).
## Staying in is the volume's 1 s pain timer: TdPawn.TakeDamage hands the
## barbed-wire type to an empty BulletDamage, so it hurts and never stumbles.
## The pain's cadence here is the stagger immunity counted from the last hit;
## the original's VolumeTimer runs on the volume's own clock.
func _apply_level_hazards() -> bool:
	if player == null:
		return false
	var next: StringName = Move.KEEP
	var staggering := false
	var stagger_damage: float = 0.0
	var knocking_down: bool = player.statuses.has(Status.Effect.KNOCKDOWN) \
			and current_name != Move.FALL_UNCONTROLLED and current_name != Move.LAY_ON_GROUND \
			and _moves.has(Move.LAY_ON_GROUND)
	var touched: bool = player.consume_hazard_touch()
	if player.statuses.has(Status.Effect.STAGGER) and current_name != Move.FALL_UNCONTROLLED:
		var amount: float = player.statuses.amount_of(Status.Effect.STAGGER)
		var tint: Color = player.statuses.tint_of(Status.Effect.STAGGER)
		if knocking_down:
			# The blow that comes with a knock-down is the knock-down's.
			staggering = true
			stagger_damage = amount
			player.pending_stagger_tint = tint
		else:
			var before: int = change_serial
			if touched and player.touch_barbed_wire(player.hazard_touch_location):
				player.take_hazard_hit(amount, tint)
				player.statuses.remove(Status.Effect.STAGGER)
				if change_serial != before:
					return true
			elif player.is_stagger_immune():
				# EATEN, NOT QUEUED, while immune: the pain timer has not come
				# round yet. Left in the list it would fire the instant the
				# window closed whether or not the body was still inside.
				player.statuses.remove(Status.Effect.STAGGER)
			elif touched:
				# A refused touch costs nothing; the body inside is left to
				# the pain timer, which starts counting here.
				player.arm_stagger_immunity()
				player.statuses.remove(Status.Effect.STAGGER)
			elif current_name == Move.LAY_ON_GROUND:
				player.statuses.remove(Status.Effect.STAGGER)
				if amount > 0.0:
					player.take_damage(amount, Health.Cause.HAZARD)
				player.arm_stagger_immunity()
			else:
				player.take_hazard_hit(amount, tint)
				player.statuses.remove(Status.Effect.STAGGER)
	if knocking_down:
		next = Move.LAY_ON_GROUND
	if next == Move.KEEP:
		return false
	var serial: int = change_serial
	if next == Move.LAY_ON_GROUND:
		# The knock-down is SeqAct_TdFallOnBack's: TdPlayerPawn.OnTdFallOnBack
		# sets LayOnGround only if TdPawn.CanDoMove(MOVE_LayOnGround).
		if pawn_can_do(next):
			set_move(next)
	elif can_enter(next):
		set_move(next)
	if change_serial == serial:
		return false
	if knocking_down:
		player.statuses.remove(Status.Effect.KNOCKDOWN)
	if staggering:
		player.statuses.remove(Status.Effect.STAGGER)
		if stagger_damage > 0.0:
			player.take_damage(stagger_damage, Health.Cause.HAZARD)
	return true

# --- grounded-declaration invariant ------------------------------------------
#
# EVERY MOVE MUST CALL player.set_grounded(), in enter() or in its
# physics_update(); a ported move's physics declares it for it. Scripted moves
# drive the body directly and never call move_and_slide(), so is_on_floor()
# reports whatever the previous move left behind -- which is why the flag is
# declared and never inferred.
#
# REPORT ONLY: push_error() fires and shows in the log, but nothing fails a
# run on it. DO NOT trust a green test suite to catch a move that forgot to
# declare grounded-ness -- read the log.
var _entry_declarations: int = -1
## Set by start(), cleared by the next declaration check, which that check then
## skips: a restart from inside a move's own update leaves that tick unable to
## exceed a baseline captured after its only chance to declare had passed.
var _restarted_this_tick: bool = false
var _reported_missing_declaration: bool = false

func _clear_stale_grounded_after_start() -> void:
	if _entry_declarations < 0:
		return
	if _declaration_count() > _entry_declarations:
		return
	_current.player.clear_grounded_undeclared()

func _declaration_count() -> int:
	if _current == null or _current.player == null:
		return -1
	return _current.player.grounded_declarations

func _arm_declaration_check() -> void:
	_entry_declarations = _declaration_count()
	_reported_missing_declaration = false

func _check_declared_grounded() -> void:
	if _restarted_this_tick:
		_restarted_this_tick = false
		return
	if _entry_declarations < 0:
		return
	if _declaration_count() > _entry_declarations:
		return
	_current.player.clear_grounded_undeclared()
	if _reported_missing_declaration:
		return
	_reported_missing_declaration = true
	var message := "state %s did not declare grounded-ness: every state must call player.set_grounded() in enter() or in its physics_update()" % current_name
	assert(false, message)
	push_error("MoveManager: " + message)

# --- look constraint -------------------------------------------------------------

## Pushes the ACTIVE move's look clamp to the camera every tick. The original
## makes this per-move data (MinLookConstraint / MaxLookConstraint /
## bConstrainLook), and it is an INPUT constraint, not an animation effect.
func _push_look_constraint() -> void:
	if _current == null or _current.player == null:
		return
	var rig = _current.player.camera_rig
	if rig == null:
		return
	# The active move's clamp and nothing else: TdMove.StopMove ends a move's
	# constraint with the move, and the next one's governs from that frame on.
	var active: MoveConfig = _current.current_config()
	rig.set_shoulder_centred(active != null and active.centre_shoulder)
	# A ported move that turns the view the original's way owns it outright;
	# any other still has its look-at and camera reset applied.
	var owns_view: bool = _current.uses_view_rotation()
	rig.set_view_rotation_move(_current, owns_view)
	if owns_view:
		return
	if active == null or not active.constrain_look:
		rig.clear_look_constraint()
		return
	if active.third_person_frees_look and rig.in_third_person():
		rig.clear_look_constraint()
		return
	var low: Vector3 = active.min_look_constraint
	var high: Vector3 = active.max_look_constraint
	var half_span: float = _current.look_yaw_half_span()
	if not is_nan(half_span):
		low.y = -absf(half_span)
		high.y = absf(half_span)
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

# --- the turn, for the moves not yet ported ----------------------------------------

## This project's own Q arbitration, kept for the moves whose original
## HandleMoveAction(MA_Turn) has not been ported: a move opts out through
## MoveConfig.allows_turn, and a refused turn may still flick the view
## (MoveConfig.q_flicks_view).
func legacy_turn() -> void:
	if current_name == Move.TURN_180 or current_name == Move.TURN_180_IN_AIR:
		return
	var active: MoveConfig = current_config()
	if active == null or not active.allows_turn:
		if _current.can_flick_view() and player != null and player.camera_rig != null:
			player.camera_rig.flick_half_turn()
		return
	# The original's two turns, each behind its own CanDoMove: 180Turn only
	# from Walking, 180TurnInAir in the air. The turns a wall takes belong to
	# the wall moves themselves (WallRun's HandleMoveAction,
	# WallClimb180TurnJump), not to either of these.
	var flying: bool = _current is AirborneMove and player != null and not player.grounded
	var turn: StringName = Move.TURN_180_IN_AIR if flying else Move.TURN_180
	if not can_do(turn):
		return
	set_move(turn)
