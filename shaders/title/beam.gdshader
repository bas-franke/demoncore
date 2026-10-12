shader_type spatial;
// Volumetric-looking light shaft: a quad billboarded around its own long axis (local Y = from the
// far end (UV.y = 1) to the source (UV.y = 0); local X length = width). Additive, soft against
// geometry, fades near the camera, slow dust streaks.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, skip_vertex_transform;
uniform vec4 color : source_color = vec4(1.0, 0.8, 0.45, 1.0);
uniform float intensity = 1.0;
uniform float spread = 1.0;
uniform float edge = 2.0;
uniform float head = 0.12;
uniform float tail = 0.25;
uniform float foot = 0.0;
uniform float streaks = 0.35;
uniform float soft_depth = 6.0;
uniform float near_fade = 20.0;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
instance uniform float seed = 0.0;
instance uniform float fade = 1.0;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 axis = MODEL_MATRIX[1].xyz;
	float w = length(MODEL_MATRIX[0].xyz);
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 center = origin + axis * VERTEX.y;
	vec3 side = normalize(cross(normalize(axis), normalize(cam - center)));
	vec3 world = center + side * VERTEX.x * w * mix(1.0, spread, UV.y);
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	float x = UV.x * 2.0 - 1.0;
	float across = pow(max(1.0 - x * x, 0.0), edge);
	float along = smoothstep(0.0, head, UV.y) * (1.0 - smoothstep(1.0 - tail, 1.0, UV.y));
	float s = 1.0 - streaks + streaks * (0.5 + 0.5 * sin(UV.x * 17.0 + seed * 5.0 + TIME * 0.11)
			* sin(UV.x * 5.3 - seed * 2.0 - TIME * 0.07 + UV.y * 2.0));
	float dust = 0.9 + 0.1 * sin(UV.y * 60.0 - TIME * 0.8 + UV.x * 7.0 + seed);
	float d = texture(depth_texture, SCREEN_UV).r;
	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	float scene_z = -v.z / v.w;
	float soft = clamp((scene_z + VERTEX.z) / soft_depth, 0.0, 1.0);
	float nf = smoothstep(0.0, near_fade, -VERTEX.z);
	float glow = 1.0 + foot * pow(UV.y, 8.0);
	ALBEDO = color.rgb * intensity * glow;
	ALPHA = clamp(across * along * s * dust * soft * nf * fade, 0.0, 1.0);
}
