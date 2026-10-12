shader_type spatial;
// Drifting bank of ground mist: a wide vertical quad with scrolling fbm, soft against the ground.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 color : source_color = vec4(0.45, 0.4, 0.35, 1.0);
uniform float opacity = 0.35;
uniform float soft_depth = 10.0;
uniform float near_fade = 12.0;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
instance uniform float seed = 0.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) { s += a * vnoise(p); p *= 2.03; a *= 0.5; }
	return s;
}
void fragment() {
	vec2 p = UV * vec2(7.0, 1.6) + vec2(TIME * 0.02 + seed * 3.1, seed * 1.7);
	float n = fbm(p + vec2(fbm(p * 0.6 + vec2(0.0, TIME * 0.015)) * 1.5, 0.0));
	n = smoothstep(0.25, 0.85, n);
	float prof = smoothstep(0.05, 0.75, UV.y) * (1.0 - smoothstep(0.96, 1.0, UV.y));
	float sides = smoothstep(0.0, 0.18, UV.x) * (1.0 - smoothstep(0.82, 1.0, UV.x));
	float d = texture(depth_texture, SCREEN_UV).r;
	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	float scene_z = -v.z / v.w;
	float soft = clamp((scene_z + VERTEX.z) / soft_depth, 0.0, 1.0);
	float nf = smoothstep(2.0, near_fade, -VERTEX.z);
	ALBEDO = color.rgb;
	ALPHA = clamp(opacity * n * prof * sides * soft * nf, 0.0, 1.0);
}
