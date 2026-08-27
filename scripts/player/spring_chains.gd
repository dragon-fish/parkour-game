class_name SpringChains
extends SpringBoneSimulator3D

# Turns bone-name prefixes into spring chains, so a model whose jiggle physics
# lived in engine-specific components (Unity PhysBones, VRM spring bones) gets
# its hair/accessory motion back from nothing but the bone naming. Placed as a
# child of the Skeleton3D it should drive, like any SkeletonModifier3D.
#
# Chain discovery: every LEAF bone whose name starts with one of
# chain_prefixes anchors a chain; the chain extends upward while the parent
# also matches AND is not a junction (a bone with more than one matching
# child). Junctions stay unsimulated so sibling chains never share a bone.
# A chain that collapses to a single bone gets a virtual extended tail --
# a one-joint spring is otherwise a no-op.

## DO NOT change this to PackedStringArray. The editor drops the packed form
## entirely when it re-saves a scene holding one, leaving every group with no
## prefixes and the model with no physics at all -- confirmed after editing
## `weight` in the editor and letting it re-save: the whole body lost its
## skeleton effects.
@export var chain_prefixes: Array[String] = []
## Joint collision radius, in the skeleton's own (pre-mount-scale) metres.
@export var joint_radius: float = 0.015
@export var chain_stiffness: float = 1.0
@export var chain_drag: float = 0.4
@export var chain_gravity: float = 0.05
## When set, every chain simulates RELATIVE to this bone (VRM's "center"):
## whole-body yaw and teleports stop exciting the springs, and only motion
## of the chain's anchor relative to the center -- the animation itself --
## does. The cure for "turn the camera and everything thrashes".
@export var center_bone_name: String = ""
## How much this group behaves like dead weight rather than hair. 0 keeps
## the three dials above exactly; 1 is iron -- gravity pins it down, drag
## kills every swing, stiffness barely pulls it back to rest. In between
## blends the three -- added so a chain like a leg-iron can read as having
## real weight, not as loose hair.
@export_range(0.0, 1.0) var weight: float = 0.0

## Iron's numbers, the weight = 1 end of the blend.
const HEAVY_STIFFNESS := 0.1
const HEAVY_DRAG := 0.95
const HEAVY_GRAVITY := 1.5

func _ready() -> void:
	if get_skeleton() == null:
		# A modifier resolves its skeleton after entering the tree; a _ready
		# that lands first tries again next frame rather than giving up.
		_build.call_deferred()
		return
	_build()

func _build() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	var children_of := {}
	for i in skeleton.get_bone_count():
		var parent := skeleton.get_bone_parent(i)
		if not children_of.has(parent):
			children_of[parent] = []
		children_of[parent].append(i)
	var chains: Array[Vector2i] = []
	for i in skeleton.get_bone_count():
		if children_of.has(i):
			continue
		if not _matches(skeleton.get_bone_name(i)):
			continue
		var root := i
		while true:
			var parent := skeleton.get_bone_parent(root)
			if parent < 0 or not _matches(skeleton.get_bone_name(parent)):
				break
			var matching := 0
			for child in children_of[parent]:
				if _matches(skeleton.get_bone_name(child)):
					matching += 1
			if matching > 1:
				break
			root = parent
		chains.append(Vector2i(root, i))
	if chains.is_empty():
		# Loud, because the failure is silent otherwise: a group with no
		# prefixes simply never moves, which reads as "the physics broke".
		push_warning("%s found no chains for prefixes %s" % [name, chain_prefixes])
	setting_count = chains.size()
	for idx in chains.size():
		set_root_bone(idx, chains[idx].x)
		set_end_bone(idx, chains[idx].y)
		if chains[idx].x == chains[idx].y:
			set_extend_end_bone(idx, true)
			set_end_bone_length(idx, joint_radius * 2.0)
		set_radius(idx, joint_radius)
		set_stiffness(idx, lerpf(chain_stiffness, HEAVY_STIFFNESS, weight))
		set_drag(idx, lerpf(chain_drag, HEAVY_DRAG, weight))
		set_gravity(idx, lerpf(chain_gravity, HEAVY_GRAVITY, weight))
		if center_bone_name != "" and skeleton.find_bone(center_bone_name) >= 0:
			set_center_from(idx, SpringBoneSimulator3D.CENTER_FROM_BONE)
			set_center_bone_name(idx, center_bone_name)

func _matches(bone_name: String) -> bool:
	for prefix in chain_prefixes:
		if bone_name.begins_with(prefix):
			return true
	return false
