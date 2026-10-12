shader_type spatial;
// Slow-flowing lava for the river and the forge pools. Bright cracks between cooling crust,
// scrolling along +X in world space so any plane size tiles seamlessly.
render_mode unshaded, cull_back, shadows_disabled;

uniform vec3 crust = vec3(0.05, 0.015, 0.01);
uniform vec3 molten = vec3(1.3, 0.26, 0.04);
uniform vec3 hot = vec3(2.4, 0.9, 0.2);
uniform float scale = 0.45;
uniform vec2 flow = vec2(0.12, 0.03);

varying vec3 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += vnoise(p) * amp;
		// Rotate each octave so the value-noise grid never lines up (no blocky squares).
		p = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p * 2.03 + vec2(1.7, 9.2);
		amp *= 0.5;
	}
	return v;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz * scale;
	float t = TIME;
	// Domain warp so the crust drifts and folds instead of sliding rigidly.
	vec2 w = vec2(fbm(p + flow * t), fbm(p + vec2(5.2, 1.3) - flow * t * 0.7));
	float n = fbm(p + w * 1.6 + flow * t * 2.0);
	float cracks = smoothstep(0.36, 0.55, n);
	float pulse = 0.85 + 0.15 * sin(t * 1.7 + n * 12.0);
	vec3 col = mix(molten * pulse, crust, cracks);
	col += hot * smoothstep(0.3, 0.15, n) * pulse;
	ALBEDO = col;
}
