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
## The WALL FACE's normal, pointing away from the wall and back toward the
## player -- kept because a shimmy runs along the ledge, and the only thing
## that knows which way "along" is, is the wall.
##
## ⚠️ "face_normal", NOT "normal". ledge_query() returns BOTH, and they are
## perpendicular: "normal" comes off SurfaceDown, the ray fired DOWNWARD onto
## the ledge top, so it points straight UP, while "face_normal" comes off the
## forward ray that found the wall. Reading the wrong one flattens to a zero
## vector the moment y is dropped, and the shimmy then refuses on every single
## tick through the horizontal-face branch below -- silently, because refusing
## to travel is a perfectly ordinary thing for it to do. IntoGrabMove hit the
## same pair and documents the same distinction on its own yaw.
##
## ⚠️ READ FROM THE LEDGE, NOT FROM THE BODY, and that is the whole point.
## The player can turn freely while hanging (see the commitment note on
## _exit_direction below), so taking "sideways" off player.basis.x would make
## A and D swap meaning as soon as they looked along the wall instead of at
## it. The wall does not turn.
var _face_normal: Vector3 = Vector3.BACK
## -1 shimmying left, +1 right, 0 hanging still. Read by character_animator.gd
## the same way is_mantling() is.
##
## HELD THROUGH A CORNER on purpose: the owner's direction was to borrow the
## travel clips for it -- "climb left right 动画...可以借一下，顺便把转角做了" --
## and there is no dedicated corner clip in either pack to borrow instead.
var _shimmy: float = 0.0

## Rounding a ninety-degree corner: a scripted swing of the whole body onto a
## perpendicular face, over corner_duration.
##
## A THIRD PHASE, beside hanging and mantling, and it earns the place for the
## same reason mantling has one: it owns the body for a stretch of time and
## shares the ledge data with the phase before it.
var _cornering: bool = false
var _corner_time: float = 0.0
var _corner_from_pos: Vector3 = Vector3.ZERO
var _corner_to_pos: Vector3 = Vector3.ZERO
var _corner_from_yaw: float = 0.0
var _corner_to_yaw: float = 0.0
## Where the hands and the face end up. Applied at COMPLETION rather than at the
## start, so a corner interrupted for any reason leaves the move still
## describing the ledge the body is actually on.
var _corner_edge: Vector3 = Vector3.ZERO
var _corner_normal: Vector3 = Vector3.BACK
## The yaw already handed to the camera, so each tick reports only its own
## slice. Mirrors Turn180Move._placed, whose handshake this copies.
var _corner_placed: float = 0.0
## The MODEL's own sweep, kept separately from the body's because they do not
## start in the same place: the body is wherever the player was looking, the
## model is squared to the face it hangs from. Absolute, never accumulated --
## see Player.pin_visual_yaw().
var _corner_model_from: float = 0.0
var _corner_model_sweep: float = 0.0
## Counts down corner_lockout after a corner, during which the shimmy refuses.
var _shimmy_lockout: float = 0.0

## WHY the shimmy did what it did on the last tick it was asked, for the HUD.
##
## ⚠️ EXISTS BECAUSE EVERY REFUSAL LOOKS THE SAME FROM OUTSIDE. A shimmy that
## stops has four different reasons to -- the ledge ended, the face ended, the
## body is blocked, the lockout is running -- and the body does exactly the same
## nothing for all of them. The owner hit a corner in me_level0 that refuses on
## geometry the arena course reproduces fine, and the arena is not where the
## answer is; the readout is.
var _shimmy_report: String = "idle"

## The segments the shimmy probes actually fired on the last tick they ran, each
## {from, to, hit, label}. Drawn by ShimmyDebug.
##
## ⚠️ RECORDED, NOT RECONSTRUCTED. The obvious cheaper version is to let the
## debug view re-run the same probes with the same arguments -- and that is a
## picture of a SECOND implementation, which agrees with this one right up until
## the moment a difference is what you are looking for. Probes hands its
## segments back for the same reason IntoGrabMove.hanging_pose() is static.
var _probe_trace: Array[Dictionary] = []
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

## One line on what the shimmy last decided and why. Read by the debug HUD.
func shimmy_report() -> String:
	return _shimmy_report

## The ledge the hands are on, for the debug view: where the anchor is, which
## way travel runs along it, and which way the face points.
##
## `along` is derived here rather than in the drawer for the same reason the
## segments are: it is the same expression _advance_shimmy() steers by, and a
## second copy of it in a debug view would agree until it mattered.
func anchor_debug() -> Dictionary:
	var facing: Vector3 = -_face_normal
	facing.y = 0.0
	var along := Vector3.ZERO
	if facing.length_squared() > 0.0001:
		along = facing.normalized().cross(Vector3.UP)
	return {"edge": _edge, "along": along, "outward": _face_normal}

## The shimmy probes fired on the last tick they ran. See _probe_trace.
func probe_trace() -> Array[Dictionary]:
	return _probe_trace

## Whether the body is mid-corner. Exposed for the same reason is_mantling() is:
## nothing outside this move can otherwise tell a corner from ordinary travel,
## and a corner refuses every input a hang accepts.
func is_cornering() -> bool:
	return _cornering

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
	# FALLBACK IS THE BODY'S OWN FACING, and only here is that safe: IntoGrabMove
	# has just squared the body to the wall face (see its _target_yaw), so on
	# this one tick the two agree. It is read once and kept, never re-read --
	# the player turns freely from the next tick onward.
	var face: Vector3 = query.get("face_normal", Vector3.ZERO)
	face.y = 0.0
	if face.length_squared() > 0.0001:
		_face_normal = face.normalized()
	else:
		# basis.z is BACKWARD, which is where a face normal points from a body
		# squared to it: away from the wall, back at the player.
		_face_normal = player.global_transform.basis.z
	_shimmy = 0.0
	_cornering = false
	_shimmy_lockout = 0.0

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

	# BEFORE EVERYTHING, mantle included. A corner is a scripted passage that
	# owns the body; a pull-up or a jump started halfway through one would
	# launch from a position that is neither the ledge left nor the ledge
	# arrived at. The original spends 1.0 s here and then another 0.6 s
	# refusing to shimmy, which is not the shape of a state you can act out of.
	if _cornering:
		_advance_corner(delta)
		return KEEP

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

	# JUMP WITH YOUR BACK TURNED PUSHES OFF instead of pulling up, and this has
	# to be asked BEFORE the climb trigger below -- that branch takes
	# jump_pressed too, so whichever is asked first wins the key.
	#
	# ✅ The original splits the same key the same way, and gives both halves the
	# same angle: TdMove_GrabJump.GrabAllowedJumpAngle = 45 against
	# TdMove_GrabPullUp.GrabAllowedPullUpAngle = 45. Looking at the wall climbs
	# it, looking away from it leaves it.
	#
	# ✅ THE OWNER: "我们没有做 Grab 的回头跳，Grab 期间扭头超过 90 度就可以跳了."
	# The threshold is the CDO's 45 rather than that 90, at their own direction
	# -- "有实测数据就按数据来，我只能用手感跟你描述."
	if input.jump_pressed:
		var turned: float = _turned_from_wall()
		if turned > deg_to_rad(config.grab.jump_angle_deg):
			_push_off(turned)
			# The re-grab cooldown is armed by MoveManager on the way out, the
			# same as every other exit from this move. That already covers what
			# the original spends bDelayTimeCheckAutoMoves = 0.2 s on, and more
			# conservatively (redo_move_time is 0.45) -- without which the very
			# next Falling tick would probe the wall you just shoved off and
			# grab it again.
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
	# ✅ AND IT NEEDS BOTH HANDS. See _two_handed(): past the angle the body is
	# hanging by one arm and cannot haul itself over anything.
	#
	# ⚠️ WITHOUT THIS THE HANG JUMP IS UNREACHABLE BY THE INPUT PEOPLE ACTUALLY
	# USE. Forward-and-jump is one gesture rather than two, so an ungated pull-up
	# does not merely coexist with the jump -- it wins every time, on the same
	# tick, with the same keys down. The branch below only ever fired for a
	# player who thought to release W first.
	if (input.move.y > 0.5 or input.jump_pressed) and _two_handed():
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
		begin(player.global_position, top, config.grab.mantle_duration,
				config.grab.mantle_camera_arc, config.grab.mantle_vertical_lead,
				config.grab.mantle_path_ease)
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
	# ✅ DisableShimmyTime. A corner leaves the hands a hand's width from the
	# corner they just rounded, so without this a wobble on the stick walks them
	# straight back around it, and around again.
	# ✅ TRAVELLING NEEDS BOTH HANDS TOO, and this is the half the first version
	# of the gate missed: it stopped the pull-up and left A and D working, so a
	# body hanging by one arm could still hand-over-hand along the ledge.
	if not _two_handed():
		_shimmy = 0.0
		_shimmy_report = "one-handed: the view is turned too far to travel"
		return
	if _shimmy_lockout > 0.0:
		_shimmy_lockout -= delta
		_shimmy = 0.0
		_shimmy_report = "corner lockout %.2fs" % _shimmy_lockout
		return
	var wanted: float = input.move.x
	if absf(wanted) < config.grab.shimmy_deadzone:
		_shimmy = 0.0
		_shimmy_report = "idle"
		return
	var side: float = signf(wanted)
	# ALONG the ledge is ACROSS the wall -- the horizontal face normal turned a
	# quarter turn. facing.cross(UP) is the right hand of whatever faces
	# `facing`, and facing here points INTO the wall, so this is the player's
	# right as they hang looking at it.
	var facing: Vector3 = -_face_normal
	facing.y = 0.0
	if facing.length_squared() < 0.0001:
		# The face is horizontal: a soffit or the underside of a slab rather
		# than a wall. There is no "along" to travel, so there is no shimmy.
		_shimmy = 0.0
		_shimmy_report = "face normal is not a wall"
		return
	var sideways: Vector3 = facing.normalized().cross(Vector3.UP)
	var step: Vector3 = sideways * (side * config.grab.shimmy_speed * delta)

	# IS THE LEDGE STILL THERE? Asked of the ledge top from above, because the
	# forward probe cannot see it from the hanging pose -- see
	# Probes.ledge_beside() for why that is and what it does instead.
	_probe_trace.clear()
	var beside: Dictionary = player.probes.ledge_beside(_edge, step,
			_face_normal, Probes.LEDGE_ANCHOR_MARGIN,
			config.grab.shimmy_probe_lift, config.grab.shimmy_edge_tolerance)
	_trace("ledge", beside)

	# ⚠️ TWO QUESTIONS, NOT ONE, and asking only the first walked the hands off
	# the outside corner of anything with depth. ledge_beside() answers about
	# the TOP, which on a 6 m block carries on for metres past the corner; the
	# FACE the body actually hangs from ended there. See Probes.face_beside().
	var face: Dictionary = player.probes.face_beside(_edge, step, _face_normal,
			config.grab.corner_probe_drop, Probes.LEDGE_ANCHOR_MARGIN)
	_trace("face", face)
	if not beside.get("valid", false) or not face.get("valid", false):
		# THE OUTSIDE CORNER. What ran out is this face, so look for the one
		# perpendicular to it -- and if there is none, the ledge simply ends and
		# hanging on is the right answer: the player still holds a perfectly
		# good ledge, they have reached the end of it.
		var around: Dictionary = player.probes.corner_beyond(_edge,
				sideways * side, _face_normal, config.grab.corner_probe_reach,
				config.grab.corner_probe_drop, Probes.LEDGE_ANCHOR_MARGIN,
				config.grab.shimmy_edge_tolerance)
		_trace("corner look", around)
		if around.has("top_from"):
			_probe_trace.append({"label": "corner top", "from": around["top_from"],
				"to": around["top_to"], "hit": around.get("valid", false)})
		if around.get("valid", false):
			_begin_corner(around["edge"], around["normal"], side)
			_shimmy_report = "outside corner"
		else:
			_shimmy = 0.0
			_shimmy_report = "%s ran out, nothing perpendicular beyond" % (
				"ledge" if not beside.get("valid", false) else "face")
		return

	# AND IS THERE ROOM FOR THE BODY? A ledge can continue past a pillar or into
	# an inside corner that the hanging body cannot pass through, and the ray
	# above threads between things a body never could.
	#
	# ⚠️ NOT fits_standing_at(), WHICH THE MANTLE USES AND WHICH IS WRONG HERE.
	# A hanging body is always INSIDE the ledge it hangs from -- 0.09 m of
	# capsule above the lip and 0.05 m of it through the wall face, by
	# construction, see Probes.side_clear() for the arithmetic. So that question
	# answers NO at every hang position on every wall, and asking it here
	# refused every step of every shimmy. That shipped, and the owner found it
	# on a wall built to be easy: "就你造的这几个墙，我都不能横爬."
	# ⚠️ TWO PROBES, AND NEITHER IS THE CAPSULE. ✅ The owner: "现在是角色的中心撞到
	# 障碍才会被阻挡，但其实人的手已经进入墙里了."
	#
	# The capsule's 0.4 m radius describes a cylinder around the torso, which is
	# not the shape of a person hanging by their hands: the arms are up and out,
	# and the LEADING HAND is both wider than the shoulder and 0.81 m higher than
	# the body's centre. Probing from the centre at the capsule's own radius
	# therefore misses a wall until the hand is already well inside it, and
	# misses one entirely if it starts above chest height.
	#
	# So: one along the chest at the body's real width, and one along the LEDGE
	# at hand height, which is where the grip is actually going.
	var travel: Vector3 = sideways * side
	var reach: float = config.grab.shimmy_body_half_width + step.length()
	var blocked: Dictionary = player.probes.side_hit(player.global_position,
			travel, reach)
	_probe_trace.append({"label": "body", "from": player.global_position,
		"to": player.global_position + travel * reach,
		"hit": not blocked.is_empty()})
	if blocked.is_empty():
		# HAND HEIGHT, AND AT THE LIP RATHER THAN AT THE ANCHOR. The anchor sits
		# LEDGE_ANCHOR_MARGIN *inside* the top, which is exactly where a railing
		# standing on the ledge lives -- firing from there put the probe's own
		# origin inside the fence on the owner's west eave, and with
		# hit_from_inside it reported "blocked" before travelling a millimetre.
		#
		# The hands are on the OUTER edge, so the ray belongs just outside the
		# face plane, running along it. A wall crossing the hand's path has to
		# cross that plane to do so; a railing set back behind it does not, and
		# is ledge_beside()'s question rather than this one.
		var lip: Vector3 = _face_normal
		lip.y = 0.0
		if lip.length_squared() > 0.0001:
			lip = lip.normalized() * (Probes.LEDGE_ANCHOR_MARGIN + 0.02)
		else:
			lip = Vector3.ZERO
		var grip: Vector3 = _edge + lip + Vector3.UP * config.grab.shimmy_grip_lift
		blocked = player.probes.side_hit(grip, travel, reach)
		_probe_trace.append({"label": "body", "from": grip,
			"to": grip + travel * reach, "hit": not blocked.is_empty()})
	if not blocked.is_empty():
		# THE INSIDE CORNER, and it is the SAME probe that used to be only a
		# refusal. Whatever is beside the body is either something to turn onto
		# or something to stop at, and its normal is what tells the two apart.
		var turned: Dictionary = _ledge_on(blocked)
		if turned.get("valid", false):
			_begin_corner(turned["edge"], turned["normal"], side)
			_shimmy_report = "inside corner"
		else:
			_shimmy = 0.0
			_shimmy_report = "blocked, and it carries no ledge at this height"
		return

	player.global_position += step
	# The TOP the probe found, not _edge + step: on a ledge that is not
	# perfectly level the two drift apart, and the anchor should track the real
	# surface rather than the straight line the hands were aimed along.
	#
	# _face_normal is deliberately NOT updated from this hit. The probe fires
	# DOWNWARD, so its normal is the ledge TOP's -- straight up -- while this
	# field holds the FACE's, which is what "along the ledge" is derived from.
	# Overwriting it would make the next step's direction undefined.
	_edge = beside["edge"]
	_shimmy = side
	_shimmy_report = "travelling"

## Whether the hands are BOTH on the ledge.
##
## 🎯 THE OWNER'S MODEL, and it is better than the two angle rules it replaces:
## "ME 里扭头大于 45° 会变成单手攀附，很多事情就解释的通，此时无法 AD，也无法
## GrabUp，因为这两种动作都要求 2 hands free."
##
## One state change with two consequences, rather than a pull-up rule and a
## shimmy rule that happen to share a number. The CDO says the same thing from
## its own side -- TdMove_Grab carries `MovementGroup = MG_TwoHandsBusy` -- and
## it explains why the threshold is where it is instead of being a tuning value:
## it is the angle past which a shoulder cannot stay square to the wall.
##
## 📌 What it does NOT gate is the jump, which is the whole point of the split:
## one arm is plenty to shove off with, and past this angle it is the only thing
## left to do.
func _two_handed() -> bool:
	return _turned_from_wall() <= deg_to_rad(config.grab.pull_up_angle_deg)

## How far the view has been turned off the wall, in radians: 0 looking straight
## at it, PI with your back to it.
##
## Measured against the FACE, not against where the body was left facing at
## grab time. IntoGrabMove squares the body to the wall on arrival, so the two
## agree for exactly one tick and then stop agreeing the moment the player
## looks anywhere.
func _turned_from_wall() -> float:
	var facing: Vector3 = -player.global_transform.basis.z
	facing.y = 0.0
	var into_wall: Vector3 = -_face_normal
	into_wall.y = 0.0
	if facing.length_squared() < 0.0001 or into_wall.length_squared() < 0.0001:
		return 0.0
	return facing.normalized().angle_to(into_wall.normalized())

## Where a jump off a hang launches: along the VIEW, wall included.
##
## ✅ THE OWNER: "应该是往镜头方向一个大跳，如果抬头也会有往上的力." The pitch
## therefore has to be in it -- this is the full 3D look direction, not its
## horizontal shadow -- which is what makes looking up send you up.
##
## ⚠️ AND NOTHING IS PROJECTED OUT OF IT, WHICH WAS THE FIRST VERSION'S MISTAKE.
## jump_angle_deg allows this jump from 45 degrees off the wall, where the view
## still points half INTO it, and removing that component looked like ordinary
## prudence. It is not:
##
## ✅ THE OWNER, on the original: "攀边扭头略大于 45° 对着墙沿起跳是一个速通
## glitch，能把超级慢的 GrabPullUp 转换为更快的 VaultOver."
##
## That glitch IS the into-the-wall component. Just past the threshold the body
## is thrown at its own ledge, the airborne vault probe catches the top on the
## way past, and the pull-up is skipped entirely. Projecting the component away
## sends the body sideways along the face instead and the vault never fires --
## so the tidy version quietly deletes a technique the speedrun route is built
## on. Copying the mistake is the port, the same as the dodge glitch in 04.
##
## 📌 It also settles what the threshold MEANS. Reading GrabAllowedJumpAngle = 45
## as "within 45 degrees of facing AWAY from the wall" was a live alternative
## while nothing told the two apart. A glitch that fires at 46 degrees off the
## WALL does.
func _launch_direction() -> Vector3:
	var look := Vector3.ZERO
	if player.camera_rig != null and player.camera_rig.camera != null:
		look = -player.camera_rig.camera.global_transform.basis.z
	if look.length_squared() < 0.0001:
		# No rig to read: the body is squared to the wall, which is the best
		# available answer. Tests with a stub player take this path.
		look = -player.global_transform.basis.z
	if look.length_squared() < 0.0001:
		return _face_normal
	return look.normalized()

## Leaves the ledge.
##
## ⚠️ bDisableFaceRotation is True on TdMove_GrabJump, which fits: the body does
## not turn to follow the launch. You look back over your shoulder and go.
func _push_off(_turned: float) -> void:
	var launch: Vector3 = _launch_direction() * config.grab.jump_speed
	launch.y += config.grab.jump_speed_up
	player.velocity = launch

## The ledge belonging to a wall the body has run into sideways, or a miss when
## that wall carries no ledge at this height.
##
## An inside corner is not merely "something is in the way": a pillar, a doorway
## reveal or a parapet returning at the wrong height all block the hands without
## offering anywhere to go. The height check is what separates a corner from an
## obstacle, and it is the same tolerance ordinary travel uses -- the hanging
## body is placed for ONE height, and a face whose top sits above or below that
## is a different ledge however square it is to this one.
func _ledge_on(blocked: Dictionary) -> Dictionary:
	var normal: Vector3 = blocked.get("normal", Vector3.ZERO)
	normal.y = 0.0
	if normal.length_squared() < 0.0001:
		return {}
	normal = normal.normalized()
	# A wall still facing the way this one does is the SAME wall, met at a
	# glancing angle -- not a corner. Same 60 degree test Probes.corner_beyond()
	# applies from the other side.
	if normal.dot(_face_normal) > 0.5:
		return {}
	var at: Vector3 = blocked.get("position", Vector3.ZERO)
	# The anchor sits LEDGE_ANCHOR_MARGIN inside the top, which is where
	# ledge_query() puts one, so the two agree about where an edge is.
	var candidate: Vector3 = Vector3(at.x, _edge.y, at.z) - normal * Probes.LEDGE_ANCHOR_MARGIN
	# A zero step: this is a probe straight down onto the candidate, and
	# ledge_beside() already measures the height it finds against the y it was
	# handed -- which is this ledge's.
	var top: Dictionary = player.probes.ledge_beside(candidate, Vector3.ZERO,
			normal, Probes.LEDGE_ANCHOR_MARGIN,
			config.grab.shimmy_probe_lift, config.grab.shimmy_edge_tolerance)
	if not top.get("valid", false):
		return {}
	return {"valid": true, "edge": top["edge"], "normal": normal}

## Starts the scripted swing onto `new_normal`'s face.
func _begin_corner(new_edge: Vector3, new_normal: Vector3, side: float) -> void:
	_corner_from_pos = player.global_position
	# Through IntoGrabMove.hanging_pose(), the same function that placed the
	# body on the ledge it is leaving. A corner that arrived at a hand-computed
	# offset would hang differently from every other grab in the game.
	_corner_to_pos = IntoGrabMove.hanging_pose(player, player.config,
			{"edge": new_edge, "face_normal": new_normal})
	_corner_from_yaw = player.rotation.y
	# The same expression IntoGrabMove._target_yaw uses: the normal points back
	# at the body, so facing the wall means facing the way it came from.
	_corner_to_yaw = atan2(new_normal.x, new_normal.z)
	_corner_placed = _corner_from_yaw
	# FROM WHEREVER THE MODEL ACTUALLY IS, to squarely facing the new wall. Not
	# from the BODY's yaw: a player who has been looking along the ledge has a
	# body turned well off the face while the model is still square to it, and
	# starting the model's sweep at the body's angle would snap it that far in
	# one tick. Ending at the face's own yaw also makes each corner
	# self-correcting -- however the model got where it is, it comes out of the
	# turn squared up.
	_corner_model_from = player.visual_yaw()
	_corner_model_sweep = wrapf(_corner_to_yaw - _corner_model_from, -PI, PI)
	_corner_edge = new_edge
	_corner_normal = new_normal
	_corner_time = 0.0
	_cornering = true
	# The travel clip keeps playing: it is what the corner is animated with.
	_shimmy = side

## One tick of the corner.
##
## THE CAMERA HANDSHAKE IS TURN180MOVE'S, copied rather than reinvented, and its
## reasoning transfers exactly: this move's look clamp is an ABSOLUTE-yaw one
## (GrabConfig sets absolute_yaw_constraint), so apply_look pins the body to
## reference-plus-offset every tick from a reference captured when the clamp
## began. Writing player.rotation.y here as well would make two writers pull
## against each other once a tick -- which is the "camera twitches left and
## right" that move documents. Moving the REFERENCE instead makes them agree.
##
## ✅ And it is what "期间锁镜头" comes out as here: the view goes round with the
## body because the fan travels with it, and the player's own mouse can only add
## to that rather than fight it.
func _advance_corner(delta: float) -> void:
	_corner_time += delta
	_shimmy_report = "rounding a corner, %.2fs of %.2f" % [
		_corner_time, config.grab.corner_duration]
	var progress: float = clampf(
			_corner_time / maxf(config.grab.corner_duration, 0.001), 0.0, 1.0)
	player.global_position = _corner_from_pos.lerp(_corner_to_pos, progress)
	# Through the SHORT way round. A corner is a quarter turn; lerping the raw
	# yaws sends a body whose facing straddles PI the long way, three quarters
	# of a circle through the wall it is hanging on.
	var sweep: float = wrapf(_corner_to_yaw - _corner_from_yaw, -PI, PI)
	var wanted: float = _corner_from_yaw + sweep * progress
	var moved: float = wanted - _corner_placed
	_corner_placed = wanted
	# THE MODEL COMES TOO, and it is told WHERE rather than BY HOW MUCH.
	# GrabConfig freezes the visual yaw so a hanging body does not swivel to
	# follow the view, and that freeze would otherwise cancel this turn degree
	# for degree -- see Player.pin_visual_yaw(), which also records why the
	# by-how-much version of this drifted a model backwards over four corners.
	player.pin_visual_yaw(_corner_model_from + _corner_model_sweep * progress)
	if player.camera_rig != null:
		player.camera_rig.shift_yaw_reference(wanted, 1.0)
		# ⚠️ ORDINARY, and two attempts at making it special were both wrong.
		# The view MUST come round the corner with the body -- see
		# CameraRig.absorb_body_yaw() for the owner's reason, which is not about
		# comfort: a view left a quarter-turn off the new wall puts the player's
		# next mouse movement straight into the one-handed lock.
		player.camera_rig.absorb_body_yaw(moved)
	else:
		# No rig to place the body: drive it directly. Tests with a stub player
		# take this path.
		player.rotation.y = wanted
	if progress < 1.0:
		return
	# THE LAST SLICE HAS TO BE PLACED HERE, for Turn180Move's reason: every
	# other tick's placement is apply_look's job on the FOLLOWING tick, and the
	# tick a corner completes is the tick the hang resumes.
	if player.camera_rig != null:
		var offset: float = float(player.camera_rig.look_debug()["relative_yaw"])
		player.rotation.y = wanted + offset
	_cornering = false
	_edge = _corner_edge
	_face_normal = _corner_normal
	_shimmy = 0.0
	_shimmy_lockout = config.grab.corner_lockout

## Records one probe's segment and outcome for the debug view.
func _trace(label: String, result: Dictionary) -> void:
	if not result.has("from"):
		return
	_probe_trace.append({"label": label, "from": result["from"],
		"to": result["to"], "hit": result.get("valid", false)})
