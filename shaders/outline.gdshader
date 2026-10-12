shader_type spatial;
// Inverted-hull ink outline, used as `next_pass` of a toon material.
render_mode unshaded, cull_front, depth_draw_opaque;

#include "res://shaders/outline_common.gdshaderinc"
