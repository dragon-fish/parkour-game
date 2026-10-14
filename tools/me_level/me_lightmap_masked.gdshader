shader_type spatial;
// A masked lightmapped surface (gratings, fences): cut out where its
// OpacityMask falls under the threshold. See me_lightmap.gdshaderinc.
render_mode unshaded;

#define ME_LIGHTMAP_MASKED
#include "res://tools/me_level/me_lightmap.gdshaderinc"
