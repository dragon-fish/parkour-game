@tool
class_name FallHeightVolume
extends Area3D

# TdFallHeightVolume: where a fall is measured from. Give it the
# CollisionShape3D children the brush needs.
#
# [ME:CONFIRMED decompile TdFallHeightVolume.Touch] a pawn touching the volume
# has EnterFallingHeight set to Center.Z + FallHeightOffset, and its current
# move is told (TdMove.TouchedFallHeightVolume). That is the whole of it: no
# condition on the move, the speed or the direction. Player.touch_fall_height_volume()
# does both halves.
#
# What it is FOR is the level's: a chute whose run-out should land hard
# (RumpSlide's landing is hard only after touching one), a pit whose landing
# should count from far higher than the body fell (the original gives some
# offsets of 1000 m and more), a drop that should count from lower.
#
# A TOUCH, NOT A STAY. The original fires once on entering; standing inside
# does nothing more, and only leaving and coming back fires again.
#
# Kismet switches some of them (SeqAct_ChangeCollision): off is no collision
# layer and mask, as for every volume the runner switches.

## Center.Z of the original's brush, world Y in metres. Kept as the original
## cooked it rather than read off the shapes: it is the value the game used.
@export var center_y: float = 0.0
## FallHeightOffset, metres. Negative counts the fall from below the centre.
@export var fall_height_offset: float = 0.0


func _init() -> void:
	# Only the body, never the level it stands in -- see Arena.PLAYER_LAYER.
	# On a layer of its own so the hand-plant's volume test can find it.
	collision_layer = Arena.MOVEMENT_VOLUME_LAYER
	collision_mask = Arena.PLAYER_LAYER


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	# Levels built before the layer was given saved theirs as 0. Whatever
	# Kismet has already switched keeps its switch; it only learns the layer
	# to restore.
	if has_meta(PackagePresence.BUILT_LAYERS_META):
		var built: Array = get_meta(PackagePresence.BUILT_LAYERS_META)
		built[0] = Arena.MOVEMENT_VOLUME_LAYER
	else:
		collision_layer = Arena.MOVEMENT_VOLUME_LAYER
	body_entered.connect(_on_body_entered)


## EnterFallingHeight as the touch sets it.
func fall_height_y() -> float:
	return center_y + fall_height_offset


func _get_configuration_warnings() -> PackedStringArray:
	for child in get_children():
		if child is CollisionShape3D and child.shape != null:
			return PackedStringArray()
	return PackedStringArray(["No CollisionShape3D with a shape: nothing can ever touch this."])


func _on_body_entered(body: Node3D) -> void:
	# TdPawn(Other) != none: whoever has the pawn's fields.
	if body.has_method("touch_fall_height_volume"):
		body.touch_fall_height_volume(fall_height_y())
