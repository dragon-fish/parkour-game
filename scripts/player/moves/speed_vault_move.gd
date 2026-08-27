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
## How far this vault's bezier control point sits back over the start -- the only
## dial the shape has. See SpeedVaultConfig.vault_over_control_bias.
var _planned_bias: float = 0.0
## How far over that top the peak should go. See
## SpeedVaultConfig.vault_over_apex_above_top.
var _planned_apex_over_top: float = 0.0
## The obstacle's top, kept from the commit. The apex is worked out from it at
## CONTACT, because that is when the clip is settled -- see physics_update().
var _planned_top_y: float = 0.0
## How high the scripted arc bulges. A vault OVER rises far less than one ONTO,
## because it never gets on top of anything.
## The camera's fallback rise for this vault. Derived from the obstacle and
## aimed at the eye -- and since it only ever moves the eye now, that derivation
## is the whole of what it is. See ScriptedMove.camera_lift().
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
## it. Both are meant to look the same. [ME:CONFIRMED 05 §5.7] The original
## agrees from the other direction: its two step-up rows are the two with no
## hand IK at all. Nothing was planted because nothing had time to be.
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
	# DO NOT read it further down, past the probe guard -- that leaves
	# _variant_name unset on every abort, including a test with no obstacle in
	# the world. Both fields are one-shot channels: leaving them set would hand
	# this vault's identity to the next one.
	var variant: Dictionary = player.pending_vault_variant
	player.pending_vault_variant = {}
	_variant_name = String(variant.get("name", ""))
	_rescued = player.pending_vault_rescue
	player.pending_vault_rescue = false

	# ONLY A REAL VAULT FOLDS. DO NOT let the step-up variants fold/drop the
	# model -- a step-up only lifts a leg a little, so lowering the body just
	# makes it clip.
	#
	# [ME:CONFIRMED 05 §5.7] The original says the same thing from the other
	# side: autostepuprightleg and stepuprightleg88 are the two rows of six
	# with NO hand IK. There is no hand because there is no plant; the body
	# stays upright and steps. A body-over-the-hands vault folds, a step does
	# not.
	#
	# Gated on is_scramble(), which is the same question CharacterAnimator asks
	# to pick StepUp over SafetyVault -- so the capsule and the clip agree by
	# construction rather than by two lists being kept in step.
	#
	# DO NOT split StepUp into its own move state: [ME:CONFIRMED] the original
	# keeps all six variants in ONE move (TdMove_SpeedVault, six VaultTypes),
	# and SpeedVaultConfig.variants is a transcription of that table. The
	# behaviour that differs is per-variant, so it is expressed per-variant. A
	# separate state would only be justified by something beyond this -- its
	# own camera, its own transitions -- which is a bigger, separate change.
	if not is_scramble():
		# THE LEGS TUCK, so the body rides at the shortened capsule's TOP.
		#
		# DO NOT shrink the capsule while leaving the model anchored at the
		# soles -- that reads as the capsule getting shorter while the body
		# keeps standing inside it. The COLLISION shortens from the top with
		# the feet on the floor, exactly as it always has, and the MODEL AND
		# EYE drop by what the capsule lost. The head then sits on the new
		# crown, which is where a vaulting body's head actually is.
		#
		# crouch_capsule_height rather than a knob of its own: it is the height
		# this project already folds to for a slide and a roll, and one number
		# is one number to keep honest.
		player.set_capsule_height(config.crouch.crouch_capsule_height)
		player.set_body_folded(true)

	# WalkingMove already null-checks player.probes AND requires a valid
	# vault_query() before ever transitioning here, so neither branch below is
	# reachable in normal play. They are kept as a guard for a future caller
	# that skips that gate -- but as a GENUINELY safe one. DO NOT fall back to
	# `top = player.global_position` as a synthetic "nowhere to land" value:
	# the landing is built as `top + forward * vault_exit_forward` with
	# `landing.y = top.y + standing_height/2`, so that fallback drives the body
	# 0.9 m up and 0.6 m forward, through whatever is there. There is no safe
	# destination to invent when the probe found nothing, so invent none: abort
	# the vault and hand back to Walking with the body untouched and its
	# velocity intact.
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
	# [ME:CONFIRMED 05 §5.7] The sweet spot PAYS (+0.8 m/s); the high variants
	# are clamped DOWN -- which is why the original's obstacles read as
	# opportunities rather than as taxes. See SpeedVaultConfig.variants' own
	# per-field sourcing on speed_addition/clamp_speed_min/clamp_speed_max.
	#
	# [ME:CONFIRMED] clamp_speed_max for the two sweet-spot rows is 7.2 --
	# exactly PawnConfig.ground_speed, the player's own hard ceiling
	# (ClampSpeedMax = 720 = GroundSpeed in the source too, so this is not a
	# retuning target). That means the bonus is invisible for any
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
	# Feet flush on the probed top -- NOT offset by variant.ledge_offset_z. DO
	# NOT add ledge_offset_z here as extra height above this placement on the
	# assumption that WalkingMove's next move_and_slide() floor-snaps the body
	# regardless: WalkingMove's floor-snap is a small downward bias
	# (-floor_snap_speed) meant to keep contact across seams and gentle slopes,
	# not to recover from being unsupported by any real distance --
	# PawnConfig.max_step_height's own comment is explicit that Godot's
	# floor_snap_length only holds a body down over gaps small enough that a
	# 5 cm plank once broke it (the reason try_step_up() exists at all). A
	# body left ledge_offset_z above a real surface -- 0.6-0.9 m for two of the
	# six variants -- does not snap back down; WalkingMove's own grounded
	# check fails and hands off to a visible multi-tick FALLING. See
	# SpeedVaultConfig.variants' own note on ledge_offset_z for why the field
	# is still recorded but left unread.
	landing.y = top.y + player.standing_height() * 0.5

	# A VAULT *OVER* LANDS ON THE FAR SIDE, NOT ON THE OBSTACLE.
	#
	# DO NOT build a vault over the same way as an onto (feet flush on the
	# probed top): that hauls the body up to the obstacle's own top edge
	# instead of carrying it past. [ME:CONFIRMED docs/feel-backlog.md 27]
	# MEASURED: a VaultOver's peak sits 0.87 m BELOW the obstacle's top and the
	# feet never clear it at all -- it is a hands-on-top move that carries the
	# body PAST the obstacle, not over it.
	#
	# `vault_over` PICKS THE LANDING, not `standable`. Those are different
	# questions: `standable` asks whether the top is FLAT, which is true for
	# every box in the calibration course, so gating on it lands every vault
	# on the obstacle regardless. The question that matters is whether the top
	# is WIDE, and `vault_over` is already it -- the probe looks a body's reach
	# past the top and asks whether the ground there is LOWER. Lower means the
	# obstacle is thin enough to be carried past; level means it is a surface
	# to land on.
	#
	# This also fixes the duration complaint without touching the timing: an
	# arc that ends on the far side spans the descent as well, so it covers the
	# whole manoeuvre instead of stopping at the top and dropping.
	var far_point: Vector3 = query.get("far_point", Vector3.ZERO)
	var is_onto: bool = not bool(query.get("vault_over", false))
	if not is_onto:
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
	# WORKED OUT NOW, SPENT AT CONTACT.
	#
	# [ME:CONFIRMED] MaxDistanceTime is a confirmed field, so the original does
	# commit before touching anything -- but a commit is the animation winding
	# up, not the body being moved. begin()ing here would interpolate from
	# wherever the commit happened, which at 7 m/s and MaxDistanceTime 0.2 s is
	# 1.4 m short of the obstacle: a metre and a half of being dragged through
	# open air.
	#
	# [ME:CONFIRMED] The vault visibly starts a little LATER than the press,
	# with the hands and feet still meeting the geometry and a fraction of a
	# second of IK-ish blending covering the difference -- you can see Faith's
	# own limbs in the original, so anything else reads as floating. See
	# docs/contact-drives-movement.md.
	#
	# ONE SHAPE, ONE DIAL: the pull-up's bezier is the only curve now, reused
	# directly from GrabMove's own rule rather than a separate one; all a
	# variant chooses is how far its control point sits back over the start.
	_planned_bias = config.speed_vault.vault_onto_control_bias if is_onto 		else config.speed_vault.vault_over_control_bias
	# WHERE THE PELVIS SHOULD PASS cannot be read off the two ends alone: the
	# game needs a different height every time, but the animator made one
	# animation for one height, so the height difference between the arc's
	# peak and the obstacle must track whatever that clip's own pelvis lift is.
	#
	# SO THE NUMBER COMES FROM THE CLIP, not from a knob. Player.
	# body_clip_hip_peaks measures how far each clip lifts its own hips above
	# rest -- SafetyVault 0.732 m, StepUp 0.226, ClimbUp_1m 0.193 -- which IS the
	# animator's own answer to "how far over the obstacle does the body go". Held
	# over the top, it scales to every obstacle height without anyone tuning it,
	# and it follows the animation pack rather than this project's taste.
	_planned_top_y = top.y
	_planned_apex_over_top = config.speed_vault.vault_onto_apex_above_top if is_onto 		else config.speed_vault.vault_over_apex_above_top
	_landing = landing

	# A VAULT MUST NOT BE SLOWER THAN JUST RUNNING THERE.
	#
	# [ME:CONFIRMED] The variant's own duration is confirmed (VaultTimeUp +
	# Over + Down), but it is a fixed TIME, and it is paired in the original
	# with the original's own fixed geometry. Applied to whatever distance
	# this obstacle happens to need, it drags: cross 3 m in 0.65 s and a
	# player who arrived at 7 m/s is visibly held back for the whole vault and
	# then handed their speed back at the end -- worse once a vault OVER lands
	# on the far side, since the distance grows while the fixed time does not.
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
			# THE HIPS GIVE UP THEIR OWN LIFT, ALWAYS: there is one shape now
			# and it is the path's, so a clip that also lifted would double-
			# count the height.
			player.set_clip_lift_kept(0.0)
			# DO NOT ask for the clip at the commit -- it lands on whatever was
			# playing a moment before the vault (Jump_Start, most of the time),
			# which is not in the table, so the apex degrades to the obstacle's
			# top exactly and the pelvis grazes it.
			#
			# THE ARC'S PEAK MUST ALWAYS CLEAR THE OBSTACLE. The clip's own hip
			# peak is what makes it so, and it is measured per clip at attach:
			# SafetyVault 0.732 m, StepUp 0.226, ClimbUp_1m 0.193.
			var apex_y: float = _planned_top_y + _planned_apex_over_top
			begin(player.global_position, _landing, _arc_duration,
					apex_y, _planned_bias,
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
	# NOT FOR A STEP-UP: the bank is the camera's half of a one-handed plant,
	# and a step-up has no hand in it -- the same reason it plays StepUp
	# rather than SafetyVault, and the same reason it does not fold. All three
	# questions are is_scramble().
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
		# never actually touched. DO NOT assert grounded=true at that point:
		# it silently re-arms coyote time (a jump buffered mid-vault would
		# fire from mid-air) before WalkingMove's OWN move_and_slide() gets a
		# chance to check anything. Leaving it false (unchanged from enter())
		# means WalkingMove's very next floor-snap tick is what first calls
		# set_grounded() for real, exactly
		# like every other transition into Walking (Falling, Slide) already
		# requires of itself. The cost is at most one tick of WalkingMove
		# running before grounded is confirmed -- harmless, since WalkingMove
		# always drives with ground_accelerate() regardless of this flag, so
		# no air control leaks in during that tick.
		return WALKING
	return KEEP
