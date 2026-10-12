shader_type spatial;
// Low ground mist: a large horizontal plane hovering just above the ground that follows the player
// (atmosphere.gd stacks 2 of them at different heights). World-space drifting noise, so the mist stays
// put while the plane moves: pools and banks with clear gaps. Soft-faded where it meets geometry (depth
// texture) and toward the plane edges, so no hard intersections. Lit cheaply: cool in shade, warmed
// where the cloud shadows (cloud.gdshaderinc) let the sun through.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

#include "res://shaders/cloud.gdshaderinc"

uniform vec3 shade_color : source_color = vec3(0.42, 0.47, 0.52);
uniform vec3 sun_color : source_color = vec3(0.78, 0.7, 0.58);
uniform float opacity = 0.3;
uniform float scale = 0.05;
uniform vec2 wind = vec2(0.35, 0.15);
uniform float coverage : hint_range(0.0, 1.0) = 0.5;
// Distance (world units) over which the mist fades in front of geometry.
uniform float soft_distance = 1.2;
uniform float seed = 0.0;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear;

varying vec3 world_pos;

float m_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float m_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(m_hash(i), m_hash(i + vec2(1, 0)), u.x), mix(m_hash(i + vec2(0, 1)), m_hash(i + vec2(1, 1)), u.x), u.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz + vec2(seed * 31.0, seed * 17.0);
	vec2 q = (p - wind * TIME) * scale;
	vec2 q2 = (p - wind * TIME * 1.7) * scale * 2.6;
	float n = m_noise(q) * 0.55 + m_noise(q2 + 4.1) * 0.3 + m_noise(q * 6.3 - wind * TIME * 0.2) * 0.15;
	float m = smoothstep(coverage - 0.18, coverage + 0.25, n);
	float d = texture(depth_texture, SCREEN_UV).r;
	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	float scene_depth = -v.z / v.w;
	float soft = clamp((scene_depth + VERTEX.z) / soft_distance, 0.0, 1.0);
	vec2 e = min(UV, 1.0 - UV);
	float edge = smoothstep(0.0, 0.2, e.x) * smoothstep(0.0, 0.2, e.y);
	float sun = (cloud_light(world_pos, TIME) - (1.0 - CLOUD_STRENGTH)) / CLOUD_STRENGTH;
	ALBEDO = mix(shade_color, sun_color, 0.35 + 0.4 * sun);
	ALPHA = m * soft * edge * opacity;
}
