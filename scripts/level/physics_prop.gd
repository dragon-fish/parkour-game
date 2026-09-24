class_name PhysicsProp
extends RigidBody3D
## A loose rigid body out of the original -- a KActor nothing but physics
## moves. It exists as a script only so the physics_props setting reaches it.


func _ready() -> void:
	SettingsStore.follow_physics_props(self)
