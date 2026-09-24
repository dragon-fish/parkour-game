class_name PhysicsProp
extends RigidBody3D
## A loose rigid body out of the original -- a KActor nothing but physics
## moves. It follows the physics_props setting, and a respawn puts it back
## where the level placed it: a box shoved off a ledge is level state a life
## used up.

var _placed: Transform3D
var _starts_asleep := false


func _ready() -> void:
	_placed = global_transform
	_starts_asleep = sleeping
	SettingsStore.follow_physics_props(self)
	add_to_group(Arena.RESET_ON_RESPAWN)


func reset_for_respawn() -> void:
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	# Through the server as well as the node: a body mid-flight has its node
	# written back from the server on the next tick, which would undo a node
	# move alone. With physics props off there is no body in the server, and
	# the node is all there is.
	if can_process():
		PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, _placed)
		PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3.ZERO)
		PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)
	global_transform = _placed
	sleeping = _starts_asleep
