class_name VaultState
extends ScriptedMove

# Vaulting DRIVES the body over an obstacle along a computed path instead of
# letting physics push it through — see the note on ScriptedMove above. The
# destination comes from Probes.vault_query()'s "top" hit, so it is known
# clear; nothing along the path itself is checked.

var _exit_speed: float = 0.0
var _exit_direction: Vector3 = Vector3.ZERO
## Set in enter() when the vault query comes back invalid: there is no probed
## top to land on, so physics_update() hands straight back to Ground without
## ever moving the body. See enter()'s note for what the old fallback did.
var _aborted: bool = false

func enter(_previous: StringName) -> void:
	# grounded is DECLARED, not read from is_on_floor(): this state never calls
	# move_and_slide(), so is_on_floor() would keep reporting whatever GroundState
	# left behind for the whole vault — stale coyote time, head bob, etc.
	player.set_grounded(false)
	_aborted = false

	# GroundState already null-checks player.probes AND requires a valid
	# vault_query() before ever transitioning here, so neither branch below is
	# reachable in normal play. They are kept as a guard for a future caller
	# that skips that gate -- but as a GENUINELY safe one. The previous version
	# fell back to `top = player.global_position`, which is not "nowhere to
	# land": the landing is then built as `top + forward * vault_exit_forward`
	# with `landing.y = top.y + standing_height/2`, so that fallback would have
	# driven the body 0.9 m up and 0.6 m forward, through whatever was there.
	# There is no safe destination to invent when the probe found nothing, so
	# invent none: abort the vault and hand back to Ground with the body
	# untouched and its velocity intact.
	var query: Dictionary = player.probes.vault_query() if player.probes != null else Probes.NO_HIT.duplicate()
	if not query["valid"]:
		_aborted = true
		return

	var horizontal := Vector3(player.velocity.x, 0.0, player.velocity.z)
	_exit_speed = horizontal.length() * config.speed_vault.vault_speed_keep
	_exit_direction = horizontal.normalized() if horizontal.length_squared() > 0.0001 else -player.global_transform.basis.z

	var top: Vector3 = query["top"]
	var landing := top + _exit_direction * config.speed_vault.vault_exit_forward
	landing.y = top.y + player.standing_height() * 0.5

	begin(player.global_position, landing, config.speed_vault.vault_duration, config.speed_vault.vault_arc_height)
	player.velocity = Vector3.ZERO

func physics_update(delta: float, _input: MoveInput) -> StringName:
	if _aborted:
		return GROUND

	if advance(delta):
		player.velocity = _exit_direction * _exit_speed
		# Deliberately NOT declared grounded here. landing.y is pinned to the
		# probed obstacle TOP plus vault_exit_forward's un-probed horizontal
		# push -- past a thin obstacle that push can overshoot the obstacle's
		# own footprint into open air over the real floor, which the body has
		# never actually touched. Asserting grounded=true at that point was
		# exactly the bug review caught: it silently re-arms coyote time (a
		# jump buffered mid-vault would fire from mid-air) before GroundState's
		# OWN move_and_slide() gets a chance to check anything. Leaving it
		# false (unchanged from enter()) means GroundState's very next
		# floor-snap tick is what first calls set_grounded() for real, exactly
		# like every other transition into Ground (Air, Slide) already
		# requires of itself. The cost is at most one tick of GroundState
		# running before grounded is confirmed -- harmless, since GroundState
		# always drives with ground_accelerate() regardless of this flag, so
		# no air control leaks in during that tick.
		return GROUND
	return KEEP
