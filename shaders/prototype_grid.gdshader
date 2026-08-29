shader_type spatial;

// Prototype grid: a world-space ruler you can build against.
//
// THE POINT IS THE SCALE, not the look. Lines are locked to world coordinates
// and one cell is one metre, so a wall pulled to four cells is four metres and
// a gap two cells wide is two metres. Nothing is read off UVs -- an unwrapped
// box and a CSG offcut both come out measuring correctly, which is the whole
// reason this exists rather than a texture. Stretch a textured box and its
// ruler stretches with it; stretch this one and the cells stay square.
//
// TRIPLANAR, so a wall is as measurable as a floor. Each axis is projected
// separately and blended by the normal, the same construction acrylic.gdshader
// uses.
//
// LINES ARE WIDENED TO STAY VISIBLE AT DISTANCE. A fixed-width line thinner
// than a pixel does not fade, it ALIASES -- the far half of a big floor turns
// into crawling moire, which is exactly what makes a dense grid unpleasant to
// stand on. fwidth() gives the size of one pixel in world units at this
// fragment, so the line is never asked to be thinner than it can be drawn, and
// the grid dissolves into flat colour in the distance instead of shimmering.

uniform vec4 base_color : source_color = vec4(0.26, 0.27, 0.29, 1.0);
uniform vec4 line_color : source_color = vec4(0.46, 0.48, 0.52, 1.0);
uniform vec4 major_color : source_color = vec4(0.62, 0.66, 0.72, 1.0);
// One cell, in METRES. Changing this changes what the ruler counts in.
uniform float cell_size = 1.0;
// How many cells between heavy lines. Five is the usual choice: a run of cells
// is countable at a glance without labelling anything.
uniform float major_every = 5.0;
// Line thickness as a fraction of a cell, before the distance floor below.
uniform float line_width : hint_range(0.002, 0.2) = 0.02;
uniform float metallic_amount : hint_range(0.0, 1.0) = 0.0;
uniform float roughness_amount : hint_range(0.0, 1.0) = 0.85;
uniform float projection_sharpness : hint_range(1.0, 16.0) = 6.0;

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// How strongly a line falls on this point, for one 2D slice of the world.
//
// Returns 0 inside a cell and 1 on a line. `period` is the spacing being
// drawn; the same function draws the fine grid and the heavy one.
float grid_line(vec2 p, float period, float width) {
	// Distance to the nearest line, in cells, on each axis.
	vec2 cell = abs(fract(p / period - 0.5) - 0.5) * period;
	// One pixel, measured in world units, on each axis.
	vec2 pixel = fwidth(p);
	// The line is `width` wide or one pixel, whichever is more -- see the note
	// on aliasing above.
	vec2 half_width = max(vec2(width * 0.5), pixel);
	vec2 line = 1.0 - smoothstep(half_width - pixel, half_width + pixel, cell);
	return max(line.x, line.y);
}

float grid_at(vec2 p, out float major) {
	float minor = grid_line(p, cell_size, cell_size * line_width);
	major = grid_line(p, cell_size * major_every, cell_size * line_width * 2.0);
	return minor;
}

void fragment() {
	vec3 weights = pow(abs(world_normal), vec3(projection_sharpness));
	weights /= max(weights.x + weights.y + weights.z, 0.0001);

	float major_x;
	float major_y;
	float major_z;
	float minor = grid_at(world_position.zy, major_x) * weights.x
		+ grid_at(world_position.xz, major_y) * weights.y
		+ grid_at(world_position.xy, major_z) * weights.z;
	float major = major_x * weights.x + major_y * weights.y + major_z * weights.z;

	vec3 albedo = mix(base_color.rgb, line_color.rgb, clamp(minor, 0.0, 1.0));
	albedo = mix(albedo, major_color.rgb, clamp(major, 0.0, 1.0));

	ALBEDO = albedo;
	METALLIC = metallic_amount;
	ROUGHNESS = roughness_amount;
}
