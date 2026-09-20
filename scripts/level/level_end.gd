class_name LevelEnd
extends Area3D

## Where the chapter ends. [ME:CONFIRMED Kismet] the original reaches
## SeqAct_TdLevelCompleted from this touch through an outro of its own; here
## the touch goes straight to a white fade back to the main menu.

var _done := false


func _ready() -> void:
	# Only the body, never the level it stands in -- see Arena.PLAYER_LAYER.
	collision_mask = Arena.PLAYER_LAYER
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	# Duck-typed like Checkpoint: whatever can touch a checkpoint is a player.
	if _done or not body.has_method("touch_checkpoint"):
		return
	_done = true
	# Looked up, not named: the level builder loads this script without the
	# autoloads, and a bare PauseUi fails to compile there -- the shell then
	# saves the area with no script at all, and the end does nothing.
	var pause := get_tree().root.get_node_or_null("PauseUi")
	if pause != null:
		pause.go_to_main_menu()
