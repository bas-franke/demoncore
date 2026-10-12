shader_type spatial;
// Burning infernal summoning circle for a 2x2 PlaneMesh scaled to the circle radius.
// Double outer ring, a band of rotating glyphs, a counter-rotating pentagram, a smouldering
// fill and flickering heat. Additive (it reads as light on the ground). `radius` keeps line
// widths constant in world units; `pulse` (0..1) flares it when it deals damage.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 fire = vec3(2.2, 0.42, 0.07);
uniform vec3 hot = vec3(4.0, 1.5, 0.45);
uniform vec3 smoulder = vec3(0.38, 0.05, 0.02);
// Line width in world units.
uniform float line_width = 0.12;
uniform float rune_count = 16.0;
// Turns per second.
uniform float spin = 0.025;
uniform float intensity = 1.0;
instance uniform float radius = 2.2;
instance uniform float pulse = 0.0;

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

float seg_dist(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	float aa = fwidth(r) * 1.5;
	float w = line_width / max(radius, 0.01);
	float ang = atan(p.y, p.x);

	float n = vnoise(vec2(ang * 4.0, r * 7.0 - TIME * 1.6)) * 0.6 + vnoise(p * 9.0 + TIME * 0.7) * 0.4;
	float flick = 0.7 + 0.6 * n;

	// Rings.
	float r_outer = 1.0 - w * 0.8;
	float r_inner = 1.0 - w * 5.0;
	float ring1 = 1.0 - smoothstep(w * 0.5, w * 0.5 + aa, abs(r - r_outer));
	float ring2 = 1.0 - smoothstep(w * 0.28, w * 0.28 + aa, abs(r - r_inner));
	float ring3 = 1.0 - smoothstep(w * 0.2, w * 0.2 + aa, abs(r - (r_inner - w * 1.4)));

	// Glyph band between the rings.
	float band_in = r_inner + w * 0.7;
	float band_out = r_outer - w * 0.8;
	float rr = (r - band_in) / max(band_out - band_in, 0.0001);
	float rot = ang / TAU + TIME * spin;
	float cell = fract(rot * rune_count);
	float id = floor(rot * rune_count);
	float glyph = 0.0;
	if (rr > 0.0 && rr < 1.0 && cell > 0.18 && cell < 0.82) {
		float lw = 0.11;
		float h1 = hash(vec2(id, 1.0));
		float h2 = hash(vec2(id, 2.0));
		float h3 = hash(vec2(id, 3.0));
		float x = (cell - 0.5) / 0.32;
		glyph = max(glyph, 1.0 - step(lw * 1.6, abs(x - (h3 - 0.5) * 0.6)));
		glyph = max(glyph, (1.0 - step(lw, abs(rr - 0.2))) * step(0.45, h1) * (1.0 - step(0.8, abs(x))));
		glyph = max(glyph, (1.0 - step(lw, abs(rr - 0.8))) * step(0.35, h2) * (1.0 - step(0.8, abs(x))));
		glyph = max(glyph, (1.0 - step(lw * 1.4, abs(x - (rr - 0.5) * 1.4))) * step(0.55, h3));
		glyph = max(glyph, (1.0 - step(lw * 1.4, abs(x + (rr - 0.5) * 1.4))) * step(0.75, h1));
	}

	// Pentagram, counter-rotating.
	float sr = r_inner - w * 1.4;
	float sa = -TIME * spin * TAU * 0.7 + PI * 0.5;
	float star = 1e3;
	for (int i = 0; i < 5; i++) {
		float a0 = sa + TAU * float(i) / 5.0;
		float a1 = sa + TAU * float(i + 2) / 5.0;
		star = min(star, seg_dist(p, vec2(cos(a0), sin(a0)) * sr, vec2(cos(a1), sin(a1)) * sr));
	}
	float star_line = 1.0 - smoothstep(w * 0.22, w * 0.22 + aa * 1.5, star);
	star_line *= step(r, sr + w);

	vec3 col = smoulder * (0.25 + 0.75 * r * r) * flick;
	col += fire * (ring1 + ring2 * 0.85 + ring3 * 0.5) * flick;
	col += hot * ring1 * 0.35 * flick;
	col += mix(fire, hot, 0.25) * glyph * flick;
	col += fire * star_line * 0.65 * flick;
	// Heat creeping inward from the rim.
	col += fire * smoothstep(0.75, 1.0, r) * 0.18 * n;
	col *= intensity * (1.0 + pulse * 1.3);

	ALBEDO = col;
	ALPHA = 1.0;
}
