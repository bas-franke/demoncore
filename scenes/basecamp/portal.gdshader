shader_type spatial;
// Swirling hellgate surface for a QuadMesh filling the gate arch. A spiral of fire twisting into a
// dark core, with a hot rim. Additive, so it reads as light. `charge` (0..1) brightens and spins it
// up when the player steps through.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 fire = vec3(1.6, 0.3, 0.05);
uniform vec3 hot = vec3(2.6, 0.9, 0.3);
uniform vec3 core = vec3(0.25, 0.02, 0.05);
uniform float spin = 0.35;
instance uniform float charge = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	// Elliptical coordinates so the swirl fills the tall arch.
	vec2 p = (UV * 2.0 - 1.0) * vec2(1.0, 1.0);
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	float a = atan(p.y, p.x);
	float t = TIME * spin * (1.0 + charge * 3.0);
	// Spiral arms: angle twisted by radius, broken up by noise.
	float twist = a + 4.0 / (r + 0.25) + t * 6.2831;
	float arms = 0.5 + 0.5 * sin(twist * 3.0);
	float n = vnoise(vec2(twist * 1.3, r * 6.0 - t * 4.0));
	float fireamt = smoothstep(0.35, 1.0, arms * 0.7 + n * 0.6) * smoothstep(1.0, 0.55, r);
	float rim = smoothstep(0.78, 0.97, r) * smoothstep(1.0, 0.95, r);
	float centre = smoothstep(0.45, 0.0, r);
	vec3 col = core * (1.0 - centre) + fire * fireamt + hot * rim * (0.8 + 0.4 * sin(TIME * 3.0 + a * 5.0));
	col += hot * centre * 0.25 * (1.0 + charge * 4.0);
	col *= 1.0 + charge * 1.5;
	ALBEDO = col;
}
