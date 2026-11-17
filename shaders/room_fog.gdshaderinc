// CameraFogRange's linear fog on the view depth, toward CameraFogColor (raw sRGB values). A feed camera
// (SecurityCam.FEED_LAYER, layer 22, in its visible layers) gets none: the original never gives sc\Cam a CameraFogMode.
// Helper functions cannot read CAMERA_VISIBLE_LAYERS, so the caller passes it in.
global uniform vec2 room_fog_range;
global uniform vec3 room_fog_color;

float room_fog_amount(vec3 view_vertex, uint camera_layers) {
	if ((camera_layers & 2097152u) != 0u) {
		return 0.0;
	}
	return clamp((-view_vertex.z - room_fog_range.x) / max(room_fog_range.y - room_fog_range.x, 0.001), 0.0, 1.0);
}
