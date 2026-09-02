class_name SpiralTower
extends RefCounted

# The tutorial tower's shape, as arithmetic. tools/build_level_0_tower.gd
# generates the .tscn from these functions; nothing places a platform by hand,
# so re-proportioning the whole tower is a change to five numbers.
#
# THE SHORT TOWER IS THE POINT. Every extra turn is cheap to add and its cost
# only shows up after the player has already formed his first impression of
# what this game is. Turns few rather than many.
#
# A PLATFORM'S ORIGIN IS ITS RUNNING SURFACE, not the centre of its slab, so
# platform 0 sits flush with the plain and stepping onto the tower is a step
# rather than a hop.

## The shipped proportions. Named fields; see naming-config-fields.
##   turns            how many times round
##   radius           metres from the axis to a platform's centre
##   rise_per_turn    metres gained each time round
##   platform_length  metres along the direction of travel
##   platform_width   metres across it
##   gap              metres of nothing between one platform and the next
##   thickness        metres of slab under the running surface
const DEFAULT_SHAPE := {
	turns = 3,
	radius = 9.0,
	rise_per_turn = 6.0,
	platform_length = 5.0,
	platform_width = 3.0,
	gap = 2.2,
	thickness = 0.4,
}

## Platforms on one turn, rounded so they close the circle exactly. THE GAP IS
## THEREFORE HONOURED ONLY TO WITHIN THAT ROUNDING -- which is what a spiral
## that has to meet itself costs. Never fewer than three, or the "circle" is a
## line.
static func per_turn(shape: Dictionary) -> int:
	var spacing: float = float(shape.platform_length) + float(shape.gap)
	return maxi(3, int(round(TAU * float(shape.radius) / maxf(spacing, 0.001))))

static func platform_count(shape: Dictionary) -> int:
	return int(shape.turns) * per_turn(shape)

## The centre of platform `index`'s running surface, in the tower's own space.
static func platform_origin(shape: Dictionary, index: int) -> Vector3:
	var count: float = float(per_turn(shape))
	var angle: float = TAU * float(index) / count
	var height: float = float(shape.rise_per_turn) * float(index) / count
	return Vector3(cos(angle) * float(shape.radius), height,
		sin(angle) * float(shape.radius))

## Which way platform `index` runs: tangential, so a body crossing it is
## already pointed at the next one.
static func platform_yaw(shape: Dictionary, index: int) -> float:
	return -TAU * float(index) / float(per_turn(shape))

## Metres from the top platform's running surface up to the orb's centre.
## Tuning value; the author will move it.
##
## THE CEILING IS A JUMP, NOT TASTE. A body leaving that platform rises
## base_jump_z^2 / (2 * gravity), and the orb's trigger volume reaches down its
## own radius below its centre. Anything above that sum is an orb the player
## can see, climb the whole tower for, and never touch -- which is the whole
## level with no ending.
const SUMMIT_CLEARANCE := 3.0

## Where the orb hangs: directly over the TOP PLATFORM.
##
## NEVER OVER THE AXIS. Nothing stands on the axis -- every platform is out on
## `radius`, and the middle of this tower is open air all the way down. An orb
## centred there is arithmetically tidy, passes any "is it above the top
## platform" check, and is a whole radius of nothing away from the only place a
## body can jump from.
static func summit_origin(shape: Dictionary) -> Vector3:
	return platform_origin(shape, platform_count(shape) - 1) \
		+ Vector3(0.0, SUMMIT_CLEARANCE, 0.0)
