shader_type spatial;
// Lit material for static scenery: no per-instance uniform (doesn't use the instance buffer) and a
// dithered see-through hole when it stands between the camera and the player (`fade_focus`, set every
// frame by atmosphere.gd on every lit_static material).
#define OCCLUDER_FADE
// Blighted from the ground up where the demon passes (res://shaders/style/corruption.gdshaderinc).
#define CORRUPTIBLE
#include "res://shaders/lit_common.gdshaderinc"
