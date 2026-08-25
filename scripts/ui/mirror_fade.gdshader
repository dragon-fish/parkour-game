shader_type canvas_item;

// The floor reflection's haze: strongest right at the fold (top of this
// rect, since the source is flipped) and gone by the bottom, with a touch
// of horizontal blur-less softening via alpha only -- the style rule says
// no blur, and a fading alpha ramp reads as polish on white anyway.

uniform float strength : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	c.a *= (1.0 - UV.y) * (1.0 - UV.y) * strength;
	COLOR = c;
}
