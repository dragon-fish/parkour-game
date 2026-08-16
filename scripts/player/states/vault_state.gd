class_name VaultState
extends ScriptedMove

# Vaulting DRIVES the body over an obstacle along a computed path instead of
# letting physics push it through — see the note on ScriptedMove above. The
# destination comes from Probes.vault_query()'s "top" hit, so it is known
# clear; nothing along the path itself is checked.

var _exit_speed: float = 0.0
var _exit_direction: Vector3 = Vector3.ZERO

func enter(_previous: StringName) -> void:
	# grounded is DECLARED, not read from is_on_floor(): this state never calls
	# move_and_slide(), so is_on_floor() would keep reporting whatever GroundState
	# left behind for the whole vault — stale coyote time, head bob, etc.
	player.set_grounded(false)

	var query: Dictionary = player.probes.vault_query()
	var horizontal := Vector3(player.velocity.x, 0.0, player.velocity.z)
	_exit_speed = horizontal.length() * config.vault_speed_keep
	_exit_direction = horizontal.normalized() if horizontal.length_squared() > 0.0001 else -player.global_transform.basis.z

	var top: Vector3 = query["top"] if query["valid"] else player.global_position
	var landing := top + _exit_direction * config.vault_exit_forward
	landing.y = top.y + player.standing_height() * 0.5

	begin(player.global_position, landing, config.vault_duration)
	player.velocity = Vector3.ZERO

func physics_update(delta: float, _input: MoveInput) -> StringName:
	if advance(delta):
		player.velocity = _exit_direction * _exit_speed
		# Landing on the far side is grounded again — declared here rather than
		# left for GroundState's own first tick, which would otherwise read
		# whatever this state left behind (false) for one extra frame.
		player.set_grounded(true)
		return GROUND
	return KEEP
