shader_type spatial;
// Falling feather (draw pass of the Atmosphere rig's "Feathers" GPUParticles3D). The quad is a single
// feather: a quill along UV.y with an asymmetric, notched vane, cut out with alpha scissor so it sits
// in the opaque pass (cheap, no sorting). The vertex shader rocks and spins it like a falling leaf,
// per particle, so the process material only has to carry it down and sideways. Lit (sun, hellglow,
// fires) with backlight so it glows when the light is behind it; a faint holy emission keeps it
// readable in shadow.
render_mode cull_disabled, depth_draw_opaque;

uniform vec4 color : source_color = vec4(0.92, 0.88, 0.8, 1.0);
uniform vec4 tip_color : source_color = vec4(0.85, 0.78, 0.62, 1.0);
uniform float emission = 0.04;
uniform float flutter = 1.0;

varying float v_rnd;

mat3 rot_axis(vec3 a, float ang) {
	float s = sin(ang);
	float c = cos(ang);
	float oc = 1.0 - c;
	return mat3(
		vec3(oc * a.x * a.x + c, oc * a.x * a.y + a.z * s, oc * a.z * a.x - a.y * s),
		vec3(oc * a.x * a.y - a.z * s, oc * a.y * a.y + c, oc * a.y * a.z + a.x * s),
		vec3(oc * a.z * a.x + a.y * s, oc * a.y * a.z - a.x * s, oc * a.z * a.z + c));
}

void vertex() {
	float id = float(INSTANCE_ID);
	v_rnd = fract(sin(id * 12.9898) * 43758.5453);
	float t = TIME * (0.8 + 0.6 * v_rnd) + v_rnd * 40.0;
	// Slow spin around up, a pendulum rock that keeps the feather mostly flat (seen from above),
	// and a little roll.
	mat3 r = rot_axis(vec3(0.0, 1.0, 0.0), t * 0.7 * (v_rnd > 0.5 ? 1.0 : -1.0))
			* rot_axis(vec3(1.0, 0.0, 0.0), 1.2 + sin(t * 1.9) * 0.6 * flutter)
			* rot_axis(vec3(0.0, 0.0, 1.0), sin(t * 1.3 + 1.0) * 0.5 * flutter);
	VERTEX = r * VERTEX;
	NORMAL = r * NORMAL;
}

void fragment() {
	float y = 1.0 - UV.y;               // 0 at the quill base, 1 at the tip
	float x = UV.x * 2.0 - 1.0;
	float side = x < 0.0 ? 0.8 : 1.0;   // asymmetric vane
	float prof = pow(clamp(sin(3.14159 * clamp((y - 0.12) / 0.88, 0.0, 1.0)), 0.0, 1.0), 0.65);
	prof *= 0.85 * side;
	// Barb ripple plus a few cuts slanting toward the tip.
	float barbs = 0.9 + 0.1 * sin((y * 46.0 - abs(x) * 9.0) + v_rnd * 6.0);
	float notch = smoothstep(0.92, 0.97, fract(y * 5.0 + abs(x) * 1.7 + v_rnd)) * step(0.35, abs(x));
	float vane = step(abs(x), prof * barbs) * (1.0 - notch);
	float quill = step(abs(x), 0.045) * step(y, 0.97);
	float a = max(vane, quill);
	vec3 base = mix(color.rgb, tip_color.rgb, smoothstep(0.55, 1.0, y) * 0.6);
	base *= 0.88 + 0.12 * barbs;
	ALBEDO = mix(base, base * 0.75, quill);
	ROUGHNESS = 0.8;
	SPECULAR = 0.2;
	BACKLIGHT = base * 0.6;
	EMISSION = base * emission;
	ALPHA = a * COLOR.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
