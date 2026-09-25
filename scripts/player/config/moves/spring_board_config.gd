class_name SpringBoardConfig
extends MoveConfig

# The original's TdMove_SpringBoard: two foot plants and the biggest vertical
# impulse in the game. Faithful to the FIRST game, on the owner's call -- not
# Catalyst's "press jump before the apex of a step-up", which turns every low
# ledge into a double jump and breaks the level language. Here the TERRAIN
# decides where a spring board is, exactly as the original does:
# [ME:CONFIRMED] the owner, in the original -- there is no trigger volume;
# two standable points, the first about 0.64 m above the feet and the second
# 0.8 to 1.48 m above the feet, about a metre apart horizontally, faced within
# 53 degrees, ARE the spring board. Two poles qualify.
# See docs/superpowers/specs/2026-08-31-spring-board-design.md.

## Vertical launch speed, m/s. [ME:CONFIRMED] SpringBoardJumpZ = 950 uu/s;
## a recording put the apex 2.82 m above the launch, 0.6 s later, which is
## exactly this at gravity 16.
@export var jump_z: float = 9.5

## Added to the horizontal speed the body arrived with, m/s -- NEGATIVE:
## the spring board buys height with speed. [ME:CONFIRMED] SpringBoardJumpXYAdd
## = -100 uu/s; the recording left a 5.75 m/s walk at 4.5 m/s.
@export var xy_add: float = -1.0

## The horizontal speed the throw never drops below, m/s. [ME:CONFIRMED]
## SpringBoardJumpXYMin = 400 uu/s; thrown with no key held the HUD read
## 14.4 km/h, which is this.
@export var xy_min: float = 4.0

## Height of the FIRST foot plant above the feet, metres. [ME:CONFIRMED]
## IntermediateFootPlantHeight = 64 uu.
@export var plant_1_height: float = 0.64

## Horizontal distance from the first plant to the second, metres.
## [ME:CONFIRMED] IntermediateFootPlantDistance = 112 uu.
@export var plant_spacing: float = 1.12

## The SECOND plant's height above the feet, metres, as a range.
## [ME:CONFIRMED] SpringBoardMinHeight = 80 uu, SpringBoardMaxHeight = 148 uu;
## the recording launched from +1.24.
@export var plant_2_min_height: float = 0.8
@export var plant_2_max_height: float = 1.48

## How long each of the two steps takes, seconds. [ME:CONFIRMED] StepTime1 =
## StepTime2 = 0.2; the recording's climb is 0.40 s from the face to launch.
@export var step_time_1: float = 0.2
@export var step_time_2: float = 0.2

## Half-width of the fan, degrees, that the line from the first plant to the
## second may lie in either side of the body's facing. [ME:CONFIRMED] the
## owner, in the original, repeatedly: 53 -- no CDO field carries it.
@export var approach_angle_deg: float = 53.0

## How far ahead of the feet the first plant may be for the jump key to mean
## a spring board, metres. A project dial: the recording shows 1.2 m accepted
## and standing against the face accepted; the far limit was never swept.
## CheckDistanceTime = 1.0 s in the CDO is unexplained and NOT this.
## 2.4 is the owner's play-tested value -- 1.2 reads as too short to aim at.
@export var trigger_distance: float = 2.4

## Spacing of the samples walked forward looking for the first plant, metres.
@export var plant_sample_step: float = 0.1

## Tolerance on plant_1_height, metres, either way. Also the least a second
## plant must stand above the first to count as a second tier at all.
@export var plant_height_tolerance: float = 0.2

## Tolerance on plant_spacing, metres, either way; three rings are tried.
@export var plant_spacing_tolerance: float = 0.3

## Radius of the sphere dropped onto each candidate point, metres. A foot,
## roughly -- wide enough to land on a pole thinner than the capsule.
@export var plant_probe_radius: float = 0.12

## How close the feet must come to the first plant, horizontally, before the
## first step begins, metres. Wider than the capsule's radius (0.4), which is
## what a box's face stops the feet at, PLUS the depth a plant sits inside
## that face: springboard_query() walks each plant off the lip it was found
## on, so a plant on a box reads 0.1-0.2 m in from the face rather than on it.
## A dial, and the generous side of one: this is the only thing that ends the
## walk-up, so a plant it cannot cover is a move entered and then abandoned.
@export var plant_reach: float = 0.8

## How long the walk to the first plant may take before the move gives up
## and hands back, seconds. The recording took 0.1 to 0.2. Sized against the
## dials rather than against that: trigger_distance at the xy_min floor is
## 2.4 / 4.0 = 0.6 s, so a timeout of 0.6 fires exactly on the boundary and
## the longest legal approach loses its move.
@export var approach_timeout: float = 1.0

## How far each step's arc peaks above the higher of its two ends, metres,
## and where the arc's control point sits (ScriptedMove.begin's control_bias:
## 0 hugs the destination, 1 rises first). Both project dials.
@export var plant_arc_height: float = 0.15
@export var plant_arc_bias: float = 0.6

func _init() -> void:
	# A hazard's hit knocks the body off. See MoveConfig.hit_knocks_off.
	hit_knocks_off = true
	# STEP_1/STEP_2 compose a ScriptedMove that writes global_position from a
	# world-space plant target, the same as Grab and SpeedVault. The gate is
	# coarse (the whole move, not just the two step phases) -- see
	# MoveConfig.holds_world_path.
	holds_world_path = true
	# [ME:CONFIRMED] bCheckForGrab, bCheckForVaultOver, bCheckForWallClimb are
	# all True on the CDO: the rise looks for all three. NOT coil: Coil enters
	# from Jump alone (05 sec 5.2), and this is not Jump.
	check_for_grab = true
	check_for_vault_over = true
	check_for_wall_climb = true
	# The interest lines, the same set Jump catches. DO NOT leave them to the
	# Falling hand-off at the apex: Stormdrain springs the player at a pipe
	# with a grabbable beam behind it, and without these the rise reached the
	# beam's ledge first and the pipe was never asked.
	check_for_zipline = true
	check_for_swing = true
	check_for_ladder = true
	check_for_ledge_walk = true
	check_for_balance = true
	# The steps are scripted: the model is pinned along the plants while the
	# capsule and the view stay the player's. [ME:CONFIRMED] ControllerState =
	# PlayerWalking and no bConstrainLook -- the view is free the whole time,
	# which is what lets a fast mouse throw the body backwards.
	freeze_visual_yaw = true
	allows_turn = false
	# [ME:INFERRED] from play: the throw's rise offers a coil the same as a
	# jump's. Read only once thrown -- the steps are the move's own.
	check_for_coil = true
