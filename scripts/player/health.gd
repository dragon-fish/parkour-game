class_name Health
extends RefCounted

# [13] What the original's screen desaturation is actually reading. There is
# no health bar in Mirror's Edge -- the picture IS the readout -- but there is
# a number behind it, and every value here was measured off the HUD.
#
# Deliberately RefCounted, not a Node: nothing here touches the scene tree,
# which is what lets it be tested without a physics world. Same stance as
# FallTracker and SpeedEnergy, which it sits beside on Player.

## Why the last damage was taken. Read to choose what a death looks like, so
## it survives on Player past the blow that ended things.
##
## DO NOT try to infer this from the state machine instead. A fatal landing
## declares its death in FallUncontrolledMove.landing_destination(), which
## then returns WALKING -- by the time anything presents the death, the
## machine is in an ordinary walk with nothing left to tell apart.
enum Cause { FALL, HARD_LANDING, HAZARD, VOLUME }

## Current health. NOT clamped at zero, deliberately: the original reads -900
## on the HUD after walking into a boundary volume, and a clamp would hide how
## heavy a blow was at exactly the moment that is worth knowing.
var hp: float = 0.0

## Why hp last went down.
var last_cause: int = Cause.FALL

## Seconds since the last damage. Regeneration waits for
## PawnConfig.health_regen_delay of these.
var _since_hurt: float = INF

var _pawn: PawnConfig

func _init(pawn: PawnConfig) -> void:
	_pawn = pawn
	hp = _pawn.max_health

func reset() -> void:
	hp = _pawn.max_health
	last_cause = Cause.FALL
	_since_hurt = INF

func is_dead() -> bool:
	return hp <= 0.0

## [13.1] Flat, and delayed. Every measured value here is a constant: the
## delay is what makes the low-health picture visible at all, because the
## climb back is only two seconds wide and the wait in front of it is five.
func tick(delta: float) -> void:
	if is_dead():
		return
	_since_hurt += delta
	if _since_hurt < _pawn.health_regen_delay:
		return
	# ONLY THE PART OF THIS TICK THAT FELL PAST THE DELAY HEALS. A step that
	# straddles the boundary would otherwise heal for its whole length, and the
	# boundary is straddled exactly once per wound -- so the error is small at
	# 60 Hz and lands every single time.
	var healing: float = minf(delta, _since_hurt - _pawn.health_regen_delay)
	hp = minf(hp + _pawn.health_regen_rate * healing, _pawn.max_health)

## How much of the wait is left before health starts coming back, 0 once it
## already is. Exists for the debug readout: without it the delay is
## indistinguishable from the system being broken.
func seconds_until_regen() -> float:
	return maxf(_pawn.health_regen_delay - _since_hurt, 0.0)

## Takes `amount` off and restarts the delay. Returns true when this blow is
## the one that killed.
##
## THE DEAD DO NOT DIE TWICE: a body already at or below zero absorbs nothing
## further, so a volume that keeps overlapping cannot re-declare a death that
## has already been declared.
func damage(amount: float, cause: int) -> bool:
	if is_dead():
		return false
	hp -= amount
	last_cause = cause
	_since_hurt = 0.0
	return is_dead()

## How far into the wounded range the body is, 0 (untouched) to 1 (at zero).
## The presentation layer's single input -- it reads a ratio rather than a
## number so a change to max_health does not silently move every threshold.
func fraction() -> float:
	return clampf(hp / maxf(_pawn.max_health, 0.001), 0.0, 1.0)
