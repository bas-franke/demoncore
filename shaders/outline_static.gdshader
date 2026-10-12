shader_type spatial;
// Ink outline for static decor (pairs with toon_static.gdshader; supports the occluder fade).
render_mode unshaded, cull_front, depth_draw_opaque;

#define OCCLUDER_FADE
#include "res://shaders/outline_common.gdshaderinc"
