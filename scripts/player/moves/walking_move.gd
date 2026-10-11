class_name WalkingMove
extends PhysicsMove

# The original's TdMove_Walking, ported. [ME:CONFIRMED decompile] A
# TdPhysicsMove with PHYS_Walking, the PlayerWalking controller state and not
# one automatic-transition switch: every way out of walking is an action
# (MoveManager's table) or the physics (walking off an edge, a chute under
# the feet). The acceleration is PlayerWalking's (Player.player_walking_move()).

func _init() -> void:
	super._init()
	controller_state = CS_PLAYER_WALKING

func is_ported() -> bool:
	return true

## TdMove_Walking.CanDoMove: from a crouch or a slide, only with room to stand
## -- a box the default collider's size swept up by 2 H - 122 uu.
func can_do_move() -> bool:
	if not td_can_do_move():
		return false
	var state: StringName = player.move_manager.current_name
	if state == CROUCH or state == SLIDE:
		var start: Vector3 = player.collision_center()
		var end: Vector3 = start + Vector3.UP * (2.0 * player.default_collision_half_height() - 122.0 * UU)
		if player.phys.trace_blocked(end, start, player.collision_extent()):
			return false
	return true

## TdMove_Walking.StartMove: [ME:CONFIRMED decompile 15.4] clears the
## wall-run-jump's ledge ban. Every move that ends by setting Walking passes
## through here, which is what makes "touch the ground" end it.
func enter(_previous: StringName) -> void:
	player.illegal_ledge_timer = 0.0

## The level's interest points a walking body steps onto: a ladder's front, a
## ledge, a beam. The original enters these through the levels' own volumes;
## this project's InterestLines stand in for them and are asked here, before
## the physics, the slot the original's automatic transitions use.
func check_auto_moves() -> void:
	if not player.grounded:
		return
	var manager = player.move_manager
	if manager.can_enter(LADDER):
		var rail: InterestLine = player.nearest_interest_line(InterestLine.Kind.LADDER)
		if rail != null and LadderMove.catch_gate(player, rail):
			manager.set_move(LADDER)
			return
	if manager.can_enter(LEDGE_WALK):
		var ledge: InterestLine = player.nearest_interest_line(InterestLine.Kind.LEDGE_WALK)
		if ledge != null and LedgeWalkMove.catch_gate(player, ledge, config.ledge_walk.foot_snap_height):
			manager.set_move(LEDGE_WALK)
			return
	if manager.can_enter(BALANCE):
		var beam: InterestLine = player.nearest_interest_line(InterestLine.Kind.BALANCE)
		if beam != null and BalanceMove.catch_gate(player, beam, config.balance.foot_snap_height):
			manager.set_move(BALANCE)

## The playback-rate hook (CharacterAnimator._drive_speed): while the body is
## stepping round on the spot, the Turn90 clip plays at
## PawnConfig.turn_in_place_clip_scale; 0 otherwise leaves the speed match
## alone.
func clip_time_scale() -> float:
	return player.turn_in_place_clip_scale()
