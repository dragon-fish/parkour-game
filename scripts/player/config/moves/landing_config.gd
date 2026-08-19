class_name LandingConfig
extends MoveConfig

# The Godot counterpart of the original's TdMove_Landing: the lockout the
# player is put into after a hard landing taken without a roll. Landing
# thresholds themselves (which tier a fall falls into) still read straight
# off PawnConfig's Landing group -- this class only owns what happens once
# the hard-unrolled case has already been decided.

# ✅ MEASURED: 2.00 s, six hard landings, timed from the last Falling frame
# to the first Walking frame (2.03 / 2.00 / 2.00 / 2.00 / 2.00 / 2.02).
# Do NOT measure the Landing state's own span -- the original's HUD misreads
# the state name often enough to slice one lockout into several fragments.
@export var lockout_time: float = 2.0
## ⚠️ Project-defined. The original's knee-clutch is animation root motion;
## nothing in its data describes a screen tint.
@export var tint_color: Color = Color(0.6, 0.0, 0.0)
## ⚠️ Project-defined, same reasoning as tint_color above -- there is no
## data-side counterpart to the knee-clutch's camera dip, only the animation
## itself. Radians; see CameraRig.set_landing_pitch_offset() for how this is
## combined with the ordinary look pitch.
@export var camera_pitch_offset: float = 0.35

func _init() -> void:
	# ⚠️ Project-defined, mirroring WallRunConfig's own look lock: input is
	# refused for the whole lockout, so the view is pinned to a small forward
	# fan rather than left free to spin while the body cannot act on it.
	constrain_look = true
	min_look_constraint = Vector3(-0.2, -0.2, 0.0)
	max_look_constraint = Vector3(0.2, 0.2, 0.0)
