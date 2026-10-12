shader_type spatial;
// Soft ground aura for a 2x2 PlaneMesh scaled to the aura radius: gentle fill, slow
// outward ripples and a dashed rotating ring at the edge. Everything outside the circle
// is discarded. `radius` keeps the ring width constant in world units.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 fill_color : source_color = vec4(0.58, 0.93, 0.55, 0.16);
uniform vec4 ripple_color : source_color = vec4(0.8, 1.0, 0.72, 0.16);
uniform vec4 ring_color : source_color = vec4(0.42, 0.8, 0.45, 0.85);
// Ring width in world units.
uniform float ring_width = 0.12;
uniform float dash_count = 28.0;
// Ring rotation, in turns per second.
uniform float ring_speed = 0.06;
uniform float ripple_count = 3.0;
uniform float ripple_speed = 0.3;
instance uniform float radius = 2.2;
// 0..1, briefly raised when the aura deals damage.
instance uniform float pulse = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	float aa = fwidth(r) * 1.5;

	// Soft fill, a bit stronger towards the edge.
	float a = fill_color.a * mix(0.45, 1.0, r * r) * (1.0 + pulse * 1.5);
	vec3 col = fill_color.rgb;

	// Slow ripples drifting outward.
	float ripple = pow(0.5 + 0.5 * sin((r * ripple_count - TIME * ripple_speed) * TAU), 6.0);
	ripple *= smoothstep(0.0, 0.25, r) * (1.0 - r * 0.6);
	col = mix(col, ripple_color.rgb, ripple);
	a += ripple * ripple_color.a;

	// Dashed rotating ring.
	float w = ring_width / max(radius, 0.01) * (1.0 + pulse * 0.6);
	float ang = atan(p.y, p.x) / TAU + 0.5;
	float dash = step(0.42, fract((ang + TIME * ring_speed) * dash_count));
	float band = smoothstep(1.0 - w - aa, 1.0 - w, r) * (1.0 - smoothstep(1.0 - aa, 1.0, r));
	float ring = band * dash;
	col = mix(col, ring_color.rgb, ring);
	a = mix(a, ring_color.a, ring);

	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0);
}
