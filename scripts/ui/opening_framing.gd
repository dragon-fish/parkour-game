class_name OpeningFraming
extends Resource

# Shared camera composition for the held opening shot. Both the menu's
# detached silhouette and the tutorial's mounted Player body provide world
# points from their live skeleton; everything from those points to the camera
# pose is solved here so the two doors cannot drift apart.

@export_range(20.0, 100.0, 0.5) var fov_degrees: float = 55.0
@export var head_screen_fraction := Vector2(0.50, 0.38)
@export_range(0.2, 1.2, 0.01) var body_screen_fraction: float = 0.72
@export_range(0.0, 0.5, 0.01) var head_top_padding: float = 0.16

static func find_skeleton(root: Node) -> Skeleton3D:
	if root == null:
		return null
	for child in root.find_children("*", "Skeleton3D", true, false):
		return child as Skeleton3D
	return null

static func bone_world_position(skeleton: Skeleton3D, bone_name: StringName,
		use_rest: bool = false) -> Variant:
	if skeleton == null:
		return null
	var index := skeleton.find_bone(bone_name)
	if index < 0:
		return null
	var pose := skeleton.get_bone_global_rest(index) if use_rest \
		else skeleton.get_bone_global_pose(index)
	return (skeleton.global_transform * pose).origin

func distance_for_span(span: float) -> float:
	var tan_v := tan(deg_to_rad(fov_degrees) * 0.5)
	return maxf(span, 0.2) / (maxf(body_screen_fraction, 0.01) * 2.0 * tan_v)

## Returns {eye: Vector3, yaw: float}. `screen_frac` uses ordinary screen
## coordinates: (0, 0) top-left and (1, 1) bottom-right.
func camera_pose(target: Vector3, distance: float, azimuth: float,
		viewport_size: Vector2, screen_frac: Vector2 = Vector2(-1.0, -1.0)) -> Dictionary:
	if screen_frac.x < 0.0:
		screen_frac = head_screen_fraction
	var tan_v := tan(deg_to_rad(fov_degrees) * 0.5)
	var tan_h := tan_v * (maxf(viewport_size.x, 1.0) / maxf(viewport_size.y, 1.0))
	var back := Vector3(cos(azimuth), 0.0, sin(azimuth))
	var right := (-back).cross(Vector3.UP).normalized()
	var ndc := Vector2((screen_frac.x - 0.5) * 2.0,
		(0.5 - screen_frac.y) * 2.0)
	return {
		eye = target + back * distance
			- right * (ndc.x * distance * tan_h)
			- Vector3.UP * (ndc.y * distance * tan_v),
		yaw = atan2(back.x, back.z),
	}
