shader_type spatial;
// Snowflake (draw pass of the Atmosphere rig's "Snow" GPUParticles3D): a camera-facing soft dot with a
// gentle sideways sway per flake (the process material does the falling). Alpha blended, unshaded;
// `color` is fed per preset by the rig.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(0.9, 0.94, 1.0, 1.0);
uniform float opacity = 0.85;
uniform float sway = 0.25;

varying float v_rnd;

void vertex() {
	float id = float(INSTANCE_ID);
	v_rnd = fract(sin(id * 12.9898) * 43758.5453);
	vec3 c = MODEL_MATRIX[3].xyz;
	c.x += sin(TIME * (0.9 + v_rnd) + v_rnd * 30.0) * sway;
	c.z += cos(TIME * (0.7 + v_rnd * 0.6) + v_rnd * 17.0) * sway * 0.6;
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], vec4(c, 1.0));
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(s, 0, 0, 0), vec4(0, s, 0, 0), vec4(0, 0, s, 0), vec4(0, 0, 0, 1));
}

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float a = smoothstep(1.0, 0.35, d);
	ALBEDO = color.rgb * (0.85 + 0.15 * v_rnd);
	ALPHA = a * opacity * COLOR.a;
}
