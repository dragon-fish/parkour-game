shader_type spatial;

// Acrylic: a glossy near-white sheet with a world-space dot grid in it --
// the showcase floor's material, generalised so any mesh can wear it (✅ the
// owner: 地板反光效果特别有 Catalyst 的画面质感, 能不能用作物品材质).
//
// THE REFLECTION IS NOT IN HERE. This shader only makes a surface smooth
// and slightly metallic; what you see mirrored in it comes from the level's
// Environment having SSR (screen-space reflections) switched on. A level
// without it gets a clean glossy plastic and no mirror -- see
// templates/base_level.tscn and tools/arena_builder.gd, which both enable
// it now.
//
// Dots are projected TRIPLANAR, in world space: the grid stays the same
// size and stays put whatever a box's orientation or scale is, so it reads
// as a ruler the way hazard_stripes.gdshader's banding does, rather than as
// a texture that stretches with the mesh. Set dot_opacity to 0 for plain
// acrylic with no grid at all.

uniform vec4 base_color : source_color = vec4(0.94, 0.95, 0.97, 1.0);
uniform vec4 dot_color : source_color = vec4(0.62, 0.7, 0.8, 1.0);
uniform float dot_opacity : hint_range(0.0, 1.0) = 1.0;
// Metres between dot centres, and the dot's own radius in metres.
uniform float spacing = 0.35;
uniform float dot_radius = 0.05;
uniform float metallic_amount : hint_range(0.0, 1.0) = 0.4;
uniform float roughness_amount : hint_range(0.0, 1.0) = 0.12;
// How hard the triplanar blend picks one axis. Higher = crisper on edges.
uniform float projection_sharpness : hint_range(1.0, 16.0) = 6.0;

// A DOT'S OWN BREATHING, off by default. Every surface already wearing this
// material (the showcase floor, the whitebox ground, modifier_course) expects
// a still grid, so dot_base 1.0 with dot_pulse 0.0 reproduces exactly what
// they had. Raise dot_pulse and each cell fades in and out on its own phase --
// the same formula scripts/ui/dot_grid.gdshader uses for the main menu's
// floor, so a level meant to look like that screen can match it.
uniform float dot_base : hint_range(0.0, 1.0) = 1.0;
uniform float dot_pulse : hint_range(0.0, 1.0) = 0.0;
uniform float dot_pulse_speed : hint_range(0.0, 8.0) = 1.2;

// HOW MANY CELLS BEFORE THE PULSE PATTERN REPEATS. Zero (the default) never
// repeats, which is right for an ordinary level.
//
// A LEVEL THAT WRAPS MUST SET THIS. The pulse phase comes from hashing a
// cell's WORLD coordinate, and a hash is not periodic: after the body is
// shifted one period, hash(cell + period_in_cells) has nothing to do with
// hash(cell), so every dot in sight changes its phase on the same frame. The
// dots stay exactly where they were -- only their blinking is replaced --
// which reads worse than a jump, because the ground is provably still yet
// obviously different. Set this to the wrap period divided by `spacing` and
// the phase survives the crossing.
uniform float phase_wrap : hint_range(0.0, 4096.0) = 0.0;

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Cheap 2D hash, the same one the menu's grid uses: no textures, and a cell
// keeps its phase as the player walks over it.
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

// One plane's worth of dots, antialiased by the screen-space derivative --
// which also makes distant dots fade into the base instead of shimmering.
float plane_dots(vec2 position) {
	vec2 grid = position / spacing;
	vec2 cell = fract(grid) - 0.5;
	float distance_to_centre = length(cell) * spacing;
	float edge = max(fwidth(distance_to_centre), 0.0001);
	float mask = 1.0 - smoothstep(dot_radius - edge, dot_radius + edge, distance_to_centre);
	if (dot_pulse <= 0.0) {
		return mask * dot_base;
	}
	// Phase per CELL, so neighbours are out of step and the field reads as
	// scattered blinking rather than as one surface throbbing.
	vec2 cell_index = floor(grid);
	if (phase_wrap > 0.0) {
		cell_index = mod(cell_index, phase_wrap);
	}
	float phase = hash(cell_index) * TAU;
	float brightness = clamp(dot_base + dot_pulse * sin(TIME * dot_pulse_speed + phase), 0.0, 1.0);
	return mask * brightness;
}

void fragment() {
	vec3 weights = pow(abs(world_normal), vec3(projection_sharpness));
	weights /= max(weights.x + weights.y + weights.z, 0.0001);
	float dots = plane_dots(world_position.zy) * weights.x
		+ plane_dots(world_position.xz) * weights.y
		+ plane_dots(world_position.xy) * weights.z;
	ALBEDO = mix(base_color.rgb, dot_color.rgb, dots * dot_opacity);
	METALLIC = metallic_amount;
	ROUGHNESS = roughness_amount;
	SPECULAR = 0.5;
}
