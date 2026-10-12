shader_type spatial;
// Hellish summoning sigil burned into the ground (flat quad / plane, UV 0..1): double ring with
// rune ticks, an inscribed five-point star, molten cracks and a slow breathing pulse.
// Additive + HDR so it blooms. Variation from world position (no instance uniforms).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.2, 0.05, 1.0);
uniform vec4 hot_color : source_color = vec4(1.0, 0.65, 0.25, 1.0);
uniform float energy = 2.6;
uniform float line = 0.012;

varying float seed;

float sd_seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

void vertex() {
	seed = fract(dot(MODEL_MATRIX[3].xyz, vec3(0.37, 0.0, 0.61)) * 3.7);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float ang = atan(p.y, p.x);
	float aa = fwidth(r) * 1.5;
	float rot = TIME * 0.05 + seed * 6.28;
	float m = 0.0;
	// rings
	m = max(m, 1.0 - smoothstep(line, line + aa, abs(r - 0.94)));
	m = max(m, 1.0 - smoothstep(line * 0.7, line * 0.7 + aa, abs(r - 0.82)));
	m = max(m, 1.0 - smoothstep(line * 0.6, line * 0.6 + aa, abs(r - 0.36)));
	// rune ticks between the outer rings
	float seg = (ang + rot) / 6.2831853 * 36.0;
	float tick = abs(fract(seg) - 0.5);
	float rune = step(0.82, r) * step(r, 0.94) * (1.0 - smoothstep(0.06, 0.06 + aa * 8.0, tick));
	rune *= step(0.35, fract(sin(floor(seg) * 91.7 + seed * 13.0) * 437.5));
	m = max(m, rune * 0.8);
	// five-point star (pentagram)
	float star = 1e3;
	for (int i = 0; i < 5; i++) {
		float a0 = rot * -2.0 + float(i) * 6.2831853 / 5.0 + 1.5708;
		float a1 = a0 + 2.0 * 6.2831853 / 5.0;
		star = min(star, sd_seg(p, vec2(cos(a0), sin(a0)) * 0.82, vec2(cos(a1), sin(a1)) * 0.82));
	}
	m = max(m, 1.0 - smoothstep(line, line + aa, star));
	// slow pulse travelling around the circle
	float pulse = 0.55 + 0.45 * sin(TIME * 1.4 + seed * 6.0);
	float wave = 0.6 + 0.4 * sin(ang * 3.0 - TIME * 2.0);
	float glow = exp(-abs(r - 0.88) * 9.0) * 0.12 + exp(-r * 3.5) * 0.12;
	float edge = 1.0 - smoothstep(0.92, 1.0, r);
	vec3 c = mix(color.rgb, hot_color.rgb, m * pulse * 0.6);
	ALBEDO = c * energy * (m * (0.6 + 0.4 * wave) * pulse + glow * pulse);
	ALPHA = clamp((m + glow) * edge, 0.0, 1.0);
}
