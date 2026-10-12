shader_type spatial;
// Toon shader variant for static decor: no `flash` instance uniform (saves instance-uniform
// buffer slots) and a dithered see-through hole when it stands between the camera and the
// player (see Toon.set_fade_focus()).

#define OCCLUDER_FADE
#include "res://shaders/toon_common.gdshaderinc"
