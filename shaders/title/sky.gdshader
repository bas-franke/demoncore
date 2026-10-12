shader_type sky;
// Dusk of a broken heaven: slate zenith, ash-gold horizon, the sun burning behind the cathedral,
// slow torn cloud bands lit gold toward the sun.
uniform vec3 zenith : source_color = vec3(0.022, 0.03, 0.048);
uniform vec3 mid : source_color = vec3(0.06, 0.058, 0.066);
uniform vec3 horizon : source_color = vec3(0.3, 0.2, 0.12);
uniform vec3 sun_col : source_color = vec3(1.0, 0.76, 0.42);
uniform vec3 cloud_dark : source_color = vec3(0.05, 0.045, 0.05);
uniform float sun_energy = 1.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 5; i++) { s += a * vnoise(p); p = p * 2.02 + vec2(1.7, 9.2); a *= 0.5; }
	return s;
}
void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 sd = normalize(LIGHT0_DIRECTION);
	float mu = max(dot(d, sd), 0.0);
	float hh = clamp(h, 0.0, 1.0);
	vec3 col = mix(horizon, mid, smoothstep(0.0, 0.2, hh));
	col = mix(col, zenith, smoothstep(0.15, 0.75, hh));
	col += sun_col * (pow(mu, 4.0) * 0.12 + pow(mu, 24.0) * 0.5 + pow(mu, 260.0) * 3.0) * sun_energy;
	if (h > -0.06) {
		vec2 uv = d.xz / (max(h, 0.0) + 0.22);
		uv = uv * 1.3 + vec2(TIME * 0.006, 0.0);
		float c = fbm(uv * vec2(0.7, 2.4));
		float c2 = fbm(uv * vec2(3.0, 7.0) + vec2(4.0, 1.0) + vec2(TIME * 0.01, 0.0));
		float cov = smoothstep(0.42, 0.95, c * 0.8 + c2 * 0.3) * 0.85;
		cov *= smoothstep(-0.04, 0.1, h);
		float lit = pow(mu, 6.0);
		vec3 ccol = mix(cloud_dark, sun_col * 1.1, lit * (1.0 - cov * 0.5)) + horizon * 0.18 * (1.0 - hh);
		col = mix(col, ccol, cov * 0.9);
	}
	col = mix(col, horizon * 0.3, smoothstep(0.0, -0.12, h));
	COLOR = col;
}
