shader_type spatial;
// Procedural fire tongue on a quad: Y-axis billboard (stays upright, turns to face the camera),
// teardrop silhouette eaten by upward-scrolling noise, white-gold core -> orange -> deep red edges.
// Additive and HDR-bright so it blooms. Per-flame variation comes from the world position, so no
// instance uniforms are needed. Quad: size (w, h), centered; the base of the flame is UV.y = 1.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 core_color : source_color = vec4(1.0, 0.86, 0.55, 1.0);
uniform vec4 mid_color : source_color = vec4(1.0, 0.42, 0.08, 1.0);
uniform vec4 edge_color : source_color = vec4(0.55, 0.06, 0.02, 1.0);
uniform float energy = 3.2;
uniform float speed = 1.6;

varying float seed;

float f_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float f_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(f_hash(i), f_hash(i + vec2(1, 0)), u.x), mix(f_hash(i + vec2(0, 1)), f_hash(i + vec2(1, 1)), u.x), u.y);
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	seed = fract(dot(origin, vec3(0.731, 0.297, 0.519)) * 7.13);
	// Y-axis billboard
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 to_cam = cam - origin;
	to_cam.y = 0.0;
	vec3 z = normalize(to_cam + vec3(0.0001, 0.0, 0.0));
	vec3 x = normalize(cross(vec3(0.0, 1.0, 0.0), z));
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	// lean slightly toward the camera so the top-down view still sees a tall flame
	vec3 y = normalize(vec3(0.0, 1.0, 0.0) + z * 0.8);
	vec3 wp = origin + x * VERTEX.x * sx + y * VERTEX.y * sy;
	// sway
	float t = TIME * speed + seed * 20.0;
	wp += x * (sin(t * 2.3) * 0.06 + sin(t * 5.1) * 0.03) * sx * max(VERTEX.y + 0.5, 0.0);
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(wp, 1.0);
}

void fragment() {
	vec2 uv = UV;
	float y = 1.0 - uv.y;	// 0 at the base, 1 at the tip
	float x = (uv.x - 0.5) * 2.0;
	float t = TIME * speed + seed * 20.0;
	float n = f_noise(vec2(uv.x * 4.0 + seed * 9.0, uv.y * 3.0 + t * 1.7)) * 0.65
			+ f_noise(vec2(uv.x * 9.0 - seed * 4.0, uv.y * 7.0 + t * 3.1)) * 0.35;
	// teardrop: wide at the base, narrowing to a tip
	float width = mix(0.8, 0.0, pow(y, 0.7)) * (0.75 + 0.5 * n);
	float shape = 1.0 - smoothstep(width * 0.2, width, abs(x));
	shape *= smoothstep(0.0, 0.08, y);
	float body = shape * smoothstep(1.0, 0.25, y + (n - 0.5) * 0.6);
	float core = body * (1.0 - smoothstep(0.0, 0.55, abs(x) / max(width, 0.01) + y * 0.9));
	vec3 c = mix(edge_color.rgb, mid_color.rgb, smoothstep(0.05, 0.5, body));
	c = mix(c, core_color.rgb, smoothstep(0.1, 0.6, core));
	float flick = 0.85 + 0.15 * sin(t * 11.0 + seed * 6.0);
	ALBEDO = c * energy * flick;
	ALPHA = clamp(body * body * 1.3, 0.0, 1.0);
}
