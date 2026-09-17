class_name LevelEntry
extends Resource

# One row of the main menu's level select.

## What the row reads.
@export var title: String = ""
## The level it loads. A file path, not a PackedScene: an exported scene is a
## hard dependency, so the menu would load every listed level as it opens.
## Dragged in the inspector it is stored as a uid://, which survives a rename.
@export_file("*.tscn") var scene: String = ""
