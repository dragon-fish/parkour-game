shader_type spatial;
render_mode blend_mix, depth_draw_never;

// The red a runner sees on the way through. Drawn as material_overlay over
// whatever the surface already is, so ANY mesh takes it -- a box dropped into
// a blockout as readily as an imported model. The original needed its art to
// cooperate: every material there carries LOI_Color and LOI_Strength
// parameters, and a material without them cannot light up at all
// (docs/mirrors-edge-deep-research/14-信使视觉LOI.md).
//
// STRENGTH AND COLOUR ARE PER-INSTANCE, so one material serves a whole level
// and each object fades on its own -- no duplicated materials, no per-object
// resources to keep in step. RunnerVisionTarget drives `strength` through
// GeometryInstance3D.set_instance_shader_parameter().
//
// LIT, NOT UNSHADED. Painted flat, an object loses its shading and with it
// every cue to its shape and distance -- a red rectangle where a pipe was. The
// original replaces the surface's diffuse and leaves the lighting alone, so
// the red still has a lit side and a shadowed one; this does the same. It does
// not write depth: it is a coat of paint, not a surface of its own.

// 0 invisible, 1 fully painted.
instance uniform float strength = 0.0;
// [ME:CONFIRMED] LOI_Color's default is (1.5, 0, 0): a red deliberately past
// white so it survives tone mapping and reads at a distance.
instance uniform vec3 paint : source_color = vec3(1.5, 0.0, 0.0);
// How much of the paint also glows. The original's runner-vision materials add
// emissive at a tenth of the colour; this is that tenth, as a dial.
uniform float glow : hint_range(0.0, 1.0) = 0.1;

void fragment() {
	ALBEDO = paint;
	// A little glow so the paint still reads in an unlit corner, well under
	// what would flatten it again.
	EMISSION = paint * glow * strength;
	ALPHA = clamp(strength, 0.0, 1.0);
}
