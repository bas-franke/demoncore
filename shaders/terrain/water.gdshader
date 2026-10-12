shader_type spatial;
// Dark still water for rivers / pools / moats (world space). Depth-faded against whatever is
// underneath (banks, sunken props), fresnel sky reflection, slow ripples and a soft foam line at the
// shore. Holy variant: set `tint` pale blue and `glow` > 0 for luminous blessed water.
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 tint : source_color = vec3(0.025, 0.04, 0.045);
uniform vec3 deep : source_color = vec3(0.005, 0.01, 0.012);
uniform vec3 sky : source_color = vec3(0.3, 0.34, 0.38);
uniform vec3 foam : source_color = vec3(0.55, 0.55, 0.5);
uniform float glow = 0.0;
uniform float depth_fade = 1.2;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;

float w_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float w_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(w_hash(i), w_hash(i + vec2(1, 0)), u.x), mix(w_hash(i + vec2(0, 1)), w_hash(i + vec2(1, 1)), u.x), u.y);
}

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float t = TIME;
	// ripple normal from two drifting noise layers
	float e = 0.15;
	float h0 = w_noise(p * 0.9 + t * 0.15) + w_noise(p * 2.3 - t * 0.21) * 0.5;
	float hx = w_noise((p + vec2(e, 0)) * 0.9 + t * 0.15) + w_noise((p + vec2(e, 0)) * 2.3 - t * 0.21) * 0.5;
	float hz = w_noise((p + vec2(0, e)) * 0.9 + t * 0.15) + w_noise((p + vec2(0, e)) * 2.3 - t * 0.21) * 0.5;
	vec3 wn = normalize(vec3(-(hx - h0) / e * 0.08, 1.0, -(hz - h0) / e * 0.08));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);

	// thickness of water in front of the bottom
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	vec4 vpos = INV_PROJECTION_MATRIX * ndc;
	vpos.xyz /= vpos.w;
	float thick = max(VERTEX.z - vpos.z, 0.0);
	float dep = clamp(thick / depth_fade, 0.0, 1.0);

	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	vec3 col = mix(tint, deep, dep);
	col = mix(col, sky, fres * 0.6);
	float shore_line = 1.0 - smoothstep(0.0, 0.25, thick);
	float foam_n = smoothstep(0.45, 0.8, w_noise(p * 4.0 + t * 0.3));
	col = mix(col, foam, shore_line * foam_n * 0.6);
	ALBEDO = col;
	ALPHA = clamp(0.55 + dep * 0.45 + shore_line * foam_n * 0.3, 0.0, 1.0);
	ROUGHNESS = 0.06;
	METALLIC = 0.0;
	SPECULAR = 0.6;
	EMISSION = tint * glow * (0.7 + 0.3 * h0);
}
