extends RefCounted

const API_VERSION := 1

func accepts(body: Node) -> bool:
	return body is RigidBody3D

func install(_body: RigidBody3D, _world: Node) -> bool:
	return false

func controls(_body: RigidBody3D, _enabled: bool) -> void:
	pass

func restore_parked(body: RigidBody3D, pose: Transform3D) -> void:
	body.global_transform = pose
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.freeze = true
	body.set_physics_process(false)

func can_park(body: RigidBody3D, _frame: int) -> bool:
	return body.sleeping

func bounds(body: RigidBody3D) -> AABB:
	return AABB(body.global_position - Vector3(3.25, 1, 3.25), Vector3(6.5, 3, 6.5))

func collision(body: RigidBody3D) -> CollisionShape3D:
	return body.get_node_or_null("ChassisCollision") as CollisionShape3D

func parked_render_parts(_body: RigidBody3D, original: Array) -> Array:
	return original

func camera_update(_body: RigidBody3D, _camera: Camera3D, _delta: float) -> void:
	pass

func capture_state(_body: RigidBody3D) -> PackedByteArray:
	return PackedByteArray()

func restore_state(_body: RigidBody3D, state: PackedByteArray) -> bool:
	return state.is_empty()

func physics_rate() -> int:
	return 60

func status_text(body: RigidBody3D) -> String:
	return "Driving · %.0f km/h · E exit" % (body.linear_velocity.length()*3.6)

func update_focus(body: RigidBody3D, world: Node) -> void:
	world.terrain.focus=body.global_position
	world.terrain.travel_velocity=body.linear_velocity
