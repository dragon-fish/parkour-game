shader_type spatial;
render_mode cull_disabled;

// Orange-and-black hazard banding, like tape on a barrier.
//
// THE POINT IS OPTICAL FLOW, not decoration. The owner, on a blockout of plain
// flat-shaded boxes: "a solid-colour block gives no reference at all -- I
// genuinely cannot tell how I am moving." A flat surface under a flat light
// produces no image motion, so speed has nothing to read off except FOV and
// head bob, and both of those are effects rather than information.
//
// Banded on WORLD Y, so the stripes are level however a box is rotated and the
// same band always sits at the same height. That makes them a ruler as well as
// a texture: at the default 0.25 m a body is about seven bands tall, and an
// obstacle's height can be counted off without reading its label.

// Metres per band. One band is one stripe plus one gap.
uniform float band_height : hint_range(0.05, 1.0) = 0.25;
uniform vec3 stripe_colour : source_color = vec3(0.95, 0.45, 0.05);
uniform vec3 gap_colour : source_color = vec3(0.10, 0.10, 0.11);
// How much of each band is the bright stripe.
uniform float stripe_share : hint_range(0.1, 0.9) = 0.5;
// Skews the bands into diagonals on vertical faces, which is what makes real
// hazard tape read as directional. 0 is level banding.
uniform float skew : hint_range(0.0, 2.0) = 0.6;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// The skew term uses X+Z rather than either alone so a box reads the same
	// from all four sides. Without it the diagonals reverse as you walk round.
	float along = world_pos.y + (world_pos.x + world_pos.z) * skew;
	float phase = fract(along / band_height);
	// smoothstep rather than step: a hard edge aliases badly at distance and
	// at grazing angles, which is exactly where the player is reading speed.
	float edge = 0.02;
	float stripe = smoothstep(stripe_share - edge, stripe_share + edge, phase);
	ALBEDO = mix(stripe_colour, gap_colour, stripe);
	ROUGHNESS = 0.85;
	SPECULAR = 0.1;
}
