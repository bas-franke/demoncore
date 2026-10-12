shader_type spatial;
// Splat + triplanar terrain material for TerrainPatch (scripts/terrain/terrain_patch.gd).
// Everything is in world space so neighbouring patches / the far skirt line up seamlessly.
// Vertex COLOR carries the splat weights baked by the patch:
//   r = path (beaten earth or laid flagstones / marble tiles, see `path_paved`)
//   g = accent mask (where glowing cracks / gold veins may appear)
//   b = shore (closeness to a liquid: scorched / damp / gilded bank, glowing for lava)
//   a = walkable (1 inside the arena, 0 on cliffs / outcrops / beyond the edge)
// UV.x = convexity baked from the heightmap (> 0 on rims and ridges, < 0 in hollows and at cliff
// feet): drives edge wear (pale, scuffed lips) and crevice grime.
// Slope picks cliff rock automatically: triplanar flagstone-texture relief, strata bands and
// terrace ledges. Colours come from a TerrainTheme (res://data/terrain/*.tres). Lighting shares the
// PBR light() + drifting cloud shadows of the lit shaders, so terrain sits in the same art style.
render_mode diffuse_burley, specular_schlick_ggx, cull_back;

#include "res://shaders/cloud.gdshaderinc"
#include "res://shaders/style/corruption.gdshaderinc"

uniform vec3 ground_a : source_color = vec3(0.16, 0.1, 0.085);
uniform vec3 ground_b : source_color = vec3(0.09, 0.06, 0.055);
uniform vec3 path_color : source_color = vec3(0.2, 0.17, 0.15);
uniform vec3 path_joint : source_color = vec3(0.04, 0.03, 0.03);
uniform vec3 cliff_a : source_color = vec3(0.13, 0.1, 0.095);
uniform vec3 cliff_b : source_color = vec3(0.25, 0.12, 0.08);
uniform vec3 accent : source_color = vec3(1.0, 0.3, 0.06);
uniform float accent_energy = 2.2;
uniform float accent_amount : hint_range(0.0, 1.0) = 0.35;
uniform vec3 shore : source_color = vec3(0.05, 0.02, 0.02);
uniform vec3 shore_glow : source_color = vec3(1.0, 0.25, 0.05);
uniform float shore_glow_energy = 1.5;
uniform float path_paved : hint_range(0.0, 1.0) = 0.0;
// Accent cracks are metallic gold (heaven) instead of glowing embers when > 0.5.
uniform float accent_metal : hint_range(0.0, 1.0) = 0.0;
uniform float liquid_level = -0.45;
uniform float bump_strength = 1.0;
// Contrast of the soil grit / grass-blade detail (0 = smooth, 1 = very grainy).
uniform float ground_grain : hint_range(0.0, 1.0) = 0.7;
// Scales the Corruption blight on this terrain (1 = as the art-style library intends).
uniform float corruption_strength : hint_range(0.0, 2.0) = 1.0;
// Path decals: worn centre, pebbles, cracked / missing flagstones and inlaid rosettes (0 = off).
uniform float path_wear : hint_range(0.0, 1.0) = 1.0;
// Rosette inlay colour on paved paths (gold in heaven, hellstone in hell).
uniform vec3 inlay_color : source_color = vec3(0.83, 0.66, 0.3);
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D stone_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;

varying vec3 world_pos;
varying vec3 world_nrm;
varying vec4 splat;
varying float convex;
varying float cloud;

#include "res://shaders/lit_light.gdshaderinc"

float t_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// x = distance to the nearest Voronoi edge, y = cell hash
vec2 t_voronoi(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 9.0;
	float d2 = 9.0;
	vec2 id = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(t_hash(i + g), t_hash(i + g + 7.7));
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
	return vec2(d2 - d1, t_hash(id));
}

// Triplanar height (stone_tex.b) around world position, weights from the world normal.
float tri_height(vec3 p, vec3 n, float scale) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= max(w.x + w.y + w.z, 1e-4);
	float a = texture(stone_tex, p.zy * scale).b;
	float b = texture(stone_tex, p.xz * scale).b;
	float c = texture(stone_tex, p.xy * scale).b;
	return a * w.x + b * w.y + c * w.z;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	splat = COLOR;
	convex = UV.x;
}

void fragment() {
	vec2 p = world_pos.xz;
	vec3 wn = normalize(world_nrm);
	vec4 macro = texture(noise_tex, p * 0.011);
	vec4 macro2 = texture(noise_tex, p * 0.047 + 0.31);

	// ---- ground: two-tone soil with grit detail
	vec3 soil = texture(soil_tex, p / 2.4).rgb;
	float grit = soil.b;
	vec3 col = mix(ground_a, ground_b, smoothstep(0.3, 0.7, macro.r * 0.7 + macro2.g * 0.3));
	// pale dusty drifts (ash in hell, pollen-gold dust in heaven) in mid-scale patches
	float drift = smoothstep(0.55, 0.8, macro2.r * 0.7 + macro.g * 0.3);
	float lum = dot(ground_a, vec3(0.299, 0.587, 0.114));
	col = mix(col, mix(ground_a, vec3(lum), 0.5) * 1.45, drift * 0.6);
	col *= 1.0 - ground_grain * 0.5 + ground_grain * grit;
	float height = grit * 0.4;
	float rough = 0.92;
	float metal = 0.0;
	vec3 emit = vec3(0.0);

	// ---- paths
	float path = smoothstep(0.15, 0.6, splat.r + (macro2.b - 0.5) * 0.3);
	if (path > 0.0) {
		vec3 pc = path_color * (0.85 + 0.3 * macro2.r);
		float ph = 0.5;
		if (path_paved > 0.0) {
			// running-bond flagstones, 1.2 x 0.8 m
			vec2 q = p / vec2(1.2, 0.8);
			q.x += floor(q.y) * 0.5;
			vec2 f = fract(q);
			vec2 id = floor(q);
			float edge = min(min(f.x, 1.0 - f.x) * 1.2, min(f.y, 1.0 - f.y) * 0.8);
			float joint = 1.0 - smoothstep(0.015, 0.05, edge);
			float tint = t_hash(id);
			vec3 stone = pc * (0.85 + 0.3 * tint) * (0.85 + 0.3 * texture(stone_tex, p / 1.6 + id * 0.37).b);
			stone = mix(stone, path_joint, joint);
			// decals: a few cracked stones, some missing ones (ground and grass show through), moss
			// creeping along the joints near the path edges
			float broken = step(0.93, t_hash(id + 7.1)) * path_wear;
			float crack_l = abs(dot(f - 0.5, normalize(vec2(t_hash(id) - 0.5, 0.6))));
			stone = mix(stone, path_joint, (1.0 - smoothstep(0.004, 0.02, crack_l)) * step(0.8, t_hash(id + 3.3)) * path_wear);
			float missing = step(0.975, t_hash(id + 11.9)) * path_wear;
			stone = mix(stone, col * 0.8, missing);
			float edge_moss = (1.0 - smoothstep(0.4, 0.9, splat.r)) * joint * path_wear;
			stone = mix(stone, ground_a * 0.7, edge_moss * 0.8);
			// inlaid rosettes on a 9 m grid (only where they land on the paving)
			vec2 rc = (floor(p / 9.0) + 0.5) * 9.0;
			float rr = length(p - rc);
			float ang = atan(p.y - rc.y, p.x - rc.x);
			float ring = 1.0 - smoothstep(0.03, 0.06, abs(rr - 0.75));
			float petals = (1.0 - smoothstep(0.0, 0.05, abs(rr - 0.45 - 0.2 * abs(sin(ang * 4.0))))) * step(rr, 0.7);
			float rosette = max(ring, petals) * step(0.5, path) * path_wear;
			stone = mix(stone, inlay_color, rosette);
			metal = mix(metal, accent_metal * 0.9, rosette);
			pc = mix(pc, stone, path_paved);
			ph = mix(ph, 0.6 - joint * 0.5 - broken * 0.2 - missing * 0.4, path_paved);
			rough = mix(rough, 0.6 + joint * 0.3 - rosette * 0.35, path * path_paved);
		} else {
			// beaten earth: a lighter worn centre, darker damp verges, pebbles and scuffs
			float centre = smoothstep(0.6, 0.95, splat.r);
			pc *= 1.0 + 0.18 * centre * path_wear - 0.15 * (1.0 - centre);
			vec2 pv = t_voronoi(p * 3.1);
			float pebble = (1.0 - smoothstep(0.08, 0.2, 1.0 - pv.x * 4.0)) * step(0.82, pv.y) * path_wear;
			pc = mix(pc, path_color * 1.5 * (0.8 + 0.4 * pv.y), pebble);
			ph += pebble * 0.4;
			float scuff = smoothstep(0.55, 0.75, texture(noise_tex, p * 0.21 + 0.6).b) * centre * path_wear;
			pc *= 1.0 - scuff * 0.12;
		}
		col = mix(col, pc, path);
		height = mix(height, ph, path);
	}

	// ---- cliffs (slope), strata bands and ledges
	float slope = 1.0 - smoothstep(0.5, 0.82, wn.y);
	// two scales of triplanar relief: big blocks + fine grain
	float rock_h = tri_height(world_pos, wn, 0.32) * 0.65 + tri_height(world_pos * 2.7 + 13.0, wn, 0.32) * 0.35;
	// strata: layered beds warped by noise, each bed its own tone, thin dark bedding seams between
	float bed_y = world_pos.y * 1.3 + macro.g * 2.5 + macro2.b * 0.8;
	float bed = fract(bed_y);
	float bed_id = floor(bed_y);
	float strata = 0.5 + 0.5 * sin(bed_id * 12.9898) * 0.6 + rock_h * 0.4;
	float seam = 1.0 - smoothstep(0.0, 0.08, min(bed, 1.0 - bed));
	// vertical joints / fractures
	vec2 vf = t_voronoi(vec2((world_pos.x + world_pos.z) * 0.9, world_pos.y * 0.35));
	float fracture = 1.0 - smoothstep(0.02, 0.07, vf.x);
	vec3 rock = mix(cliff_a, cliff_b, smoothstep(0.2, 0.85, strata));
	rock *= 0.7 + 0.5 * rock_h;
	rock *= 1.0 - 0.45 * max(seam * 0.8, fracture);
	// streaks of grime washed down the faces
	float streak = texture(noise_tex, vec2((world_pos.x + world_pos.z) * 0.35, world_pos.y * 0.04)).a;
	rock *= 1.0 - 0.25 * smoothstep(0.5, 0.8, streak);
	// flat ledges on top of cliffs/outcrops keep some ground colour, dusted darker
	float high_flat = (1.0 - splat.a) * (1.0 - slope);
	vec3 ledge = mix(col, rock, 0.55) * 0.85;
	col = mix(col, ledge, high_flat);
	col = mix(col, rock, slope);
	height = mix(height, rock_h - (seam + fracture) * 0.4 * slope, max(slope, high_flat * 0.6));
	rough = mix(rough, 0.85, slope);
	// edge wear: rims and ridges are scuffed pale and dusty; hollows and cliff feet collect grime
	float lip = smoothstep(0.02, 0.18, convex);
	float hollow = smoothstep(0.03, 0.25, -convex);
	vec3 worn = mix(col, vec3(dot(col, vec3(0.333))), 0.35) * 1.35 + 0.03;
	col = mix(col, worn, lip * 0.7);
	rough = mix(rough, 0.98, lip * 0.5);
	col *= 1.0 - hollow * 0.35;

	// ---- accent cracks (ember veins in hell, gold veins in heaven)
	vec2 v = t_voronoi(p * 0.42 + macro.b * 1.5);
	float crack_w = 0.012 + 0.03 * macro2.a * macro2.a;
	float crack = 1.0 - smoothstep(crack_w * 0.35, crack_w, v.x);
	// sparse patches: the mask only opens where both the macro field and the baked accent agree
	float mask = smoothstep(1.0 - accent_amount, 1.0 - accent_amount + 0.12, macro.a * 0.5 + splat.g * 0.5);
	crack *= mask * (1.0 - path * 0.8);
	// cliff fissures too
	vec2 v2 = t_voronoi(vec2(p.x + p.y, world_pos.y * 1.6) * 0.6);
	crack = max(crack, (1.0 - smoothstep(0.01, 0.04, v2.x)) * slope * mask * 0.8);
	float pulse = 0.8 + 0.2 * sin(TIME * 1.3 + macro.r * 12.0);
	if (accent_metal > 0.5) {
		col = mix(col, accent, crack);
		metal = mix(metal, 0.95, crack);
		rough = mix(rough, 0.3, crack);
	} else {
		col = mix(col, accent * 0.15, crack);
		// hotter (brighter, wider glow) in the middle of a patch, dull at its fringe
		emit += accent * accent_energy * crack * pulse * (0.35 + 0.65 * mask * mask);
	}
	height -= crack * 0.3;

	// ---- shore: scorched / wet / gilded banks, hot glow right at the liquid line
	float sh = clamp(splat.b, 0.0, 1.0);
	col = mix(col, shore, smoothstep(0.1, 0.8, sh));
	float near = smoothstep(0.55, 1.0, sh) * smoothstep(liquid_level + 0.6, liquid_level, world_pos.y);
	emit += shore_glow * shore_glow_energy * near * pulse;
	rough = mix(rough, 0.55, sh * 0.5);

	// ---- demonic blight around / behind the player (res://shaders/style/corruption.gdshaderinc)
	float crp = clamp(corruption_at(world_pos) * corruption_strength, 0.0, 1.0);
	corruption_blight(crp, world_pos, col, rough, emit);
	metal *= 1.0 - crp;

	// ---- bump from the combined height (screen-space derivative, no tangents needed)
	vec3 sx = dFdx(VERTEX);
	vec3 sy = dFdy(VERTEX);
	vec3 r1 = cross(sy, NORMAL);
	vec3 r2 = cross(NORMAL, sx);
	float det = dot(sx, r1);
	float h = height * 0.03 * bump_strength;
	vec3 grad = sign(det) * (dFdx(h) * r1 + dFdy(h) * r2);
	NORMAL = normalize(abs(det) * NORMAL - grad);

	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.05, 1.0);
	METALLIC = metal;
	EMISSION = emit;
	AO = mix(1.0, 0.6 + 0.4 * height, 0.6) * (1.0 - hollow * 0.3);
	AO_LIGHT_AFFECT = 0.2;
	cloud = cloud_light(world_pos, TIME);
}
