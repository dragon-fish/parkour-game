shader_type canvas_item;

// The main menu's ground: a dot grid lying on an actual plane, drawn on a
// ColorRect that covers the bottom half of the screen.
//
// A REAL PLANE, SOLVED PER PIXEL, not a fake. The first version divided by
// UV.y for a cheap "1/y" recession, which looks like ground until the camera
// moves: it knows nothing about how high the camera is, how far away it is,
// or which way it is pointing, so during the entrance orbit the pattern turns
// about the middle of the screen while the character's feet swing about her
// own position, and the two visibly disagree. Every pixel here instead
// unprojects into the world and asks what is under it, which is the same
// answer a plane in the 3D scene would give.
//
// WHY NOT AN ACTUAL PLANE IN THE VIEWPORT: the mirror reuses the viewport's
// texture as its reflection, so a floor inside it would come back flipped as
// well -- ground reflected in ground. Doing the projection here keeps the
// layer order, the fade-in and the mirror's framing untouched.
//
// THE HORIZON IS THE RECT'S TOP EDGE, exactly. A camera with no pitch puts
// the horizon at the middle of the frame whatever its height, and this rect
// starts there, so UV.y = 0 is infinitely far away and UV.y = 1 is the bottom
// of the screen.
//
// PER-CELL RANDOM PULSE: each cell gets a fixed hash-derived phase offset so
// dots pulse independently instead of in lockstep. That randomness is what
// reads as alive rather than as blinking, and it survives from the first
// version unchanged -- it was the one part that was right.

// The camera, as the 3D scene actually has it.
uniform float eye_height = 0.8;
uniform float cam_yaw = 0.0;
uniform vec2 cam_pos = vec2(0.0);
// Half-FOV tangents. Vertical comes from the camera's own fov; horizontal is
// that times the viewport's aspect, which is how Godot widens a KEEP_HEIGHT
// camera.
uniform float tan_v = 0.52;
uniform float tan_h = 0.92;

// Cells per WORLD METRE now, not per unit of the old fake's own space, so
// the old number could not be carried over and this one was solved instead.
//
// At the settled camera -- 0.795 m up, 55 degrees vertical -- a pixel at
// screen depth v sits 1.527/v metres out, so matching the old spacing along
// the DEPTH axis wants 9.2 cells per metre and matching it ACROSS wants 5.0.
// They disagree because the old projection was not a plane: it scaled its two
// axes differently, and its cells were stretched. This is the geometric mean
// of the two, which is as close as one number gets to a shape that never had
// a single scale.
uniform float spacing : hint_range(0.1, 24.0) = 6.8;
uniform float dot_size : hint_range(0.01, 0.5) = 0.12;
uniform float flow_phase = 0.0;
// The direction she walks, in world XZ, handed over rather than assumed.
// Which axis is "forward" is a convention argument nobody wins twice, and
// getting it backwards makes her moonwalk -- so it is read off the body's own
// transform instead of written down here.
uniform vec2 flow_dir = vec2(0.0, 1.0);
uniform float speed : hint_range(0.0, 8.0) = 1.2;
uniform float pulse : hint_range(0.0, 1.0) = 0.35;
uniform float base : hint_range(0.0, 1.0) = 0.35;
// How far out the ground fades to nothing. Without it the cells near the
// horizon are finer than a pixel and boil.
uniform float fade_from : hint_range(1.0, 200.0) = 6.0;
uniform float fade_to : hint_range(1.0, 400.0) = 26.0;
uniform vec4 tint : source_color = vec4(0.75, 0.82, 0.92, 1.0);

// Classic cheap 2D hash: no textures, deterministic per grid cell.
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void fragment() {
	// Screen NDC for this pixel. The rect is the bottom half, so its UV.y
	// runs from the horizon (0) to the bottom of the screen (1), which is
	// NDC y from 0 down to -1.
	float sx = (UV.x - 0.5) * 2.0;
	float sy = -UV.y;

	// The view ray in camera space, and where it meets y = 0. A level camera
	// looks along -Z, so the hit's forward distance is -hit.z.
	vec3 dir = vec3(sx * tan_h, sy * tan_v, -1.0);
	float t = eye_height / max(-dir.y, 0.0001);
	vec3 hit = dir * t;
	float distance_out = -hit.z;

	// Camera space to world: rotate about Y by the camera's yaw, then offset
	// by where the camera stands.
	float c = cos(cam_yaw);
	float s = sin(cam_yaw);
	vec2 ground = cam_pos + vec2(hit.x * c + hit.z * s, -hit.x * s + hit.z * c);

	// WALKING FORWARD MOVES THE GROUND BACKWARDS, which is why this adds. She
	// stands still and the world slides: a patch of ground under her feet has
	// to end up behind her, so the point being sampled travels FORWARD along
	// her facing as the phase grows.
	ground += flow_dir * flow_phase;

	vec2 grid = ground * spacing;
	vec2 cell = floor(grid);
	vec2 local = fract(grid) - 0.5;
	float dot_mask = 1.0 - smoothstep(dot_size, dot_size + 0.04, length(local));

	float phase = hash(cell) * TAU;
	float brightness = clamp(base + pulse * sin(TIME * speed + phase), 0.0, 1.0);

	// Two fades: distance, and the last sliver above the horizon where t
	// runs away to infinity and the grid is finer than the screen.
	float far = 1.0 - smoothstep(fade_from, fade_to, distance_out);
	float horizon = smoothstep(0.0, 0.03, UV.y);

	COLOR = vec4(tint.rgb, tint.a * dot_mask * brightness * far * horizon);
}
