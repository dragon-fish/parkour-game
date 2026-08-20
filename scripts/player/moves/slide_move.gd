class_name SlideMove
extends Move

# A slide is a commitment: it only PRESERVES the speed you already had (there
# is no acceleration term anywhere in it), steers poorly, and ends on its own
# terms. Everything about it is tuned to make the player choose WHERE to slide
# rather than sliding constantly -- the original's own lesson, not this
# project's former "slide adds a burst" one.
#
# Deliberately absent: Slide never transitions into a wall run. The spec
# forbids it -- chaining a slide straight into a wall run lets the player
# build speed in a loop that never has to give any back. Reaching a wall from
# a slide has to go through Walking or Jump first.
#
# NOTE that Jump is not a toll the way Walking is: a slide jump keeps its
# horizontal speed all the way to the wall, so a downhill slide into a wall
# kick is now a lossless chain. That follows from the original -- Jump is a
# launch state and every launch state holds bCheckForWallClimb -- and is the
# price of the fidelity, not an oversight. Recorded in docs/feel-backlog.md
# in case play-testing says the loop needs a brake after all. Was pinned by
# tests/legacy/test_slide_state.gd's
# test_slide_can_only_reach_ground_air_or_crouch and
# test_slide_returns_only_ground_air_or_keep -- do not add a return into that
# move here regardless. (Deliberately not spelling the move's own constant
# name in this comment: the first of those two tests greps this file's
# former path (res://scripts/player/states/slide_state.gd) for PlayerState's
# constant names verbatim, precisely so that even NAMING the forbidden target
# here -- not just returning it -- trips the tripwire.) Both tests are
# ARCHIVED by Task 1 and NOT in the running suite, so nothing enforces this
# today; restore the pins -- and their now-stale source path -- when the
# behavioural suite is rewritten.

var _elapsed: float = 0.0
var _direction: Vector3 = Vector3.ZERO
## Latched once a slide has spent itself under something too low to stand up
## in. Cleared the moment headroom returns. See _crawl().
var _crawling: bool = false

func enter(_previous: StringName) -> void:
	_elapsed = 0.0
	_crawling = false
	var horizontal := Vector3(player.velocity.x, 0.0, player.velocity.z)
	_direction = horizontal.normalized() if horizontal.length_squared() > 0.0001 else Vector3.ZERO

	player.set_capsule_height(config.slide.slide_capsule_height)

## Deliberately a REQUEST, not an unconditional restore. The off-edge exit
## below returns FALLING whether or not there is headroom — a player who walks off
## a ledge must fall, ceiling or not, so that path cannot be headroom-gated the
## way the jump path is — and _crawl() shuffling off a ledge reaches it too.
## Restoring the 1.8 m capsule here regardless would spawn it inside the roof.
## Player owes the restore and performs it the moment there is room.
func exit() -> void:
	player.request_standing_capsule()
	player.begin_slide_recovery()

## True while a spent slide is shuffling out from under a ceiling rather than
## sliding. Both are move Slide, so nothing else can tell them apart — the
## arena's traversability test reads this to prove the tunnel is cleared on
## momentum rather than rescued by the safety net.
func is_crawling() -> bool:
	return _crawling

func physics_update(delta: float, input: MoveInput) -> StringName:
	_elapsed += delta

	# Asked once per tick and reused by the crawl latch and the jump gate, so
	# the two cannot disagree within a single frame.
	# `player` is deliberately untyped (see Move), so its return values
	# arrive as Variant and need an explicit type here.
	var blocked: bool = not player.has_headroom()
	var speed := Vector2(player.velocity.x, player.velocity.z).length()

	if not blocked:
		_crawling = false
	elif speed <= config.slide.slide_abort_speed:
		_crawling = true

	if _crawling:
		_crawl(input)
	else:
		_slide(delta, input, speed)

	# A jump out of a slide is refused under a roof on its own merits, quite
	# apart from the capsule: you cannot jump into a ceiling. (The capsule is
	# separately safe either way — see exit().) has_headroom() is checked BEFORE
	# consume_jump() so the short-circuit leaves the buffered press unspent:
	# press jump inside the tunnel and it fires the moment you clear the roof,
	# rather than being silently eaten.
	if not blocked and player.consume_jump():
		player.velocity.y = config.pawn.base_jump_z
		player.velocity += player.jump_add_velocity(input)
		player.move_and_slide()
		player.set_grounded(player.is_on_floor())
		# JUMP, not FALLING -- the same hand-off WalkingMove's own jump branch
		# makes. This IS a take-off (velocity.y was just set to base_jump_z),
		# and "is this a launch" is expressed by WHICH STATE owns the tick,
		# never by a speed guard: only Jump carries check_for_wall_climb, and
		# only Falling may hand off to FallingUncontrolled (invariant I2).
		# Returning Falling here left a slide jump unable to reach a wall AND
		# immediately eligible for the uncontrolled-fall height check, neither
		# of which a rising take-off should ever be.
		return JUMP

	# Same ankle-high clutter allowance WalkingMove gets. Without it a slide is
	# stopped dead by a kerb the same body walks over for free, which reads as
	# the geometry being sticky rather than as a rule. Applies to the crawl
	# too: shuffling out from under a roof has the same problem.
	var rise: float = player.try_step_up(delta)
	# ANY rise, however small. A threshold here was tried and made things worse:
	# a step often arrives over two or three ticks (0.299, then 0.077, 0.037,
	# 0.012 as the body creeps onto it), and the ones below the threshold moved
	# the body without compensating the camera -- which is a hard jump, exactly
	# the flicker the offset exists to prevent. Ramps are refused inside
	# try_step_up() now, so anything that still produces a rise is a real step.
	if rise > 0.0 and player.camera_rig != null:
		player.camera_rig.add_step_offset(rise)

	player.move_and_slide()
	# Geometry can throw the body clear of the floor for a tick -- riding up and
	# off a small sloped obstacle does exactly that -- and without this the tick
	# reads as a ledge exit and cancels the move. See Player.try_step_down().
	# `or` the step-down: moving the body directly does not refresh
	# is_on_floor(), so its own answer is what says the body was caught.
	var stepped_down: bool = player.try_step_down()
	player.set_grounded(player.is_on_floor() or stepped_down)

	if not player.grounded:
		# A step-up lifts the body in place and lets move_and_slide() carry it
		# forward onto the step, so the tick it fires ALWAYS ends airborne --
		# by construction, not by accident. Reading that tick as "walked off a
		# ledge" is what turned riding a 0.30 m kerb into
		# Slide -> Falling -> Grab -> Falling -> Walking: the slide was
		# cancelled by clutter it had successfully ridden over, and the same
		# airborne tick handed the kerb to the ledge probe.
		if player.in_step_grace():
			return KEEP
		player.velocity.y = 0.0
		return FALLING

	# Read speed back AFTER move_and_slide(): a collision (e.g. sliding into a
	# wall) can shave it down well below the friction-only decay computed
	# above. Using the pre-move value here would let a wall impact leave the
	# slide "stuck" in place until slide_abort_time expires instead of
	# ending promptly.
	var post_move_speed := Vector2(player.velocity.x, player.velocity.z).length()

	# Every exit passes the same headroom gate: crouch-release, speed decay and
	# timeout alike. Stand up into a ceiling once and the body clips through
	# it, so a blocked slide simply continues — crawling, by then.
	# has_headroom() is re-asked here rather than reusing `blocked`, because
	# the move_and_slide() above may have carried the body clear of the roof
	# on this very tick.
	#
	# A slide that ran itself out (speed decay or timeout, NOT the key being
	# released) settles into CROUCH when the key is still held, rather than
	# snapping the player upright the instant speed runs out -- the owner's
	# direction on GBA_Crouch's downward branch. No separate headroom check is
	# needed for the Crouch hand-off: crouch_capsule_height defaults to the
	# same number as slide_capsule_height (see CrouchConfig's own comment),
	# so anywhere the slide capsule already fits, the crouch capsule fits too.
	# Releasing the key still asks for the full standing capsule, exactly as
	# before.
	var spent := post_move_speed <= config.slide.slide_abort_speed or _elapsed >= config.slide.slide_abort_time
	var wants_to_exit := (not input.crouch_held) or spent
	if wants_to_exit and player.has_headroom():
		if input.crouch_held:
			return CROUCH
		return WALKING
	return KEEP

## The slide proper: committed steering, friction, and slope.
func _slide(delta: float, input: MoveInput, speed: float) -> void:
	# Steering is deliberately slow: a slide commits you to a line.
	var wish_dir: Vector3 = player.wish_direction(input)
	if wish_dir != Vector3.ZERO and _direction != Vector3.ZERO:
		var max_turn := config.slide.slide_steer_rate * delta
		var angle := _direction.signed_angle_to(wish_dir, Vector3.UP)
		_direction = _direction.rotated(Vector3.UP, clampf(angle, -max_turn, max_turn))

	# Slope drives FRICTION, not a made-up acceleration bonus (03 §3.3).
	# Uphill multiplies friction by 5.0 -- an uphill slide stops almost
	# immediately -- while downhill drops it to 1.8x. `grade` is +1 straight
	# down the fall line, matching Friction's own convention.
	var slope_dir := _slope_direction()
	var grade := -slope_dir.y
	var decel: float = Friction.slide_friction(config.pawn, cfg.friction_modifier, grade)

	# ORDINARY GRAVITY, not a reinstated slide_slope_accel: the deleted field
	# was an invented bonus layered ON TOP of friction; this is the plain
	# along-slope component of the SAME gravity every other move already
	# falls under, g * sin(angle) = gravity * grade. Without it the scalar
	# speed above can only ever decay, on every grade, at every angle -- a
	# descent would merely be SLOWER to stop than a climb, never faster,
	# which is not what 05 §5.1 describes. Past the break-even grade (where
	# this exceeds decel -- ~18.2 degrees at this project's current
	# constants; see test_slide.gd's BREAK_EVEN_GRADE for the derivation) a
	# downhill slide genuinely nets speed; below it, friction still wins and
	# the slide simply carries further before stopping. Below the break-even
	# grade this differs from pure-friction decay in RATE, not sign; only
	# past it does the sign flip.
	var gravity_along: float = config.pawn.gravity * grade
	speed = maxf(speed + (gravity_along - decel) * delta, 0.0)

	# Drive along the SLOPE, scaled so the horizontal magnitude is still
	# `speed`. Steering the body horizontally instead would leave a descent to
	# floor_snap_speed alone, which is not enough to hold the body on a steep
	# ramp at slide speeds — it would part company with the floor and drop the
	# slide into Falling partway down.
	var horizontal_len := Vector2(slope_dir.x, slope_dir.z).length()
	if horizontal_len > 0.001:
		var velocity := slope_dir * (speed / horizontal_len)
		player.velocity.x = velocity.x
		player.velocity.z = velocity.z
		player.velocity.y = velocity.y - config.pawn.floor_snap_speed
	else:
		player.velocity.x = 0.0
		player.velocity.z = 0.0
		player.velocity.y = -config.pawn.floor_snap_speed

## The slide is spent but there is a roof directly overhead, so standing up is
## impossible and the exit to Walking is gated shut. Rather than sit at zero
## speed forever with no transition available and no way in this move to
## generate any, let the player shuffle out under their own input. Steering is
## immediate here, not the slide's committed line: this is no longer a slide,
## it is someone getting out from under something.
func _crawl(input: MoveInput) -> void:
	var wish_dir: Vector3 = player.wish_direction(input)
	if wish_dir == Vector3.ZERO:
		player.velocity.x = 0.0
		player.velocity.z = 0.0
	else:
		_direction = wish_dir
		player.velocity.x = wish_dir.x * config.slide.slide_crawl_speed
		player.velocity.z = wish_dir.z * config.slide.slide_crawl_speed
	player.velocity.y = -config.pawn.floor_snap_speed

## The slide line projected onto the floor plane, as a unit vector. Falls back
## to the horizontal line whenever there is no usable floor normal to project
## against, which makes every caller behave exactly as it did before slopes
## existed.
func _slope_direction() -> Vector3:
	if _direction == Vector3.ZERO or not player.grounded:
		return _direction
	var normal: Vector3 = player.get_floor_normal()
	if normal.length_squared() < 0.0001:
		return _direction
	var projected := _direction - normal * _direction.dot(normal)
	if projected.length_squared() < 0.0001:
		return _direction
	return projected.normalized()
