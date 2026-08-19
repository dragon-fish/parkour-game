shader_type canvas_item;

// One material carries all three effects so a state only ever writes numbers.
// Order matters: blur samples the scene, desaturation acts on what was
// sampled, tint sits on top of the result.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec4 tint_color : source_color = vec4(1.0, 0.0, 0.0, 1.0);
uniform float tint_amount : hint_range(0.0, 1.0) = 0.0;
uniform float desaturation : hint_range(0.0, 1.0) = 0.0;
uniform float blur : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec3 col;
	if (blur > 0.001) {
		// Mip-based blur: cheap, and the radius maps linearly onto the knob.
		col = textureLod(screen_tex, SCREEN_UV, blur * 4.0).rgb;
	} else {
		col = texture(screen_tex, SCREEN_UV).rgb;
	}
	// Rec. 709 luma -- a plain average reads as muddy on skin and sky.
	float luma = dot(col, vec3(0.2126, 0.7152, 0.0722));
	col = mix(col, vec3(luma), desaturation);
	col = mix(col, tint_color.rgb, tint_amount);
	COLOR = vec4(col, 1.0);
}
