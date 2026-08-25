shader_type spatial;

// The main menu's dot-grid language, as a REAL floor: world-XZ dots on
// near-white, glossy enough that screen-space reflections read as the
// menu's mirror sheen. Lives under a free camera, which the menu's own
// screen-space pseudo-perspective (dot_grid.gdshader) cannot.

uniform vec4 base_color : source_color = vec4(0.94, 0.95, 0.97, 1.0);
uniform vec4 dot_color : source_color = vec4(0.62, 0.7, 0.8, 1.0);
uniform float spacing = 0.35;
uniform float dot_radius = 0.05;
uniform float metallic_amount : hint_range(0.0, 1.0) = 0.4;
uniform float roughness_amount : hint_range(0.0, 1.0) = 0.12;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 cell = fract(wpos.xz / spacing) - 0.5;
	float dist = length(cell) * spacing;
	float dot_mask = 1.0 - smoothstep(dot_radius * 0.7, dot_radius, dist);
	ALBEDO = mix(base_color.rgb, dot_color.rgb, dot_mask);
	METALLIC = metallic_amount;
	ROUGHNESS = roughness_amount;
	SPECULAR = 0.5;
}
