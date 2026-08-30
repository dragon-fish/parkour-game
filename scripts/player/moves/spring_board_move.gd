class_name SpringBoardMove
extends AirborneMove

# The original's TdMove_SpringBoard, faithful to the first game: two foot
# plants the terrain provides, a walk up to the first, two scripted steps with
# no gravity, a throw at the biggest vertical impulse in the game, and the
# rise kept by this move until the apex. See
# docs/superpowers/specs/2026-08-31-spring-board-design.md for the
# measurements every number here comes from.
#
# FOUR PHASES IN ONE MOVE, and the first and last are the reason it is one:
# [ME:CONFIRMED] a recording of the original holds SpringBoarding from the
# jump press, through 0.1-0.2 s of ordinary walking up to the first face,
# through the 0.4 s climb, and on through the whole 0.6 s rise -- Falling only
# takes over at the apex. Handing the rise to JumpMove instead would let it
# coil, which the original cannot (Coil enters from Jump alone), and would
# run Jump's probes rather than the three the CDO gives this move.
#
# Extends AirborneMove for the rise's air physics and probes, and COMPOSES a
# ScriptedMove for the two steps -- the same shape LadderMove gives its top
# exit, because GDScript has no second base class.

enum Phase { APPROACH, STEP_1, STEP_2, RISE }

## The step being walked, and the arc it is on. A child so its lifetime is
## this move's; see LadderMove._top_exit.
var _hop: ScriptedMove = ScriptedMove.new()
var _phase: Phase = Phase.APPROACH
var _plant_1: Vector3 = Vector3.ZERO
var _plant_2: Vector3 = Vector3.ZERO
## Horizontal speed at entry -- what the throw is priced against. Read
## BEFORE anything zeroes velocity (the steps do), the same trap
## BalanceMove.enter() documents.
var _entry_speed: float = 0.0
var _approach_time: float = 0.0
var _launched: bool = false
var _aborted: bool = false

func _ready() -> void:
	super._ready()
	add_child(_hop)

func enter(_previous: StringName) -> void:
	var board: Dictionary = player.pending_spring_board
	player.pending_spring_board = {}
	_aborted = board.is_empty() or not bool(board.get("valid", false))
	_launched = false
	# ABOVE THE ABORT, the way LadderMove resets _top_exiting above its own:
	# an interrupted move left mid-step keeps whatever phase it died in, and
	# is_stepping()/scripted_duration() would then answer for a move that is
	# not running -- which is exactly what CharacterAnimator routes on.
	_phase = Phase.APPROACH
	if _aborted:
		return
	_plant_1 = board["plant_1"]
	_plant_2 = board["plant_2"]
	_entry_speed = player.horizontal_speed()
	_approach_time = 0.0
	_hop.player = player
	# The feet are on things for the whole of the walk and the steps:
	# declared, never inferred, and set again every tick below.
	player.set_grounded(true)
	# NO INPUT LOCK. [ME:CONFIRMED] ControllerState = PlayerWalking and no
	# bConstrainLook: the view stays live for the whole climb, which is what
	# lets a fast mouse throw the body backwards. A lock would substitute an
	# empty MoveInput and freeze the look with it, putting that behaviour out
	# of reach. Movement keys are ignored by construction instead -- the
	# approach and the steps never read input.move.
	# The model faces along the plants for the steps; the capsule keeps
	# following the view, which is what the throw reads.
	var along: Vector3 = _plant_2 - _plant_1
	along.y = 0.0
	if along.length_squared() > 0.0001:
		along = along.normalized()
		player.pin_visual_yaw(atan2(-along.x, -along.z))
	# The arcs carry the whole climb; a clip lifting its own hips on top
	# would double it -- the gate every scripted carry arms.
	player.set_clip_lift_cancelled(true)

func exit() -> void:
	player.set_clip_lift_cancelled(false)

func physics_update(delta: float, input: MoveInput) -> StringName:
	if _aborted:
		player.set_grounded(player.is_on_floor())
		return WALKING
	match _phase:
		Phase.APPROACH:
			return _approach(delta)
		Phase.STEP_1, Phase.STEP_2:
			return _step(delta)
		Phase.RISE:
			return _rise(delta, input)
	return KEEP

## Walking on to the first plant until the feet are within plant_reach of it.
## [ME:CONFIRMED] the recording: 0.1-0.2 s of ordinary travel between the
## press and the climb. Timed out rather than waited on forever: a body that
## never gets there -- the press was taken from further out than the walk can
## cover -- is handed back to walk.
##
## DRIVEN, NOT COASTED. Movement input is ignored by construction -- neither
## this phase nor the steps read input.move -- so nothing else is pushing the
## body: a press taken from a standstill would coast nowhere and time out,
## which would make a spring board something only a run can have.
##
## AT NO LESS THAN THE THROW'S OWN FLOOR SPEED, xy_min, and never below the
## speed the body arrived with -- a run must not be braked on its way in. The
## band this phase has to cover is trigger_distance minus plant_reach, 1.6 m,
## which at that speed is 0.4 s.
##
## ENDS BY REACH ALONE, and plant_reach is sized for the tightest shape there
## is: a plant on a box sits INSIDE the face (springboard_query walks each
## plant off the lip it was found on, so 0.1-0.2 m in) while the capsule's own
## radius holds the feet 0.4 m short of that face, so the gap floors out
## around 0.5 m and plant_reach has to cover the sum.
##
## A STALL DETECTOR WAS TRIED HERE AND REMOVED -- ending the walk-up on "the
## drive stopped carrying the body" instead of on reach. DO NOT re-add it
## without first bounding the gap to the PLANT: it fires on whatever blocks
## the body, which need not be the plant at all, so a wall standing between
## the feet and a plant found past it starts the climb and arcs the body
## through the wall. The symptom it was written for -- the move entered, then
## abandoned to walking, the ordinary step-up lifting the body onto the first
## tier, which reads in play as sticking on the first step -- never reproduced
## on committed code: measured on the debug gallery, the gap settles at
## 0.4-0.5 m, inside plant_reach with room to spare.
func _approach(delta: float) -> StringName:
	_approach_time += delta
	var feet := Vector3(player.global_position.x, player.probes.feet_y(), player.global_position.z)
	var gap := Vector3(_plant_1.x - feet.x, 0.0, _plant_1.z - feet.z)
	if gap.length() <= cfg.plant_reach:
		_begin_step(_plant_1, cfg.step_time_1)
		_phase = Phase.STEP_1
		return KEEP
	if _approach_time >= cfg.approach_timeout:
		player.set_grounded(player.is_on_floor())
		return WALKING
	var toward: Vector3 = gap.normalized()
	player.ground_accelerate(toward, maxf(_entry_speed, cfg.xy_min), delta,
		player.ground_grade(toward))
	# The same downward bias WalkingMove keeps: without it is_on_floor()
	# flickers across a seam and the walk-up leaves the ground for a tick.
	player.velocity.y = -config.pawn.floor_snap_speed
	player.move_and_slide()
	player.set_grounded(true)
	return KEEP

## One step: a small arc from where the body is to `plant`, the capsule's
## centre a half height above the plant, peaking plant_arc_height above the
## higher end. ScriptedMove's one bezier, the shape every scripted carry
## shares (see its sample()).
func _begin_step(plant: Vector3, duration: float) -> void:
	var from: Vector3 = player.global_position
	var to: Vector3 = plant + Vector3.UP * (player.standing_height() * 0.5)
	var apex: float = maxf(from.y, to.y) + cfg.plant_arc_height
	_hop.begin(from, to, duration, apex, cfg.plant_arc_bias)
	# NO GRAVITY THROUGH THE STEPS. [ME:CONFIRMED] PawnPhysics = PHYS_Flying:
	# the arc owns the body outright and velocity means nothing until the
	# throw writes it.
	player.velocity = Vector3.ZERO

func _step(delta: float) -> StringName:
	player.set_grounded(true)
	if not _hop.advance(delta):
		return KEEP
	if _phase == Phase.STEP_1:
		_begin_step(_plant_2, cfg.step_time_2)
		_phase = Phase.STEP_2
		return KEEP
	_launch()
	return KEEP

## The throw, the tick the second step lands.
##
## THE CAMERA'S WAY, READ NOW. [ME:CONFIRMED] the owner, twice in the
## original: in at an angle, out at that angle; turn the view right round
## during the steps and the body is thrown backwards. The capsule's yaw IS the
## view's, in both of this project's views, so it is read off the capsule.
## Priced against the speed the body ARRIVED with: [ME:CONFIRMED] a 5.75 m/s
## walk left at 4.5, and a standing start left at 4.0 -- xy_add and xy_min.
func _launch() -> void:
	var dir: Vector3 = -player.global_transform.basis.z
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		dir = _plant_2 - _plant_1
		dir.y = 0.0
	dir = dir.normalized()
	var xy: float = maxf(_entry_speed + cfg.xy_add, cfg.xy_min)
	player.velocity = dir * xy + Vector3.UP * cfg.jump_z
	# REPINNED TO THE THROW, because freeze_visual_yaw holds this move's pin
	# for the whole rise: left facing along the plants the model flies 0.6 s
	# sideways and snaps round the moment Falling takes over. The model
	# follows displacement, and from this tick the displacement is the
	# throw's.
	player.pin_visual_yaw(atan2(-dir.x, -dir.z))
	# The fall is measured from the launch, not from the ground the walk
	# began on: a spring board is not a 1.2 m drop before it has even risen.
	player.fall_tracker.reset(player.global_position.y)
	player.set_grounded(false)
	player.set_clip_lift_cancelled(false)
	_launched = true
	_phase = Phase.RISE

## The rise, kept here until the apex. Air physics and the config's own
## probes (grab, vault over, wall climb -- [ME:CONFIRMED] the three
## bCheckFor* on the CDO), and Falling the tick the vertical speed is gone
## ([ME:CONFIRMED] bCheckExitToFalling). No coil: that is Jump's alone.
func _rise(delta: float, input: MoveInput) -> StringName:
	apply_air_physics(delta, player.wish_direction(input))
	var probed := probe_transition()
	if probed != KEEP:
		player.set_grounded(false)
		return probed
	if player.velocity.y <= 0.0:
		return advance_and_hand_off(FALLING)
	return settle_landing(delta)

## True through the two scripted steps. Read by CharacterAnimator and tests.
func is_stepping() -> bool:
	return _phase == Phase.STEP_1 or _phase == Phase.STEP_2

## True once the throw has been written. Read by tests.
func has_launched() -> bool:
	return _launched

## The scripted-fit hook (CharacterAnimator._scripted_fit): the whole climb,
## both steps, is one window for the clip; 0 outside the steps.
func scripted_duration() -> float:
	return cfg.step_time_1 + cfg.step_time_2 if is_stepping() else 0.0

## For the debug HUD's scripted row and the animation lab, which draw the
## real curve rather than a picture of a second implementation.
func path_debug() -> Dictionary:
	return _hop.path_debug() if is_stepping() else {}

func sample(t: float) -> Vector3:
	return _hop.sample(t)
