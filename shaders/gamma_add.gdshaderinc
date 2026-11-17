// Additive pictures (EntityBlend 3: the light glows and fixtures, cones, sparks, dust, muzzle flashes...). Blitz adds the
// picture's display value to the screen's. Done with the hardware's additive blend so that nothing reads the screen copy
// (Godot takes that copy once per frame, before glass and the like are drawn, so a picture reading it painted a square of the
// glass-free scene over any glass in front). The added amount is the picture's display value converted to linear, which is
// exactly Blitz's sum over a black background and a little less over a bright one.
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 color : source_color = vec4(1.0);
uniform bool additive = true;   // kept so that GammaBlend can set it on either kind
uniform bool billboard = false;
uniform bool single_sided = false;      // a Blitz sprite in free view mode has a front only
uniform float billboard_roll = 0.0;      // radians a billboard is turned in its own plane (a Blitz sprite's roll)
uniform vec2 uv_offset = vec2(0.0);      // PositionTexture: the picture slides (the tesla gate's arc)

vec3 to_srgb(vec3 c) {
	c = max(c, vec3(0.0));
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - vec3(0.055), step(vec3(0.0031308), c));
}

vec3 from_srgb(vec3 c) {
	return mix(c / 12.92, pow((c + vec3(0.055)) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	if (billboard) {
		float roll_cos = cos(billboard_roll);
		float roll_sin = sin(billboard_roll);
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * roll_cos + INV_VIEW_MATRIX[1] * roll_sin, INV_VIEW_MATRIX[1] * roll_cos - INV_VIEW_MATRIX[0] * roll_sin, INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
		MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	}
}

void fragment() {
	if (single_sided && !FRONT_FACING) {
		discard;
	}
	vec4 sample = texture(tex, UV + uv_offset);
	vec3 top = to_srgb(sample.rgb) * to_srgb(color.rgb) * sample.a * color.a;
	ALBEDO = from_srgb(clamp(top, vec3(0.0), vec3(1.0)));
	ALPHA = 1.0;
}
