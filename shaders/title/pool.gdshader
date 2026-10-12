shader_type spatial;
// Radial additive glow lying on the ground where the pillar of light lands.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 color : source_color = vec4(1.0, 0.8, 0.45, 1.0);
uniform float intensity = 1.0;
void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float a = pow(max(1.0 - r, 0.0), 2.6);
	ALBEDO = color.rgb * intensity;
	ALPHA = a * (0.88 + 0.12 * sin(TIME * 0.6));
}
