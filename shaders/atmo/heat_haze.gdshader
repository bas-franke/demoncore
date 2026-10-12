shader_type spatial;
// Heat haze: refracts the already-rendered scene behind it with rising, churning noise. Used by
// AtmoHeat as camera-facing puffs (hellfire casts, braziers, the hub bonfire; `billboard` on) and
// by the hub dressing as flat strips over the lava (`billboard` off, noise in world XZ so it never
// stretches). Instance uniform `fade` (0..1) fades each puff in and out. Medium quality and up.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform bool billboard = true;
uniform float strength = 1.0;
uniform float scale = 6.0;
uniform float rise = 1.4;
instance uniform float fade = 1.0;

varying vec3 wpos;

float h_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float h_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h_hash(i), h_hash(i + vec2(1, 0)), u.x), mix(h_hash(i + vec2(0, 1)), h_hash(i + vec2(1, 1)), u.x), u.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (billboard) {
		float s = length(MODEL_MATRIX[0].xyz);
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
		MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(s, 0, 0, 0), vec4(0, s, 0, 0), vec4(0, 0, s, 0), vec4(0, 0, 0, 1));
	}
}

void fragment() {
	float m;
	vec2 p;
	if (billboard) {
		m = 1.0 - smoothstep(0.15, 0.5, length(UV - 0.5));
		p = UV * scale + vec2(0.0, TIME * rise);
	} else {
		vec2 e = min(UV, 1.0 - UV);
		m = smoothstep(0.0, 0.25, e.x) * smoothstep(0.0, 0.25, e.y);
		p = wpos.xz * scale * 0.25 + vec2(TIME * 0.3, TIME * rise * 0.5);
	}
	vec2 n = vec2(h_noise(p), h_noise(p * 1.7 + vec2(3.1, 7.7))) - 0.5;
	float k = m * clamp(fade, 0.0, 1.0) * strength;
	vec2 off = n * 0.012 * k;
	ALBEDO = texture(screen_tex, SCREEN_UV + off).rgb;
	ALPHA = clamp(k * 3.0, 0.0, 1.0);
}
