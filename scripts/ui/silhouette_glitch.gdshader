shader_type canvas_item;

// Subtle glitch over the walking silhouette (✅ the owner: "角色剪影带轻微
// 故障粒子"): once in a while a few horizontal bands shear sideways for a
// frame or two, with a faint red/white split. Zero texture reads beyond the
// screen itself; everything is hashed off TIME so it never repeats visibly.

uniform float burst_chance : hint_range(0.0, 1.0) = 0.12;
uniform float band_height : hint_range(0.002, 0.08) = 0.014;
uniform float shear_px = 7.0;
uniform float split_px = 1.5;
uniform float width_px = 1920.0;

float hash(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	// A new dice roll every ~0.09 s; most rolls do nothing.
	float slot = floor(TIME * 11.0);
	float roll = hash(slot);
	float shear = 0.0;
	if (roll < burst_chance) {
		// Two or three bands, positions hashed off the slot.
		for (int i = 0; i < 3; i++) {
			float band_y = hash(slot + float(i) * 7.3);
			if (abs(uv.y - band_y) < band_height * (0.5 + hash(slot + float(i) + 0.5))) {
				shear = (hash(slot + float(i) + 0.25) - 0.5) * 2.0 * shear_px / width_px;
			}
		}
	}
	uv.x += shear;
	vec4 base = texture(TEXTURE, uv);
	if (shear != 0.0) {
		// Faint chromatic split only inside the sheared band.
		float off = split_px / width_px;
		float r = texture(TEXTURE, uv + vec2(off, 0.0)).a;
		float w = texture(TEXTURE, uv - vec2(off, 0.0)).a;
		base.rgb = mix(base.rgb, vec3(0.913, 0.004, 0.0), r * 0.25);
		base.a = max(base.a, max(r, w) * 0.6);
	}
	COLOR = base;
}
