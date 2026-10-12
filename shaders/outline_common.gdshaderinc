// Legacy inverted-hull outline body (outline.gdshader / outline_static.gdshader).
// SINBOUND has no ink outlines: the hull is collapsed outside the clip volume in vertex(), so any
// old material that still chains this pass draws nothing and costs no fragments. Uniforms are kept
// so existing scenes / code that set them keep loading.

uniform vec4 color : source_color = vec4(0.17, 0.11, 0.2, 1.0);
uniform float width = 0.04;
uniform vec4 far_color : source_color = vec4(0.42, 0.3, 0.36, 1.0);
uniform float far_start = 21.0;
uniform float far_end = 33.0;
uniform float far_mix = 0.55;

#ifdef OCCLUDER_FADE
uniform vec3 fade_focus = vec3(0.0, -10000.0, 0.0);
uniform float fade_radius = 0.085;
#endif

void vertex() {
	POSITION = vec4(2.0, 2.0, 2.0, 1.0);
}

void fragment() {
	ALBEDO = color.rgb;
}
