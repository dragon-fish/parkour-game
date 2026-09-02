class_name CubeSwarm
extends MultiMeshInstance3D

# A solid box that comes apart into a swarm of small glowing cubes, and goes
# back together again.
#
# EXACT, NOT AN APPROXIMATION. Every lesson block in the tutorial IS a box, so
# a regular grid of cubes filling its AABB is the box: packed tight and wearing
# one material, it reads as the original solid, and dispersing is nothing more
# than moving each cube.
#
# ONE NUMBER DRIVES IT. progress 0 is packed, 1 is gone, and growth is the same
# animation run backwards -- deliberately the same code path, not a second one.
#
# NOT FOR THE FLOOR. The tutorial's plain is hundreds of metres across and
# would voxelise into millions of instances. It leaves by fading into the void
# and dropping its dot field instead; see LevelZero. DO NOT make the two share
# an implementation.

const SHADER := "res://shaders/cube_swarm.gdshader"

## The box this stands in for, metres. The grid fills exactly this.
@export var box_size: Vector3 = Vector3.ONE

## Edge length of one cube. 0.25 m puts a waist-high 6 x 1 x 0.6 m wall at
## 24 x 4 x 2 = 192 instances -- chunky on purpose, and nowhere near a count
## that costs anything.
@export var cube_size: float = 0.25

## How far a cube has travelled once it is gone, metres. Tuning value.
@export var travel: float = 3.0

@export var base_color: Color = Color(0.93, 0.95, 0.97)
@export var glow_color: Color = Color(0.85, 0.92, 1.0)

## Fixed so a rebuild lands the same cubes in the same places. A swarm that
## reshuffled on every load could not be judged by eye at all.
@export var random_seed: int = 20260903

## 0 = the packed box, 1 = fully dispersed. The only thing anything outside
## this class touches.
var progress: float = 0.0:
	set(value):
		progress = clampf(value, 0.0, 1.0)
		if _material != null:
			_material.set_shader_parameter("progress", progress)

var _material: ShaderMaterial
## Per cube, in instance order. Named fields because this will grow more of
## them (a spin, a per-cube tint); see .claude/skills/naming-config-fields.
##   origin     Vector3 -- where the cube sits packed, in this node's space
##   direction  Vector3 -- unit, the way this cube leaves
##   delay      float, 0..1 -- how far into the run it starts moving
##
## THE PACKED ORIGIN IS KEPT HERE, NOT READ BACK OUT OF THE MULTIMESH.
## MultiMesh instance transforms live in the RenderingServer, and under
## --headless that is the dummy driver: set_instance_transform stores nothing
## and get_instance_transform answers identity for every index. Reading the
## grid back through it makes every packed cube sit at the node origin, which
## is silently inside any box and turns the placement tests vacuous.
var _cubes: Array[Dictionary] = []

func _ready() -> void:
	build()

## Lays out the grid. Idempotent: calling it again rebuilds from whatever
## box_size/cube_size currently say.
func build() -> void:
	var counts := grid_counts()
	var cell := Vector3(box_size.x / float(counts.x),
		box_size.y / float(counts.y), box_size.z / float(counts.z))

	_material = ShaderMaterial.new()
	_material.shader = load(SHADER)
	_material.set_shader_parameter("base_color", base_color)
	_material.set_shader_parameter("glow_color", glow_color)
	_material.set_shader_parameter("travel", travel)
	_material.set_shader_parameter("progress", progress)

	var cube_mesh := BoxMesh.new()
	cube_mesh.size = cell
	cube_mesh.material = _material

	var mesh := MultiMesh.new()
	mesh.transform_format = MultiMesh.TRANSFORM_3D
	mesh.use_custom_data = true
	mesh.mesh = cube_mesh
	mesh.instance_count = counts.x * counts.y * counts.z

	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	_cubes.clear()
	var index := 0
	for ix in counts.x:
		for iy in counts.y:
			for iz in counts.z:
				var origin := Vector3(
					(float(ix) + 0.5) * cell.x - box_size.x * 0.5,
					(float(iy) + 0.5) * cell.y - box_size.y * 0.5,
					(float(iz) + 0.5) * cell.z - box_size.z * 0.5)
				# Biased upwards: a block that comes apart should read as
				# rising light, not as rubble.
				var direction := Vector3(rng.randf_range(-1.0, 1.0),
					rng.randf_range(-0.2, 1.0), rng.randf_range(-1.0, 1.0))
				if direction.length() < 0.001:
					direction = Vector3.UP
				direction = direction.normalized()
				var delay := rng.randf_range(0.0, 0.6)
				_cubes.append({origin = origin, direction = direction, delay = delay})
				mesh.set_instance_transform(index, Transform3D(Basis.IDENTITY, origin))
				mesh.set_instance_custom_data(index,
					Color(direction.x, direction.y, direction.z, delay))
				index += 1
	multimesh = mesh

## How many cubes along each axis. At least one per axis, so a box thinner
## than a cube still gets a slab rather than nothing at all.
func grid_counts() -> Vector3i:
	var edge: float = maxf(cube_size, 0.001)
	return Vector3i(
		maxi(1, int(round(box_size.x / edge))),
		maxi(1, int(round(box_size.y / edge))),
		maxi(1, int(round(box_size.z / edge))))

## Where cube `index` stands at `at` progress, in this node's own space.
##
## THIS IS THE SAME ARITHMETIC shaders/cube_swarm.gdshader runs on the GPU, and
## those two are the only copies of it. Change one and change the other.
func cube_origin(index: int, at: float) -> Vector3:
	var cube: Dictionary = _cubes[index]
	var delay: float = cube.delay
	var k: float = clampf((at - delay) / maxf(1.0 - delay, 0.0001), 0.0, 1.0)
	return (cube.origin as Vector3) + (cube.direction as Vector3) * travel * k
