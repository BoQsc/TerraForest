class_name VehicleGroundDebugTrace
extends Node3D

# Persistent ground diagnostic for steering/slip analysis.
# Cyan = driven trajectory. Green = chassis heading. Orange = rear-axle velocity (the no-slip reference).
# F4 clears history. F5 toggles recording + visibility.
const CLEAR_KEY: Key = KEY_F4
const TOGGLE_KEY: Key = KEY_F5
const SAMPLE_DISTANCE: float = 0.72
const MAX_CONNECT_DISTANCE: float = 3.0
const MIN_SAMPLE_SPEED: float = 0.8
const MAX_SAMPLES: int = 280
const PAINT_LIFT: float = 0.028
const VECTOR_LIFT: float = 0.007
const PATH_WIDTH: float = 0.055
const VECTOR_LENGTH: float = 1.05
const VECTOR_SHAFT_WIDTH: float = 0.055
const VECTOR_TIP_WIDTH: float = 0.19
const VECTOR_TIP_LENGTH: float = 0.24
const VECTOR_SIDE_OFFSET: float = 0.085

@export var car_path: NodePath = ^"../Car"

@onready var paint_mesh_instance: MeshInstance3D = $PaintMesh

var car: Variant = null
var wheel_rays: Array[RayCast3D] = []
var paint_enabled: bool = true

var _mesh: ImmediateMesh = ImmediateMesh.new()
var _path_material: StandardMaterial3D = StandardMaterial3D.new()
var _forward_material: StandardMaterial3D = StandardMaterial3D.new()
var _velocity_material: StandardMaterial3D = StandardMaterial3D.new()

var _points: Array[Vector3] = []
var _normals: Array[Vector3] = []
var _forward_directions: Array[Vector3] = []
var _velocity_directions: Array[Vector3] = []
var _connect_from_previous: Array[bool] = []

var _has_last_sample: bool = false
var _last_sample_point: Vector3 = Vector3.ZERO
var _clear_was_down: bool = false
var _toggle_was_down: bool = false


func _ready() -> void:
	car = get_node_or_null(car_path)
	if not is_instance_valid(car):
		push_error("DebugGroundPaint car_path does not point to DrivingCar.")
		set_physics_process(false)
		return

	var front_left: RayCast3D = car.get_node_or_null("FrontLeft/Ray") as RayCast3D
	var front_right: RayCast3D = car.get_node_or_null("FrontRight/Ray") as RayCast3D
	var rear_left: RayCast3D = car.get_node_or_null("RearLeft/Ray") as RayCast3D
	var rear_right: RayCast3D = car.get_node_or_null("RearRight/Ray") as RayCast3D
	if is_instance_valid(front_left):
		wheel_rays.append(front_left)
	if is_instance_valid(front_right):
		wheel_rays.append(front_right)
	if is_instance_valid(rear_left):
		wheel_rays.append(rear_left)
	if is_instance_valid(rear_right):
		wheel_rays.append(rear_right)

	if wheel_rays.size() != 4:
		push_error("DebugGroundPaint could not bind all four custom suspension rays.")
		set_physics_process(false)
		return

	_configure_material(_path_material, Color(0.16, 0.78, 1.0, 1.0), Color(0.04, 0.52, 0.95, 1.0))
	_configure_material(_forward_material, Color(0.16, 1.0, 0.28, 1.0), Color(0.08, 0.75, 0.16, 1.0))
	_configure_material(_velocity_material, Color(1.0, 0.42, 0.08, 1.0), Color(0.9, 0.22, 0.03, 1.0))

	paint_mesh_instance.mesh = _mesh
	paint_mesh_instance.visible = true
	print("Ground steering trace enabled: cyan path, green heading, orange rear-axle velocity. F4 clear, F5 toggle.")


func _physics_process(_delta: float) -> void:
	var clear_down: bool = Input.is_key_pressed(CLEAR_KEY)
	if clear_down and not _clear_was_down:
		clear_trace()
	_clear_was_down = clear_down

	var toggle_down: bool = Input.is_key_pressed(TOGGLE_KEY)
	if toggle_down and not _toggle_was_down:
		paint_enabled = not paint_enabled
		paint_mesh_instance.visible = paint_enabled
		print("Ground steering trace: ", "ON" if paint_enabled else "OFF")
	_toggle_was_down = toggle_down

	if paint_enabled:
		_sample_if_needed()


func clear_trace() -> void:
	_points.clear()
	_normals.clear()
	_forward_directions.clear()
	_velocity_directions.clear()
	_connect_from_previous.clear()
	_has_last_sample = false
	_last_sample_point = Vector3.ZERO
	_mesh.clear_surfaces()
	print("Ground steering trace cleared.")


func _sample_if_needed() -> void:
	if not is_instance_valid(car):
		return

	var contact_count: int = 0
	var ground_point: Vector3 = Vector3.ZERO
	var ground_normal: Vector3 = Vector3.ZERO
	for index in wheel_rays.size():
		if car._contact_active[index]:
			ground_point += car._contact_points[index]
			ground_normal += car._contact_normals[index]
			contact_count += 1

	if contact_count < 2:
		return

	ground_point /= float(contact_count)
	ground_normal /= float(contact_count)
	if ground_normal.length_squared() < 0.0001:
		ground_normal = Vector3.UP
	else:
		ground_normal = ground_normal.normalized()

	var ground_velocity: Vector3 = car.get_rear_axle_velocity().slide(ground_normal)
	var ground_speed: float = ground_velocity.length()
	if ground_speed < MIN_SAMPLE_SPEED:
		return

	if _has_last_sample and ground_point.distance_to(_last_sample_point) < SAMPLE_DISTANCE:
		return

	var forward_direction: Vector3 = car.global_transform.basis.z.slide(ground_normal)
	if forward_direction.length_squared() < 0.0001:
		return
	forward_direction = forward_direction.normalized()

	var velocity_direction: Vector3 = ground_velocity / ground_speed
	var connect_to_previous: bool = _has_last_sample and ground_point.distance_to(_last_sample_point) <= MAX_CONNECT_DISTANCE

	_points.append(ground_point)
	_normals.append(ground_normal)
	_forward_directions.append(forward_direction)
	_velocity_directions.append(velocity_direction)
	_connect_from_previous.append(connect_to_previous)

	_last_sample_point = ground_point
	_has_last_sample = true

	while _points.size() > MAX_SAMPLES:
		_points.pop_front()
		_normals.pop_front()
		_forward_directions.pop_front()
		_velocity_directions.pop_front()
		_connect_from_previous.pop_front()
	if not _connect_from_previous.is_empty():
		_connect_from_previous[0] = false

	_rebuild_mesh()


func _rebuild_mesh() -> void:
	_mesh.clear_surfaces()
	var count: int = _points.size()
	if count == 0:
		return

	if count >= 2:
		_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _path_material)
		for index: int in range(1, count):
			if _connect_from_previous[index]:
				_emit_path_segment(index - 1, index)
		_mesh.surface_end()

	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _forward_material)
	for index: int in range(count):
		var normal: Vector3 = _normals[index]
		var heading: Vector3 = _forward_directions[index]
		var lateral: Vector3 = normal.cross(heading)
		if lateral.length_squared() < 0.0001:
			lateral = Vector3.RIGHT
		else:
			lateral = lateral.normalized()
		var origin: Vector3 = _points[index] + normal * (PAINT_LIFT + VECTOR_LIFT) - lateral * VECTOR_SIDE_OFFSET
		_emit_arrow(origin, heading, normal)
	_mesh.surface_end()

	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _velocity_material)
	for index: int in range(count):
		var normal: Vector3 = _normals[index]
		var heading: Vector3 = _forward_directions[index]
		var lateral: Vector3 = normal.cross(heading)
		if lateral.length_squared() < 0.0001:
			lateral = Vector3.RIGHT
		else:
			lateral = lateral.normalized()
		var origin: Vector3 = _points[index] + normal * (PAINT_LIFT + VECTOR_LIFT * 2.0) + lateral * VECTOR_SIDE_OFFSET
		_emit_arrow(origin, _velocity_directions[index], normal)
	_mesh.surface_end()


func _emit_path_segment(previous_index: int, current_index: int) -> void:
	var point_a: Vector3 = _points[previous_index]
	var point_b: Vector3 = _points[current_index]
	var normal_a: Vector3 = _normals[previous_index]
	var normal_b: Vector3 = _normals[current_index]
	var average_normal: Vector3 = normal_a + normal_b
	if average_normal.length_squared() < 0.0001:
		average_normal = Vector3.UP
	else:
		average_normal = average_normal.normalized()

	var direction: Vector3 = (point_b - point_a).slide(average_normal)
	if direction.length_squared() < 0.0001:
		return
	direction = direction.normalized()
	var side: Vector3 = average_normal.cross(direction)
	if side.length_squared() < 0.0001:
		return
	side = side.normalized() * (PATH_WIDTH * 0.5)

	var a_center: Vector3 = point_a + normal_a * PAINT_LIFT
	var b_center: Vector3 = point_b + normal_b * PAINT_LIFT
	var a_left: Vector3 = a_center - side
	var a_right: Vector3 = a_center + side
	var b_left: Vector3 = b_center - side
	var b_right: Vector3 = b_center + side

	_emit_triangle(a_left, a_right, b_right, average_normal)
	_emit_triangle(a_left, b_right, b_left, average_normal)


func _emit_arrow(origin: Vector3, direction: Vector3, normal: Vector3) -> void:
	var tangent_direction: Vector3 = direction.slide(normal)
	if tangent_direction.length_squared() < 0.0001:
		return
	tangent_direction = tangent_direction.normalized()
	var side: Vector3 = normal.cross(tangent_direction)
	if side.length_squared() < 0.0001:
		return
	side = side.normalized()

	var shaft_end: Vector3 = origin + tangent_direction * (VECTOR_LENGTH - VECTOR_TIP_LENGTH)
	var shaft_half: Vector3 = side * (VECTOR_SHAFT_WIDTH * 0.5)
	var shaft_a_left: Vector3 = origin - shaft_half
	var shaft_a_right: Vector3 = origin + shaft_half
	var shaft_b_left: Vector3 = shaft_end - shaft_half
	var shaft_b_right: Vector3 = shaft_end + shaft_half

	_emit_triangle(shaft_a_left, shaft_a_right, shaft_b_right, normal)
	_emit_triangle(shaft_a_left, shaft_b_right, shaft_b_left, normal)

	var tip_half: Vector3 = side * (VECTOR_TIP_WIDTH * 0.5)
	var tip_left: Vector3 = shaft_end - tip_half
	var tip_right: Vector3 = shaft_end + tip_half
	var tip_point: Vector3 = origin + tangent_direction * VECTOR_LENGTH
	_emit_triangle(tip_left, tip_right, tip_point, normal)


func _emit_triangle(a: Vector3, b: Vector3, c: Vector3, normal: Vector3) -> void:
	_mesh.surface_set_normal(normal)
	_mesh.surface_add_vertex(a)
	_mesh.surface_set_normal(normal)
	_mesh.surface_add_vertex(b)
	_mesh.surface_set_normal(normal)
	_mesh.surface_add_vertex(c)


func _configure_material(material: StandardMaterial3D, albedo: Color, emission_color: Color) -> void:
	material.albedo_color = albedo
	material.roughness = 0.55
	material.emission_enabled = true
	material.emission = emission_color
	material.emission_energy_multiplier = 1.35
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
