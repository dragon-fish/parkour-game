### TdPlayerReplicationInfo

```
   ClientVersion                                  1
   GameMessageClass                               TdGameMessage
```

### TdMoveVolumeRenderComponent

```
   HiddenGame                                     True
   bAcceptsDecals                                 False
   CastShadow                                     False
   bAcceptsLights                                 False
   CollideActors                                  False
   BlockActors                                    False
   BlockZeroExtent                                False
   BlockNonZeroExtent                             False
   BlockRigidBody                                 False
   AlwaysLoadOnClient                             False
   AlwaysLoadOnServer                             False
```

### TdMovementVolume

```
   bAutoPath                                      True
   bHideSplineMarkers                             True
   NumSplineSegments                              10
   Components                                     <ArrayProperty, 16 bytes>
   RemoteRole                                     ROLE_SimulatedProxy
```

### TdPawn

```
   bCanUnCrouch                                   True
   bGoingForward                                  True
   bAllowMoveChange                               True
   bCharacterInhaling                             True
   bTakeFallDamage                                True
   GravityModifier                                1.0
   OldMovementState                               MOVE_Walking
   MovementState                                  MOVE_Walking
   OverrideWalkingState                           WAS_None
   PendingOverrideWalkingState                    WAS_None
   MinLookConstraint                              (-32768, -32768, -32768)
   MaxLookConstraint                              (32768, 32768, 32768)
   LegRotationSpeed                               50000.0
   GoBackLegAngleLimitMin                         -16384
   GoBackLegAngleLimitMax                         16384
   LegAngleLimitFudge                             2000
   SneakVelocity                                  5.0
   WalkVelocity                                   50.0
   JogVelocity                                    260.0
   RunVelocity                                    400.0
   SprintVelocity                                 630.0
   ASFilterTime                                   3.0
   ASPollSlots                                    40
   MoveManagerClass                               TdPlayerMoveManager
   MoveClasses                                    <ArrayProperty, 380 bytes>
   MaxWallStepHeight                              35.0
   LedgeFindExtent                                (10.0, 10.0, 86.0)
   LedgeFindDistance                              350.0
   LedgeFindDepth                                 4.0
   SpeedCurve_LightWeapon                         <StructProperty<InterpCurveFloat>, 828 bytes>
   SpeedCurve_HeavyWeapon                         <StructProperty<InterpCurveFloat>, 372 bytes>
   SpeedMaxBaseVelocity                           400.0
   SpeedMinBaseVelocity                           10.0
   SpeedStrafeVelocityAccelerationFactor          10.0
   SpeedWalkVelocityAccelerationFactor            7.0
   SpeedSprintVelocityAccelerationFactor          30.0
   SpeedEnergyDecelerationTime                    3.0
   SpeedEnergyDecelerationExponent                0.5
   SpeedTurnDecelerationFactor                    10.0
   UpwardWalkFrictionScale                        1.100000023841858
   DownwardWalkFrictionScale                      0.800000011920929
   MinWalkFrictionModify                          0.4000000059604645
   MaxWalkFrictionModify                          2.0
   UpwardSlideFrictionScale                       5.0
   DownwardSlideFrictionScale                     1.7999999523162842
   BrakingFrictionStrength                        1.0
   RollTriggerTime                                1.0
   FallingUncontrolledHeight                      1000.0
   OverrideSynchPosOffset                         -1.0
   PhysicsHitReactionBlendInTime                  0.07999999821186066
   PhysicsHitReactionBlendOutTime                 0.6000000238418579
   PhysicsHitReactionScale                        1.0
   FootstepTraceLength                            80.0
   FootstepTraceWidth                             10.0
   UnrealEngineFallDamageScale                    1.0
   RegenerateFromTaserPerSecond                   50.0
   TaserRegenerateDelay                           1.5
   RegenerateFromStunPerSecond                    10.0
   MinTimeBeforeRemovingDeadBody                  0.5
   MaxTimeBeforeRemovingDeadBody                  4.0
   WalkableFloorZ                                 0.7099999785423279
   bCanCrouch                                     True
   bCanFly                                        True
   bIsFemale                                      True
   bCanPickupInventory                            True
   GroundSpeed                                    720.0
   AirSpeed                                       2400.0
   AccelRate                                      6144.0
   AirControl                                     0.02500000037252903
   CrouchedPct                                    0.4000000059604645
   BaseEyeHeight                                  76.0
   SceneCapture                                   SceneCaptureCharacterComponent0
   AlwaysRelevantDistanceSquared                  1000000.0
   InventoryManagerClass                          TdInventoryManager
   Components                                     <ArrayProperty, 36 bytes>
```

### TdMoveNode

```
   bNoAutoConnect                                 True
   bIsSkippable                                   False
   bNeedsVelocityToTrigger                        True
   bIsSpecialMove                                 True
   bCanBePlayerNavigationPoint                    False
   GoodSprite                                     Sprite
   BadSprite                                      Sprite2
   Components                                     <ArrayProperty, 24 bytes>
```

### TdMove

```
   SpeedModifier                                  1.0
   FrictionModifier                               1.0
   bShouldUnzoom                                  True
   bAvoidLedges                                   True
   bStickyAim                                     True
   AiAimPenalties                                 <StructProperty<AIAimingModifierSettings>, 92 bytes>
   FirstPersonDPG                                 SDPG_Foreground
   FirstPersonLowerBodyDPG                        SDPG_Intermediate
   AimMode                                        MAM_Default
   LastStopMoveTime                               -10.0
   PreciseLocationSpeed                           400.0
   MinLookConstraint                              (-32768, -32768, -32768)
   MaxLookConstraint                              (32768, 32768, 32768)
   WeaponInactivePitchAimingLimit                 8000
   RootMotionScale                                (1.0, 1.0, 1.0)
   SwanNeckEnableAtPitch                          15
   SwanNeckForward                                35.0
   SwanNeckDown                                   30.0
   StickyAngle                                    800
```

### TdMove_180Turn

```
   FrictionModifier                               0.30000001192092896
   bConstrainLook                                 True
   bUseCameraCollision                            True
   MovementGroup                                  MG_TwoHandsBusy
   DisableMovementTime                            0.30000001192092896
   RedoMoveTime                                   0.5
   MinLookConstraint                              (-10000, -16384, 0)
   MaxLookConstraint                              (10000, 16384, 0)
```

### TdMove_180TurnInAir

```
   PawnPhysics                                    PHYS_Falling
   bCheckExitToUncontrolledFalling                True
   bCheckForSoftLanding                           True
   bConstrainLook                                 True
   bLookAtTargetLocation                          True
   bDisableFaceRotation                           True
   bUseCustomCollision                            True
   FirstPersonLowerBodyDPG                        SDPG_Foreground
   DisableMovementTime                            -1.0
   MinLookConstraint                              (0, -5000, -32768)
   MaxLookConstraint                              (32768, 5000, 32768)
   SwanNeckEnableAtPitch                          0
   SwanNeckForward                                0.0
   SwanNeckDown                                   0.0
```

### TdMove_Barge

```
   BargeMinTraceDistance                          90.0
   BargeTraceTime                                 0.5
   BargeAddOnSpeed                                200.0
   BargeMaxSpeed                                  500.0
   BargeKickThresholdSpeed                        250.0
   bConstrainLook                                 True
   bDisableFaceRotation                           True
   MovementGroup                                  MG_NonInteractive
   FirstPersonLowerBodyDPG                        SDPG_Foreground
   AimMode                                        MAM_NoHands
   RedoMoveTime                                   0.10000000149011612
   MinLookConstraint                              (-14000, -5000, -32768)
   MaxLookConstraint                              (16384, 5000, 32768)
```

### TdMove_AirBarge

```
   HeightBoostDuration                            0.25
   TotalHeightBoost                               60.0
   BargeMinTraceDistance                          300.0
   PawnPhysics                                    PHYS_Falling
   ControllerState                                PlayerWalking
   bCheckExitToUncontrolledFalling                True
   bUseCustomCollision                            True
   DisableLookTime                                -1.0
```

### TdMove_AISpecialMove

```
   bDisableCollision                              True
```

### TdMove_AnimationPlayback

```
   PlayRate                                       1.0
```

### TdMove_AutoStepUp

```
   StepUpDistanceLimit                            60.0
   StepUpSpeedLimit                               300.0
   StepUpLowMinHeight                             33.0
   StepUpMediumMinHeight                          68.0
   StepUpHighMinHeight                            8.0
   StepUpHighMaxHeight                            48.0
   StepUpOptimalLowHeight                         48.0
   StepUpOptimalMediumHeight                      88.0
   StepUpOptimalHighHeight                        144.0
   PawnPhysics                                    PHYS_Flying
   bDisableCollision                              True
   DisableMovementTime                            -1.0
   DisableLookTime                                -1.0
```

### TdMove_Balance

```
   TimeToCounter                                  0.800000011920929
   GravityInfluence                               0.30000001192092896
   ControlInfluence                               1.5
   SpeedInfluence                                 2.5
   CameraInfluence                                0.30000001192092896
   ControllerState                                PlayerBalanceWalk
   SpeedModifier                                  0.3400000035762787
   bConstrainLook                                 True
   bDisableFaceRotation                           True
   bDisableControllerFacingPawnYawRotation        True
   bAvoidLedges                                   False
   AiAimOneShotPenalties                          <StructProperty<AIAimingModifierSettings>, 92 bytes>
   MovementGroup                                  MG_TwoHandsBusy
   AimMode                                        MAM_NoHands
   RedoMoveTime                                   0.5
   MinLookConstraint                              (-13000, -6000, -32768)
   MaxLookConstraint                              (25000, 6000, 32768)
```

### TdMove_BotMelee

```
   GenericAttackProperties                        <StructProperty<MeleeAttackProperties>, 372 bytes>
   bEnableFootPlacement                           True
   MovementGroup                                  MG_NonInteractive
   DisableMovementTime                            -1.0
   DisableLookTime                                -1.0
```

### TdMove_BotBlock

```
   GenericAttackProperties                        <StructProperty<MeleeAttackProperties>, 64 bytes>
```

### TdMove_BotJump

```
   AnticipationTime                               0.4000000059604645
   PawnPhysics                                    PHYS_Flying
   bCheckForGrab                                  True
   bCheckForVaultOver                             True
```

### TdMove_BotLanding

```
   MediumRunningDistance                          250.0
   LongRunningDistance                            450.0
   SoftLandingHeight                              420.0
   RollDistance                                   650.0
   JumpLength                                     BJL_None
   bDisableCollision                              False
```

### TdMove_BotMeleeSecondSwing_Assault

```
   GenericAttackProperties                        <StructProperty<MeleeAttackProperties>, 64 bytes>
```

### TdMove_BotMeleeSecondSwing_CopRemington

```
   GenericAttackProperties                        <StructProperty<MeleeAttackProperties>, 64 bytes>
```

### TdMove_BotMeleeSecondSwing_Sniper

```
   GenericAttackProperties                        <StructProperty<MeleeAttackProperties>, 36 bytes>
```

### TdMove_BotMeleeSecondSwing_Support

```
   GenericAttackProperties                        <StructProperty<MeleeAttackProperties>, 36 bytes>
```

### TdMove_BotPursuitFinishingAttack

```
   FinishingAttackProperties                      <StructProperty<MeleeAttackProperties>, 372 bytes>
   bEnableFootPlacement                           False
```

### TdMove_BotStart

```
   bEnableFootPlacement                           True
```

### TdMove_BotStartRunning

```
   MoveStartedTimeStamp                           -999.0
   MinTimeBetweenTwoStartMoves                    0.5
```

### TdMove_BotStartWalking

```
   MinTimeBetweenTwoStartMoves                    0.5
```

### TdMove_BotStop

```
   MaxRunningStopTriggerDist                      145.0
   MinRunningStopTriggerDist                      105.0
   MaxWalkingStopTriggerDist                      90.0
   MinWalkingStopTriggerDist                      70.0
   StopMoveDistanceRunning                        145.0
   StopMoveDistanceWalking                        80.0
```

### TdMove_StumbleBase

```
   DirectionalBias                                0.5
   MovementGroup                                  MG_TwoHandsBusy
   DisableMovementTime                            -1.0
   DisableLookTime                                -1.0
```

### TdMove_BotTurnStanding

```
   bEnableFootPlacement                           True
```

### TdMove_Climb

```
   IdleBlendInTime                                0.05000000074505806
   ClimbBlendInTime                               0.05000000074505806
   ClimbDownBlendInTime                           0.5
   ClimbDownFastVelocity                          200.0
   StartTurningAngle                              16384
   PawnPhysics                                    PHYS_Flying
   ControllerState                                PlayerGrabbing
   bShouldHolsterWeapon                           True
   bConstrainLook                                 True
   bDisableFaceRotation                           True
   MovementGroup                                  MG_TwoHandsBusy
   FirstPersonDPG                                 SDPG_Intermediate
   AimMode                                        MAM_NoHands
   RedoMoveTime                                   0.5
   MinLookConstraint                              (-5000, -32000, 0)
   MaxLookConstraint                              (10000, 32000, 0)
   SwanNeckForward                                40.0
```

### TdMove_Coil

```
   HeightBoostDuration                            0.25
   TotalHeightBoost                               60.0
   CoilMinTriggerSpeed                            100.0
   CoilTime                                       0.5
   PawnPhysics                                    PHYS_Falling
   ControllerState                                PlayerWalking
   bCheckExitToUncontrolledFalling                True
   bConstrainLook                                 True
   bUseCustomCollision                            True
   FirstPersonLowerBodyDPG                        SDPG_Foreground
   MinLookConstraint                              (-5000, -32768, -32768)
   MaxLookConstraint                              (30000, 32768, 32768)
```

### TdMove_Crouch

```
   SpeedModifier                                  0.20000000298023224
   bShouldUnzoom                                  False
   bConstrainLook                                 True
   bUseCustomCollision                            True
   bUseCameraCollision                            True
   bEnableFootPlacement                           True
   bEnableAgainstWall                             True
   bAllowPickup                                   True
   MinLookConstraint                              (-14000, -32768, -32768)
   MaxLookConstraint                              (14000, 32768, 32768)
```

### TdMove_Cutscene

```
   PawnPhysics                                    PHYS_Flying
   bDisableCollision                              True
   DisableMovementTime                            -1.0
   DisableLookTime                                -1.0
```

### TdMove_Disarm_Tutorial

```
   DisableMovementTime                            0.0
   DisableLookTime                                0.0
```

### TdMove_Disarmed

```
   PawnPhysics                                    PHYS_Flying
   bDisableCollision                              True
   MovementGroup                                  MG_NonInteractive
```

### TdMove_DisarmedTutorial

```
   bDisableCollision                              False
```

### TdMove_DodgeJump

```
   BaseJumpZ                                      300.0
   JumpAddXY                                      600.0
   StrafeThreshold                                0.9900000095367432
   DodgeJumpInertiaConservation                   0.30000001192092896
   JumpBlendInTime                                0.10000000149011612
   JumpBlendOutTime                               0.20000000298023224
   LookAtAIVelThreshold                           200.0
   LookAtAITraceDistance                          250.0
   LookAtAIRadiusThreshold                        90.0
   PawnPhysics                                    PHYS_Falling
   ControllerState                                PlayerGrabbing
   bCheckExitToFalling                            True
   ExitToFallingZSpeed                            -190.0
   AiAimOneShotPenalties                          <StructProperty<AIAimingModifierSettings>, 92 bytes>
   DisableMovementTime                            -1.0
   RedoMoveTime                                   0.30000001192092896
```

### TdMove_Falling

```
   PawnPhysics                                    PHYS_Falling
   ControllerState                                PlayerWalking
   bCheckForGrab                                  True
   bCheckForVaultOver                             True
   bCheckExitToUncontrolledFalling                True
   bCheckForSoftLanding                           True
```

### TdMove_FallingBot

```
   bDisableCollision                              False
```

### TdMove_FallingUncontrolled

```
   PawnPhysics                                    PHYS_Falling
   ControllerState                                PlayerDying
   bCheckForSoftLanding                           True
```

### TdMove_Grab

```
   GrabDesiredLedgeOffset                         (30.0, 0.0, 92.80000305175781)
   GrabMaxAngle                                   40.0
   HangFreeZDistanceCheck                         128.0
   StartTurningAngle                              16384.0
   bIsWithinForwardView                           True
   CurrentShimmyMove                              NoShimmy
   HangFreeMinLookContraint                       (8300, -16384, 0)
   HangFreeMaxLookContraint                       (16000, 16384, 0)
   SlopeMinLookContraint                          (-3200, -8192, 0)
   SlopeMaxLookContraint                          (8300, 8192, 0)
   ShimmyAroundCornerMinLookContraint             (3200, -32768, 0)
   ShimmyAroundCornerMaxLookContraint             (16000, 32768, 0)
   ShimmyAroundCornerFreeMinLookContraint         (11000, -32768, 0)
   ShimmyAroundCornerFreeMaxLookContraint         (16000, 32768, 0)
   DisableShimmyTime                              0.6000000238418579
   PawnPhysics                                    PHYS_None
   ControllerState                                PlayerGrabbing
   bDisableCollision                              True
   bConstrainLook                                 True
   bDisableFaceRotation                           True
   MovementGroup                                  MG_TwoHandsBusy
   AimMode                                        MAM_NoHands
   DisableLookTime                                0.800000011920929
   RedoMoveTime                                   0.15000000596046448
   MinLookConstraint                              (-3200, -32768, 0)
   MaxLookConstraint                              (16000, 32768, 0)
   SwanNeckEnableAtPitch                          0
   SwanNeckForward                                70.0
```

### TdMove_GrabJump

```
   GrabJumpOffZHeight                             160.0
   GrabJumpPushAwayMaxSpeed                       400.0
   GrabJumpPushAwayMinSpeed                       200.0
   GrabAllowedJumpAngle                           45.0
   PawnPhysics                                    PHYS_Falling
   ControllerState                                PlayerWalking
   bCheckForGrab                                  True
   bCheckForVaultOver                             True
   bCheckExitToFalling                            True
   bDelayTimeCheckAutoMoves                       0.20000000298023224
   bDisableFaceRotation                           True
```

### TdMove_GrabPullUp

```
   GrabAllowedPullUpAngle                         45
   PawnPhysics                                    PHYS_Flying
   ControllerState                                PlayerWalking
   bDisableCollision                              True
   bShouldHolsterWeapon                           True
   bConstrainLook                                 True
   bDisableFaceRotation                           True
   bUseCameraCollision                            True
   MovementGroup                                  MG_NonInteractive
   AimMode                                        MAM_NoHands
   DisableMovementTime                            -1.0
   DisableLookTime                                0.20000000298023224
   MinLookConstraint                              (0, -10000, 0)
   MaxLookConstraint                              (16384, 10000, 0)
```

### TdMove_GrabPullUpBot

```
   PawnPhysics                                    PHYS_Flying
```

### TdMove_GrabTransfer

```
   Allowed2DTransferDistance                      260.0
   AllowedZTransferDistance                       140.0
   PawnPhysics                                    PHYS_Flying
   ControllerState                                PlayerWalking
   bShouldHolsterWeapon                           True
   bDisableFaceRotation                           True
   AiAimOneShotPenalties                          <StructProperty<AIAimingModifierSettings>, 92 bytes>
   AimMode                                        MAM_NoHands
   DisableMovementTime                            -1.0
   DisableLookTime                                -1.0
```

### TdMove_Interact

```
   DistanceToAButton                              48.0
   DistanceToAValve                               40.0
   ControllerState                                PlayerWalking
   bDisableFaceRotation                           True
   MovementGroup                                  MG_NonInteractive
   AimMode                                        MAM_NoHands
   DisableMovementTime                            -1.0
   DisableLookTime                                -1.0
```

### TdMove_IntoClimb

```
   FirstStepZDistance                             38.0
   PawnPhysics                                    PHYS_Flying
   ControllerState                                PlayerWalking
   bShouldHolsterWeapon                           True
   MovementGroup                                  MG_NonInteractive
   FirstPersonDPG                                 SDPG_Intermediate
   AimMode                                        MAM_NoHands
   DisableMovementTime                            -1.0
   DisableLookTime                                -1.0
   RedoMoveTime                                   0.5
```

### TdMove_IntoGrab

```
   IntoGrabMaxAngle                               70.0
   IntoGrabAlignSpeed                             300.0
   IntoGrabMinInitialAlignSpeed                   -3000.0
   GrabMinGrabableZNormal                         0.7070000171661377
   GrabDesiredLedgeOffset                         (30.0, 0.0, 92.80000305175781)
   MinGrabLedgeAdjustDistance                     32.0
   IntoGrabMaxDistance                            200.0
   IntoGrabZVelocityThreshold                     150.0
   HangFoldedDownwardSpeedLimit                   -300.0
   HangFoldedIntoGrabZSpeedThreshold              150.0
   HangFoldedIntoGrabSpeed2DThreshold             50.0
   HangFoldedUpperDeltaDistance                   35.0
   HangFoldedLowerDeltaDistance                   70.0
   HangFoldedMaxDistance                          60.0
   HangImpactMinZSpeed                            -600.0
   HangHardImpactMinZSpeed                        -1000.0
   PawnPhysics                                    PHYS_Falling
   ControllerState                                PlayerWalking
   bCheckForVaultOver                             True
   bCheckExitToUncontrolledFalling                True
   MovementGroup                                  MG_NonInteractive
   AimMode                                        MAM_NoHands
```

### TdMove_IntoGrabBot

```
   IntoGrabMaxAngle                               90.0
```

### TdMove_IntoZipLine

```
   HangOffset                                     (0.0, 0.0, -90.0)
   ZVelocityFallLimit                             -600.0
   IntoZiplineBlendInTime                         0.30000001192092896
   IntoZiplineBlendOutTime                        0.20000000298023224
   SameZipLineRedoMoveTime                        3.0
   PawnPhysics                                    PHYS_Flying
   ControllerState                                PlayerWalking
   bConstrainLook                                 True
   MovementGroup                                  MG_NonInteractive
   AimMode                                        MAM_NoHands
   RedoMoveTime                                   0.5
   MinLookConstraint                              (-2500, -7000, -32768)
   MaxLookConstraint                              (32768, 7000, 32768)
```

### TdMove_Jump

```
   BaseJumpZ                                      630.0
   BaseJumpZHeavy                                 430.0
   JumpAddXY                                      100.0
   LongJumpSlowThreshold                          400.0
   LongJumpNormalThreshold                        500.0
   LongJumpFastThreshold                          700.0
   JumpBlendInTime                                0.10000000149011612
   JumpBlendOutTime                               0.20000000298023224
   JumpStillBlendOutTime                          0.20000000298023224
   CanDoMoveTaserLimit                            0.5
   ControllerState                                PlayerWalking
   bCheckForGrab                                  True
   bCheckForVaultOver                             True
   bCheckForWallClimb                             True
   bCheckExitToFalling                            True
   bUseCameraCollision                            True
   bAllowPickup                                   True
   AiAimPenalties                                 <StructProperty<AIAimingModifierSettings>, 64 bytes>
```

### TdMove_JumpBot_Base

```
   AnticipationTime                               0.4000000059604645
   PawnPhysics                                    PHYS_Flying
   bDisableCollision                              False
```

### TdMove_JumpIntoGrabBot

```
   PawnPhysics                                    PHYS_Flying
```

### TdMove_Landing

```
   HardLandingDamage                              15.0
   LandingSpeedReduction                          65.0
   HardLandingHeight                              530.0
   SkillRollLandingHeight                         200.0
   SoftLandingHeight                              300.0
```

### TdMove_LayOnGround

```
   PawnPhysics                                    PHYS_Falling
   ControllerState                                PlayerGrabbing
   FrictionModifier                               0.15000000596046448
   bConstrainLook                                 True
   bDisableFaceRotation                           True
   bAvoidLedges                                   False
   bUseCustomCollision                            True
   FirstPersonLowerBodyDPG                        SDPG_Foreground
   AimMode                                        MAM_Right
   MinLookConstraint                              (-2000, -5000, -32768)
   MaxLookConstraint                              (32768, 5000, 32768)
   SwanNeckEnableAtPitch                          0
   SwanNeckForward                                0.0
   SwanNeckDown                                   0.0
```

### TdMove_LayOnGroundBot

```
   LayDownIdleTime                                0.25
```

### TdMove_LedgeWalk

```
   ControllerState                                PlayerLedgeWalking
   SpeedModifier                                  0.10000000149011612
   bConstrainLook                                 True
   bDisableFaceRotation                           True
   bDisableControllerFacingPawnYawRotation        True
   bAvoidLedges                                   False
   bEnableAgainstWall                             True
   MovementGroup                                  MG_OneHandBusy
   MinLookConstraint                              (-14000, -10000, -32768)
   MaxLookConstraint                              (16384, 10000, 32768)
```

### TdMove_MeleeBase

```
   bTargeting                                     True
   TargetingRotationSpeed                         10.0
   TargetingMaxDistance                           300.0
   TraceExtent                                    (5.0, 5.0, 5.0)
   MeleeDamage                                    50.0
   MaxMeleeDistance                               180.0
   MaxMeleeAngle                                  0.5
   CanDoMoveTaserLimit                            0.800000011920929
   MovementGroup                                  MG_NonInteractive
   AimMode                                        MAM_NoHands
```

### TdMove_Melee

```
   BlendInMissed                                  0.07999999821186066
   BlendOutMissed                                 0.10000000149011612
   TraceExtent                                    (12.0, 12.0, 12.0)
   MeleeDamage                                    33.5
   bConstrainLook                                 True
   bUseCameraCollision                            True
   AimMode                                        MAM_TwoHanded
   MinLookConstraint                              (-10000, -32768, -32768)
   MaxLookConstraint                              (10000, 32768, 32768)
```

### TdMove_Melee_Assault

```
   GenericAttackProperties                        <StructProperty<MeleeAttackProperties>, 64 bytes>
```

### TdMove_PursuitMelee

```
   JumpKickAttackPropertiesE                      <StructProperty<MeleeAttackProperties>, 380 bytes>
   RunAttackPropertiesE                           <StructProperty<MeleeAttackProperties>, 372 bytes>
   StandAttackPropertiesE                         <StructProperty<MeleeAttackProperties>, 372 bytes>
   SlideAttackPropertiesE                         <StructProperty<MeleeAttackProperties>, 380 bytes>
   ShoveAttackPropertiesE                         <StructProperty<MeleeAttackProperties>, 372 bytes>
   JumpKickAttackPropertiesN                      <StructProperty<MeleeAttackProperties>, 380 bytes>
   RunAttackPropertiesN                           <StructProperty<MeleeAttackProperties>, 380 bytes>
   StandAttackPropertiesN                         <StructProperty<MeleeAttackProperties>, 380 bytes>
   SlideAttackPropertiesN                         <StructProperty<MeleeAttackProperties>, 380 bytes>
   ShoveAttackPropertiesN                         <StructProperty<MeleeAttackProperties>, 380 bytes>
   JumpKickAttackPropertiesH                      <StructProperty<MeleeAttackProperties>, 380 bytes>
   RunAttackPropertiesH                           <StructProperty<MeleeAttackProperties>, 380 bytes>
   StandAttackPropertiesH                         <StructProperty<MeleeAttackProperties>, 380 bytes>
   SlideAttackPropertiesH                         <StructProperty<MeleeAttackProperties>, 380 bytes>
   ShoveAttackPropertiesH                         <StructProperty<MeleeAttackProperties>, 380 bytes>
   bEnableFootPlacement                           False
```

### TdMove_Melee_BossCeleste

```
   JumpKickAttackPropertiesE                      <StructProperty<MeleeAttackProperties>, 156 bytes>
   RunAttackPropertiesE                           <StructProperty<MeleeAttackProperties>, 212 bytes>
   StandAttackPropertiesE                         <StructProperty<MeleeAttackProperties>, 240 bytes>
   JumpKickAttackPropertiesN                      <StructProperty<MeleeAttackProperties>, 156 bytes>
   RunAttackPropertiesN                           <StructProperty<MeleeAttackProperties>, 184 bytes>
   StandAttackPropertiesN                         <StructProperty<MeleeAttackProperties>, 212 bytes>
   JumpKickAttackPropertiesH                      <StructProperty<MeleeAttackProperties>, 148 bytes>
   RunAttackPropertiesH                           <StructProperty<MeleeAttackProperties>, 176 bytes>
   StandAttackPropertiesH                         <StructProperty<MeleeAttackProperties>, 176 bytes>
```

### TdMove_Melee_PatrolCop

```
   GenericAttackProperties                        <StructProperty<MeleeAttackProperties>, 64 bytes>
```

### TdMove_Melee_PatrolCop_Remington

```
   GenericAttackProperties                        <StructProperty<MeleeAttackProperties>, 64 bytes>
```

### TdMove_Melee_Riot

```
   ShieldPushProperties                           <StructProperty<MeleeAttackProperties>, 372 bytes>
```

### TdMove_Melee_SupportCop

```
   GenericAttackProperties                        <StructProperty<MeleeAttackProperties>, 36 bytes>
```

### TdMove_MeleeAir

```
   LookAtAngle                                    (-6000, 0, 0)
   MeleeAirAboveMinAngle                          0.800000011920929
   MeleeAirAboveMinSeparation                     150.0
   MeleeAirAboveMaxSeparation                     500.0
   TargetingMaxDistance                           800.0
   TraceExtent                                    (60.0, 60.0, 160.0)
   MeleeDamage                                    100.0
   PawnPhysics                                    PHYS_Falling
   FirstPersonLowerBodyDPG                        SDPG_Foreground
   DisableMovementTime                            -1.0
   RedoMoveTime                                   0.30000001192092896
```

### TdMove_MeleeAirAbove

```
   bTargeting                                     False
   MeleeDamage                                    300.0
   PawnPhysics                                    PHYS_Flying
   DisableMovementTime                            -1.0
   DisableLookTime                                -1.0
```

### TdMove_MeleeAirAboveBot

```
   bDisableCollision                              True
```

### TdMove_MeleeCrouch

```
   BargeTraceDistance                             120.0
   TraceExtent                                    (30.0, 30.0, 30.0)
   MeleeDamage                                    33.5
   SpeedModifier                                  0.20000000298023224
   bUseCustomCollision                            True
   AimMode                                        MAM_TwoHanded
```

### TdMove_MeleeDummy

```
   GenericAttackProperties                        <StructProperty<MeleeAttackProperties>, 120 bytes>
```

### TdMove_MeleeSlide

```
   BargeTraceDistance                             90.0
   TraceExtent                                    (40.0, 40.0, 40.0)
   MeleeDamage                                    60.0
   FrictionModifier                               0.10000000149011612
   bUseCustomCollision                            True
   DisableMovementTime                            -1.0
   DisableLookTime                                -1.0
```

### TdMove_MeleeVault

```
   TargetingMaxDistance                           800.0
   TraceExtent                                    (60.0, 60.0, 160.0)
   PawnPhysics                                    PHYS_Flying
   bConstrainLook                                 True
   bDisableFaceRotation                           True
   MovementGroup                                  MG_OneHandBusy
   DisableLookTime                                -1.0
   MinLookConstraint                              (-3000, -8000, -32768)
   MaxLookConstraint                              (6000, 8000, 32768)
```

### TdMove_MeleeWallrun

```
   bTargeting                                     False
   TraceOffset                                    (30.0, 0.0, 0.0)
   TraceExtent                                    (30.0, 30.0, 30.0)
   MeleeDamage                                    80.0
   PawnPhysics                                    PHYS_Falling
   bConstrainLook                                 True
   MinLookConstraint                              (-3000, -8000, 0)
   MaxLookConstraint                              (16000, 8000, 0)
```

### TdMove_RumpSlide

```
   MaxSlideSpeed                                  1000.0
   SideControl                                    350.0
   GravityModifier                                0.5
   InitialSpeedLoss                               0.75
   MinSlideFloorZ                                 0.8999999761581421
   PawnPhysics                                    PHYS_Falling
   bConstrainLook                                 True
   bDisableFaceRotation                           True
   AiAimPenalties                                 <StructProperty<AIAimingModifierSettings>, 92 bytes>
   AiAimOneShotPenalties                          <StructProperty<AIAimingModifierSettings>, 92 bytes>
   DisableMovementTime                            -1.0
   RedoMoveTime                                   1.0
   MinLookConstraint                              (-5000, -5000, 0)
   MaxLookConstraint                              (5000, 5000, 0)
   RootOffset                                     (0.0, 0.0, 20.0)
```

### TdMove_SkillRoll

```
   ControllerState                                PlayerGrabbing
   bConstrainLook                                 True
   bDisableFaceRotation                           True
   bAvoidLedges                                   False
   MovementGroup                                  MG_TwoHandsBusy
   AimMode                                        MAM_Right
   MinLookConstraint                              (-2000, -5000, -32768)
   MaxLookConstraint                              (32768, 5000, 32768)
```

### TdMove_Slide

```
   SlideAbortSpeed                                250.0
   SlideAbortTime                                 2.0
   MaxFloorInclineZ                               0.5
   FrictionModifier                               0.10000000149011612
   bConstrainLook                                 True
   bDisableFaceRotation                           True
   bAvoidLedges                                   False
   bUseCustomCollision                            True
   bUseCameraCollision                            True
   bAllowPickup                                   True
   AiAimPenalties                                 <StructProperty<AIAimingModifierSettings>, 92 bytes>
   DisableMovementTime                            -1.0
   MinLookConstraint                              (-10000, -10000, 0)
   MaxLookConstraint                              (10000, 10000, 0)
```

### TdMove_SlideBot

```
   SlideAbortSpeed                                100.0
   FrictionModifier                               0.03500000014901161
   bDisableCollision                              False
   bDisableActorCollision                         True
   bUseCustomCollision                            True
```

### TdMove_SoftLanding

```
   PawnPhysics                                    PHYS_Falling
   ControllerState                                PlayerWalking
   bCheckExitToFalling                            True
   bCheckForSoftLanding                           True
   bConstrainLook                                 True
   bDisableFaceRotation                           True
   DisableMovementTime                            -1.0
   MinLookConstraint                              (-16384, -5000, 0)
   MaxLookConstraint                              (16384, 5000, 0)
```

### TdMove_SpeedVault

```
   VaultClearObjectHeight                         35.0
   MaxTimeToLedge                                 0.4000000059604645
   VaultTypes                                     <ArrayProperty, 4588 bytes>
   PawnPhysics                                    PHYS_Flying
   bDisableCollision                              True
   bConstrainLook                                 True
   bDisableFaceRotation                           True
   bAvoidLedges                                   False
   bUseCameraCollision                            True
   AiAimOneShotPenalties                          <StructProperty<AIAimingModifierSettings>, 92 bytes>
   MovementGroup                                  MG_OneHandBusy
   DisableMovementTime                            -1.0
   DisableLookTime                                -1.0
   MinLookConstraint                              (-3000, -8000, -32768)
   MaxLookConstraint                              (6000, 8000, 32768)
```

### TdMove_VaultBot

```
   PawnPhysics                                    PHYS_Flying
```

### TdMove_SpringBoard

```
   SpringBoardMaxHeight                           148.0
   SpringBoardMinHeight                           80.0
   SpringBoardJumpZ                               950.0
   SpringBoardJumpXYAdd                           -100.0
   SpringBoardJumpXYMin                           400.0
   IntermediateFootPlantHeight                    64.0
   IntermediateFootPlantDistance                  112.0
   CheckDistanceTime                              1.0
   StepTime1                                      0.20000000298023224
   StepTime2                                      0.20000000298023224
   PawnPhysics                                    PHYS_Flying
   ControllerState                                PlayerWalking
   bCheckForGrab                                  True
   bCheckForVaultOver                             True
   bCheckForWallClimb                             True
   bCheckExitToFalling                            True
   bDelayTimeCheckAutoMoves                       0.699999988079071
   bTriggersCompliment                            True
   AiAimPenalties                                 <StructProperty<AIAimingModifierSettings>, 92 bytes>
   AiAimOneShotPenalties                          <StructProperty<AIAimingModifierSettings>, 92 bytes>
   DisableMovementTime                            -1.0
```

### TdMove_StandGrabHeaveBot

```
   ForcedSpeed                                    200.0
   WallDistance                                   125.0
   GrabZOffset                                    120.42500305175781
   PawnPhysics                                    PHYS_Flying
```

### TdMove_StepUp

```
   StepUpDistanceLimit                            60.0
   StepUpSpeedLimit                               300.0
   StepUpLowMinHeight                             33.0
   StepUpMediumMinHeight                          68.0
   StepUpHighMinHeight                            112.0
   StepUpHighMaxHeight                            148.0
   StepUpOptimalLowHeight                         48.0
   StepUpOptimalMediumHeight                      88.0
   StepUpOptimalHighHeight                        144.0
   PawnPhysics                                    PHYS_Flying
   bDisableCollision                              True
   bConstrainLook                                 True
   bDisableFaceRotation                           True
   bAvoidLedges                                   False
   DisableMovementTime                            -1.0
   MinLookConstraint                              (-3000, -8000, -32768)
   MaxLookConstraint                              (6000, 8000, 32768)
```

### TdMove_Stumble

```
   PawnPhysics                                    PHYS_Falling
   bCheckExitToUncontrolledFalling                True
   bShouldHolsterWeapon                           True
```

### TdMove_Swing

```
   MaxSwingVelocity                               4.25
   ExitVelocityModifier                           600.0
   SwingPendulumLength                            120.0
   SwingAngleTimingOffset                         1.0
   SwingExitGravityModifier                       0.75
   SwingExitGravityModifierTime                   0.699999988079071
   PawnPhysics                                    PHYS_Flying
   ControllerState                                PlayerGrabbing
   bCheckForGrab                                  True
   bCheckForVaultOver                             True
   bCheckForWallClimb                             True
   bShouldHolsterWeapon                           True
   AiAimPenalties                                 <StructProperty<AIAimingModifierSettings>, 92 bytes>
   AiAimOneShotPenalties                          <StructProperty<AIAimingModifierSettings>, 92 bytes>
   MovementGroup                                  MG_TwoHandsBusy
   FirstPersonDPG                                 SDPG_Intermediate
   AimMode                                        MAM_NoHands
   DisableLookTime                                -1.0
```

### TdMove_SwingJump

```
   GravityModifier                                0.7300000190734863
   GravityModifierTimer                           0.75
   TargetVolumeOffset                             (-120.0, 0.0, -20.0)
   PawnPhysics                                    PHYS_Falling
   ControllerState                                PlayerWalking
   bCheckForGrab                                  True
   bCheckForVaultOver                             True
   bCheckForWallClimb                             True
   bCheckExitToFalling                            True
   bTriggersCompliment                            True
   bConstrainLook                                 True
   AiAimPenalties                                 <StructProperty<AIAimingModifierSettings>, 92 bytes>
   AiAimOneShotPenalties                          <StructProperty<AIAimingModifierSettings>, 92 bytes>
   MinLookConstraint                              (-11000, -32768, -32768)
   MaxLookConstraint                              (16384, 32768, 32768)
```

### TdMove_Vertigo

```
   ZoomFOV                                        84.0
   ZoomRate                                       30.0
   ZoomOutTime                                    1.2000000476837158
   bUseCameraCollision                            True
   MovementGroup                                  MG_TwoHandsBusy
   AimMode                                        MAM_TwoHanded
   DisableMovementTime                            1.5
   DisableLookTime                                1.5
   RedoMoveTime                                   3.0
```

### TdMove_Walking

```
   ControllerState                                PlayerWalking
   bShouldUnzoom                                  False
   bUseCameraCollision                            True
   bEnableFootPlacement                           True
   bEnableAgainstWall                             True
   bAllowPickup                                   True
```

### TdMove_WallClimb

```
   WallClimbingVerticalStartAngle                 33.0
   WallClimbingVerticalFriction                   6.0
   WallClimbingMaxDistance2D                      120.0
   AddOnSpeed2DHeight                             60.0
   AddOnSpeed2DMaxLimit                           650.0
   AddOnSpeedZHeight                              130.0
   AddOnSpeedZMaxLimit                            320.0
   WallClimbingGravity                            800.0
   MinLegdeZNormal                                0.7070000171661377
   MinWallHeight                                  180.0
   MinUpwardsVelocityToDoubleJump                 100.0
   MaxIntoWallClimbVelocityToDoubleJump           100.0
   PawnPhysics                                    PHYS_WallClimbing
   ControllerState                                PlayerWallWalking
   bCheckForGrab                                  True
   bCheckForVaultOver                             True
   bCheckForEdgeInVelDir                          True
   FrictionModifier                               0.30000001192092896
   AiAimPenalties                                 <StructProperty<AIAimingModifierSettings>, 92 bytes>
   AimMode                                        MAM_NoHands
   WeaponInactivePitchAimingLimit                 0
```

### TdMove_WallClimb180TurnJump

```
   JumpOffZHeight                                 250.0
   JumpPushAwaySpeed                              400.0
   JumpTimeWindow                                 0.6000000238418579
   PawnPhysics                                    PHYS_Falling
   ControllerState                                PlayerWalking
   bCheckForGrab                                  True
   bCheckForVaultOver                             True
   bCheckForWallClimb                             True
   bCheckExitToFalling                            True
   ExitToFallingZSpeed                            -800.0
   bTriggersCompliment                            True
   AiAimPenalties                                 <StructProperty<AIAimingModifierSettings>, 92 bytes>
   AiAimOneShotPenalties                          <StructProperty<AIAimingModifierSettings>, 92 bytes>
   AimMode                                        MAM_Right
   DisableMovementTime                            0.4000000059604645
   RedoMoveTime                                   1.0
```

### TdMove_WallClimbDodgeJump

```
   BaseJumpZ                                      700.0
   JumpAddXY                                      150.0
   DodgeJumpInertiaConservation                   1.0
   JumpBlendInTime                                0.20000000298023224
   JumpBlendOutTime                               0.20000000298023224
   PawnPhysics                                    PHYS_Falling
   ControllerState                                PlayerWalking
   bCheckForGrab                                  True
   bCheckForVaultOver                             True
   bCheckForWallClimb                             True
   bCheckExitToFalling                            True
   bTriggersCompliment                            True
   AiAimOneShotPenalties                          <StructProperty<AIAimingModifierSettings>, 92 bytes>
   AimMode                                        MAM_Right
```

### TdMove_WallKick

```
   WallKickMaxDistance                            60.0
   WallKickCheckHeight                            90.0
   WallKickExtentWidth                            20.0
   WallKickExtentHeight                           10.0
   WallKickVelocity2D                             300.0
   WallKickVelocityZ                              580.0
   PawnPhysics                                    PHYS_Falling
   ControllerState                                PlayerWalking
   bCheckForGrab                                  True
   bCheckForVaultOver                             True
   bTriggersCompliment                            True
   RedoMoveTime                                   1.0
```

### TdMove_WallRun

```
   WallRunningForwardCheckDistance                50.0
   WallRunningStrafeCheckDistance                 50.0
   WallRunningMinWallHeight                       192.0
   WallRunningMinSpeed                            200.0
   WallRunningVelocityStartLimit                  300.0
   WallRunningVelocityStopLimit                   -500.0
   WallRunningForwardMaxStartAngle                57.0
   WallRunningStrafeStartAngle                    60.0
   WallRunningHorisontalFriction                  0.05000000074505806
   WallRunningHorisontalInitialZHeight            170.0
   WallRunningHorisontalAcceleration              820.0
   WallRunningHorisontalDeceleration              500.0
   WallRunningHorisontalAlignSpeed                700.0
   WallRunningIntoWallrunBlendInTime              0.20000000298023224
   WallRunningIntoWallrunBlendOutTime             0.20000000298023224
   WallRunningDelayPawnRotationTime               0.009999999776482582
   WallRunningDistanceForIntoWall                 180.0
   WallRunningRotatePawnAlongWallTime             0.4000000059604645
   WallRunningMoveToIntoPositionDegreeThreshold   70.0
   MinimumVelocityIntoWall                        600.0
   MaximumVelocityIntoWall                        700.0
   LookAlongWallInterpolationTime                 0.20000000298023224
   ControllerState                                PlayerWallWalking
   bConstrainLook                                 True
   bUseAbsoluteYawConstraint                      True
   bDisableControllerFacingPawnYawRotation        True
   bUseCameraCollision                            True
   AiAimPenalties                                 <StructProperty<AIAimingModifierSettings>, 92 bytes>
   RedoMoveTime                                   0.15000000596046448
   MinLookConstraint                              (-13000, -16384, -32768)
   MaxLookConstraint                              (13000, 16384, 32768)
   StickyAngle                                    4000
   StickyAimedModifier                            1.0
```

### TdMove_WallrunDodgeJump

```
   BaseJumpZ                                      300.0
   JumpAddXY                                      600.0
   DodgeJumpInertiaConservation                   0.30000001192092896
   PawnPhysics                                    PHYS_Falling
   ControllerState                                PlayerWalking
   bCheckExitToFalling                            True
   bTriggersCompliment                            True
   AiAimOneShotPenalties                          <StructProperty<AIAimingModifierSettings>, 92 bytes>
```

### TdMove_WallrunJump

```
   WallRunningPushAwaySpeedNoob                   120.0
   WallRunningPushAwaySpeedProAdd                 400.0
   WallRunningPushForwardSpeedMin                 0.10000000149011612
   WallRunningJumpOffZHeightForward               100.0
   WallRunningJumpOffZHeightMaxAddTurned          60.0
   PawnPhysics                                    PHYS_Falling
   ControllerState                                PlayerWalking
   bCheckForGrab                                  True
   bCheckForVaultOver                             True
   bCheckForWallClimb                             True
   bCheckExitToFalling                            True
   bUseAbsoluteYawConstraint                      True
   AiAimOneShotPenalties                          <StructProperty<AIAimingModifierSettings>, 92 bytes>
```

### TdMove_ZipLine

```
   HangOffset                                     (0.0, 0.0, -90.0)
   MinZipVelocity                                 300.0
   MinZipAcceleration                             400.0
   ZipFadeInTime                                  0.10000000149011612
   ZipFadeOutTime                                 0.5
   PawnPhysics                                    PHYS_Flying
   ControllerState                                PlayerGrabbing
   bShouldHolsterWeapon                           True
   bConstrainLook                                 True
   bDisableFaceRotation                           True
   AiAimPenalties                                 <StructProperty<AIAimingModifierSettings>, 92 bytes>
   AiAimOneShotPenalties                          <StructProperty<AIAimingModifierSettings>, 92 bytes>
   MovementGroup                                  MG_TwoHandsBusy
   AimMode                                        MAM_NoHands
   DisableMovementTime                            -1.0
   MinLookConstraint                              (-3200, -7000, -32768)
   MaxLookConstraint                              (32768, 7000, 32768)
```

### TdMovementExclusionVolume

```
   bExcludeFootMoves                              True
   bExcludeHandMoves                              True
   Components                                     <ArrayProperty, 8 bytes>
   SupportedEvents                                <ArrayProperty, 4 bytes>
```

### TdMovementSplineMarker

```
   bHardAttach                                    True
   bHiddenEd                                      True
   bEdShouldSnap                                  True
   Components                                     <ArrayProperty, 8 bytes>
```

### TdMoveNode_Destination

```
   bIsSkippable                                   True
   bIsSpecialMove                                 False
   GoodSprite                                     Sprite
   BadSprite                                      Sprite2
   Components                                     <ArrayProperty, 24 bytes>
```

### TdMoveNode_GrabHeave

```
   WallDistance                                   140.0
   MinWallHeight                                  175.0
   MaxWallHeight                                  350.0
   bDoAutoWallAdjustment                          True
   MoveReachspecClass                             TdReachSpec_GrabHeave
   SpecialMoveCost                                1200
   bNeedsVelocityToTrigger                        False
   GoodSprite                                     Sprite
   BadSprite                                      Sprite2
   Components                                     <ArrayProperty, 28 bytes>
```

### TdMoveNode_Vault

```
   ForcedSpeed                                    500.0
   VaultOverWallDistance_LowVault                 250.0
   VaultOntoWallDistance_LowVault                 180.0
   VaultOverWallDistance_HighVault                245.0
   VaultOntoWallDistance_HighVault                270.0
   MinWallHeight_LowVault                         75.0
   MaxWallHeight_LowVault                         144.0
   MinWallHeight_HighVault                        145.0
   MaxWallHeight_HighVault                        304.0
   iHighVaultCost                                 1000
   iVaultOntoCost                                 400
   MoveReachspecClass                             TdReachSpec_Vault
   GoodSprite                                     Sprite
   BadSprite                                      Sprite2
   Components                                     <ArrayProperty, 32 bytes>
```

### TdMoveNode_HighVault

```
   GoodSprite                                     Sprite
   BadSprite                                      Sprite2
   Components                                     <ArrayProperty, 32 bytes>
```

### TdMoveNode_JumpIntoGrab

```
   MoveReachspecClass                             TdReachSpec_JumpIntoGrab
   SpecialMoveCost                                1600
   GoodSprite                                     Sprite
   BadSprite                                      Sprite2
   Components                                     <ArrayProperty, 24 bytes>
```

### TdMoveNode_Slide

```
   MoveReachspecClass                             TdReachSpec_Slide
   SpecialMoveCost                                400
   GoodSprite                                     Sprite
   BadSprite                                      Sprite2
   Components                                     <ArrayProperty, 24 bytes>
```

### TdMoveNode_SpeedVault

```
   GoodSprite                                     Sprite
   BadSprite                                      Sprite2
   Components                                     <ArrayProperty, 32 bytes>
```

### TdMoveNode_WallRun

```
   ForcedSpeed                                    720.0
   WallDistance                                   210.0
   MinWallHeight                                  250.0
   MaxWallHeight                                  600.0
   MoveReachspecClass                             TdReachSpec_Wallrun
   SpecialMoveCost                                2000
   GoodSprite                                     Sprite
   BadSprite                                      Sprite2
   Components                                     <ArrayProperty, 24 bytes>
```

### TdMoveReachSpec

```
   bIsSkippable                                   False
```

### TdPlayerCamera

```
   FreeflightScale                                1.0
```

### TdPlayerController

```
   bLeftThumbStickPassedDeadZone                  True
   bRightThumbStickPassedDeadZone                 True
   JumpTapTime                                    0.15000000596046448
   BagSearchTapTime                               0.30000001192092896
   AllowedEmoteMessageInterval                    3.0
   TargetingCutoffAngle                           3900.0
   LookAtTimeDelay                                0.6000000238418579
   CloseCombatMinRange                            170.0
   CloseCombatMaxRange                            360.0
   CloseCombatRangeTime                           0.699999988079071
   CloseCombatMaxAngle                            0.699999988079071
   InputMaxSprintRaduisLimit                      0.699999988079071
   InputMaxSprintHeightLimit                      0.699999988079071
   InputMaxWalkRadiusLimit                        0.6899999976158142
   WallRunningAlignTime                           0.20000000298023224
   ReactionTimeSpawnLevel                         99.9000015258789
   ReactionTimeDrain                              8.0
   ReactionTimeFadeIn                             90.0
   ReactionTimeFadeOut                            20.0
   ReactionTimeBuildRates                         <StructProperty<ReactionTimeSettings>, 92 bytes>
   WallClimbingDodgeJumpThreshold                 0.800000011920929
   WallRunningDodgeJumpThreshold                  0.800000011920929
   WalkCyclePart1                                 0.20000000298023224
   WalkCyclePart2                                 0.699999988079071
   Team                                           1
   StickySpeed                                    100.0
   TutorialDataClass                              UIDataStore_TdTutorialData
   TimeTrialDataClass                             UIDataStore_TdTimeTrialData
   StringAliasBindingsMapClass                    UIDataStore_TdStringAliasBindingsMap
   SixAxisDisarmZ                                 -0.10000000149011612
   SixAxisDisarmY                                 0.44999998807907104
   SixAxisRollZ                                   0.3499999940395355
   SixAxisRollY                                   0.05000000074505806
   DisarmTimeMultiplier                           1.0
   CameraClass                                    TdPlayerCamera
   SavedMoveClass                                 TdSavedMove
   CheatClass                                     TdCheatManager
   InputClass                                     TdPlayerInputConsole
   bNotifyFallingHitWall                          True
   MinHitWall                                     1.0
   Components                                     <ArrayProperty, 12 bytes>
```

### TdPlayerInput

```
   bViewAccelEnabled                              True
   YawAccelThreshold                              0.8999999761581421
   MaxSensitivityMultiplier                       1.7999999523162842
   MinSensitivityMultiplier                       0.20000000298023224
   SensitivityMultiplier                          1.0
   WalkButtonMultiplier                           0.30000001192092896
```

### TdPlayerInputConsole

```
   bAAEnabled                                     True
   AAStrafeAssistRelease                          3000
   AssistYawBias                                  1.0
   AssistPitchBias                                1.0
```

### TdPlayerPawn

```
   bEnableHairPhysics                             True
   FirstPersonDPG                                 SDPG_Foreground
   FirstPersonLowerBodyDPG                        SDPG_Intermediate
   VertigoEdgeProbingHeight                       1000.0
   VertigoEdgeProbingDistance                     70.0
   EdgeCheckMaxSpeed                              300.0
   EdgeCheckDistance                              20.0
   EdgeStopMinHeight                              36.0
   ReverbVolumePollTime                           0.4000000059604645
   OcclusionDuckLevel                             0.15000000596046448
   OcclusionDuckFadeTime                          0.6000000238418579
   IndoorMixGroupIndex                            -1
   OutdoorMixGroupIndex                           -1
   MovementStringAllowedGap                       0.8999999761581421
   PlayerBulletDamageMultiplier                   1.0
   HairBones                                      <ArrayProperty, 52 bytes>
   FocusLocationInterpolationSpeed                20.0
   CommonArmedLight1p                             AS_C1P_OneHanded_Common
   CommonArmedHeavy1p                             AS_C1P_TwoHanded_Common
   CommonArmedLight3p                             AS_F3P_OneHanded_Common
   CommonArmedHeavy3p                             AS_F3P_TwoHanded_Common
   OldMovementState                               MOVE_None
   MovementState                                  MOVE_None
   BrakingFrictionStrength                        0.5
   ArmorBulletsHeadSettings                       <StructProperty<ArmorSettings>, 92 bytes>
   ArmorBulletsBodySettings                       <StructProperty<ArmorSettings>, 92 bytes>
   ArmorBulletsLegsSettings                       <StructProperty<ArmorSettings>, 92 bytes>
   ArmorMeleeHeadSettings                         <StructProperty<ArmorSettings>, 64 bytes>
   ArmorMeleeBodySettings                         <StructProperty<ArmorSettings>, 64 bytes>
   ArmorMeleeLegsSettings                         <StructProperty<ArmorSettings>, 64 bytes>
   RegenerateDelay                                5.0
   RegenerateHealthPerSecond                      25.0
   bAvoidLedges                                   True
   bDirectHitWall                                 True
   SceneCapture                                   SceneCaptureCharacterComponent0
   Components                                     <ArrayProperty, 40 bytes>
```

### TdPlayerStart

```
   Radius                                         300.0
   GenericSprite                                  Sprite
   GoodSprite                                     Sprite
   BadSprite                                      Sprite2
   Components                                     <ArrayProperty, 28 bytes>
```
