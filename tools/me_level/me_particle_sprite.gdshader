shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// A camera-facing sprite of one of the original's emitters, drawn as its
// material draws (tools/me_level/me_particles.gd reads the material's graph
// into these uniforms). For the smoke family that graph is, [ME:CONFIRMED
// M_FX_LevelFX_Smoke_CheapSmoke_01]:
//   Emissive = VertexColor.rgb * SubUV(T_FX_Smoke_DefaultSmoke_01_DA).g
//   Opacity  = clamp(DepthBiasedAlpha(SubUV.a * VertexColor.a, bias 0.5, scale 400), 0, 15)
// translucent and unlit. VertexColor is the particle's colour.
//
// The quad is the sprite's full width: a particle's size is its whole extent,
// not a radius. [ME:CONFIRMED Engine/Shaders/ParticleSpriteVertexFactory.usf]
// corners at Size * (TexCoord - 0.5) along the camera's unit right and up;
// [ME:INFERRED] the vertex's Size is the particle's times the component's
// scale, not doubled on the way.

uniform sampler2D sheet : source_color, filter_linear_mipmap, repeat_disable;
// The sheet's grid, columns by rows, and whether the frame between two sub
// images is a blend of both (PSUVIM_Linear_Blend) or the earlier alone.
uniform vec2 sub_images = vec2(1.0, 1.0);
uniform bool blend_sub_images = false;
// Brightness: the texture channel it takes (a mask dotted with the sample),
// or the sample's RGB when emissive_rgb is set, or 1 when the term has no
// texture; times the particle's colour when emissive_particle_color is set;
// times emissive_scale.
uniform bool emissive_textured = true;
uniform vec4 emissive_mask = vec4(0.0, 1.0, 0.0, 0.0);
uniform bool emissive_rgb = false;
uniform bool emissive_particle_color = true;
uniform float emissive_scale = 1.0;
// Opacity, the same way, with the particle's alpha.
uniform bool opacity_textured = true;
uniform vec4 opacity_mask = vec4(0.0, 0.0, 0.0, 1.0);
uniform bool opacity_particle_alpha = true;
uniform float opacity_scale = 1.0;
uniform vec2 opacity_clamp = vec2(0.0, 1.0);
// Metres of scene behind the sprite over which it fades in: what
// DepthBiasedAlpha does, so a sprite crossing a roof does not end in a line.
// 0 switches the fade off.
uniform float depth_fade_m = 0.0;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
// One over the level's exposure. A lit surface here is lit by a live
// sun as bright as the bake's (2.5 in the tutorial) and exposed back down by
// its inverse; an unlit sprite never sees that sun, so at the level's
// exposure alone it came out at a third of its brightness and the vents read
// as faint grey smudges where the tutorial's spawn shot has white wisps. The
// dome is drawn the same way (me_environment.gd). Judged against that shot.
// A uniform of the material, not an instance uniform: a build runs headless,
// and an instance uniform set there is not saved with the scene.
uniform float exposure_compensation = 1.0;

varying vec2 uv_a;
varying vec2 uv_b;
varying float sub_blend;

void vertex() {
	// As BaseMaterial3D's BILLBOARD_PARTICLES: face the camera, turn by the
	// particle's rotation, keep the particle's scale (its size).
	mat4 mat_world = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]),
			normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	mat_world = mat_world * mat4(vec4(cos(INSTANCE_CUSTOM.x), -sin(INSTANCE_CUSTOM.x), 0.0, 0.0),
			vec4(sin(INSTANCE_CUSTOM.x), cos(INSTANCE_CUSTOM.x), 0.0, 0.0),
			vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat_world;
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);

	float total = sub_images.x * sub_images.y;
	float index = clamp(INSTANCE_CUSTOM.z, 0.0, total - 1.0);
	float first = floor(index);
	float next = mod(first + 1.0, total);
	sub_blend = blend_sub_images ? index - first : 0.0;
	vec2 cell = vec2(1.0) / sub_images;
	uv_a = (vec2(mod(first, sub_images.x), floor(first / sub_images.x)) + UV) * cell;
	uv_b = (vec2(mod(next, sub_images.x), floor(next / sub_images.x)) + UV) * cell;
}

void fragment() {
	vec4 texel = mix(texture(sheet, uv_a), texture(sheet, uv_b), sub_blend);
	vec3 brightness = !emissive_textured ? vec3(1.0) : (emissive_rgb ? texel.rgb : vec3(dot(texel, emissive_mask)));
	if (emissive_particle_color) {
		brightness *= COLOR.rgb;
	}
	ALBEDO = brightness * emissive_scale * exposure_compensation;
	float opacity = (opacity_textured ? dot(texel, opacity_mask) : 1.0) * opacity_scale;
	if (opacity_particle_alpha) {
		opacity *= COLOR.a;
	}
	if (depth_fade_m > 0.0) {
		float depth = texture(depth_texture, SCREEN_UV).r;
		vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
		float scene_distance = -behind.z / behind.w;
		opacity *= clamp((scene_distance + VERTEX.z) / depth_fade_m, 0.0, 1.0);
	}
	ALPHA = clamp(opacity, opacity_clamp.x, min(opacity_clamp.y, 1.0));
}
