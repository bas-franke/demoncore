shader_type spatial;
// Lightning bolt ribbon (built per strike by the Atmosphere rig as camera-facing quads along a jagged
// path). UV.x runs across the ribbon, UV.y along the bolt (0 = sky). Additive HDR core so it blooms;
// `fade` is driven by the rig from the strike's flicker pulses, COLOR.a thins the side branches.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(0.78, 0.8, 1.0, 1.0);
uniform float energy = 9.0;
uniform float fade = 1.0;

void fragment() {
	float x = abs(UV.x * 2.0 - 1.0);
	float core = 1.0 - smoothstep(0.0, 0.35, x);
	float halo = pow(1.0 - x, 2.0) * 0.35;
	ALBEDO = mix(color.rgb, vec3(1.0), core * 0.7) * energy * (core + halo);
	ALPHA = clamp((core + halo) * fade * COLOR.a, 0.0, 1.0);
}
