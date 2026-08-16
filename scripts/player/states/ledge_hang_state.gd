class_name LedgeHangState
extends ScriptedMove

# Two phases in one state: hanging (position frozen, waiting on input) and
# mantling (a scripted move onto the top). They share the same ledge data, and
# splitting them would mean handing that data across a state boundary.

## Set in enter() when the ledge query comes back invalid: there is nothing to
## hang from, so physics_update() hands straight back to Air without ever
## touching the body. See enter()'s note for what the old fallback did instead.
var _aborted: bool = false

var _edge: Vector3 = Vector3.ZERO
## The direction the mantle pushes and exits along. Captured ONCE, at
## COMMITMENT -- the moment forward or jump is pressed and begin() is called,
## in physics_update()'s climb-trigger branch below -- NOT at grab time.
## Grabbing a ledge does not commit to a direction: the player can hang and
## turn freely first, and only the facing at the moment they actually choose
## to climb should decide where that climb goes. See the note on the
## climb-trigger branch for the full reasoning (and why an earlier version of
## this file, which captured in enter(), got this wrong).
var _exit_direction: Vector3 = Vector3.ZERO
var _mantling: bool = false

func enter(_previous: StringName) -> void:
	# grounded is DECLARED, not read from is_on_floor(): like Vault, this
	# state drives the body directly and never calls move_and_slide() --
	# neither while hanging (frozen in place, see the "hold still" branch
	# below) nor while mantling (a scripted arc onto the ledge top) -- so
	# is_on_floor() would keep reporting whatever the previous state left
	# behind for the whole time this state runs. See VaultState.enter()'s
	# matching note.
	#
	# A single declaration here is enough to cover every exit path too:
	# nothing below ever sets grounded true, so both a completed mantle
	# (hands off to Ground) and a crouch-release drop (hands off to Air)
	# correctly leave it false -- the mantle case deliberately mirrors
	# VaultState's own hand-off to Ground (see the note on that return below).
	# It is also what satisfies StateMachine's declaration invariant for this
	# state, which never calls set_grounded() again after this line.
	player.set_grounded(false)

	_aborted = false
	_mantling = false

	# AirState already null-checks player.probes AND requires a valid
	# ledge_query() before ever transitioning here, so neither branch below is
	# reachable in normal play. They are kept as a guard for a future caller
	# that skips that gate -- but as a GENUINELY safe one. The previous version
	# fell back to `_edge = player.global_position`, which is not "nowhere to
	# hang": the mantle target is built as `_edge + up * standing_height/2 +
	# forward * mantle_forward_offset`, so that fallback would have teleported
	# the body 0.9 m up and 0.4 m forward, through whatever was there. There is
	# no safe destination to invent when the probe found nothing, so invent
	# none: abort and let the player fall.
	var query: Dictionary = player.probes.ledge_query() if player.probes != null else Probes.NO_HIT.duplicate()
	if not query["valid"]:
		_aborted = true
		return
	_edge = query["edge"]

	player.velocity = Vector3.ZERO
	# The body holds exactly wherever it grabbed -- NO repositioning, up or
	# down. ledge_query()'s "height" is measured against the player's CURRENT
	# feet at the moment of the grab, so a valid grab can land anywhere in
	# [ledge_min_height, ledge_max_height] above them. Snapping to any FIXED
	# offset from the edge from there would, for most of that range, be
	# either an upward pop (pulling the body toward the edge) or a downward
	# drop (pushing it away) the player never asked for -- holding position
	# is the correct behaviour on its own merits, not a simplification of a
	# "real" reposition. (A grab near the top of the reachable range now
	# hangs at full stretch, well below the edge; see
	# test_mantling_completes_from_the_top_of_the_grab_range in
	# tests/test_ledge.gd for confirmation the mantle still completes fine
	# from there within mantle_duration -- the climb is a fixed-time lerp,
	# not a fixed-speed one, so distance never affects how long it takes.)

## Started on EVERY exit, not just the deliberate crouch-drop, and here rather
## than at each `return` so a future exit path cannot forget it. The mantle
## hand-off used to leave the cooldown at zero: a landing that found no floor
## dropped to Air and AirState's very next ledge_query() could re-grab on the
## same tick, with no gate of any kind between the two. That is an unbounded
## oscillation whenever the landing point is not standing room -- the inverted
## mantle_forward_offset sign made every running grab exactly that case, but
## fixing the sign only removes today's trigger, not the hole. The cooldown is
## the hole's actual lid.
##
## Harmless on the paths that were already fine: a completed mantle leaves the
## player standing on top of the platform, where there is no ledge in front of
## them to re-grab anyway, so withholding grabs for ledge_regrab_cooldown costs
## nothing a player can feel.
func exit() -> void:
	player.start_ledge_cooldown()

func physics_update(delta: float, input: MoveInput) -> StringName:
	if _aborted:
		return AIR

	if _mantling:
		if advance(delta):
			player.velocity = _exit_direction * config.mantle_exit_speed
			# Deliberately NOT declared grounded here -- see the note on
			# enter() above, and VaultState.physics_update()'s matching note.
			# The landing point is pinned to the probed ledge edge plus an
			# un-probed forward offset (mantle_forward_offset) that nothing
			# here has checked against real geometry, so asserting grounded
			# true at this exact instant would be exactly the bug that note
			# describes for Vault. Leaving it false means GroundState's own
			# next floor-snap tick is what first verifies it for real -- and,
			# since Step Zero of this task, GroundState's Slide/Vault entry
			# checks are themselves gated on grounded being true, so this
			# hand-off cannot chain straight into a second scripted move
			# either.
			return GROUND
		return KEEP

	# Hanging: hold still. enter() zeroed velocity once and nothing in this
	# branch ever calls move_and_slide(), so nothing needs to run every tick
	# to keep the body from drifting or falling -- there is simply no code
	# path here that would move it. Matches VaultState, which likewise zeros
	# velocity once at enter() rather than every tick of its own scripted move.

	# The re-grab cooldown this drop needs is started by exit(), which covers
	# this path and the mantle hand-off alike -- see the note on exit().
	if input.crouch_held:
		return AIR

	# Pushing forward, or jumping, climbs up. This IS the moment of
	# commitment: the player has been free to turn at any point while
	# hanging, right up until this tick, and CameraRig.apply_look() keeps
	# turning the body every physics tick regardless of state -- so facing is
	# sampled HERE, fresh, rather than reusing whatever _edge's grab-time
	# probe happened to see. This is also the ONLY place _exit_direction is
	# ever written: both the landing point immediately below and the exit
	# push on mantle completion (above) read it back rather than re-sampling
	# facing themselves, so a further turn made DURING the 0.42 s scripted
	# climb cannot retroactively change either one either.
	if input.move.y > 0.5 or input.jump_pressed:
		_exit_direction = -player.global_transform.basis.z
		var top := _edge + Vector3(0.0, player.standing_height() * 0.5, 0.0)
		# PLUS, not minus. _exit_direction is FORWARD (-basis.z), and the
		# landing has to sit mantle_forward_offset PAST the lip, standing on
		# the platform -- exactly what VaultState does with vault_exit_forward,
		# and exactly what MovementConfig documents this knob as doing. The
		# original brief wrote `top -= basis.z * 0.4`, where basis.z is
		# BACKWARD, so that `-=` was already a forward push; a later refactor
		# introduced `_exit_direction = -basis.z` but kept the `-=`,
		# double-negating it. _edge is the SurfaceDown hit exactly ledge_reach
		# ahead of the body, so subtracting here put the landing
		# (ledge_reach - offset) ahead of the body: for a running grab (body
		# 0.85-1.0 m off the face) that is 0.25-0.4 m IN FRONT of the wall,
		# feet at platform height over open air. Measured on the test rig with
		# the sign inverted, the body then settles balanced on the block's top
		# EDGE, outside the platform -- and on the arena's LedgeMid it drops,
		# slides back down the face and re-grabs: climb / fall / re-climb on
		# every approach.
		top += _exit_direction * config.mantle_forward_offset
		begin(player.global_position, top, config.mantle_duration, config.mantle_arc_height)
		_mantling = true
	return KEEP
