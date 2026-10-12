shader_type canvas_item;
// Full-screen finishing pass on the tonemapped 3D image (CanvasLayer below the UI):
//   - muted gold / teal split-tone grade (teal-slate shadows, tarnished-gold highlights)
//   - gentle desaturation of the mids, a touch of filmic contrast
//   - very slight chromatic fringe toward the corners
//   - dark, heavy vignette and fine animated film grain
// Game-feel inputs (driven by res://scenes/world/game_feel.gd, all 0 at rest):
//   - low_hp     : 0..1 near-death state (desaturation + crimson vignette, pulsed by heartbeat)
//   - heartbeat  : 0..1 current heartbeat pulse envelope
//   - hit_flash  : 0..1 brief crimson edge flash when the player is struck
//   - chroma_pulse : 0..1 extra chromatic split (kill streaks / big moments)

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
// grading
uniform vec3 shadow_tint : source_color = vec3(0.86, 0.97, 1.02);
uniform vec3 highlight_tint : source_color = vec3(1.07, 1.0, 0.86);
uniform float grade_strength : hint_range(0.0, 1.0) = 0.85;
uniform float saturation : hint_range(0.0, 2.0) = 0.86;
uniform float contrast : hint_range(0.5, 1.5) = 1.08;
uniform float lift : hint_range(-0.1, 0.1) = 0.008;
// chromatic fringe (in UV units at the corners)
uniform float fringe = 0.0012;
// vignette
uniform vec3 vignette_color : source_color = vec3(0.02, 0.018, 0.02);
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.62;
uniform float vignette_inner = 0.38;
uniform float vignette_outer = 1.15;
// grain
uniform float grain : hint_range(0.0, 0.2) = 0.035;
// game feel
uniform vec3 blood_color : source_color = vec3(0.55, 0.02, 0.03);
uniform float low_hp : hint_range(0.0, 1.0) = 0.0;
uniform float heartbeat : hint_range(0.0, 1.0) = 0.0;
uniform float hit_flash : hint_range(0.0, 1.0) = 0.0;
uniform float chroma_pulse : hint_range(0.0, 1.0) = 0.0;
uniform float low_hp_desat : hint_range(0.0, 1.0) = 0.55;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;  // width / height
	vec2 cuv = uv - 0.5;
	float r2 = dot(cuv, cuv);
	// base corner fringe + a radial split that swells on chroma pulses / heartbeats
	float split = fringe * 4.0 * r2 + (chroma_pulse * 0.011 + low_hp * heartbeat * 0.004) * (0.25 + r2 * 2.0);
	vec2 off = cuv * split;
	vec3 c;
	c.r = textureLod(screen_tex, uv + off, 0.0).r;
	c.g = textureLod(screen_tex, uv, 0.0).g;
	c.b = textureLod(screen_tex, uv - off, 0.0).b;

	// split toning
	float lum = dot(c, vec3(0.2126, 0.7152, 0.0722));
	vec3 graded = c * mix(shadow_tint, highlight_tint, smoothstep(0.08, 0.7, lum));
	c = mix(c, graded, grade_strength);
	// saturation (keep strong emissive accents a bit more saturated); drains toward death
	lum = dot(c, vec3(0.2126, 0.7152, 0.0722));
	float sat = mix(saturation, 1.05, smoothstep(0.55, 1.0, lum));
	sat *= 1.0 - low_hp * low_hp_desat;
	c = mix(vec3(lum), c, sat);
	// contrast around a low pivot (dark fantasy: deep blacks, soft highlights)
	c = max((c - 0.18) * contrast + 0.18, vec3(0.0)) + lift;

	// vignette (oval, near-black); tightens a little when near death
	vec2 q = cuv * vec2(aspect, 1.0) / (0.5 * aspect);
	float d = length(q * vec2(0.85, 1.12));
	float v = smoothstep(vignette_inner - low_hp * 0.12, vignette_outer, d);
	c = mix(c, c * vignette_color * 4.0, v * vignette_strength);

	// crimson edge: near-death heartbeat bleed + hit flash
	float edge = smoothstep(0.4, 1.25, d);
	float blood = low_hp * (0.34 + 0.55 * heartbeat) * edge;
	blood += hit_flash * smoothstep(0.25, 1.15, d) * 0.85;
	blood = clamp(blood, 0.0, 0.9);
	vec3 tinted = blood_color * (0.35 + 0.65 * lum) + blood_color * 0.25;
	c = mix(c, max(tinted, c * blood_color * 2.0), blood);

	// film grain, mostly in the mids
	float n = hash12(FRAGCOORD.xy + fract(TIME * 7.13) * vec2(113.0, 271.0)) - 0.5;
	c += n * grain * (0.35 + 0.65 * (1.0 - abs(lum - 0.4) * 1.6));

	COLOR = vec4(c, 1.0);
}
