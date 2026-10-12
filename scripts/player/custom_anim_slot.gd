class_name CustomAnimSlot
extends RefCounted

# The pawn's custom animation slots, as the move logic sees them: what plays
# on each, how far through, at what blend weight, when it ends, and the root
# motion it carries. [ME:CONFIRMED decompile TdMove.PlayMoveAnim, TdPawn.OnAnimEnd
# / OnCeaseRelevantRootMotion, TdAnimNodeSequence.OnCeaseRelevant]
#
# One slot per TdPawn.CustomNodeType (CNT_FullBody, CNT_UpperBody, CNT_Canned,
# ...): an animation started on one fades out only what plays on the same
# one. Every move's PlayMoveAnim comes here; the move takes its ends and
# cease-relevant events for the animation it last played, whichever slot.
#
# Timing is the original's first-person sequence (RootMotionTracks), never a
# clip of this project's: the model is optional, and what it shows is
# CharacterAnimator's business. A name the original's player sets do not
# carry plays nothing.
#
# [ME:INFERRED] UE3's slot, not decompiled here: a new animation fades in
# over its blend-in while the others on its slot fade out over the same time; a non-looping
# one starts its own blend-out that long before its end; a stopped one fades
# out but keeps playing, so it can still reach its end. The end fires when a
# playing animation reaches it with any weight left; "ceases relevant" fires
# when the weight of one played with root motion or root rotation reaches zero
# (180TurnInAir and Swing turn their root rotation off on it). Root motion is the track's
# change over the frame, weighted by the blend.

## TdPawn.CustomNodeType.
const CNT_CANNED := 0
const CNT_FULL_BODY := 2
const CNT_UPPER_BODY := 4
const CNT_WEAPON := 7

class Channel:
	var node: int = CNT_FULL_BODY
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

## Plays `anim` on slot `node`. Returns false when the original's sets have
## no such sequence.
func play(anim: StringName, rate: float, blend_in: float, blend_out: float, root_motion: bool,
		root_rotation: bool, pawn_yaw: float, node: int = CNT_FULL_BODY) -> bool:
	var length: float = length_of(anim)
	if length < 0.0:
		return false
	for c in channels:
		if c.node == node:
			_fade(c, blend_in)
	var ch := Channel.new()
	ch.node = node
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

## StopCustomAnim(Type, BlendOutTime): what plays on slot `node` fades out
## over `blend_out`.
func stop(blend_out: float, node: int = CNT_FULL_BODY) -> void:
	var c: Channel = current(node)
	if c != null:
		_fade(c, blend_out)

## The animation playing in front on slot `node`: the last one started there
## that is not fading.
func current(node: int = CNT_FULL_BODY) -> Channel:
	for i in range(channels.size() - 1, -1, -1):
		if not channels[i].fading and channels[i].node == node:
			return channels[i]
	return null

func current_name(node: int = CNT_FULL_BODY) -> StringName:
	var c: Channel = current(node)
	return c.name if c != null else &""

## Seconds into `anim`'s sequence at rate 1, or -1 when it is not playing.
func position_of(anim: StringName) -> float:
	var c: Channel = _find(anim)
	return c.sequence_time() if c != null else -1.0

## Whether `anim` is playing on any slot, fading or not.
func is_playing(anim: StringName) -> bool:
	return _find(anim) != null

## The current animation's SequenceLength, seconds, or 0.
func current_length() -> float:
	var c: Channel = current()
	return c.length * absf(c.rate) if c != null else 0.0

func _find(anim: StringName) -> Channel:
	for i in range(channels.size() - 1, -1, -1):
		if channels[i].name == anim:
			return channels[i]
	return null

## AnimNodeSequence.SetPosition of the current animation: `seconds` into its
## sequence, at rate 1.
func set_position(seconds: float) -> void:
	var c: Channel = current()
	if c != null:
		c.elapsed = seconds / maxf(absf(c.rate), 1e-6)

## GetAnimPlaybackLength of the current animation: its length at its rate.
func current_playback_length() -> float:
	var c: Channel = current()
	return c.length if c != null else 0.0

## GetNormalizedPosition of the current animation, or 0.
func current_normalized_position() -> float:
	var c: Channel = current()
	return clampf(c.elapsed / c.length, 0.0, 1.0) if c != null and c.length > 0.0 else 0.0

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
##
## The motion is put into the world through the mesh's frame NOW, `pawn_yaw`,
## as the original transforms it by LocalToWorld at the update [ME:CONFIRMED
## decompile 0x00d235c0]; with root rotation on, the clip's own turn so far is
## taken off first, the translation being the root's relative to it.
## [ME:INFERRED] that UE3 extracts the translation relative to the extracted
## rotation; a pawn that turns only by the clip's own rotation travels the
## same path either way.
func advance(dt: float, pawn_yaw: float = NAN) -> Dictionary:
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
				var frame_yaw: float = c.start_yaw
				if not is_nan(pawn_yaw):
					frame_yaw = pawn_yaw
					if c.root_rotation:
						frame_yaw += c.clip.turn((t0 + t1) * 0.5)
				var f: Vector3 = Vector3(-sin(frame_yaw), 0.0, -cos(frame_yaw))
				var r: Vector3 = UE.cross(Vector3.UP, f)
				var d: Vector2 = c.clip.displacement(t1) - c.clip.displacement(t0)
				delta += (f * d.x + r * d.y + Vector3.UP * (c.clip.rise(t1) - c.clip.rise(t0))) * w
			if c.root_rotation:
				yaw += (c.clip.turn(t1) - c.clip.turn(t0)) * UE.UNITS_PER_RADIAN * w
		if not c.ended and c.elapsed >= c.length and (w0 > 0.0 or c.auto_out):
			c.ended = true
			ended.append(c.name)
		if c.weight <= 0.0 and (c.ended or (c.fading and not c.auto_out)):
			if c.root_motion or c.root_rotation:
				ceased.append(c.name)
			channels.erase(c)
	return {"ended": ended, "ceased": ceased, "delta": delta, "yaw": yaw, "rooted": rooted}
