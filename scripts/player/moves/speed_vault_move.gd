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
## The camera's fallback rise for this vault. Derived from the obstacle and
## aimed at the eye -- and since it only ever moves the eye now, that derivation
## is the whole of what it is. See ScriptedMove.camera_lift().
## The clearance this vault needs, derived from the obstacle. Feeds TWO things
## now: how much of the clip's own hip lift to keep (the body's rise), and the
## camera's fallback lift for a body with no model to follow.
var _planned_clearance: float = 0.0
## How far the rise leads the travel for THIS vault -- the shape, not the size.
## See SpeedVaultConfig.vault_onto_vertical_lead.
var _planned_lead: float = 0.0
## The world height the pelvis should pass through, settled at the commit from
## the obstacle alone. The bump that reaches it is worked out at contact.
var _planned_apex_y: float = 0.0
var _touched: bool = false
## Where the obstacle's face was when the commit was made. See Move.touching().
var _face_point: Vector3 = Vector3.ZERO
var _approach_time: float = 0.0
## The variant this vault resolved to, kept after enter() consumes the handoff.
## Read by CharacterAnimator, the same way it reads GrabMove.is_mantling().
var _variant_name: String = ""
## True when the entry only happened because the falling-rescue window was
## open. See AirborneMove._vault_speed_z().
var _rescued: bool = false

## True when this vault was SCRAMBLED rather than set up: either it resolved to
## one of the step-up rows, or it only happened because the falling rescue let
## it. ✅ The owner asked for both to look the same -- and the original agrees
## from the other direction, since its two step-up rows are the two with no
## hand IK at all (05 §5.7). Nothing was planted because nothing had time to be.
func is_scramble() -> bool:
	return _rescued or _variant_name.begins_with("step_up")  or _variant_name.begins_with("auto_step_up")

func enter(_previous: StringName) -> void:
	# grounded is DECLARED, not read from is_on_floor(): this move never calls
	# move_and_slide(), so is_on_floor() would keep reporting whatever WalkingMove
	# left behind for the whole vault — stale coyote time, head bob, etc.
	player.set_grounded(false)
	_aborted = false
	# THE CODE OWNS THE HEIGHT HERE, so the clip must not add its own. Every
	# variant, step-ups included -- the arc carries the body in all six cases,
	# and SafetyVault alone lifts the hips 0.825 m on top of it. See
	# Player.set_clip_lift_cancelled().
	player.set_clip_lift_cancelled(true)


	# THE HANDOFF IS CONSUMED FIRST, before any of the abort paths below.
	# ⚠️ It used to be read further down, past the probe guard, and that made
	# _variant_name unset on every abort -- which is also how it read in a test
	# with no obstacle in the world. Both fields are one-shot channels: leaving
	# them set would hand this vault's identity to the next one.
	var variant: Dictionary = player.pending_vault_variant
	player.pending_vault_variant = {}
	_variant_name = String(variant.get("name", ""))
	_rescued = player.pending_vault_rescue
	player.pending_vault_rescue = false

	# ONLY A REAL VAULT FOLDS. ✅ The owner: the step-up variants drop the model
	# too, and they must not -- "that one only lifts a leg a little, and
	# lowering the body just makes it clip."
	#
	# The original says the same thing from the other side: autostepuprightleg
	# and stepuprightleg88 are the two rows of six with NO hand IK (05 §5.7).
	# There is no hand because there is no plant; the body stays upright and
	# steps. A body-over-the-hands vault folds, a step does not.
	#
	# Gated on is_scramble(), which is the same question CharacterAnimator asks
	# to pick StepUp over SafetyVault -- so the capsule and the clip agree by
	# construction rather than by two lists being kept in step.
	#
	# ⚠️ The owner suggested splitting StepUp into its own state for this. Not
	# done, and worth saying why: the original keeps all six in ONE move
	# (TdMove_SpeedVault, six VaultTypes) and SpeedVaultConfig.variants is a
	# transcription of that table. The behaviour that differs is per-variant, so
	# it is expressed per-variant. If a separate state is wanted for reasons
	# beyond this -- its own camera, its own transitions -- that is a bigger
	# change and a separate one.
	if not is_scramble():
		# THE LEGS TUCK, so the body rides at the shortened capsule's TOP.
		#
		# ✅ The owner, twice, and the second time is the one I had to hear:
		# "the capsule should shrink hugging the FEET -- but the model and the
		# eye should come down with it, instead of the capsule getting shorter
		# while the model goes on playing anchored at the soles. The model's
		# head should be anchored to the capsule's top."
		#
		# So: the COLLISION shortens from the top with the feet on the floor,
		# exactly as it always has, and the MODEL AND EYE drop by what the
		# capsule lost. The head then sits on the new crown, which is where a
		# vaulting body's head actually is.
		#
		# crouch_capsule_height rather than a knob of its own: it is the height
		# this project already folds to for a slide and a roll, and one number
		# is one number to keep honest.
		player.set_capsule_height(config.crouch.crouch_capsule_height)
		player.set_body_folded(true)

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
	var arc: float = config.speed_vault.vault_camera_arc
	# ⚠️ THE APEX IS GEOMETRY; THE ARC IS NOT. Where the pelvis should pass is a
	# fact about the obstacle and can be settled now. How big a bump reaches it
	# depends on where the body IS when the move starts -- and this runs at the
	# COMMIT, while begin() runs at CONTACT, with the body still rising in
	# between. Deriving the bump here made the apex land 0.056 m high on a knob
	# set to 0.2, which is enough to make tuning by eye lie.
	var apex_y: float = 0.0
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
	if bool(query.get("vault_over", false)):
		if far_point == Vector3.ZERO:
			# AN OVER WITH NOWHERE TO LAND: a thin obstacle with a drop beyond
			# deeper than a vault reaches. See Probes._query_vault_over().
			#
			# Carried PAST the far face at the top's own height and released.
			# There is no landing to aim at, so none is invented -- the move
			# ends airborne, physics_update() returns FALLING because the body
			# is not grounded, and gravity does the rest. Which is what happens
			# to a person who vaults a fence over a stairwell.
			landing = top + _exit_direction * (config.speed_vault.vault_over_probe_distance
					+ config.speed_vault.vault_exit_forward)
			landing.y = top.y + player.standing_height() * 0.5
		else:
			landing = far_point + _exit_direction * config.speed_vault.vault_exit_forward
			landing.y = far_point.y + player.standing_height() * 0.5
		# ✅ THE APEX IS SET, NOT DERIVED. THE OWNER, after several derivations
		# missed: "我们直接来调弧线的最高点，每种动作变体对应一种...Vault动画，最高点调
		# 整为障碍顶端+0.45m."
		#
		# 📌 IT IS THE PELVIS THAT PASSES THERE, and that is what makes 0.45 mean
		# something. The hips are pinned to the capsule's centre, and a folded
		# capsule's centre sits about 0.45 above its own feet -- so "centre 0.45
		# over the top" is "feet grazing the top". docs/feel-backlog.md 27
		# measured the original's FEET at 0.87 BELOW the top; those two numbers
		# are not in the same frame of reference, and this is the one that can be
		# watched on screen.
		#
		# ⚠️ A SYMMETRIC BUMP PEAKS IN THE MIDDLE of the straight line between the
		# ends, so the arc wanted is the gap from that middle up to the apex.
		apex_y = top.y + config.speed_vault.vault_over_apex_above_top
		# ⚠️ SET WHERE THE ARC IS, not somewhere else that asks the same question
		# again. It WAS asked again, in commit(), against a `query` that did not
		# carry the answer -- so an over took the ONTO shape, whose crossing
		# height is max(from, to) rather than the line's middle, and every apex
		# came out 0.05 m high. Measured 1.501 where 1.450 was asked for, and
		# 1.006 + 0.497 says exactly which formula produced it.
		_planned_lead = config.speed_vault.vault_vertical_lead
	else:
		# ⚠️ THE OTHER SHAPE, THE OTHER RULE. ✅ "StepUp动画，最高点调整为障碍顶端
		# +0.9m." A vault ONTO runs on the composite path, whose crossing height
		# is max(from, to) rather than the line's middle -- so the arc wanted is
		# the gap from THAT up to the apex, and it is zero whenever the landing
		# is already the highest point, which for a step onto a flat top it is.
		apex_y = top.y + config.speed_vault.vault_onto_apex_above_top
		_planned_lead = config.speed_vault.vault_onto_vertical_lead

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
	_planned_clearance = arc
	_planned_apex_y = apex_y

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
	_arc_duration = clampf(by_travel,
			variant["duration"] * config.speed_vault.duration_floor_pct,
			variant["duration"])
	_face_point = query.get("face_point", Vector3.ZERO)
	_touched = false
	_approach_time = 0.0

## HANDS THE BANK BACK. The rig decays nothing on its own, and this move writes
## its roll from sin(PI * progress()) BEFORE advance() moves the clock -- so the
## last value it ever writes is taken a tick short of the end, around
## sin(0.95 PI) rather than sin(PI). Without this the residual stayed on the rig
## for good: every vault left the horizon banked a fraction of a degree until
## some later vault happened to overwrite it.
##
## Same class as the roll's entry flicker, at the other end of a move: a
## presentational channel borrowed and not returned. SkillRollMove.exit() does
## the same for its own two.
func exit() -> void:
	# The same REQUEST, not an unconditional restore, that Slide, Crouch and
	# SkillRoll use: a vault can end under something low, and standing up into
	# it would put the capsule inside it. Player owes the restore and performs
	# it on the first tick there is room.
	player.request_standing_capsule()
	player.set_body_folded(false)
	player.set_clip_lift_cancelled(false)
	if player.camera_rig != null:
		player.camera_rig.set_vault_roll(0.0)

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
			# THE RISE LEADS THE TRAVEL -- see SpeedVaultConfig.vault_vertical_lead.
			# A symmetric bump peaks half way ALONG the journey, and the obstacle is
			# at the near end of it.
			# ⚠️ THE CLIP'S OWN RISE, SCALED TO THIS OBSTACLE, and set here rather
			# than on entry because the clip is only settled once the animator
			# has seen the move. Keeping all of it is the animator's wall;
			# keeping none is the flat pin that left the body too low. See
			# Player.body_clip_hip_peaks.
			# NOTHING KEPT WHEN THE PATH ITSELF ARCS: the rise is the capsule's
			# in that mode, and adding the clip's on top is the double-count.
			player.set_clip_lift_kept(0.0 if config.scripted_path_arcs
					else player.clip_lift_kept_for(
						player._current_clip(), _planned_clearance))
			# THE BUMP, WORKED OUT NOW, from where the body actually is.
			# A symmetric bump peaks at the middle of the straight line; the
			# composite crosses at the higher end. Same apex, different base.
			var base: float = (player.global_position.y + _landing.y) * 0.5
			if _planned_lead > 0.0:
				base = maxf(player.global_position.y, _landing.y)
			if _planned_apex_y > 0.0:
				# THE FLOOR, applied here rather than at the commit because it is
				# measured from where the body ACTUALLY starts.
				var apex: float = maxf(_planned_apex_y, player.global_position.y
						+ config.speed_vault.vault_min_rise_above_start)
				_planned_clearance = maxf(0.0, apex - base)
			begin(player.global_position, _landing, _arc_duration, _planned_clearance,
					_planned_lead,
					config.speed_vault.vault_path_ease)
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
	# ✅ NOT FOR A STEP-UP, on the owner's call: "the StepUp action does not need
	# to rotate the screen." The bank is the camera's half of a one-handed
	# plant, and a step-up has no hand in it -- which is the same reason it
	# plays StepUp rather than SafetyVault, and the same reason it does not
	# fold. All three questions are is_scramble().
	if player.camera_rig != null and not is_scramble():
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
