shader_type canvas_item;

// One material carries every effect so a state only ever writes numbers.
// ORDER MATTERS, and it is the order the eye applies them: blur samples the
// scene, grade (brightness/contrast) works on what was sampled, desaturation
// drains what the grade produced, the vignette darkens or reddens the edge,
// and tint sits flat on top of the result.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec4 tint_color : source_color = vec4(1.0, 0.0, 0.0, 1.0);
uniform float tint_amount : hint_range(0.0, 1.0) = 0.0;
uniform float desaturation : hint_range(0.0, 1.0) = 0.0;
uniform float blur : hint_range(0.0, 1.0) = 0.0;

// 1.0 leaves the picture alone. Below one dims, above one lifts.
uniform float brightness : hint_range(0.0, 2.0) = 1.0;
// Pivoted on mid grey, so raising it does not also raise the average.
uniform float contrast : hint_range(0.0, 3.0) = 1.0;

// The edge of the screen, which is where a body reports on itself: darkening
// for losing consciousness, red for being close to death. One pair of knobs
// rather than two effects -- they never want to run at once, and a single
// falloff keeps them from fighting over the same pixels.
uniform vec4 vignette_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float vignette_amount : hint_range(0.0, 1.0) = 0.0;
// How far in from the corner the darkening reaches. Small values ring the
// very edge; large ones close over the middle of the screen.
uniform float vignette_width : hint_range(0.05, 1.0) = 0.45;

void fragment() {
	vec3 col;
	if (blur > 0.001) {
		// Mip-based blur: cheap, and the radius maps linearly onto the knob.
		col = textureLod(screen_tex, SCREEN_UV, blur * 4.0).rgb;
	} else {
		col = texture(screen_tex, SCREEN_UV).rgb;
	}
	col = (col - 0.5) * contrast + 0.5;
	col *= brightness;
	// Rec. 709 luma -- a plain average reads as muddy on skin and sky.
	float luma = dot(col, vec3(0.2126, 0.7152, 0.0722));
	col = mix(col, vec3(luma), desaturation);
	if (vignette_amount > 0.001) {
		// Distance from centre, normalised so the CORNERS are 1.0 whatever
		// the aspect ratio -- otherwise a wide window rings its sides and
		// leaves the top and bottom clear.
		float d = length(SCREEN_UV - vec2(0.5)) / length(vec2(0.5));
		float edge = smoothstep(1.0 - vignette_width, 1.0, d);
		col = mix(col, vignette_color.rgb, edge * vignette_amount);
	}
	// Alpha is the tint's own strength: a translucent colour never covers.
	col = mix(col, tint_color.rgb, tint_amount * tint_color.a);
	COLOR = vec4(clamp(col, vec3(0.0), vec3(1.0)), 1.0);
}
