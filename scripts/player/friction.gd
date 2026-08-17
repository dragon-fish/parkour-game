class_name Friction
extends RefCounted

# The original's friction model (03 §3.3): terrain grade modulates friction
# directly, and every move declares its own multiplier on top. This replaces
# two unrelated absolute decelerations -- one for walking, one for sliding --
# which between them could not express "downhill is a free acceleration lane
# and uphill is a tax" at all.
#
# `grade` is +1 pointing straight down the fall line, -1 straight up it, 0 on
# the flat -- i.e. the downhill component of the movement direction, which is
# exactly what SlideMove._slope_direction() already computes.
#
# All static: nothing here has state.

static func walk_friction(pawn: PawnConfig, move_modifier: float, grade: float) -> float:
	var scale: float = _grade_scale(grade, pawn.upward_walk_friction_scale, \
		pawn.downward_walk_friction_scale)
	# The clamp is named MinWalkFrictionModify / MaxWalkFrictionModify and is
	# applied ONLY here: sliding's own uphill scale (5.0) sits above the 2.0
	# ceiling, so applying it there would silently cap the steepest slide case
	# at less than half the friction the original gives it.
	scale = clampf(scale, pawn.min_walk_friction_modify, pawn.max_walk_friction_modify)
	return _compose(pawn, move_modifier, scale)

static func slide_friction(pawn: PawnConfig, move_modifier: float, grade: float) -> float:
	var scale: float = _grade_scale(grade, pawn.upward_slide_friction_scale, \
		pawn.downward_slide_friction_scale)
	return _compose(pawn, move_modifier, scale)

## Interpolates between the uphill and downhill scales by grade, holding 1.0
## on the flat so level ground reduces to plain base friction. Linear rather
## than a step, because the original's own walking pair (1.1 / 0.8) straddles
## 1.0 and a step would make a barely-tilted floor behave like a ramp.
static func _grade_scale(grade: float, uphill: float, downhill: float) -> float:
	var g: float = clampf(grade, -1.0, 1.0)
	if g >= 0.0:
		return lerpf(1.0, downhill, g)
	return lerpf(1.0, uphill, -g)

static func _compose(pawn: PawnConfig, move_modifier: float, scale: float) -> float:
	# TdPlayerPawn overrides BrakingFrictionStrength from 1.0 down to 0.5 --
	# the player is deliberately harder to stop than the AI, which is what
	# makes them "slide" a little into every direction change.
	return maxf(pawn.base_friction * scale * move_modifier * pawn.braking_friction_strength, 0.0)
