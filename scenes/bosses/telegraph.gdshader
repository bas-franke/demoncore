shader_type spatial;
// Ground sigil for the Herald's attacks: a disc sector (or full disc) of radiant gold light with a
// crisp outer ring, an inner ring of slowly turning rune ticks, a faint wash, and a "fill" of light
// that grows from the center as the attack charges. Additive, so it reads as light on dark ground.
// Expects a 2x2 PlaneMesh (local XZ in [-1, 1]); the sector is centered on local -Z.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_add;

uniform vec4 color : source_color = vec4(1.0, 0.85, 0.5, 1.0);
// Half the sector's opening angle in radians (>= PI = full disc).
uniform float half_angle = 3.2;
// 0..1 charge progress, drawn as a brighter area growing outward.
uniform float fill = 0.0;
uniform float alpha = 1.0;
// Border thickness as a fraction of the radius.
uniform float edge = 0.05;
// Overall brightness (values > 1 bloom).
uniform float energy = 1.6;

varying vec2 lp;

void vertex() {
	lp = VERTEX.xz;
}

void fragment() {
	float r = length(lp);
	float ang_signed = atan(lp.x, -lp.y);
	float ang = abs(ang_signed);
	float aa = max(fwidth(r) * 1.5, 0.002);
	float full = step(3.14, half_angle);
	float ang_d = (half_angle - ang) * r;
	float in_disc = 1.0 - smoothstep(1.0 - aa, 1.0, r);
	float in_arc = max(full, smoothstep(-aa, 0.0, ang_d));
	float shape = in_disc * in_arc;
	if (shape <= 0.001) {
		discard;
	}
	// Outer ring + straight sector edges.
	float border = 1.0 - smoothstep(edge - aa, edge, 1.0 - r);
	border = max(border, (1.0 - full) * (1.0 - smoothstep(edge * 0.6 - aa, edge * 0.6, ang_d)));
	// Inner thin ring with turning rune ticks.
	float ring_r = 0.78;
	float inner = 1.0 - smoothstep(0.0, edge * 0.35 + aa, abs(r - ring_r));
	float ticks = step(0.72, fract(ang_signed * 9.549 + TIME * 0.35)) * (1.0 - smoothstep(0.0, edge * 1.4 + aa, abs(r - ring_r + edge * 1.2)));
	// Charge fill: a bright front that sweeps outward, with a soft wash behind it.
	float fill_r = clamp(fill, 0.0, 1.0);
	float filled = 1.0 - smoothstep(fill_r - aa * 2.0, fill_r, r);
	float front = (1.0 - smoothstep(0.0, 0.05 + aa, abs(r - fill_r))) * step(0.001, fill_r);
	float a = 0.07;
	a = max(a, filled * (0.18 + 0.22 * fill_r));
	a = max(a, front * 0.65);
	a = max(a, inner * 0.55);
	a = max(a, ticks * 0.5);
	a = max(a, border * 0.95);
	vec3 c = mix(color.rgb, vec3(1.0, 0.97, 0.9), border * 0.35 + front * 0.4);
	ALBEDO = c * energy;
	ALPHA = clamp(a * shape * alpha, 0.0, 1.0);
}
