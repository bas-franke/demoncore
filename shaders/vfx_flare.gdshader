shader_type spatial;
// Impact flare: a camera-facing star of light (soft core + thin cross rays) that blooms and
// collapses in a few frames. Driven per instance by `progress` (0 -> 1) on pooled quads.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, depth_test_disabled;

#include "res://shaders/vfx_common.gdshaderinc"

instance uniform float progress = 1.0;
instance uniform vec4 tint : source_color = vec4(1.0, 0.85, 0.5, 1.0);
instance uniform float energy = 3.0;
instance uniform float roll = 0.0;

void vertex() {
	MODELVIEW_MATRIX = vfx_billboard(MODEL_MATRIX, VIEW_MATRIX, INV_VIEW_MATRIX, roll);
}

void fragment() {
	float p = clamp(progress, 0.0, 1.0);
	vec2 c = UV * 2.0 - 1.0;
	float r = length(c);
	// Swell in the first 20 %, then collapse.
	float grow = smoothstep(0.0, 0.2, p);
	float fade = 1.0 - smoothstep(0.15, 1.0, p);
	float s = mix(0.35, 1.0, grow);
	vec2 q = c / s;
	float core = exp(-dot(q, q) * 26.0);
	float halo = exp(-dot(q, q) * 6.0) * 0.18;
	float rays = exp(-abs(q.y) * 38.0) * max(1.0 - abs(q.x), 0.0)
		+ exp(-abs(q.x) * 38.0) * max(1.0 - abs(q.y), 0.0) * 0.7;
	float a = (core + halo + rays * 0.8) * fade * (1.0 - smoothstep(0.85, 1.0, r));
	vec3 col = mix(tint.rgb, vec3(1.0, 0.98, 0.92), core);
	ALBEDO = col * energy * a;
	ALPHA = 1.0;
}
