shader_type spatial;
// Billowing mist puff (blood mist): camera-facing, soft-edged and noise-torn, alpha blended (not
// additive, so it reads as a dark wet spray rather than light). Soft-particle fade against the
// ground. COLOR from the color ramp; a faint self-glow keeps it readable in shadow.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

#include "res://shaders/vfx_common.gdshaderinc"

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform float glow = 0.15;
uniform float density = 0.7;

varying float seed;
varying float age;

void vertex() {
	seed = float(INSTANCE_ID) * 1.618;
	age = INSTANCE_CUSTOM.y;
	MODELVIEW_MATRIX = vfx_billboard(MODEL_MATRIX, VIEW_MATRIX, INV_VIEW_MATRIX, seed * 2.4);
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float r = length(c);
	vec2 p = UV * 2.6 + vec2(seed * 3.1, seed * 1.7) + vec2(0.0, age * 0.8);
	float n = vfx_fbm(p);
	// The puff frays as it ages.
	float edge = mix(0.95, 0.55, age);
	float shape = 1.0 - smoothstep(edge * (0.55 + 0.45 * n), edge * (0.75 + 0.35 * n) + 0.1, r);
	float wisps = smoothstep(0.25 + age * 0.35, 0.75, n);
	float a = shape * mix(1.0, wisps, 0.55) * density;
	float soft = vfx_soft(depth_tex, SCREEN_UV, INV_PROJECTION_MATRIX, VERTEX, 0.35);
	vec3 col = COLOR.rgb * (0.75 + 0.5 * n);
	ALBEDO = col * (1.0 + glow * (1.0 - r));
	ALPHA = clamp(a * COLOR.a * soft, 0.0, 1.0);
}
