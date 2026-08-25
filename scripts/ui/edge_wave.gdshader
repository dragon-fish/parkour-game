shader_type canvas_item;

// Wavy left/right edges for ME-style red menu columns and the white
// selection bar (✅ 作者): "左右边缘带随机的水波浪动态". The same shader is
// reused on both -- the caller just halves amplitude_px for the bar, since
// "白条动得比红列更轻".
//
// AMPLITUDE UNITS: amplitude_px is a pixel quantity, but a canvas_item
// fragment only ever sees UV (0..1) -- there is no built-in read of the
// Control's actual size to convert px -> UV. Rather than silently treat
// amplitude_px as if it already were a UV fraction (which would make the
// wave's visible width depend on whatever pixel width the control happens
// to have), this shader takes a companion `width_px` uniform and does the
// division itself. MeTheme.wave_material() only sets amplitude_px (per the
// factory's signature); the consuming node is expected to also set
// width_px to its control's size.x (once at ready, and again on resize for
// a resizable control) via set_shader_parameter.
uniform float amplitude_px : hint_range(0.0, 64.0) = 6.0;
uniform float width_px : hint_range(1.0, 4096.0) = 400.0;
uniform float frequency : hint_range(0.0, 64.0) = 9.0;
uniform float speed : hint_range(0.0, 8.0) = 0.8;
uniform float seed_left = 0.0;
uniform float seed_right = 3.7;

// Three off-frequency sines layered together read as "random water" with
// zero texture sampling, and never visibly repeat during normal play.
float wave(float y, float seed) {
	float t = TIME * speed;
	float a = sin(y * frequency + t + seed);
	float b = 0.6 * sin(y * frequency * 2.3 - t * 1.7 + seed * 2.0);
	float c = 0.35 * sin(y * frequency * 4.7 + t * 0.6);
	return (a + b + c) / 1.95;
}

void fragment() {
	float amplitude_uv = amplitude_px / max(width_px, 1.0);
	float left_edge = amplitude_uv * wave(UV.y, seed_left);
	float right_edge = amplitude_uv * wave(UV.y, seed_right);
	// wave() can go negative, which just means "no erosion here" -- the
	// edge cannot bulge past the control's own bounds, only fray inward.
	if (UV.x < left_edge || UV.x > 1.0 - right_edge) {
		discard;
	}
}
