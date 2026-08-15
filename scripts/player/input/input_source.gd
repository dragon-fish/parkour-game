class_name InputSource
extends RefCounted

# The seam that lets tests drive the player without a real keyboard.
# Implementations must return a snapshot that is safe to hold for one tick.
func poll() -> MoveInput:
	push_error("InputSource.poll() is abstract and must be overridden")
	return MoveInput.new()
