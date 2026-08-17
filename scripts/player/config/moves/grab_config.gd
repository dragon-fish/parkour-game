class_name GrabConfig
extends MoveConfig

# The Godot counterpart of the original's TdMove_Grab (the ledge hang/mantle
# move).

## Lowest and highest ledge tops, measured from the player's feet, that can be
## grabbed. The lower bound keeps low ledges going through Vault instead.
@export var ledge_min_height: float = 1.4
@export var ledge_max_height: float = 2.8
## How far ahead of the body a ledge can be reached.
@export var ledge_reach: float = 1.0
## How long the mantle motion takes.
@export var mantle_duration: float = 0.42
## Horizontal speed granted on top after a mantle.
@export var mantle_exit_speed: float = 2.0
## How far past the ledge edge the mantle's landing point sits, so the body
## ends up standing ON the platform rather than teetering right at its lip.
## Mirrors SpeedVaultConfig.vault_exit_forward's role for VaultState.
@export var mantle_forward_offset: float = 0.4
## Peak height of the vertical arc ScriptedMove.advance() adds over the
## straight line from the hang position to the mantle's landing point, so the
## body reads as climbing up and over the lip instead of clipping through it.
## Mirrors SpeedVaultConfig.vault_arc_height's role for VaultState -- see
## ScriptedMove's own note on why the arc is a per-call value rather than a
## shared literal.
@export var mantle_arc_height: float = 0.3
