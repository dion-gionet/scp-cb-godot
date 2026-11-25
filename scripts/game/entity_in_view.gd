class_name EntityInView

# Blitz3D's EntityInView: a mesh entity counts while any part of its own (oriented) bounding box is inside the camera's frustum,
# with no occlusion test, so walls do not hide it. A pivot such as an NPC's collider counts by its position alone
# (camera.is_position_in_frustum).
static func mesh(camera: Camera3D, node: MeshInstance3D) -> bool:
	if node == null or node.mesh == null:
		return false
	var xform := node.global_transform
	var box := node.get_aabb()
	var centre := xform * box.get_center()
	var half := box.size * 0.5
	# the box lies wholly outside a plane when its centre is further out than the box reaches along the plane's normal
	for plane in camera.get_frustum():
		var reach := absf(plane.normal.dot(xform.basis.x)) * half.x + absf(plane.normal.dot(xform.basis.y)) * half.y + absf(plane.normal.dot(xform.basis.z)) * half.z
		if plane.distance_to(centre) > reach:
			return false
	return true
