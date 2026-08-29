shader_type canvas_item;

// Powder on a driven plate: the main menu's background field, above the
// horizon and behind everything else.
//
// A CHLADNI FIGURE is what sand does on a plate being made to resonate. It
// gets bounced off wherever the plate is moving and can only settle where the
// plate is still, so it collects on the NODAL LINES -- the places where the
// standing wave crosses zero. Change the driving frequency and a different
// mode takes over, and the powder reorganises into another pattern.
//
// For a square plate the modes have a closed form, which is the whole reason
// this is affordable as a fragment shader:
//
//     f(x, y) = cos(n*PI*x) * cos(m*PI*y) - cos(m*PI*x) * cos(n*PI*y)
//
// The figure is where f = 0. Two integers pick the mode; everything else here
// is presentation.
//
// PARTICLES, NOT LINES. Drawing |f| < eps directly gives clean curves, which
// is a diagram rather than powder. Instead a hash-seeded grain per cell is
// shown according to how close its own cell sits to a nodal line, so the
// figure is made of countable specks that thin out as they leave the line --
// which is what the real thing looks like, because the settling is a
// tendency and not a rule.

uniform float mode_n : hint_range(1.0, 12.0) = 3.0;
uniform float mode_m : hint_range(1.0, 12.0) = 5.0;
// How wide a band around the nodal line still holds grains. Widening it is
// what a plate driven harder actually does -- the powder cannot settle as
// tightly -- so this is where loudness goes.
uniform float settle : hint_range(0.01, 1.0) = 0.18;
// How far a grain is thrown from its cell, which is the plate shaking.
uniform float agitation : hint_range(0.0, 1.0) = 0.0;
// Grains per plate unit. In PLATE space, not screen space, so it has to
// rise as `zoom` falls or a blown-up detail is drawn with blown-up specks.
uniform float grain_density : hint_range(4.0, 800.0) = 260.0;
uniform float grain_size : hint_range(0.01, 0.5) = 0.16;
uniform float brightness : hint_range(0.0, 1.0) = 0.5;
// The rect is wide and the plate is square: without this the figure is
// stretched and stops being symmetric, which is the one thing it is for.
uniform float aspect : hint_range(0.1, 8.0) = 1.777;
// Where the plate is centred across the rect, 0 to 1. The figure is
// symmetric about its own centre, so leaving this at 0.5 puts the symmetry
// somewhere the composition does not have anything -- the character stands
// left of centre, and the picture reads as two things that disagree.
uniform float centre_x : hint_range(0.0, 1.0) = 0.5;
// How much of the plate the rect shows, in plate units across its height.
// Below one this is a DETAIL of the figure blown up, which is what reads as
// one large form rather than as wallpaper: at one the rect holds several
// periods side by side and the eye stops seeing a figure and starts seeing a
// repeat.
uniform float zoom : hint_range(0.05, 4.0) = 0.6;
// Which point of the plate sits at the middle of the rect.
//
// WHOLE NUMBERS ONLY, and it must JUMP rather than slide. cos is even, so the
// field is mirror-symmetric about any point where both cos(n*PI*x) and
// cos(m*PI*x) are even -- which for whole n and m is every integer, and while
// sliding between two of them is nothing at all. The figure is symmetric at
// every instant or it is not symmetric.
uniform vec2 centre = vec2(0.0);
// How far past the settling band grains keep appearing, thinning out. A hard
// edge makes the figure a solid shape with a boundary, which at this size
// reads as a stain rather than as powder.
uniform float spread : hint_range(0.0, 2.0) = 0.5;
// Fades the field out toward the horizon, so it sits in the picture rather
// than ending on a line.
uniform float horizon_fade : hint_range(0.0, 1.0) = 0.35;
uniform vec4 tint : source_color = vec4(0.34, 0.41, 0.52, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

// The plate's displacement at a point, normalised to roughly -1..1.
float plate(vec2 p, float n, float m) {
	return (cos(n * PI * p.x) * cos(m * PI * p.y)
		- cos(m * PI * p.x) * cos(n * PI * p.y)) * 0.5;
}

void fragment() {
	// Plate coordinates: a window of size `zoom` around `centre`, hung off
	// centre_x rather than off the middle of the rect, with the wide axis
	// corrected so the figure is not stretched out of its own symmetry.
	//
	// The sampling is symmetric about (centre_x, 0.5) by construction, which
	// is what makes the figure symmetric on screen -- see `centre`.
	vec2 plate_uv = centre
		+ (UV - vec2(centre_x, 0.5)) * vec2(aspect, 1.0) * zoom;

	vec2 grid = plate_uv * grain_density;
	vec2 cell = floor(grid);
	vec2 local = fract(grid) - 0.5;

	// Each grain sits somewhere of its own inside its cell, and is thrown
	// about from there. Two hashes so the throw is not diagonal.
	vec2 seed = vec2(hash(cell), hash(cell + 17.3));
	vec2 offset = (seed - 0.5) * 0.7;
	float wobble = hash(cell + 91.7) * TAU;
	offset += agitation * 0.45 * vec2(sin(TIME * 9.0 + wobble), cos(TIME * 7.3 + wobble));

	float dist = length(local - offset);
	float grain = 1.0 - smoothstep(grain_size, grain_size + 0.10, dist);

	// How well this grain's own place holds it: right on the line, entirely;
	// well past the band, hardly at all.
	//
	// A LONG TAIL RATHER THAN AN EDGE. smoothstep to zero draws the figure as
	// a solid shape with a boundary, which at this size reads as a stain --
	// and a dense one is unfriendly to look at. Powder is dense on the line
	// and keeps going, thinning, for some way either side, so the falloff
	// runs past `settle` and decays instead of ending.
	vec2 at = (cell + 0.5 + offset) / grain_density;
	float away = abs(plate(at, mode_n, mode_m)) / max(settle, 0.001);
	float settled = 1.0 / (1.0 + away * away / max(spread, 0.001));

	// A few grains never settle. Without them the empty regions are empty in
	// a way that reads as a mask rather than as powder.
	float strays = 0.07 * step(0.955, hash(cell + 5.1));

	float alpha = grain * clamp(settled + strays, 0.0, 1.0) * brightness;
	alpha *= smoothstep(0.0, horizon_fade, 1.0 - UV.y);
	COLOR = vec4(tint.rgb, tint.a * alpha);
}
