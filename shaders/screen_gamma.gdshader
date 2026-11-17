shader_type canvas_item;
// Main.bb's ScreenGamma pass over the finished frame: above 1 the frame is drawn again additively at
// alpha gamma - 1 (c * gamma); below 1 it is multiplied by itself plus a grey of gamma (c * (c + gamma)).

uniform float gamma = 1.0;
uniform sampler2D screen : hint_screen_texture, filter_nearest;

void fragment() {
	vec3 c = texture(screen, SCREEN_UV).rgb;
	vec3 result = gamma > 1.0 ? c * gamma : c * min(c + vec3(gamma), vec3(1.0));
	COLOR = vec4(clamp(result, 0.0, 1.0), 1.0);
}
