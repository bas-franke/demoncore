// Corruption spread: the blight the demon leaves on the world (see docs/team/art-style.md).
// Fed by the `Corruption` autoload (res://autoload/corruption.gd) through global shader uniforms
// (declared in project.godot [shader_globals]), so any shader can include this file:
//
//   #include "res://shaders/style/corruption.gdshaderinc"
//   ...
//   float c = corruption_at(world_pos);                    // 0 = pristine .. 1 = fully blighted
//   corruption_blight(c, world_pos, col, rough, emit);     // ground: char, ash, ember veins
//   corruption_wither(c, col);                             // foliage / props: darken and redden
//
// corruption_map (RGF, CORRUPTION_RES^2 texels, toroidal over the world):
//   R = time (corruption_params.x clock) the texel was last blighted, already shifted older toward
//       the brush edge so edges fade first; G = id of the world tile the stamp belongs to, so the
//       wrapped texture never shows a ghost of a trail one window-width away.
// corruption_params: x = clock (s, pauses with the game), y = hold time (s at full strength),
//   z = total lifetime (s), w = texel size (m).
// corruption_origin: xyz = the player's position, w = radius (m) of the live aura around them.
// corruption_ambient: floor applied everywhere (Basecamp Hell = 1, a holy map = 0), broken up by a
//   broad noise field so it never looks evenly spread.
// The live aura and the trail are both noise-warped so the front reads as creeping, not circular.

global uniform sampler2D corruption_map;
global uniform vec4 corruption_params;
global uniform vec4 corruption_origin;
global uniform float corruption_ambient;
// 0 = off, 1 = low (crust only, no crack network, no prop char), 2 = full. Corruption.quality.
global uniform float corruption_quality;

// Must match Corruption.RES in res://autoload/corruption.gd.
#define CORRUPTION_RES 256

// Hellfire palette used by the blight (keep in sync with ArtStyle in res://scripts/art_style.gd).
const vec3 CRP_CHAR = vec3(0.045, 0.03, 0.03);
const vec3 CRP_ASH = vec3(0.16, 0.13, 0.12);
const vec3 CRP_BLOOD = vec3(0.24, 0.025, 0.02);
const vec3 CRP_EMBER = vec3(1.0, 0.3, 0.06);

float crp_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float crp_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(crp_hash(i), crp_hash(i + vec2(1.0, 0.0)), f.x),
		mix(crp_hash(i + vec2(0.0, 1.0)), crp_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// Two rotated octaves: plain value noise shows axis-aligned blocks over large blighted areas.
float crp_fbm(vec2 p) {
	const mat2 r = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	return crp_noise(r * p) * 0.6 + crp_noise(r * r * p * 2.3 + 5.7) * 0.4;
}

// Distance to the nearest Voronoi cell edge (the crack network of the blighted crust).
float crp_cracks(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(crp_hash(i + g), crp_hash(i + g + vec2(17.17, 3.71)));
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

// Trail strength of one texel (world texel index `ix`), 0 if it belongs to another world tile.
float crp_texel(ivec2 ix) {
	ivec2 tile = ivec2(floor(vec2(ix) / float(CORRUPTION_RES)));
	ivec2 local = ix - tile * CORRUPTION_RES;
	vec2 v = texelFetch(corruption_map, local, 0).rg;
	float id = float((tile.x & 1023) + (tile.y & 1023) * 1024);
	if (abs(v.g - id) > 0.5 || v.r <= 0.0) {
		return 0.0;
	}
	float age = corruption_params.x - v.r;
	return 1.0 - smoothstep(corruption_params.y, max(corruption_params.z, corruption_params.y + 0.01), age);
}

// Bilinear trail strength at a world XZ position (manual, because tile ids must not be blended).
float crp_trail(vec2 xz) {
	float ts = max(corruption_params.w, 0.01);
	vec2 g = xz / ts - 0.5;
	ivec2 i = ivec2(floor(g));
	vec2 f = g - floor(g);
	float a = crp_texel(i);
	float b = crp_texel(i + ivec2(1, 0));
	float c = crp_texel(i + ivec2(0, 1));
	float d = crp_texel(i + ivec2(1, 1));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// 0..1 corruption at a world position: max(trail, live aura, ambient), with a noisy creeping edge.
float corruption_at(vec3 wp) {
	if (corruption_quality < 0.5) {
		return 0.0;
	}
	vec2 xz = wp.xz;
	// Warp the lookup so the blight front has tendrils instead of round brush blobs.
	float n = crp_fbm(xz * 0.55);
	float trail = crp_trail(xz + (vec2(crp_noise(xz * 0.4 + 9.0), crp_noise(xz * 0.4 - 3.0)) - 0.5) * 1.6);
	float aura = 0.0;
	if (corruption_origin.w > 0.0) {
		float d = length(xz - corruption_origin.xz) / corruption_origin.w;
		aura = 1.0 - smoothstep(0.55, 1.0, d + (n - 0.5) * 0.45);
	}
	// Ambient blight is not a flat floor: broad (~15 m) drifts where it thins out, so a fully
	// blighted scene (Basecamp Hell) still has variation and some of the original ground shows.
	float amb = corruption_ambient;
	if (amb > 0.0) {
		amb *= mix(0.45, 1.15, crp_fbm(xz * 0.065 + 17.0));
	}
	float c = max(max(trail, aura), amb);
	// Sharpen into a crust with a frayed edge; low values die off in noise pockets first.
	return smoothstep(0.08, 0.7, c - (n - 0.5) * 0.35);
}

// Ground blight. `c` from corruption_at(). Darkens and chars the albedo, dusts it with ash, opens
// glowing ember veins in the crust and lays a smouldering rim along the advancing front. Large
// areas vary: crack density follows a broad noise field, and some patches have cooled into
// glossy black obsidian (no embers, low roughness, a faint deep-red glint in the seams).
void corruption_blight(float c, vec3 wp, inout vec3 col, inout float rough, inout vec3 emit) {
	if (c <= 0.001) {
		return;
	}
	vec2 xz = wp.xz;
	float n = crp_fbm(xz * 1.6);
	vec3 crust = mix(CRP_CHAR, CRP_ASH, smoothstep(0.45, 0.85, n) * 0.75);
	crust = mix(crust, CRP_BLOOD, smoothstep(0.6, 0.9, crp_fbm(xz * 0.5 + 2.0)) * 0.4);
	// Keep a trace of the original surface so roads and stones still read underneath.
	// (more of it under ambient blight, where the whole scene is crust).
	vec3 burned = mix(crust, col * vec3(0.45, 0.3, 0.27), mix(0.25, 0.45, corruption_ambient));
	col = mix(col, burned, c);
	rough = mix(rough, 0.92, c);
	if (corruption_quality < 1.5) {
		return;	// low quality: crust only, no crack network
	}
	// Broad fields (~10-20 m): crack density and cooled-obsidian patches.
	float density = crp_fbm(xz * 0.12 + 41.0);
	float cooled = smoothstep(0.54, 0.64, crp_fbm(xz * 0.09 - 23.0)) * smoothstep(0.6, 0.9, c);
	// Ember veins: thin crack network, only in well-established blight, slowly breathing.
	// Only part of the network glows (noise mask), so it reads as fissures, not a lava grid.
	float e = crp_cracks(xz * 1.3 + vec2(crp_noise(xz * 1.3), crp_noise(xz * 1.3 + 5.0)) * 0.6);
	float vein = 1.0 - smoothstep(0.012, 0.05, e);
	// Denser in the player's fresh trail than in a scene-wide ambient blight.
	float thr = mix(0.95, 0.5, smoothstep(0.4, 0.7, density)) - 0.3 * (1.0 - corruption_ambient);
	vein *= smoothstep(thr, thr + 0.12, crp_noise(xz * 0.6 + 7.0));
	float pulse = 0.65 + 0.35 * sin(corruption_params.x * 1.7 + crp_noise(xz * 0.3) * 12.0);
	float veins = vein * smoothstep(0.5, 0.9, c) * pulse * (1.0 - cooled);
	// Dark scorched halo along every crack, glowing or not.
	float seam = 1.0 - smoothstep(0.0, 0.1, e);
	col *= 1.0 - seam * 0.5 * c;
	col = mix(col, CRP_EMBER * 0.4, veins * 0.6);
	emit += CRP_EMBER * veins * mix(1.3, 0.9, corruption_ambient);
	// Cooled obsidian: black glass with a dull glint, seams faintly red-hot deep down.
	col = mix(col, vec3(0.018, 0.015, 0.018), cooled * 0.9);
	rough = mix(rough, 0.18 + 0.2 * n, cooled);
	emit += CRP_BLOOD * seam * cooled * 0.6;
	// Smouldering front: a dim ember band where the blight is still spreading.
	float front = smoothstep(0.08, 0.3, c) * (1.0 - smoothstep(0.3, 0.55, c));
	emit += CRP_EMBER * front * smoothstep(0.45, 0.8, n) * 0.5;
}

// Foliage / prop wither: blackens, dries and reddens living colors (no emission).
void corruption_wither(float c, inout vec3 col) {
	if (c <= 0.001) {
		return;
	}
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	vec3 dead = mix(vec3(l) * vec3(0.55, 0.36, 0.3), CRP_CHAR, 0.35);
	col = mix(col, dead, c * 0.85);
}

// Scenery char: blight creeping up a prop from the ground, ragged top edge, faint ember smoulder
// right at the base of walls. `c` = corruption_at(world_pos), `wn` = world normal. Upward faces
// near the ground (flagstones, plinths, steps) are treated as floor and get the ground blight.
void corruption_char(float c, vec3 wp, vec3 wn, inout vec3 col, inout float rough, inout vec3 emit) {
	if (c <= 0.001) {
		return;
	}
	float floor_k = smoothstep(0.6, 0.85, wn.y) * (1.0 - smoothstep(0.3, 0.6, wp.y));
	if (floor_k > 0.5) {
		corruption_blight(c, wp, col, rough, emit);
		return;
	}
	float edge = 0.35 + 1.1 * c + (crp_fbm(vec2(wp.x + wp.z, wp.y) * 3.0) - 0.5) * 0.5;
	float k = 1.0 - smoothstep(edge - 0.25, edge, wp.y);
	k *= c;
	col = mix(col, CRP_CHAR * 1.6 + col * 0.06, k * 0.92);
	rough = mix(rough, 0.95, k);
	// Embers only along the foot of walls (not tops, not the sides of flat floor tiles, and only
	// in the player's fresh blight: an ambient-blighted scene would get a glowing grid).
	float side = 1.0 - smoothstep(0.4, 0.7, abs(wn.y));
	float foot = smoothstep(0.03, 0.08, wp.y) * (1.0 - smoothstep(0.14, 0.24, wp.y));
	emit += CRP_EMBER * foot * k * side * (1.0 - corruption_ambient) * 0.5;
}
