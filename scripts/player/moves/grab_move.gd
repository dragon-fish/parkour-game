class_name GrabMove
extends ScriptedMove

# Two phases in one move: hanging (position frozen, waiting on input) and
# mantling (a scripted move onto the top). They share the same ledge data, and
# splitting them would mean handing that data across a move boundary.

## Set in enter() when the ledge query comes back invalid: there is nothing to
## hang from, so physics_update() hands straight back to Falling without ever
## touching the body. See enter()'s note for what the old fallback did instead.
var _aborted: bool = false

var _edge: Vector3 = Vector3.ZERO
## The ledge face's normal, pointing AWAY from the wall and back toward the
## player -- kept because a shimmy runs along the ledge, and the only thing
## that knows which way "along" is, is the wall.
##
## ⚠️ READ FROM THE LEDGE, NOT FROM THE BODY, and that is the whole point.
## The player can turn freely while hanging (see the commitment note on
## _exit_direction below), so taking "sideways" off player.basis.x would make
## A and D swap meaning as soon as they looked along the wall instead of at
## it. The wall does not turn.
var _edge_normal: Vector3 = Vector3.BACK
## -1 shimmying left, +1 right, 0 hanging still. Read by character_animator.gd
## the same way is_mantling() is.
var _shimmy: float = 0.0
## The direction the mantle pushes and exits along. Captured ONCE, at
## COMMITMENT -- the moment forward or jump is pressed and begin() is called,
## in physics_update()'s climb-trigger branch below -- NOT at grab time.
## Grabbing a ledge does not commit to a direction: the player can hang and
## turn freely first, and only the facing at the moment they actually choose
## to climb should decide where that climb goes. See the note on the
## climb-trigger branch for the full reasoning (and why an earlier version of
## this file, which captured in enter(), got this wrong).
var _exit_direction: Vector3 = Vector3.ZERO
var _mantling: bool = false

## Whether the CURRENT ledge stint is mantling (the scripted climb onto the
## top) rather than hanging (frozen, waiting on input). Exposed the same way
## SlideMove.is_crawling() is (see MoveManager.move_for()'s own comment on
## that precedent): nothing outside this move can otherwise tell the two
## phases apart, and character_animator.gd needs exactly that distinction --
## only the hang phase has a genuine clip match in the owner's reported
## vocabulary (`ladder_stillness`); the mantle phase still does not.
func is_mantling() -> bool:
	return _mantling

## Which way the hands are travelling along the ledge: -1 left, +1 right, 0
## still. Exposed for the same reason is_mantling() is -- nothing outside this
## move can otherwise tell a hang apart from a shimmy, and the animator needs
## exactly that to choose between Climb_Idle and Climb_Left/Climb_Right.
func shimmy_direction() -> float:
	return _shimmy

func enter(_previous: StringName) -> void:
	# grounded is DECLARED, not read from is_on_floor(): like SpeedVault, this
	# move drives the body directly and never calls move_and_slide() --
	# neither while hanging (frozen in place, see the "hold still" branch
	# below) nor while mantling (a scripted arc onto the ledge top) -- so
	# is_on_floor() would keep reporting whatever the previous move left
	# behind for the whole time this move runs. See SpeedVaultMove.enter()'s
	# matching note.
	#
	# A single declaration here is enough to cover every exit path too:
	# nothing below ever sets grounded true, so both a completed mantle
	# (hands off to Walking) and a crouch-release drop (hands off to Falling)
	# correctly leave it false -- the mantle case deliberately mirrors
	# SpeedVaultMove's own hand-off to Walking (see the note on that return below).
	# It is also what satisfies MoveManager's declaration invariant for this
	# move, which never calls set_grounded() again after this line.
	player.set_grounded(false)

	_aborted = false
	_mantling = false

	# FallingMove already null-checks player.probes AND requires a valid
	# ledge_query() before ever transitioning here, so neither branch below is
	# reachable in normal play. They are kept as a guard for a future caller
	# that skips that gate -- but as a GENUINELY safe one. The previous version
	# fell back to `_edge = player.global_position`, which is not "nowhere to
	# hang": the mantle target is built as `_edge + up * standing_height/2 +
	# forward * mantle_forward_offset`, so that fallback would have teleported
	# the body 0.9 m up and 0.4 m forward, through whatever was there. There is
	# no safe destination to invent when the probe found nothing, so invent
	# none: abort and let the player fall.
	# The reach hands its own result over (Player.pending_ledge). Re-querying
	# here cannot work any more: IntoGrabMove has just carried the body to the
	# hanging pose, 0.45 m back and most of a body-length below the lip, and
	# from there the probe no longer sees the edge it was carried to. The grab
	# aborted on its first tick and dropped the player.
	var query: Dictionary = player.pending_ledge
	player.pending_ledge = {}
	if query.is_empty():
		# Entered without a reach -- nothing does that today, but a future
		# caller might. Falling back to a fresh query is right for that case.
		query = player.probes.ledge_query() if player.probes != null else Probes.NO_HIT.duplicate()
	if not query.get("valid", false):
		_aborted = true
		return
	_edge = query["edge"]
	_edge_normal = query.get("normal", Vector3.BACK)
	_shimmy = 0.0

	player.velocity = Vector3.ZERO
	# The body holds exactly wherever it grabbed -- NO repositioning, up or
	# down. ledge_query()'s "height" is measured against the player's CURRENT
	# feet at the moment of the grab, so a valid grab can land anywhere in
	# [min_wall_height, ledge_max_height] above them. Snapping to any FIXED
	# offset from the edge from there would, for most of that range, be
	# either an upward pop (pulling the body toward the edge) or a downward
	# drop (pushing it away) the player never asked for -- holding position
	# is the correct behaviour on its own merits, not a simplification of a
	# "real" reposition. (A grab near the top of the reachable range now
	# hangs at full stretch, well below the edge; was confirmed by
	# test_mantling_completes_from_the_top_of_the_grab_range in
	# tests/legacy/test_ledge.gd -- the climb is a fixed-time lerp, not a
	# fixed-speed one, so distance never affects how long it takes. That test
	# is ARCHIVED by Task 1 and NOT in the running suite, so nothing enforces
	# this today; restore the pin when the behavioural suite is rewritten.)

# NO exit() override any more. The re-grab cooldown this move needs is now
# GrabConfig's own redo_move_time (0.45 s), armed by MoveManager on every
# transition OUT of this move and checked by MoveManager.can_enter() before
# every transition back in -- exactly the mechanism WallRun already uses.
#
# That covers strictly more than the hand-rolled Player._ledge_cooldown it
# replaces, and covers it without this move having to remember anything: the
# mantle hand-off used to leave the cooldown at zero, so a landing that found
# no floor dropped to Falling and FallingMove's very next ledge_query() could
# re-grab on the same tick, with no gate of any kind between the two. That is
# an unbounded oscillation whenever the landing point is not standing room.
#
# Harmless on the paths that were already fine: a completed mantle leaves the
# player standing on top of the platform, where there is no ledge in front of
# them to re-grab anyway, so withholding grabs for 0.45 s costs nothing a
# player can feel.

## ⚠️ THIS MOVE HAD NO exit() AT ALL, which was survivable only because it
## changed nothing that needed putting back. The mantle's folded capsule does,
## and a state that shrinks the body without restoring it leaves the player
## permanently crouched -- the exact shape of the leak SpeedVaultMove's missing
## exit() had with its camera roll.
##
## A REQUEST rather than a restore, matching Slide, Crouch, SkillRoll and now
## the vault: a mantle can end under something low, and standing up into it
## would put the capsule inside it. Player owes the restore and performs it on
## the first tick there is room.
##
## Safe on the hang-and-drop path too, where nothing was ever shrunk: asking for
## a standing capsule you already have costs nothing.
func exit() -> void:
	player.request_standing_capsule()
	player.set_body_folded(false)
	player.set_clip_lift_cancelled(false)

func physics_update(delta: float, input: MoveInput) -> StringName:
	if _aborted:
		return FALLING

	if _mantling:
		if advance(delta):
			player.velocity = _exit_direction * config.grab.mantle_exit_speed
			# Deliberately NOT declared grounded here -- see the note on
			# enter() above, and SpeedVaultMove.physics_update()'s matching note.
			# The landing point is pinned to the probed ledge edge plus an
			# un-probed forward offset (mantle_forward_offset) that nothing
			# here has checked against real geometry, so asserting grounded
			# true at this exact instant would be exactly the bug that note
			# describes for SpeedVault. Leaving it false means WalkingMove's own
			# next floor-snap tick is what first verifies it for real -- and,
			# since Step Zero of this task, WalkingMove's Slide/SpeedVault entry
			# checks are themselves gated on grounded being true, so this
			# hand-off cannot chain straight into a second scripted move
			# either.
			return WALKING
		return KEEP

	# Hanging: hold still. enter() zeroed velocity once and nothing in this
	# branch ever calls move_and_slide(), so nothing needs to run every tick
	# to keep the body from drifting or falling -- there is simply no code
	# path here that would move it. Matches SpeedVaultMove, which likewise zeros
	# velocity once at enter() rather than every tick of its own scripted move.

	# The re-grab cooldown this drop needs is armed by MoveManager on the way
	# out, which covers this path and the mantle hand-off alike without either
	# of them doing anything -- see the block above physics_update() for why
	# this move no longer overrides exit() at all.
	if input.crouch_held:
		return FALLING

	# Pushing forward, or jumping, climbs up. This IS the moment of
	# commitment: the player has been free to turn at any point while
	# hanging, right up until this tick, and CameraRig.apply_look() keeps
	# turning the body every physics tick regardless of state -- so facing is
	# sampled HERE, fresh, rather than reusing whatever _edge's grab-time
	# probe happened to see. This is also the ONLY place _exit_direction is
	# ever written: both the landing point immediately below and the exit
	# push on mantle completion (above) read it back rather than re-sampling
	# facing themselves, so a further turn made DURING the 0.42 s scripted
	# climb cannot retroactively change either one either.
	if input.move.y > 0.5 or input.jump_pressed:
		_exit_direction = -player.global_transform.basis.z
		var top := _edge + Vector3(0.0, player.standing_height() * 0.5, 0.0)
		# PLUS, not minus. _exit_direction is FORWARD (-basis.z), and the
		# landing has to sit mantle_forward_offset PAST the lip, standing on
		# the platform -- exactly what SpeedVaultMove does with vault_exit_forward,
		# and exactly what MovementConfig documents this knob as doing. The
		# original brief wrote `top -= basis.z * 0.4`, where basis.z is
		# BACKWARD, so that `-=` was already a forward push; a later refactor
		# introduced `_exit_direction = -basis.z` but kept the `-=`,
		# double-negating it.
		#
		# _edge is SurfaceDown's hit, which sits LEDGE_ANCHOR_MARGIN (0.1 m)
		# past the wall face the forward ray found -- i.e. just inside the
		# ledge top, tracking the real obstacle rather than sitting a fixed
		# distance ahead of the body (see Probes.ledge_query()). Subtracting
		# here therefore put the landing 0.4 m BACK from that anchor: 0.3 m
		# SHORT of the face, feet at platform height over open air -- and on
		# EVERY approach, not just close ones, since the anchor now tracks the
		# face. Measured on the test rig with the sign inverted, the body then
		# settles balanced on the block's top EDGE, outside the platform -- and
		# on the arena's LedgeMid it drops, slides back down the face and
		# re-grabs: climb / fall / re-climb every time.
		#
		# With the sign correct the landing sits 0.1 + 0.4 = 0.5 m past the
		# face, comfortably on top of any ledge deep enough to have been
		# anchored to in the first place.
		# NOWHERE TO GO IS NOT A MANTLE.
		#
		# ✅ The owner drew the shape and gave the original's answer: a ledge
		# with a slab overhanging it can be HUNG from and shimmied along, and
		# cannot be pulled up onto. Ours pulled up regardless and put the body
		# inside the geometry -- clipping through walls, reported as happening
		# a lot.
		#
		# Refused rather than aborted: the hang is still perfectly valid, and
		# staying on it is what the original does -- AND, since this move grew
		# a shimmy, staying on it is now something the player can act on rather
		# than a dead end. An overhung ledge is exactly the case the owner
		# described: hang, travel along it to somewhere the slab does not
		# reach, and pull up there.
		#
		# Asked of the BODY, not of the probe. Player.fits_standing_at() moves
		# the shapecast that already exists for the crouch-to-stand restore --
		# a SHAPE, because a body has width, where a ray threads between two
		# slabs it could never fit through.
		if not player.fits_standing_at(top):
			return KEEP
		top += _exit_direction * config.grab.mantle_forward_offset
		begin(player.global_position, top, config.grab.mantle_duration, config.grab.mantle_arc_height)
		_mantling = true
		# THE BODY FOLDS TO PULL UP, the same way SpeedVaultMove folds to vault
		# -- see its enter() for the owner's reasoning and the arithmetic that
		# backs it. A pull-up is knees-to-chest and then a stand; carrying a
		# rigid 1.8 m upright capsule through it is what puts the eye a whole
		# body above the ledge.
		#
		# ONLY THE MANTLE, not the hang: hanging is full extension, arms
		# overhead and body straight, which is the one pose the standing capsule
		# actually fits.
		# See SpeedVaultMove.enter(): the collision shortens from the top with
		# the feet on the floor, and the MODEL AND EYE drop to sit on the new
		# crown. A pull-up is knees-to-chest, so the head is where the body
		# actually is.
		player.set_capsule_height(config.crouch.crouch_capsule_height)
		player.set_body_folded(true)
		# ClimbUp_2m lifts the hips 1.201 m by itself, and the mantle's own arc
		# already carries the body up the wall. See
		# Player.set_clip_lift_cancelled().
		player.set_clip_lift_cancelled(true)
	else:
		# NOT CLIMBING THIS TICK, so the hands are free to travel. Deliberately
		# in the `else`: holding forward-and-sideways should climb, not shimmy,
		# and the pull-up is the committed action of the two.
		_advance_shimmy(delta, input)
	return KEEP

## One tick of travel along the ledge.
##
## ✅ THE OWNER wanted the Climb set used, and it is the one place UAL1
## carries a complete hang vocabulary: Climb_Idle to hang, Climb_Left and
## Climb_Right to travel, ClimbLedge to pull up. Both travel clips are 0.87 s
## with ZERO net displacement, which is the shape this project already relies
## on everywhere else -- the clip supplies the pose, the code supplies the
## metres.
##
## THE BODY AND THE ANCHOR MOVE TOGETHER OR NEITHER MOVES. Every refusal below
## returns without touching either, because advancing one without the other is
## the failure this whole move is built to avoid: _edge is what the pull-up
## aims at, so an anchor that has crept past the real ledge would mantle the
## player onto thin air, and a body that has crept past its anchor would hang
## from a point the ledge no longer occupies.
func _advance_shimmy(delta: float, input: MoveInput) -> void:
	if player.probes == null:
		return
	var wanted: float = input.move.x
	if absf(wanted) < config.grab.shimmy_deadzone:
		_shimmy = 0.0
		return
	var side: float = signf(wanted)
	# ALONG the ledge is ACROSS the wall -- the horizontal face normal turned a
	# quarter turn. facing.cross(UP) is the right hand of whatever faces
	# `facing`, and facing here points INTO the wall, so this is the player's
	# right as they hang looking at it.
	var facing: Vector3 = -_edge_normal
	facing.y = 0.0
	if facing.length_squared() < 0.0001:
		# The face is horizontal: a soffit or the underside of a slab rather
		# than a wall. There is no "along" to travel, so there is no shimmy.
		_shimmy = 0.0
		return
	var sideways: Vector3 = facing.normalized().cross(Vector3.UP)
	var step: Vector3 = sideways * (side * config.grab.shimmy_speed * delta)

	# IS THE LEDGE STILL THERE? Asked of the ledge top from above, because the
	# forward probe cannot see it from the hanging pose -- see
	# Probes.ledge_beside() for why that is and what it does instead.
	var beside: Dictionary = player.probes.ledge_beside(_edge, step,
			config.grab.shimmy_probe_lift, config.grab.shimmy_edge_tolerance)
	if not beside.get("valid", false):
		# The ledge ran out. Hanging on is right: the player is still holding
		# a perfectly good ledge, they have simply reached the end of it.
		# Rounding a corner is a separate question and is not answered here.
		_shimmy = 0.0
		return

	# AND IS THERE ROOM FOR THE BODY? A ledge can continue past a pillar, a
	# column or an inside corner that the hanging body cannot pass through, and
	# the ray above threads between things a body never could. Same shapecast
	# the mantle asks with, for the same reason.
	var half: float = player.standing_height() * 0.5
	var feet: Vector3 = player.global_position + step - Vector3.UP * half
	if not player.fits_standing_at(feet):
		_shimmy = 0.0
		return

	player.global_position += step
	# The TOP the probe found, not _edge + step: on a ledge that is not
	# perfectly level the two drift apart, and the anchor should track the real
	# surface rather than the straight line the hands were aimed along.
	#
	# _edge_normal is deliberately NOT updated from this hit. The probe fires
	# DOWNWARD, so its normal is the ledge TOP's -- straight up -- while this
	# field holds the FACE's, which is what "along the ledge" is derived from.
	# Overwriting it would make the next step's direction undefined.
	_edge = beside["edge"]
	_shimmy = side
