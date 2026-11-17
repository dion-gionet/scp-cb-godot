extends Node
# "room2gw_b" (UpdateEvents.bb): the airlock whose pipes have burst. Within 8 of the room a dead guard lies in the corner (made once),
# steam blows out of Objects[0] (a puff a frame, 10 frames long) and the alarm of the airlocks sounds at the pipes.
# `host` is ambient_events.gd.

var host: Node

func _ev_room2gw_b(rec: Dictionary, st: Dictionary, c: Dictionary) -> void:
	var nodes: Dictionary = host._nodes.get_or_add(c.key, {})
	if c.dist >= 8.0 or c.room == null:
		var alarm: Variant = nodes.get("alarm")
		if alarm != null and is_instance_valid(alarm):
			(alarm as Node).queue_free()
			nodes.erase("alarm")
		return
	if st.s == 0.0:
		st.s = 1.0
		var body_at: Vector3 = c.room.object_point(2)
		nodes["guard"] = host._dead_guard(body_at + Vector3(0.0, 0.5, 0.0), host._yaw_toward(body_at, Vector3(rec.position.x, body_at.y, rec.position.z)), 288.0)
	var steam = host.facility.particles.create(c.room.object_point(0), 6, 0.2, 0.0, 10.0)
	if steam != null:
		steam.speed = 0.01
		steam.dir = Particles.heading(-60.0, float(rec.angle) - 90.0)
		steam.a_change = -0.02
	if not nodes.has("alarm") or not is_instance_valid(nodes["alarm"]):
		nodes["alarm"] = host._loop_at(c.room, "SFX/Alarm/Alarm4.ogg", 5.0)
