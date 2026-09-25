class_name CoilConfig
extends MoveConfig

# The original's TdMove_Coil: tucking the legs up in mid-air. GBA_Crouch's
# fifth outlet, and the last one this project had nothing behind -- see
# walking_move.gd's own table of the key's five results.
#
# The CDO, quoted in full (05 §5.2):
#
#     CoilMinTriggerSpeed  = 100            1.0 m/s
#     CoilTime             = 0.5 s
#     HeightBoostDuration  = 0.25 s
#     TotalHeightBoost     = 60 uu          0.6 m
#     MinLookConstraint    = (-5000, ...)   pitch -27.5 deg
#     MaxLookConstraint    = (30000, ...)   pitch +165 deg
#
# 🎯 WHAT THE MOVE IS FOR, in the owner's words, and it is not what the CDO
# looks like on its own: "一般用于速通跳过更宽的沟而不触发 StepUp 减速，或者
# 关卡强制要求缩腿避免被下面的铁刺扎伤". Two different jobs, and they come
# from two different halves of the move -- the probes it does NOT run, and the
# capsule it shrinks. Both are below.

func _init() -> void:
	# LEGS BUSY: they are tucked under the chin. Same reasoning as
	# SkillRollConfig's own, and the same field carries it.
	allows_turn = false

	# A coil is how a wide gap gets crossed, and the far edge is exactly as
	# likely to be a ledge -- or a beam -- as solid ground, so unlike the
	# three probe flags below, these two stay on.
	check_for_ledge_walk = true
	check_for_balance = true

	# ⚠️ THE THREE PROBE FLAGS ARE LEFT FALSE, AND THAT IS THE MOVE.
	#
	# 11 §11.2's capability matrix gives Coil none of bCheckForGrab,
	# bCheckForVaultOver or bCheckForWallClimb. It is one of the very few
	# airborne states holding not one of the three, and the consequence is the
	# whole reason the manoeuvre is a skill rather than a freebie -- ✅ the
	# owner: "在此期间无法触发 StepUp 或 Grab，所以这个技巧有一定的风险，判断
	# 失误可能就会直接撞到障碍边缘掉下去摔死".
	#
	# It reads exactly like forgotten wiring. It is not. tests/test_coil.gd
	# holds all three down so that a later "fix" for a coil that refuses a
	# ledge in reach has to argue with a test rather than with a comment.
	#
	# 🎯 This is also the mechanism behind the speedrun use: StepUp is a row in
	# SpeedVaultConfig.variants, reached through check_for_vault_over, so a
	# coil crossing a wide gap cannot be grabbed by the vault table and slowed
	# down. Nothing special had to be written for it.

	# ✅ MinLookConstraint pitch = -5000/65536 x 360 = -27.5 degrees. The legs
	# are folded up in front of the chest, so there is nothing to look down at.
	#
	# ⚠️ THE UPPER HALF IS DELIBERATELY LEFT OPEN, against the CDO's own number.
	# MaxLookConstraint = 30000 converts to +165 degrees, which is not a
	# physically meaningful pitch ceiling -- a view cannot pass +90 without
	# being upside down, and no other move in the library asks for anything
	# like it (SkillRoll's +180 is the one that does, and a roll genuinely
	# takes the view over the top). Read here as "unconstrained above" rather
	# than transcribed literally, because transcribing it would produce a clamp
	# that never engages while looking like a measurement that does.
	constrain_look = true
	min_look_constraint = Vector3(-deg_to_rad(27.5), -PI, -PI)
	max_look_constraint = Vector3(PI, PI, PI)

## ✅ CoilTime. How long the whole manoeuvre owns the body.
##
## The legs stay tucked for ALL of it -- ✅ the owner, on the recovery half:
## "coil 会有一个最大持续时间以及后摇，在此期间无法触发 StepUp 或 Grab".
## So this is not "0.25 s of tuck plus 0.25 s of something else"; it is 0.25 s
## of drawing the legs up (see boost_duration) and then holding them there
## until the clock runs out.
@export var duration: float = 0.5

## Seconds the fade into the tuck takes, and out of it. PROJECT-DEFINED. The
## capsule shrinks at once (boost_duration eases it); the legs are allowed
## longer to arrive, so the tuck reads as drawn up rather than snapped. Read
## when the body's animation graph is built -- see Player._exit_blend_time().
@export var pose_enter_blend_time: float = 0.32
@export var pose_exit_blend_time: float = 0.18
## Seconds the tuck stays on screen after the coil hands over to a fall, so
## the pose outlasts the capsule. PROJECT-DEFINED. A landing ends it early.
@export var pose_linger_time: float = 0.2
## Seconds the tuck is held on screen after a coil's landing before it fades
## out, so the change of pose happens under the camera's landing throw rather
## than as a cut. PROJECT-DEFINED; the throw's own way down
## (CameraConfig.coil_land_pitch_kick_rise_time) is the natural match.
@export var landing_hold_time: float = 0.2

## ✅ HeightBoostDuration. How long the capsule takes to reach capsule_height.
##
## The EASE, not the hold. Read together with the owner's note above, the two
## CDO durations stop being redundant: the shrink takes 0.25 s to complete and
## then stands for the remaining 0.25 s of `duration`.
@export var boost_duration: float = 0.25

## ✅ CoilMinTriggerSpeed = 100 uu/s. Below this a crouch pressed in mid-air
## does nothing at all -- measured in-game (05 §5.2): a standing vertical jump
## with the crouch key pressed produces no move, a running one coils.
##
## This is the one row of GBA_Crouch's five-outlet table with no outlet.
@export var min_trigger_speed: float = 1.0

## How tall the capsule is while coiled.
##
## ✅ THE SAME HEIGHT AS A CROUCH, measured by the owner through ME Tweaks'
## collision-box visualiser. What differs is the ANCHOR, and that is the whole
## of the difference between the two moves:
##
##     crouch   anchored at the FEET     the head comes down, the feet stay
##     coil     anchored at the CENTRE   the feet rise and the headroom grows
##
## ✅ The owner, on finding it: "胶囊缩放不是以头为准！是以中心为准！也就是说
## 同时会增加头顶的空间". My own first reading was crown-anchored -- feet up,
## head still -- and it was wrong.
##
## ⚠️ WHICH LEAVES A DISAGREEMENT WITH THE CDO, recorded rather than papered
## over. Centre-anchored, this height lifts the feet by (1.8 - 0.9) / 2 =
## 0.45 m, where TotalHeightBoost says 0.6 m. The two cannot both be satisfied
## by one number, and the measurement is of THIS project's capsule while the
## CDO is of a body 1.76 m tall with its own crouch height -- so the ratio did
## not have to survive the port. Left as the measured relationship (coil height
## == crouch height) rather than as the CDO's absolute, because the
## relationship is what the owner actually saw. It is a dial either way: if a
## 0.6 m lift is what plays better, this becomes 0.6 and the comment becomes
## wrong, which is the correct order for those two things to happen in.
@export var capsule_height: float = 0.9
