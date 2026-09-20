@tool
class_name SectionLoader
extends Node3D

## The sections of a chapter too large to open whole, loaded as one level.
##
## PackedScene, NOT paths. As resources the sections are dependencies of the
## chapter scene, so the main menu's threaded load brings them in behind the
## run-up. Paths would leave the loader to fetch them after the scene swap,
## and the player would land in a world that is not there yet.
##
## Runtime instances every section. The editor instances NONE of them unless
## editor_preview names one: opening a whole chapter is what crashed the
## editor, and seeing one section at a time is how the original's own editor
## worked (UE3's Levels window).
@export var sections: Array[PackedScene] = []

## Editor only: the section to show, by its root node's name. Empty shows
## nothing. The preview is never owned, so it is never saved into the chapter.
@export var editor_preview: String = "":
	set(value):
		editor_preview = value
		if Engine.is_editor_hint() and is_inside_tree():
			_show_preview()

var _preview: Node = null


func _ready() -> void:
	if Engine.is_editor_hint():
		_show_preview()
		return
	var started := Time.get_ticks_msec()
	for packed in sections:
		if packed != null:
			add_child(packed.instantiate())
	print("[load]   SectionLoader instanced %d sections: %d ms" % [sections.size(), Time.get_ticks_msec() - started])


func _show_preview() -> void:
	if _preview != null:
		_preview.queue_free()
		_preview = null
	if editor_preview.is_empty():
		return
	for packed in sections:
		if packed == null:
			continue
		var state := packed.get_state()
		if state.get_node_count() > 0 and String(state.get_node_name(0)) == editor_preview:
			_preview = packed.instantiate()
			add_child(_preview)
			return
	push_warning("SectionLoader: no section named %s" % editor_preview)
