shader_type spatial;
// Glowing ember / spark: camera-facing soft dot, additive and bright enough to bloom, with a
// hot core and flicker. Draw pass of the atmosphere's ember GPUParticles3D (COLOR from the ramp).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(1.0, 0.42, 0.1, 1.0);
uniform vec4 core_tint : source_color = vec4(1.0, 0.85, 0.5, 1.0);
uniform float energy = 4.0;

varying float twinkle;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
			vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
			vec4(0.0, 0.0, 0.0, 1.0));
	float id = float(INSTANCE_ID);
	twinkle = 0.45 + 0.55 * abs(sin(TIME * (5.0 + mod(id, 7.0)) + id * 2.39));
}

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float a = pow(clamp(1.0 - d, 0.0, 1.0), 2.2);
	float core = pow(clamp(1.0 - d * 1.8, 0.0, 1.0), 2.0);
	ALBEDO = mix(tint.rgb, core_tint.rgb, core) * COLOR.rgb * energy;
	ALPHA = clamp(a * COLOR.a * twinkle, 0.0, 1.0);
}
