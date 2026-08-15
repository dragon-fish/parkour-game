class_name TestCase
extends RefCounted

# Base class for every test file. The runner injects `tree` before running
# any test method, so `step()` can advance the physics server.

var tree: SceneTree
var failures: Array[String] = []
var checks: int = 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func check_greater(a: float, b: float, message: String) -> void:
	checks += 1
	if not (a > b):
		failures.append("%s (expected %f > %f)" % [message, a, b])

func check_approx(a: float, b: float, tolerance: float, message: String) -> void:
	checks += 1
	if absf(a - b) > tolerance:
		failures.append("%s (expected %f ~= %f, tolerance %f)" % [message, a, b, tolerance])

# Advance the physics server by `frames` ticks. Every test method must await
# this at least once before touching global transforms — nodes added to the
# tree are not actually in-tree until a frame has elapsed.
func step(frames: int) -> void:
	for i in frames:
		await tree.physics_frame
