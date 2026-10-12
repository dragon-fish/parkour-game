class_name StumbleHardMove
extends StumbleMove

# The original's TdMove_StumbleHard, ported. [ME:CONFIRMED decompile] The
# second swing of a melee combo (MA_StumbleHard): whatever the hit, the body
# reels back GetHitStumbleBwdFar2's 2.5 m as root motion, and the animation's
# end (1.63 s) hands back to Walking. Its 0.8 s timer finds no animation it
# ends on and does nothing.

func _play_stumble_animation() -> void:
	_facing = player.pawn_facing()
	_anim_time = 0.0
	_ends_on_timer = false
	player.use_root_motion(true)
	_clip = RootMotionClip.stumble_hard()
	_anim_length = _clip.length
	set_timer(0.8)
