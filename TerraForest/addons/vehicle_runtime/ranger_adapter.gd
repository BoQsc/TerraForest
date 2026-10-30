extends "res://addons/vehicle_runtime/vehicle_adapter.gd"

var follow: RefCounted

func accepts(body: Node) -> bool:
	return super.accepts(body) and body.has_method("bind_streamed_world") and body.has_method("set_controls_enabled")

func install(body: RigidBody3D, world: Node) -> bool:
	for wheel in body.wheel_rays:
		wheel.collision_mask = 7
		wheel.add_exception(body)
	body.bind_streamed_world(world.terrain, world.structures)
	if "vegetation" in world: body.streaming.bind_vegetation(world.vegetation)
	follow = ClassDB.instantiate("NativeVehicleCamera")
	return true

func controls(body: RigidBody3D, enabled: bool) -> void:
	body.set_controls_enabled(enabled)

func restore_parked(body: RigidBody3D, pose: Transform3D) -> void:
	body.restore_parked(pose)

func can_park(body: RigidBody3D, frame: int) -> bool:
	return not body.freeze and body.contact_physics_frame == frame and body.loaded_wheels >= 2 and body._has_drive_support() and body.linear_velocity.length() < .15 and body.angular_velocity.length() < .1

func bounds(body: RigidBody3D) -> AABB:
	return body.driving_policy.travel_bounds(body.global_position, Vector3.ZERO, 1.0 / 120.0)

func camera_update(body: RigidBody3D, camera: Camera3D, delta: float) -> void:
	follow.update(body, camera, delta)

func physics_rate() -> int:
	return 120

func status_text(body: RigidBody3D) -> String:
	return "Waiting for terrain/building collision…" if body.streaming.waiting else super.status_text(body)

func update_focus(_body: RigidBody3D, _world: Node) -> void:
	pass
