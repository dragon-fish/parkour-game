class_name LedgeHangState
extends ScriptedMove

# Two phases in one state: hanging (position frozen, waiting on input) and
# mantling (a scripted move onto the top). They share the same ledge data, and
# splitting them would mean handing that data across a state boundary.

var _edge: Vector3 = Vector3.ZERO
## The direction the mantle pushes and exits along. Captured ONCE, in
## enter() -- see the note there for why sampling it again later (at
## climb-start for the landing point, or at mantle-completion for the exit
## push, as an earlier version of this file did) is wrong.
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
	player.set_grounded(false)

	# AirState already null-checks player.probes before ever transitioning
	# here (see its own ledge-grab check), so this branch is currently
	# unreachable in normal play -- kept as a defensive guard anyway, matching
	# VaultState.enter()'s identical guard, so a future caller into Ledge that
	# skips that gate degenerates to "hang in place" instead of a
	# null-dereference crash.
	var query: Dictionary = player.probes.ledge_query() if player.probes != null else Probes.NO_HIT.duplicate()
	_edge = query["edge"] if query["valid"] else player.global_position

	# Captured here, once, same as VaultState's _exit_direction: CameraRig.apply_look()
	# turns the player's yaw every physics tick regardless of state, so it is
	# free to change both while hanging (before the player decides to climb)
	# and during the scripted mantle itself (0.42 s of travel time). Sampling
	# facing again later -- at climb-start for the landing point, or at
	# mantle-completion for the exit push -- would let a turn made in either
	# window aim that later step off the ledge actually grabbed. Freezing it
	# here is also the direction the forward probe rays that FOUND _edge were
	# themselves pointing along, so it is the one direction guaranteed to
	# still face the platform.
	_exit_direction = -player.global_transform.basis.z

	_mantling = false
	player.velocity = Vector3.ZERO
	# Hang with the head just under the lip -- but never SNAP the body
	# upward to get there. ledge_query()'s "height" is measured against the
	# player's CURRENT feet at the moment of the grab, which can be anywhere
	# within [ledge_min_height, ledge_max_height] above the edge; a grab near
	# the top of that range already has the feet close to (or below) the
	# standard hang drop, and forcing them down to it regardless would be a
	# visible upward pop. Taking the LOWER of the two only ever pulls the
	# body down (or leaves it alone) -- a high-reach grab simply hangs at
	# full stretch instead, which is also what it should look like.
	var standard_y := _edge.y - config.ledge_hang_drop
	player.global_position = Vector3(
		player.global_position.x,
		minf(player.global_position.y, standard_y),
		player.global_position.z)

func physics_update(delta: float, input: MoveInput) -> StringName:
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

	if input.crouch_held:
		player.start_ledge_cooldown()
		return AIR

	# Pushing forward, or jumping, climbs up.
	if input.move.y > 0.5 or input.jump_pressed:
		var top := _edge + Vector3(0.0, player.standing_height() * 0.5, 0.0)
		top -= _exit_direction * config.mantle_forward_offset
		begin(player.global_position, top, config.mantle_duration, config.mantle_arc_height)
		_mantling = true
	return KEEP
