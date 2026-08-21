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
@export var vault_arc_height: float = 0.15
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
		"name": "vault_over", "min_height": 0.64, "max_height": 1.48,
		"vault_onto": false, "min_speed_z": 0.0, "max_speed_z": 100.0,
		"entry_speed_min": 4.0, "entry_speed_max": INF,
		"clamp_speed_min": 0.0, "clamp_speed_max": 7.2,
		"speed_addition": 0.8, "duration": 0.65, "max_distance_time": 0.4,
		"is_stringable": true, "reset_camera": false, "ledge_offset_z": 0.25,
	},
	{
		"name": "vault_onto", "min_height": 0.64, "max_height": 1.48,
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
		"name": "step_up_right_leg_88", "min_height": 0.48, "max_height": 1.48,
		"vault_onto": true, "min_speed_z": 0.0, "max_speed_z": 7.0,
		"entry_speed_min": 0.0, "entry_speed_max": 2.0,
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
