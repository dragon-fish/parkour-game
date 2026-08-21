@tool
extends SceneTree

# Builds scenes/calibration_course.tscn: a row of obstacles for judging what the
# move system does with each, by running at them.
#
# WHY A COURSE AND NOT MORE MEASUREMENT. The classification rules came out of
# the original with a stopwatch and a debug HUD (docs/feel-backlog.md 25-32),
# and the one number still missing -- the vertical speed that forks a vault from
# a grab -- is not even displayed there. It is cheaper to build the obstacles
# HERE, where the HUD is ours and reports which state actually fired, than to
# keep hunting the original's rooftops for a shape that happens to test the
# right thing.
#
# EVERYTHING IS CSGBox3D WITH use_collision. One node carries the mesh and the
# collider together, so the owner can drag a size in the editor without
# realigning a separate collision shape afterwards -- which is what they asked
# for, and the reason nothing here is a StaticBody3D with a CollisionShape3D
# child the way tools/arena_builder.gd builds its own geometry.
#
# Run:
#   .engine\Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#       --script res://tools/build_calibration_course.gd

const OUT_PATH := "res://scenes/calibration_course.tscn"
const STRIPES := "res://shaders/hazard_stripes.gdshader"

## Body landmarks, from the feet. Used only to place the labels' commentary --
## the obstacles themselves are plain numbers.
const WAIST := 0.9
const EYE := 1.66
## ✅ MEASURED four times in the original, 1.86-1.90: the highest an obstacle's
## top may be above the FEET and still be reachable. See feel-backlog.md 29, 32.
const REACH := 1.87

var _stripe_material: ShaderMaterial


func _init() -> void:
	var shader: Shader = load(STRIPES)
	_stripe_material = ShaderMaterial.new()
	_stripe_material.shader = shader

	var root := Node3D.new()
	root.name = "CalibrationCourse"

	_height_ladder(root)
	_width_row(root)
	_hollow_row(root)
	_take_off_steps(root)

	_save(root)
	quit()


## A CSG box with collision, striped, and labelled with its own size.
##
## `size.y` IS THE HEIGHT ABOVE THE GROUND, not the box's own extent: every box
## here sits on the floor, so the two are the same thing and saying it once
## avoids a page of `pos.y = size.y * 0.5` at every call site.
func _obstacle(parent: Node3D, obstacle_name: String, size: Vector3, pos: Vector3,
		note: String = "") -> CSGBox3D:
	var box := CSGBox3D.new()
	box.name = obstacle_name
	box.size = size
	box.position = Vector3(pos.x, size.y * 0.5, pos.z)
	box.use_collision = true
	box.material = _stripe_material
	parent.add_child(box)

	var label := Label3D.new()
	label.name = "Size"
	label.text = "%.2f h  %.2f w\n%s" % [size.y, size.z, note] if note != "" \
		else "%.2f h  %.2f w" % [size.y, size.z]
	# Floating just clear of the top, facing the approach. Billboarded would be
	# easier to read from anywhere, but a FIXED facing is what makes a label
	# usable while running at it: it stays put in the view instead of swinging.
	label.position = Vector3(0.0, size.y * 0.5 + 0.35, size.z * 0.5 + 0.05)
	label.font_size = 96
	label.pixel_size = 0.0015
	label.modulate = Color(1.0, 1.0, 1.0)
	label.outline_size = 24
	label.no_depth_test = true
	box.add_child(label)
	return box


## Graded heights, one narrow top each, so the only thing that varies is how far
## above the feet the edge sits. Straddles the measured reach threshold.
func _height_ladder(root: Node3D) -> void:
	var lane := Node3D.new()
	lane.name = "HeightLadder"
	lane.position = Vector3(-12.0, 0.0, 0.0)
	root.add_child(lane)

	var heights := [0.4, 0.8, 1.2, 1.6, 1.9, 2.2, 2.6]
	for i in heights.size():
		var h: float = heights[i]
		var note := ""
		if absf(h - WAIST) < 0.25:
			note = "~waist"
		elif absf(h - EYE) < 0.2:
			note = "~eye"
		elif absf(h - REACH) < 0.15:
			note = "~reach 1.87"
		_obstacle(lane, "H_%d" % roundi(h * 100.0), Vector3(6.0, h, 0.35),
			Vector3(0.0, 0.0, -float(i) * 9.0), note)


## One height, graded TOP WIDTHS. ✅ The owner settled this axis from play: a
## fence and the cabinet beside it are the same height and both vault, and the
## cabinet's wide top is simply where Faith ends up standing.
func _width_row(root: Node3D) -> void:
	var lane := Node3D.new()
	lane.name = "WidthRow"
	lane.position = Vector3(0.0, 0.0, 0.0)
	root.add_child(lane)

	var widths := [0.1, 0.3, 0.6, 1.0, 1.6, 2.4]
	for i in widths.size():
		var w: float = widths[i]
		_obstacle(lane, "W_%d" % roundi(w * 100.0), Vector3(6.0, 1.4, w),
			Vector3(0.0, 0.0, -float(i) * 9.0), "over or onto?")


## Obstacles with NOTHING at shin height -- the case that used to be invisible
## to the probe, because it demanded a face down there. A duct with open space
## beneath it, at three heights.
func _hollow_row(root: Node3D) -> void:
	var lane := Node3D.new()
	lane.name = "HollowRow"
	lane.position = Vector3(12.0, 0.0, 0.0)
	root.add_child(lane)

	var tops := [1.0, 1.4, 1.8]
	for i in tops.size():
		var top: float = tops[i]
		var thickness := 0.4
		var box := CSGBox3D.new()
		box.name = "Duct_%d" % roundi(top * 100.0)
		box.size = Vector3(6.0, thickness, 0.5)
		box.position = Vector3(0.0, top - thickness * 0.5, -float(i) * 9.0)
		box.use_collision = true
		box.material = _stripe_material
		lane.add_child(box)

		var label := Label3D.new()
		label.name = "Size"
		label.text = "duct top %.2f\nclear below" % top
		label.position = Vector3(0.0, thickness * 0.5 + 0.35, 0.3)
		label.font_size = 96
		label.pixel_size = 0.0015
		label.outline_size = 24
		label.no_depth_test = true
		box.add_child(label)


## Steps of graded height in front of ONE tall wall, so the same wall can be
## met from different take-off heights. ✅ That is the variable that forks a
## vault from a grab -- how far the climb has left to run when reach height
## arrives (feel-backlog.md 32) -- and it is the one thing the original's own
## rooftops made hard to vary.
func _take_off_steps(root: Node3D) -> void:
	var lane := Node3D.new()
	lane.name = "TakeOffSteps"
	lane.position = Vector3(24.0, 0.0, 0.0)
	root.add_child(lane)

	var wall := CSGBox3D.new()
	wall.name = "TallWall"
	wall.size = Vector3(14.0, 4.0, 0.6)
	wall.position = Vector3(0.0, 2.0, -14.0)
	wall.use_collision = true
	wall.material = _stripe_material
	lane.add_child(wall)

	var steps := [0.0, 0.4, 0.8, 1.2]
	for i in steps.size():
		var h: float = steps[i]
		if h <= 0.0:
			continue
		_obstacle(lane, "Step_%d" % roundi(h * 100.0), Vector3(2.4, h, 2.4),
			Vector3(-4.5 + float(i) * 3.0, 0.0, -11.0), "take off from here")


func _save(root: Node3D) -> void:
	# owner must be set on every descendant or PackedScene keeps only the root.
	_claim(root, root)
	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		push_error("calibration course: pack failed")
		return
	if ResourceSaver.save(packed, OUT_PATH) != OK:
		push_error("calibration course: save failed")
		return
	print("wrote ", OUT_PATH)


func _claim(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		_claim(child, owner_node)
