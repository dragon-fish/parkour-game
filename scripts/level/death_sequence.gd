class_name DeathSequence
extends Node

# ⚠️ Every number here is project-defined. The original plays a cutscene at
# this point and its data says nothing about camera timing.
#
# Owned by the level rather than by a Move, because by the time this runs the
# body has no state left to be in -- see spec §1 on the two orthogonal state
# machines.

signal finished

## ⚠️ All four are project-defined, and all four come from the owner's own
## storyboard rather than from the original -- which plays a cutscene here and
## whose data says nothing about camera timing.
##
## The two HOLDS are the point of the shape: the body arrives, stops, and only
## then gives way, and it lies still afterwards instead of cutting straight to
## a respawn. Without them the whole thing reads as one continuous slump.
const DROP_TIME := 0.5      ## eye height -> half height, the legs going
const HOLD_TIME := 1.0      ## knelt, not yet fallen
const TOPPLE_TIME := 1.5    ## quarter circle to the right, pivoting near the feet
const REST_TIME := 1.0      ## lying still before the level takes over

## ⚠️ PROJECT-DEFINED. How far above the floor the arc bottoms out, so the view
## ends up cheek-to-the-ground rather than inside it -- a camera pivoting on
## the feet exactly would put its near plane through the floor and show the
## underside of the level.
const GROUND_CLEARANCE := 0.15

## ⚠️ PROJECT-DEFINED. The floor under the elastic overshoot. easeOutElastic
## deliberately goes PAST its target and springs back -- that overshoot is the
## impact -- but the arc's target is already only GROUND_CLEARANCE above the
## floor, so unguarded it would drive the near plane through the ground and
## show the underside of the level for a few frames.
const MIN_GROUND_CLEARANCE := 0.05

## ⚠️ PROJECT-DEFINED, both tuned by eye. How much of the springy curve to mix
## in over a plain ease-out: 0 is no spring at all, 1 is the textbook easing
## function at full strength. Full strength on either of these reads as comedy
## rather than as weight -- the knees bounce like rubber, the body flops.
const DROP_ELASTIC := 0.35     ## knees giving way: springs, lightly
const TOPPLE_BOUNCE := 0.45    ## the body landing: settles in a beat or two

var _player: Player
var _elapsed: float = 0.0
var _playing: bool = false
var _eye_height: float = 0.0

## Where the FEET are, in the rig's own local space -- i.e. how far below the
## Player origin the ground is. The rig hangs off the Player node, whose origin
## sits at the capsule's CENTRE, so local y = 0 is roughly half a body above
## the floor rather than on it. Without this the topple arc pivoted around the
## capsule centre and bottomed out a half-body short of the ground: the view
## rolled over but never came down, which is not what falling over looks like.
var _feet_offset: float = 0.0

## The pitch the player happened to be looking at when they died, eased out
## over the drop. Watching the ground rush up is the reflex on a fatal fall, so
## without this the whole topple plays from a face-down view.
var _entry_pitch: float = 0.0

## Whether THIS death is driving the camera. False in third person, where the
## body's own death clip does the work -- see play().
var _cinematic: bool = false

## How long the screen spends going black at the END of a death, in seconds.
##
## ✅ The owner, on the one genuinely awkward part of a ragdoll -- that it is a
## one-way door and the body is left in whatever pose physics chose: "we can
## black the screen for a moment on respawn. Games and film are the art of
## deception; if you cannot do it well, cover it up." Quite right, and it is
## what every game does with a respawn anyway.
const BLACKOUT := 0.35

## ✅ THE OWNER: "死亡的黑屏应该在重置回检查点之后再覆盖个0.5s，并且期间禁操作，
## 因为现在这个还是能看到镜头瞬移和身体从死亡站起来，很尴尬." The respawn
## happens UNDER full black; the cover holds RESPAWN_COVER with the input
## locked, then lifts over COVER_FADE.
const RESPAWN_COVER := 0.5
const COVER_FADE := 0.25

## True once this death handed the body to the physics solver, so the release
## knows to take it back.
var _ragdolled: bool = false
## Seconds of post-respawn cover (hold + fade) still to run. Independent of
## _playing on purpose: reset_player() calls stop(), and the cover must
## survive the very reset it exists to hide.
var _cover_left: float = 0.0

func total_duration() -> float:
	return DROP_TIME + HOLD_TIME + TOPPLE_TIME + REST_TIME

func play(player: Player) -> void:
	_player = player
	_elapsed = 0.0
	_playing = true
	if _player != null:
		# config is only absent for a bare Player.new() that skipped setup()
		# (some headless tests do exactly that); guard it the same way the
		# camera_rig/screen_effects calls below are guarded, rather than
		# assuming a live Player always has one.
		if _player.config != null:
			_eye_height = _player.config.camera.eye_height
		# Half the standing capsule, because the Player origin is its centre.
		# standing_height() rather than the live height: the body may already
		# be crouched or sliding when it dies, and the fall should read from
		# where a standing body's feet are.
		_feet_offset = _player.standing_height() * 0.5
		_player.set_dying(true)
		# ALREADY GOING, usually. ✅ The owner: the ragdoll begins when control
		# is lost, which is FallUncontrolledMove.enter() -- long before the body
		# lands and this sequence starts. Recorded here only so the release
		# knows to take it back.
		#
		# Still started here for the deaths that never went through an
		# uncontrolled fall, if any ever do.
		# ⚠️ THE SWITCH IS CHECKED HERE TOO. ✅ The owner, with the flag already
		# off: "how is the landing death still a ragdoll?" Because this is a
		# SECOND way in -- FallUncontrolledMove starts one on the way down, and
		# this starts one for a death that never fell. Gating only the first
		# left the second wide open.
		if _player.ragdoll_enabled and _player.ragdoll != null and _player.body != null:
			if not _player.ragdoll.is_simulating() 					and _player.ragdoll.build(_player.find_skeleton()):
				_player.ragdoll.start(_player.velocity * 0.5, _player.get_rid())
			_ragdolled = _player.ragdoll.is_simulating()
		if _player.camera_rig != null:
			# BEFORE the branch below, and in both views. A fatal fall lands
			# like any other, so the landing flinch has already been written by
			# the time the death is known -- died_from_fall is deferred a frame.
			# ✅ The owner: a death should skip the ordinary landing cushion.
			_player.camera_rig.clear_landing_dip()
			# THE SCRIPTED FALL IS THE FALLBACK NOW, not the default.
			#
			# It exists because a bodiless player has nothing to watch: the eye
			# falls, rolls and ends up looking at the sky because that is what
			# the body would be doing, and there is no body doing it.
			#
			# ✅ With a body there IS, and the owner found the proof by
			# accident: dying in third person and pressing V mid-clip "lines up
			# really well with the animation". Of course it does -- a
			# third-person death already skips the cinematic, so the eye runs
			# the ordinary path and the head-follow carries it along with the
			# death clip. Two scripted falls fighting over the same transform is
			# what the cinematic branch was ever protecting against.
			#
			# So: no body, no head to follow, keep the old effect. A body, and
			# the animation does the work -- all the eye needs is somewhere to
			# point, which is the line below.
			_cinematic = _player.body == null
			if not _cinematic:
				var camera_config: CameraConfig = _player.config.camera
				# ⚠️ THE OTHER WAY ROUND IN THIRD PERSON, and the geometry says
				# why: the camera hangs BEHIND the rig, so pitching the rig up
				# swings the arm DOWN -- straight into the floor a dead body is
				# lying on. ✅ The owner reported exactly that.
				var third: bool = _player.camera_rig.third_person
				_player.camera_rig.set_pitch(deg_to_rad(
					camera_config.death_pitch_third_person_deg if third
					else camera_config.death_pitch_deg))
				# First person only: the head-follow puts the eye where the head
				# bone is, and a body on the floor has its head ON the floor.
				if not third:
					_player.camera_rig.set_death_lift(camera_config.death_eye_lift)
			if _cinematic:
				# Read BEFORE begin_cinematic(), while rotation.x is still the
				# player's own look.
				_entry_pitch = _player.camera_rig.rotation.x
				_player.camera_rig.begin_cinematic()
		if _player.screen_effects != null:
			_player.screen_effects.set_desaturation(1.0)
		_player.lock_input()

func _physics_process(delta: float) -> void:
	if _cover_left > 0.0:
		_cover_left -= delta
		if _player != null and _player.screen_effects != null:
			_player.screen_effects.set_tint(Color.BLACK,
				clampf(_cover_left / COVER_FADE, 0.0, 1.0))
		if _cover_left <= 0.0:
			_end_cover()
		return
	if not _playing:
		return
	_elapsed += delta
	if _cinematic and _player != null and _player.camera_rig != null:
		var pose := _pose_at(_elapsed)
		_player.camera_rig.set_cinematic_pose(pose[0], pose[1], pose[2])
	# THE CURTAIN. Ramped over the last BLACKOUT seconds, so the moment the
	# solver is taken away -- and the skeleton snaps back to whatever the
	# animation wanted -- happens behind it.
	if _player != null and _player.screen_effects != null:
		var into_blackout: float = _elapsed - (total_duration() - BLACKOUT)
		_player.screen_effects.set_tint(Color.BLACK,
				clampf(into_blackout / BLACKOUT, 0.0, 1.0))
	if _elapsed >= total_duration():
		_release_player()
		finished.emit()
		# THE COVER. The emit above IS the respawn (Arena wires finished ->
		# reset_player), so the teleport and the body standing back up have
		# just happened under full black -- and the reset also re-opened the
		# input gate and cleared the tint, so both are re-asserted here.
		_cover_left = RESPAWN_COVER + COVER_FADE
		if _player != null:
			_player.lock_input()
			if _player.screen_effects != null:
				_player.screen_effects.set_tint(Color.BLACK, 1.0)

## Cancels a sequence in progress. The level calls this whenever it respawns by
## some other route (the manual reset key), because a sequence left running
## would fire `finished` -- and therefore a second respawn -- long after the
## player got on with their life.
##
## Deliberately does NOT emit `finished`: this is a cancellation, not a
## completion, and Arena wires `finished` straight to reset_player(), which is
## the very thing being cancelled. Safe to call at any time -- on a sequence
## that never started, or from inside the `finished` handler itself (by then
## _release_player() has already cleared _playing, so this returns immediately
## and the finished -> reset_player -> stop chain cannot recurse).
func stop() -> void:
	# A manual reset during the cover takes the cover with it -- the player
	# asked for a fresh start, not a black screen over one.
	if _cover_left > 0.0:
		_end_cover()
	if not _playing:
		return
	_release_player()

## Lifts the post-respawn cover: the tint goes, the input gate re-opens.
func _end_cover() -> void:
	_cover_left = 0.0
	if _player == null:
		return
	if _player.screen_effects != null:
		_player.screen_effects.set_tint(Color.BLACK, 0.0)
	_player.unlock_input()

## Everything a sequence owes the player on its way out, shared by the normal
## end above and by stop() so the two cannot drift apart: the camera comes back
## from cinematic, the screen loses the death desaturation, and the input gate
## opens. Whether `finished` fires is the CALLER's business, and is the only
## thing that separates finishing from being cancelled.
func _release_player() -> void:
	_playing = false
	if _player == null:
		return
	_player.set_dying(false)
	if _ragdolled and _player.ragdoll != null:
		_player.ragdoll.stop()
		_ragdolled = false
	if _player.camera_rig != null:
		_player.camera_rig.set_death_lift(0.0)
	# Symmetrically: only ended if it was ever begun. end_cinematic() on a rig
	# that never entered it would clear a state the player owns.
	if _cinematic and _player.camera_rig != null:
		_player.camera_rig.end_cinematic()
	_cinematic = false
	if _player.screen_effects != null:
		_player.screen_effects.set_desaturation(0.0)
	_player.unlock_input()

## Local camera offset, roll and pitch at time t. Returns [Vector3, float, float].
##
## Everything below is worked in EYE-ABOVE-GROUND terms and converted to a rig
## offset at the end, because the storyboard is drawn from the ground: the view
## drops to half the body's height, holds, then sweeps a quarter circle of that
## same radius pivoting near the feet -- ending flat on the floor, offset to the
## side by as much as it lost in height.
func _pose_at(t: float) -> Array:
	# Ground to eye, which is what "half height" in the storyboard means.
	var stature: float = _feet_offset + _eye_height
	var half: float = stature * 0.5
	if t < DROP_TIME:
		# Elastic: the legs do not lower the body, they FAIL. It drops past
		# where it comes to rest and springs back -- that overshoot is what
		# reads as weight rather than as a controlled crouch.
		var u: float = t / DROP_TIME
		var k: float = _ease_out_elastic(u, DROP_ELASTIC)
		# Pitch levels on a PLAIN ease-out, not the elastic one. The elastic
		# curve overshoots by design, and overshooting a level view means
		# looking UP -- measured at +0.057 rad partway through the drop, i.e.
		# the dying body glancing at the sky. Height and roll want that
		# overshoot; the direction of gaze does not.
		var k_pitch: float = 1.0 - pow(1.0 - u, 2.0)
		return [Vector3(0.0, _to_offset(lerpf(stature, half, k)), 0.0), 0.0,
			lerpf(_entry_pitch, 0.0, k_pitch)]
	if t < DROP_TIME + HOLD_TIME:
		return [Vector3(0.0, _to_offset(half), 0.0), 0.0, 0.0]
	# BOUNCE, not elastic. Elastic overshoots its target and springs back around
	# it, which on a body hitting the floor reads as rubber. Bounce approaches
	# from one side and settles in a couple of diminishing hops -- the head
	# meeting the ground and coming to rest, which is what this is.
	#
	# Past TOPPLE_TIME the clamp holds this final pose for REST_TIME, which is
	# what makes the body lie still at the end.
	var u: float = clampf((t - DROP_TIME - HOLD_TIME) / TOPPLE_TIME, 0.0, 1.0)
	var k2: float = _ease_out_bounce(u, TOPPLE_BOUNCE)
	# A QUARTER CIRCLE, not a slide sideways and not a drop straight down: the
	# head is on the end of a body that pivots at the floor, so it sweeps an arc
	# of radius `radius` -- losing height and gaining offset together, fastest
	# through the middle of the turn.
	#
	# Pivots on a point just ABOVE the feet, so the arc bottoms out at
	# GROUND_CLEARANCE instead of at the floor itself. The radius shrinks to
	# match, which keeps the arc starting exactly where the drop left off.
	#
	# X AND ROLL MUST AGREE. A roll of -angle turns the camera's up axis toward
	# its RIGHT, i.e. the body is going over to the right, so the head has to
	# travel right as well (+X). It used to travel left while rolling right,
	# and the two cancelling out read as the head dropping straight down and
	# the picture rotating around it -- no waist, no volume, just a spin.
	var angle: float = k2 * PI * 0.5
	var radius: float = maxf(half - GROUND_CLEARANCE, 0.01)
	# maxf, because the elastic overshoot drives the angle past a quarter turn
	# and cos() negative with it. The head is allowed to come lower than the
	# resting clearance on the impact -- that IS the impact -- but not through
	# the floor.
	var above_ground: float = maxf(GROUND_CLEARANCE + radius * cos(angle),
		MIN_GROUND_CLEARANCE)
	var y: float = _to_offset(above_ground)
	var x: float = radius * sin(angle)
	return [Vector3(x, y, 0.0), -angle, 0.0]

## The plain curve both springy forms are blended back toward, so `strength`
## can dial either of them down without changing its shape.
static func _ease_out_quad(x: float) -> float:
	return 1.0 - pow(1.0 - x, 2.0)

## easeOutElastic at `strength`, blended toward a plain ease-out. Overshoots
## its target and springs back around it: the knees going past where they come
## to rest. At full strength it reads as rubber, hence the blend.
static func _ease_out_elastic(x: float, strength: float) -> float:
	if x <= 0.0:
		return 0.0
	if x >= 1.0:
		return 1.0
	const PERIOD := TAU / 3.0
	var full: float = pow(2.0, -10.0 * x) * sin((x * 10.0 - 0.75) * PERIOD) + 1.0
	return lerpf(_ease_out_quad(x), full, strength)

## easeOutBounce at `strength`, blended toward a plain ease-out. Unlike elastic
## this never passes its target -- it arrives, rebounds, and settles in a few
## diminishing hops, which is what a body meeting the floor does.
static func _ease_out_bounce(x: float, strength: float) -> float:
	if x <= 0.0:
		return 0.0
	if x >= 1.0:
		return 1.0
	const N1 := 7.5625
	const D1 := 2.75
	var full: float
	if x < 1.0 / D1:
		full = N1 * x * x
	elif x < 2.0 / D1:
		var a: float = x - 1.5 / D1
		full = N1 * a * a + 0.75
	elif x < 2.5 / D1:
		var b: float = x - 2.25 / D1
		full = N1 * b * b + 0.9375
	else:
		var c: float = x - 2.625 / D1
		full = N1 * c * c + 0.984375
	return lerpf(_ease_out_quad(x), full, strength)

## Converts a height ABOVE THE GROUND into the rig-local offset that
## CameraRig.update_effects() adds to its resting eye position.
func _to_offset(above_ground: float) -> float:
	return above_ground - _feet_offset - _eye_height
