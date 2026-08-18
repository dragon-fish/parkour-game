class_name SpeedVaultMove
extends ScriptedMove

# Vaulting DRIVES the body over an obstacle along a computed path instead of
# letting physics push it through — see the note on ScriptedMove above. The
# destination comes from Probes.vault_query()'s "top" hit, so it is known
# clear; nothing along the path itself is checked.

var _exit_speed: float = 0.0
var _exit_direction: Vector3 = Vector3.ZERO
## Set in enter() when the vault query comes back invalid: there is no probed
## top to land on, so physics_update() hands straight back to Walking without
## ever moving the body. See enter()'s note for what the old fallback did.
var _aborted: bool = false

func enter(_previous: StringName) -> void:
	# grounded is DECLARED, not read from is_on_floor(): this move never calls
	# move_and_slide(), so is_on_floor() would keep reporting whatever WalkingMove
	# left behind for the whole vault — stale coyote time, head bob, etc.
	player.set_grounded(false)
	_aborted = false

	# WalkingMove already null-checks player.probes AND requires a valid
	# vault_query() before ever transitioning here, so neither branch below is
	# reachable in normal play. They are kept as a guard for a future caller
	# that skips that gate -- but as a GENUINELY safe one. The previous version
	# fell back to `top = player.global_position`, which is not "nowhere to
	# land": the landing is then built as `top + forward * vault_exit_forward`
	# with `landing.y = top.y + standing_height/2`, so that fallback would have
	# driven the body 0.9 m up and 0.6 m forward, through whatever was there.
	# There is no safe destination to invent when the probe found nothing, so
	# invent none: abort the vault and hand back to Walking with the body
	# untouched and its velocity intact.
	var query: Dictionary = player.probes.vault_query() if player.probes != null else Probes.NO_HIT.duplicate()
	if not query["valid"]:
		_aborted = true
		return

	# WalkingMove/FallingMove only ever return SPEED_VAULT immediately after
	# populating this with a real match from SpeedVaultConfig.pick_variant()
	# (see their own lookahead check) -- so this should always be populated on
	# a legitimate entry. Same "invent nothing" reasoning as the invalid-probe
	# branch above: a caller that reached this move without going through
	# should_commit() has no variant to fall back to, only an abort.
	var variant: Dictionary = player.pending_vault_variant
	player.pending_vault_variant = {}
	if variant.is_empty():
		_aborted = true
		return

	var horizontal := Vector3(player.velocity.x, 0.0, player.velocity.z)
	# The sweet spot PAYS (+0.8 m/s); the high variants are clamped DOWN. This
	# is the opposite sign from this project's old flat 0.85 keep ratio, and
	# it is the whole reason the original's obstacles read as opportunities
	# rather than as taxes. Source: 05 §5.7 (see SpeedVaultConfig.variants'
	# own per-field sourcing on speed_addition/clamp_speed_min/clamp_speed_max).
	#
	# clamp_speed_max for the two sweet-spot rows is 7.2 -- exactly
	# PawnConfig.ground_speed, the player's own hard ceiling (confirmed
	# faithful to the source: ClampSpeedMax = 720 = GroundSpeed there too, so
	# this is not a retuning target). That means the bonus is invisible for any
	# entry at or above ground_speed: there is no "faster than your own top
	# speed" to grant. What it DOES give back is speed already LOST to a turn,
	# a rough landing, or friction since the last time the player was at cap --
	# the vault tops up a player who has bled speed, it does not create speed
	# that was never there. See tests/test_speed_vault_move.gd for both cases
	# (a mid-range entry that keeps the full bonus, and an at-cap entry where
	# the net gain is exactly zero) exercised through this exact formula.
	_exit_speed = clampf(horizontal.length() + variant["speed_addition"], \
		variant["clamp_speed_min"], variant["clamp_speed_max"])
	_exit_direction = horizontal.normalized() if horizontal.length_squared() > 0.0001 else -player.global_transform.basis.z

	var top: Vector3 = query["top"]
	var landing := top + _exit_direction * config.speed_vault.vault_exit_forward
	# Feet flush on the probed top -- NOT offset by variant.ledge_offset_z.
	# An earlier version of this line added ledge_offset_z here as extra
	# height above this placement, on the reasoning that WalkingMove's next
	# move_and_slide() floor-snaps the body regardless. Review found that
	# reasoning false for this codebase: WalkingMove's floor-snap is a small
	# downward bias (-floor_snap_speed) meant to keep contact across seams and
	# gentle slopes, not to recover from being unsupported by any real
	# distance -- PawnConfig.max_step_height's own comment is explicit that
	# Godot's floor_snap_length only holds a body down over gaps small enough
	# that a 5 cm plank once broke it (the reason try_step_up() exists at
	# all). A body left ledge_offset_z above a real surface -- 0.6-0.9 m for
	# two of the six variants -- does not snap back down; WalkingMove's own
	# grounded check fails and hands off to a visible multi-tick FALLING. See
	# SpeedVaultConfig.variants' own note on ledge_offset_z for why the field
	# is still recorded but left unread.
	landing.y = top.y + player.standing_height() * 0.5

	begin(player.global_position, landing, variant["duration"], config.speed_vault.vault_arc_height)
	player.velocity = Vector3.ZERO

func physics_update(delta: float, _input: MoveInput) -> StringName:
	if _aborted:
		return WALKING

	if advance(delta):
		player.velocity = _exit_direction * _exit_speed
		# Deliberately NOT declared grounded here. landing.y is pinned to the
		# probed obstacle TOP plus vault_exit_forward's un-probed horizontal
		# push -- past a thin obstacle that push can overshoot the obstacle's
		# own footprint into open air over the real floor, which the body has
		# never actually touched. Asserting grounded=true at that point was
		# exactly the bug review caught: it silently re-arms coyote time (a
		# jump buffered mid-vault would fire from mid-air) before WalkingMove's
		# OWN move_and_slide() gets a chance to check anything. Leaving it
		# false (unchanged from enter()) means WalkingMove's very next
		# floor-snap tick is what first calls set_grounded() for real, exactly
		# like every other transition into Walking (Falling, Slide) already
		# requires of itself. The cost is at most one tick of WalkingMove
		# running before grounded is confirmed -- harmless, since WalkingMove
		# always drives with ground_accelerate() regardless of this flag, so
		# no air control leaks in during that tick.
		return WALKING
	return KEEP
