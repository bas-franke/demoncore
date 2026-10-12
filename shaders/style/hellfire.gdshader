shader_type spatial;
// Emissive hellfire surface: a dark obsidian / charred crust split by molten cracks that flow
// upward and breathe. The infernal counterpart of holy_glow.gdshader, for anything that belongs to
// the demon side: hellfire weapons, braziers, lava pools, Basecamp Hell props, demon sigil stones.
// Noise is triplanar in object space (no UVs needed, primitives work), so the pattern sticks to the
// mesh when it moves. Lit (PBR crust) with the molten part in EMISSION, HDR-bright so it blooms.
// Presets: res://assets/materials/hellfire_*.tres, or ArtStyle.hellfire() in res://scripts/art_style.gd.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Crust (rock / char) color and roughness.
uniform vec4 crust_color : source_color = vec4(0.07, 0.045, 0.04, 1.0);
uniform float crust_roughness : hint_range(0.0, 1.0) = 0.85;
// Molten ramp: edge of the cracks -> hot middle -> white-gold core.
uniform vec4 edge_color : source_color = vec4(0.55, 0.05, 0.02, 1.0);
uniform vec4 hot_color : source_color = vec4(1.0, 0.3, 0.05, 1.0);
uniform vec4 core_color : source_color = vec4(1.0, 0.78, 0.4, 1.0);
uniform float energy = 3.0;
// 0 = all crust, 1 = all molten. ~0.35 reads as cracked rock with lava veins.
uniform float molten : hint_range(0.0, 1.0) = 0.35;
// Cells per meter (object space) of the crack network.
uniform float crack_scale = 2.2;
// Upward flow speed of the molten pattern (m/s, object space).
uniform float flow_speed = 0.25;
// Breathing pulse amount and rate.
uniform float pulse : hint_range(0.0, 1.0) = 0.3;
uniform float pulse_rate = 1.4;
// Extra heat on the silhouette (fresnel), sells "glowing from within".
uniform float rim_heat : hint_range(0.0, 2.0) = 0.6;
// Hotter toward the bottom (lava pools, brazier bowls) > 0, toward the top < 0.
uniform float heat_gradient : hint_range(-1.0, 1.0) = 0.0;
uniform float gradient_height = 1.0;

varying vec3 obj_pos;
varying vec3 obj_nrm;

float hf_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float hf_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hf_hash(i), hf_hash(i + vec2(1.0, 0.0)), f.x),
		mix(hf_hash(i + vec2(0.0, 1.0)), hf_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// Distance to the nearest Voronoi edge.
float hf_cracks(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(hf_hash(i + g), hf_hash(i + g + vec2(17.17, 3.71)));
			float d = length(g + o - f);
			if (d < d1) {
				d2 = d1;
				d1 = d;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return d2 - d1;
}

// Molten amount 0..1 on one projection plane.
float hf_plane(vec2 p, float t) {
	vec2 w = vec2(hf_noise(p * 0.8 + vec2(0.0, -t * 0.5)), hf_noise(p * 0.8 + vec2(5.2, -t * 0.5)));
	float e = hf_cracks(p * crack_scale + (w - 0.5) * 0.9);
	float width = mix(0.02, 0.45, molten);
	float crack = 1.0 - smoothstep(width * 0.3, width, e);
	float flow = hf_noise(p * 3.0 + vec2(0.0, -t * 2.0)) * 0.6 + hf_noise(p * 7.0 + vec2(2.0, -t * 3.5)) * 0.4;
	return crack * (0.55 + 0.45 * flow);
}

void vertex() {
	obj_pos = VERTEX;
	obj_nrm = NORMAL;
}

void fragment() {
	float t = TIME * flow_speed;
	vec3 w = pow(abs(normalize(obj_nrm)), vec3(4.0));
	w /= max(w.x + w.y + w.z, 1e-4);
	// Scroll "up" (object +Y) on the side planes; drift on the top plane.
	float m = hf_plane(obj_pos.zy + vec2(0.0, -t), TIME * 0.2) * w.x
			+ hf_plane(obj_pos.xz + vec2(t * 0.3, 0.0), TIME * 0.2) * w.y
			+ hf_plane(obj_pos.xy + vec2(0.0, -t), TIME * 0.2) * w.z;
	float grad = clamp(1.0 - obj_pos.y / max(gradient_height, 0.01), 0.0, 1.0);
	m *= 1.0 + heat_gradient * (grad - 0.5) * 1.6;
	float breathe = 1.0 - pulse + pulse * (0.5 + 0.5 * sin(TIME * pulse_rate + obj_pos.x * 1.3 + obj_pos.z));
	m = clamp(m, 0.0, 1.0);
	vec3 molten_col = mix(edge_color.rgb, hot_color.rgb, smoothstep(0.1, 0.55, m));
	molten_col = mix(molten_col, core_color.rgb, smoothstep(0.6, 0.95, m));
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	// Crust is darkened close to the cracks (scorched rims).
	ALBEDO = mix(crust_color.rgb * (1.0 - 0.4 * smoothstep(0.0, 0.3, m)), molten_col * 0.3, smoothstep(0.3, 0.7, m));
	ROUGHNESS = mix(crust_roughness, 0.4, m);
	EMISSION = molten_col * energy * breathe * (m * m * 1.4 + fres * rim_heat * (0.3 + m));
}
