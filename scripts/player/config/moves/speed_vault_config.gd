class_name SpeedVaultConfig
extends MoveConfig

# The Godot counterpart of the original's TdMove_SpeedVault.

## Highest obstacle top, measured from the player's feet, that can be vaulted.
@export var vault_max_height: float = 1.3
## How far ahead of the body the vault probe reaches.
@export var vault_reach: float = 1.4
## Minimum horizontal speed required to vault. Vaulting from a standstill would
## turn every waist-high box into a free elevator.
@export var vault_min_speed: float = 2.5
## How long the vault motion takes. Short enough to feel snappy, long enough
## to read as a deliberate action rather than a teleport.
@export var vault_duration: float = 0.32
## Fraction of the approach speed carried out the far side.
@export var vault_speed_keep: float = 0.85
## How far past the obstacle top the vault places the player.
##
## NOTE (transit speed): vault_duration does not scale with how far the body
## actually travels, so at vault_min_speed the body crosses a long path in the
## same fixed time as a short one — around the middle of the move it can be
## travelling several times faster than the approach speed even though the
## EXIT speed (vault_speed_keep) is a net loss. Not a correctness bug (nothing
## reads a mid-vault speed), just a visible fact about this design worth
## knowing before retuning either knob.
@export var vault_exit_forward: float = 0.6
## Peak height of the vertical arc ScriptedMove.advance() adds over the
## straight line from vault start to landing, so the body reads as rising
## over the obstacle instead of clipping through it.
@export var vault_arc_height: float = 0.15
