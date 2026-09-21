class_name MovementConfig
extends Resource

# Aggregate root. Holds nothing of its own -- every number lives in the
# sub-resource that matches the original's own layering: [ME:CONFIRMED 06]
# the original declares Pawn-wide numbers on TdPawn and per-move numbers on
# one TdMove_* class per move, which is PawnConfig and one MoveConfig subclass
# per move here, plus CameraConfig for the perception layer.
#
# Kept as the single injected object -- Arena hands this instance to Player,
# CameraRig and TuningPanel, and Player passes it on to Probes -- so every
# consumer reads from one shared instance and a preset is still one .tres.
#
# DO NOT leave any of these defaults null. A fresh MovementConfig must be
# immediately usable, because Arena falls back to MovementConfig.new() when
# nothing is assigned in the scene; and per-instance construction is what
# keeps two players from sharing one PawnConfig -- the same hazard
# Player.setup() already guards against by duplicating the collision capsule
# shape, which is a resource shared by every instance of player.tscn.

@export var pawn: PawnConfig = PawnConfig.new()
@export var camera: CameraConfig = CameraConfig.new()

@export var walking: WalkingConfig = WalkingConfig.new()
@export var jump: JumpConfig = JumpConfig.new()
@export var coil: CoilConfig = CoilConfig.new()
@export var falling: FallingConfig = FallingConfig.new()
@export var fall_uncontrolled: FallUncontrolledConfig = FallUncontrolledConfig.new()
@export var soft_landing: SoftLandingConfig = SoftLandingConfig.new()
@export var landing: LandingConfig = LandingConfig.new()
@export var lay_on_ground: LayOnGroundConfig = LayOnGroundConfig.new()
@export var skill_roll: SkillRollConfig = SkillRollConfig.new()
@export var slide: SlideConfig = SlideConfig.new()
@export var ramp_slide: RampSlideConfig = RampSlideConfig.new()
@export var crouch: CrouchConfig = CrouchConfig.new()
@export var speed_vault: SpeedVaultConfig = SpeedVaultConfig.new()
@export var into_grab: IntoGrabConfig = IntoGrabConfig.new()
@export var grab: GrabConfig = GrabConfig.new()
@export var wall_run: WallRunConfig = WallRunConfig.new()
@export var wall_climb: WallClimbConfig = WallClimbConfig.new()
@export var turn_180: Turn180Config = Turn180Config.new()
@export var wallrun_jump: WallrunJumpConfig = WallrunJumpConfig.new()
@export var zipline: ZiplineConfig = ZiplineConfig.new()
@export var swing: SwingConfig = SwingConfig.new()
@export var ladder: LadderConfig = LadderConfig.new()
@export var balance: BalanceConfig = BalanceConfig.new()
@export var ledge_walk: LedgeWalkConfig = LedgeWalkConfig.new()
@export var spring_board: SpringBoardConfig = SpringBoardConfig.new()
@export var dodge_jump: DodgeJumpConfig = DodgeJumpConfig.new()
