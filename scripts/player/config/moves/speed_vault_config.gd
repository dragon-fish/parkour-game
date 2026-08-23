class_name SpeedVaultConfig
extends MoveConfig

func _init() -> void:
	# LEGS BUSY: no spare limbs to spin on. See MoveConfig.allows_turn.
	allows_turn = false  # legs busy: hands and feet are both on the obstacle.

# The Godot counterpart of the original's TdMove_SpeedVault.

## How far ahead of the body the vault probe reaches.
@export var vault_reach: float = 1.4
## How far past the obstacle top the vault places the player.
##
## NOTE (transit speed): duration (per-variant now, see `variants` below) does
## not scale with how far the body actually travels, so at a variant's own
## entry-speed floor the body crosses a long path in the same fixed time as a
## short one — around the middle of the move it can be travelling several
## times faster than the approach speed even though the EXIT speed (variant
## clamp) may be a net loss for the high variants. Not a correctness bug
## (nothing reads a mid-vault speed), just a visible fact about this design
## worth knowing before retuning either knob.
@export var vault_exit_forward: float = 0.6
## Peak height of the vertical arc ScriptedMove.advance() adds over the
## straight line from vault start to landing, so the body reads as rising
## over the obstacle instead of clipping through it.
@export var vault_arc_height: float = 0.0
## How far past the obstacle's far face to look for somewhere to land, which
## is what decides vault-OVER from vault-ONTO. The original expresses this as
## the bCheckForVaultOver probe on TdPhysicsMove (06 §6.2) rather than as a
## distance, so this number is ours: half the body's own depth is enough to
## tell "there is floor on the other side" from "this thing is thick".
@export var vault_over_probe_distance: float = 0.5

## Source: 05 §5.7 `TdMove_SpeedVault.VaultTypes`. ✅ All six confirmed
## variants, converted to metric (1 uu = 1 cm; a `*_speed_z` field is
## uu/s -> m/s the same way). ORDER IS SIGNIFICANT: pick_variant() takes the
## FIRST match, and ❓ the original's own precedence rule needs bytecode to
## recover (05 §5.7's own "未知：多个变体同时匹配时的优先级规则" callout) --
## so the high-momentum variants are listed ahead of the low-momentum ones.
## That ordering is what makes "running fast unlocks the better move" true,
## and it also resolves the 3 cm height overlap the raw data itself has
## between vaultOnto/vaultOver's MaxHeight = 148 uu and VaultOverHigh/
## VaultOntoHigh's MinHeight = 145 uu: in that sliver, a fast RISING approach
## still gets the sweet-spot treatment rather than the high-variant
## punishment, because vault_over/vault_onto are checked first.
##
## TWO DIFFERENT SPEED CONCEPTS, deliberately separate fields -- 05 §5.7 ②
## reads them as different things and conflating them makes the table
## unsatisfiable:
##   entry_speed_min / entry_speed_max  ENTRY GATE. Which variant this
##       approach is allowed to trigger. `stepuprightleg88` is gated by
##       MaxMomentum = 200 uu/s (an UPPER bound: walk up to it and you climb),
##       `vaultOnto`/`vaultOver` by ClampSpeedMin = 400 uu/s (a LOWER bound:
##       run at it and you speed-vault).
##   clamp_speed_min / clamp_speed_max  OUTPUT CLAMP. What the move does to
##       your speed once it is running. Only the two high variants use this as
##       a genuine floor-and-ceiling squeeze (05 §5.7: "钳到 200-400" ✅); the
##       other four leave clamp_speed_min at 0.0 -- a no-op floor, since their
##       own entry gate already bounds the speed that can arrive here -- and
##       use clamp_speed_max only as a ceiling. ⚠️ Own reading: the source
##       data never actually separates "the speed required to enter" from
##       "the speed you are held to" for those four the way it does for the
##       two explicitly gated by MaxMomentum/ClampSpeedMin above.
##
## PER-FIELD SOURCING (05 §5.7's full variant table + its own timing table +
## its LedgeOffset.Z list; every entry below is ✅ read directly off the
## decompile unless marked otherwise):
##   name                    This project's own identifier -- the original's
##       animation/struct name, minus the Td prefix and the VaultTypes array.
##   min_height / max_height MinHeight/MaxHeight, uu -> m. ✅ autostepuprightleg
##       0-48, stepuprightleg88 48-148, vaultOnto/vaultOver 64-148,
##       VaultOverHigh/VaultOntoHigh 145-192.
##   vault_onto              bVaultOnto. ✅ concept confirmed; see
##       pick_variant()'s own comment for how this project reads it (an OVER
##       variant needs the incoming vault_over probe result to be true; an
##       ONTO variant is always admissible regardless of it).
##   min_speed_z / max_speed_z  MinSpeedZ/MaxSpeedZ, uu/s -> m/s. ✅ every MIN
##       bound and every variant's MAX except the two highs':
##       autostepuprightleg -6.0~0.0 (falling/level only), stepuprightleg88
##       0.0~7.0 (rising only), vaultOnto/vaultOver 0.0~100.0 (source gives
##       0~10000 uu/s, i.e. no real ceiling in either direction "not falling"
##       -- 100.0 m/s is this project's own stand-in for that). The two high
##       variants only state "MinSpeedZ >= 50" (0.5 m/s) with no upper bound
##       in the source; max_speed_z = 100.0 there is the same ⚠️ stand-in.
##   entry_speed_min / entry_speed_max  See the two-concepts note above. ✅ for
##       stepuprightleg88's 2.0 (MaxMomentum = 200) and vaultOnto/vaultOver's
##       4.0 (ClampSpeedMin = 400). ⚠️ Own choice: the INF upper bounds (no raw
##       entry ceiling exists in the source beyond the output clamp), and
##       autostepuprightleg's 1.0-3.0, which reuses its single raw ClampSpeed
##       range (100-300 uu/s) as an entry gate since the source does not split
##       an entry threshold out separately for this variant the way it does
##       for stepuprightleg88's MaxMomentum.
##   clamp_speed_min / clamp_speed_max  See the two-concepts note above. ✅
##       VaultOverHigh/VaultOntoHigh's 2.0-4.0 ("钳到 200-400"); vaultOnto/
##       vaultOver's 7.2 ceiling (`ClampSpeedMax = 720`, "恰好等于 GroundSpeed
##       上限"). ⚠️ Own choice: every other clamp_speed_min (all four non-high
##       rows, left at 0.0) is a no-op floor, not a raw value -- see the
##       two-concepts note.
##   speed_addition          SpeedAddition. ✅ +80 uu/s -> +0.8 m/s, ONLY on
##       vaultOnto/vaultOver. 0.0 elsewhere is not itself a stated value in
##       the source; it follows from SpeedAddition simply never being
##       mentioned for the other four rows.
##   duration                Sum of the source's own VaultTimeUp+Over+Down
##       timing table. ✅ 0.50 / 0.65 / 0.65 / 0.65 / 1.03 / 1.17 s.
##   max_distance_time       MaxDistanceTime. ✅ 0.2 s (autostepuprightleg
##       only), 0.4 s (the other five) -- see should_commit()'s own comment
##       for why this is a TIME despite its name, not the distance it claims.
##   is_stringable            bIsStringable. ✅ true only on vaultOnto/vaultOver
##       ("只有它们能连进 movement string"). Nothing in this project's Move
##       layer reads it yet -- recorded for a future movement-string task,
##       the same status MoveConfig.min_look_constraint carried before
##       CameraRig.apply_look() caught up to it.
##   reset_camera             bResetCamera. ✅ true only on the two high
##       variants ("强制重置镜头朝向，打断玩家的视线规划"). Nothing in this
##       project's CameraRig reads it yet, recorded for the same reason as
##       is_stringable above.
##   ledge_offset_z           LedgeOffset.Z. ✅ as a value -- 0.9 / 0.6 / 0.25 /
##       0.25 / 0.05 / 0.35 m, read directly off 05 §5.7's own list -- ❓ as a
##       role, same status as PawnConfig.speed_max_base_velocity. The
##       research reads this as a height offset of the landing point relative
##       to the edge, but the values are dimensionally impossible as a
##       landing ELEVATION for a human capsule (0.9 m of extra height on a
##       variant whose own obstacles top out at 0.48 m would land the player
##       nearly a metre above a knee-high box, with no real support under
##       them -- see SpeedVaultMove.enter()'s own note on why this codebase's
##       floor-snap cannot absorb that). An earlier version of this project
##       added it to the landing height on that literal reading; review found
##       the landing floats and does not recover, so it is recorded here but
##       deliberately left unread rather than shipped on a guess about which
##       frame it is actually expressed in.
@export var variants: Array[Dictionary] = [
	{
		# ⚠️ min_height RAISED FROM THE CDO's 0.64 TO THE WAIST. ✅ The owner:
		# "a lot of heights that visually just need a step get the hand plant
		# instead, and the hand is nowhere near the surface."
		#
		# 05 §5.7's raw figure is 64 uu = 0.64 m, and the classification rule
		# 05 §27 converged on is not a height at all -- it is a place on the
		# BODY: "hands above the waist, thin things get crossed". The waist is
		# 0.9 m, the same figure crouch_capsule_height uses, so the two rows
		# that plant a hand start there and the step-up owns everything below.
		#
		# Recorded as a divergence from the transcription, not folded into it.
		"name": "vault_over", "min_height": 0.9, "max_height": 1.48,
		"vault_onto": false, "min_speed_z": 0.0, "max_speed_z": 100.0,
		"entry_speed_min": 4.0, "entry_speed_max": INF,
		"clamp_speed_min": 0.0, "clamp_speed_max": 7.2,
		"speed_addition": 0.8, "duration": 0.65, "max_distance_time": 0.4,
		"is_stringable": true, "reset_camera": false, "ledge_offset_z": 0.25,
	},
	{
		# Raised with vault_over above -- see its note.
		"name": "vault_onto", "min_height": 0.9, "max_height": 1.48,
		"vault_onto": true, "min_speed_z": 0.0, "max_speed_z": 100.0,
		"entry_speed_min": 4.0, "entry_speed_max": INF,
		"clamp_speed_min": 0.0, "clamp_speed_max": 7.2,
		"speed_addition": 0.8, "duration": 0.65, "max_distance_time": 0.4,
		"is_stringable": true, "reset_camera": false, "ledge_offset_z": 0.25,
	},
	{
		"name": "vault_over_high", "min_height": 1.45, "max_height": 1.92,
		"vault_onto": false, "min_speed_z": 0.5, "max_speed_z": 100.0,
		"entry_speed_min": 0.0, "entry_speed_max": INF,
		"clamp_speed_min": 2.0, "clamp_speed_max": 4.0,
		"speed_addition": 0.0, "duration": 1.03, "max_distance_time": 0.4,
		"is_stringable": false, "reset_camera": true, "ledge_offset_z": 0.05,
	},
	{
		"name": "vault_onto_high", "min_height": 1.45, "max_height": 1.92,
		"vault_onto": true, "min_speed_z": 0.5, "max_speed_z": 100.0,
		"entry_speed_min": 0.0, "entry_speed_max": INF,
		"clamp_speed_min": 2.0, "clamp_speed_max": 4.0,
		"speed_addition": 0.0, "duration": 1.17, "max_distance_time": 0.4,
		"is_stringable": false, "reset_camera": true, "ledge_offset_z": 0.35,
	},
	{
		# ⚠️ entry_speed_max RAISED FROM 2.0, with the same reasoning as
		# vault_over's min_height above. The CDO's MaxMomentum = 200 makes this
		# row a SLOW approach only, which combined with the hand-plant rows
		# starting at 0.64 left a running player no way to step up anything at
		# all. With the plant now starting at the waist, this row is what owns
		# the band below it -- and it has to be reachable at speed to do that.
		"name": "step_up_right_leg_88", "min_height": 0.48, "max_height": 1.48,
		"vault_onto": true, "min_speed_z": 0.0, "max_speed_z": 7.0,
		"entry_speed_min": 0.0, "entry_speed_max": INF,
		"clamp_speed_min": 0.0, "clamp_speed_max": 7.0,
		"speed_addition": 0.0, "duration": 0.65, "max_distance_time": 0.4,
		"is_stringable": false, "reset_camera": false, "ledge_offset_z": 0.6,
	},
	{
		"name": "auto_step_up_right_leg", "min_height": 0.0, "max_height": 0.48,
		"vault_onto": true, "min_speed_z": -6.0, "max_speed_z": 0.0,
		"entry_speed_min": 1.0, "entry_speed_max": 3.0,
		"clamp_speed_min": 0.0, "clamp_speed_max": 3.0,
		"speed_addition": 0.0, "duration": 0.50, "max_distance_time": 0.2,
		"is_stringable": false, "reset_camera": false, "ledge_offset_z": 0.9,
	},
]

## Highest `max_height` across every row in `variants` above -- what used to
## be the standalone `vault_max_height` tunable before Task 14 folded a single
## flat ceiling into the per-variant table. Probes.vault_query() reads this to
## know how far above the feet to bother looking for a vaultable top at all,
## and to reject anything past the whole table's own reach (05 §5.7: past
## 1.92 m the original leaves VaultTypes entirely for the wall-climb/grab/
## pull-up chain -- see pick_variant()'s own note on the same boundary).
## Computed from `variants` rather than duplicated as a second constant, so it
## can never drift from the table it describes.
## Source: 05 §5.7, VaultOverHigh/VaultOntoHigh's own MaxHeight = 192 uu. ✅
func table_ceiling() -> float:
	var ceiling: float = 0.0
	for v in variants:
		ceiling = maxf(ceiling, v["max_height"])
	return ceiling

## First variant whose five axes all admit this approach, or {} for none.
## An empty result is a normal outcome, not an error -- above 1.92 m the
## original leaves VaultTypes entirely (05 §5.7) and this project simply
## does not vault.
func pick_variant(height: float, vault_over: bool, speed_z: float, speed_xy: float) -> Dictionary:
	for v in variants:
		if height < v["min_height"] or height > v["max_height"]:
			continue
		# An OVER variant needs somewhere to land on the far side; an ONTO
		# variant is always admissible, because a thin obstacle can be
		# climbed onto just as well as crossed. bVaultOnto describes what the
		# ANIMATION does, not what the geometry forbids -- reading it as a
		# two-way exclusive leaves a thin obstacle approached slowly with no
		# match at all.
		if not v["vault_onto"] and not vault_over:
			continue
		if speed_z < v["min_speed_z"] or speed_z > v["max_speed_z"]:
			continue
		if speed_xy < v["entry_speed_min"] or speed_xy > v["entry_speed_max"]:
			continue
		return v
	return {}

## True once the obstacle is within `max_distance_time` SECONDS of arrival.
## The parameter is named MaxDistanceTime and holds 0.2 / 0.4 while every
## genuine distance in the same file is 50-350 uu, so it is a time (05 §5.7).
##
## Committing on time rather than on contact buys three things: the lookahead
## scales with speed for free, the velocity vector read at commit time is
## still clean (contact has not yet perturbed it), and there is a real 0.2-0.4
## s left to blend an animation into. The cost is that commitment is final --
## changing input after the lock does not cancel it, which is consistent with
## the original's "the quality of the take-off decides everything".
func should_commit(distance: float, speed_xy: float, variant: Dictionary) -> bool:
	if variant.is_empty() or speed_xy <= 0.01:
		return false
	return distance / speed_xy <= variant["max_distance_time"]

## How long the APPROACH phase may wait for contact before giving up.
##
## ⚠️ PROJECT-DEFINED, and needed only because commit and contact are separate
## here (see docs/contact-drives-movement.md). MaxDistanceTime already says how
## far ahead a commit may be made; this bounds what happens when the contact it
## predicted never arrives. Generously longer than the largest MaxDistanceTime
## in the table, so it only ever fires on a genuine miss.
@export var approach_timeout: float = 0.6

## HOW HIGH ABOVE THE FEET AN OBSTACLE'S TOP MAY BE AND STILL BE VAULTED.
##
## ✅ MEASURED TWICE, from two entirely different approaches, agreeing to two
## centimetres:
##
##   chain-link fence, running jump    feet 0.76, top 2.64  ->  1.88
##   AC unit, wall climb converting    feet 2.06, top 3.96  ->  1.90
##
## Both read at the frame the vault COMMITS, so both are pure subtraction with
## no model in them. See docs/feel-backlog.md 26 and 29.
##
## MEASURED FROM THE FEET, AND THE FEET MOVE. That is the whole reason the same
## obstacle vaults or does not depending on the jump: the owner's "with good
## jump timing even a taller building can trigger VaultOver" is not a special
## case, it is what this frame predicts. It is also why a wall climb can convert
## into a vault part-way up -- the climb raises the feet until the top comes
## within reach.
##
## Anatomically this sits a little ABOVE the eye (1.66 above the feet here),
## which is right: a vault peaks BELOW the obstacle's own top and the feet never
## clear it, because it is a hands-on-top move. What you can vault is what you
## can get your hands on top of.
@export var max_edge_above_feet: float = 1.89

## How high a vault OVER bulges above the straight line from where it started to
## where it lands.
##
## How far ABOVE the obstacle's top the EYE passes during a vault OVER.
##
## ✅ MEASURED, from docs/feel-backlog.md 26-27 -- the same measurement two
## earlier versions of this field held, read one step further. The fence's top
## is at SZD 2.64 and the feet peak at 1.77, so the feet pass 0.87 BELOW it;
## the eye sits 1.66 above the feet, so the eye passes 2.64 + 0.79.
##
## ⚠️ AIMED AT THE EYE, and that correction is the whole history of this field.
## It first held the measured RISE (1.0 m) and applied it at every obstacle
## height, which put the eye 1.66 m over a 1 m box. It then held the feet
## figure (0.87), which generalises properly -- but the body had meanwhile been
## given a FOLD that lowers the eye 0.9 m relative to the feet, and the two
## subtractions stacked: the eye came out below the top and the camera passed
## through a solid 1.9 m wall.
##
## The eye is what the player is, so the eye is what the number is about. The
## feet peak is derived from it, through whatever the fold is doing at the time,
## so changing the fold moves the arc with it instead of silently double
## counting.
@export var vault_over_eye_above_top: float = 0.79

## The shortest a vault may be squeezed to for a fast approach, as a fraction
## of its variant's own duration.
##
## The duration in the variants table is the CEILING -- a slow approach gets the
## original's own timing -- and a fast one is shortened toward the obstacle it
## is already nearly touching. This is the floor on that.
##
## ⚠️ PROJECT-DEFINED, and it was 0.5 with no reasoning beyond "brisk rather
## than instantaneous". ✅ The owner, in play: "a 0.3 s fast vault really is too
## fast, make it 0.45." 0.7 of the middle tier's 0.65 s is 0.455.
## How much of a vault is UP before any of it is forward, 0..1.
##
## ✅ THE OWNER, with a drawing of a stick figure clipping a block: "这个弧线同样
## 也是 VaultOver 的问题，它目前同样在穿墙...对于稍高的墙，都应该是总体有一个向上的
## 趋势，再往前送."
##
## ⚠️ A SYMMETRIC ARC IS WRONG ABOUT WHERE THE OBSTACLE IS. The old path added a
## sine bump to a straight line, which peaks half way ALONG the journey -- and
## the thing being vaulted is not half way along, it is at the near end. The body
## was still climbing while it was already inside the face.
##
## Under a lead the vertical instead runs up to a peak clear of both ends, holds
## while the travel crosses, and drops onto the far side. See
## ScriptedMove.begin(), where 0 leaves the old single curve untouched.
##
## 📌 Applies to every row. The low ones barely notice -- auto_step_up's whole
## rise is 0.48 m and its arc is a few centimetres -- while the high ones, which
## are the ones that clipped, change the most.
## ✅ BACK TO ZERO with the mantle's, and for the owner's reason rather than
## mine: "反正都是手K关键帧偏移，越简单的运动曲线反而对我来说越容易." See
## GrabConfig.mantle_vertical_lead.
@export var vault_vertical_lead: float = 0.0

## The same for a vault: 1 is a straight line at a constant speed. See
## GrabConfig.mantle_path_ease.
@export var vault_path_ease: float = 1.0

@export var duration_floor_pct: float = 0.7
