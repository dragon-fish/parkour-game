shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha,
		diffuse_lambert, specular_disabled;

// lilToon's matcap compositing, ported from the shader the model was authored
// against (lilxyzw/lilToon, lil_common_frag.hlsl / lil_functions.hlsl):
//
//   mc      = _MatCapColor * texture(_MatCapTex, matcapUV)
//   mc.rgb  = mix(mc.rgb, mc.rgb * albedo, _MatCapMainStrength)
//   col     = lilBlendColor(col, mc.rgb, _MatCapBlend * mc.a * mask.rgb, mode)
//
// THE MULTIPLY BY ALBEDO IS NOT OPTIONAL, and neither is the matcap colour's
// ALPHA in the blend weight. An Add or Screen matcap applied at full strength
// to a raw matcap texture lifts every dark texel towards white; on a white
// costume with black panels that erases the whole design, which is exactly
// what happened here. The mask is sampled .rgb per lilToon, not .r.
//
// EVERY texture here is sRGB, masks included: the model's Unity importer marks
// all of them sRGBTexture: 1, so lilToon samples a mask through the same gamma
// decode as a colour. Sampling a mask raw instead reads roughly double the
// weight at mid grey, which is a second way to blow the matcap out.
//
// The colour uniforms carry NO source_color hint on purpose: their values come
// straight out of Unity's .mat, which stores them LINEAR and sometimes above
// 1.0. Hinting them would gamma-decode an already-linear number a second time.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec4 tint = vec4(1.0);
uniform float alpha_scissor : hint_range(0.0, 1.0) = 0.0;

uniform sampler2D matcap_tex : source_color, hint_default_black;
uniform sampler2D matcap_mask : source_color, hint_default_white;
uniform vec4 matcap_color = vec4(1.0);
uniform float matcap_blend : hint_range(0.0, 2.0) = 0.0;
uniform float matcap_main_strength : hint_range(0.0, 1.0) = 0.0;
uniform int matcap_mode = 0; // 0 normal, 1 add, 2 screen, 3 multiply

uniform sampler2D matcap2_tex : source_color, hint_default_black;
uniform sampler2D matcap2_mask : source_color, hint_default_white;
uniform vec4 matcap2_color = vec4(1.0);
uniform float matcap2_blend : hint_range(0.0, 2.0) = 0.0;
uniform float matcap2_main_strength : hint_range(0.0, 1.0) = 0.0;
uniform int matcap2_mode = 0;

// lilToon's emission layer, same shape as the matcap one. Godot's EMISSION is
// deliberately not used: lilToon composites emission INTO the base colour with
// the same blend modes, so a glowing edge stays tied to the albedo underneath
// instead of becoming a light source the environment's glow picks up.
//
// The two masks are NOT interchangeable, and this model uses one each way:
// _EmissionMap multiplies the emission COLOUR (body), _EmissionBlendMask
// scales its WEIGHT (wing). Swapping them tints where it should gate.
uniform sampler2D emission_tex : source_color, hint_default_white;
uniform sampler2D emission_blend_mask : source_color, hint_default_white;
uniform vec4 emission_color = vec4(0.0);
uniform float emission_blend : hint_range(0.0, 2.0) = 0.0;
uniform float emission_main_strength : hint_range(0.0, 1.0) = 0.0;
uniform int emission_mode = 1;

// lilToon clamps the TOTAL light a pixel receives to [_LightMinLimit,
// _LightMaxLimit] (0.15 / 1.0 on this model) and desaturates it by
// _MonochromeLighting (0.2). That clamp is the whole reason an avatar keeps its
// colours in a world it was never lit for.
//
// Godot 4 exposes NO writable AMBIENT_LIGHT in fragment() or light(), so only
// the direct half of the clamp is reproduced: light() adds at most
// light_max_limit. The ambient half is the level's own, so a dark interior
// darkens the character with it and a sunlit street does not; EMISSION is only
// lilToon's floor, light_min_limit, so a pitch-black corner still shows her.
//
// DO NOT switch the environment's ambient off again and hand the model a fixed
// one through EMISSION. That was done while the levels' ambient was a
// saturated cold blue: it kept her colours, and made her glow the same grey in
// sun and in a dark room alike.
uniform float light_min_limit : hint_range(0.0, 1.0) = 0.05;
uniform float light_max_limit : hint_range(0.0, 2.0) = 1.0;
uniform float monochrome_lighting : hint_range(0.0, 1.0) = 0.2;

const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);

vec3 lil_blend(vec3 dst, vec3 src, vec3 w, int mode) {
	vec3 ad = dst + src;
	vec3 mu = dst * src;
	vec3 target = src;
	if (mode == 1) {
		target = ad;
	} else if (mode == 2) {
		target = max(ad - mu, dst);
	} else if (mode == 3) {
		target = mu;
	}
	return mix(dst, target, clamp(w, 0.0, 1.0));
}

void fragment() {
	vec4 alb = texture(albedo_tex, UV) * tint;
	if (alpha_scissor > 0.0 && alb.a < alpha_scissor) {
		discard;
	}
	vec2 muv = NORMAL.xy * vec2(0.5, -0.5) + 0.5;
	vec3 col = alb.rgb;

	vec4 mc = matcap_color * texture(matcap_tex, muv);
	mc.rgb = mix(mc.rgb, mc.rgb * alb.rgb, matcap_main_strength);
	col = lil_blend(col, mc.rgb,
		matcap_blend * mc.a * texture(matcap_mask, UV).rgb, matcap_mode);

	vec4 mc2 = matcap2_color * texture(matcap2_tex, muv);
	mc2.rgb = mix(mc2.rgb, mc2.rgb * alb.rgb, matcap2_main_strength);
	col = lil_blend(col, mc2.rgb,
		matcap2_blend * mc2.a * texture(matcap2_mask, UV).rgb, matcap2_mode);

	vec4 em = emission_color * texture(emission_tex, UV);
	em.rgb = mix(em.rgb, em.rgb * alb.rgb, emission_main_strength);
	col = lil_blend(col, em.rgb,
		emission_blend * em.a * texture(emission_blend_mask, UV).rgb, emission_mode);

	ALBEDO = col;
	EMISSION = col * light_min_limit;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	ALPHA = alb.a;
}

void light() {
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	// LIGHT_COLOR already carries the light's energy times PI.
	vec3 c = LIGHT_COLOR / PI * ATTENUATION * ndl;
	c = mix(c, vec3(dot(c, LUMA)), monochrome_lighting);
	DIFFUSE_LIGHT += ALBEDO * min(c, vec3(light_max_limit));
}
