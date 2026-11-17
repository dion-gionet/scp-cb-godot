// Blitz3D alpha-blends display (sRGB) values; the hardware here blends linear ones, where a pale texel at a low alpha
// lifts a dark background about four times as much and black smoke darkens it far less. The screen copy gives what is
// behind, but it holds the opaque scene only: writing the mixed value at full alpha would replace whatever the
// transparent pass has already drawn there. So the hardware still blends, with the cover that makes one layer over the
// copy come out as the display-space mix. The colour stays the picture's own (corrected per channel so that one layer
// is exact), so layers drawn over each other still end at the picture's colour, as they do in the original: a cover
// that only depended on the alpha left dense smoke far too thin. Needs to_srgb and from_srgb.
void display_mix(vec3 behind_linear, vec3 top_srgb, float alpha, out vec3 albedo, out float cover) {
	alpha = clamp(alpha, 0.0, 1.0);
	vec3 top_linear = from_srgb(clamp(top_srgb, vec3(0.0), vec3(1.0)));
	vec3 wanted = from_srgb(mix(to_srgb(behind_linear), top_srgb, alpha));
	vec3 span = behind_linear - top_linear;
	float reach = dot(span, span);
	cover = reach > 0.0000001 ? clamp(dot(behind_linear - wanted, span) / reach, 0.0, 1.0) : alpha;
	// no channel may need a negative colour (dark red over grey: green and blue fall further than red)
	vec3 kept = wanted / max(behind_linear, vec3(0.000001));
	cover = max(cover, 1.0 - min(min(kept.r, kept.g), min(kept.b, 1.0)));
	albedo = cover > 0.0001 ? max((wanted - behind_linear * (1.0 - cover)) / cover, vec3(0.0)) : top_linear;
}
