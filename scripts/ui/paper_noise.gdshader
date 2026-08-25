shader_type canvas_item;

// Main menu's "背景极淡纸感噪点" (spec, 现代化改良五件套): a near-invisible
// grain overlay on the near-white background -- just enough texture that the
// backdrop reads as paper rather than a flat fill. One hash, no textures, no
// animation (a still grain, not a shimmer).

uniform float grain_alpha : hint_range(0.0, 0.2) = 0.035;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void fragment() {
	float n = hash(floor(FRAGCOORD.xy));
	COLOR = vec4(vec3(0.0), grain_alpha * n);
}
