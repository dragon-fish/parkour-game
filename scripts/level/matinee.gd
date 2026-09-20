class_name Matinee
extends Node3D

## One movement sequence from an extracted level. Played forward or in
## reverse by its triggers -- Area3D children (a touch, once per life) and
## UseZone children (a stand-still "use") -- or by another Matinee finishing.
##
## Keys are RELATIVE to each target's transform the FIRST time this sequence
## is activated in a life, and stay relative to that: a lever that plays the
## crane up and back down, or a train that restarts itself, must not drift by
## one run's worth every time round. [ME:INFERRED] UE3 captures an interp
## actor's initial transform once, the same way.
##
## Only the shape the extractor reads is reproduced (see its matinee.py):
## touches, uses, "Completed" chains, through switches, gates and delays.

## One entry per moving group: {targets: Array[NodePath], local: bool, and
## per channel (pos_, rot_, scl_) times, values, arrive, leave, modes}.
## Positions are metres; rotations the original's (roll, pitch, yaw) in
## degrees, turned into a basis after sampling; scales the original's absolute
## DrawScale3D, applied to each target's Mesh as a ratio to the first key.
## `local`: keys are in each target's own frame (UE3 IMF_RelativeToInitial),
## else in world axes. `absolute` (UE3 IMF_World): a key is where the target
## IS -- a world position, a world rotation -- and where it started has no say;
## a channel with no keys leaves that much of the target alone. modes: 0
## constant, 1 linear, 2 curve (Hermite on the stored tangents).
@export var tracks: Array[Dictionary] = []
@export var length: float = 0.0
## Seconds of the keys per second of play. The original sets it per action.
@export var play_rate: float = 1.0
## Sequences this one starts when it finishes: {path: NodePath, action:
## "play" | "reverse", delay: float}. May name this node itself -- a loop.
##
## A follower may also carry `delay_min` and `delay_max`, and then the gap is
## drawn afresh every time. A CONSTANT gap makes a metronome of a level: the
## original's trains come back after 5 to 10 seconds, never on the beat.
@export var followers: Array[Dictionary] = []
## Where a forward play STARTS, seconds into the keys. Negative -- the usual
## case -- means the beginning.
##
## [ME:CONFIRMED Stormdrain Kismet] UE3's SeqAct_Interp carries bForceStartPos
## and ForceStartPosition, and a sequence written for a respawn uses them: the
## `construction` point's girder is forced to 3.1 s of its 5, which is what
## puts the girder UNDER the point instead of 46 m below it. The designer's own
## comment on that action is "load".
##
## This is an authored constant, not a saved position. Nothing records how far
## a sequence had got when the player died; the level author decided once where
## a respawn should pick it up, and that number rides on the action.
@export var start_position: float = -1.0
## Plays itself as the level loads, and again after every respawn.
##
## Only for a sequence whose one way in is its own loop -- the extractor marks
## exactly that shape. Nothing else in the level ever starts such a sequence,
## so without this the Mall's tracks stay empty for the whole chapter.
@export var autostart: bool = false
## Held for as long as the movement lasts: {stream: AudioStream, fade_in: float,
## fade_out: float}. The original runs the train's rolling noise off the
## sequence's own soundon/soundoff, not off any trigger, so it begins and ends
## with the motion rather than with the player being somewhere.
@export var sound: Dictionary = {}

## The rolling sound's player, built on demand and parented to the first
## target, so the sound travels with what moves. Doppler is on: a body passing
## at 50 m/s that does not change pitch reads as a painted backdrop.
var _sound_player: AudioStreamPlayer3D = null
var _sound_fade: float = 0.0

## Keys time, 0 .. length.
## Played by the level's Kismet and by nothing of its own: see take_over().
var driven := false
## Goes round from its end to 0 by itself (UE3's bLooping), set by whoever
## drives it.
var looping := false

var _time: float = 0.0
## +1 forward, -1 reverse, 0 still.
var _direction: int = 0
## A queued start waiting out its delay.
var _pending_direction: int = 0
var _pending_wait: float = 0.0
var _captured := false
## Per track, per target: the transform the keys are relative to.
var _starts: Array = []
## Per track, per target: the Mesh child's basis at capture (scale tracks).
var _mesh_starts: Array = []
## Every target's transform, and its Mesh's, as the level loaded.
var _homes: Dictionary = {}
var _mesh_homes: Dictionary = {}


func _ready() -> void:
	add_to_group(Arena.RESET_ON_RESPAWN)
	for track: Dictionary in tracks:
		for path: NodePath in track["targets"]:
			var target := get_node_or_null(path) as Node3D
			if target == null:
				continue
			_homes[path] = target.global_transform
			var mesh := target.get_node_or_null("Mesh") as Node3D
			if mesh != null:
				_mesh_homes[path] = mesh.transform
	for child in get_children():
		if child is UseZone:
			(child as UseZone).used.connect(_on_trigger.bind(child))
		elif child is Area3D:
			(child as Area3D).body_entered.connect(_on_touch.bind(child))
	set_physics_process(false)
	# _process exists only to fade the rolling sound, and most sequences have
	# none; it turns itself on when there is something to fade.
	set_process(false)
	if autostart:
		play()


## Back to the level's opening state and playable again. Every Matinee that
## drives a target puts it back to the same load-time transform, so chained
## sequences sharing targets cannot disagree.
func reset_for_respawn() -> void:
	# A sequence the level's Kismet plays is put back BY the Kismet, at the
	# moment it forgets the old life -- see KismetRunner._forget_everything().
	# This call comes from the respawn's group sweep, in tree order, and for a
	# chapter that is AFTER the runner has already started the new life: it
	# stopped the trains the level had just set running again, and left the
	# runner's clock and this node's apart for good.
	if driven:
		return
	_reset()


func _reset() -> void:
	set_physics_process(false)
	_time = 0.0
	_direction = 0
	_pending_direction = 0
	_captured = false
	for path: NodePath in _homes:
		var target := get_node_or_null(path) as Node3D
		if target == null:
			continue
		place(target, _homes[path])
		var mesh := target.get_node_or_null("Mesh") as Node3D
		if mesh != null and _mesh_homes.has(path):
			mesh.transform = _mesh_homes[path]
	for child in get_children():
		if child is Area3D:
			child.set_meta("spent", false)
	_silence()
	# A loop stopped by the reset would never run again: dying once beside the
	# tracks would empty them for the rest of the chapter.
	if autostart and not driven:
		play()


## Puts a driven target somewhere, from ANY frame.
##
## AN AnimatableBody3D DISCARDS A TRANSFORM WRITTEN OUTSIDE THE PHYSICS STEP.
## A mover is one of those so that whoever stands on it is carried, and the
## same sync_to_physics that carries them threw away the respawn's write, which
## arrives on an idle frame: the cars carried on from wherever they had reached,
## every respawn captured a start further down the track, and within a few
## deaths the train had walked away from its own kill box -- the box being an
## Area3D, which reset perfectly. Two trains running side by side with their
## bodies somewhere else is the same fault seen from the other end.
##
## _apply() does not come through here. It runs from _physics_process, ahead of
## the server's own integration, where the write lands like any other.
##
## DO NOT GUARD THIS WITH Engine.is_in_physics_frame(). Being inside the
## physics step is not the same as being ahead of the body's sync, and a guard
## on that flag put the drift straight back: the reset arrives inside the step
## but after the body has already been read, so the write is still thrown away.
## Taking the body off sync is what makes it land, and a respawn is rare enough
## that the property write costs nothing worth saving.
static func place(target: Node3D, to: Transform3D) -> void:
	var animatable := target as AnimatableBody3D
	if animatable == null or not animatable.sync_to_physics:
		target.global_transform = to
		return
	animatable.sync_to_physics = false
	animatable.global_transform = to
	# AND the server's own copy, said outright. The write above reaches it only
	# when the call happens to come at the right point of the frame: a respawn
	# behind the death curtain does, one forced early with R does not, and then
	# the NODE went home while the BODY stayed where the sequence had left it
	# -- the subway's runaway train, gone from sight and still there to be
	# walked on, 600 m from its own picture.
	PhysicsServer3D.body_set_state(animatable.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, to)
	animatable.sync_to_physics = true


## The level's Kismet plays this sequence from now on: KismetRunner. Its own
## triggers, its followers and its autostart were all read OUT of that same
## graph as though it held no state, and would now fire a second time beside
## the real thing.
func take_over() -> void:
	driven = true
	for child in get_children():
		if child is Area3D:
			child.process_mode = Node.PROCESS_MODE_DISABLED
			(child as Area3D).set_deferred("monitoring", false)
	_reset()


## Where the sequence is, said by whoever drives it, and shown at once. The
## runner's clock and this node's run side by side and may be a frame apart:
## stopped on its own frame, the subway's ring froze a whole lap out of place
## -- the runner had wrapped to 0, this node was still at the end.
func seek(time: float) -> void:
	if not _captured:
		_capture()
	_time = clampf(time, 0.0, length)
	_apply()


## "play", "reverse", "loop" (round again from 0, NOT from start_position:
## that is where a play begins, not where a lap does), "stop" (hold where it
## is) or "reset" (back to the start).
func drive(action: String) -> void:
	match action:
		"play":
			_begin(1)
		"loop":
			_time = 0.0
			_direction = 1
			set_physics_process(true)
		"reverse":
			_begin(-1)
		"stop":
			_direction = 0
			_pending_direction = 0
			_hush()
		"reset":
			_reset()


func _on_touch(body: Node3D, area: Area3D) -> void:
	# Duck-typed like Checkpoint: whatever can touch a checkpoint is a player.
	# A touch fires once per life, the original's default MaxTriggerCount.
	if not body.has_method("touch_checkpoint") or area.get_meta("spent", false):
		return
	area.set_meta("spent", true)
	_on_trigger(area)


func _on_trigger(area: Node) -> void:
	start(str(area.get_meta("action", "play")), float(area.get_meta("delay", 0.0)))


## "play", "reverse" or "toggle" (reverse after a finished forward run,
## forward otherwise) -- the original's lever through a Switch.
func start(action: String, delay: float = 0.0) -> void:
	var direction := 1
	if action == "reverse" or (action == "toggle" and _direction == 0 and _time >= length):
		direction = -1
	if delay > 0.0:
		_pending_direction = direction
		_pending_wait = delay
		set_physics_process(true)
		return
	_begin(direction)


func play() -> void:
	start("play")


func is_running() -> bool:
	return _direction != 0 or _pending_direction != 0


func _begin(direction: int) -> void:
	# Keys are relative to where the targets START, and a target can be taken
	# somewhere between two plays: a lift's doors ride up with the car. At rest
	# at the start it IS at its start, wherever that now is, so that is read
	# again. Read once, the doors were hauled back down to the landing they
	# first opened on, and the car arrived to doors that never opened.
	# NOT when replaying from the end: there the target stands at its END.
	if not _captured or (direction > 0 and _time <= 0.0):
		_capture()
	# A forward start from the end replays from the top; a reverse start from
	# the top has nothing to undo.
	if direction > 0 and start_position >= 0.0:
		_time = clampf(start_position, 0.0, length)
	elif direction > 0 and _time >= length:
		_time = 0.0
	if direction < 0 and _time <= 0.0:
		return
	_direction = direction
	set_physics_process(true)
	if direction > 0:
		_sing()


func _capture() -> void:
	_captured = true
	_starts.clear()
	_mesh_starts.clear()
	for track: Dictionary in tracks:
		var starts: Array[Transform3D] = []
		var meshes: Array[Basis] = []
		for path: NodePath in track["targets"]:
			var target := get_node_or_null(path) as Node3D
			starts.append(target.global_transform if target != null else Transform3D())
			var mesh := target.get_node_or_null("Mesh") as Node3D if target != null else null
			meshes.append(mesh.transform.basis if mesh != null else Basis())
		_starts.append(starts)
		_mesh_starts.append(meshes)


func _physics_process(delta: float) -> void:
	if _pending_direction != 0:
		_pending_wait -= delta
		if _pending_wait > 0.0:
			return
		var queued := _pending_direction
		_pending_direction = 0
		_begin(queued)
	if _direction == 0:
		set_physics_process(false)
		return
	var unclamped := _time + delta * play_rate * _direction
	if looping and _direction > 0 and unclamped >= length and length > 0.0:
		# Round again WITH what ran over. A lap that ended by stopping at the
		# end and starting from 0 a frame later lost a metre or two each time
		# at the subway tunnel's sixty metres a second, and the ring opened a
		# seam at whichever piece had just wrapped.
		_time = fmod(unclamped, length)
		_apply()
		return
	_time = clampf(unclamped, 0.0, length)
	_apply()
	var finished := _time >= length if _direction > 0 else _time <= 0.0
	if not finished:
		return
	var went := _direction
	_direction = 0
	set_physics_process(false)
	if went > 0:
		_hush()
		if driven:
			return
		for follower: Dictionary in followers:
			var next := get_node_or_null(follower["path"]) as Matinee
			if next != null:
				next.start(str(follower["action"]), gap_of(follower))


## How long before a follower starts. A follower carrying delay_min/delay_max
## draws a fresh gap every time; one carrying neither uses its fixed delay.
static func gap_of(follower: Dictionary) -> float:
	var fixed := float(follower.get("delay", 0.0))
	var low := float(follower.get("delay_min", fixed))
	var high := float(follower.get("delay_max", fixed))
	if high <= low:
		return fixed
	return randf_range(low, high)


func _apply() -> void:
	for i in tracks.size():
		var track: Dictionary = tracks[i]
		var offset := sample(track["pos_times"], track["pos_values"], track["pos_arrive"],
			track["pos_leave"], track["pos_modes"], _time)
		var turn := basis_from_euler(sample(track["rot_times"], track["rot_values"],
			track["rot_arrive"], track["rot_leave"], track["rot_modes"], _time))
		var scaled: bool = not (track["scl_times"] as PackedFloat32Array).is_empty()
		var stretch := Vector3.ONE
		if scaled:
			var first: Vector3 = (track["scl_values"] as PackedVector3Array)[0]
			var now := sample(track["scl_times"], track["scl_values"], track["scl_arrive"],
				track["scl_leave"], track["scl_modes"], _time)
			stretch = Vector3(now.x / maxf(first.x, 0.0001), now.y / maxf(first.y, 0.0001),
				now.z / maxf(first.z, 0.0001))
		var targets: Array = track["targets"]
		for j in targets.size():
			var target := get_node_or_null(targets[j]) as Node3D
			if target == null:
				continue
			var start_transform: Transform3D = _starts[i][j]
			var pivots: Array = track.get("pivots", [])
			if j < pivots.size() and pivots[j] is Transform3D:
				# Hard-attached: the keys move the actor it rides, and it keeps
				# its place relative to that actor.
				var pivot: Transform3D = pivots[j]
				var carried := _placed(pivot, offset, turn, track) if track.get("absolute", false) \
						else _moved(pivot, offset, turn, track["local"])
				target.global_transform = carried * pivot.affine_inverse() * start_transform
			elif track.get("absolute", false):
				target.global_transform = _placed(start_transform, offset, turn, track)
			else:
				target.global_transform = _moved(start_transform, offset, turn, track["local"])
			if scaled:
				var mesh := target.get_node_or_null("Mesh") as Node3D
				if mesh != null:
					mesh.transform.basis = (_mesh_starts[i][j] as Basis) * Basis.from_scale(stretch)


## Where one sample of ABSOLUTE keys puts `from`: at the key, keeping its own
## scale, and keeping whatever a channel with no keys says nothing about.
static func _placed(from: Transform3D, position: Vector3, turn: Basis, track: Dictionary) -> Transform3D:
	var origin: Vector3 = from.origin if (track["pos_times"] as PackedFloat32Array).is_empty() else position
	var basis: Basis = from.basis
	if not (track["rot_times"] as PackedFloat32Array).is_empty():
		basis = turn * Basis.from_scale(from.basis.get_scale())
	return Transform3D(basis, origin)


## Where `from` is carried by one sample of the keys.
static func _moved(from: Transform3D, offset: Vector3, turn: Basis, local: bool) -> Transform3D:
	if local:
		return Transform3D(from.basis * turn, from.origin + from.basis.orthonormalized() * offset)
	return Transform3D(turn * from.basis, from.origin + offset)


## UE3 FInterpCurve::Eval: the leaving key's mode decides the segment.
static func sample(times: PackedFloat32Array, values: PackedVector3Array, arrive: PackedVector3Array,
		leave: PackedVector3Array, modes: PackedByteArray, t: float) -> Vector3:
	if times.is_empty():
		return Vector3.ZERO
	if t <= times[0]:
		return values[0]
	for k in range(1, times.size()):
		if t > times[k]:
			continue
		var span := maxf(times[k] - times[k - 1], 0.0001)
		var a := (t - times[k - 1]) / span
		match modes[k - 1]:
			0:
				return values[k - 1]
			1:
				return values[k - 1].lerp(values[k], a)
		var a2 := a * a
		var a3 := a2 * a
		return values[k - 1] * (2.0 * a3 - 3.0 * a2 + 1.0) + leave[k - 1] * span * (a3 - 2.0 * a2 + a) \
			+ arrive[k] * span * (a3 - a2) + values[k] * (-2.0 * a3 + 3.0 * a2)
	return values[values.size() - 1]


## Quietest audible gain: below this the player is stopped rather than left
## running inaudibly, because an AudioStreamPlayer3D costs whether or not
## anyone can hear it and a level holds dozens of these.
const SOUND_FLOOR := 0.002


## Starts the rolling sound, or fades it back in mid-fade-out.
func _sing() -> void:
	if not sound.has("stream") or sound["stream"] == null:
		return
	if _sound_player == null:
		_sound_player = AudioStreamPlayer3D.new()
		_sound_player.name = "Sound"
		_sound_player.stream = _looped(sound["stream"])
		# PHYSICS_STEP, not IDLE_STEP: the targets are moved from
		# _physics_process, so an idle-sampled velocity reads whatever the
		# frame happened to catch. The camera must have its own tracking on
		# too -- Godot needs BOTH ends, and one alone is the half-built state
		# where a passing train shifts pitch but running at a standing one
		# does not.
		_sound_player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
		_sound_player.volume_db = -80.0
		_carrier().add_child(_sound_player)
	if not _sound_player.playing:
		_sound_player.play()
	set_process(true)


## A copy of `stream` that repeats. The run outlasts the recording -- a train
## crosses for eleven seconds off a six-second loop -- so the engine has to own
## the repeat, which is also the only gapless way to do it.
##
## THE FLAG GOES ON THE RESOURCE, not in the .import file: an import file is
## regenerated, often untracked, and a first headless import can wipe it. The
## same call MenuMusic makes, for the same reason -- see
## .claude/skills/authoring-godot-scene-files. duplicate() so nothing else
## loading the same path inherits it.
static func _looped(stream: AudioStream) -> AudioStream:
	if stream is AudioStreamOggVorbis:
		var ogg := stream.duplicate() as AudioStreamOggVorbis
		ogg.loop = true
		return ogg
	if stream is AudioStreamWAV:
		var wav := stream.duplicate() as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = wav.data.size() / (4 if wav.stereo else 2)
		return wav
	return stream


## Begins the fade out. The sound outlives the movement by fade_out seconds,
## which is what makes a train recede instead of switching off.
func _hush() -> void:
	set_process(_sound_player != null)


## Stops it where it stands, for a respawn: nothing should be heard rolling
## away from a place the player is no longer in.
func _silence() -> void:
	_sound_fade = 0.0
	if _sound_player != null and _sound_player.playing:
		_sound_player.stop()


## Where the rolling sound sits: whatever the first track moves, so it travels
## with the thing making it. Falls back to this node when no target resolves.
func _carrier() -> Node3D:
	if tracks.is_empty():
		return self
	var targets: Array = tracks[0]["targets"]
	for path: NodePath in targets:
		var target := get_node_or_null(path) as Node3D
		if target != null:
			return target
	return self


func _process(delta: float) -> void:
	if _sound_player == null:
		set_process(false)
		return
	var rising := _direction > 0
	var seconds := float(sound.get("fade_in", 0.0)) if rising else float(sound.get("fade_out", 0.0))
	var step := 1.0 if seconds <= 0.0 else delta / seconds
	_sound_fade = clampf(_sound_fade + (step if rising else -step), 0.0, 1.0)
	if _sound_fade <= SOUND_FLOOR:
		_silence()
		set_process(false)
		return
	_sound_player.volume_db = linear_to_db(_sound_fade)
	if _sound_fade >= 1.0 and rising:
		set_process(false)


## (roll, pitch, yaw) degrees -> Godot basis. The same conjugation by the
## Y/Z axis swap as the extractor's common.godot_basis(); DO NOT re-derive it
## in Godot's own Euler conventions, that is how a mirrored level happened.
static func basis_from_euler(euler: Vector3) -> Basis:
	var r := deg_to_rad(euler.x)
	var p := deg_to_rad(euler.y)
	var y := deg_to_rad(euler.z)
	var sp := sin(p)
	var sy := sin(y)
	var sr := sin(r)
	var cp := cos(p)
	var cy := cos(y)
	var cr := cos(r)
	var row0 := Vector3(cp * cy, cp * sy, sp)
	var row1 := Vector3(sr * sp * cy - cr * sy, sr * sp * sy + cr * cy, -sr * cp)
	var row2 := Vector3(-(cr * sp * cy + sr * sy), cy * sr - cr * sp * sy, cr * cp)
	return Basis(Vector3(row0.x, row0.z, row0.y), Vector3(row2.x, row2.z, row2.y), Vector3(row1.x, row1.z, row1.y))
