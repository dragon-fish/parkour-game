class_name CustomAnimSlot
extends RefCounted

# The pawn's full-body custom animation slot, as the move logic sees it: what
# plays, how far through, at what blend weight, when it ends, and the root
# motion it carries. [ME:CONFIRMED decompile TdMove.PlayMoveAnim, TdPawn.OnAnimEnd
# / OnCeaseRelevantRootMotion, TdAnimNodeSequence.OnCeaseRelevant]
#
# Timing is the original's first-person sequence (RootMotionTracks), never a
# clip of this project's: the model is optional, and what it shows is
# CharacterAnimator's business. A name the original's player sets do not
# carry plays nothing.
#
# [ME:INFERRED] UE3's slot, not decompiled here: a new animation fades in
# over its blend-in while the others fade out over the same time; a non-looping
# one starts its own blend-out that long before its end; a stopped one fades
# out but keeps playing, so it can still reach its end. The end fires when a
# playing animation reaches it with any weight left; "ceases relevant" fires
# when a root-motion animation's weight reaches zero. Root motion is the track's
# change over the frame, weighted by the blend.

class Channel:
	var name: StringName = &""
	var key: StringName = &""
	var length: float = 0.0
	var rate: float = 1.0
	var elapsed: float = 0.0
	var weight: float = 0.0
	var blend_in: float = 0.0
	var blend_out: float = -1.0
	var fading: bool = false
	## The fade is its own blend-out before the end, not a stop.
	var auto_out: bool = false
	var fade_rate: float = 0.0
	var ended: bool = false
	var root_motion: bool = false
	var root_rotation: bool = false
	## The pawn's yaw (Godot radians) when it started: the frame its root
	## motion is in.
	var start_yaw: float = 0.0
	## The root track, for an animation played with root motion or rotation.
	var clip: RootMotionClip = null

	## Seconds into the sequence at rate 1.
	func sequence_time() -> float:
		return elapsed * absf(rate)

var channels: Array[Channel] = []

static func length_of(anim: StringName) -> float:
	var key: StringName = StringName(String(anim).to_lower())
	return float(RootMotionTracks.LENGTHS.get(key, -1.0))

## Plays `anim`. Returns false when the original's sets have no such sequence.
func play(anim: StringName, rate: float, blend_in: float, blend_out: float, root_motion: bool,
		root_rotation: bool, pawn_yaw: float) -> bool:
	var length: float = length_of(anim)
	if length < 0.0:
		return false
	for c in channels:
		_fade(c, blend_in)
	var ch := Channel.new()
	ch.name = anim
	ch.key = StringName(String(anim).to_lower())
	ch.rate = rate
	ch.length = length / maxf(absf(rate), 1e-6)
	ch.blend_in = blend_in
	ch.blend_out = blend_out
	ch.weight = 1.0 if blend_in <= 0.0 else 0.0
	ch.root_motion = root_motion
	ch.root_rotation = root_rotation
	ch.start_yaw = pawn_yaw
	if root_motion or root_rotation:
		ch.clip = RootMotionClip.from_track(ch.key)
	channels.append(ch)
	return true

static func _fade(c: Channel, seconds: float) -> void:
	c.fading = true
	c.auto_out = false
	c.fade_rate = INF if seconds <= 0.0 else 1.0 / seconds

## StopCustomAnim: the current animation fades out over `blend_out`.
func stop(blend_out: float) -> void:
	var c: Channel = current()
	if c != null:
		_fade(c, blend_out)

## The animation playing in front: the last one started that is not fading.
func current() -> Channel:
	for i in range(channels.size() - 1, -1, -1):
		if not channels[i].fading:
			return channels[i]
	return null

func current_name() -> StringName:
	var c: Channel = current()
	return c.name if c != null else &""

## The current animation's SequenceLength, seconds, or 0.
func current_length() -> float:
	var c: Channel = current()
	return c.length * absf(c.rate) if c != null else 0.0

func _find(anim: StringName) -> Channel:
	for i in range(channels.size() - 1, -1, -1):
		if channels[i].name == anim:
			return channels[i]
	return null

## AnimNodeSequence.GetNormalizedPosition of `anim`, or 0.
func normalized_position(anim: StringName) -> float:
	var c: Channel = _find(anim)
	return clampf(c.elapsed / c.length, 0.0, 1.0) if c != null and c.length > 0.0 else 0.0

## AnimNode.NodeTotalWeight of `anim`, or 0.
func weight_of(anim: StringName) -> float:
	var c: Channel = _find(anim)
	return c.weight if c != null else 0.0

func clear() -> void:
	channels.clear()

## A frame of the slot. Returns {"ended": [names], "ceased": [names],
## "delta": root motion in the world (m), "yaw": root rotation (rotator units,
## turning right), "rooted": whether any root-motion animation is playing},
## the root motion summed over the root-motion animations (RootMotionClip).
func advance(dt: float) -> Dictionary:
	var ended: Array[StringName] = []
	var ceased: Array[StringName] = []
	var delta := Vector3.ZERO
	var yaw: float = 0.0
	var rooted: bool = false
	for c in channels.duplicate():
		var t0: float = c.sequence_time()
		var w0: float = c.weight
		c.elapsed += dt
		if not c.fading and c.blend_out >= 0.0 and c.length - c.elapsed <= c.blend_out:
			_fade(c, c.blend_out)
			c.auto_out = true
		if c.fading:
			c.weight = maxf(0.0, c.weight - dt * c.fade_rate)
		elif c.blend_in > 0.0:
			c.weight = minf(1.0, c.weight + dt / c.blend_in)
		if c.clip != null:
			var t1: float = minf(c.sequence_time(), c.length * absf(c.rate))
			var w: float = (w0 + c.weight) * 0.5
			if c.root_motion:
				rooted = true
				var f: Vector3 = Vector3(-sin(c.start_yaw), 0.0, -cos(c.start_yaw))
				var r: Vector3 = UE.cross(Vector3.UP, f)
				var d: Vector2 = c.clip.displacement(t1) - c.clip.displacement(t0)
				delta += (f * d.x + r * d.y + Vector3.UP * (c.clip.rise(t1) - c.clip.rise(t0))) * w
			if c.root_rotation:
				yaw += (c.clip.turn(t1) - c.clip.turn(t0)) * UE.UNITS_PER_RADIAN * w
		if not c.ended and c.elapsed >= c.length and (w0 > 0.0 or c.auto_out):
			c.ended = true
			ended.append(c.name)
		if c.weight <= 0.0 and (c.ended or (c.fading and not c.auto_out)):
			if c.root_motion:
				ceased.append(c.name)
			channels.erase(c)
	return {"ended": ended, "ceased": ceased, "delta": delta, "yaw": yaw, "rooted": rooted}
