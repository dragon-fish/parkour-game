class_name LandingMove
extends Move

# [ME:CONFIRMED] TdMove_Landing's Godot counterpart: a 2 s lockout after a
# hard landing taken without a roll (see LandingConfig.lockout_time for the
# measurement). MOVEMENT input is refused for the
# whole duration -- that is the entire point: this move never reads its
# MoveInput at all, and LandingConfig.constrain_look pins the yaw to a +-0.2
# rad fan around the facing the landing began with on top of that. LOOK PITCH
# is deliberately still the player's (see LandingConfig's own note on why
# clamping it here as well fought set_landing_pitch_offset below). The camera
# and the red tint recover across the lockout so the player can see the
# penalty draining rather than merely waiting it out.
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

	# THE SINK BELONGS TO THE IMPACT FRAME. MoveManager calls enter() mid-tick
	# and does not run this move's own physics_update() on that tick, so driving
	# the camera only from there put the sink a frame late -- and
	# Player.update_effects() deliberately skips writing the crouch while this
	# move is current, so the entry frame kept showing the airborne view.
	#
	# The same one-logic-frame gap as SkillRollMove.enter(); milder here, since
	# it delays an effect rather than flashing a wrong value. It still lands on
	# the one frame of a hard landing anyone actually looks at.
	_drive_effects(1.0)

func physics_update(delta: float, _input: MoveInput) -> StringName:
	_elapsed += delta
	var t: float = clampf(_elapsed / maxf(config.landing.lockout_time, 0.0001), 0.0, 1.0)

	# Recovering, not holding: 1 at touchdown falling to 0 at release.
	_drive_effects(1.0 - t)

	player.velocity.y = -config.pawn.floor_snap_speed
	player.move_and_slide()
	player.set_grounded(player.is_on_floor())

	if t >= 1.0:
		return WALKING
	return KEEP

func exit() -> void:
	_drive_effects(0.0)

## The whole visible weight of the lockout, at `severity`: 1 at the impact and 0
## by the time it lets go. One place, because it is driven from three -- entry,
## every tick, and the hand-off -- and a channel written in only two of them is
## exactly the gap this move already had.
func _drive_effects(severity: float) -> void:
	if player.camera_rig != null:
		player.camera_rig.set_crouch_amount(severity)
		player.camera_rig.set_landing_pitch_offset(config.landing.camera_pitch_offset * severity)
	if player.screen_effects != null:
		player.screen_effects.set_tint(config.landing.tint_color, severity)
