shader_type spatial;
// Persistent ground marks (ground_marks.gd). One flat quad per MultiMesh instance, sampled from a
// 4x2 atlas (tools/build_decals.gd). Per instance:
//   INSTANCE_CUSTOM = (cell, spawn time, lifetime, heat)   COLOR = (glow tint rgb, opacity)
// Heat cools exponentially (white-gold -> ember red -> dark); the mark dissolves along a noise
// field over the last ~35% of its life.

render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D data_tex : filter_linear_mipmap_anisotropic, repeat_disable;
uniform float now = 0.0;
uniform float cool_time = 1.5;
// Long, faint after-glow (craters keep smouldering).
uniform float ember_time = 14.0;
uniform float ember_level = 0.12;
uniform vec3 ember_color : source_color = vec3(1.0, 0.22, 0.04);
uniform float glow_energy = 0.9;
uniform float bump = 6.0;

varying vec4 v_custom;
varying vec4 v_tint;

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	v_tint = COLOR;
	float age = now - INSTANCE_CUSTOM.y;
	// Small "stamp" pop when the mark appears.
	float pop = smoothstep(0.0, 0.18, age);
	VERTEX.xz *= mix(0.6, 1.0, pop) + 0.06 * sin(pop * 3.14159);
}

void fragment() {
	vec2 uv = clamp(UV, vec2(0.004), vec2(0.996));
	float cell = v_custom.x;
	vec2 cuv = (uv + vec2(mod(cell, 4.0), floor(cell / 4.0))) / vec2(4.0, 2.0);
	vec4 a = texture(albedo_tex, cuv);
	vec4 d = texture(data_tex, cuv);

	float age = max(now - v_custom.y, 0.0);
	float life = max(v_custom.z, 0.01);
	float t = age / life;
	// Noise dissolve: low-noise texels (edges) go first, centres last.
	float thr = smoothstep(0.62, 1.0, t) * 1.1;
	float keep = smoothstep(thr, thr + 0.12, d.g);
	float fade = keep * (1.0 - smoothstep(0.9, 1.0, t)) * smoothstep(0.0, 0.08, age);

	float heat = v_custom.w * exp(-age / cool_time);
	float ember = v_custom.w * ember_level * exp(-age / ember_time);
	vec3 hot = mix(ember_color, v_tint.rgb, smoothstep(0.15, 0.9, heat));
	hot = mix(hot, vec3(1.0, 0.97, 0.9), smoothstep(0.85, 1.4, heat) * 0.6);
	float glow_amt = d.r * (min(heat * heat, 1.6) + ember);

	ALBEDO = a.rgb;
	ALPHA = clamp(max(a.a * v_tint.a, d.r * min(heat, 1.0)) * fade, 0.0, 1.0);
	EMISSION = hot * glow_amt * glow_energy;
	ROUGHNESS = mix(0.95, 0.28, d.a);
	SPECULAR = mix(0.3, 0.6, d.a);

	// Height -> tangent-space normal.
	vec2 px = vec2(1.0 / 1024.0, 1.0 / 512.0);
	float h = d.b;
	float hx = texture(data_tex, cuv + vec2(px.x, 0.0)).b;
	float hy = texture(data_tex, cuv + vec2(0.0, px.y)).b;
	NORMAL_MAP = normalize(vec3((h - hx) * bump, (h - hy) * bump, 1.0)) * 0.5 + 0.5;
}
