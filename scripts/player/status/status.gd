class_name Status

# The closed vocabulary of temporary modifications a level may put on the
# player. An enum rather than a class hierarchy: the set is small, fixed, and
# author-facing, and a value that does not exist cannot be authored by mistake.
#
# DO NOT add BLOCK_WALKING / BLOCK_FALLING / BLOCK_LANDING /
# BLOCK_FALL_UNCONTROLLED. Blocking any of those strands the state machine or
# leaves the body hanging in mid-air with nothing to run. Their absence from
# this enum IS the guard -- there is no validation to write, no warning to
# raise, and no error to report, because the mistake cannot be expressed.

## The three-valued answer StatusList.forced_view() gives, and the values
## StatusSpec.view may take. NONE is only ever RETURNED -- an author cannot
## write it, because "no FORCE_VIEW status" already means no override.
enum View { NONE, FIRST, THIRD }

## One effect does one thing. Payload fields are read per the table below;
## every effect not listed reads none of them.
##
##   effect                 reads
##   ---------------------  ------------------------------
##   SPEED_CAP              amount   = ceiling factor (0..1)
##   FORCE_VIEW             view     = View.FIRST / THIRD
##   BLOCK_INTEREST_LINE    subject  = InterestLine.tag
##   everything else        nothing
##
## DO NOT put a second meaning into any payload field. A new meaning is a new
## field -- see .claude/skills/naming-config-fields.
enum Effect {
	SPEED_CAP,
	FORCE_VIEW,
	BLOCK_JUMP,
	BLOCK_SLIDE,
	BLOCK_SKILL_ROLL,
	BLOCK_COIL,
	BLOCK_CROUCH,
	BLOCK_WALL_RUN,
	BLOCK_WALL_CLIMB,
	BLOCK_GRAB,
	BLOCK_SPEED_VAULT,
	BLOCK_LADDER,
	BLOCK_ZIPLINE,
	BLOCK_SWING,
	BLOCK_TURN_180,
	BLOCK_INTEREST_LINE,
	STAGGER,
}
