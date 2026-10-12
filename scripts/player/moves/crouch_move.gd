class_name CrouchMove
extends PhysicsMove

# The original's TdMove_Crouch, ported. [ME:CONFIRMED decompile N5 §2]
#
# PHYS_Walking with SpeedModifier 0.2 (the walking physics caps the speed at
# GroundSpeed x 0.2), the crouched collision, and nothing else of its own: no
# automatic transitions, no falling exits -- its PrePhysics does not call the
# TdPhysicsMove one. Reached through the action table, where a held crouch key
# is MA_Crouch every tick and Walking asks Slide before Crouch; left the same
# way, MA_StopCrouch to Walking (which needs room to stand) or to Falling in
# the air.
#
# It is the one move the walking physics holds back at an edge: every action
# it is handed sets Pawn.bAvoidLedges to whether that action was MA_Crouch,
# and the ledge check clamps only Crouch's delta (PawnPhysics._check_for_ledges).

func _init() -> void:
	super._init()
	use_custom_collision = true

func is_ported() -> bool:
	return true

## TdMove_Crouch.CanDoMove: anything but a crouch. It does NOT ask the base, so
## there is no RedoMoveTime and no dying check. A level that forbids crouching
## is this project's and is still asked -- except where the body cannot stand
## up at all, which is the geometry and not a choice.
func can_do_move() -> bool:
	if player.move_manager.current_name == CROUCH:
		return false
	if player.statuses != null and player.statuses.is_move_blocked(CROUCH) and player.has_headroom():
		return false
	return true

## TdMove_Crouch.StartMove: SetPhysics(PHYS_Walking) again, whatever the
## physics was -- a crouch started in the air walks.
func enter(_previous: StringName) -> void:
	player.set_physics(PHYS_WALKING)

## TdMove_Crouch.StopMove: ledge avoidance back on.
func exit() -> void:
	player.avoid_ledges = true

## TdMove_Crouch.HandleMoveAction: Pawn.bAvoidLedges = (Action == MA_Crouch).
## A held key keeps it on; the frame a jump arrives on top of the crouch it is
## off, for that frame's physics.
func handle_move_action(action: int) -> void:
	player.avoid_ledges = action == MA_CROUCH

## Crouch's CheckAutoMoves: every switch is clear, so all that runs is the
## base's reset of the ledge result while moving.
func check_auto_moves() -> void:
	var v: Vector3 = player.velocity
	if absf(v.x) < 1e-6 and absf(v.y) < 1e-6 and absf(v.z) < 1e-6:
		return
	player.move_ledge_result = 0

## TdMove_Crouch PrePhysics (0x011fe160): bCanUnCrouch only. It does not call
## the TdPhysicsMove PrePhysics, so no precise location and no falling exits.
func pre_physics(_delta: float) -> void:
	player.can_uncrouch = player.test_can_uncrouch()
