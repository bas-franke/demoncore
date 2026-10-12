shader_type spatial;
// Player "presence" brand on the ground under the demon (characters-polish): a faint ring of
// slowly turning rune dashes around a soft ember glow, so the player can find themselves in a
// horde. Additive and unshaded; draw on a flat PlaneMesh at the feet. `color` follows the skin.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.36, 0.08, 1.0);
uniform float energy = 1.0;
// Ring radius and width in UV units (the plane spans -0.5..0.5).
uniform float ring_radius = 0.42;
uniform float ring_width = 0.025;
uniform float dash_count = 18.0;
uniform float spin = 0.25;
// 0..1 brightening (hits), set from script.
uniform float pulse = 0.0;

void fragment() {
	vec2 p = UV - 0.5;
	float r = length(p);
	float a = atan(p.y, p.x);
	// Ring of dashes turning slowly.
	float d = abs(r - ring_radius);
	float ring = 1.0 - smoothstep(ring_width * 0.4, ring_width, d);
	float dash = smoothstep(0.15, 0.3, abs(fract(a / 6.2831853 * dash_count + TIME * spin) - 0.5));
	// Thin inner hairline (unbroken) for structure.
	float inner = 1.0 - smoothstep(0.002, 0.007, abs(r - ring_radius * 0.82));
	// Soft glow pooled under the feet, fading out well before the ring.
	float pool = pow(1.0 - smoothstep(0.0, ring_radius * 0.9, r), 2.0);
	float breathe = 0.85 + 0.15 * sin(TIME * 2.1);
	float v = ring * dash * 0.6 + inner * 0.25 + pool * 0.2 * breathe;
	v *= 1.0 + pulse * 2.5;
	ALBEDO = color.rgb * v * energy;
	ALPHA = clamp(v, 0.0, 1.0);
}
