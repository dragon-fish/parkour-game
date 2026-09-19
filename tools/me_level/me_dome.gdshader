shader_type spatial;
// The dome the player SEES: an inverted sphere round the camera, unlit, out
// of the fog, drawn with the same sky as me_sky.gdshader but at the dome's
// own brightness. See me_sky_common.gdshaderinc.
render_mode unshaded, cull_disabled, fog_disabled, depth_draw_opaque, shadows_disabled;

#include "res://tools/me_level/me_sky_common.gdshaderinc"

uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0);

varying vec3 world_dir;

void vertex() {
	world_dir = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - CAMERA_POSITION_WORLD;
}

void fragment() {
	ALBEDO = me_sky_color(normalize(world_dir), normalize(sun_direction), true);
}
