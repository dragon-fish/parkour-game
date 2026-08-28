class_name StatusSpec
extends Resource

# One line a level author fills in on a ModifierVolume: which effect, its
# payload, and how long it lasts. Which payload field an effect reads is
# documented once, above Status.Effect.

@export var effect: Status.Effect = Status.Effect.SPEED_CAP
## Ceiling factor for SPEED_CAP. Left at 0 by every other effect.
@export var amount: float = 0.0
## InterestLine.tag for BLOCK_INTEREST_LINE. Left empty by every other effect.
@export var subject: StringName = &""
## FORCE_VIEW only.
@export var view: Status.View = Status.View.FIRST
## How long this lasts. INF means "until something removes it".
@export var seconds: float = INF
