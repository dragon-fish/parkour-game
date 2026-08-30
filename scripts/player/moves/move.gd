class_name Move
extends Node

# One movement action -- the Godot counterpart of the original's TdMove. A
# move decides its own outgoing transitions: every question of the form "can
# I go from X to Y" has exactly one answer, and it lives in X's
# physics_update.
#
# Names live here rather than on Player. GDScript resolves class_name globals
# at parse time, so if the moves referenced Player.FALLING while Player
# referenced WalkingMove, the two scripts would form a cycle and fail to
# resolve. Keeping the names on this layer makes the dependency
# one-directional: Player -> moves -> Move.
#
# [ME:CONFIRMED 06] Names follow the original's own move classes (minus the Td
# prefix): TdMove_Walking, TdMove_Falling, TdMove_Slide, TdMove_Crouch,
# TdMove_SpeedVault, TdMove_Grab, TdMove_WallRun.

## Returned from physics_update to stay in the current move.
const KEEP: StringName = &""

const WALKING: StringName = &"Walking"
const FALLING: StringName = &"Falling"
const FALL_UNCONTROLLED: StringName = &"FallUncontrolled"
const SOFT_LANDING: StringName = &"SoftLanding"
const JUMP: StringName = &"Jump"
const LANDING: StringName = &"Landing"
const SKILL_ROLL: StringName = &"SkillRoll"
const COIL: StringName = &"Coil"
const SLIDE: StringName = &"Slide"
const CROUCH: StringName = &"Crouch"
const SPEED_VAULT: StringName = &"SpeedVault"
const INTO_GRAB: StringName = &"IntoGrab"
const GRAB: StringName = &"Grab"
const WALL_RUN: StringName = &"WallRun"
const WALL_CLIMB: StringName = &"WallClimb"
const TURN_180: StringName = &"Turn180"
const ZIPLINE: StringName = &"Zipline"
const SWING: StringName = &"Swing"
const LADDER: StringName = &"Ladder"
const BALANCE: StringName = &"Balance"
const LEDGE_WALK: StringName = &"LedgeWalk"
const SPRING_BOARD: StringName = &"SpringBoard"

## Set by Player before the manager starts. Untyped for the same reason the
## names live here: a typed reference would reintroduce the cycle.
var player

## The whole config tree, for the Pawn-wide values every move needs.
var config: MovementConfig

## This move's OWN declared parameters. Assigned by Player at registration
## from the matching MovementConfig field.
var cfg: MoveConfig

## The MoveConfig in force RIGHT NOW. Overridable so a move whose own config
## legitimately varies mid-move (without a state transition) has somewhere to
## express that. No move overrides this today; it is a retained hook, not dead
## code -- see MoveManager._push_look_constraint()'s own note on why it is
## still read every tick rather than only on transition. Everything else
## returns its own cfg.
func current_config() -> MoveConfig:
	return cfg

func enter(_previous: StringName) -> void:
	pass

## Returns the name of the move to switch to, or KEEP to stay.
func physics_update(_delta: float, _input: MoveInput) -> StringName:
	return KEEP

func exit() -> void:
	pass

# --- contact drives movement --------------------------------------------------
#
# See docs/contact-drives-movement.md. The body keeps its own ballistic motion
# until a hand or a foot actually reaches the obstacle; only then does a
# scripted interaction start moving it, and only from where the body has
# actually got to.
#
# Shared here rather than written twice because the two moves that need it --
# the reach onto a ledge and the vault -- got it wrong in exactly the same way,
# and a third will be written eventually.

## Whether the obstacle a query found is close enough to be TOUCHED.
##
## DERIVED FROM THE CAPSULE, not a tunable. `face_distance` is measured from the
## body's centre, so contact is one radius away, plus a margin small enough to
## be a rounding error and large enough that a body pressed against a surface
## does not flicker in and out of touching it.
##
## A reach_distance knob can never be tuned right, because what it is trying to
## express is "how long are the arms", and that is a function of the body's own
## size. This project has been through that twice already -- see
## IntoGrabConfig.arrive_distance and WallClimbMove.rise_speed()'s base.
const CONTACT_MARGIN := 0.08

## One physics tick, for the predictive part of touching(). Read from the engine
## rather than assumed, so a project that changes its tick rate does not
## silently change how early a vault commits.
var _tick_travel: float = 1.0 / 60.0

func _ready() -> void:
	_tick_travel = 1.0 / maxf(float(Engine.physics_ticks_per_second), 1.0)

## AGAINST A POINT CAPTURED AT COMMIT, not against a live query.
##
## The probes are built to see an interaction COMING, and stop reporting one
## from close up: vault_query() goes invalid at about a metre out, because the
## downward anchor it plants a fixed distance ahead sails past the obstacle once
## the body is nearly on it. A move that waits for contact by asking again
## simply watches the obstacle vanish and times out. Measured directly.
##
## So the commit captures where the face IS, and the approach watches the body
## reach it. Both probes return `face_point` for this.
##
## Horizontal only: the body's own arc is still carrying it up or down, and a
## vault taken at the top of a jump is touching the face just as much as one
## taken level with it.
func touching(face_point: Vector3) -> bool:
	if face_point == Vector3.ZERO:
		return false
	# Annotated, not inferred: `player` is deliberately untyped (see above), so
	# anything read through it arrives as Variant.
	var here: Vector3 = player.global_position
	# PREDICTIVE, by one tick's travel. move_and_slide() stops the capsule at
	# exactly one radius from the face, so a test that only fires AT that radius
	# is a tick too late: at 7 m/s the body covers 0.117 m in a tick and can go
	# from clear to already-stopped between two checks, so the foot visibly
	# catches before the body is lifted -- two motions instead of one.
	#
	# Adding the distance this tick will cover means the scripted motion always
	# takes over before the collision resolves, which is what makes the vault
	# read as one continuous movement rather than a stumble and a recovery.
	var speed: float = player.horizontal_speed()
	var reach: float = player.current_capsule_radius() + CONTACT_MARGIN + speed * _tick_travel
	return Vector2(face_point.x - here.x, face_point.z - here.z).length() <= reach

## Carries the body through one tick of its own ballistic motion: full gravity,
## real collisions, no scripted displacement at all.
##
## What the APPROACH phase runs. The commit has already been made and the
## animation is winding up, but nothing has been touched yet, so nothing may
## move the body except the body's own momentum. Anything else reads as the
## body being dragged through open air toward the obstacle instead of falling
## under it.
func carry_ballistically(delta: float) -> void:
	# effective_gravity(): free flight honours the player's gravity window.
	player.velocity.y -= player.effective_gravity() * delta
	player.velocity.y = maxf(player.velocity.y, -config.pawn.terminal_velocity)
	player.move_and_slide()
	player.set_grounded(player.is_on_floor())

## How long MoveManager refuses re-entry to this move after it leaves,
## seconds. The config's redo_move_time by default; a move overrides this
## when it can tell that THIS exit is not the kind the cooldown guards --
## LineWalkMove arms it for a fall off the line and not for a walk off its
## end (see there). Asked by MoveManager._arm_cooldown() after exit().
func redo_cooldown() -> float:
	return cfg.redo_move_time if cfg != null else 0.0

## Half-width of the look fan's YAW, radians, when the move wants something
## other than its config's min/max_look_constraint.y this tick, or NAN to
## take the config's. Asked by MoveManager._push_look_constraint() every tick,
## so a move may answer differently as its own state changes -- LedgeWalkMove
## widens the fan in third person, where the confirmed first-person number is
## not the one being looked through.
func look_yaw_half_span() -> float:
	return NAN
