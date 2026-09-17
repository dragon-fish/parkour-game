extends SceneTree

# Builds an extracted Mirror's Edge level: mesh library, geometry scene, and
# the editable shell when it does not exist yet.
#
#   <engine> --headless --path . --script res://tools/me_level/build_level.gd -- \
#       <config.json> [--rebuild-interactions]
#
# Run the extractor first (docs/mirrors-edge-deep-research/tools/level_extract/).
# --rebuild-interactions REPLACES the shell and everything edited in it.

const Common := preload("res://tools/me_level/me_level_common.gd")
const MeLibrary := preload("res://tools/me_level/mesh_library.gd")
const GeometryBuilder := preload("res://tools/me_level/geometry_builder.gd")
const ShellBuilder := preload("res://tools/me_level/shell_builder.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("usage: build_level.gd -- <config.json> [--rebuild-interactions]")
		quit(2)
		return
	quit(0 if _build(args[0], args.has("--rebuild-interactions")) else 1)


func _build(config_path: String, rebuild_interactions: bool) -> bool:
	var config: Dictionary = Common.read_json(config_path)
	if config == null:
		return false
	var dir := Common.project_path(Common.EXTRACT_DIR).path_join(config["id"])
	var manifest = Common.read_json(dir.path_join("manifest.json"))
	var meshes = Common.read_json(dir.path_join("meshes.json"))
	if manifest == null or meshes == null:
		push_error("[me_level] run the extractor for %s first" % config["id"])
		return false
	# The manifest records the config it was extracted with; a stale extract
	# would silently build yesterday's level.
	if JSON.stringify(manifest["config"]["sections"]) != JSON.stringify(config.get("sections", [])) \
			or JSON.stringify(manifest["config"]["packages"]) != JSON.stringify(config.get("packages", [])):
		push_error("[me_level] manifest was extracted with a different config; re-run the extractor")
		return false
	var paths := Common.output_paths(config)

	if not MeLibrary.new().build(meshes):
		return false

	var geometry: Node3D = GeometryBuilder.new().build(manifest, str(config["id"]).to_pascal_case() + "Geometry")
	if not _save(geometry, paths.geometry, ResourceSaver.FLAG_COMPRESS):
		return false
	print("[me_level] wrote geometry: ", paths.geometry)

	if ResourceLoader.exists(paths.shell) and not rebuild_interactions:
		print("[me_level] kept editable shell: ", paths.shell)
		return true
	var shell := ShellBuilder.new().build(manifest, paths.geometry)
	var staging := "user://me_level_shell_%d.tscn" % OS.get_process_id()
	if not _save(shell, staging, 0):
		return false
	var text := ShellBuilder.compose(FileAccess.get_file_as_string(staging))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(staging))
	if text.is_empty():
		return false
	var file := FileAccess.open(paths.shell, FileAccess.WRITE)
	if file == null:
		push_error("[me_level] cannot write %s" % paths.shell)
		return false
	file.store_string(text)
	file.close()
	print("[me_level] wrote shell: ", paths.shell)
	return true


func _save(root: Node, path: String, flags: int) -> bool:
	if root.owner == null:
		for child in root.get_children():
			_claim(child, root)
	var packed := PackedScene.new()
	var error := packed.pack(root)
	root.free()
	if error == OK:
		error = ResourceSaver.save(packed, path, flags)
	if error != OK:
		push_error("[me_level] saving %s: %s" % [path, error_string(error)])
	return error == OK


func _claim(node: Node, owner: Node) -> void:
	# Nodes that already belong to an instanced scene keep their owner.
	if node.owner == null:
		node.owner = owner
	if node.scene_file_path.is_empty():
		for child in node.get_children():
			_claim(child, owner)
