shader_type canvas_item;

// Pulsing dot-grid floor for the main menu, composition referenced from
// Arknights: Endfield's title screen (✅ 作者). Meant for a ColorRect
// covering roughly the bottom half of the screen; UV.y = 0 is the rect's
// top (toward the horizon), UV.y = 1 is its bottom (closest to camera).
//
// PSEUDO-PERSPECTIVE: dividing by UV.y is not a real 3D ground projection,
// just a cheap "1/y" divide -- it makes the grid compress toward the top of
// the rect the way a real ground plane recedes toward a horizon, for one
// division per pixel and zero texture reads.
//
// PER-CELL RANDOM PULSE (✅ 作者, Endfield 参照): each grid cell gets a fixed
// hash-derived phase offset so dots pulse independently instead of in
// lockstep -- that randomness is what reads as "alive" rather than
// "blinking uniformly".

uniform vec2 scroll_offset = vec2(0.0);
uniform float spacing : hint_range(1.0, 64.0) = 14.0;
uniform float dot_size : hint_range(0.01, 0.5) = 0.12;
uniform float speed : hint_range(0.0, 8.0) = 1.2;
uniform float pulse : hint_range(0.0, 1.0) = 0.35;
uniform float base : hint_range(0.0, 1.0) = 0.35;
uniform vec4 tint : source_color = vec4(0.75, 0.82, 0.92, 1.0);

// Classic cheap 2D hash: no textures, deterministic per grid cell.
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void fragment() {
	float eps = 0.001;
	vec2 ground_uv = vec2(UV.x - 0.5, 1.0) / max(UV.y, eps);
	ground_uv += scroll_offset;
	vec2 grid = ground_uv * spacing;
	vec2 cell = floor(grid);
	vec2 local = fract(grid) - 0.5;
	float dist = length(local);
	float dot_mask = 1.0 - smoothstep(dot_size, dot_size + 0.04, dist);

	float phase = hash(cell) * TAU;
	float brightness = clamp(base + pulse * sin(TIME * speed + phase), 0.0, 1.0);

	COLOR = vec4(tint.rgb, tint.a * dot_mask * brightness);
}
