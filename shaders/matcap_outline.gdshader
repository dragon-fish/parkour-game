shader_type spatial;
render_mode cull_front, ambient_light_disabled, diffuse_lambert, specular_disabled,
		shadows_disabled;

// lilToon's outline pass, ported from lilxyzw/lilToon (lil_vert_outline.hlsl,
// lilCalcOutlinePosition). It is an inverted hull: the mesh is drawn a second
// time with front faces culled and every vertex pushed out along its normal,
// so what survives the depth test is a rim the width of that push.
//
// The model asks for this. Its five body materials all reference lts_o.shader
// (guid efa77a80ca0344749b4f19fdd5891cbe) -- lilToon's OUTLINE variant -- and
// the author hand-painted bodyOutlineMask.png to vary the width. DO NOT read
// the `_UseOutline: 0` in those .mat files as "outline off": that field is
// inspector bookkeeping, and the shader variant is what actually decides.
//
// outline_width is lilToon's own number and carries its 0.01 factor here, so
// 0.1 means one millimetre. That reads as a hairline, which is what the
// author's reference renders show -- this is not a heavy black cel border.
//
// NOT PORTED: lilToon's outline "lit" term, which lifts the rim back towards
// the plain texture colour where the surface faces the light
// (saturate(NdotL * 10 - 8) * _OutlineLitColor.a). It only fires above
// NdotL 0.8, so the visible cost is a slightly darker rim on directly lit
// faces. Adding it needs the light vector inside fragment(), which Godot does
// not hand out. Also not ported: _OutlineVertexR2Width (horn only) and
// _OutlineZBias -- reinstate the bias if the rim ever z-fights the body.

uniform sampler2D outline_tex : source_color, hint_default_white;
uniform sampler2D outline_width_mask : source_color, hint_default_white;
// Linear, straight from the .mat, so no source_color hint -- see the same note
// on the colours in matcap_toon.gdshader.
uniform vec3 outline_color = vec3(1.0);
uniform float outline_width : hint_range(0.0, 1.0) = 0.1;
uniform float outline_fix_width : hint_range(0.0, 1.0) = 0.5;
uniform float alpha_scissor : hint_range(0.0, 1.0) = 0.0;

// Kept in step with matcap_toon.gdshader on purpose: a rim lit by the level's
// ambient while the body it outlines is not would drift colour away from it.
// Change these two together or the rim separates from the silhouette.
uniform vec3 ambient_color = vec3(0.477, 0.692, 1.0);
uniform float ambient_energy : hint_range(0.0, 2.0) = 0.90;
uniform float light_max_limit : hint_range(0.0, 2.0) = 1.05;
uniform float monochrome_lighting : hint_range(0.0, 1.0) = 0.2;

const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);

void vertex() {
	float w = outline_width * 0.01;
	// lilToon thins the rim only within a metre of the eye; past that the width
	// is constant in world space.
	float dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	w *= mix(1.0, clamp(dist, 0.0, 1.0), outline_fix_width);
	// The mask is read at LOD 0: a vertex stage has no derivatives to pick one.
	w *= textureLod(outline_width_mask, UV, 0.0).r;
	VERTEX += NORMAL * w;
}

void fragment() {
	vec4 t = texture(outline_tex, UV);
	if (alpha_scissor > 0.0 && t.a < alpha_scissor) {
		discard;
	}
	vec3 col = t.rgb * outline_color;
	ALBEDO = col;
	EMISSION = col * ambient_color * ambient_energy;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	ALPHA = t.a;
}

void light() {
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	vec3 c = LIGHT_COLOR / PI * ATTENUATION * ndl;
	c = mix(c, vec3(dot(c, LUMA)), monochrome_lighting);
	vec3 headroom = vec3(max(light_max_limit - ambient_energy, 0.0));
	DIFFUSE_LIGHT += ALBEDO * min(c, headroom);
}
