shader_type spatial;

// Prototype grid: a world-space ruler you can build against, in the game's
// own white.
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
// into crawling moire, which is what makes a dense grid unpleasant to stand
// on. fwidth() gives the size of one pixel in world units at this fragment, so
// a line is never asked to be thinner than it can be drawn, and the grid
// dissolves into flat colour in the distance instead of shimmering.
//
// THE MARKS ARE THE REASON TO USE THIS OVER GRAPH PAPER. Counting cells tells
// you a wall is 1.8 m; it does not tell you 1.8 m is the lowest wall the hands
// can catch. Each height below is a threshold the movement code actually
// tests, so a blockout can be built against what the body can do rather than
// against round numbers. Set one to 0.0 to switch it off.
//
// DO NOT hand-edit these to "nicer" values. They are the config's, and a mark
// that disagrees with the config is worse than no mark -- it certifies a wall
// the body cannot climb. See the per-mark note for where each is read from.

// -- Surface ---------------------------------------------------------------

// White, but NOT near-white, and the difference is the whole readability of
// this surface. Levels light themselves with a strongly blue ambient
// (Arena.COLD_AMBIENT_TINT, and the templates' own Environment), which lands
// on top of albedo: at 0.93 every face of every box saturates to the same pale
// blue, a wall becomes indistinguishable from the floor it stands on, and the
// marks wash out to pink. Held down here, the ambient has somewhere to go and
// lit and unlit faces separate again.
//
// DO NOT raise this to match the game's own surfaces. This is a ruler, and it
// is read under whatever light the level happens to have.
uniform vec4 base_color : source_color = vec4(0.80, 0.82, 0.85, 1.0);
uniform vec4 line_color : source_color = vec4(0.55, 0.58, 0.63, 1.0);
uniform vec4 major_color : source_color = vec4(0.38, 0.41, 0.46, 1.0);
// The one saturated colour in the picture, and it is spent on the thresholds.
uniform vec4 mark_color : source_color = vec4(0.76, 0.13, 0.10, 1.0);

// FLAT AND MATTE ON PURPOSE. Any metallic at all makes the surface mirror the
// sky through SSR, which in a blue-lit level tints the whole grid blue on top
// of the ambient already doing it. A ruler reflects nothing.
uniform float metallic_amount : hint_range(0.0, 1.0) = 0.0;
uniform float roughness_amount : hint_range(0.0, 1.0) = 0.9;
uniform float projection_sharpness : hint_range(1.0, 16.0) = 6.0;

// -- Grid ------------------------------------------------------------------

// One cell, in METRES. This is what the ruler counts in.
uniform float cell_size = 1.0;
// Cells between heavy lines. Five makes a run countable at a glance.
uniform float major_every = 5.0;
uniform float line_width : hint_range(0.001, 0.2) = 0.012;
// Marks are drawn NO HEAVIER than the grid they annotate. They are read by
// where they sit, not by how loud they are, and three of the heights fall
// within 25 cm of each other -- at any real thickness those merge into one
// red band and stop being three separate answers.
uniform float mark_width : hint_range(0.001, 0.2) = 0.012;
// How far a mark is allowed to take over the surface. Short of 1 the colour
// stays a tint on the grid rather than a stripe painted over it.
uniform float mark_strength : hint_range(0.0, 1.0) = 0.85;

// -- Heights the body actually cares about ---------------------------------
// Drawn on VERTICAL faces, where a height is hard to judge by eye. Every one
// is a number from the movement config, listed with where to re-read it.

// PawnConfig.max_step_height. Below this the body walks up without being asked.
uniform float mark_step = 0.35;
// Apex of a standing jump: base_jump_z^2 / (2 * gravity) = 6.3^2 / 32.
// [ME:DERIVED] from two [ME:CONFIRMED] values. Feet reach here, hands higher.
uniform float mark_jump = 1.24;
// SpeedVaultConfig.vault_reach.
uniform float mark_vault = 1.4;
// WallClimbConfig.climb_height_running -- what a run-up carries the body up.
uniform float mark_climb = 1.47;
// GrabConfig.min_wall_height. Under this the hands find nothing to catch.
uniform float mark_grab_low = 1.8;
// GrabConfig.ledge_max_height. Above this the ledge is out of reach.
uniform float mark_grab_high = 2.8;

// -- Distance the body actually covers -------------------------------------

// Drawn on HORIZONTAL faces, spaced from the world origin, so a gap can be
// checked against the jump that has to clear it.
//
// A full-speed running jump: (ground_speed + jump_add_xy) * 2 * base_jump_z /
// gravity = 8.2 * 0.7875 s. [ME:DERIVED], and the airborne half is unverified
// -- air control and drag are not in it. Treat it as the optimistic bound and
// measure a real jump against it before trusting a gap built to the line.
uniform float mark_run_jump = 6.46;

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// How strongly a line falls on this point, for one 2D slice of the world.
// 0 inside a cell, 1 on a line.
float grid_line(vec2 p, float period, float width) {
	vec2 cell = abs(fract(p / period - 0.5) - 0.5) * period;
	vec2 pixel = fwidth(p);
	vec2 half_width = max(vec2(width * 0.5), pixel);
	vec2 line = 1.0 - smoothstep(half_width - pixel, half_width + pixel, cell);
	return max(line.x, line.y);
}

// The same, for a single value rather than a plane: one line at one height.
float line_at(float value, float target, float width) {
	if (target <= 0.0) {
		return 0.0;
	}
	float pixel = fwidth(value);
	float half_width = max(width * 0.5, pixel);
	return 1.0 - smoothstep(half_width - pixel, half_width + pixel,
		abs(value - target));
}

// Evenly spaced lines through the origin, for a distance that repeats.
float spacing_at(vec2 p, float period, float width) {
	if (period <= 0.0) {
		return 0.0;
	}
	return grid_line(p, period, width);
}

void fragment() {
	vec3 weights = pow(abs(world_normal), vec3(projection_sharpness));
	weights /= max(weights.x + weights.y + weights.z, 0.0001);

	float minor = grid_line(world_position.zy, cell_size, cell_size * line_width) * weights.x
		+ grid_line(world_position.xz, cell_size, cell_size * line_width) * weights.y
		+ grid_line(world_position.xy, cell_size, cell_size * line_width) * weights.z;

	float major_period = cell_size * major_every;
	float major_w = cell_size * line_width * 2.0;
	float major = grid_line(world_position.zy, major_period, major_w) * weights.x
		+ grid_line(world_position.xz, major_period, major_w) * weights.y
		+ grid_line(world_position.xy, major_period, major_w) * weights.z;

	// Height marks belong on what a body would climb, distance marks on what
	// it would run across, so each is weighted by how vertical the face is.
	float upright = 1.0 - weights.y;
	float heights = max(max(
		max(line_at(world_position.y, mark_step, mark_width),
			line_at(world_position.y, mark_jump, mark_width)),
		max(line_at(world_position.y, mark_vault, mark_width),
			line_at(world_position.y, mark_climb, mark_width))),
		max(line_at(world_position.y, mark_grab_low, mark_width),
			line_at(world_position.y, mark_grab_high, mark_width))) * upright;
	// WIDTH IN METRES, NOT IN PERIODS. Scaling it by the spacing made the
	// 6.46 m line six times heavier than the 1 m grid, so the one mark meant
	// to sit quietly under a gap was the loudest thing on the floor.
	float distances = spacing_at(world_position.xz, mark_run_jump,
		cell_size * mark_width) * weights.y;

	vec3 albedo = mix(base_color.rgb, line_color.rgb, clamp(minor, 0.0, 1.0));
	albedo = mix(albedo, major_color.rgb, clamp(major, 0.0, 1.0));
	albedo = mix(albedo, mark_color.rgb,
		clamp(max(heights, distances), 0.0, 1.0) * mark_strength);

	ALBEDO = albedo;
	METALLIC = metallic_amount;
	ROUGHNESS = roughness_amount;
}
