shader_type spatial;
// Rain streak: draw pass of the Weather rain GPUParticles3D. Each particle is a thin quad,
// billboarded around the fall direction (axial billboard toward the camera) and kept at least ~1.5 px
// wide so streaks don't shimmer away at distance. Additive and faint on their own; drops that fall
// through one of the atmosphere's holy light shafts catch the gold (shaft footprints are fed in by
// weather.gd: xy = ground position, z = width, w = fade).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 base_color : source_color = vec3(0.55, 0.6, 0.68);
uniform float base_intensity = 0.34;
uniform vec3 shaft_color : source_color = vec3(1.0, 0.8, 0.46);
uniform float shaft_intensity = 1.6;
uniform vec3 fall_dir = vec3(0.08, -1.0, 0.04);
uniform float streak_length = 0.9;
uniform float streak_width = 0.034;
uniform float opacity = 1.0;
uniform vec3 sun_down = vec3(0.5, -0.7, 0.3);
uniform vec4 beams[8];

varying float v_lit;
varying float v_alpha;

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	vec3 up = normalize(-fall_dir);
	vec3 to_cam = CAMERA_POSITION_WORLD - center;
	vec3 side = normalize(cross(up, to_cam));
	float dist = length(to_cam);
	float rnd = fract(sin(float(INSTANCE_ID) * 12.9898) * 43758.5453);
	float w = max(streak_width, dist * 0.0013);
	float len = streak_length * (0.7 + 0.6 * rnd);
	vec3 wp = center + side * VERTEX.x * w + up * VERTEX.y * len;
	POSITION = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(wp, 1.0));

	// trace the drop back along the sunlight to the ground and test it against the shaft footprints
	float t = max(center.y, 0.0) / max(-sun_down.y, 0.1);
	vec2 g = center.xz + sun_down.xz * t;
	float lit = 0.0;
	for (int i = 0; i < 8; i++) {
		vec4 b = beams[i];
		if (b.w <= 0.0) {
			continue;
		}
		vec2 d = (g - b.xy) / max(b.z * 0.5, 0.01);
		float a = max(1.0 - dot(d, d), 0.0);
		lit += a * a * b.w;
	}
	v_lit = min(lit, 1.5);
	v_alpha = COLOR.a * (0.5 + 0.5 * rnd);
}

void fragment() {
	float x = abs(UV.x * 2.0 - 1.0);
	float across = 1.0 - smoothstep(0.0, 1.0, x);
	// bright head at the bottom (UV.y = 1), tail fading upward
	float along = smoothstep(0.0, 0.9, UV.y) * (1.0 - smoothstep(0.93, 1.0, UV.y));
	vec3 col = base_color * base_intensity + shaft_color * shaft_intensity * v_lit;
	ALBEDO = col;
	ALPHA = clamp(across * along * v_alpha * opacity, 0.0, 1.0);
}
