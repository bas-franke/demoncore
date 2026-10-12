shader_type spatial;
// Lit material for characters and anything that hit-flashes (`flash` instance uniform).
// Static scenery uses lit_static.gdshader (identical look, no instance uniform).
#define FLASHABLE
#include "res://shaders/lit_common.gdshaderinc"
