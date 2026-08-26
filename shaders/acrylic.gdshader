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

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// One plane's worth of dots, antialiased by the screen-space derivative --
// which also makes distant dots fade into the base instead of shimmering.
float plane_dots(vec2 position) {
	vec2 cell = fract(position / spacing) - 0.5;
	float distance_to_centre = length(cell) * spacing;
	float edge = max(fwidth(distance_to_centre), 0.0001);
	return 1.0 - smoothstep(dot_radius - edge, dot_radius + edge, distance_to_centre);
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
