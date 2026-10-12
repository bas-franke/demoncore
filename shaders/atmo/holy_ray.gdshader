shader_type spatial;
// Holy light ray (draw pass of the Atmosphere rig's "Rays" GPUParticles3D). Each particle sits on the
// ground; the quad is rebuilt here as a long shaft along -sun_down (axial billboard toward the camera),
// so the rays always lean with the sun. UV.y = 0 at the sky end, 1 at the ground. Additive, soft at
// the sides, a brighter pool at the ground, soft where it meets geometry, faint dust drifting inside.
// Particle COLOR.a (the process material's fade ramp) fades each ray in and out over its life.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, world_vertex_coords;

uniform vec4 color : source_color = vec4(1.0, 0.85, 0.55, 1.0);
uniform float intensity = 0.3;
uniform vec3 sun_down = vec3(0.5, -0.75, 0.3);
uniform float ray_length = 22.0;
uniform vec2 width_range = vec2(1.0, 3.4);
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;

varying float v_seed;
varying float v_alpha;

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	float rnd = fract(sin(float(INSTANCE_ID) * 12.9898 + 4.1) * 43758.5453);
	v_seed = rnd * 10.0;
	vec3 up = normalize(-sun_down);
	vec3 side = cross(up, CAMERA_POSITION_WORLD - center);
	side = length(side) > 0.0001 ? normalize(side) : vec3(1.0, 0.0, 0.0);
	float w = mix(width_range.x, width_range.y, rnd);
	float len = ray_length * (0.75 + 0.5 * fract(rnd * 7.31));
	// Local quad coords come from UV (VERTEX is already in world space with world_vertex_coords).
	VERTEX = center + side * (UV.x - 0.5) * w + up * (1.0 - UV.y) * len;
	v_alpha = COLOR.a * (0.55 + 0.45 * fract(rnd * 3.77));
}

void fragment() {
	float x = UV.x * 2.0 - 1.0;
	float across = 1.0 - x * x;
	across = across * across * across;
	float along = smoothstep(0.0, 0.6, UV.y) * (1.0 - smoothstep(0.92, 1.0, UV.y));
	along *= 0.55 + 0.45 * UV.y;
	float streak = 0.6 + 0.4 * sin(UV.x * 19.0 + v_seed * 7.0 + TIME * 0.25)
			* sin(UV.x * 6.0 - v_seed * 3.0 - TIME * 0.17);
	float drift = 0.85 + 0.15 * sin(UV.y * 40.0 - TIME * 1.3 + UV.x * 9.0 + v_seed);
	float d = texture(depth_texture, SCREEN_UV).r;
	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	float scene_depth = -v.z / v.w;
	float soft = clamp((scene_depth + VERTEX.z) / 3.0, 0.0, 1.0);
	ALBEDO = color.rgb * intensity;
	ALPHA = clamp(across * along * streak * drift * soft * v_alpha, 0.0, 1.0);
}
