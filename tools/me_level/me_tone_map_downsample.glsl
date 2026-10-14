#[compute]
#version 450

// One step of the luminance average the original's exposure reads.
// [ME:CONFIRMED TM1 0x012cffa0] each target pixel is the mean of n x n point
// samples of the source around its mapped centre, n = clamp(round(srcW /
// dstW), 1, 4) from the widths alone, and every level is a 16-bit UNORM
// target: the average is clamped to 0..1 per channel at every step. The chain
// is view -> 512 -> 128 -> 32 -> 8 -> 2 -> 1.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

// A sampler, read with texelFetch: the first source is the fp16 scene colour,
// every later one a UNORM level.
layout(set = 0, binding = 0) uniform sampler2D source;
layout(rgba16, set = 0, binding = 1) uniform writeonly image2D target;

layout(push_constant, std430) uniform Step {
	ivec2 source_size;
	ivec2 target_size;
	int taps;
	int pad0;
	int pad1;
	int pad2;
} step;

void main() {
	ivec2 at = ivec2(gl_GlobalInvocationID.xy);
	if (at.x >= step.target_size.x || at.y >= step.target_size.y) {
		return;
	}
	vec2 centre = (vec2(at) + 0.5) / vec2(step.target_size) * vec2(step.source_size);
	vec4 sum = vec4(0.0);
	for (int y = 0; y < step.taps; y++) {
		for (int x = 0; x < step.taps; x++) {
			ivec2 tap = ivec2(floor(centre + vec2(float(x), float(y)) - float(step.taps) * 0.5));
			tap = clamp(tap, ivec2(0), step.source_size - 1);
			sum += texelFetch(source, tap, 0);
		}
	}
	imageStore(target, at, clamp(sum / float(step.taps * step.taps), 0.0, 1.0));
}
