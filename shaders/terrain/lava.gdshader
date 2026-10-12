shader_type spatial;
// Molten lava surface (world space, so any mesh -- a big plane under a TerrainPatch, a river ribbon,
// a pool disc -- shows one continuous flow). Two layers:
//   - glowing melt: domain-warped fbm drifting along `flow`, white-yellow in hot veins, deep red in
//     the cooler body
//   - floating crust plates: Voronoi cells that drift a little slower than the melt, dark basalt with
//     cracks that glow; crust thins out where the melt is hottest
// Heat breathes slowly (`pulse`). Lit (crust gets highlights), HDR emission blooms.
render_mode diffuse_burley, specular_schlick_ggx, cull_back;

uniform vec3 hot_color : source_color = vec3(1.0, 0.78, 0.32);
uniform vec3 mid_color : source_color = vec3(1.0, 0.28, 0.04);
uniform vec3 cool_color : source_color = vec3(0.35, 0.03, 0.01);
uniform vec3 crust_color : source_color = vec3(0.05, 0.035, 0.03);
uniform float energy = 3.0;
uniform vec2 flow = vec2(0.25, 0.12);
uniform float scale = 0.35;
uniform float crust_amount : hint_range(0.0, 1.0) = 0.55;
uniform float pulse = 0.15;

float lv_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float lv_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(lv_hash(i), lv_hash(i + vec2(1, 0)), u.x), mix(lv_hash(i + vec2(0, 1)), lv_hash(i + vec2(1, 1)), u.x), u.y);
}

float lv_fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * lv_noise(p);
		p = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6)) * p + 3.7;
		a *= 0.5;
	}
	return s / 0.9375;
}

// x = distance to cell edge, y = cell hash
vec2 lv_voronoi(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 9.0;
	float d2 = 9.0;
	vec2 id = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(lv_hash(i + g), lv_hash(i + g + 9.1));
			float d = length(g + o - f);
			if (d < d1) {
				d2 = d1;
				d1 = d;
				id = i + g;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return vec2(d2 - d1, lv_hash(id + 3.3));
}

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz * scale;
	float t = TIME;
	vec2 melt_p = p - flow * t * scale;
	vec2 warp = vec2(lv_fbm(melt_p * 0.8 + t * 0.05), lv_fbm(melt_p * 0.8 + 5.2 - t * 0.04));
	float heat = lv_fbm(melt_p * 1.3 + warp * 1.6);
	heat = clamp(heat * 1.25 - 0.1, 0.0, 1.0);
	heat *= 1.0 + pulse * sin(t * 0.9 + lv_noise(p * 0.3) * 6.0);
	vec3 melt = mix(cool_color, mid_color, smoothstep(0.2, 0.6, heat));
	melt = mix(melt, hot_color, smoothstep(0.62, 0.95, heat));

	// crust plates drift at 70% of the melt speed, so they slide over it
	vec2 v = lv_voronoi((p - flow * t * scale * 0.7) * 1.6 + warp * 0.35);
	float plate = smoothstep(0.04, 0.16, v.x);
	float crust = plate * step(v.y, crust_amount) * (1.0 - smoothstep(0.55, 0.85, heat));
	vec3 emit = melt * energy * (1.0 - crust * 0.92);
	// glowing seam around each plate
	float seam = (1.0 - smoothstep(0.0, 0.06, v.x)) * step(v.y, crust_amount);
	emit += mid_color * seam * energy * 0.6;

	ALBEDO = mix(melt * 0.2, crust_color, crust);
	ROUGHNESS = mix(0.35, 0.9, crust);
	METALLIC = 0.0;
	EMISSION = emit;
	SPECULAR = 0.4;
}
