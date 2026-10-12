shader_type spatial;
// Cel shader for characters and anything that hit-flashes. `flash` is an instance uniform so
// hit-flashes need no material copies:
//   mesh_instance.set_instance_shader_parameter(&"flash", 1.0)
// Static decor uses toon_static.gdshader (same look, no instance uniform, occluder fade).
// Uniforms (albedo, shade_color, gloss, ...) live in toon_common.gdshaderinc.

#define FLASHABLE
#include "res://shaders/toon_common.gdshaderinc"
