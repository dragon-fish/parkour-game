class_name GrabJumpConfig
extends MoveConfig

# The original's TdMove_GrabJump, CDO and DefaultPawnMovement.ini
# [TdGame.TdMove_GrabJump]. [ME:CONFIRMED decompile] Metric. What each value
# does is in GrabJumpMove.

## GrabJumpOffZHeight, 160 uu: the jump's apex above the hang, or the headroom.
@export var grab_jump_off_z_height: float = 1.6
## GrabJumpPushAwayMaxSpeed 400 / MinSpeed 200 uu/s: the push along the view,
## blended by how squarely the view faces away from the wall.
@export var grab_jump_push_away_max_speed: float = 4.0
@export var grab_jump_push_away_min_speed: float = 2.0
## GrabAllowedJumpAngle, 45 degrees: the view must be turned at least this far
## from the wall.
@export var grab_allowed_jump_angle: float = 45.0

func _init() -> void:
	check_for_grab = true
	check_for_vault_over = true
