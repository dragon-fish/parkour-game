// A static surface of an extracted Mirror's Edge level, lit by the original's
// own Beast lightmap and by nothing live: what the original's base pass draws
// for a lightmapped primitive. Unshaded, so no Godot light and no GI reaches
// it; the level's fog still does.
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

// Per placement: where it lies in its atlas, and each coefficient's scale.
instance uniform vec4 lightmap_uv_scale_bias = vec4(1.0, 1.0, 0.0, 0.0);
instance uniform vec3 lightmap_scale_0 = vec3(1.0);
instance uniform vec3 lightmap_scale_1 = vec3(1.0);
instance uniform vec3 lightmap_scale_2 = vec3(1.0);

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
		// Per vertex, as the original's vertex shader does it, then interpolated.
		vertex_light_0 = pow(CUSTOM0.rgb, vec3(2.2)) * lightmap_scale_0;
		vertex_light_1 = pow(CUSTOM1.rgb, vec3(2.2)) * lightmap_scale_1;
		vertex_light_2 = pow(CUSTOM2.rgb, vec3(2.2)) * lightmap_scale_2;
	}
}

void fragment() {
	vec2 uv = UV * uv1_scale;
	vec4 albedo = vec4(albedo_color, 1.0);
	if (use_albedo_texture) {
		albedo *= texture(albedo_texture, uv);
	}
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
	vec3 color = albedo.rgb * light + shine;
	if (use_emissive_texture) {
		color += texture(emissive_texture, uv).rgb;
	}
	ALBEDO = color;
#ifdef ME_LIGHTMAP_MASKED
	ALPHA = albedo.a;
	ALPHA_SCISSOR_THRESHOLD = 0.4;
#endif
#ifdef ME_LIGHTMAP_TRANSLUCENT
	ALPHA = albedo.a;
#endif
}
