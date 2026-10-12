shader_type spatial;
// Hot spark / light shard: a thin streak aligned to the particle's velocity (process material
// needs particle_flag_align_y), additive and bright enough to bloom, with a white-hot head and a
// tapering tail. COLOR comes from the process material's color ramp.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

#include "res://shaders/vfx_common.gdshaderinc"

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec4 core_tint : source_color = vec4(1.0, 0.97, 0.88, 1.0);
uniform float energy = 4.0;
// Quad width / length relative to the particle scale.
uniform float width = 0.06;
uniform float stretch = 0.9;

void vertex() {
	MODELVIEW_MATRIX = vfx_streak(MODEL_MATRIX, VIEW_MATRIX, INV_VIEW_MATRIX, width, stretch);
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	// y: -1 = head (front, UV.y 0 is the top of the quad = +Y = along velocity), +1 = tail.
	float along = c.y * 0.5 + 0.5;
	float across = abs(c.x);
	float taper = mix(1.0, 0.15, along);
	float body = clamp(1.0 - across / taper, 0.0, 1.0);
	body *= body;
	float lng = smoothstep(1.0, 0.55, along) * smoothstep(0.0, 0.12, along);
	float a = body * lng;
	float hot = pow(body, 3.0) * smoothstep(0.6, 0.0, along);
	vec3 col = mix(COLOR.rgb, core_tint.rgb, hot);
	float soft = vfx_soft(depth_tex, SCREEN_UV, INV_PROJECTION_MATRIX, VERTEX, 0.08);
	ALBEDO = col * energy;
	ALPHA = clamp(a * COLOR.a * soft, 0.0, 1.0);
}
