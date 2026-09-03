class_name TutorialIntro
extends Node

# The tutorial's opening shot, and the hand-over out of it.
#
# THE FIGURE IN THE SHOT IS NOT THE PLAYER. She is a SilhouetteBody: a bare
# model with its own AnimationPlayer and nothing else writing her bones. The
# real Player stands in the same spot with her body hidden and her input
# locked, and the two are swapped on the frame the stand-up ends -- both are
# the same red silhouette in the same place, so the cut is not visible.
#
# THIS IS A DECEPTION AND IT IS ALLOWED TO BE ONE. Posing the real Player was
# tried and it does not work: her skeleton has an AnimationTree fed by the move
# machine, a HeadLook modifier turning the neck toward the lens every frame,
# clip-offset drivers and spring bones on it, and silencing them one at a time
# means the one that gets missed is on screen -- a neck twisted toward a
# side-on camera, and a body stuck in the crouch clip through every move made
# afterwards. Both of those shipped. DO NOT bring the AnimationTree, the
# modifiers or AnimationPlayer.play() on the real body back into this file.
#
# NOTHING CUTS AND NOTHING COVERS. The camera is the Player's own rig, parked,
# so standing up, the lens coming round behind her and control arriving are one
# continuous shot inside one scene -- no load, no swap, no curtain. DO NOT
# reintroduce a transition anywhere in this file.
#
# THE PLAYER IS NOT SET UP WHEN THIS NODE IS READY. A child's _ready() runs
# before its parent's, so Arena._ready() has not yet called player.setup() and
# there is no move manager, no config and no mounted body to reach for. Every
# reach into the Player happens from _physics_process instead, on the first
# tick that finds it built -- the same trap TutorialDirector already fell into.
#
# AND IT RUNS AFTER THE PLAYER IN TREE ORDER, deliberately: CameraRig's own
# update_effects() must have run once before the cutscene freezes it, or the
# camera child is left at the origin and the body is left rendering both of its
# layer variants at once.

## The body whose place the stand-in takes and whose camera films it. Without
## one this node hands over immediately, so a level that forgot to wire it is
## playable rather than frozen.
@export var player: Player

## Seconds the stand-up and the camera move take. They are ONE beat: the body
## reaches fully standing on the frame the camera lands. Keep it equal to
## MainMenu.RISE_TIME -- the two openings are the same move.
@export var rise_time: float = 1.5

## The blend the stand-up falls back to when the model has no real Crouch_Exit
## clip. Same value and same reason as MainMenu.BODY_STAND_BLEND.
@export var stand_blend: float = 1.5

## The held shot, in the body's own frame, measured from its origin (the
## capsule's centre, ~0.95 m off the floor).
##
## PLACEHOLDERS. Nothing here can be solved -- the figure's height depends on
## whichever model is mounted, and whether the framing reads is a matter for
## the eye. These put the lens off her right shoulder at roughly the main
## menu's close-up: profile, head towards screen right, filling most of the
## frame.
@export var shot_right: float = 1.3
@export var shot_height: float = -0.10
@export var shot_forward: float = -0.11
## Where the lens points, degrees in the body's frame. 90 looks along the
## body's own -X, i.e. straight at her from her right, which puts her head
## towards screen right the way the menu's opening plate does.
@export var shot_yaw_degrees: float = 90.0
@export var shot_pitch_degrees: float = 0.0
## The close-up's field of view. The game's own fov_base is far wider -- a
## portrait framed at it would want the lens close enough to clip through her.
@export var shot_fov_degrees: float = 55.0

## The world the shot is composed against, so the opening can flatten it and
## hand the level's own palette back as she rises.
@export var world: WorldEnvironment
@export var plain_mesh: MeshInstance3D

## What sky and floor are painted while she is still crouching: the menu's own
## flat near-white, one colour with no horizon and no sheen in it.
##
## THE MENU IS A FLAT 2D PLATE AND THIS IS A LIT 3D WORLD. Standing them side
## by side, the level's graduated sky and its mirror of a floor read as a
## different place -- which is exactly what the opening must not be. Starting
## here and arriving at the level's own palette over the rise is what makes
## them the same shot.
@export var opening_colour: Color = Color(0.96, 0.96, 0.94)

## Emitted the instant control reaches the player. LevelZero starts the
## tutorial's own beats off this rather than off its _ready(), so nothing is
## said over a shot the player cannot act in.
signal handed_over

## Above ScreenEffects (100) so nothing the camera does can wash the mark out,
## and below PauseUi (200) so Esc still puts a menu over the whole thing.
const PLATE_LAYER := 150

# THE FRONT DOOR'S OWN FRAMING, not an approximation of it. The menu solves its
# shot from the figure's actual skeleton -- how tall the crouch is decides how
# far back the lens goes -- so hand-typed offsets here can only ever be near
# it, and "near" is what the eye reads as a different shot. These are
# MainMenu's values; change them there and here together, or better, look at
# why they diverged.
#
# CLOSE_BODY_FRAC is what makes it a close-up: the crouched upper body fills
# 85% of the frame's height. A medium shot is what you get for leaving it out.
const MENU_FOV_DEG := 55.0
## Where the head lands on screen and how much of the frame the crouch fills.
## MainMenu's own values, exposed because matching the front door by eye is the
## only way to finish the job -- nothing headless can see whether they agree.
@export var head_x_frac: float = 0.55
@export var head_y_frac: float = 0.34
@export var close_body_frac: float = 0.85
const MENU_HEAD_TOP_PAD := 0.16
const MENU_FRONT_YAW_DEG := -180.0
const MENU_CLOSE_AZIMUTH_DEG := 180.0
const MENU_FALLBACK_CROUCH_HEAD := 0.82
const MENU_FALLBACK_CROUCH_HIPS := 0.51

enum _State { WAITING, HELD, RISING, DONE }

var _state: int = _State.WAITING
var _elapsed: float = 0.0
var _stood_up: bool = false
## Where the ordinary third-person camera sits, captured the tick the shot
## takes over. The rise ends exactly there, so handing the rig back is not a
## cut -- see _pose().
var _seat: Vector3 = Vector3.ZERO
## The camera child's own aim, zeroed for the shot so the rig's yaw is the
## only thing pointing the lens -- otherwise whatever pitch it was carrying
## tips the solved framing and the head slides off the top of the frame.
var _seat_rot: Vector3 = Vector3.ZERO
## Where the rig itself rests, captured on the same tick as _seat. The blend
## ends HERE rather than at the rig's nominal eye position: the resting spot
## also carries the eye's forward offset and the head-follow, and a rise that
## ignored those would step ~0.2 m sideways on the frame control arrives.
var _rest: Vector3 = Vector3.ZERO
var _base_fov: float = 90.0

## The stand-in. Null on a machine with no body linked, which is a shot with
## nobody in it and still a level that hands over control.
var performer: SilhouetteBody

var _plate_layer: CanvasLayer
var _plate: MeOpeningPlate

## The solved shot, in the rig's own local space. Falls back to the shot_*
## exports when there is no performer to measure.
var _solved := false
var _shot_local: Vector3 = Vector3.ZERO
var _shot_yaw: float = 0.0

## The level's own palette, read once at the top of the shot and blended back
## in over the rise. Null until _begin_shot() has run, and null forever in a
## level that wired neither.
var _sky: ProceduralSkyMaterial = null
var _floor_material: ShaderMaterial = null
var _sky_authored: Dictionary = {}
## How cold this level's ambient is, read once so the opening can flatten it
## to neutral and hand it back. See Arena._process().
var _ambient_strength: float = 1.0
var _floor_authored: Dictionary = {}

## True until control reaches the player -- from before the first tick, through
## the held shot and the rise, up to the frame `handed_over` fires.
func is_holding() -> bool:
	return _state != _State.DONE

# THE MARK IS UP FROM THE FIRST FRAME, which is why it is built here and not
# on the tick the shot begins. The router that launched this level shows a bare
# ground and no mark of its own precisely so that this one can be the only one
# on screen; a mark that waited for the player to finish setting up would be
# the flash-and-vanish that started this rework.
func _ready() -> void:
	_plate_layer = CanvasLayer.new()
	_plate_layer.name = "OpeningPlate"
	_plate_layer.layer = PLATE_LAYER
	add_child(_plate_layer)
	# The front door's paper grain, on the same layer and under the plate so
	# it grains the world rather than the logo.
	_plate_layer.add_child(MeTheme.paper_noise_layer())
	_plate = MeOpeningPlate.new()
	_plate_layer.add_child(_plate)
	_plate.open()

func _physics_process(delta: float) -> void:
	if _state == _State.DONE:
		return
	if player == null or player.camera_rig == null:
		_hand_over()
		return
	# The mark that Arena._ready() has been through: setup() is what builds the
	# move manager and gives the rig its config.
	if player.move_manager == null or player.config == null:
		return

	match _state:
		_State.WAITING:
			_begin_shot()
		_State.HELD:
			# EVERY TICK, not once. Player.reset_state() clears the lock, and
			# Arena calls it on any respawn -- including one that lands while
			# the shot is still held.
			player.lock_input()
			_free_the_pointer()
			_pose(0.0)
			_paint(0.0)
		_State.RISING:
			_elapsed += delta
			var k: float = clampf(_elapsed / maxf(rise_time, 0.001), 0.0, 1.0)
			if not _stood_up and _elapsed >= _stand_up_delay():
				_stood_up = true
				if performer != null:
					performer.start_stand_up(stand_blend)
			# Cubic ease-in-out, the shape the menu's own rise uses.
			var eased: float = k * k * (3.0 - 2.0 * k) if k < 1.0 else 1.0
			_pose(eased)
			_paint(eased)
			if k >= 1.0:
				_hand_over()

func _unhandled_input(event: InputEvent) -> void:
	if _state != _State.HELD:
		return
	# THE SAME GATE THE MENU USES: a press during the opening hold, before the
	# invitation is on screen, is not an answer to anything.
	if _plate != null and not _plate.prompt_shown:
		return
	var pressed_key: bool = event is InputEventKey \
		and (event as InputEventKey).pressed and not (event as InputEventKey).echo
	var clicked: bool = event is InputEventMouseButton \
		and (event as InputEventMouseButton).pressed
	if not (pressed_key or clicked):
		return
	_state = _State.RISING
	_elapsed = 0.0
	if _plate != null:
		_plate.dismiss()

func _begin_shot() -> void:
	player.lock_input()
	var rig: CameraRig = player.camera_rig
	_seat = rig.camera.position if rig.camera != null else Vector3.ZERO
	_seat_rot = rig.camera.rotation if rig.camera != null else Vector3.ZERO
	_rest = rig.position
	_base_fov = player.config.camera.fov_base
	rig.begin_cinematic()
	_capture_palette()
	_raise_performer()
	_solve_shot()
	_state = _State.HELD
	_pose(0.0)
	_paint(0.0)
	# APPLIED ON THIS TICK, not left for the next one. The Player runs before
	# this node and has already placed the rig for the ordinary view; without
	# this the level's first frame is drawn from behind her and the shot cuts in
	# afterwards. Player itself calls update_effects the same way with a zero
	# delta -- in the cinematic branch it only copies the pose across.
	rig.update_effects(0.0, 0.0, player.grounded)

func _stand_up_delay() -> float:
	return performer.stand_up_delay(rise_time) if performer != null else 0.0

## Places the lens for a blend factor k: 0 is the held profile, 1 is exactly
## where the ordinary third-person camera sits, so end_cinematic() lands on the
## frame the rig would have drawn anyway.
## Sky and floor over the rise. DUPLICATED FIRST, both of them: the sky is a
## sub-resource of a scene that may be instanced more than once in a session,
## and materials/acrylic_void.tres is shared with the debug plain -- painting
## either in place would repaint everything else that has it.
## THE POINTER IS THE PLAYER'S UNTIL THE GAME STARTS. Before the click this is
## the front door, and a front door does not grab the mouse -- the menu leaves
## it visible and so must this. EVERY TICK, not once: Arena._ready() captures
## it and runs AFTER this node's _ready() (a child is ready before its parent),
## and PauseUi recaptures on resume.
func _free_the_pointer() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

## And the level takes it back with control, on its own terms -- a level that
## wants a free cursor (the animation lab is one) still gets one.
func _take_the_pointer() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var arena := get_parent() as Arena
	if arena != null and not arena.capture_mouse:
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

## Reproduces MainMenu._solve_framing() / _place_cam() against the performer,
## then expresses the answer in the rig's local space. The rig is a child of
## the Player, so everything world-space has to come back through the player's
## own transform before it means anything to set_cinematic_pose().
func _solve_shot() -> void:
	if performer == null or player == null:
		return
	var view: Viewport = get_viewport()
	var size: Vector2 = Vector2(1920.0, 1080.0)
	if view != null:
		size = view.get_visible_rect().size
	var tan_v: float = tan(deg_to_rad(MENU_FOV_DEG) * 0.5)
	var tan_h: float = tan_v * (maxf(size.x, 1.0) / maxf(size.y, 1.0))

	# Height above the feet, measured on the pose she is actually holding.
	var head_h: float = MENU_FALLBACK_CROUCH_HEAD
	var hips_h: float = MENU_FALLBACK_CROUCH_HIPS
	for node in performer.find_children("*", "Skeleton3D", true, false):
		var skeleton := node as Skeleton3D
		var head: int = skeleton.find_bone("Head")
		var hips: int = skeleton.find_bone("Hips")
		if head >= 0 and hips >= 0:
			var base_y: float = performer.global_position.y
			head_h = (skeleton.global_transform * skeleton.get_bone_global_pose(head)).origin.y - base_y
			hips_h = (skeleton.global_transform * skeleton.get_bone_global_pose(hips)).origin.y - base_y
		break

	var upper: float = maxf(head_h + MENU_HEAD_TOP_PAD - hips_h, 0.2)
	var distance: float = upper / (close_body_frac * 2.0 * tan_v)
	var target: Vector3 = performer.global_position + Vector3(0.0, head_h, 0.0)
	# The azimuth the menu uses is measured against a body it has yawed to
	# FRONT_YAW_DEG, so what carries over is the DIFFERENCE, applied to
	# whichever way this performer happens to be facing.
	var azimuth: float = performer.global_rotation.y \
		+ deg_to_rad(MENU_CLOSE_AZIMUTH_DEG - MENU_FRONT_YAW_DEG)
	var back := Vector3(cos(azimuth), 0.0, sin(azimuth))
	var right: Vector3 = (-back).cross(Vector3.UP).normalized()
	var ndc := Vector2((head_x_frac - 0.5) * 2.0, (0.5 - head_y_frac) * 2.0)
	var eye: Vector3 = target + back * distance \
		- right * (ndc.x * distance * tan_h) - Vector3.UP * (ndc.y * distance * tan_v)

	_shot_local = player.global_transform.affine_inverse() * eye
	_shot_yaw = atan2(back.x, back.z) - player.global_rotation.y
	_solved = true

func _capture_palette() -> void:
	if player != null and player.config != null:
		_ambient_strength = player.config.camera.ambient_cold_strength
	if world != null and world.environment != null and world.environment.sky != null:
		var sky := world.environment.sky.duplicate() as Sky
		var material := sky.sky_material
		if material is ProceduralSkyMaterial:
			sky.sky_material = (material as ProceduralSkyMaterial).duplicate()
			_sky = sky.sky_material as ProceduralSkyMaterial
			world.environment = world.environment.duplicate()
			world.environment.sky = sky
			_sky_authored = {
				top = _sky.sky_top_color,
				horizon = _sky.sky_horizon_color,
				ground_bottom = _sky.ground_bottom_color,
				ground_horizon = _sky.ground_horizon_color,
			}
	if plain_mesh != null and plain_mesh.material_override is ShaderMaterial:
		_floor_material = (plain_mesh.material_override as ShaderMaterial).duplicate() as ShaderMaterial
		plain_mesh.material_override = _floor_material
		_floor_authored = {
			base = _floor_material.get_shader_parameter("base_color"),
			dots = float(_floor_material.get_shader_parameter("dot_opacity")),
			metallic = float(_floor_material.get_shader_parameter("metallic_amount")),
			roughness = float(_floor_material.get_shader_parameter("roughness_amount")),
		}

func _paint(k: float) -> void:
	if _sky != null:
		_sky.sky_top_color = opening_colour.lerp(_sky_authored.top, k)
		_sky.sky_horizon_color = opening_colour.lerp(_sky_authored.horizon, k)
		_sky.ground_bottom_color = opening_colour.lerp(_sky_authored.ground_bottom, k)
		_sky.ground_horizon_color = opening_colour.lerp(_sky_authored.ground_horizon, k)
	if player != null and player.config != null:
		# THE AMBIENT IS WHY FLATTENING THE FLOOR MADE IT BLUER. Dropping
		# metallic turns a mirror into a diffuse sheet, and a diffuse sheet
		# drinks this level's cold ambient neat; the menu's ground is an unlit
		# rectangle and takes no light at all.
		#
		# THE DIAL, NOT THE COLOUR. Arena._process() rewrites
		# ambient_light_color from this strength EVERY frame so the F1 slider
		# stays live, and _process runs after _physics_process -- writing the
		# colour here is overwritten before it is ever drawn. DO NOT go back to
		# setting the colour.
		player.config.camera.ambient_cold_strength = lerpf(0.0, _ambient_strength, k)
	if _floor_material != null:
		_floor_material.set_shader_parameter("base_color",
			opening_colour.lerp(_floor_authored.base, k))
		# The menu's ground has no dot field on it at all.
		_floor_material.set_shader_parameter("dot_opacity",
			lerpf(0.0, _floor_authored.dots, k))
		# FLAT AND ROUGH IS WHAT MAKES IT THE MENU'S FLOOR. The colour alone
		# leaves a mirror standing where the menu has a plain sheet, and a
		# mirror is the thing the eye reads as "a different place".
		_floor_material.set_shader_parameter("metallic_amount",
			lerpf(0.0, _floor_authored.metallic, k))
		_floor_material.set_shader_parameter("roughness_amount",
			lerpf(1.0, _floor_authored.roughness, k))

func _pose(k: float) -> void:
	var rig: CameraRig = player.camera_rig
	var shot := _shot_local if _solved else Vector3(shot_right, shot_height, -shot_forward)
	# What set_cinematic_pose takes is an offset from the rig's nominal eye
	# position, so every absolute point above is converted here rather than
	# being authored in the rig's own terms.
	var base := Vector3(0.0, player.config.camera.eye_height, -rig.eye_forward)
	rig.set_cinematic_pose(shot.lerp(_rest, k) - base, 0.0,
		deg_to_rad(shot_pitch_degrees) * (1.0 - k))
	var yaw: float = _shot_yaw if _solved else deg_to_rad(shot_yaw_degrees)
	rig.set_cinematic_yaw(yaw * (1.0 - k))
	if rig.camera != null:
		# The camera CHILD carries the third-person seat, and the rig's own yaw
		# swings it round while the shot is coming out of profile. Zero at the
		# held end so the lens sits where this node put it, and full at the
		# other so nothing moves when the rig takes over again.
		rig.camera.position = _seat * k
		rig.camera.rotation = _seat_rot * k
		rig.camera.fov = lerpf(MENU_FOV_DEG if _solved else shot_fov_degrees, _base_fov, k)

func _hand_over() -> void:
	if _state == _State.DONE:
		return
	_state = _State.DONE
	_paint(1.0)
	_dismiss_performer()
	if _plate_layer != null:
		_plate_layer.queue_free()
		_plate_layer = null
		_plate = null
	if player != null:
		if player.camera_rig != null:
			player.camera_rig.end_cinematic()
		player.unlock_input()
	_take_the_pointer()
	set_physics_process(false)
	handed_over.emit()

# ---------------------------------------------------------------------------
# The stand-in
# ---------------------------------------------------------------------------

## Stands the performer exactly where the Player's own body is drawn, and takes
## that body off screen for as long as she is there.
##
## THE ORIGIN CONVENTION IS FEET, HERS AND THE MOUNT'S. Player mounts its body
## at compute_mount_transform(), which drops the capsule's centre by half its
## height before adding the profile's own offset; SilhouetteBody applies the
## same offset from its own origin. So dropping this node by half a capsule
## puts the two models in the same place to the millimetre. DO NOT add the
## profile's mount_offset here as well -- the stand-in has already applied it.
func _raise_performer() -> void:
	performer = SilhouetteBody.build()
	if performer == null:
		return
	var host: Node = player.get_parent()
	if host == null:
		host = self
	host.add_child(performer)
	var stance: Transform3D = player.global_transform
	stance.origin.y -= player.current_capsule_height() * 0.5
	performer.global_transform = stance
	performer.hold_crouch()
	var body_root: Node3D = player.get_node_or_null("BodyRoot") as Node3D
	if body_root != null:
		body_root.visible = false

## The swap. Both figures are the same red silhouette standing in the same
## spot, so this is a cut nobody sees -- which is the whole trick.
func _dismiss_performer() -> void:
	if player != null:
		var body_root: Node3D = player.get_node_or_null("BodyRoot") as Node3D
		if body_root != null:
			body_root.visible = true
	if performer != null:
		performer.queue_free()
		performer = null
