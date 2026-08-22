class_name FallUncontrolledMove
extends AirborneMove

# ControllerState = PlayerDying. Input is gone the moment this state is
# entered -- in the air, not on impact -- which is why a roll cannot save it.
# Entering is one-way: regaining height does not hand control back, because
# the original treats the outcome as already settled.

## ControllerState = PlayerDying, expressed where the original expresses it.
##
## The CDO for this move is three lines long -- PawnPhysics, ControllerState,
## bCheckForSoftLanding -- and carries NO bConstrainLook. The original does not
## clamp the view here; the view stops responding because the CONTROLLER stops
## reading input, which is a different layer (spec §1, the two orthogonal state
## machines). Player's own input gate is that layer, so this is the faithful
## reading rather than inventing a look constraint the source never had.
##
## Ignoring `_input` in physics_update() below is not enough on its own: the
## camera is driven from Player._physics_process(), not from here, so without
## the gate the player could still spin the view all the way down.
func enter(_previous: StringName) -> void:
	player.lock_input()
	# ✅ THE OWNER: "the ragdoll starts the moment control is lost, not after
	# landing." Right -- this state IS losing control, and it is already fatal
	# by definition. Waiting for the touchdown meant watching a clip fall for
	# two seconds and only then going limp, which is the wrong way round.
	#
	# DeathSequence guards against starting it twice; a body it cannot be built
	# on simply never starts one.
	_ragdoll_still = 0.0
	_ragdoll_elapsed = 0.0
	if player.ragdoll != null and player.body != null 			and player.ragdoll.build(player.find_skeleton()):
		# Some direction, so a death reads as being thrown rather than folding
		# straight down. The carried velocity is mixed in because being launched
		# is what is killing them.
		var throw := Vector3(randf_range(-1.0, 1.0), randf_range(0.2, 0.8),
				randf_range(-1.0, 1.0)).normalized() * randf_range(3.0, 7.0)
		player.ragdoll.start(throw + player.velocity * 0.5, player.get_rid())
		# THE CAPSULE STOPS HERE. Its velocity is handed to the ragdoll above
		# and must not also be spent by the body -- see physics_update().
		player.velocity = Vector3.ZERO

## How slowly the hips have to be moving to count as having arrived, and how
## long to wait before deciding they never will.
const RAGDOLL_REST_SPEED := 1.2
const RAGDOLL_REST_TIME := 0.35
const RAGDOLL_TIMEOUT := 6.0

var _ragdoll_still: float = 0.0
var _ragdoll_elapsed: float = 0.0

func physics_update(delta: float, _input: MoveInput) -> StringName:
	# ⚠️ THE RAGDOLL OWNS THE BODY, and the capsule stops entirely.
	#
	# ✅ The owner, and it explains two other things they reported: "once the
	# ragdoll is running the capsule is meaningless, surely the ragdoll's
	# position is the authority? Otherwise the timing does not line up and the
	# blackout comes early or late."
	#
	# It is worse than a timing problem. The twelve bodies are children of the
	# skeleton, which hangs off this CharacterBody3D -- so every metre the
	# capsule travels TELEPORTS all of them, and the solver spends the whole
	# fall being yanked. That is "the body convulses the moment the ragdoll
	# starts". And at the end the capsule and the ragdoll are in two different
	# places, which is the launch on respawn.
	#
	# So the capsule stops: no air physics, no move_and_slide, nothing. The eye
	# still follows the body, because the head-follow reads the head BONE and
	# the ragdoll is driving it.
	if player.ragdoll != null and player.ragdoll.is_simulating():
		return _settle_ragdoll(delta)
	# No wish direction: the body falls, the player watches.
	apply_air_physics(delta, Vector3.ZERO)
	# After the physics, so the effects read THIS tick's own speed rather than
	# the speed the tick started with.
	_drive_screen_effects()
	# No probe_transition() call at all -- the config forbids every probe, and
	# not calling it makes that structural rather than a matter of trusting
	# three booleans.
	return settle_landing(delta)

## The one thing that tells the player they have already lost, while there is
## still a fall left to watch. Driven by DOWNWARD SPEED, never by elapsed time
## (spec §6): scraping over the 10 m line and dropping 40 m must not look the
## same, and speed already carries that difference for free -- ~17.9 m/s at
## the threshold against ~35.8 m/s from 40 m, at this project's measured
## gravity.
##
## ⚠️ THE WHOLE MAPPING IS PROJECT-DEFINED. Nothing in the original describes a
## screen effect during a fall (see FallUncontrolledConfig.blur_scale's own
## note). Normalised against terminal_velocity so it is bounded by
## construction and has no ceiling of its own to keep in step with; terminal
## (60 m/s, a ~112 m drop) is far past anything this arena can produce, which
## is deliberate -- the point is a GRADIENT across the falls that actually
## happen, not a wall that saturates a few metres past the line.
##
## screen_effects may be null (a hand-built player, some headless tests), so
## it is guarded the same way every other sink on Player is.
func _drive_screen_effects() -> void:
	if player.screen_effects == null:
		return
	var intensity: float = clampf(-player.velocity.y \
		/ maxf(config.pawn.terminal_velocity, 0.001), 0.0, 1.0)
	player.screen_effects.set_desaturation(intensity)
	player.screen_effects.set_blur(intensity * config.fall_uncontrolled.blur_scale)

## Clears exactly what this move set and nothing else, the same way
## LandingMove.exit() does with its own tint.
##
## ORDER, against the one thing that runs after this in the normal case:
## settle_landing() -> landing_destination() emits died_from_fall, MoveManager
## then calls this exit() SYNCHRONOUSLY on the same tick, and only after that
## does the deferred handler start DeathSequence, which sets desaturation to
## 1.0. The cutscene's hard cut is therefore written last and wins, which is
## the intended look (that cut is deliberate -- see DeathSequence). The two do
## not fight.
##
## Clearing here is still what matters for every OTHER way out of this state:
## a respawn restarting the move manager mid-fall exits this move without any
## cutscene following it, and without this the screen would stay grey and
## blurred into the next life.
func exit() -> void:
	# Released here rather than left for whatever comes next, so the gate is
	# owned by the state that closed it. DeathSequence closes it again for the
	# cutscene a frame later (died_from_fall is deferred); the one frame of
	# ordinary Walking in between is not enough to move a body that lands with
	# its horizontal speed already spent.
	player.unlock_input()
	if player.screen_effects != null:
		player.screen_effects.set_desaturation(0.0)
		player.screen_effects.set_blur(0.0)

## Waits for the ragdoll to finish arriving, then declares the death.
##
## A landing cannot be detected the usual way any more -- the capsule is not
## moving, so it never touches anything. The hips coming to rest is the same
## question asked of the thing that is actually falling.
##
## Timed out as well, because a body wedged in geometry can twitch forever and a
## death that never resolves is a game that never respawns.
func _settle_ragdoll(delta: float) -> StringName:
	# DECLARED, like every other path through every other state -- MoveManager
	# asserts on a tick that does not. False, because the capsule is tracking
	# nothing: it is frozen in mid-air while the ragdoll does the falling.
	player.set_grounded(false)
	_ragdoll_elapsed += delta
	_drive_screen_effects()
	if player.ragdoll.hips_speed() <= RAGDOLL_REST_SPEED:
		_ragdoll_still += delta
	else:
		_ragdoll_still = 0.0
	if _ragdoll_still < RAGDOLL_REST_TIME and _ragdoll_elapsed < RAGDOLL_TIMEOUT:
		return KEEP
	return landing_destination(0.0, false)

func landing_destination(_fall_height: float, _rolled: bool) -> StringName:
	# ✅ THE OWNER: "why does a third-person death always play Jump_Land and
	# THEN Death2 -- it strikes a pose before dying." Because died_from_fall is
	# DEFERRED: the cutscene, and with it set_dying(), did not start until the
	# next frame, and the body spent that frame landing like anyone else.
	#
	# Declared HERE instead, on the tick the fall is known to be fatal. The
	# sequence still owns clearing it -- see DeathSequence._release_player() --
	# so this only moves the start of it earlier, to the moment it is true.
	player.set_dying(true)
	player.died_from_fall.emit()
	return WALKING
