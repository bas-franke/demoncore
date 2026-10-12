shader_type spatial;
// Ground foliage (grass, ferns, brambles, flowers, reeds, litter) drawn with MultiMeshes by
// res://scenes/world/foliage.gd. Same physically based light() as the rest of the world
// (lit_light.gdshaderinc, with wrapped diffuse + soft rim = light through thin leaves), plus:
//   * wind: a slow travelling gust wave along `wind_dir` + per-plant sway + fast leaf flutter,
//     weighted by height above the ground (roots stay put, tips swing)
//   * push-away bending around the player / enemies (`pushers`, set every frame)
//   * spawn grow-in (instance uniform `grow`, per chunk) and a shrink fade toward the edge of the
//     streamed area (`fade_center`, `fade_half`) so chunks never pop in view
//   * soft "grassy" shading: normals bent toward +Y, darker roots, lighter tips, per-plant tint
// MultiMesh custom data per instance: rgb = tint multiplier, a = random phase (0..1).
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx, world_vertex_coords;

#include "res://shaders/cloud.gdshaderinc"
#include "res://shaders/style/corruption.gdshaderinc"

uniform vec4 albedo : source_color = vec4(0.3, 0.35, 0.15, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.8;
// Wrapped diffuse + rim (lit_light LIT_SHEEN): light bleeding through thin blades and petals.
uniform float sheen : hint_range(0.0, 1.0) = 0.6;
// Height (m above ground) at which the sway weight reaches 1; 0 sway below the ground.
uniform float sway_height = 0.5;
uniform float sway_strength = 1.0;
uniform float stiffness = 1.6;
// How much shading normals are bent toward +Y (0 = geometric normals).
uniform float normal_up : hint_range(0.0, 1.0) = 0.55;
// Root darkening (fake ground occlusion) and tip brightening.
uniform float base_dark : hint_range(0.0, 1.0) = 0.5;
uniform float tip_light : hint_range(0.0, 1.0) = 0.15;
uniform float ao_height = 0.35;

// --- set by foliage.gd
uniform vec2 wind_dir = vec2(0.87, 0.5);
uniform float wind_strength = 1.0;
// xyz = world position, w = radius (0 = unused slot)
uniform vec4 pushers[8];
uniform vec3 fade_center = vec3(0.0);
// Half extents (x, z) of the visible area around fade_center; plants shrink away past them.
uniform vec2 fade_half = vec2(26.0, 22.0);
uniform float fade_band = 4.0;
instance uniform float grow = 1.0;

varying vec3 world_pos;
varying float cloud;
varying float hgt;
varying vec3 tint;
// Per-plant blight (corruption.gdshaderinc): withers, droops and darkens near the demon.
varying float crp;

#define LIT_SHEEN
#include "res://shaders/lit_light.gdshaderinc"

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float phase = INSTANCE_CUSTOM.a * 6.2832;
	tint = INSTANCE_CUSTOM.rgb;

	// spawn grow-in + edge fade: scale the plant about its root
	vec2 dd = abs(origin.xz - fade_center.xz) - fade_half;
	float edge = max(dd.x, dd.y);
	float f = grow * (1.0 - smoothstep(-fade_band, 0.0, edge));
	crp = corruption_at(origin);
	f *= 1.0 - crp * 0.35;
	VERTEX = origin + (VERTEX - origin) * f;

	float h = max(VERTEX.y - origin.y, 0.0);
	hgt = h;
	float w = pow(clamp(h / sway_height, 0.0, 1.6), stiffness) * sway_strength;

	// wind: gust fronts travelling along the wind + individual sway + flutter
	float t = TIME;
	float along = dot(origin.xz, wind_dir);
	float gust = 0.55 + 0.45 * sin(t * 0.55 - along * 0.13) * sin(t * 0.23 - along * 0.05 + 1.7);
	float sway = sin(t * 1.9 - along * 0.6 + phase) * 0.6 + sin(t * 3.1 + phase * 1.7) * 0.25;
	vec2 perp = vec2(-wind_dir.y, wind_dir.x);
	float flutter = sin(t * 7.3 + dot(VERTEX.xz, vec2(9.1, 7.3)) + phase) * 0.35;
	vec2 offs = wind_dir * (gust * 0.13 + sway * 0.05 * (0.4 + gust)) + perp * (sway * 0.025 + flutter * 0.012);
	offs *= w * wind_strength;

	// push-away bend around characters
	vec2 push = vec2(0.0);
	for (int i = 0; i < 8; i++) {
		vec4 p = pushers[i];
		if (p.w <= 0.0) {
			continue;
		}
		vec2 d = VERTEX.xz - p.xz;
		float dist = length(d);
		float k = 1.0 - smoothstep(p.w * 0.35, p.w, dist);
		push += (d / max(dist, 0.05)) * k * p.w * 0.55;
	}
	float pl = length(push);
	if (pl > 0.6) {
		push *= 0.6 / pl;
	}
	offs += push * min(w, 1.2);

	// keep blade length roughly constant: bending lowers the tip
	float o2 = dot(offs, offs);
	VERTEX.xz += offs;
	VERTEX.y = max(VERTEX.y - o2 * 1.3 / max(h, 0.15) * step(0.001, h), origin.y + h * 0.25);

	NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), normal_up));
	world_pos = VERTEX;
}

void fragment() {
	// cull_disabled flips NORMAL on back faces; plants are shaded with the same (up-bent) normal on
	// both sides, so thin blades light consistently.
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	float ao = mix(1.0 - base_dark, 1.0, smoothstep(0.0, ao_height, hgt));
	float tipl = 1.0 + tip_light * smoothstep(sway_height * 0.4, sway_height * 1.2, hgt);
	vec3 fcol = albedo.rgb * tint * ao * tipl;
	corruption_wither(crp, fcol);
	ALBEDO = fcol;
	ROUGHNESS = roughness;
	SPECULAR = 0.35;
	AO = ao;
	AO_LIGHT_AFFECT = 0.4;
	cloud = cloud_light(world_pos, TIME);
}
