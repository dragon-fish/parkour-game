class_name LedgeWalkConfig
extends MoveConfig

# The original's TdMove_LedgeWalk, CDO and DefaultPawnMovement.ini
# [TdGame.TdMove_LedgeWalk]. [ME:CONFIRMED decompile] What each value does is
# in LedgeWalkMove.

func _init() -> void:
	# This project's hook: the torus wrap waits while the move holds a world
	# position.
	holds_world_path = true
	freeze_visual_yaw = true
	centre_shoulder = true
	# SpeedModifier 0.1: the walking physics caps the 80 uu/s the move asks
	# for at 72.
	speed_modifier = 0.1
	# bConstrainLook, relative to the pawn: pitch -14000 .. 16384 (the narrow
	# kind -6000 ..), yaw +-10000.
	constrain_look = true
	min_look_constraint = Vector3(-14000.0, -10000.0, -32768.0) / UE.UNITS_PER_RADIAN
	max_look_constraint = Vector3(16384.0, 10000.0, 32768.0) / UE.UNITS_PER_RADIAN

# --- presentation ---------------------------------------------------------------
#
# This project's, not the original's (which has no third person): FIRST person
# backs onto the wall as the original does; THIRD person faces it, model and
# camera alike. See LedgeWalkMove's presentation section.

## How long the body takes to turn round on the spot when the view switches
## mid-ledge, seconds. The pack's Turn180 clip is fitted to this window by
## CharacterAnimator._scripted_fit(), and no travel happens for its duration.
## A project dial: the original never switches views.
@export var turn_time: float = 0.5

## Full width, degrees, of the yaw window the view is held inside in THIRD
## person, centred on the wall the body faces -- 175 means +-87.5. First
## person keeps the original's +-10000 above: that number is for the eye, and
## an outside camera looking past the body at the wall has room the eye never
## had.
@export var third_person_look_yaw_deg: float = 175.0

## How far the head turns toward the way the body is shuffling, degrees, in
## third person. The shoulders are pinned across the line, so a shuffling
## character otherwise stares at the wall while travelling sideways, which
## reads as being dragged. NOT in first person: the camera follows a head node
## by position, and the turn would slide the eye sideways. Kept well inside
## HeadLook's own release curve: this stacks on however far the view has
## already turned.
@export var head_turn_deg: float = 40.0

## Where the head's pitch is held, degrees (negative is down), in third
## person: a shuffling body watches its own feet on the ledge, not wherever the
## camera is pitched. Not in first person, where the eye IS the head.
@export var head_pitch_deg: float = -10.0

## Playback rate of the sidestep clips (Walk_L / Walk_R) while shuffling, a
## plain multiplier on the authored pace. Replaces CharacterAnimator's speed
## match, which fits a walking gait to the shuffle's 0.72 m/s and lands near
## 0.4x -- far too slow: a shuffle's steps are short, its cadence is not.
@export var shuffle_clip_scale: float = 1.0

## THIRD PERSON: how far the CAMERA must look off the ledge's normal, degrees,
## before W/S carry the body along the ledge the way A/D do -- so a
## third-person player can steer with the camera. Latched on the press: a view
## turned while the key is held does not change the direction. Looking straight
## at the wall and pressing W does nothing, which is what the gate is for.
## First person keeps the original's strafe-only shimmy.
@export var look_assist_angle_deg: float = 45.0
