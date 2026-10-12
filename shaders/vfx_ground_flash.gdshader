shader_type spatial;
// Light branded into the ground where an angel falls (and, much larger, where the Herald does):
// a hot core, an expanding torn ring and faint radial rays, all burning away to nothing.
// Flat PlaneMesh (2 x 2, radius 1) scaled to the radius; driven per instance by `progress`.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

#include "res://shaders/vfx_common.gdshaderinc"

instance uniform float progress = 1.0;
instance uniform vec4 tint : source_color = vec4(1.0, 0.85, 0.5, 1.0);
instance uniform float energy = 2.0;
instance uniform float seed = 0.0;
// Number of radial rays (0 = none).
uniform float rays = 11.0;

void fragment() {
	float p = clamp(progress, 0.0, 1.0);
	vec2 c = UV * 2.0 - 1.0;
	float r = length(c);
	float ang = atan(c.y, c.x);
	float n = vfx_fbm(c * 3.5 + vec2(seed * 7.3, seed * 3.1));
	float ring_r = (1.0 - pow(1.0 - p, 3.0)) * 0.88;
	float ring_w = 0.035 + 0.09 * p;
	float ring = exp(-pow((r - ring_r) / ring_w, 2.0));
	ring *= smoothstep(0.2, 0.6, n + 0.25) * (1.0 - p);
	float core = pow(clamp(1.0 - r / (0.25 + 0.35 * ring_r), 0.0, 1.0), 2.0) * pow(1.0 - p, 2.5);
	float ray_n = vfx_noise(vec2(ang * rays / 6.2832 * 2.0 + seed * 13.0, 0.5));
	float ray = pow(abs(sin(ang * rays * 0.5 + seed * 5.0 + ray_n * 1.5)), 18.0);
	ray *= smoothstep(1.0, 0.1, r) * smoothstep(0.0, 0.15, r) * pow(1.0 - p, 3.0);
	// burnt, glowing embers left inside the ring for a moment
	float embers = smoothstep(0.72, 0.9, n) * smoothstep(ring_r + 0.05, ring_r - 0.2, r) * (1.0 - p) * 0.6;
	float a = ring * 1.3 + core * 1.1 + ray * 0.6 + embers;
	a *= 1.0 - smoothstep(0.9, 1.0, r);
	vec3 col = mix(tint.rgb, vec3(1.0, 0.97, 0.9), clamp(core, 0.0, 1.0));
	ALBEDO = col * energy * a;
	ALPHA = 1.0;
}
