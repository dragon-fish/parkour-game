shader_type spatial;
// depth_draw_always keeps the packed box writing depth. At progress 0 this
// material has to read as the solid it replaces, and a transparent surface
// that skips the depth buffer sorts wrong against everything around it.
render_mode blend_mix, depth_draw_always, cull_back;

// 0 = the packed box, 1 = fully dispersed. Driven by GrowingSolid.
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 base_color : source_color = vec4(0.93, 0.95, 0.97, 1.0);
uniform vec4 glow_color : source_color = vec4(0.85, 0.92, 1.0, 1.0);
// Metres a cube travels by the time it is gone.
uniform float travel = 3.0;
uniform float glow_strength = 3.0;

varying float leaving;

void vertex() {
	// INSTANCE_CUSTOM carries this cube's own direction (rgb) and the point in
	// the run at which it starts moving (a), so the block does not leave on
	// one frame.
	//
	// THIS IS THE SAME ARITHMETIC AS CubeSwarm.cube_origin(). Those two are
	// the only copies of it: change one and change the other, or the swarm on
	// screen stops matching the swarm the tests describe.
	float delay = INSTANCE_CUSTOM.a;
	float k = clamp((progress - delay) / max(1.0 - delay, 0.0001), 0.0, 1.0);
	leaving = k;
	// Shrink about the cube's own centre, then carry it off. At k = 0 the
	// scale is 1 and the offset is 0, which is what makes the packed grid
	// indistinguishable from the solid box it stands in for.
	VERTEX *= 1.0 - k;
	VERTEX += normalize(INSTANCE_CUSTOM.rgb + vec3(1e-5)) * travel * k;
}

void fragment() {
	ALBEDO = mix(base_color.rgb, glow_color.rgb, leaving);
	EMISSION = glow_color.rgb * glow_strength * leaving;
	ALPHA = 1.0 - leaving * leaving;
	ROUGHNESS = 0.6;
}
