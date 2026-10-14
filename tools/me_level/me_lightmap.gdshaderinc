// A static surface of an extracted Mirror's Edge level, lit by the original's
// own Beast lightmap and by nothing live: what the original's base pass draws
// for a lightmapped primitive. The level's fog still reaches it.
//
// The bake is the EMISSION, and the only light that changes it is the
// level's shadow light (geometry_builder's ShadowLight): a directional light
// of NEGATIVE energy, which only takes light away. Where something that moves
// blocks the sun, the bake is multiplied by the shadow's modulation, as the
// original's modulated shadows multiply the frame (light() below). Any other
// light reaching the surface -- the shell's sun in the editor -- is ignored:
// its shadows are in the bake already. With the shadow light off or out of
// range the surface is its bake exactly, as an unshaded one was. Ambient and
// specular are off so nothing else of Godot's lighting is added.
//
// [ME:CONFIRMED Engine/Shaders/BasePassPixelShader.usf, BasePassVertexShader.usf,
// LocalVertexFactory.usf, MaterialTemplate.usf]
//   LM_i     = sRGB_decode(tex_i(uv2 * scale + bias)) * ScaleVector_i   texture
//   LM_i     = pow(FColor_i.rgb, 2.2) * ScaleVector_i                    vertex
//   w_i      = saturate(dot(N_t, B_i)) ^ (2 * DiffusePower)               DiffusePower 1
//   Diffuse  = sum(LM_i * w_i) * DiffuseColor * (1 + DiffusePower) / 2
//   Spec     = sum(LM_i * saturate(dot(R_t, B_i)) ^ (SpecularPower + 1)) * SpecularColor
//   Color    = Emissive + Diffuse + Spec
// with B_i the directional lightmap basis in tangent space (Z the normal) and
// N_t the material's own normal there. A non-directional material takes every
// coefficient whole and has no lightmap specular.
//
// N_t is the original's tangent space, not Godot's: the baked normal map's
// green was flipped for Godot and is flipped back here, and the mesh's
// tangent sign was turned round for the axis map (static_mesh.godot_tangent),
// so TANGENT, BINORMAL and NORMAL here are the original's X, Y and Z.
//
// Colour uniforms are LINEAR: no source_color on a value the builder computes.

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_albedo_texture = false;
uniform vec3 albedo_color = vec3(1.0);
uniform vec2 uv1_scale = vec2(1.0);
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_normal_texture = false;
uniform float normal_scale = 1.0;
uniform sampler2D emissive_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_emissive_texture = false;
// [ME:INFERRED] UE3's defaults for an unconnected input: SpecularColor 0,
// SpecularPower 15.
uniform float specular = 0.0;
uniform float specular_power = 15.0;
uniform bool nondirectional = false;
uniform bool vertex_lightmap = false;
uniform sampler2D lightmap_0 : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D lightmap_1 : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D lightmap_2 : source_color, filter_linear_mipmap, repeat_disable;
// A vertex lightmap's samples, the chapter's (me_lightmaps.gd): three texels a
// vertex, the FColor bytes as stored, decoded here as the original's vertex
// shader decodes them.
uniform sampler2D vertex_samples : filter_nearest, repeat_disable;

// Per placement: where it lies in its atlas, and each coefficient's scale.
// Instance uniforms, so placements share their materials and Godot can draw
// them instanced: a copy of the material per placement doubled the
// tutorial's draw calls and cost the overview shot 1.7 ms of CPU a frame.
// Loaded from a scene file, Godot 4.7 leaves some instances reading the
// defaults instead (a lit tent drew black): me_lightmapped.gd sets them again.
// Every placement takes seven slots of the project's instance uniform buffer
// (rendering/limits/global_shader_variables/buffer_size): at Godot's default
// of 65536 the Escape ran out 4500 placements short, and those drew with the
// defaults -- the whole atlas -- as did the player's body loaded after them.
// Stormdrain alone needs some 91000. DO NOT lower it below 262144.
instance uniform vec4 lightmap_uv_scale_bias = vec4(1.0, 1.0, 0.0, 0.0);
instance uniform vec3 lightmap_scale_0 = vec3(1.0);
instance uniform vec3 lightmap_scale_1 = vec3(1.0);
instance uniform vec3 lightmap_scale_2 = vec3(1.0);
// Where the placement's run of vertex samples starts, in vertices.
instance uniform int lightmap_vertex_offset = 0;

// Runner Vision, as the original paints it: in the surface's own material
// ([ME:CONFIRMED 14 §14.3] LOI_Color and LOI_Strength are material
// parameters), so the red is lit by the same bake and darkened by the same
// shadow as the rest of the surface. RunnerVisionTarget drives both by these
// names (scripts/level/runner_vision_target.gd, paint_in_material).
//
// DO NOT draw the target's flat-coat overlay over this shader instead. An
// instance uniform's slot is its INDEX in its own shader, not its name: the
// overlay's strength and paint took slots 0 and 1, which are
// lightmap_uv_scale_bias and lightmap_scale_0 here, so fading it in rescaled
// the atlas lookup (the texture swam and striped) and tinted the bake red.
// The overlay was lit, too, and nothing reaches this layer but the negative
// shadow light: it drew near black, and lighter where the player's shadow fell.
instance uniform float strength = 0.0;
instance uniform vec3 paint = vec3(1.5, 0.0, 0.0);
// [ME:CONFIRMED 14 §14.3] EmissiveColor = LOI_Strength * DiffuseColor * 0.1.
const float RUNNER_VISION_GLOW = 0.1;

// The shadow light's point light, as the original places it: (position, 1 /
// Radius), world space; w = 0 when there is none (me_shadow_light.gd).
global uniform vec4 me_shadow_light_sphere;
// [ME:CONFIRMED DLE 0xff3a90] its ShadowFalloffExponent.
const float SHADOW_FALLOFF_EXPONENT = 0.5;
varying float shadow_falloff;

varying vec3 vertex_light_0;
varying vec3 vertex_light_1;
varying vec3 vertex_light_2;

// Columns are the basis vectors.
const mat3 LIGHTMAP_BASIS = mat3(
		vec3(0.0, 0.81649658, 0.57735027),
		vec3(-0.70710678, -0.40824829, 0.57735027),
		vec3(0.70710678, -0.40824829, 0.57735027));

void vertex() {
	if (vertex_lightmap) {
		// The original vertex this one is: VERTEX_ID, except on a surface the
		// library built flat, which records it in CUSTOM0.r, plus one.
		int source = CUSTOM0.r > 0.5 ? int(CUSTOM0.r + 0.5) - 1 : VERTEX_ID;
		int at = (lightmap_vertex_offset + source) * 3;
		int width = textureSize(vertex_samples, 0).x;
		// Per vertex, as the original's vertex shader does it, then interpolated.
		vertex_light_0 = pow(texelFetch(vertex_samples, ivec2(at % width, at / width), 0).rgb, vec3(2.2)) * lightmap_scale_0;
		vertex_light_1 = pow(texelFetch(vertex_samples, ivec2((at + 1) % width, (at + 1) / width), 0).rgb, vec3(2.2)) * lightmap_scale_1;
		vertex_light_2 = pow(texelFetch(vertex_samples, ivec2((at + 2) % width, (at + 2) / width), 0).rgb, vec3(2.2)) * lightmap_scale_2;
	}
}

void fragment() {
	vec2 uv = UV * uv1_scale;
	vec4 albedo = vec4(albedo_color, 1.0);
	if (use_albedo_texture) {
		albedo *= texture(albedo_texture, uv);
	}
	// The paint replaces the diffuse and leaves the lighting alone, as the
	// flat coat on a live-lit level does (shaders/runner_vision.gdshader).
	albedo.rgb = mix(albedo.rgb, paint, strength);
	vec3 n = vec3(0.0, 0.0, 1.0);
	if (use_normal_texture) {
		vec2 xy = (texture(normal_texture, uv).xy * 2.0 - 1.0) * normal_scale;
		n = normalize(vec3(xy.x, -xy.y, sqrt(max(1.0 - dot(xy, xy), 0.0))));
	}
	vec3 lm0, lm1, lm2;
	if (vertex_lightmap) {
		lm0 = vertex_light_0;
		lm1 = vertex_light_1;
		lm2 = vertex_light_2;
	} else {
		vec2 at = UV2 * lightmap_uv_scale_bias.xy + lightmap_uv_scale_bias.zw;
		lm0 = texture(lightmap_0, at).rgb * lightmap_scale_0;
		lm1 = texture(lightmap_1, at).rgb * lightmap_scale_1;
		lm2 = texture(lightmap_2, at).rgb * lightmap_scale_2;
	}
	vec3 light;
	vec3 shine = vec3(0.0);
	if (nondirectional) {
		light = lm0 + lm1 + lm2;
	} else {
		vec3 d = clamp(n * LIGHTMAP_BASIS, 0.0, 1.0);
		vec3 w = d * d;
		light = lm0 * w.x + lm1 * w.y + lm2 * w.z;
		if (specular > 0.0) {
			vec3 v = vec3(dot(VIEW, TANGENT), dot(VIEW, BINORMAL), dot(VIEW, NORMAL));
			vec3 r = -v + n * dot(n, v) * 2.0;
			vec3 s = pow(clamp(r * LIGHTMAP_BASIS, 0.0, 1.0), vec3(specular_power + 1.0));
			shine = (lm0 * s.x + lm1 * s.y + lm2 * s.z) * specular;
		}
	}
	vec3 color = albedo.rgb * light + shine + paint * (strength * RUNNER_VISION_GLOW);
	if (use_emissive_texture) {
		color += texture(emissive_texture, uv).rgb;
	}
	ALBEDO = color;
	EMISSION = color;
	shadow_falloff = 1.0;
	if (me_shadow_light_sphere.w > 0.0) {
		vec3 world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		vec3 offset = (world - me_shadow_light_sphere.xyz) * me_shadow_light_sphere.w;
		shadow_falloff = pow(clamp(1.0 - dot(offset, offset), 0.0, 1.0), SHADOW_FALLOFF_EXPONENT);
	}
	METALLIC = 0.0;
	SPECULAR = 0.0;
	ROUGHNESS = 1.0;
#ifdef ME_LIGHTMAP_MASKED
	ALPHA = albedo.a;
	ALPHA_SCISSOR_THRESHOLD = 0.4;
#endif
#ifdef ME_LIGHTMAP_TRANSLUCENT
	ALPHA = albedo.a;
#endif
}

// [ME:CONFIRMED ModShadowProjectionPixelShader.usf, ModShadowCommon.usf]
// the original multiplies the frame by lerp(lerp(1, ModulateColor, Att), 1,
// Lit^2), Lit the PCF fraction unoccluded (uniform PCF: BranchingPCF is off).
// The shadow light's colour is 1 - ModShadowColor and its energy -Fade, so
// -LIGHT_COLOR / PI (LIGHT_COLOR is the linear colour times the energy and PI)
// is (1 - ModulateColor). Att comes from shadow_falloff; ATTENUATION is Lit.
void light() {
	if (LIGHT_IS_DIRECTIONAL && LIGHT_COLOR.r + LIGHT_COLOR.g + LIGHT_COLOR.b < 0.0) {
		vec3 darkening = min(-LIGHT_COLOR / PI, vec3(1.0));
		DIFFUSE_LIGHT -= darkening * shadow_falloff * (1.0 - ATTENUATION * ATTENUATION);
	}
}
