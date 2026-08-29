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
// ONE THRESHOLD LINE, and only the one that can honestly be drawn.
//
// An earlier version ruled six heights on every wall -- step, vault, climb,
// the two grab bounds -- and every one of them was a lie in the general case.
// GrabConfig measures ledge_max_height FROM THE FEET, so where the hands can
// reach depends on where the feet are at the time: standing, 2.8 m; at the
// apex of a jump, 1.24 + 2.8. A line drawn at 2.8 forbids walls the body
// clears easily, which is the worst thing a guide can do.
//
// The CEILING survives that argument where the others do not. 4.04 m is the
// reach at the apex of the best jump available, so above it there is nothing
// to be done with a wall -- no timing, no run-up, no angle. Nothing below it
// is being promised: a wall under the line may or may not go, and that is
// what a blockout is for finding out. The line only says where trying stops.
//
// It also draws itself only where it matters. A 2 m wall never reaches 4 m, so
// the line appears on tall geometry and nowhere else -- its presence IS the
// warning, rather than a stripe every surface has to carry.
//
// DASHED, so it cannot be mistaken for the metre ruling, and faint, because it
// is a boundary rather than a feature.
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

// -- The reach ceiling -----------------------------------------------------

// Height of the line ABOVE base_y, in metres. Set to 0 to switch it off.
//
// 5.5 m, and getting there takes the whole chain rather than a jump:
//
//   1.24  the jump arc, at the point contact is made with the wall
// + 1.47  WallClimbConfig.climb_height_running, the kick up the wall
//   ----
//   2.71  where the feet are at the top of the climb (measured, SZD)
// + 2.80  GrabConfig.ledge_max_height, reach from the feet
//   ----
//   5.51  rounded down to 5.5
//
// AT FULL SPEED ONLY. climb_height_running is the run_speed_limit end of a
// dial whose other end is climb_height (1.30) for a standing kick, so a wall
// approached from a standstill tops out around 4.1 m. The line is the
// optimistic bound: what a good run-up can still reach, not what any approach
// will.
//
// AN EARLIER VERSION SAID 4.0, which was the jump plus the grab with the climb
// left out entirely -- it drew a ceiling under walls the body climbs routinely.
// If this ever needs re-deriving, the chain is Jump -> Airborne -> WallClimb ->
// Falling -> IntoGrab, and every link contributes height.
uniform float reach_ceiling = 5.5;

// WHERE THE FLOOR UNDER THIS OBJECT IS, in world Y.
//
// PER INSTANCE, because a height is measured from the ground the player stands
// on and a rooftop level stands 60 m up -- a single global value put every line
// in the basement the moment anything was built off the slab. Set it in the
// inspector under Geometry > Instance Shader Parameters, per box, so a wall
// carries its own answer and keeps it when moved.
//
// A SHADER CANNOT WORK THIS OUT ITSELF. Fragments know their own world
// position and nothing about the object they belong to: there is no bounding
// box, no object height, no "bottom" to read. NODE_POSITION_WORLD gives the
// ORIGIN, which for a CSGBox3D is its centre, so deriving the base from it
// still needs the height nobody has. Hence a declared value.
//
// ON A CSG TREE, SET IT ON THE ROOT. A CSGCombiner3D merges its children into
// one mesh and only the root remains a GeometryInstance3D, so a parameter set
// on a child inside a combiner is silently ignored.
instance uniform float base_y = 0.0;
uniform vec4 reach_color : source_color = vec4(0.78, 0.16, 0.13, 1.0);
uniform float reach_opacity : hint_range(0.0, 1.0) = 0.22;
uniform float reach_width = 0.03;
// Dash length plus gap, in metres, and how much of it is drawn.
uniform float dash_period = 0.6;
uniform float dash_duty : hint_range(0.05, 0.95) = 0.5;

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

// One line at one height, antialiased the same way the grid is.
float line_at(float value, float target, float width) {
	float pixel = fwidth(value);
	float half_width = max(width * 0.5, pixel);
	return 1.0 - smoothstep(half_width - pixel, half_width + pixel,
		abs(value - target));
}

// The on/off of a dash, along whichever axis runs across the face.
float dash_mask(float along) {
	float pixel = fwidth(along);
	float phase = fract(along / max(dash_period, 0.001));
	// Softened by a pixel so the dash ends do not crawl at grazing angles.
	float edge = max(pixel / max(dash_period, 0.001), 0.001);
	return 1.0 - smoothstep(dash_duty - edge, dash_duty + edge, phase);
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

	vec3 albedo = mix(base_color.rgb, line_color.rgb,
		clamp(lines, 0.0, 1.0) * line_opacity);

	// Upright faces only: a ceiling on reach says nothing about a floor, and
	// drawn on one it would be a stripe across open ground at a height the
	// ground does not have.
	if (reach_ceiling > 0.0) {
		float at_height = line_at(world_position.y - base_y,
			reach_ceiling, reach_width);
		// The axis that runs ACROSS the face, so the dashes march along the
		// line rather than chopping it where two projections meet.
		float dashes = dash_mask(world_position.z) * weights.x
			+ dash_mask(world_position.x) * weights.z;
		albedo = mix(albedo, reach_color.rgb,
			clamp(at_height * dashes, 0.0, 1.0) * reach_opacity);
	}

	ALBEDO = albedo;
	METALLIC = metallic_amount;
	ROUGHNESS = roughness_amount;
}
