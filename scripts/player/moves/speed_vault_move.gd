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
## Where the arc will land, and how long it takes. Worked out at COMMIT, from
## the obstacle the probe found; spent at CONTACT, from wherever the body has
## actually got to by then. See docs/contact-drives-movement.md.
var _landing: Vector3 = Vector3.ZERO
var _arc_duration: float = 0.0
## How high the scripted arc bulges. A vault OVER rises far less than one ONTO,
## because it never gets on top of anything.
var _arc_height: float = 0.0
var _touched: bool = false
## Where the obstacle's face was when the commit was made. See Move.touching().
var _face_point: Vector3 = Vector3.ZERO
var _approach_time: float = 0.0

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

	# A VAULT *OVER* LANDS ON THE FAR SIDE, NOT ON THE OBSTACLE.
	#
	# Everything above builds an ONTO: feet flush on the probed top. Applied to
	# a vault over as well -- which is what this move did -- the body is hauled
	# up to the obstacle's own top edge, which the owner described exactly:
	# "ours is the foot catching and then the body being lifted to the top edge,
	# where the original traces a graceful arc over it".
	#
	# ✅ MEASURED: a VaultOver's peak sits 0.87 m BELOW the obstacle's top and
	# the feet never clear it at all (docs/feel-backlog.md 27). It is a
	# hands-on-top move that carries the body PAST the obstacle, not over it.
	var arc: float = config.speed_vault.vault_arc_height
	# `vault_over` PICKS THE LANDING, not `standable`.
	#
	# Those are different questions and the first attempt used the wrong one.
	# `standable` asks whether the top is FLAT; every box in the calibration
	# course has a flat top, so it was always true and every vault landed on the
	# obstacle. The owner: "ours all end at the obstacle's top edge, where the
	# original's vault-overs carry on until they are nearly on the ground."
	#
	# The question that matters is whether the top is WIDE, and `vault_over` is
	# already it: the probe looks a body's reach past the top and asks whether
	# the ground there is LOWER. Lower means the obstacle is thin enough to be
	# carried past; level means it is a surface to land on.
	#
	# Fixing this fixes the duration complaint too, without touching the timing.
	# An arc that ends on the far side spans the descent as well, so it covers
	# the whole manoeuvre instead of stopping at the top and dropping.
	var far_point: Vector3 = query.get("far_point", Vector3.ZERO)
	if bool(query.get("vault_over", false)) and far_point != Vector3.ZERO:
		landing = far_point + _exit_direction * config.speed_vault.vault_exit_forward
		landing.y = far_point.y + player.standing_height() * 0.5
		arc = config.speed_vault.vault_over_arc_height

	# WORKED OUT NOW, SPENT AT CONTACT.
	#
	# MaxDistanceTime is a confirmed field, so the original does commit before
	# touching anything -- but a commit is the animation winding up, not the
	# body being moved. begin()ing here would interpolate from wherever the
	# commit happened, which at 7 m/s and MaxDistanceTime 0.2 s is 1.4 m short
	# of the obstacle: a metre and a half of being dragged through open air.
	#
	# The owner put the whole principle plainly, and confirmed the timing from
	# play: the vault visibly starts a little LATER than the press, with the
	# hands and feet still meeting the geometry and a fraction of a second of
	# IK-ish blending covering the difference. You can see Faith's own limbs in
	# the original, so anything else reads as floating. See
	# docs/contact-drives-movement.md.
	_landing = landing
	_arc_height = arc

	# A VAULT MUST NOT BE SLOWER THAN JUST RUNNING THERE.
	#
	# The variant's own duration is ✅ confirmed (VaultTimeUp + Over + Down), but
	# it is a fixed TIME, and it is paired in the original with the original's
	# own fixed geometry. Applied to whatever distance this obstacle happens to
	# need, it drags: cross 3 m in 0.65 s and a player who arrived at 7 m/s is
	# visibly held back for the whole vault and then handed their speed back at
	# the end. The owner felt it as "sometimes a bit slow", and this commit's
	# own change made it worse -- a vault OVER now lands on the FAR side, so the
	# distance grew while the time did not.
	#
	# Same lesson IntoGrabMove learned: a manoeuvre that covers ground should
	# take the time the ground takes, and the duration falls out of the geometry
	# rather than being declared.
	#
	# The confirmed figure stays the CEILING, so a slow approach still gets the
	# original's own timing. Floored at half of it so a fast one is brisk rather
	# than instantaneous -- there is a manoeuvre happening, and it has to be
	# visible.
	var carried: float = maxf(horizontal.length(), 0.5)
	var by_travel: float = player.global_position.distance_to(landing) / carried
	_arc_duration = clampf(by_travel, variant["duration"] * 0.5, variant["duration"])
	_face_point = query.get("face_point", Vector3.ZERO)
	_touched = false
	_approach_time = 0.0

func physics_update(delta: float, _input: MoveInput) -> StringName:
	if _aborted:
		return WALKING

	# THE APPROACH. Committed, winding up, and not yet touching anything -- so
	# nothing moves the body but the body's own momentum.
	if not _touched:
		_approach_time += delta
		if touching(_face_point):
			_touched = true
			# From where the body ACTUALLY IS, which is the whole point.
			begin(player.global_position, _landing, _arc_duration, _arc_height)
			player.velocity = Vector3.ZERO
		elif _approach_time >= config.speed_vault.approach_timeout:
			# The contact the commit predicted never arrived -- jumped short, or
			# the obstacle turned out to be somewhere else. Handing back is
			# honest; waiting in the air is not.
			player.set_grounded(player.is_on_floor())
			return WALKING if player.grounded else FALLING
		else:
			carry_ballistically(delta)
			return KEEP

	# A slight bank through the arc, peaking in the middle and gone by the end.
	# sin() rather than a ramp: a vault that ended still leaning would hand a
	# tilted horizon to whatever came next.
	if player.camera_rig != null:
		# LEANS ONE WAY, ALWAYS. A vault is a one-handed move -- the same hand
		# every time in the original -- so the bank has a side rather than being
		# derived from the geometry. Positive is a lean to the right.
		player.camera_rig.set_vault_roll(
			sin(PI * progress()) * deg_to_rad(config.camera.vault_roll_deg))

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
