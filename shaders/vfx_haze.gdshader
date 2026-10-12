shader_type spatial;
// Heat haze: refracts the screen behind it. `billboard` = camera-facing shimmer puff (big hellfire
// hits); otherwise a flat expanding shockwave ring (PlaneMesh 2 x 2, radius 1) on the ground.
// Driven per instance by `progress`. Costs one screen copy per frame while any instance is visible.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

#include "res://shaders/vfx_common.gdshaderinc"

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform bool billboard = false;
uniform float strength = 0.02;

instance uniform float progress = 1.0;
instance uniform float power = 1.0;

void vertex() {
	if (billboard) {
		MODELVIEW_MATRIX = vfx_billboard(MODEL_MATRIX, VIEW_MATRIX, INV_VIEW_MATRIX, 0.0);
	}
}

void fragment() {
	float p = clamp(progress, 0.0, 1.0);
	vec2 c = UV * 2.0 - 1.0;
	float r = length(c);
	vec2 dir = c / max(r, 1e-3);
	float profile;
	if (billboard) {
		profile = pow(clamp(1.0 - r, 0.0, 1.0), 1.5) * smoothstep(0.0, 0.15, p);
	} else {
		float ring_r = (1.0 - pow(1.0 - p, 2.5)) * 0.92;
		profile = exp(-pow((r - ring_r) / (0.05 + 0.06 * p), 2.0));
	}
	float fade = 1.0 - smoothstep(0.35, 1.0, p);
	float wob = vfx_noise(UV * 9.0 + vec2(TIME * 3.0, -TIME * 4.0)) - 0.5;
	vec2 off = (dir * (billboard ? wob * 1.6 : 1.0 + wob) + vec2(wob, -wob) * 0.6) * profile * fade * strength * power;
	ALBEDO = textureLod(screen_tex, SCREEN_UV + off, 0.0).rgb;
	ALPHA = clamp(profile * fade * 3.0, 0.0, 1.0) * (1.0 - smoothstep(0.92, 1.0, r));
}
