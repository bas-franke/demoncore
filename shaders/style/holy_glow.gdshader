shader_type spatial;
// Holy glow: unshaded, additive, HDR light-body for anything radiant on heaven's side: halos,
// wings of light, angelic shields, auras, sanctified relics, choir wisps. Fresnel-weighted (bright,
// crisp silhouette, softer middle) with slow vertical shimmer bands and a fine sparkle, in sterile
// white-gold. The holy counterpart of hellfire.gdshader. Works on any mesh, no UVs needed.
// Presets: res://assets/materials/holy_*.tres, or ArtStyle.holy_glow() in res://scripts/art_style.gd.
// `fade` is an instance uniform, so one material can be faded per object (spawn-in, death).
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

uniform vec4 core_color : source_color = vec4(1.0, 0.97, 0.88, 1.0);
uniform vec4 edge_color : source_color = vec4(1.0, 0.78, 0.38, 1.0);
uniform float energy = 2.2;
// How much of the glow sits on the silhouette (1) vs. fills the body evenly (0).
uniform float rim_weight : hint_range(0.0, 1.0) = 0.65;
uniform float rim_power = 2.0;
// Moving bands of light (sterile, orderly: they scroll in straight lines, never flicker).
uniform float shimmer : hint_range(0.0, 1.0) = 0.35;
uniform float shimmer_scale = 3.0;
uniform float shimmer_speed = 0.6;
// Tiny twinkling sparkles.
uniform float sparkle : hint_range(0.0, 1.0) = 0.25;
// Soft fade at the mesh's contact with opaque geometry (needs depth texture; 0 = off).
uniform float soft_distance = 0.0;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
instance uniform float fade = 1.0;

varying vec3 obj_pos;

float hg_hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void vertex() {
	obj_pos = VERTEX;
}

void fragment() {
	float ndv = clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	float rim = pow(1.0 - ndv, rim_power);
	float body = mix(1.0, rim * 1.6 + 0.12, rim_weight);
	float band = 0.5 + 0.5 * sin((obj_pos.y + obj_pos.x * 0.25) * shimmer_scale * 6.2832 - TIME * shimmer_speed * 6.2832);
	body *= 1.0 - shimmer + shimmer * (0.4 + 0.9 * band * band);
	vec3 cell = floor(obj_pos * 18.0);
	float sp = step(0.985, hg_hash(cell)) * (0.5 + 0.5 * sin(TIME * 7.0 + hg_hash(cell + 3.0) * 40.0));
	body += sp * sparkle * 3.0;
	vec3 col = mix(core_color.rgb, edge_color.rgb, clamp(rim * 1.3, 0.0, 1.0));
	float soft = 1.0;
	if (soft_distance > 0.0) {
		float d = texture(depth_tex, SCREEN_UV).r;
		vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
		soft = clamp((VERTEX.z - v.z / v.w) / soft_distance, 0.0, 1.0);
	}
	ALBEDO = col * energy * body * fade * soft;
	// Additive: alpha only marks the material as transparent (sorted, no depth write).
	ALPHA = 1.0;
}
