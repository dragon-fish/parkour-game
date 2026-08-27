shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha, ambient_light_disabled,
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
// Godot 4 exposes NO writable AMBIENT_LIGHT in fragment() or light(), so the
// clamp cannot be applied to the environment's ambient after the fact. The
// environment's contribution is switched off for this material and its share of
// the budget is supplied here instead: EMISSION carries the ambient half (the
// only route to unlit brightness once ambient_light_disabled is set), and
// light() may add at most the headroom left under the ceiling.
//
// ambient_energy is NOT lilToon's 0.15 floor. That floor only ever mattered in
// a dark world; a lit one hands lilToon an ambient near 1.0, which is what the
// author's own renders show. Set this to what the character should read as with
// no sun on it, and light_max_limit to what full sun may take it to.
//
// DO NOT drop ambient_light_disabled so the character "sits in the scene". The
// level's ambient is a saturated cold blue on purpose; at full strength it dyes
// the entire model, which is the failure this replaces. ambient_color is the
// dial for letting the level's mood reach the skin: the model's own texture is
// a warm white, which reads as yellow against a cold level until this cools it.
//
// LINEAR, like every other colour here, and for a second reason on top of the
// one above: a shader's DEFAULT value is not gamma-decoded, while the same
// numbers set on the material are. Leaving the hint on would make the default
// and an override disagree. 0.477/0.692/1.0 is sRGB 0.72/0.85/1.0.
uniform vec3 ambient_color = vec3(0.477, 0.692, 1.0);
uniform float ambient_energy : hint_range(0.0, 2.0) = 0.90;
uniform float light_max_limit : hint_range(0.0, 2.0) = 1.05;
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
	EMISSION = col * ambient_color * ambient_energy;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	ALPHA = alb.a;
}

void light() {
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	// LIGHT_COLOR already carries the light's energy times PI.
	vec3 c = LIGHT_COLOR / PI * ATTENUATION * ndl;
	c = mix(c, vec3(dot(c, LUMA)), monochrome_lighting);
	vec3 headroom = vec3(max(light_max_limit - ambient_energy, 0.0));
	DIFFUSE_LIGHT += ALBEDO * min(c, headroom);
}
