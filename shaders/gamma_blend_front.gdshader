shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque, fog_disabled;
#define ROOM_FOG
#include "res://shaders/gamma_blend.gdshaderinc"
