shader_type spatial;
// Claw-mark slash. Mesh UVs: x = 0..1 along the arc, y = 0..1 across the stroke.
// `sweep` reveals the stroke along the arc (0 -> hidden, >1 -> fully drawn); `fade` is overall alpha.
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 core_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 edge_color : source_color = vec4(1.0, 0.55, 0.72, 1.0);
instance uniform float fade = 1.0;
instance uniform float sweep = 1.0;

void fragment() {
	float across = abs(UV.y * 2.0 - 1.0);
	float aa = fwidth(across) * 1.5;
	vec3 col = mix(core_color.rgb, edge_color.rgb, smoothstep(0.1, 0.7, across));
	float reveal = 1.0 - smoothstep(sweep - 0.12, sweep, UV.x);
	float edge = 1.0 - smoothstep(1.0 - aa, 1.0, across);
	ALBEDO = col;
	ALPHA = clamp(fade * reveal * edge * core_color.a, 0.0, 1.0);
}
