shader_type spatial;
// Endless ruined-sanctum ground. Works in world space, so the plane can follow the player without
// the pattern sliding. Layout is procedural; surface detail comes from baked seamless textures
// (tools/build_ground_textures.gd, assigned by ground.gd):
//   noise_tex  RGBA = four smooth fbm fields (macro variation, layer masks, anti-tiling)
//   stone_tex  RG = detail normal, B = height, A = lichen      (1.6 m tile, offset per flagstone)
//   soil_tex   RG = detail normal, B = height (grit < 0.3 < grass blades), A = blade tint (2.4 m tile)
// Layers, all height-blended against each other:
//   1. grass sward (baked blades, sampled twice at different scale/rotation to kill tiling), moss
//      cushions, bare dirt, wet mud in hollows, ash drifts that fill the lows first
//   2. winding flagstone roads and ring-laid plazas (one at the origin): per-stone texture, chipped
//      rounded bevels, recessed grout with grass tufts, moss creeping in from the joints, ash piling
//      against the edges, water pooling on the low corner of tilted stones, sun contact shadows
//   3. puddles (driven by `wetness`): roughness ~0, flat, fresnel sky + drifting-cloud reflection
//   4. decals: bones / skulls / ribs, pebbles (with cast shadows), charred specks and embers,
//      fallen leaves (veins, curl, floating on puddles)
//   5. normal = baked detail slopes + derivative bump of the procedural height; PBR light from
//      lit_light.gdshaderinc with drifting cloud shadows (and the contact shadows) on the sun

render_mode diffuse_burley, specular_schlick_ggx;

#include "res://shaders/cloud.gdshaderinc"
#include "res://shaders/style/corruption.gdshaderinc"

// --- soil & vegetation
uniform vec3 grass_dark : source_color = vec3(0.055, 0.08, 0.04);
uniform vec3 grass_mid : source_color = vec3(0.13, 0.165, 0.065);
uniform vec3 grass_dry : source_color = vec3(0.27, 0.235, 0.13);
uniform vec3 dirt_color : source_color = vec3(0.16, 0.125, 0.09);
uniform vec3 mud_color : source_color = vec3(0.055, 0.045, 0.037);
uniform vec3 ash_color : source_color = vec3(0.25, 0.24, 0.23);
// --- stone
uniform vec3 stone_color : source_color = vec3(0.42, 0.4, 0.36);
uniform vec3 stone_color_b : source_color = vec3(0.31, 0.31, 0.315);
uniform vec3 joint_color : source_color = vec3(0.035, 0.038, 0.028);
uniform vec3 moss_color : source_color = vec3(0.09, 0.115, 0.045);
// --- decals
uniform vec3 bone_color : source_color = vec3(0.6, 0.56, 0.46);
uniform vec3 leaf_color_a : source_color = vec3(0.17, 0.09, 0.045);
uniform vec3 leaf_color_b : source_color = vec3(0.36, 0.24, 0.08);
uniform vec3 ember_color : source_color = vec3(1.0, 0.32, 0.06);
// --- layout
uniform float road_scale = 0.017;
uniform float road_width = 0.03;
uniform float plaza_cell = 40.0;
uniform float plaza_chance : hint_range(0.0, 1.0) = 0.45;
uniform float origin_plaza_radius = 7.0;
uniform float bump_strength = 1.0;
// --- surface detail / weather
uniform float detail_strength : hint_range(0.0, 3.0) = 1.0;
/// 0 = dry, 1 = after heavy rain (more / bigger puddles, darker glossy stone and soil).
uniform float wetness : hint_range(0.0, 1.0) = 0.35;
uniform vec3 water_color : source_color = vec3(0.02, 0.022, 0.02);
uniform vec3 puddle_sky_color : source_color = vec3(0.26, 0.3, 0.34);
uniform vec3 puddle_horizon_color : source_color = vec3(0.5, 0.44, 0.35);
uniform float puddle_reflection = 1.0;
/// Direction TOWARD the sun (world). ground.gd keeps it in sync with the scene's DirectionalLight3D.
uniform vec3 sun_dir = vec3(0.45, 0.75, 0.5);
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D stone_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;

const float STONE_TILE = 1.6;
const float SOIL_TILE = 2.4;
const float GAP = 0.04;

varying vec3 world_pos;
varying float cloud;

#include "res://shaders/lit_light.gdshaderinc"

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

vec2 hash22(vec2 p) {
	return vec2(hash21(p), hash21(p + vec2(17.17, 3.71)));
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	mat2 r = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6));
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p = r * p + vec2(3.1, 7.7);
		a *= 0.5;
	}
	return s / 0.9375;
}

// Distance to the nearest Voronoi edge (cracks).
float voronoi_edge(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = hash22(i + g);
			float d = length(g + o - f);
			if (d < d1) {
				d2 = d1;
				d1 = d;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return d2 - d1;
}

mat2 rot2(float a) {
	float c = cos(a);
	float s = sin(a);
	return mat2(vec2(c, s), vec2(-s, c));
}

float seg_dist(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

// Baked normal (RG) -> world height slope (dh/dx, dh/dz).
vec2 tex_slope(vec2 e) {
	vec2 n = e * 2.0 - 1.0;
	float ny = sqrt(max(1.0 - dot(n, n), 0.05));
	return -n / ny;
}

// Road mask: 1 on the road, soft toward the edge. `wide` = wider halo (dirt verge).
float road_mask(vec2 p, out float wide) {
	vec2 q = p * road_scale;
	vec2 w = vec2(fbm(q * 1.7 + 11.0), fbm(q * 1.7 - 7.0));
	float n = fbm(q + (w - 0.5) * 0.7);
	float d = abs(n - 0.5);
	wide = 1.0 - smoothstep(road_width, road_width * 2.4, d);
	return 1.0 - smoothstep(road_width * 0.45, road_width, d);
}

// Plaza: returns mask; offset from the plaza center and its radius via out.
float plaza_mask(vec2 p, out vec2 rel, out float radius) {
	float best = 0.0;
	rel = vec2(1000.0);
	radius = 1.0;
	// guaranteed plaza at the origin (the player starts here)
	float r0 = length(p);
	if (r0 < origin_plaza_radius + 0.5) {
		rel = p;
		radius = origin_plaza_radius;
		best = 1.0 - smoothstep(radius - 1.8, radius + 0.2, r0);
	}
	vec2 cell = floor(p / plaza_cell);
	bool near_origin = abs(cell.x + 0.5) < 1.0 && abs(cell.y + 0.5) < 1.0;
	if (!near_origin && hash21(cell + 0.37) < plaza_chance) {
		vec2 c = (cell + 0.3 + 0.4 * hash22(cell + 5.1)) * plaza_cell;
		float rad = mix(4.5, 8.0, hash21(cell + 2.9));
		vec2 d = p - c;
		float r = length(d);
		float m = 1.0 - smoothstep(rad - 2.0, rad + 0.2, r);
		if (m > best) {
			best = m;
			rel = d;
			radius = rad;
		}
	}
	return best;
}

// Flagstone layout. Returns the (chipped) distance into the stone from its joint, in metres.
float stone_layout(vec2 p, vec2 prel, bool ringed, vec2 gx, vec2 gy, out vec2 id, out vec2 local, out vec2 size) {
	float e;
	if (ringed) {
		// ring-laid stones around the plaza center
		float r = length(prel);
		float ang = atan(prel.y, prel.x);
		float ring_w = 0.95;
		float ri = floor(r / ring_w);
		if (ri < 1.0) {
			id = vec2(-7.0, -7.0) + floor(prel / 100.0);
			e = ring_w - r;
			size = vec2(ring_w * 2.0);
			local = prel + ring_w;
		} else {
			float circ = TAU * (ri + 0.5) * ring_w;
			float nseg = max(6.0, floor(circ / 1.25));
			float u = (ang / TAU + 0.5 + hash21(vec2(ri, 3.0))) * nseg;
			float seg = floor(u);
			float seg_len = circ / nseg;
			float along = fract(u) * seg_len;
			float across = r - ri * ring_w;
			e = min(min(along, seg_len - along), min(across, ring_w - across));
			id = vec2(ri, mod(seg, nseg)) + floor(p / 300.0) * 37.0;
			local = vec2(along, across);
			size = vec2(seg_len, ring_w);
		}
	} else {
		// running-bond road stones
		size = vec2(1.25, 0.8);
		float row = floor(p.y / size.y);
		float x = p.x + hash21(vec2(row, 1.7)) * size.x;
		float colm = floor(x / size.x);
		local = vec2(x - colm * size.x, p.y - row * size.y);
		e = min(min(local.x, size.x - local.x), min(local.y, size.y - local.y));
		id = vec2(colm, row);
	}
	// chipped, broken edges: fine jitter + occasional deep spalls bitten out of the rim
	e += (vnoise(p * 9.0) - 0.5) * 0.05 + (vnoise(p * 2.3) - 0.5) * 0.06;
	float spall = textureGrad(noise_tex, p * 0.31 + hash21(id) * 5.0, gx * 0.31, gy * 0.31).a;
	e -= smoothstep(0.6, 0.78, spall) * 0.13;
	return e;
}

float stone_present(vec2 id, float pave) {
	float missing = mix(0.95, 0.1, smoothstep(0.0, 0.85, pave));
	return step(missing, hash21(id + 9.3));
}

// Bones / skulls / ribs in a 2.6 m cell grid. Returns coverage; height (m) and socket darkness via out.
float bones_at(vec2 p, float density, float aa, out float bh, out float dark) {
	bh = 0.0;
	dark = 0.0;
	float bc = 2.6;
	vec2 cell = floor(p / bc);
	if (hash21(cell + 4.21) >= density) {
		return 0.0;
	}
	vec2 c = (cell + 0.25 + 0.5 * hash22(cell + 7.3)) * bc;
	vec2 q = rot2(hash21(cell + 1.1) * TAU) * (p - c);
	float kind = hash21(cell + 9.9);
	float bm = 0.0;
	if (kind < 0.22) {
		// skull: cranium, cheek/maxilla, sockets, nasal cavity, teeth line
		vec2 s = q * vec2(1.0, 1.0);
		float cran = length(s * vec2(1.0, 1.25) - vec2(0.0, 0.03)) - 0.13;
		float face = length((s - vec2(0.0, -0.1)) * vec2(1.45, 1.6)) - 0.1;
		float d = min(cran, face);
		bm = 1.0 - smoothstep(-aa, aa, d);
		float rr = clamp(-d / 0.13, 0.0, 1.0);
		bh = 0.07 * sqrt(rr) * bm;
		float eyes = min(length((s - vec2(0.05, -0.05)) * vec2(1.0, 1.2)), length((s - vec2(-0.05, -0.05)) * vec2(1.0, 1.2))) - 0.032;
		float nose = length((s - vec2(0.0, -0.11)) * vec2(2.2, 1.0)) - 0.025;
		float holes = 1.0 - smoothstep(-aa, aa * 0.5 + 0.006, min(eyes, nose));
		float teeth = (1.0 - smoothstep(0.004, 0.009, abs(s.y + 0.165))) * step(abs(s.x), 0.05)
				* (0.5 + 0.5 * step(0.5, fract(s.x * 70.0)));
		dark = max(holes, teeth * 0.6) * bm;
		bh -= holes * 0.05 * bm;
		// a cracked fontanel
		dark = max(dark, (1.0 - smoothstep(0.0, 0.006, abs(s.x + 0.012 * sin(s.y * 60.0)))) * step(0.0, s.y) * 0.5 * bm);
	} else if (kind < 0.4) {
		// rib cage remnant: a few curved ribs off a spine
		float d = abs(q.x) - 0.018;	// spine
		d = max(d, abs(q.y) - 0.28);
		for (int i = 0; i < 4; i++) {
			float y = -0.2 + float(i) * 0.13;
			vec2 rq = q - vec2(0.0, y);
			rq.x = abs(rq.x);
			float arc = abs(length(rq - vec2(0.0, -0.22)) - 0.25) - 0.012;
			arc = max(arc, -(rq.y + 0.05));
			arc = max(arc, rq.x - 0.24 + 0.08 * hash21(cell + float(i)));
			d = min(d, arc);
		}
		bm = 1.0 - smoothstep(-aa, aa, d);
		bh = 0.025 * bm * sqrt(clamp(-d / 0.015, 0.0, 1.0));
	} else {
		// long bone(s) with two-lobed ends, sometimes snapped
		float len = mix(0.16, 0.3, hash21(cell + 3.9));
		float r = 0.022;
		float d = seg_dist(q, vec2(-len, 0.0), vec2(len, 0.0)) - r * (1.0 + 0.6 * smoothstep(len * 0.6, len, abs(q.x)));
		vec2 qa = vec2(abs(q.x) - len, abs(q.y) - 0.022);
		d = min(d, length(qa) - 0.03);
		if (hash21(cell + 6.6) < 0.35) {
			d = max(d, q.x - len * 0.3 + 0.02 * sin(q.y * 120.0));	// snapped, jagged end
		}
		bm = 1.0 - smoothstep(-aa, aa, d);
		bh = 0.035 * bm * sqrt(clamp(-d / 0.03, 0.0, 1.0));
		if (hash21(cell + 2.4) < 0.5) {
			vec2 q2 = rot2(1.1) * q - vec2(0.0, 0.07);
			float d2 = seg_dist(q2, vec2(-len * 0.8, 0.0), vec2(len * 0.8, 0.0)) - 0.02;
			d2 = min(d2, length(vec2(abs(q2.x) - len * 0.8, q2.y)) - 0.03);
			float bm2 = 1.0 - smoothstep(-aa, aa, d2);
			bm = max(bm, bm2);
			bh = max(bh, 0.05 * bm2 * sqrt(clamp(-d2 / 0.03, 0.0, 1.0)));
		}
	}
	return bm;
}

// Pebbles in a 0.9 m grid. Returns coverage; height (m) and tint via out.
float pebble_at(vec2 p, float density, float aa, out float ph, out float tint) {
	ph = 0.0;
	tint = 0.0;
	float pc = 0.9;
	vec2 cell = floor(p / pc);
	if (hash21(cell + 6.66) >= density) {
		return 0.0;
	}
	vec2 c = (cell + 0.25 + 0.5 * hash22(cell + 2.7)) * pc;
	float r = mix(0.035, 0.1, hash21(cell + 5.5));
	vec2 q = rot2(hash21(cell + 0.5) * TAU) * (p - c);
	float d = length(q * vec2(1.0, 1.35)) / r;
	d += (vnoise(q * 40.0 + cell) - 0.5) * 0.25;
	float pm = 1.0 - smoothstep(1.0 - aa / r, 1.0 + aa / r, d);
	ph = r * 0.7 * sqrt(clamp(1.0 - d * d, 0.0, 1.0)) * pm;
	tint = hash21(cell);
	return pm;
}

// Fallen leaf in a jittered cell grid of size `lc`. Returns coverage; color/height/AO halo via out.
float leaf_at(vec2 p, float lc, float seed, float density, float aa, out vec3 lcol, out float lh, out float halo) {
	lcol = vec3(0.0);
	lh = 0.0;
	halo = 0.0;
	vec2 cell = floor(p / lc) + seed;
	if (hash21(cell + 0.71) >= density) {
		return 0.0;
	}
	vec2 c = (cell - seed + 0.22 + 0.56 * hash22(cell + 1.9)) * lc;
	vec2 q = rot2(hash21(cell + 3.3) * TAU) * (p - c);
	float sz = mix(0.07, 0.13, hash21(cell + 8.8));
	float t = clamp(q.x / sz, -1.0, 1.0);
	// lanceolate-to-ovate outline, wider toward the stem, lobed for oak-like leaves
	float w = sz * mix(0.34, 0.5, hash21(cell + 4.4)) * pow(max(1.0 - t * t, 0.0), 0.7) * (1.0 - 0.25 * t);
	float oak = step(0.55, hash21(cell + 2.9));
	w *= 1.0 + oak * 0.22 * sin((t + 1.0) * 3.1416 * 3.5);
	float d = max(abs(q.y) - w, abs(q.x) - sz);
	float stem = max(seg_dist(q, vec2(-sz, 0.0), vec2(-sz * 1.32, 0.01)) - 0.003, 0.0);
	float lm = 1.0 - smoothstep(-aa * 0.6, aa * 0.6, min(d, stem));
	halo = 1.0 - smoothstep(0.0, 0.025, d);
	if (lm <= 0.0 && halo <= 0.0) {
		return 0.0;
	}
	float age = hash21(cell + 6.1);
	lcol = mix(leaf_color_a, leaf_color_b, age) * (0.65 + 0.45 * hash21(cell + 2.2));
	// a few rust-red and near-black rotting leaves
	lcol = mix(lcol, vec3(0.3, 0.09, 0.04), step(0.85, hash21(cell + 7.7)) * 0.7);
	lcol = mix(lcol, vec3(0.05, 0.04, 0.03), step(0.9, age) * 0.7);
	float yn = abs(q.y) / max(w, 1e-4);
	// midrib + lateral veins (lighter on dried leaves), decayed darker margins, fungal speckles
	float rib = 1.0 - smoothstep(0.0, 0.004 + aa * 0.3, abs(q.y));
	float vein = 1.0 - smoothstep(0.0, 0.12, abs(fract((q.x + abs(q.y) * 1.3) / (sz * 0.3)) - 0.5) * 2.0 - 0.0);
	lcol *= 1.0 + 0.35 * rib + 0.12 * vein * (1.0 - yn);
	lcol *= 1.0 - 0.45 * smoothstep(0.55, 1.0, yn);
	lcol *= 1.0 - 0.5 * step(0.8, vnoise(q * 160.0 + cell * 3.0)) * step(0.5, age);
	// curled-up margins and raised midrib
	float curl = mix(0.004, 0.018, hash21(cell + 5.2));
	lh = (0.004 + curl * yn * yn + 0.002 * rib) * lm;
	return lm;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	vec2 dpx = dFdx(p);
	vec2 dpy = dFdy(p);
	float aa = max(fwidth(p.x), 0.002);
	// fade very fine detail when it would alias
	float fine_fade = 1.0 - smoothstep(0.03, 0.09, aa);
	vec3 sun = normalize(sun_dir);
	vec2 sun_off = sun.xz / max(sun.y, 0.3);	// horizontal shift (toward the sun) per metre of height
	float sun_shadow = 0.0;	// contact shadows from stones / bones / pebbles
	float ao = 1.0;

	// ------------------------------------------------ macro fields
	vec4 nA = texture(noise_tex, p / 113.0);
	vec4 nB = texture(noise_tex, p / 31.0 + vec2(0.37, 0.61));
	vec4 nC = texture(noise_tex, rot2(0.7) * p / 7.3 + vec2(0.13, 0.71));
	float big = nA.r;
	float relief = nA.b * 0.65 + nB.r * 0.35;	// macro terrain height: water and mud gather in the lows

	// ------------------------------------------------ 1. soil & vegetation
	// grass texture sampled twice (different scale & rotation), blended by noise: no visible tiling
	mat2 R = rot2(1.1);
	vec4 s1 = texture(soil_tex, p / SOIL_TILE);
	vec4 s2 = texture(soil_tex, (R * p) / (SOIL_TILE * 1.37) + vec2(0.29, 0.53));
	float sb = smoothstep(0.38, 0.62, nC.r);
	float s_h = mix(s1.b, s2.b, sb);
	float s_t = mix(s1.a, s2.a, sb);
	vec2 slope = mix(tex_slope(s1.rg), transpose(R) * tex_slope(s2.rg) / 1.37, sb);

	float dirt = smoothstep(0.6, 0.76, nB.a * 0.55 + nA.r * 0.25 + nC.b * 0.2);
	float ash = smoothstep(0.6, 0.72, nA.a * 0.8 + nB.b * 0.2);
	float road_wide;
	float road = road_mask(p, road_wide);
	vec2 prel;
	float prad;
	float plaza = plaza_mask(p, prel, prad);
	dirt = max(dirt, road_wide * 0.8);
	dirt = max(dirt, smoothstep(prad + 2.5, prad - 0.5, length(prel)) * 0.75);
	dirt = max(dirt, smoothstep(0.42, 0.3, relief) * 0.8);	// trampled, bare in the hollows

	// grass: lush / olive / sun-dried by macro fields, per-blade tint, dark gaps between blades
	float lush = smoothstep(0.3, 0.7, nB.g * 0.7 + nC.g * 0.3);
	vec3 gcol = mix(grass_dark, grass_mid, lush);
	gcol = mix(gcol, grass_dry, smoothstep(0.56, 0.76, big) * 0.8);
	gcol *= 0.72 + 0.56 * s_t;
	gcol = mix(gcol, gcol * vec3(1.25, 1.1, 0.65), smoothstep(0.7, 1.0, s_t) * 0.55);
	float tip = smoothstep(0.36, 0.95, s_h);
	gcol *= mix(0.45, 1.2, tip);
	// moss cushions
	float moss_zone = smoothstep(0.6, 0.74, nA.g * 0.75 + nC.a * 0.25);
	gcol = mix(gcol, moss_color * (0.8 + 0.5 * s_h), moss_zone * 0.75);
	// soil between and instead of the blades
	vec3 soil = mix(moss_color * 0.35, dirt_color * (0.6 + 1.4 * s_h), smoothstep(0.0, 0.5, dirt + 0.15));
	soil *= 0.85 + 0.3 * nC.b;
	// height-blend: thinning grass keeps only its tallest blades
	float cov_thr = mix(0.3, 1.0, dirt);
	float gw = smoothstep(cov_thr - 0.05, cov_thr + 0.05, s_h);
	vec3 col = mix(soil, gcol, gw);
	float rough = mix(0.95, 0.82, gw);
	float spec = mix(0.3, 0.45, gw);
	float surf = mix(s_h * 0.5, s_h, gw);	// local height (0..1) for the other blends
	ao *= mix(0.6, 1.0, smoothstep(0.1, 0.6, s_h));
	slope *= mix(0.6, 1.0, gw) * (1.0 - moss_zone * 0.5);

	// mud: fills the hollows, grass blades poke out of it at the margins
	float mud_lvl = smoothstep(0.42, 0.28, relief) * 1.25 - 0.1 + (nC.a - 0.5) * 0.3;
	float mud = smoothstep(-0.06, 0.06, mud_lvl - surf);
	vec3 mudc = mud_color * (0.8 + 0.5 * s_h) * (0.9 + 0.2 * nC.g);
	col = mix(col, mudc, mud);
	rough = mix(rough, 0.5, mud);
	slope *= 1.0 - mud * 0.6;
	surf = mix(surf, mud_lvl * 0.5, mud);

	// ash drifts settle into the lows first
	vec3 ashc = ash_color * (0.8 + 0.3 * nC.r) * (0.9 + 0.2 * s_h);
	float ash_lvl = ash * 1.4 - 0.3;
	float ash_w = smoothstep(-0.08, 0.08, ash_lvl - surf * 0.8) * step(0.001, ash);
	col = mix(col, ashc, ash_w);
	rough = mix(rough, 1.0, ash_w);
	slope *= 1.0 - ash_w * 0.7;

	float h = 0.0;	// procedural height (metres) -> derivative bump

	// ------------------------------------------------ 2. flagstones
	float pave = max(road, plaza);
	float stone_m = 0.0;
	float wet_bias = 0.0;
	float stone_pool = 0.0;
	if (pave > 0.01) {
		bool ringed = plaza >= road;
		vec2 id;
		vec2 local;
		vec2 size;
		float e = stone_layout(p, prel, ringed, dpx, dpy, id, local, size);
		float hs = hash21(id);
		float present = stone_present(id, pave);
		float m = smoothstep(GAP, GAP + 0.008 + aa, e) * present;
		// per-stone texture patch
		vec4 st = textureGrad(stone_tex, p / STONE_TILE + hash22(id) * 7.0, dpx / STONE_TILE, dpy / STONE_TILE);
		float bev = smoothstep(GAP, GAP + 0.11, e);
		bev = 1.0 - (1.0 - bev) * (1.0 - bev);	// rounded, worn arris
		vec2 tilt = (hash22(id + 4.4) - 0.5) * 0.045;
		float tilt_h = dot(local - size * 0.5, tilt);
		float stone_h = (0.05 + tilt_h) * bev;
		float st_hb = bev * 0.55 + st.b * 0.45;	// 0..1 for blending

		vec3 sc = mix(stone_color, stone_color_b, hash21(id + 1.3));
		sc *= 0.72 + 0.4 * hs;
		sc *= 0.62 + 0.7 * st.b;	// cavities & pits hold grime
		sc *= 1.0 - 0.3 * smoothstep(0.55, 0.82, textureGrad(noise_tex, p * 0.19 + hs, dpx * 0.19, dpy * 0.19).g);	// water stains
		sc *= 1.0 + 0.2 * (1.0 - smoothstep(GAP, GAP + 0.05, e)) * m;	// paler freshly-chipped lip
		vec3 lichen = mix(vec3(0.46, 0.47, 0.37), vec3(0.5, 0.4, 0.2), hash21(id + 3.0));
		sc = mix(sc, lichen, st.a * smoothstep(0.3, 0.9, hash21(id + 8.1)) * 0.6);
		// carved inlay ring on plazas
		if (ringed) {
			float inlay = 1.0 - smoothstep(0.035, 0.07, abs(length(prel) - prad * 0.62));
			sc *= 1.0 - inlay * 0.55;
			stone_h -= inlay * 0.012;
		}
		// cracks
		if (hash21(id + 5.7) < 0.4) {
			float ce = voronoi_edge(p * 1.6 + hs * 13.0);
			float crack = 1.0 - smoothstep(0.012, 0.035 + aa, ce);
			sc = mix(sc, joint_color * 1.5, crack * 0.85);
			stone_h -= crack * 0.025;
			st_hb -= crack * 0.5;
		}
		// moss creeping in from the joints and cracks, filling the low pits first
		float edge_near = 1.0 - smoothstep(GAP, GAP + 0.3, e);
		float moss_lvl = edge_near * 0.7 + (vnoise(p * 3.3 + 2.0) - 0.5) * 0.6 + (1.0 - pave) * 0.35 + moss_zone * 0.35 - 0.12;
		float mw = smoothstep(-0.07, 0.07, moss_lvl - st_hb);
		sc = mix(sc, moss_color * (0.75 + 0.6 * st.b), mw * 0.9);
		// ash piles against the stone edges
		float ash_st = smoothstep(-0.08, 0.08, ash * 1.3 - 0.45 + edge_near * 0.5 - st_hb * 0.6) * step(0.001, ash);
		sc = mix(sc, ashc, ash_st);
		// water pools on the low corner of tilted stones
		float pool_lvl = mix(-0.04, 0.012, wetness) + (hash21(id + 2.2) - 0.5) * 0.02;
		stone_pool = smoothstep(0.0, 0.004, pool_lvl - tilt_h - (st.b - 0.5) * 0.01) * bev * m * (1.0 - ash_st);

		// joints: dark soil, moss and grass tufts, a little water when wet
		float in_pave = smoothstep(0.0, 0.4, pave) * present;
		float tuft = smoothstep(0.45, 0.6, s_h) * smoothstep(0.3, 0.6, vnoise(p * 1.7 + 5.0));
		vec3 jc = mix(joint_color, moss_color * 0.6, smoothstep(0.4, 0.7, vnoise(p * 5.0)));
		jc = mix(jc, gcol, tuft);
		jc = mix(jc, ashc * 0.85, ash * 0.8);
		float jw = in_pave * (1.0 - m);
		col = mix(col, jc, jw * 0.85);
		ao *= 1.0 - jw * (1.0 - tuft) * 0.6;
		wet_bias += jw * 0.5;

		// contact shadow: is there a stone between this point and the sun?
		vec2 id2;
		vec2 l2;
		vec2 sz2;
		vec2 o = sun_off * 0.05;
		float e2 = stone_layout(p + o, prel + o, ringed, dpx, dpy, id2, l2, sz2);
		float occ = smoothstep(GAP + 0.02, GAP + 0.05, e2) * stone_present(id2, pave) * step(0.001, pave);
		sun_shadow = max(sun_shadow, occ * (1.0 - m) * 0.85);

		stone_m = m;
		col = mix(col, sc, m);
		rough = mix(rough, mix(0.86, 0.6, st.b) - 0.08 * hs, m * (1.0 - mw * 0.5));
		spec = mix(spec, 0.5, m);
		vec2 st_slope = tex_slope(st.rg) * (1.0 - mw * 0.5) * (1.0 - ash_st * 0.7);
		slope = mix(slope, st_slope, m);
		h = mix(h - jw * 0.015, stone_h, m);
		surf = mix(surf, st_hb, m);
	}

	// ------------------------------------------------ 3. decals (bones, pebbles, embers)
	float open_ground = 1.0 - stone_m;
	vec3 emit = vec3(0.0);
	{
		float bh;
		float dark;
		float bone_density = 0.035 + 0.08 * dirt + 0.12 * ash;
		float bm = bones_at(p, bone_density, aa, bh, dark) * open_ground;
		vec3 bcol = bone_color * (0.72 + 0.35 * vnoise(p * 23.0)) * (0.8 + 0.25 * vnoise(p * 3.0 + 7.0));
		bcol = mix(bcol, bcol * vec3(0.75, 0.68, 0.55), smoothstep(0.4, 0.8, vnoise(p * 6.0)) * 0.6);	// soil stain
		bcol *= mix(0.55, 1.0, smoothstep(0.0, 0.03, bh));	// grimy where it meets the ground
		bcol = mix(bcol, vec3(0.02, 0.018, 0.015), dark);
		col = mix(col, bcol, bm);
		rough = mix(rough, 0.68, bm);
		spec = mix(spec, 0.4, bm);
		slope *= 1.0 - bm;
		h = mix(h, max(h, 0.0) + bh, bm);
		float sbh;
		float sdark;
		float sbm = bones_at(p + sun_off * 0.04, bone_density, aa, sbh, sdark);
		sun_shadow = max(sun_shadow, sbm * (1.0 - bm) * 0.8 * open_ground);
		ao *= 1.0 - 0.35 * smoothstep(0.0, 1.0, bones_at(p, bone_density, aa * 6.0 + 0.02, sbh, sdark)) * (1.0 - bm) * open_ground;
	}
	{
		float ph;
		float pt;
		float pdens = 0.05 + 0.14 * road_wide + 0.05 * dirt;
		float pm = pebble_at(p, pdens, aa, ph, pt) * open_ground;
		vec3 pcol = mix(stone_color, stone_color_b, pt) * (0.45 + 0.4 * pt) * (0.7 + 0.5 * smoothstep(0.0, 0.05, ph));
		col = mix(col, pcol, pm);
		rough = mix(rough, 0.7, pm);
		slope *= 1.0 - pm;
		h = mix(h, max(h, 0.0) + ph, pm);
		float sph;
		float spt;
		float spm = pebble_at(p + sun_off * 0.03, pdens, aa, sph, spt);
		sun_shadow = max(sun_shadow, spm * (1.0 - pm) * 0.75 * open_ground);
	}
	{
		// charred specks and dying embers in the ash fields
		float ec = 0.45;
		vec2 cell = floor(p / ec);
		float he = hash21(cell + 8.08);
		if (he < ash * 0.18) {
			vec2 c = (cell + 0.2 + 0.6 * hash22(cell + 3.1)) * ec;
			float d = length(p - c);
			float r = mix(0.03, 0.08, hash21(cell + 1.4));
			float cm = 1.0 - smoothstep(r * 0.4, r + aa, d);
			col = mix(col, vec3(0.03, 0.025, 0.022), cm * 0.9 * open_ground);
			if (hash21(cell + 4.7) < 0.3) {
				float pulse = 0.5 + 0.5 * sin(TIME * (1.3 + hash21(cell) * 2.0) + hash21(cell + 2.0) * 6.28);
				float core = 1.0 - smoothstep(0.0, r * 0.5 + aa, d);
				emit += ember_color * core * (0.8 + 2.2 * pulse) * open_ground;
			}
		}
	}

	// ------------------------------------------------ 4. wetness & puddles
	float dry_ash = ash_w * open_ground;
	float pud_thr = mix(0.16, 0.34, wetness);
	float puddle = smoothstep(pud_thr, pud_thr - 0.012, relief + (surf - 0.4) * 0.03) * open_ground * (1.0 - dry_ash);
	puddle = max(puddle, stone_pool);
	float wet = clamp(wetness * 0.35 + mud * 0.55 + wet_bias * wetness + smoothstep(pud_thr + 0.045, pud_thr, relief) * 0.55, 0.0, 1.0);
	wet *= 1.0 - dry_ash;
	// damp surfaces: darker (pores fill with water) and glossier
	col *= mix(1.0, 0.55, wet * 0.8);
	rough = mix(rough, 0.22, wet * 0.75);
	vec3 refl = vec3(0.0);
	if (puddle > 0.001) {
		// murky water over whatever lies beneath, flat with a faint wind ripple
		col = mix(col, col * 0.3 + water_color, puddle * 0.9);
		rough = mix(rough, 0.03, puddle);
		spec = mix(spec, 0.5, puddle);
		vec2 rp = p * 0.35 + TIME * vec2(0.015, 0.008);
		vec2 ripple = (textureGrad(noise_tex, rp * 3.0, dpx * 1.05, dpy * 1.05).rg - 0.5) * 0.03 + (textureGrad(noise_tex, rp * 7.0 + 0.5, dpx * 2.45, dpy * 2.45).ba - 0.5) * 0.015;
		slope = mix(slope, ripple, puddle);
		h = mix(h, min(h, 0.0), puddle);
		// fresnel sky reflection with the drifting clouds mirrored in it
		vec3 vw = normalize(CAMERA_POSITION_WORLD - world_pos);
		vec3 rw = vec3(-vw.x, vw.y, -vw.z);
		float fres = 0.02 + 0.98 * pow(1.0 - clamp(vw.y, 0.0, 1.0), 5.0);
		fres = clamp(fres * 3.0 + 0.06, 0.0, 1.0);
		vec3 cloud_pt = world_pos + vec3(rw.x, 0.0, rw.z) / max(rw.y, 0.2) * 30.0 + vec3(ripple.x, 0.0, ripple.y) * 60.0;
		float overcast = 1.0 - cloud_light(cloud_pt, TIME);
		vec3 sky = mix(puddle_sky_color, puddle_horizon_color, pow(1.0 - clamp(rw.y, 0.0, 1.0), 2.0));
		sky = mix(sky, dot(sky, vec3(0.33)) * 1.6 + vec3(0.04, 0.035, 0.03), overcast * 2.0);
		refl = sky * fres * puddle * puddle_reflection;
	}

	// ------------------------------------------------ 5. fallen leaves (on top of everything, float on water)
	if (fine_fade > 0.0) {
		float leaf_dens = smoothstep(0.42, 0.72, nB.r * 0.6 + nC.g * 0.4) * 0.5 * (1.0 - ash) * (1.0 - stone_m * 0.5);
		vec3 lcol;
		float lh;
		float halo;
		float lm = leaf_at(p, 0.5, 0.0, leaf_dens, aa, lcol, lh, halo);
		vec3 lcol2;
		float lh2;
		float halo2;
		float lm2 = leaf_at(p, 0.37, 31.0, leaf_dens * 0.7, aa, lcol2, lh2, halo2);
		if (lm2 > lm) {
			lm = lm2;
			lcol = lcol2;
			lh = lh2;
		}
		halo = max(halo, halo2);
		lm *= fine_fade;
		ao *= 1.0 - 0.35 * halo * (1.0 - lm) * fine_fade;
		lcol *= mix(1.0, 0.6, wet * 0.7);
		col = mix(col, lcol, lm);
		rough = mix(rough, mix(0.8, 0.35, wet), lm);
		spec = mix(spec, 0.4, lm);
		slope *= 1.0 - lm;
		h = mix(h, lh, lm);
		refl *= 1.0 - lm;
	}

	// ------------------------------------------------ 6. surface
	// large-scale drift + darker hollows
	col *= 0.84 + 0.3 * big;
	// demonic blight around / behind the player (res://shaders/style/corruption.gdshaderinc)
	float crp = corruption_at(world_pos);
	corruption_blight(crp, world_pos, col, rough, emit);
	refl *= 1.0 - crp * 0.6;
	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.02, 1.0);
	SPECULAR = spec;
	AO = ao;
	AO_LIGHT_AFFECT = 0.25;
	EMISSION = emit + refl;

	// normal: baked detail slopes + derivative bump of the procedural height (world space -> view)
	vec3 dpdx = dFdx(world_pos);
	vec3 dpdy = dFdy(world_pos);
	float hx = dFdx(h);
	float hy = dFdy(h);
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 r1 = cross(dpdy, up);
	vec3 r2 = cross(up, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (hx * r1 + hy * r2);
	vec3 wn = normalize(abs(det) * (up - vec3(slope.x, 0.0, slope.y) * detail_strength) - grad * bump_strength);
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);

	cloud = cloud_light(world_pos, TIME) * (1.0 - sun_shadow);
}
