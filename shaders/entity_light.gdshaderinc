// The model lighting (entity.gdshaderinc) and the room fog (shaders/lightmap.gdshader), shared by the shaders that need them.
// Blitz3D's CreateLight sets Attenuation1 = 1 / LightRange and leaves the light's own range unlimited, so a light falls off
// as range / distance and never cuts out. The lights are the ones UpdateRoomLights shows (facility_map._update_lights),
// at most 8 like the Direct3D 7 device.
global uniform vec3 entity_ambient;        // AmbientLight / 255
global uniform mat4 entity_light_pos_a;    // columns: xyz world position, w = LightRange (0: no light)
global uniform mat4 entity_light_pos_b;
global uniform mat4 entity_light_col_a;    // columns: rgb LightColor / 255
global uniform mat4 entity_light_col_b;
#include "res://shaders/room_fog.gdshaderinc"

vec3 point_light(vec3 at, vec3 normal, vec4 light, vec4 colour) {
	if (light.w <= 0.0) {
		return vec3(0.0);
	}
	vec3 to_light = light.xyz - at;
	float dist = max(length(to_light), 0.0001);
	return colour.rgb * max(dot(normal, to_light / dist), 0.0) * light.w / dist;
}

// AmbientLight plus every shown light, at a world point with a unit normal
vec3 entity_light_sum(vec3 at, vec3 normal) {
	vec3 sum = entity_ambient;
	for (int i = 0; i < 4; i++) {
		sum += point_light(at, normal, entity_light_pos_a[i], entity_light_col_a[i]);
		sum += point_light(at, normal, entity_light_pos_b[i], entity_light_col_b[i]);
	}
	return sum;
}

