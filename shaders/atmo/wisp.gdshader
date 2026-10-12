shader_type spatial;
// Drifting cloud wisp (draw pass of the Atmosphere rig's "Wisps" GPUParticles3D): a big soft
// camera-facing puff shaped by a few octaves of slowly churning value noise, faded where it meets
// geometry. Very low alpha: haze drifting between the camera and the arena, never a wall.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(0.85, 0.82, 0.76, 1.0);
uniform float opacity = 0.16;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear;

varying float v_rnd;

float w_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float w_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(w_hash(i), w_hash(i + vec2(1, 0)), u.x), mix(w_hash(i + vec2(0, 1)), w_hash(i + vec2(1, 1)), u.x), u.y);
}

void vertex() {
	v_rnd = fract(sin(float(INSTANCE_ID) * 12.9898) * 43758.5453);
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(s * 1.6, 0, 0, 0), vec4(0, s, 0, 0), vec4(0, 0, s, 0), vec4(0, 0, 0, 1));
}

void fragment() {
	vec2 q = UV - 0.5;
	float r = length(q * vec2(1.0, 1.25)) * 2.0;
	vec2 p = UV * 3.0 + v_rnd * 17.0 + vec2(TIME * 0.03, -TIME * 0.02);
	float n = w_noise(p) * 0.55 + w_noise(p * 2.1 + 3.7) * 0.3 + w_noise(p * 4.3 - TIME * 0.05) * 0.15;
	float m = smoothstep(0.25, 0.75, n + (1.0 - r) * 0.6 - 0.3) * smoothstep(1.0, 0.55, r);
	float d = texture(depth_texture, SCREEN_UV).r;
	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	float scene_depth = -v.z / v.w;
	float soft = clamp((scene_depth + VERTEX.z) / 4.0, 0.0, 1.0);
	ALBEDO = color.rgb * (0.9 + 0.2 * n);
	ALPHA = clamp(m * soft * opacity * COLOR.a, 0.0, 1.0);
}
