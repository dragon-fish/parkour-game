// The sky of an extracted Mirror's Edge level, shared by the dome that is
// seen (me_dome.gdshader) and the sky that lights the world (me_sky.gdshader).
// A saturated gradient with the clouds of a photographed panorama laid over
// it, and a soft glare round the sun. The original's sky is a painted dome
// (S_Skydome_*, filtered out of the extraction as an FX mesh): deep blue
// overhead, paler at the horizon, white cumulus. What matters for the look is
// that the blue stays SATURATED down to the horizon and that the clouds are
// white, not the panorama's own colours: the panorama contributes only where
// it is brighter than its sky, as a mask.
//
// Colours are LINEAR as given: no source_color, which would gamma-decode a
// value that is already linear and quarter the sky's brightness.

uniform vec3 zenith_color = vec3(0.055, 0.12, 0.36);
uniform vec3 horizon_color = vec3(0.45, 0.55, 0.75);
uniform vec3 ground_color = vec3(0.4, 0.48, 0.64);
// How fast the horizon colour gives way to the zenith: below 1 the deep blue
// reaches most of the way down, which is what the original's dome does.
uniform float horizon_falloff : hint_range(0.1, 3.0) = 0.6;
// The whole sky, times this. The dome is drawn at the level's exposure, so
// the environment sets this to undo it; the lighting sky sets it to the sky
// light's share of the frame.
uniform float energy = 1.0;

uniform sampler2D cloud_panorama : source_color, filter_linear_mipmap, repeat_enable;
// Turns the panorama about the up axis, in radians, to put its clouds where
// the shot wants them.
uniform float cloud_yaw : hint_range(-3.1416, 3.1416) = 0.0;
// Panorama luminance where a pixel starts to count as cloud, and where it is
// fully one. HDR values: the photographed blue sky sits well below the first.
uniform float cloud_low = 0.35;
uniform float cloud_high = 0.9;
// Luminance at which a cloud reads as pure white; darker cloud keeps its
// shading, tinted toward the sky it stands in.
uniform float cloud_white = 1.6;
uniform float cloud_amount : hint_range(0.0, 1.0) = 1.0;
// Clouds sink into the horizon haze instead of standing on it.
uniform float cloud_horizon_fade = 0.08;

uniform float sun_disc_size : hint_range(0.0, 0.1) = 0.012;
uniform float sun_glow_power = 48.0;
uniform float sun_glow_energy = 0.35;
uniform vec3 sun_glow_color = vec3(1.0, 0.9, 0.6);
uniform vec3 sun_disc_color = vec3(1.0, 0.96, 0.9);

vec2 me_sky_uv(vec3 dir) {
	return vec2(atan(dir.x, -dir.z) / (2.0 * PI) + 0.5, acos(clamp(dir.y, -1.0, 1.0)) / PI);
}

vec3 me_sky_color(vec3 dir, vec3 sun_dir, bool with_disc) {
	float up = dir.y;
	vec3 col;
	if (up >= 0.0) {
		col = mix(horizon_color, zenith_color, pow(clamp(up, 0.0, 1.0), horizon_falloff));
	} else {
		col = mix(horizon_color, ground_color, pow(clamp(-up, 0.0, 1.0), 0.5));
	}
	if (up > -0.02 && cloud_amount > 0.0) {
		vec2 uv = me_sky_uv(dir);
		uv.x = fract(uv.x + cloud_yaw / (2.0 * PI));
		vec3 pano = texture(cloud_panorama, uv).rgb;
		float lum = dot(pano, vec3(0.2126, 0.7152, 0.0722));
		float mask = smoothstep(cloud_low, cloud_high, lum) * cloud_amount;
		mask *= smoothstep(0.0, cloud_horizon_fade, up);
		float shade = clamp(lum / cloud_white, 0.0, 1.0);
		vec3 cloud = mix(mix(horizon_color, zenith_color, 0.3) * 1.4, vec3(1.0), shade);
		col = mix(col, cloud, mask);
	}
	float cos_angle = dot(dir, sun_dir);
	col += sun_glow_color * pow(clamp(cos_angle, 0.0, 1.0), sun_glow_power) * sun_glow_energy;
	if (with_disc) {
		float disc = smoothstep(cos(sun_disc_size * 1.3), cos(sun_disc_size), cos_angle);
		col += sun_disc_color * disc * 4.0;
	}
	return col * energy;
}
