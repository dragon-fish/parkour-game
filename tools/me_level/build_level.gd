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
const SectionLoaderScript := preload("res://scripts/level/section_loader.gd")


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
	var bakes = Common.read_json(dir.path_join("materials.json"))
	if manifest == null or meshes == null or bakes == null:
		push_error("[me_level] run the extractor for %s first" % config["id"])
		return false
	# The manifest records the config it was extracted with; a stale extract
	# would silently build yesterday's level.
	if JSON.stringify(manifest["config"]["sections"]) != JSON.stringify(config.get("sections", [])) \
			or JSON.stringify(manifest["config"]["packages"]) != JSON.stringify(config.get("packages", [])):
		push_error("[me_level] manifest was extracted with a different config; re-run the extractor")
		return false
	# Taken LIVE from the config, overwriting the snapshot the extract was made
	# with. Which file a cue name plays says nothing about what was read out of
	# the original -- it is a build-time choice, and one that gets changed
	# repeatedly while someone is auditioning sounds. Making that re-run a
	# whole chapter's extraction would be a minute's wait for a one-line edit.
	# `look` is read live for the same reason, a few lines below.
	manifest["config"]["sounds"] = config.get("sounds", {})
	var paths := Common.output_paths(config)

	_look = config.get("look", {})
	_cloth = config.get("cloth", [])
	_library = MeLibrary.new()
	if _look.has(BAKER_TINT_DIAL):
		_library.baker_tint_strength = float(_look[BAKER_TINT_DIAL])
	if _look.has(NORMAL_SCALE_DIAL):
		_library.normal_scale = float(_look[NORMAL_SCALE_DIAL])
	if not _library.build(meshes, bakes):
		return false
	manifest["puppet_bodies"] = _puppet_bodies(manifest, dir.path_join("puppets"), (paths.shell as String).get_basename() + "_puppets")

	if config.get("split_sections", false):
		return _build_split(config, manifest, paths, rebuild_interactions)

	var geometry: Node3D = _geometry_builder().build(manifest, str(config["id"]).to_pascal_case() + "Geometry")
	if not _save(geometry, paths.geometry, ResourceSaver.FLAG_COMPRESS):
		return false
	print("[me_level] wrote geometry: ", paths.geometry)

	if ResourceLoader.exists(paths.shell) and not rebuild_interactions:
		print("[me_level] kept editable shell: ", paths.shell)
		return true
	var shell := ShellBuilder.new().build(manifest, paths.geometry)
	return _write_shell(shell, paths.shell, ShellBuilder.fall_out_height(manifest))


## A chapter too large to open whole: one geometry scene and one editable
## section scene per section, and a chapter scene (the shell) holding spawn,
## checkpoints, the chapter-wide layer and a SectionLoader over the sections.
## See docs/superpowers/specs/2026-09-19-me-chapter-sections-design.md.
var _library = null
var _look := {}
var _cloth: Array = []
## `look` key for MeshLibrary.baker_tint_strength.
const BAKER_TINT_DIAL := "baker_tint_strength"
## `look` key for MeshLibrary.normal_scale.
const NORMAL_SCALE_DIAL := "normal_scale"


func _geometry_builder():
	var builder := GeometryBuilder.new()
	builder.library = _library
	builder.look_dials = _look
	builder.cloth_meshes = _cloth
	return builder


## Each body the extractor wrote (skeletal_glb.py) as a scene of its own, and
## {glb name: scene path}. Read with GLTFDocument HERE rather than left to the
## importer: the .glb is in the extract directory, outside anything Godot
## imports, and a level is built headless, where nothing is imported at all.
func _puppet_bodies(manifest: Dictionary, from_dir: String, to_dir: String) -> Dictionary:
	var out := {}
	var wanted := {}
	for puppet: Dictionary in manifest.get("puppets", []):
		wanted[str(puppet["body"])] = true
	if wanted.is_empty():
		return out
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(to_dir))
	for body: String in wanted:
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		if document.append_from_file(from_dir.path_join(body), state) != OK:
			push_error("[me_level] puppet body %s does not load" % body)
			continue
		var scene := document.generate_scene(state)
		if scene == null:
			push_error("[me_level] puppet body %s makes no scene" % body)
			continue
		scene.name = "Body"
		# TURNED BACK. skeletal_glb.py stands a HUMANOID rig the way
		# SkeletonProfileHumanoid wants it -- facing -Z, left hand toward +X --
		# because retargeting a clip onto another body goes through that
		# profile. The level does not: its actors are placed in the world the
		# extractor's own axis map made, a quarter turn from Godot's
		# convention. A scene body is placed BY THE LEVEL, and a first-person
		# cutscene has the view riding one of its bones, so leaving it turned
		# swings every such scene ninety degrees.
		# +90, the inverse of skeletal_glb.py's UPRIGHT -- worked out against
		# that matrix rather than guessed at, because guessing it turns the
		# body another quarter instead of back.
		if _is_humanoid(scene):
			(scene as Node3D).rotation = Vector3(0.0, PI * 0.5, 0.0)
		for node: Node in scene.find_children("*", "", true, false):
			node.owner = scene
		var path := to_dir.path_join(body.get_basename() + ".scn")
		# _save() frees what it saves.
		if _save(scene, path, ResourceSaver.FLAG_COMPRESS):
			out[body] = path
	print("[me_level] puppet bodies: %d" % out.size())
	return out


## The same test skeletal_glb.py makes when it decides to stand a rig up:
## every human rig in the original carries these, a pigeon or a rat none.
const HUMANOID_BONES := ["Hips", "Spine", "Head", "LeftHand", "RightHand", "LeftFoot", "RightFoot"]


static func _is_humanoid(scene: Node) -> bool:
	for node in scene.find_children("*", "Skeleton3D", true, false):
		var skeleton := node as Skeleton3D
		for bone in HUMANOID_BONES:
			if skeleton.find_bone(bone) < 0:
				return false
		return true
	return false


func _build_split(config: Dictionary, manifest: Dictionary, paths: Dictionary, rebuild: bool) -> bool:
	var base: String = (paths.shell as String).get_basename()
	var sections: Array[PackedScene] = []
	var shell_origins := {}
	for entry: Dictionary in config["sections"]:
		var section: String = entry["name"]
		var started := Time.get_ticks_msec()
		var part := _section_of(manifest, section)
		part["all_checkpoints"] = manifest["checkpoints"]
		# The look is the chapter's: its geometry carries it, once.
		part.erase("environment")
		var geometry_path := "%s_%s_geometry.scn" % [base, section.to_lower()]
		var geometry: Node3D = _geometry_builder().build(part, section.to_pascal_case() + "Geometry")
		if not _save(geometry, geometry_path, ResourceSaver.FLAG_COMPRESS):
			return false
		var scene_path := "%s_%s.tscn" % [base, section.to_lower()]
		# Built whether or not it is written: what it says about which node
		# came from which package is wanted either way.
		var fresh: Node = ShellBuilder.new().build_section(part, geometry_path, section)
		shell_origins[String(fresh.name)] = ShellBuilder.origins(fresh)
		if rebuild or not ResourceLoader.exists(scene_path):
			if not _save(fresh, scene_path, 0):
				return false
		else:
			fresh.free()
		print("[me_level] section %s: %d placements, %d ms" % [section, part["placements"].size(), Time.get_ticks_msec() - started])
		sections.append(load(scene_path))

	var chapter := _section_of(manifest, "")
	var chapter_geometry: Node3D = _geometry_builder().build(chapter, str(config["id"]).to_pascal_case() + "ChapterGeometry")
	manifest["shell_origins"] = shell_origins
	var kismet_path := Common.project_path(Common.EXTRACT_DIR).path_join(config["id"]).path_join("kismet.json")
	var kismet: Dictionary = Common.read_json(kismet_path) if FileAccess.file_exists(kismet_path) else {}
	var streaming := ShellBuilder.new().build_streaming(manifest, kismet, base + "_kismet.res")
	if streaming != null:
		chapter_geometry.add_child(streaming)
		print("[me_level] kismet: %d nodes, %d event zones" % [
			kismet["nodes"].size(), streaming.get_node("Kismet").get_child_count()])
	if not _save(chapter_geometry, paths.geometry, ResourceSaver.FLAG_COMPRESS):
		return false
	if ResourceLoader.exists(paths.shell) and not rebuild:
		print("[me_level] kept editable shell: ", paths.shell)
		return true
	# A checkpoint belongs to the section whose floor it stands on, and is
	# built into that section's shell, where it can be dragged against the
	# geometry it sits on; the chapter shell keeps the ones standing over
	# nothing. The spawn is chosen from all of them, whichever shell holds it.
	chapter["spawns"] = manifest["spawns"]
	chapter["all_checkpoints"] = manifest["checkpoints"]
	var shell := ShellBuilder.new().build(chapter, paths.geometry)
	var loader: Node3D = SectionLoaderScript.new()
	loader.name = "Sections"
	loader.set("sections", sections)
	shell.add_child(loader)
	loader.owner = shell
	return _write_shell(shell, paths.shell, ShellBuilder.fall_out_height(manifest))


## The manifest restricted to one section; "" is the chapter-wide layer.
static func _section_of(manifest: Dictionary, section: String) -> Dictionary:
	var part := manifest.duplicate()
	for key in ["placements", "lights", "annotations", "bsp", "checkpoints", "puppets"]:
		if not manifest.has(key):
			continue
		part[key] = (manifest[key] as Array).filter(func(r: Dictionary) -> bool: return r.get("section", "") == section)
	# A section's swing volume can hang on a bar placed from another section's
	# package or the chapter's (Subway's Plat-Tunnel slice, Mall's MallExterior).
	part["all_placements"] = manifest["placements"]
	return part


func _write_shell(shell: Node, path: String, fall_out: float) -> bool:
	var staging := "user://me_level_shell_%d.tscn" % OS.get_process_id()
	if not _save(shell, staging, 0):
		return false
	var text := ShellBuilder.compose(FileAccess.get_file_as_string(staging), fall_out)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(staging))
	if text.is_empty():
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("[me_level] cannot write %s" % path)
		return false
	file.store_string(text)
	file.close()
	print("[me_level] wrote shell: ", path)
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
