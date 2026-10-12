// Shared body of lit.gdshader / lit_static.gdshader: physically lit dark-fantasy surface with
// procedural weathering (world-space grime, roughness variation, damp contact darkening near the
// ground, optional moss on upward faces), optional emission and sheen.
// Defines before including:
//   FLASHABLE      -> per-instance `flash` hit-flash uniform (characters)
//   OCCLUDER_FADE  -> dithered see-through hole when the mesh stands between camera and `fade_focus`
//   CORRUPTIBLE    -> withers / chars near the ground inside the demon's blight (corruption.gdshaderinc)
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/cloud.gdshaderinc"
#ifdef CORRUPTIBLE
#include "res://shaders/style/corruption.gdshaderinc"
#endif

uniform vec4 albedo : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.8;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform vec4 emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;
// 0 = clean, 1 = heavily weathered (dark grime in noise patches, rougher).
uniform float grime : hint_range(0.0, 1.0) = 0.35;
// Scale of the weathering noise in world units^-1.
uniform float grime_scale = 2.5;
// Soft back-light sheen (cloth, skin, feathers).
uniform float sheen : hint_range(0.0, 1.0) = 0.0;
// Moss / lichen on upward-facing surfaces (ruins).
uniform float moss : hint_range(0.0, 1.0) = 0.0;
uniform vec4 moss_color : source_color = vec4(0.13, 0.16, 0.07, 1.0);
// Darkening of vertical faces close to the ground (damp stone, contact occlusion).
uniform float contact_dark : hint_range(0.0, 1.0) = 0.35;
// Surface detail (res://assets/textures/surf_<type>.png: R = height, G = roughness variation),
// applied triplanar in object space with screen-space bump. 0 strength = off.
uniform sampler2D detail_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float detail_strength : hint_range(0.0, 2.0) = 0.0;
uniform float detail_scale = 2.0;
uniform float detail_bump = 1.0;
// Baked textures (tools/blender/bake.py -> GLB -> GlbModel -> Art.textured_mat), sampled with UV.
// albedo/emission multiply the colors above; ORM = R ambient occlusion, G roughness, B metallic
// (multiplying roughness/metallic). Off by default: untextured materials never sample them.
uniform bool use_textures = false;
uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap_anisotropic;
uniform sampler2D emission_tex : source_color, hint_default_white, filter_linear_mipmap_anisotropic;
uniform float normal_strength : hint_range(0.0, 2.0) = 1.0;
// 0 when the ORM red channel holds no occlusion.
uniform float ao_strength : hint_range(0.0, 1.0) = 1.0;
#ifdef FLASHABLE
instance uniform float flash = 0.0;
// Dissolve (res://scripts/dissolve.gd): 0 = solid .. 1 = gone; noise-eaten, burning edge of dissolve_color.
instance uniform float dissolve = 0.0;
instance uniform vec4 dissolve_color : source_color = vec4(1.0, 0.85, 0.5, 1.0);
// Faction rim light (ArtStyle.set_rim() in res://scripts/art_style.gd): rgb = color, a = strength.
// Unlit fresnel glow on the silhouette so characters read against the dark ground. 0 = off.
instance uniform vec4 rim_color : source_color = vec4(0.0);
// NOTE: these take instance slots 0..3. Any overlay / next_pass shader drawn on the same mesh
// (outline.gdshader) must put its own instance uniforms at instance_index(4+).
#endif
#ifdef OCCLUDER_FADE
uniform vec3 fade_focus = vec3(0.0, -10000.0, 0.0);
// Radius of the see-through hole, in tangent-of-view-angle units.
uniform float fade_radius = 0.07;
#endif

varying vec3 world_pos;
varying vec3 world_nrm;
varying vec3 obj_pos;
varying vec3 obj_nrm;
varying float cloud;

#define LIT_SHEEN
#include "res://shaders/lit_light.gdshaderinc"

float lit_hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float lit_noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(lit_hash(i + vec3(0, 0, 0)), lit_hash(i + vec3(1, 0, 0)), f.x),
			mix(lit_hash(i + vec3(0, 1, 0)), lit_hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(lit_hash(i + vec3(0, 0, 1)), lit_hash(i + vec3(1, 0, 1)), f.x),
			mix(lit_hash(i + vec3(0, 1, 1)), lit_hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	obj_pos = VERTEX;
	obj_nrm = NORMAL;
}

// Triplanar sample of the surface detail texture in object space.
vec2 lit_detail(vec3 p, vec3 nrm) {
	vec3 w = pow(abs(normalize(nrm)), vec3(4.0));
	w /= max(w.x + w.y + w.z, 1e-4);
	vec2 a = texture(detail_tex, p.yz * detail_scale).rg;
	vec2 b = texture(detail_tex, p.xz * detail_scale).rg;
	vec2 c = texture(detail_tex, p.xy * detail_scale).rg;
	return a * w.x + b * w.y + c * w.z;
}

void fragment() {
#ifdef OCCLUDER_FADE
	// Only for the perspective main camera (directional shadow passes are orthographic).
	if (PROJECTION_MATRIX[3][3] < 0.5 && world_pos.y > 0.7) {
		vec3 fv = (VIEW_MATRIX * vec4(fade_focus + vec3(0.0, 0.7, 0.0), 1.0)).xyz;
		float depth = -VERTEX.z;
		if (fv.z < 0.0 && depth < -fv.z - 0.8) {
			float d = length(VERTEX.xy / depth - fv.xy / -fv.z);
			float hole = 1.0 - smoothstep(fade_radius * 0.5, fade_radius, d);
			ivec2 q = ivec2(FRAGCOORD.xy) % 4;
			int idx = q.x + q.y * 4;
			float bayer[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
			if ((bayer[idx] + 0.5) / 16.0 < hole * 0.75) {
				discard;
			}
		}
	}
#endif
	vec3 base_col = albedo.rgb;
	float base_rough = roughness;
	float base_metal = metallic;
	vec3 base_emit = emission.rgb * emission_energy;
	vec3 nmap = vec3(0.5, 0.5, 1.0);
	float base_ao = 1.0;
	if (use_textures) {
		base_col *= texture(albedo_tex, UV).rgb;
		vec3 orm = texture(orm_tex, UV).rgb;
		base_ao = mix(1.0, orm.r, ao_strength);
		base_rough *= orm.g;
		base_metal *= orm.b;
		base_emit *= texture(emission_tex, UV).rgb;
		nmap = texture(normal_tex, UV).rgb;
	}
	vec3 q = world_pos * grime_scale;
	float n = lit_noise(q) * 0.6 + lit_noise(q * 3.1 + 7.3) * 0.4;
	float dirt = smoothstep(0.4, 0.9, n) * grime;
	float fine = lit_noise(q * 7.0);
	// streaks running down vertical faces (rain-washed grime)
	float streak = lit_noise(vec3(world_pos.x * 9.0, world_pos.y * 0.8, world_pos.z * 9.0));
	vec3 col = base_col * (1.0 - dirt * 0.4) * (0.9 + 0.2 * fine) * (1.0 - grime * 0.18 * streak);
	vec3 wn = normalize(world_nrm);
	// damp / grimy band near the ground on vertical faces
	float side = 1.0 - clamp(wn.y, 0.0, 1.0);
	float low = 1.0 - smoothstep(0.0, 0.7, world_pos.y);
	col *= 1.0 - contact_dark * low * side * (0.6 + 0.4 * n);
	float rough = base_rough + dirt * 0.25 + (n - 0.5) * 0.1;
	// moss on top faces, in noise patches
	if (moss > 0.0) {
		float mn = lit_noise(world_pos * 1.3 + 3.0) * 0.6 + fine * 0.4;
		float m = smoothstep(0.35, 0.85, wn.y) * smoothstep(0.42, 0.62, mn) * moss;
		m = max(m, smoothstep(0.6, 0.75, mn) * low * moss * 0.8);
		col = mix(col, moss_color.rgb * (0.8 + 0.4 * fine), m);
		rough = mix(rough, 1.0, m);
	}
	if (detail_strength > 0.0) {
		vec2 d = lit_detail(obj_pos, obj_nrm);
		float ds = detail_strength;
		col *= mix(1.0 - 0.45 * ds, 1.0 + 0.12 * ds, d.r);
		rough += (d.g - 0.5) * 0.5 * ds;
		// Screen-space bump from the height (no tangents/UVs needed).
		vec3 sx = dFdx(VERTEX);
		vec3 sy = dFdy(VERTEX);
		vec3 r1 = cross(sy, NORMAL);
		vec3 r2 = cross(NORMAL, sx);
		float det = dot(sx, r1);
		float h = d.r * detail_bump * ds * 0.02;
		vec3 grad = sign(det) * (dFdx(h) * r1 + dFdy(h) * r2);
		NORMAL = normalize(abs(det) * NORMAL - grad);
	}
#ifdef CORRUPTIBLE
	// Scenery chars from the ground up inside the blight (up to ~1.5 m, ragged edge).
	vec3 crp_emit = vec3(0.0);
	if (corruption_quality > 1.5) {
		corruption_char(corruption_at(world_pos), world_pos, wn, col, rough, crp_emit);
	}
	base_emit += crp_emit;
#endif
	float fl = 0.0;
#ifdef FLASHABLE
	fl = flash;
#endif
	ALBEDO = mix(col, vec3(1.0, 0.96, 0.9), fl * 0.7);
	ROUGHNESS = clamp(rough, 0.04, 1.0);
	METALLIC = base_metal;
	// Flash / wind-up telegraph emission is capped on already-bright albedo (white robes, marble,
	// gold): they read as "lit up" from the albedo shift alone and would otherwise bloom out
	// (art-style round 3). Dark bodies (demons, steel) keep the full flash.
	float fl_lum = dot(col, vec3(0.299, 0.587, 0.114));
	EMISSION = base_emit + vec3(1.0, 0.85, 0.6) * fl * 1.5 * (1.0 - 0.6 * smoothstep(0.35, 0.8, fl_lum));
#ifdef FLASHABLE
	if (rim_color.a > 0.0) {
		float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
		EMISSION += rim_color.rgb * rim * rim_color.a;
	}
#endif
	// Flat (0.5, 0.5, 1) is an exact no-op, so untextured meshes without tangents are unaffected.
	NORMAL_MAP = nmap;
	NORMAL_MAP_DEPTH = normal_strength;
	AO = base_ao;
	AO_LIGHT_AFFECT = 0.25;
#ifdef FLASHABLE
	if (dissolve > 0.0) {
		float dn = clamp((lit_noise(obj_pos * 5.5) * 0.65 + lit_noise(obj_pos * 16.0 + 3.1) * 0.35 - 0.18) / 0.64, 0.0, 1.0);
		float dd = dn - (dissolve * 1.16 - 0.08);
		if (dd < 0.0) {
			discard;
		}
		float de = 1.0 - smoothstep(0.0, 0.08, dd);
		ALBEDO = mix(ALBEDO, dissolve_color.rgb, de);
		EMISSION += dissolve_color.rgb * (de * de * 10.0 + de * 2.0 + dissolve * 0.6);
	}
#endif
	cloud = cloud_light(world_pos, TIME);
}
