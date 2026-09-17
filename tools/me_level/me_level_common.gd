@tool
extends RefCounted

# Shared by the Mirror's Edge level builders: manifest paths, conversions,
# node naming and the material palette. Holds no original data.

const EXTRACT_DIR := "_local/me-reference/level-extract"
const LIBRARY_DIR := "res://scenes/local_debug_levels/mirrors_edge/mesh_library"
const LEVEL_DIR := "res://scenes/local_debug_levels/mirrors_edge"

# A small industrial palette keyed by use, never by a name hash. Rules match
# the MATERIAL name first, then the mesh name.
const MATERIAL_PALETTE := {
	"default": Color("9badb6"),
	"facade": Color("b5bec3"),
	"roof": Color("6c808b"),
	"metal": Color("59636a"),
	"wood": Color("9d805b"),
	"interaction": Color("a8584b"),
	"fabric": Color("b0aa95"),
	"glass": Color("526e7b"),
	"vegetation": Color("68705a"),
	"asphalt": Color("434a50"),
	"concrete": Color("a3a8a6"),
	"light": Color("e8eef0"),
}

const MATERIAL_RULES := [
	{family = "wood", tokens = ["plank", "planck", "wooden", "pallet", "chipboard", "cardboard", "runnerboard"]},
	{family = "interaction", tokens = ["swingpole", "laddersystem", "ziplinebase", "runnerramp"]},
	{family = "light", tokens = ["fluorescent", "lamp", "lightceiling", "lightwall", "lightbulb"]},
	{family = "glass", tokens = ["glass", "skylight", "solarpanel"]},
	{family = "fabric", tokens = ["tent", "plasticcover", "netting", "constructionpackages"]},
	{family = "vegetation", tokens = ["bush", "treea_"]},
	{family = "asphalt", tokens = ["road_", "tarmac", "parking", "garbagebag"]},
	{family = "metal", tokens = ["pipe", "airduct", "vent", "acunit", "acrooftop", "acsystem", "antenna", "parabol", "fence", "railing", "catwalk", "scaffolding", "metal", "cable", "wire", "crane", "cistern", "door", "hatch", "fusebox", "toolbox", "utilitycart", "shelf", "flagpole", "steel"]},
	{family = "concrete", tokens = ["concrete", "stormdrain", "pillar", "cement"]},
]


static func project_path(relative: String) -> String:
	return ProjectSettings.globalize_path("res://").path_join(relative)


static func read_json(path: String) -> Variant:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("[me_level] cannot read %s" % path)
		return null
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		push_error("[me_level] invalid JSON in %s" % path)
	return parsed


static func v3(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


static func basis_of(columns: Array) -> Basis:
	return Basis(v3(columns[0]), v3(columns[1]), v3(columns[2]))


static func transform_of(entry: Dictionary) -> Transform3D:
	return Transform3D(basis_of(entry["basis"]), v3(entry["position"]))


static func output_paths(config: Dictionary) -> Dictionary:
	var outputs: Dictionary = config.get("outputs", {})
	var id: String = config["id"]
	return {
		geometry = outputs.get("geometry") if outputs.get("geometry") else LEVEL_DIR.path_join(id + "_geometry.scn"),
		shell = outputs.get("shell") if outputs.get("shell") else LEVEL_DIR.path_join(id + ".tscn"),
	}


static func material_family(material_name: String, mesh_name: String) -> String:
	for candidate in [material_name.to_lower(), mesh_name.to_lower()]:
		if candidate.is_empty():
			continue
		for rule: Dictionary in MATERIAL_RULES:
			for token: String in rule["tokens"]:
				if candidate.contains(token):
					return rule["family"]
	var name := mesh_name.to_lower()
	if name.begins_with("s_r_") or name.begins_with("s_c_"):
		var parts := name.split("_")
		return "roof" if parts.size() > 4 and parts[4].begins_with("r") else "facade"
	if name.contains("rooftopplatform"):
		return "roof"
	if name.contains("building") or name.begins_with("s_bd_") or name.contains("_bac"):
		return "facade"
	return "default"


## Unique, valid node names under one parent. DO NOT let Godot name a node:
## a clash becomes "@Path3D@9002", which is not a legal name, spams warnings
## and changes between builds.
class NameAllocator:
	var _used := {}

	func take(raw: String) -> String:
		var base := raw.validate_node_name().replace("@", "_")
		if base.is_empty():
			base = "Node"
		var count: int = _used.get(base, 0) + 1
		_used[base] = count
		return base if count == 1 else "%s_%d" % [base, count]
