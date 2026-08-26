shader_type spatial;
render_mode cull_back, specular_schlick_ggx;

// A mirror that is not a perfect one.
//
// THE REFLECTION ARRIVES ALREADY FRAMED. Mirror builds a SubViewport whose
// camera shares the main camera's projection, so the pixel this fragment
// wants is at the fragment's own SCREEN_UV -- no projection maths in here,
// and the SubViewport may be rendered at any fraction of the main viewport's
// size without changing a thing, because SCREEN_UV is normalised.
//
// Everything below is the DIRT, and the dirt is what makes this affordable:
// a perfect mirror is the expensive one, because nothing hides a half-
// resolution render. Refraction offset, warp, haze and grime all disguise
// exactly the artefacts that a cheap reflection has.
//
// ✅ THE OWNER: "我希望那个镜子不要是超级干净的完美反射，需要能调出因为镜面有
// 厚度导致的折射+反射带来的光线损失+随机轻微扭曲，并且可以给镜面添加雾化，甚至
// 老化或碎裂效果."

// ⚠️ repeat_disable IS LOAD-BEARING. Godot's samplers default to repeat_enable,
// and every offset below can push a fragment near the frame's edge past 0 or 1
// -- where wrapping fetches from the OPPOSITE side of the reflection and draws
// a hard seam. ✅ THE OWNER: "如果镜子位于屏幕边缘会有奇怪的缝隙."
uniform sampler2D reflection_tex : filter_linear, repeat_disable, hint_default_black;

// Ordinary soda-lime glass. Fixed rather than exposed: it is what caps the
// thickness displacement below, and there is no look worth reaching by lying
// about what the pane is made of -- `thickness` is the dial for that.
const float GLASS_IOR = 1.5;

// Light the glass loses on the way in and out. A colour rather than a scalar
// so a mirror can lean cold or warm as well as dim; old silvering goes yellow-
// green, and this is the dial for it.
uniform vec4 reflectance : source_color = vec4(0.86, 0.88, 0.92, 1.0);

// Glass thickness in metres. Real mirrors silver the BACK face, so the image
// you see has crossed the pane twice and comes back displaced -- the further
// off-axis you look, the bigger the shift. Zero makes a front-silvered mirror
// with no displacement at all.
uniform float thickness : hint_range(0.0, 0.06) = 0.012;

// How uneven the pane is. Float glass is never flat; this is the slow, low-
// frequency wobble that makes a reflection breathe as you walk past it.
uniform float warp : hint_range(0.0, 1.0) = 0.35;
uniform float warp_scale : hint_range(0.5, 40.0) = 6.0;

// Fog on the glass. Cheap: a few taps, plus the contrast loss that actually
// reads as haze -- a dirty mirror loses CONTRAST more than it loses sharpness,
// and lifting the blacks sells it better than blurring does.
uniform float haze : hint_range(0.0, 1.0) = 0.25;
uniform vec4 haze_color : source_color = vec4(0.72, 0.76, 0.82, 1.0);

// Age: patchy darkening and desaturation, as the silvering goes.
uniform float grime : hint_range(0.0, 1.0) = 0.30;
uniform float grime_scale : hint_range(0.5, 40.0) = 9.0;

// The glass itself, seen when the reflection gives up: edge-on the pane is
// bright, face-on it is nearly all reflection.
uniform float fresnel_strength : hint_range(0.0, 1.0) = 0.25;
uniform float roughness_amount : hint_range(0.0, 1.0) = 0.06;

varying vec3 view_dir_local;

// -- value noise, two octaves ------------------------------------------------
// Deliberately not a texture: the warp and the grime want to be TUNED, and a
// dial that regenerates the pattern beats a mask nobody can adjust without
// leaving the engine. A crack mask will need a real texture; these do not.
float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm2(vec2 p) {
	return value_noise(p) * 0.65 + value_noise(p * 2.17 + 11.3) * 0.35;
}

void vertex() {
	// The eye, in the quad's own space. Used for the thickness offset, which
	// has to grow with the viewing angle rather than with screen position.
	view_dir_local = (inverse(MODELVIEW_MATRIX) * vec4(0.0, 0.0, 0.0, 1.0)).xyz - VERTEX;
}

void fragment() {
	// ⚠️ THE U FLIP IS NOT A HACK, IT IS THE OTHER HALF OF Mirror.reflect_across.
	//
	// A true reflection basis is LEFT-handed. A left-handed camera inverts
	// triangle winding and renders every surface in the mirror inside-out, so
	// reflect_across rebuilds a right-handed one through Basis.looking_at --
	// and the way looking_at achieves that is by negating the camera's X axis.
	// The cost does not vanish, it moves into the image: the reflection comes
	// out mirrored about the viewport's vertical centre line. Measured, not
	// argued -- a point the real mirror should put at screen x=274 came back
	// at x=526 in an 800-wide viewport, and dead centre stayed put.
	//
	// ✅ THE OWNER SPOTTED IT: "我面对镜子，往左扭头，镜子里的角色也往左，理论上
	// 镜子里的角色应该相对镜头往右." Same flip, seen as a rotation.
	//
	// Negating the camera's X mirrors a symmetric perspective projection about
	// that centre line exactly, so 1.0 - u is its exact inverse. Undo it FIRST,
	// then every offset below is in honest mirror space.
	vec2 uv = vec2(1.0 - SCREEN_UV.x, SCREEN_UV.y);

	// -- thickness: the second surface is the one that reflects -------------
	// The image crosses the pane, bounces off the silvering at the back, and
	// crosses again -- landing somewhere else on the glass, further off the
	// more steeply you look.
	//
	// ⚠️ IT MUST SATURATE. An earlier version scaled by 1/cos of the view
	// angle, which diverges: at a grazing view it reached 0.08 uv, eight
	// percent of the screen, and the reflection visibly swung away from the
	// thing reflecting. ✅ THE OWNER: "视线越偏，镜子里的内容也越偏，比如这里镜框
	// 的虚像已经和本体形成几乎15°夹角了."
	//
	// Real glass cannot do that, because the ray REFRACTS on the way in and the
	// refracted angle is capped by total internal reflection -- about 41° for
	// n = 1.5. So the sideways travel is bounded by 2 * thickness * tan(41°),
	// roughly 1.7 thicknesses, however steeply you look. That missing refraction
	// was the whole bug: the old formula had light going straight through glass.
	vec3 v = normalize(view_dir_local);
	float sin_in = length(v.xy);
	vec2 lateral = sin_in > 0.0001 ? v.xy / sin_in : vec2(0.0);
	float tan_out = sin_in / sqrt(max(GLASS_IOR * GLASS_IOR - sin_in * sin_in, 0.0001));
	vec2 offset = lateral * (2.0 * thickness * tan_out);

	// -- warp: the pane is not flat -----------------------------------------
	if (warp > 0.0) {
		vec2 w = vec2(
			fbm2(UV * warp_scale),
			fbm2(UV * warp_scale + 37.7)
		) - 0.5;
		offset += w * warp * 0.02;
	}

	// THE REFLECTION HAS NO OUTSIDE. Every offset above asks for a pixel next
	// to this one, and near the frame's edge that pixel was never rendered --
	// the reflection viewport holds exactly the main view's framing and not one
	// texel more. At a grazing angle the thickness term alone reaches 0.08 uv,
	// eight percent of the screen, which is a wide band of nothing to fetch.
	//
	// Faded over exactly the room each axis has left, so an offset is full
	// strength wherever it fits and gone by the edge. Clamping alone would stop
	// the wrap but smear the last texel into a streak instead; this way there
	// is nothing to smear.
	vec2 room = min(uv, vec2(1.0) - uv);
	uv += offset * smoothstep(vec2(0.0), abs(offset) + 0.0001, room);
	uv = clamp(uv, vec2(0.0), vec2(1.0));

	// -- the reflection, hazed ----------------------------------------------
	vec3 reflected = texture(reflection_tex, uv).rgb;
	if (haze > 0.0) {
		// Four taps on a rotated cross. ViewportTextures carry no mipmaps in
		// Godot, so there is no cheap LOD to blur with -- but the reflection is
		// already rendered at a fraction of screen size, so these taps are
		// cheap and land further apart than their offsets suggest.
		// Clamped for the same reason as the offsets above: a tap that lands
		// outside the frame has nothing to average in.
		float r = haze * 0.006;
		vec3 blur = texture(reflection_tex, clamp(uv + vec2( r,  r * 0.5), vec2(0.0), vec2(1.0))).rgb
			+ texture(reflection_tex, clamp(uv + vec2(-r, -r * 0.5), vec2(0.0), vec2(1.0))).rgb
			+ texture(reflection_tex, clamp(uv + vec2( r * 0.5, -r), vec2(0.0), vec2(1.0))).rgb
			+ texture(reflection_tex, clamp(uv + vec2(-r * 0.5,  r), vec2(0.0), vec2(1.0))).rgb;
		reflected = mix(reflected, blur * 0.25, haze);
		// The half that actually sells it: contrast, not sharpness.
		reflected = mix(reflected, haze_color.rgb, haze * 0.35);
	}

	// -- age -----------------------------------------------------------------
	float grime_mask = 1.0;
	if (grime > 0.0) {
		float g = fbm2(UV * grime_scale + 5.1);
		grime_mask = mix(1.0, smoothstep(0.15, 0.85, g), grime);
		float grey = dot(reflected, vec3(0.299, 0.587, 0.114));
		reflected = mix(reflected, vec3(grey), grime * (1.0 - grime_mask) * 0.8);
	}

	// -- light lost crossing the glass, twice --------------------------------
	reflected *= reflectance.rgb * grime_mask;

	// Edge-on, the pane's own sheen takes over from the image.
	float fres = pow(1.0 - clamp(dot(normalize(view_dir_local), vec3(0.0, 0.0, 1.0)), 0.0, 1.0), 3.0);

	ALBEDO = reflected;
	EMISSION = reflected * 0.6;
	SPECULAR = 0.5 + fres * fresnel_strength;
	ROUGHNESS = roughness_amount + grime * (1.0 - grime_mask) * 0.4;
	METALLIC = 0.0;
}
