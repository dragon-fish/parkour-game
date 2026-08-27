class_name Friction
extends RefCounted

# [ME:CONFIRMED 03 §3.3] the original's friction model: terrain grade
# modulates friction directly, and every move declares its own multiplier on
# top.
#
# DO NOT collapse this back into a pair of absolute decelerations, one for
# walking and one for sliding: that pair cannot express "downhill is a free
# acceleration lane and uphill is a tax" at all.
#
# `grade` is +1 pointing straight down the fall line, -1 straight up it, 0 on
# the flat -- i.e. the downhill component of the movement direction, which is
# exactly what SlideMove._slope_direction() already computes.
#
# All static: nothing here has state.

static func walk_friction(pawn: PawnConfig, move_modifier: float, grade: float) -> float:
	var scale: float = _grade_scale(grade, pawn.upward_walk_friction_scale, \
		pawn.downward_walk_friction_scale)
	# [ME:CONFIRMED 03 §3.3] the clamp is named MinWalkFrictionModify /
	# MaxWalkFrictionModify. [ME:INFERRED] the "Walk" in those names is what
	# scopes it to walking. DO NOT apply the clamp in slide_friction() too:
	# sliding's own uphill scale (5.0) sits above the 2.0 ceiling, so the
	# steepest slide case would be silently capped at less than half the
	# friction the original gives it.
	scale = clampf(scale, pawn.min_walk_friction_modify, pawn.max_walk_friction_modify)
	return _compose(pawn, move_modifier, scale)

static func slide_friction(pawn: PawnConfig, move_modifier: float, grade: float) -> float:
	var scale: float = _grade_scale(grade, pawn.upward_slide_friction_scale, \
		pawn.downward_slide_friction_scale)
	return _compose(pawn, move_modifier, scale)

## Interpolates between the uphill and downhill scales by grade, holding 1.0
## on the flat so level ground reduces to plain base friction. DO NOT make
## this a step: [ME:CONFIRMED 03 §3.3] the original's walking pair is
## 1.1 / 0.8, which straddles 1.0, so a step would make a barely-tilted floor
## behave like a ramp.
static func _grade_scale(grade: float, uphill: float, downhill: float) -> float:
	var g: float = clampf(grade, -1.0, 1.0)
	if g >= 0.0:
		return lerpf(1.0, downhill, g)
	return lerpf(1.0, uphill, -g)

static func _compose(pawn: PawnConfig, move_modifier: float, scale: float) -> float:
	# [ME:CONFIRMED 03 §3.3] TdPawn declares BrakingFrictionStrength 1.0 and
	# TdPlayerPawn overrides it to 0.5 -- the player is deliberately harder to
	# stop than the AI, which is what makes them "slide" a little into every
	# direction change.
	return maxf(pawn.base_friction * scale * move_modifier * pawn.braking_friction_strength, 0.0)
