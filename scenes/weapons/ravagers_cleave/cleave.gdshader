shader_type spatial;
// Ravager's Cleave smear. Mesh UVs: x = 0..1 along the arc, y = 0 (inner edge) .. 1 (outer, cutting edge).
// A dark-steel crescent whose cutting edge burns white-hot to hellfire. `sweep` reveals the arc
// (0 hidden, >1 fully drawn) with the leading edge brightest; `fade` is overall opacity.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 steel : source_color = vec4(0.09, 0.08, 0.09, 1.0);
uniform vec3 edge_fire = vec3(2.4, 0.42, 0.07);
uniform vec3 edge_hot = vec3(4.5, 1.7, 0.5);
instance uniform float fade = 1.0;
instance uniform float sweep = 1.0;

void fragment() {
	float across = UV.y;
	float mid = abs(across * 2.0 - 1.0);
	float aa = fwidth(mid) * 1.5;
	float behind = clamp(sweep - UV.x, 0.0, 1.0);
	float reveal = 1.0 - smoothstep(sweep - 0.06, sweep, UV.x);
	float trail = exp(-behind * 2.4);

	vec3 col = mix(steel.rgb, edge_fire, smoothstep(0.5, 0.88, across));
	col = mix(col, edge_hot, smoothstep(0.86, 0.98, across) * (0.5 + 0.5 * trail));
	// Brushed streaks along the swing.
	float streak = 0.75 + 0.25 * sin(UV.x * 110.0 + across * 9.0);
	col *= streak;
	// Leading edge flares.
	col += edge_fire * smoothstep(0.12, 0.0, behind) * 0.8 * smoothstep(0.2, 0.9, across);

	float edge = 1.0 - smoothstep(1.0 - aa, 1.0, mid);
	ALBEDO = col;
	ALPHA = clamp(fade * reveal * edge * mix(0.3, 1.0, trail) * mix(0.7, 1.0, across), 0.0, 1.0);
}
