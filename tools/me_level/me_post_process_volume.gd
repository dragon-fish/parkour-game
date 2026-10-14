@tool
extends Node3D

# One of the original's PostProcessVolumes: inside its brush the level is
# graded by its own settings instead of the world's. [ME:CONFIRMED TM1
# 0x00c15ee0] the first enabled volume by priority whose brush holds the view
# wins, and its settings REPLACE the world's.
#
# The brush is its outward face planes in world space (environment.py), a
# point inside when it is behind every plane of one of its hulls.

## Higher wins.
@export var priority := 0.0
@export var enabled := true
## The planes of every hull, one after another; hull_sizes says how many each.
@export var planes: Array[Plane] = []
@export var hull_sizes := PackedInt32Array()
@export var tone: Resource = null

## Metres a point may stand outside a face and still count as in.
const SLACK := 0.0001


func contains(point: Vector3) -> bool:
	var at := 0
	for size in hull_sizes:
		var inside := true
		for k in size:
			if planes[at + k].distance_to(point) > SLACK:
				inside = false
				break
		if inside:
			return true
		at += size
	return false
