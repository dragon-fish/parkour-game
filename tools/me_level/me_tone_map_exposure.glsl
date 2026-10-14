#[compute]
#version 450

// The original's eye adaptation, as the speedrun community's graphics mod
// computes it: Engine/Shaders/TdToneMapExposurePixelShader.usf, line by line.
// One invocation; it reads the luminance average and last frame's exposure
// and writes this frame's, which the tone mapping reads.
// [ME:CONFIRMED TM1 0x012d37e0] the exposure buffers are 1x1 16-bit UNORM
// holding exposure / 64.

layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;

layout(rgba16, set = 0, binding = 0) uniform readonly image2D average;
layout(r16, set = 0, binding = 1) uniform readonly image2D previous_exposure;
layout(r16, set = 0, binding = 2) uniform writeonly image2D new_exposure;

layout(push_constant, std430) uniform Settings {
	vec4 exposure_settings;   // (Manual, dt * min(SpeedUp, 2.5), Low, High)
	float max_delta_down;     // dt * min(SpeedDown, 3)
	float pad0;
	float pad1;
	float pad2;
} s;

void main() {
	vec3 sampled_color = imageLoad(average, ivec2(0, 0)).rgb;
	if (!(sampled_color.r > 0.0) && !(sampled_color.r < 0.0)) {
		sampled_color = vec3(0.25);
	}
	float avg_luminance = dot(sampled_color, vec3(0.2126, 0.7152, 0.0722));
	float key_value = 0.25;
	float dark_boost_max = 1.00;
	float target_unclamped = key_value / max(avg_luminance, 0.001);
	float target_clamped = clamp(target_unclamped, s.exposure_settings.b, s.exposure_settings.a);
	float clamp_deficit = clamp(1.0 - target_clamped / target_unclamped, 0.0, 1.0);
	float max_exposure = s.exposure_settings.a * (1.0 + dark_boost_max);
	float target_exposure = target_clamped * (1.0 + dark_boost_max * clamp_deficit);

	float current_exposure = imageLoad(previous_exposure, ivec2(0, 0)).r * 64.0;
	current_exposure = clamp(current_exposure, s.exposure_settings.b, max_exposure);

	float adaptation_alpha;
	if (target_exposure < current_exposure) {
		adaptation_alpha = clamp(s.max_delta_down * (9.3 / 0.475), 0.0, 1.0);
	} else {
		adaptation_alpha = clamp(s.exposure_settings.g * (1.24 / 0.275), 0.0, 1.0);
	}
	float exposure = mix(current_exposure, target_exposure, adaptation_alpha);
	exposure = clamp(exposure, s.exposure_settings.b, max_exposure);
	imageStore(new_exposure, ivec2(0, 0), vec4(exposure * s.exposure_settings.r / 64.0));
}
