class_name MovementConfig
extends Resource

# Aggregate root. Holds nothing of its own -- every number lives in the
# sub-resource that matches the original's own layering: PawnConfig for what
# TdPawn declares Pawn-wide, one MoveConfig subclass per move for what each
# TdMove_* declares, CameraConfig for the perception layer.
#
# Kept as the single injected object (Arena -> Player/CameraRig/Probes/
# TuningPanel) so every consumer still reads from one shared instance, and a
# preset is still one .tres.
#
# Each default is built with .new() rather than left null: a fresh
# MovementConfig must be immediately usable (Arena falls back to
# MovementConfig.new() when nothing is assigned in the scene), and per-
# instance construction is what keeps two players from sharing one
# PawnConfig -- the same hazard Player.setup() already guards against for the
# collision capsule.

## Which of the two ways of getting the body over an obstacle is in use.
##
## ✅ A SWITCH RATHER THAN A REVERT, so both can be looked at: the owner, having
## seen the scaled version, "你能不能先把代码改成，弧形脚本路径（起点、终点、最高点）配合
## in-place动画？我想再看一次."
##
## false -- the capsule travels in a STRAIGHT line and the clip's own hip lift is
## scaled to the clearance the obstacle needs. One thing moves; the animator's
## curve supplies the shape.
##
## true -- the capsule travels an ARC through a derived apex and the hips are
## held flat. The body's rise is entirely the path's.
##
## ⚠️ NEVER BOTH. Whichever one is off has to be off completely: an arc under a
## clip that also lifts is the double-count that put the hands 1.32 m out in the
## first place, and it is the reason this is one flag rather than two.
@export var scripted_path_arcs: bool = true

@export var pawn: PawnConfig = PawnConfig.new()
@export var camera: CameraConfig = CameraConfig.new()

@export var walking: WalkingConfig = WalkingConfig.new()
@export var jump: JumpConfig = JumpConfig.new()
@export var falling: FallingConfig = FallingConfig.new()
@export var fall_uncontrolled: FallUncontrolledConfig = FallUncontrolledConfig.new()
@export var landing: LandingConfig = LandingConfig.new()
@export var skill_roll: SkillRollConfig = SkillRollConfig.new()
@export var slide: SlideConfig = SlideConfig.new()
@export var crouch: CrouchConfig = CrouchConfig.new()
@export var speed_vault: SpeedVaultConfig = SpeedVaultConfig.new()
@export var into_grab: IntoGrabConfig = IntoGrabConfig.new()
@export var grab: GrabConfig = GrabConfig.new()
@export var wall_run: WallRunConfig = WallRunConfig.new()
@export var wall_climb: WallClimbConfig = WallClimbConfig.new()
@export var turn_180: Turn180Config = Turn180Config.new()
@export var wallrun_jump: WallrunJumpConfig = WallrunJumpConfig.new()
