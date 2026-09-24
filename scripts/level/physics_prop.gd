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


## The physics_props setting, by freezing the body where it stands.
##
## DO NOT switch this with process_mode. PackagePresence keeps every body in a
## level active while disabled (DISABLE_MODE_KEEP_ACTIVE, so a package coming
## back does not rebuild its hulls), and writes the placement node's
## process_mode itself whenever its package comes or goes -- and a loose box IS
## its placement node. Both ways the box went on being shoved about with the
## setting off.
func simulate(on: bool) -> void:
	freeze = not on


func reset_for_respawn() -> void:
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	# Through the server as well as the node: a body mid-flight has its node
	# written back from the server on the next tick, which would undo a node
	# move alone.
	if PhysicsServer3D.body_get_space(get_rid()).is_valid():
		PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, _placed)
		PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3.ZERO)
		PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)
	global_transform = _placed
	sleeping = _starts_asleep
