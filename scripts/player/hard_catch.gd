class_name HardCatch
extends RefCounted

# A catch that stops a fall past hard_landing_height costs the same lockout a
# hard landing does: the red screen, and the body pinned with no input.
# [ME:CONFIRMED] for a ladder caught mid-fall, and for a ledge.
#
# Reads config.landing rather than owning dials of its own: this IS the hard
# landing's own stun, so one number drives both and the two cannot drift apart.
# The camera dip is deliberately NOT copied: the hands are holding on, so there
# are no knees to buckle.
#
# [ME:UNKNOWN] whether the lockout can be released early -- nothing about the
# way out of it was read off the original. The body is pinned outright,
# matching LandingMove, which refuses every input for its whole span.
#
# `player` is untyped for the reason Move.player is: Player -> moves must stay
# one-directional at parse time.

## Seconds of lockout still owed, 0 when there is none.
var left: float = 0.0

## Arms the lockout from the fall the hands just stopped. Called from the
## catching move's enter(), which MoveManager runs mid-tick without running
## that move's physics_update() -- so the tint is set here too, or it arrives a
## frame late on the one frame of a hard catch anyone actually looks at.
func arm(player) -> void:
	if player.fall_tracker.fall_height < player.config.pawn.hard_landing_height:
		left = 0.0
		return
	left = player.config.landing.lockout_time
	_drive_effects(player)

## Advances the lockout. True while it still holds, in which case the caller
## replaces this tick's input with a neutral one -- a fresh MoveInput, the way
## FallUncontrolledMove refuses input -- so every action is refused at once
## without any of them growing a gate of its own.
func tick(player, delta: float) -> bool:
	if left <= 0.0:
		return false
	left = maxf(0.0, left - delta)
	_drive_effects(player)
	return true

## Drops any lockout still running and takes the red down with it. From the
## catching move's exit().
func clear(player) -> void:
	left = 0.0
	if player.screen_effects != null:
		player.screen_effects.set_tint(player.config.landing.tint_color, 0.0)

## The red at the severity the remaining lockout implies: 1 at the catch, 0 as
## it lets go. Same colour and curve as LandingMove._drive_effects().
func _drive_effects(player) -> void:
	if player.screen_effects == null:
		return
	var severity: float = left / maxf(player.config.landing.lockout_time, 0.0001)
	player.screen_effects.set_tint(player.config.landing.tint_color, clampf(severity, 0.0, 1.0))
