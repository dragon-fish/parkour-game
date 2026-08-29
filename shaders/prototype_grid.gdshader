shader_type spatial;

// Prototype grid: acrylic.gdshader's surface with its dots replaced by a
// ruled grid, for blocking out.
//
// SAME SHEET, DIFFERENT MARKING. Base colour, dot colour, metallic and
// roughness are acrylic's, so a whitebox reads as the same material the game
// is made of rather than as a borrowed engineering texture. Only what is
// printed on it changes: a metre grid instead of a dot field, because a grid
// can be counted and dots cannot.
//
// WORLD SPACE, TRIPLANAR. One cell is one metre on a floor, a wall and a CSG
// offcut alike -- stretch a textured box and its ruler stretches with it,
// stretch this one and the cells stay square. Which is the whole reason this
// is a shader and not an image.
//
// NO THRESHOLD MARKS, and this is a decision rather than an omission. Drawing
// "1.8 m is the lowest wall the hands can catch" as a line needs two things
// that are not true. It needs the floor to be at y = 0, when a rooftop level
// stands 60 m up and every line lands in the basement. And it needs the
// threshold to be a world height at all, when GrabConfig measures
// ledge_max_height FROM THE FEET -- at the apex of a jump the feet are 1.24 m
// up and the reach is 4.04 m, so the number has no fixed place to be drawn. A
// line that certifies a wall the body cannot climb is worse than no line. If
// this is wanted it belongs on a gizmo that follows the player and reads the
// live state, not baked into a surface.
//
// LINES ARE WIDENED TO STAY VISIBLE AT DISTANCE. A line thinner than a pixel
// does not fade, it ALIASES -- the far half of a large floor turns into
// crawling moire, which is what makes a fine grid unpleasant to stand on.
// fwidth() gives the size of a pixel in world units here, so a line is never
// asked to be thinner than it can be drawn and the grid dissolves into flat
// colour in the distance instead of shimmering. That floor is what lets the
// 0.2 m subdivision exist at all.

// acrylic.gdshader's own values, unchanged.
uniform vec4 base_color : source_color = vec4(0.94, 0.95, 0.97, 1.0);
uniform vec4 line_color : source_color = vec4(0.62, 0.7, 0.8, 1.0);
// As faint as the dots were. The grid is there to say whether you are moving
// and how big a thing is; it is not the subject of the picture.
uniform float line_opacity : hint_range(0.0, 1.0) = 0.1;
uniform float metallic_amount : hint_range(0.0, 1.0) = 0.4;
uniform float roughness_amount : hint_range(0.0, 1.0) = 0.12;
uniform float projection_sharpness : hint_range(1.0, 16.0) = 6.0;

// The metre. Every count is in these.
uniform float spacing = 1.0;
uniform float line_width = 0.02;
// The fine ruling inside each cell, for reading a size smaller than a stride.
// Set to 0 to switch it off.
uniform float fine_spacing = 0.2;
uniform float fine_width = 0.008;
// How much fainter the fine ruling is than the metre lines, so a cell edge is
// still tellable from a subdivision at a glance.
uniform float fine_fade : hint_range(0.0, 1.0) = 0.45;

varying vec3 world_position;
varying vec3 world_normal;

// How strongly a line falls on this point, for one 2D slice of the world.
// 0 inside a cell, 1 on a line.
float grid_line(vec2 p, float period, float width) {
	if (period <= 0.0) {
		return 0.0;
	}
	vec2 cell = abs(fract(p / period - 0.5) - 0.5) * period;
	vec2 pixel = fwidth(p);
	vec2 half_width = max(vec2(width * 0.5), pixel);
	vec2 line = 1.0 - smoothstep(half_width - pixel, half_width + pixel, cell);
	return max(line.x, line.y);
}

// The whole ruling on one plane: metre lines at full weight, the subdivision
// under them. Taken as a max rather than a sum so a fine line landing on a
// metre line does not double up and read heavier than its neighbours.
float ruling(vec2 p) {
	return max(grid_line(p, spacing, line_width),
		grid_line(p, fine_spacing, fine_width) * fine_fade);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 weights = pow(abs(world_normal), vec3(projection_sharpness));
	weights /= max(weights.x + weights.y + weights.z, 0.0001);

	float lines = ruling(world_position.zy) * weights.x
		+ ruling(world_position.xz) * weights.y
		+ ruling(world_position.xy) * weights.z;

	ALBEDO = mix(base_color.rgb, line_color.rgb,
		clamp(lines, 0.0, 1.0) * line_opacity);
	METALLIC = metallic_amount;
	ROUGHNESS = roughness_amount;
}
