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

@export var pawn: PawnConfig = PawnConfig.new()
@export var camera: CameraConfig = CameraConfig.new()

@export var walking: WalkingConfig = WalkingConfig.new()
@export var jump: JumpConfig = JumpConfig.new()
@export var falling: FallingConfig = FallingConfig.new()
@export var landing: LandingConfig = LandingConfig.new()
@export var slide: SlideConfig = SlideConfig.new()
@export var crouch: CrouchConfig = CrouchConfig.new()
@export var speed_vault: SpeedVaultConfig = SpeedVaultConfig.new()
@export var grab: GrabConfig = GrabConfig.new()
@export var wall_run: WallRunConfig = WallRunConfig.new()
@export var wallrun_jump: WallrunJumpConfig = WallrunJumpConfig.new()
