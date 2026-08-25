shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;

// lilToon-style matcap compositing, enough to reproduce a stylized model's
// intended look without its engine: base albedo, then up to two matcap
// layers, each masked in UV space and blended in one of lilToon's modes.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(1.0);
uniform float alpha_scissor : hint_range(0.0, 1.0) = 0.0;

uniform sampler2D matcap_tex : source_color, hint_default_black;
uniform sampler2D matcap_mask : hint_default_white;
uniform float matcap_blend : hint_range(0.0, 2.0) = 0.0;
uniform int matcap_mode = 0; // 0 normal, 1 add, 2 screen, 3 multiply

uniform sampler2D matcap2_tex : source_color, hint_default_black;
uniform sampler2D matcap2_mask : hint_default_white;
uniform float matcap2_blend : hint_range(0.0, 2.0) = 0.0;
uniform int matcap2_mode = 0;

vec3 apply_matcap(vec3 base, vec3 mc, float w, int mode) {
	vec3 target;
	if (mode == 1) {
		target = base + mc;
	} else if (mode == 2) {
		target = 1.0 - (1.0 - base) * (1.0 - mc);
	} else if (mode == 3) {
		target = base * mc;
	} else {
		target = mc;
	}
	return mix(base, target, clamp(w, 0.0, 1.0));
}

void fragment() {
	vec4 alb = texture(albedo_tex, UV) * tint;
	if (alpha_scissor > 0.0 && alb.a < alpha_scissor) {
		discard;
	}
	vec2 muv = NORMAL.xy * vec2(0.5, -0.5) + 0.5;
	vec3 col = alb.rgb;
	col = apply_matcap(col, texture(matcap_tex, muv).rgb,
		texture(matcap_mask, UV).r * matcap_blend, matcap_mode);
	col = apply_matcap(col, texture(matcap2_tex, muv).rgb,
		texture(matcap2_mask, UV).r * matcap2_blend, matcap2_mode);
	ALBEDO = col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	ALPHA = alb.a;
}
