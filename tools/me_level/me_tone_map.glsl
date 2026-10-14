#[compute]
#version 450

// Mirror's Edge's tone mapping, as the speedrun community's graphics mod
// draws it: the owner's install runs that mod, and the reference shots are of
// it. A port of Engine/Shaders/TdToneMappingPixelShader.usf line by line;
// the constants are the ones the game feeds it (me_tone_map.gd).
//
// The result is the frame as the original sends it to the screen. Godot's own
// tone mapper is left linear at exposure 1, so what this writes is turned
// back from the sRGB curve Godot puts on afterwards: the screen shows exactly
// this shader's output.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform image2D scene_color;
layout(r16, set = 0, binding = 1) uniform readonly image2D exposure_buffer;
layout(set = 0, binding = 2, std140) uniform Parameters {
	vec4 inverse_highlights;          // SceneInverseHighLights
	vec4 shadows_and_desaturation;    // SceneShadowsAndDesaturation
	vec4 midtones;                    // SceneMidTones
	vec4 scaled_luminance_weights;    // SceneScaledLuminanceWeights
	vec4 gamma_color_scale_and_inverse;
	vec4 gamma_overlay_color;
	vec4 curves_k[16];                // ColorCurvesKTexture: (M.r, B.r, M.g, B.g)
	vec4 curves_m[16];                // ColorCurvesMTexture: (M.b, B.b, 0, 0)
} p;

layout(push_constant, std430) uniform Size {
	ivec2 size;
	vec2 pad;
} frame;

const int NUM_CURVE_SEGMENTS = 16;
const vec3 LUMA_WEIGHTS = vec3(0.2126, 0.7152, 0.0722);

vec3 apply_white_neutrality_correction(vec3 color, vec3 luma_weights) {
	float white_luma_start = 0.72;
	float white_luma_range = 0.28;
	float white_chroma_start = 0.04;
	float white_chroma_range = 0.30;
	float white_neutrality_strength = 0.85;
	float luma = dot(color, luma_weights);
	float display_energy = (color.r + color.g + color.b) / 3.0;
	float peak = max(max(color.r, color.g), color.b);
	float low_channel = min(min(color.r, color.g), color.b);
	float relative_chroma = (peak - low_channel) / max(peak, 0.001);
	float luma_mask = clamp((luma - white_luma_start) / white_luma_range, 0.0, 1.0);
	float neutrality_mask = 1.0 - clamp((relative_chroma - white_chroma_start) / white_chroma_range, 0.0, 1.0);
	float white_mask = luma_mask * luma_mask * neutrality_mask * neutrality_mask;
	vec3 neutral_white = vec3(luma);
	vec3 corrected = mix(color, neutral_white, white_mask * white_neutrality_strength);
	float corrected_energy = (corrected.r + corrected.g + corrected.b) / 3.0;
	float energy_protection = min(1.0, display_energy / max(corrected_energy, 0.001));
	return clamp(corrected * mix(1.0, energy_protection, white_mask), 0.0, 1.0);
}

float black_point_adapt(float value, float old_black_point, float roll_off_range, float min_lum) {
	float t = (value - old_black_point) / roll_off_range;
	float toe = 1.0 - t;
	toe = toe * toe;
	toe = toe * toe;
	return (min_lum * toe + t) * roll_off_range + old_black_point;
}

vec3 apply_display_black_floor_correction(vec3 color, vec3 luma_weights) {
	float old_black_point = 2.5 / 255.0;
	float roll_off_stopping_point = 16.0 / 255.0;
	float roll_off_range = roll_off_stopping_point - old_black_point;
	float new_black_point = 0.0;
	float min_lum = (new_black_point - old_black_point) / roll_off_range;
	float display_luma = dot(color, luma_weights);
	if (display_luma >= roll_off_stopping_point) {
		return color;
	}
	float corrected_luma = max(0.0, black_point_adapt(display_luma, old_black_point, roll_off_range, min_lum));
	float luma_ratio = corrected_luma / max(display_luma, 0.0001);
	return clamp(color * luma_ratio, 0.0, 1.0);
}

// Point sampling of a 16-texel curve at u: [ME:CONFIRMED TM1 0x12d64e0] the
// curve textures are sampled SF_Point on D3D9.
int segment(float u) {
	return min(int(floor(clamp(u, 0.0, 1.0) * float(NUM_CURVE_SEGMENTS))), NUM_CURVE_SEGMENTS - 1);
}

float srgb_to_linear(float c) {
	return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
}

void main() {
	ivec2 at = ivec2(gl_GlobalInvocationID.xy);
	if (at.x >= frame.size.x || at.y >= frame.size.y) {
		return;
	}
	vec4 sampled = imageLoad(scene_color, at);
	vec3 color = sampled.rgb;
	float exposure = imageLoad(exposure_buffer, ivec2(0, 0)).r * 64.0;

	float linear_white = 4.0;
	float curve_domain_white = (float(NUM_CURVE_SEGMENTS) - 1.0) / float(NUM_CURVE_SEGMENTS);

	vec3 hdr_color = color * exposure;
	vec3 graded_hdr = max(vec3(0.0), hdr_color * p.inverse_highlights.rgb - p.shadows_and_desaturation.rgb);
	float luma_hdr = dot(graded_hdr, LUMA_WEIGHTS);
	float luma_tm = luma_hdr * (1.0 + (luma_hdr / (linear_white * linear_white))) / (1.0 + luma_hdr);
	vec3 reconstructed = graded_hdr * (luma_tm / max(luma_hdr, 0.0001));

	float highlight_chroma_weight = clamp((luma_hdr - (linear_white * 0.5)) / (linear_white * 1.5), 0.0, 1.0);
	highlight_chroma_weight = highlight_chroma_weight * highlight_chroma_weight;
	vec3 tonemapped = mix(reconstructed, vec3(luma_tm), highlight_chroma_weight * 0.55);

	float neutral_mid_tone = dot(p.midtones.rgb, LUMA_WEIGHTS);
	vec3 final_color = pow(max(vec3(0.0001), tonemapped), vec3(neutral_mid_tone));
	vec3 per_channel_final_color = pow(max(vec3(0.0001), tonemapped), p.midtones.rgb);
	float grade_preserve_weight = 1.0 - clamp((luma_tm - 0.16) * 1.75, 0.0, 1.0);
	final_color = mix(final_color, per_channel_final_color, grade_preserve_weight);

	vec3 scaled_luminance = vec3(dot(final_color, p.scaled_luminance_weights.rgb));
	vec3 material_result = p.gamma_overlay_color.rgb + final_color * p.shadows_and_desaturation.a + scaled_luminance;

	vec3 out_color = pow(clamp(material_result * p.gamma_color_scale_and_inverse.rgb, 0.0, 1.0),
			vec3(p.gamma_color_scale_and_inverse.a));

	float correction = curve_domain_white;
	vec4 r_curve = p.curves_k[segment(out_color.r * correction)];
	vec4 g_curve = p.curves_k[segment(out_color.g * correction)];
	vec4 b_curve = p.curves_m[segment(out_color.b * correction)];
	out_color.r = out_color.r * r_curve.r + r_curve.g;
	out_color.g = out_color.g * g_curve.b + g_curve.a;
	out_color.b = out_color.b * b_curve.r + b_curve.g;

	out_color = clamp(out_color / curve_domain_white, 0.0, 1.0);
	out_color = apply_white_neutrality_correction(out_color, LUMA_WEIGHTS);
	out_color = apply_display_black_floor_correction(out_color, LUMA_WEIGHTS);

	imageStore(scene_color, at, vec4(srgb_to_linear(out_color.r), srgb_to_linear(out_color.g),
			srgb_to_linear(out_color.b), sampled.a));
}
