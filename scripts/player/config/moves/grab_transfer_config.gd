class_name GrabTransferConfig
extends MoveConfig

# The original's TdMove_GrabTransfer, CDO and DefaultPawnMovement.ini
# [TdGame.TdMove_GrabTransfer]. [ME:CONFIRMED decompile] Metric.

## Allowed2DTransferDistance, 260 uu: how far sideways (or along the view) a
## ledge or a ladder is looked for.
@export var allowed_2d_transfer_distance: float = 2.6
## AllowedZTransferDistance, 140 uu: the most a ledge on the same wall may be
## above the one hung from.
@export var allowed_z_transfer_distance: float = 1.4

func _init() -> void:
	# This project's hook: the torus wrap waits while the move holds a world
	# position.
	holds_world_path = true
