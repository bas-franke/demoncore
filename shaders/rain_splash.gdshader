shader_type spatial;
// Rain splash: draw pass of the Weather splash GPUParticles3D (flat ground-facing quad). A tiny bright
// impact dot, then a thin ring that expands and fades over the particle's short life.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 color : source_color = vec3(0.72, 0.74, 0.78);
uniform float intensity = 0.3;

varying float v_t;
varying float v_a;

void vertex() {
	v_t = INSTANCE_CUSTOM.y;  // age / lifetime
	v_a = COLOR.a;
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float r = length(q);
	float rad = mix(0.12, 0.95, sqrt(v_t));
	float ring = 1.0 - smoothstep(0.0, 0.1 + 0.08 * v_t, abs(r - rad));
	float dot_c = (1.0 - smoothstep(0.0, 0.22, r)) * (1.0 - smoothstep(0.0, 0.25, v_t));
	float a = (ring * (1.0 - v_t) * (1.0 - v_t) * 0.7 + dot_c * 1.2) * v_a;
	ALBEDO = color * intensity;
	ALPHA = clamp(a, 0.0, 1.0);
}
