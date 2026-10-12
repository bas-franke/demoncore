shader_type spatial;
// Falling ash flake: small, slowly tumbling, irregular grey flake (alpha blended, not glowing).
// Draw pass of the atmosphere's ash GPUParticles3D; the particle's own rotation makes it tumble,
// and the quad is lit only by a flat ambient-ish tint so it reads at any angle.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.62, 0.6, 0.57, 1.0);
uniform float opacity = 0.75;

varying float shade;

void vertex() {
	float id = float(INSTANCE_ID);
	shade = 0.55 + 0.45 * fract(sin(id * 12.9898) * 43758.5453);
}

void fragment() {
	vec2 q = UV - 0.5;
	// irregular flake outline
	float ang = atan(q.y, q.x);
	float r = 0.36 + 0.08 * sin(ang * 3.0 + shade * 20.0) + 0.05 * sin(ang * 7.0 + shade * 9.0);
	float d = length(q);
	float a = 1.0 - smoothstep(r - 0.08, r, d);
	ALBEDO = tint.rgb * shade;
	ALPHA = a * opacity * COLOR.a;
}
