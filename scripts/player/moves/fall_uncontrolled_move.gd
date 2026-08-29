class_name FallUncontrolledMove
extends AirborneMove

# [ME:CONFIRMED 03 §3.1] ControllerState = PlayerDying. Input is gone the
# moment this state is entered -- in the air, not on impact -- which is why a
# roll cannot save it. Entering is one-way: regaining height does not hand
# control back, because the original treats the outcome as already settled.

## [ME:CONFIRMED 03 §3.1] ControllerState = PlayerDying, expressed where the
## original expresses it: the CDO for this move is three lines long --
## PawnPhysics, ControllerState, bCheckForSoftLanding -- and carries NO
## bConstrainLook. The original does not clamp the view here; the view stops
## responding because the CONTROLLER stops reading input, which is a different
## layer (spec §1, the two orthogonal state machines). Player's own input gate
## is that layer, so this is the faithful reading rather than inventing a look
## constraint the source never had.
##
## Ignoring `_input` in physics_update() below is not enough on its own: the
## camera is driven from Player._physics_process(), not from here, so DO NOT
## remove the lock_input() call below -- without the gate the player could
## still spin the view all the way down.
func enter(_previous: StringName) -> void:
	player.lock_input()
	# FIRST PERSON ONLY, exactly as the death's own lift is: the eye is riding
	# the head bone, and LiftAir_Fall_Air holds the body horizontal with its
	# hips near the floor. From outside there is no such problem -- the camera
	# is metres away. See CameraConfig.fall_uncontrolled_eye_lift.
	if player.camera_rig != null and not player.camera_rig.in_third_person():
		player.camera_rig.set_death_lift(config.camera.fall_uncontrolled_eye_lift)
	# THE RAGDOLL STARTS THE MOMENT CONTROL IS LOST, not after landing: this
	# state IS losing control, and it is already fatal by definition. DO NOT
	# wait for the touchdown to start it -- that means watching a clip fall
	# for two seconds and only then going limp, which is the wrong way round.
	#
	# DeathSequence guards against starting it twice; a body it cannot be built
	# on simply never starts one.
	_ragdoll_elapsed = 0.0
	_ragdoll_dropping = false
	_declared = false
	_drift_from = Vector3.ZERO
	_drift_since = 0.0
	# Player.ragdoll_enabled is off by default -- see its own note. With it off
	# nothing here runs, no ragdoll is ever built, and the death plays out
	# through the animation exactly as it did before any of this: the capsule
	# falls, settle_landing() sees it land, and landing_destination() declares
	# the death.
	if player.ragdoll_enabled and player.ragdoll != null and player.body != null 			and player.ragdoll.build(player.find_skeleton()):
		# Some direction, so a death reads as being thrown rather than folding
		# straight down. The carried velocity is mixed in because being launched
		# is what is killing them.
		var throw := Vector3(randf_range(-1.0, 1.0), randf_range(0.2, 0.8),
				randf_range(-1.0, 1.0)).normalized() * randf_range(3.0, 7.0)
		player.ragdoll.start(throw + player.velocity * 0.5, player.get_rid())
		# THE CAPSULE STOPS HERE. Its velocity is handed to the ragdoll above
		# and must not also be spent by the body -- see physics_update().
		player.velocity = Vector3.ZERO

## WHAT COUNTS AS HAVING ARRIVED, per the owner's rule: the vertical speed
## suddenly zeroes or reverses, or the hips have not moved 0.5 m in a while,
## or it has been falling for more than six seconds.
##
## The first is the impact and is what actually fires: a body that was dropping
## and is suddenly not has hit something. The other two are for the cases that
## never produce one -- sliding down a slope, wedging in geometry, falling
## forever into the void.
const RAGDOLL_FALLING_SPEED := 4.0
const RAGDOLL_IMPACT_SPEED := 0.5
const RAGDOLL_DRIFT_WINDOW := 1.0
const RAGDOLL_DRIFT_DISTANCE := 0.5
const RAGDOLL_TIMEOUT := 6.0

var _ragdoll_elapsed: float = 0.0
## True once the hips have been dropping fast enough for a stop to mean
## something. Without it a ragdoll that starts near rest is "impacted" on its
## first tick.
var _ragdoll_dropping: bool = false
## Where the hips were when the current drift window opened, and when.
var _drift_from: Vector3 = Vector3.ZERO
var _drift_since: float = 0.0
## Emitted exactly once. FALLUNCONTROLLED IS A TERMINAL STATE: DO NOT return
## WALKING from here on its own -- with the capsule frozen mid-air that falls
## straight back into another uncontrolled fall, declares another death, and
## cycles forever.
var _declared: bool = false

func physics_update(delta: float, _input: MoveInput) -> StringName:
	# THE RAGDOLL OWNS THE BODY, and the capsule stops entirely: DO NOT run air
	# physics or move_and_slide() once the ragdoll is simulating -- the
	# ragdoll's position is the authority once it is running.
	#
	# The ragdoll's twelve bodies are children of the skeleton, which hangs off
	# this CharacterBody3D -- so every metre the capsule travels TELEPORTS all
	# of them, and the solver spends the whole fall being yanked, which reads
	# as the body convulsing the moment the ragdoll starts. Left running, the
	# capsule and the ragdoll also end up in two different places, which
	# launches the body on respawn.
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
## THE WHOLE MAPPING IS PROJECT-DEFINED. Nothing in the original describes a
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
	# THE RAGDOLL'S SPEED, NOT THE CAPSULE'S, once one is running: the capsule
	# is frozen at zero the whole way down (see physics_update), so DO NOT read
	# the capsule's velocity here -- that leaves the screen clear through the
	# entire fall.
	var falling: float = -player.velocity.y
	if player.ragdoll != null and player.ragdoll.is_simulating():
		falling = player.ragdoll.hips_fall_speed()
	var intensity: float = clampf(falling / maxf(config.pawn.terminal_velocity, 0.001), 0.0, 1.0)
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
	# WHOEVER STARTED IT OWNS STOPPING IT, and this state is the only thing
	# that starts one: DO NOT leave the ragdoll running on exit. Debug noclip
	# can force the state machine straight to Walking with no respawn behind
	# it, and without this the ragdoll would go on simulating underneath a
	# player flying around. Every other way out -- the respawn, a reset, the
	# death sequence -- already stops it; idempotent on a ragdoll that is not
	# running.
	if player.ragdoll != null:
		player.ragdoll.stop()
	# The lift goes back with everything else this state borrowed. DeathSequence
	# sets its own, larger one on the tick after this if the fall was fatal.
	if player.camera_rig != null:
		player.camera_rig.set_death_lift(0.0)
	# And the death with it -- BUT ONLY IF THIS FALL DID NOT DECLARE ONE. DO NOT
	# clear it unconditionally: a FATAL landing exits through here too, where the
	# fall declares the death and returns WALKING, MoveManager calls exit() on
	# the way out, and clearing the flag here before CharacterAnimator ever asks
	# would silently drop the Jump_Land-on-landing pose the absorb it gates is
	# armed for.
	#
	# Leaving without having declared anything -- which is what noclip is --
	# still has to clear it, or the body walks around playing its own death
	# clip. That is the only case this line serves.
	if not _declared:
		player.set_dying(false)
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
	if _declared:
		# TERMINAL, and the screen is no longer ours: DO NOT keep calling
		# _drive_screen_effects() once _declared is true. This state HOLDS after
		# declaring the death instead of handing off, so left running it computes
		# an intensity from a hips speed that is zero once the body has landed and
		# overwrites the desaturation DeathSequence just set to 1 -- two drivers,
		# one channel.
		#
		# Nothing follows an uncontrolled fall but a respawn, and the respawn
		# restarts the move manager itself.
		return KEEP
	_drive_screen_effects()
	var falling: float = player.ragdoll.hips_fall_speed()
	if falling >= RAGDOLL_FALLING_SPEED:
		_ragdoll_dropping = true
	var hips: Vector3 = player.ragdoll.hips_position()
	if _drift_since <= 0.0 or hips.distance_to(_drift_from) > RAGDOLL_DRIFT_DISTANCE:
		_drift_from = hips
		_drift_since = _ragdoll_elapsed
	var drifted_little: bool = _ragdoll_elapsed - _drift_since >= RAGDOLL_DRIFT_WINDOW
	var struck: bool = _ragdoll_dropping and falling <= RAGDOLL_IMPACT_SPEED
	if not (struck or drifted_little or _ragdoll_elapsed >= RAGDOLL_TIMEOUT):
		return KEEP
	_declared = true
	# [13.1] A fatal fall costs exactly a full bar, so a death at full health
	# and one already wounded are the same arithmetic with no special case.
	# Taken here rather than on impact because this is where the death is
	# DECLARED, and the ragdoll branch never reaches a landing at all.
	player.take_damage(config.pawn.fatal_fall_damage, Health.Cause.FALL)
	player.set_dying(true)
	player.died_from_fall.emit()
	return KEEP

## Nothing HERE. This fall charges its full bar where the death is declared,
## which is earlier and covers the ragdoll branch that never lands at all --
## see landing_destination() below. Charging the ordinary fifteen on top would
## be billing the same fall twice.
func landing_damage(_fall_height: float, _rolled: bool) -> float:
	return 0.0

func landing_destination(_fall_height: float, _rolled: bool) -> StringName:
	# A third-person death must not play Jump_Land and then Death2 as if it
	# struck a pose before dying: died_from_fall is DEFERRED, so set_dying()
	# left to fire from there alone would not start until the next frame, and
	# the body would spend that frame landing like anyone else.
	#
	# Declared HERE instead, on the tick the fall is known to be fatal. The
	# sequence still owns clearing it -- see DeathSequence._release_player() --
	# so this only moves the start of it earlier, to the moment it is true.
	_declared = true
	# [13.1] A fatal fall costs exactly a full bar, so a death at full health
	# and one already wounded are the same arithmetic with no special case.
	# Taken here rather than on impact because this is where the death is
	# DECLARED, and the ragdoll branch never reaches a landing at all.
	player.take_damage(config.pawn.fatal_fall_damage, Health.Cause.FALL)
	player.set_dying(true)
	player.died_from_fall.emit()
	return WALKING
