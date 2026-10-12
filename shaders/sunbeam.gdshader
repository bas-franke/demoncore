shader_type spatial;
// Holy light shaft from the heavens: an additive, axially-billboarded quad (long axis = sun
// direction, set by atmosphere.gd). UV.y = 0 at the sky end, 1 where it meets the ground. Soft at the
// sides and top, a brighter pool where it touches the ground, soft intersection with geometry, and
// slow drifting dust streaks inside.
render_mode unshaded, blend_add, depth_draw_never, depth_test_default, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.8, 0.46, 1.0);
uniform float intensity = 0.32;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
instance uniform float fade = 1.0;
instance uniform float seed = 0.0;

void fragment() {
	float x = UV.x * 2.0 - 1.0;
	float across = 1.0 - x * x;
	across = across * across * across;
	float along = smoothstep(0.0, 0.6, UV.y) * (1.0 - smoothstep(0.9, 1.0, UV.y));
	// brighter toward the ground
	along *= 0.55 + 0.45 * UV.y;
	float streak = 0.6 + 0.4 * sin(UV.x * 19.0 + seed * 7.0 + TIME * 0.25)
			* sin(UV.x * 6.0 - seed * 3.0 - TIME * 0.17);
	// motes drifting down the shaft
	float drift = 0.85 + 0.15 * sin(UV.y * 40.0 - TIME * 1.3 + UV.x * 9.0 + seed);
	float d = texture(depth_texture, SCREEN_UV).r;
	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	float scene_depth = -v.z / v.w;
	float soft = clamp((scene_depth + VERTEX.z) / 3.0, 0.0, 1.0);
	ALBEDO = color.rgb * intensity;
	ALPHA = clamp(across * along * streak * drift * soft * fade, 0.0, 1.0);
}
