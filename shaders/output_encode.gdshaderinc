// How the Compatibility renderer (the web build) differs from Forward+ for the shaders here, which work in Blitz3D's display
// (sRGB) values. Measured with a grey test texture, a colour uniform and a copied backdrop on each renderer:
//   - the output: Forward+ treats ALBEDO as linear light and encodes it on output; Compatibility writes it as it is and blends
//     the framebuffer's display values, as Blitz3D does -> output_encode / output_display / output_alpha;
//   - a `source_color` texture sample and the screen texture: linear on Forward+, the raw display value on Compatibility
//     -> as_display;
//   - a Color set on a vec4 uniform, with the hint or without it: converted to linear on Forward+ only -> as_display;
//   - a vertex or instance colour: the same raw value on both, so nothing to do.
// A texture sampled without the hint is raw on both (shaders/lightmap.gdshader, entity.gdshaderinc), and sky_box and
// particle_mul write a plain sample to ALBEDO, which is right on both.
// output_compat is 1 on Compatibility (GameState sets it): the shader defines (RENDERER_*) are set in every renderer.
// Includes srgb.gdshaderinc; a shader that includes this must not define to_srgb / from_srgb itself.
#include "res://shaders/srgb.gdshaderinc"

global uniform float output_compat;

// a linear value, as the shaders that do their arithmetic in linear light produce it
vec3 output_encode(vec3 linear) {
	return output_compat > 0.5 ? to_srgb(linear) : linear;
}

// a display value, as the shaders that work in Blitz3D's display values produce it
vec3 output_display(vec3 display) {
	return output_compat > 0.5 ? display : from_srgb(display);
}

// the display value of a source_color texture sample, a Color uniform or the screen texture
vec3 as_display(vec3 hinted) {
	return output_compat > 0.5 ? hinted : to_srgb(hinted);
}

// the alpha that makes the hardware blend come out as the display-space blend of the original
float output_alpha(float alpha) {
	return output_compat > 0.5 ? alpha : 1.0 - pow(1.0 - alpha, 2.2);
}
