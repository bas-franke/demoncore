shader_type spatial;
// Back-lit cathedral stained glass on a quad (PropBuilder.quad, UV 0..1, v = 0 at the top).
// The pane is cut to a gothic pointed arch; inside, lead came (dark lines) splits it into Voronoi
// shards plus a rose roundel near the top. Shard colours come from a small jewel palette picked by
// hash, with a slow drifting "holy light" glint and per-window variation from the world position
// (no instance uniforms needed, so windows batch and merge freely). Unshaded and HDR so it blooms.
render_mode unshaded, cull_disabled, shadows_disabled;

uniform vec3 color_a : source_color = vec3(0.75, 0.08, 0.1);	// ruby
uniform vec3 color_b : source_color = vec3(0.1, 0.25, 0.85);	// sapphire
uniform vec3 color_c : source_color = vec3(1.0, 0.72, 0.18);	// gold
uniform vec3 color_d : source_color = vec3(0.45, 0.15, 0.7);	// amethyst
uniform vec3 lead_color : source_color = vec3(0.03, 0.025, 0.03);
uniform float energy = 1.6;
// 0 = intact, 1 = shattered (missing shards show nothing, edges jagged).
uniform float broken : hint_range(0.0, 1.0) = 0.0;
uniform float cells = 5.0;

float sg_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

vec2 sg_hash2(vec2 p) {
	return vec2(sg_hash(p), sg_hash(p + 17.7));
}

// x = distance to nearest cell edge, y = cell id hash
vec2 voronoi(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 9.0;
	float d2 = 9.0;
	vec2 id = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = 0.15 + 0.7 * sg_hash2(i + g);
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
	return vec2(d2 - d1, sg_hash(id));
}

varying vec3 wpos;

void vertex() {
	wpos = MODEL_MATRIX[3].xyz;
}

void fragment() {
	vec2 uv = UV;
	float seed = sg_hash(floor(wpos.xz * 3.0) + 0.5);
	// pointed arch: straight sides below y = 0.38, two circle arcs meeting at the apex above
	vec2 c = vec2(uv.x - 0.5, uv.y);
	float inside = step(abs(c.x), 0.5);
	if (uv.y < 0.38) {
		// arc centred on the opposite side (classic equilateral gothic arch)
		float side = sign(c.x + 1e-4);
		vec2 o = vec2(-side * 0.35, 0.38);
		float r = 0.85;
		// y stretch chosen so both arcs meet exactly at the top centre (uv = 0.5, 0)
		inside *= step(length((c - o) * vec2(1.0, 2.04)), r);
	}
	if (inside < 0.5) {
		discard;
	}
	// rose roundel in the top third, Voronoi shards elsewhere
	vec2 rose_c = vec2(0.0, 0.28);
	float rr = length(c - rose_c);
	float lead;
	float pick;
	if (rr < 0.2) {
		float ang = atan(c.y - rose_c.y, c.x - rose_c.x);
		float petals = abs(sin(ang * 4.0));
		float ring = abs(rr - 0.11);
		lead = min(ring, abs(petals * 0.2 - rr * 0.6) * 0.5);
		lead = min(lead, abs(rr - 0.195));
		pick = fract(floor((ang + 3.1416) / 0.785) * 0.37 + step(0.11, rr) * 0.5 + seed);
	} else {
		vec2 v = voronoi(uv * vec2(cells * 0.6, cells) + seed * 31.0);
		lead = v.x * 0.12;
		pick = v.y;
		// horizontal saddle bars
		lead = min(lead, abs(fract(uv.y * 3.0) - 0.5) < 0.015 ? 0.0 : 1.0);
	}
	if (broken > 0.0 && pick < broken * 0.6) {
		discard;
	}
	vec3 col = pick < 0.3 ? color_a : (pick < 0.55 ? color_b : (pick < 0.8 ? color_c : color_d));
	// grain inside each shard + drifting glint band
	col *= 0.75 + 0.35 * sg_hash(floor(uv * 60.0));
	float glint = smoothstep(0.85, 1.0, sin(uv.x * 3.0 + uv.y * 2.0 - TIME * 0.35 + seed * 6.0));
	float edge = smoothstep(0.0, 0.012, lead);
	vec3 glow = col * energy * (1.0 + glint * 0.8);
	ALBEDO = mix(lead_color, glow, edge);
}
