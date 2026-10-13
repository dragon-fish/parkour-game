shader_type particles;

// One LOD of one of the original's sprite emitters (tools/me_level/
// me_particles.gd fills every uniform from the extract). Not a
// ParticleProcessMaterial: that takes a starting velocity as a direction and a
// spread, and the original's is a box -- every component drawn on its own
// between its own min and max -- which no direction and spread reproduce.
//
// Every value is in the EMITTER's space and turned into the simulation's on
// the way out: EMISSION_TRANSFORM is the node's transform for a world-space
// system and identity for a local one, so a velocity multiplied by it is
// right in both. Acceleration is NOT turned: [ME:INFERRED UDK
// ParticleModuleAccelerationOverLifetime] the original adds it in whatever
// space the emitter simulates in.
//
// CUSTOM carries x: sprite rotation (radians), y: age over lifetime (0..1),
// z: sub-image index (the SubUV curve's value), w: this particle's lifetime
// (seconds). The sprite shader reads x and z.

// The shortest lifetime over the longest, which is the system's LIFETIME.
uniform float lifetime_min_ratio = 1.0;
uniform vec3 location_min = vec3(0.0);
uniform vec3 location_max = vec3(0.0);
uniform vec3 velocity_min = vec3(0.0);
uniform vec3 velocity_max = vec3(0.0);
// Sprite width in metres: the original's square sprites take Size.X alone.
uniform float size_min = 1.0;
uniform float size_max = 1.0;
uniform float rotation_min = 0.0;
uniform float rotation_max = 0.0;
// HDR: the original's colours go above 1 (VentSmoke_01_Big is 1.357).
uniform vec3 color_scale = vec3(1.0);
uniform float alpha_scale = 1.0;
uniform bool clamp_alpha = true;
// Every value over a particle's life is scale * curve(age). A curve is sampled
// from the original's own keys; a constant leaves its curve unset (white) and
// lives in the scale alone, and an absent module is a scale of its neutral.
uniform sampler2D size_curve : hint_default_white, repeat_disable, filter_linear;
uniform sampler2D color_curve : hint_default_white, repeat_disable, filter_linear;
uniform sampler2D alpha_curve : hint_default_white, repeat_disable, filter_linear;
uniform vec3 accel_scale = vec3(0.0);
uniform sampler2D accel_curve : hint_default_white, repeat_disable, filter_linear;
uniform float sub_image_scale = 0.0;
uniform sampler2D sub_image_curve : hint_default_white, repeat_disable, filter_linear;

float rand_from_seed(inout uint seed) {
	int k;
	int s = int(seed);
	if (s == 0) {
		s = 305420679;
	}
	k = s / 127773;
	s = 16807 * (s - k * 127773) - 2836 * k;
	if (s < 0) {
		s += 2147483647;
	}
	seed = uint(s);
	return float(seed % uint(65536)) / 65535.0;
}

uint hash(uint x) {
	x = ((x >> uint(16)) ^ x) * uint(73244475);
	x = ((x >> uint(16)) ^ x) * uint(73244475);
	x = (x >> uint(16)) ^ x;
	return x;
}

// The particle's own random draws, the same in start() and in every
// process(): a particle's starting size is needed each frame and there is no
// slot left in CUSTOM to keep it.
struct Draws {
	float life;
	vec3 location;
	vec3 velocity;
	float rotation;
	float size;
};

Draws draws(uint number, uint random_seed) {
	uint seed = hash(number + uint(1) + random_seed);
	Draws d;
	d.life = rand_from_seed(seed);
	d.location = vec3(rand_from_seed(seed), rand_from_seed(seed), rand_from_seed(seed));
	d.velocity = vec3(rand_from_seed(seed), rand_from_seed(seed), rand_from_seed(seed));
	d.rotation = rand_from_seed(seed);
	d.size = rand_from_seed(seed);
	return d;
}

void set_size(inout mat4 xform, float size) {
	float s = max(size, 0.0001);
	xform[0].xyz = vec3(s, 0.0, 0.0);
	xform[1].xyz = vec3(0.0, s, 0.0);
	xform[2].xyz = vec3(0.0, 0.0, s);
}

void start() {
	Draws d = draws(NUMBER, RANDOM_SEED);
	if (RESTART_CUSTOM) {
		CUSTOM = vec4(mix(rotation_min, rotation_max, d.rotation), 0.0,
				sub_image_scale * texture(sub_image_curve, vec2(0.0)).r,
				LIFETIME * mix(lifetime_min_ratio, 1.0, d.life));
	}
	if (RESTART_VELOCITY) {
		VELOCITY = mat3(EMISSION_TRANSFORM) * mix(velocity_min, velocity_max, d.velocity);
	}
	if (RESTART_POSITION) {
		TRANSFORM = mat4(1.0);
		TRANSFORM[3].xyz = (EMISSION_TRANSFORM * vec4(mix(location_min, location_max, d.location), 1.0)).xyz;
	}
	if (RESTART_COLOR) {
		COLOR = vec4(color_scale * texture(color_curve, vec2(0.0)).rgb, alpha_scale * texture(alpha_curve, vec2(0.0)).r);
	}
	set_size(TRANSFORM, mix(size_min, size_max, d.size) * texture(size_curve, vec2(0.0)).r
			* length(EMISSION_TRANSFORM[0].xyz));
}

void process() {
	Draws d = draws(NUMBER, RANDOM_SEED);
	CUSTOM.y += DELTA / max(CUSTOM.w, 0.001);
	if (CUSTOM.y >= 1.0) {
		ACTIVE = false;
	}
	vec2 t = vec2(clamp(CUSTOM.y, 0.0, 1.0), 0.0);
	VELOCITY += accel_scale * texture(accel_curve, t).rgb * DELTA;
	CUSTOM.z = sub_image_scale * texture(sub_image_curve, t).r;
	float alpha = alpha_scale * texture(alpha_curve, t).r;
	COLOR = vec4(color_scale * texture(color_curve, t).rgb, clamp_alpha ? clamp(alpha, 0.0, 1.0) : alpha);
	set_size(TRANSFORM, mix(size_min, size_max, d.size) * texture(size_curve, t).r
			* length(EMISSION_TRANSFORM[0].xyz));
}
