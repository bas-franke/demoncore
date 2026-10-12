// Drifting cloud shadows (overcast patches sweeping over the world), shared by the lit, toon and
// ground shaders. Driven by world position plus three global shader params set every frame by the
// Atmosphere autoload (per-map presets, docs/team/visuals.md; declared in project.godot):
//   atmo_cloud_strength  how much sunlight a cloud blocks (0 = no cloud shadows .. 1)
//   atmo_cloud_cover     noise threshold (bigger = fewer, smaller clouds)
//   atmo_cloud_offset    accumulated drift (world units), integrated on the CPU so wind changes never
//                        make the clouds jump
// Applied to the directional sun only (see lit_light.gdshaderinc).

global uniform float atmo_cloud_strength;
global uniform float atmo_cloud_cover;
global uniform vec2 atmo_cloud_offset;

const float CLOUD_SCALE = 0.022;	// noise frequency (bigger = smaller clouds)
const float CLOUD_EDGE = 0.22;	// softness of cloud shadow edges
// Kept as macros for the shaders that read them (ground_mist divides by the strength).
#define CLOUD_COVER atmo_cloud_cover
#define CLOUD_STRENGTH max(atmo_cloud_strength, 0.001)

float _cloud_hash(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

float _cloud_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = _cloud_hash(i);
	float b = _cloud_hash(i + vec2(1.0, 0.0));
	float c = _cloud_hash(i + vec2(0.0, 1.0));
	float d = _cloud_hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// 1.0 = full sun, lower = under a cloud. `wp` = world position. `t` (TIME) is unused now that the
// drift comes from atmo_cloud_offset; the parameter stays so callers need no change.
float cloud_light(vec3 wp, float t) {
	vec2 p = (wp.xz - atmo_cloud_offset) * CLOUD_SCALE;
	float n = _cloud_noise(p) * 0.6 + _cloud_noise(p * 2.13 + vec2(5.2, 1.3)) * 0.28
			+ _cloud_noise(p * 4.7 + vec2(-3.1, 7.7)) * 0.12;
	float cover = smoothstep(CLOUD_COVER, CLOUD_COVER + CLOUD_EDGE, n);
	return 1.0 - cover * clamp(atmo_cloud_strength, 0.0, 1.0);
}
