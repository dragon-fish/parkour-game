shader_type sky;

// The sky that LIGHTS an extracted Mirror's Edge level (ambient and SDFGI).
// The dome the player sees is me_dome.gdshader on a mesh, drawn brighter:
// the original's dome is a painting, several times brighter than the sky
// light its lightmaps were baked with, and Godot has one sky for both.

#include "res://tools/me_level/me_sky_common.gdshaderinc"

void sky() {
	vec3 sun_dir = LIGHT0_ENABLED ? LIGHT0_DIRECTION : vec3(0.0, 1.0, 0.0);
	COLOR = me_sky_color(EYEDIR, sun_dir, false);
}
