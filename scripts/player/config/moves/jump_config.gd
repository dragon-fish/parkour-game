class_name JumpConfig
extends MoveConfig

# The Godot counterpart of the original's TdMove_Jump. No fields of its own
# yet -- jump take-off still reads straight off PawnConfig's base_jump_z/
# jump_add_xy -- so this class exists purely to give Jump a slot in
# MovementConfig that matches every other move's own layering.
