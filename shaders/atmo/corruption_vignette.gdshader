shader_type canvas_item;
// Corruption vignette (AtmoScreenFX, CanvasLayer 0 above the post pass): dark tendrils creeping in
// from the screen edges as the demon's gloom rises. Pure overlay, no screen read, so it is cheap
// enough for every quality tier. `strength` = Atmosphere gloom (0..1.5).

uniform float strength = 0.0;
uniform vec4 color : source_color = vec4(0.09, 0.02, 0.06, 1.0);

float v_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float v_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(v_hash(i), v_hash(i + vec2(1, 0)), u.x), mix(v_hash(i + vec2(0, 1)), v_hash(i + vec2(1, 1)), u.x), u.y);
}

void fragment() {
	vec2 c = SCREEN_UV - 0.5;
	c.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;  // aspect-correct
	float r = length(c);
	// Angular noise, wrapped seamlessly around the screen, slowly crawling inward.
	float a = atan(c.y, c.x) / 6.28318 + 0.5;
	vec2 p = vec2(a * 14.0, r * 5.0 - TIME * 0.12);
	float n = v_noise(p) * 0.6 + v_noise(p * 2.3 + 7.1) * 0.4;
	float s = clamp(strength, 0.0, 1.5);
	// The edge of the stain moves in with the gloom; tendrils reach further where the noise is high.
	float reach = 0.78 - 0.22 * s - n * 0.16 * s;
	float m = smoothstep(reach, reach + 0.32, r);
	// Slow breathing so it reads as alive.
	m *= 0.85 + 0.15 * sin(TIME * 0.8);
	COLOR = vec4(color.rgb, clamp(m * s * 0.8, 0.0, 0.85));
}
