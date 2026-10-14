shader_type spatial;
// A translucent lightmapped surface. See me_lightmap.gdshaderinc.
render_mode ambient_light_disabled, specular_disabled, blend_mix, depth_draw_opaque;

#define ME_LIGHTMAP_TRANSLUCENT
#include "res://tools/me_level/me_lightmap.gdshaderinc"
