class_name LedgeHangState
extends ScriptedMove

# Two phases in one state: hanging (position frozen, waiting on input) and
# mantling (a scripted move onto the top). They share the same ledge data, and
# splitting them would mean handing that data across a state boundary.

var _edge: Vector3 = Vector3.ZERO
var _normal: Vector3 = Vector3.UP
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
	_normal = query["normal"] if query["valid"] else Vector3.UP
	_mantling = false
	player.velocity = Vector3.ZERO
	# Hang with the head just under the lip.
	player.global_position = Vector3(
		player.global_position.x,
		_edge.y - config.ledge_hang_drop,
		player.global_position.z)

func physics_update(delta: float, input: MoveInput) -> StringName:
	if _mantling:
		if advance(delta):
			var forward: Vector3 = -player.global_transform.basis.z
			player.velocity = forward * config.mantle_exit_speed
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

	# Hanging: hold still. No gravity, no drift.
	player.velocity = Vector3.ZERO

	if input.crouch_held:
		player.start_ledge_cooldown()
		return AIR

	# Pushing forward, or jumping, climbs up.
	if input.move.y > 0.5 or input.jump_pressed:
		var top := _edge + Vector3(0.0, player.standing_height() * 0.5, 0.0)
		top -= player.global_transform.basis.z * config.mantle_forward_offset
		begin(player.global_position, top, config.mantle_duration, config.mantle_arc_height)
		_mantling = true
	return KEEP
