class_name HalfTurn
extends RefCounted

# Half a turn clockwise, carried out by a script: the Q turn on the ground and
# off a wall (Turn180Move), and the one in mid-air (Turn180InAirMove).
#
# ALWAYS CLOCKWISE, AND ALWAYS EXACTLY HALF A TURN. [ME:CONFIRMED] Faith only
# ever turns right in the original. Godot's yaw grows counter-clockwise seen
# from above, so clockwise is the negative direction. DO NOT turn toward
# whichever side the entry lean favours instead -- that makes the direction a
# function of the entry angle, and leaves it a coin flip on float noise for the
# head-on approach the move is mostly used for.
#
# By absolute progress rather than a per-tick rate, so the turn lands on
# exactly the target and the camera is handed a series of small even deltas
# instead of one lump. See docs/camera-authority.md: the body is being moved BY
# A SCRIPT, so the eye trails it and eases in.
#
# `player` is untyped for the reason Move.player is.

var from: float = 0.0
var to: float = 0.0
## The scripted facing already handed to the camera, so each call reports only
## its own slice of the turn rather than the whole of it so far.
var _placed: float = 0.0

func begin(yaw: float) -> void:
	from = yaw
	to = yaw - PI
	_placed = yaw

## Places the turn `progress` (0 to 1) of the way round.
func advance(player, progress: float) -> void:
	progress = clampf(progress, 0.0, 1.0)
	var wanted: float = lerpf(from, to, progress)
	var moved: float = wanted - _placed
	_placed = wanted
	if player.camera_rig != null:
		# THE FAN TRAVELS WITH THE TURN, and the body is left to apply_look to
		# place. DO NOT also write player.rotation.y here -- both turning moves
		# carry an absolute-yaw look clamp, so apply_look pins the body to
		# reference + offset EVERY tick, using a reference captured when the
		# turn began. Two writers, once a tick, pulling opposite ways, is what
		# makes the camera visibly twitch left and right during a wall-climb
		# turn.
		#
		# Moving the reference instead makes them agree: apply_look places the
		# body at the scripted facing plus whatever the player's own mouse has
		# added, which is exactly right. assist = 1 because a scripted BODY turn
		# is one the view goes with -- what softens it is the eye's lag below,
		# not holding the fan back.
		player.camera_rig.shift_yaw_reference(wanted, 1.0)
		player.camera_rig.absorb_body_yaw(moved)
		if progress >= 1.0:
			# THE LAST SLICE HAS TO BE PLACED HERE. Every other tick's placement
			# is done by apply_look on the FOLLOWING tick, which is fine while
			# the move is still running -- but the tick the turn completes is
			# also the tick it hands off, and the move it hands to may have no
			# look clamp, so that following placement never happens. The turn
			# ended one tick's worth short of its target: ten degrees, at a 0.3 s
			# ground turn.
			#
			# Placed at the target PLUS whatever the player's own mouse has
			# added, which is what apply_look would have put there.
			var offset: float = float(player.camera_rig.look_debug()["relative_yaw"])
			player.rotation.y = wanted + offset
	else:
		# No rig to place the body: drive it directly. Tests with a stub player
		# take this path.
		player.rotation.y = wanted
	# THE MODEL TURNS WITH THE BODY. It otherwise chases the body only while a
	# key asks it to move, and not at all in third person with none held -- a
	# turn in mid-air with the keys let go left it facing the old way.
	player.pin_visual_yaw(wanted)
	# The turn is SCRIPTED, so it is not a mouse swing and must not be billed
	# as one. Without this, spinning while holding W flips the wish direction
	# through half a circle and the turn tax charges for the whole thing --
	# which would make Q the most expensive key on the board.
	player.forgive_turn()
