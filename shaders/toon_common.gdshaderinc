// Shared body of the legacy "toon" shaders (toon.gdshader / toon_static.gdshader).
// SINBOUND no longer uses cel shading: anything still built with Toon.* during the transition is
// rendered with the same physically lit look as lit_common (muted / desaturated albedo, GGX, cloud
// shadows, no bands, no outlines), so old models don't break the art direction.
// Defines before including:
//   FLASHABLE      -> `instance uniform float flash` (white hit-flash, characters)
//   OCCLUDER_FADE  -> dithered see-through when the mesh is between the camera and `fade_focus`

render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/cloud.gdshaderinc"

uniform vec4 albedo : source_color = vec4(1.0);
// Kept for API compatibility with Toon.material(); `gloss` lowers roughness.
uniform float gloss = 0.0;
// How much the old pastel colors are muted toward the dark-fantasy palette.
uniform float desaturate : hint_range(0.0, 1.0) = 0.45;
uniform float darken : hint_range(0.0, 1.0) = 0.3;

#ifdef FLASHABLE
instance uniform float flash = 0.0;
#endif

#ifdef OCCLUDER_FADE
uniform vec3 fade_focus = vec3(0.0, -10000.0, 0.0);
uniform float fade_radius = 0.07;
#endif

varying vec3 world_pos;
varying float cloud;

#include "res://shaders/lit_light.gdshaderinc"

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float fl = 0.0;
#ifdef FLASHABLE
	fl = flash;
#endif
#ifdef OCCLUDER_FADE
	if (PROJECTION_MATRIX[3][3] < 0.5 && world_pos.y > 0.7) {
		vec3 fv = (VIEW_MATRIX * vec4(fade_focus + vec3(0.0, 0.7, 0.0), 1.0)).xyz;
		float depth = -VERTEX.z;
		if (fv.z < 0.0 && depth < -fv.z - 0.8) {
			float d = length(VERTEX.xy / depth - fv.xy / -fv.z);
			float hole = 1.0 - smoothstep(fade_radius * 0.5, fade_radius, d);
			ivec2 q = ivec2(FRAGCOORD.xy) % 4;
			int idx = q.x + q.y * 4;
			float bayer[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
			if ((bayer[idx] + 0.5) / 16.0 < hole * 0.75) {
				discard;
			}
		}
	}
#endif
	vec3 c = albedo.rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(l), desaturate) * (1.0 - darken);
	ALBEDO = mix(c, vec3(1.0, 0.96, 0.9), fl * 0.7);
	ROUGHNESS = mix(0.8, 0.35, clamp(gloss, 0.0, 1.0));
	EMISSION = vec3(1.0, 0.85, 0.6) * fl * 1.5;
	cloud = cloud_light(world_pos, TIME);
}
