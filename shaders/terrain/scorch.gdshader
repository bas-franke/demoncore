shader_type spatial;
// Burning cloven hoofprints left by the demon (ScorchTrail, scripts/terrain/scorch_trail.gd).
// One flat quad per print in a MultiMesh; INSTANCE_CUSTOM = (spawn time, side -1/+1, seed, strength).
// A print glows ember-hot when fresh, cools to a dull red rim, then leaves a charred mark that
// fades out. `now` is the trail's clock (set by the script every frame).
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, diffuse_burley;

uniform float now = 0.0;
uniform float glow_time = 3.5;
uniform float life = 18.0;
uniform vec3 ember : source_color = vec3(1.0, 0.36, 0.08);
uniform vec3 char_color : source_color = vec3(0.035, 0.025, 0.022);
uniform float energy = 4.0;

varying vec4 data;

void vertex() {
	data = INSTANCE_CUSTOM;
}

float sd_ellipse(vec2 p, vec2 r) {
	return (length(p / r) - 1.0) * min(r.x, r.y);
}

void fragment() {
	float age = now - data.x;
	if (age < 0.0 || age > life) {
		discard;
	}
	// -1..1, +y = toe (PlaneMesh V runs along +Z, the script points -Z... so flip V)
	vec2 uv = vec2(UV.x, 1.0 - UV.y) * 2.0 - 1.0;
	uv.x *= data.y;            // mirror left / right hoof
	// cloven hoof: two toe lobes split by a cleft, a heel pad behind
	float lobe_a = sd_ellipse(uv - vec2(-0.3, 0.25), vec2(0.27, 0.5));
	float lobe_b = sd_ellipse(uv - vec2(0.3, 0.25), vec2(0.27, 0.5));
	float heel = sd_ellipse(uv - vec2(0.0, -0.45), vec2(0.42, 0.28));
	float d = min(min(lobe_a, lobe_b), heel);
	// ragged edge
	float n = fract(sin(dot(floor(uv * 9.0 + data.z * 31.0), vec2(12.9898, 78.233))) * 43758.5453);
	d += (n - 0.5) * 0.05;
	float print_mask = 1.0 - smoothstep(-0.02, 0.03, d);
	float halo = (1.0 - smoothstep(0.0, 0.35, d)) * (1.0 - print_mask);
	float cool = clamp(age / glow_time, 0.0, 1.0);
	float fade = 1.0 - smoothstep(life * 0.55, life, age);
	float heat = (1.0 - cool) * (1.0 - cool);
	// the glow lingers at the rim of the print as it cools
	float rim = smoothstep(-0.12, 0.0, d) * print_mask;
	ALBEDO = mix(char_color, char_color * 2.0, halo);
	EMISSION = ember * energy * data.w * (print_mask * heat + rim * (0.15 + 0.85 * heat) * (1.0 - cool * 0.7) * 0.6);
	ROUGHNESS = 1.0;
	ALPHA = (print_mask * 0.92 + halo * 0.35) * fade * data.w;
}
