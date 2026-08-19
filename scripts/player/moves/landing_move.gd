class_name LandingMove
extends Move

# The Godot counterpart of the original's TdMove_Landing: the 2 s lockout
# after a hard landing taken without a roll. Input is refused for the whole
# duration -- that is the entire point, see LandingConfig.constrain_look --
# and the camera plus the red tint recover across it so the player can see
# the penalty draining rather than merely waiting it out.
#
# ScreenEffects and CameraRig are both plain-number sinks with no time logic
# of their own (see their own header comments); this move owns the whole
# fade curve and pushes a fresh number to each of them every tick.

var _elapsed: float = 0.0

func enter(_previous: StringName) -> void:
	_elapsed = 0.0
	player.velocity = Vector3.ZERO
	# Landing already found a floor before handing off here (settle_landing()
	# only ever calls landing_destination() after set_grounded(true)), and
	# this move never calls move_and_slide() on its own first tick -- so the
	# declaration has to be made here rather than left to physics_update().
	player.set_grounded(true)
	# Same reasoning as SlideMove.exit()/CrouchMove.exit(): the capsule may
	# still be sitting at a shrunk height coming in here. The ordinary path is
	# a jump or a fall, where the capsule was never touched and this is a
	# no-op -- but a hard landing straight out of a Slide/Crouch that never
	# got its standing capsule back (still pinned under a low ceiling right up
	# to the moment of impact) must not carry that shrink silently into a
	# 2 s lockout this move never inspects again. request_standing_capsule()
	# is itself deferred (not forced) when there is still no headroom, so this
	# is always safe to call unconditionally.
	player.request_standing_capsule()

func physics_update(delta: float, _input: MoveInput) -> StringName:
	_elapsed += delta
	var t: float = clampf(_elapsed / maxf(config.landing.lockout_time, 0.0001), 0.0, 1.0)

	# Recovering, not holding: 1 at touchdown falling to 0 at release.
	var severity: float = 1.0 - t
	if player.camera_rig != null:
		player.camera_rig.set_crouch_amount(severity)
		player.camera_rig.set_landing_pitch_offset(config.landing.camera_pitch_offset * severity)
	if player.screen_effects != null:
		player.screen_effects.set_tint(config.landing.tint_color, severity)

	player.velocity.y = -config.pawn.floor_snap_speed
	player.move_and_slide()
	player.set_grounded(player.is_on_floor())

	if t >= 1.0:
		return WALKING
	return KEEP

func exit() -> void:
	if player.camera_rig != null:
		player.camera_rig.set_crouch_amount(0.0)
		player.camera_rig.set_landing_pitch_offset(0.0)
	if player.screen_effects != null:
		player.screen_effects.set_tint(config.landing.tint_color, 0.0)
