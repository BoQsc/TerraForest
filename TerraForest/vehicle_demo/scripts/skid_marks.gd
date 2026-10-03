class_name VehicleSkidMarks
extends Node3D

# Gameplay tire marks. These are independent from the cyan/green/orange debug trace.
# A wheel paints only while its contact patch is meaningfully sliding.
const MAX_MARKS: int = 8192
const MIN_GROUND_SPEED: float = 1.0
const MIN_MARK_DISTANCE: float = 0.055
const MAX_CONNECT_DISTANCE: float = 1.35
const SLIP_ANGLE_START_DEG: float = 3.5
const SLIP_ANGLE_FULL_DEG: float = 14.0
const BODY_SLIP_START_DEG: float = 1.5
const BODY_SLIP_FULL_DEG: float = 8.0
const MIN_LATERAL_SPEED: float = 0.25
const MARK_WIDTH_MIN: float = 0.105
const MARK_WIDTH_MAX: float = 0.19
const MARK_THICKNESS: float = 0.005
const MARK_LIFT: float = 0.012

@export var car_path: NodePath = ^"../Car"

var car: Variant = null
var wheel_rays: Array[RayCast3D] = []
var wheel_steer_pivots: Array[Node3D] = []

var _marks_instance: MultiMeshInstance3D
var _multimesh: MultiMesh
var _mark_mesh: BoxMesh
var _mark_material: StandardMaterial3D
var _next_mark_index: int = 0

var _has_last_point: Array[bool] = [false, false, false, false]
var _last_points: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var _last_normals: Array[Vector3] = [Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP]


func _ready() -> void:
	car = get_node_or_null(car_path)
	if not is_instance_valid(car):
		push_error("SkidMarks car_path does not point to DrivingCar.")
		set_physics_process(false)
		return

	_bind_wheel_nodes("FrontLeft")
	_bind_wheel_nodes("FrontRight")
	_bind_wheel_nodes("RearLeft")
	_bind_wheel_nodes("RearRight")
	if wheel_rays.size() != 4 or wheel_steer_pivots.size() != 4:
		push_error("SkidMarks could not bind all four wheel rays/steer pivots.")
		set_physics_process(false)
		return

	_mark_material = StandardMaterial3D.new()
	_mark_material.albedo_color = Color(0.025, 0.024, 0.022, 1.0)
	_mark_material.roughness = 0.98
	_mark_material.metallic = 0.0
	_mark_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	_mark_mesh = BoxMesh.new()
	_mark_mesh.size = Vector3.ONE
	_mark_mesh.material = _mark_material

	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.mesh = _mark_mesh
	_multimesh.instance_count = MAX_MARKS
	_multimesh.visible_instance_count = MAX_MARKS

	var hidden_basis: Basis = Basis(
		Vector3(0.0001, 0.0, 0.0),
		Vector3(0.0, 0.0001, 0.0),
		Vector3(0.0, 0.0, 0.0001)
	)
	var hidden_transform: Transform3D = Transform3D(hidden_basis, Vector3(0.0, -10000.0, 0.0))
	for index: int in range(MAX_MARKS):
		_multimesh.set_instance_transform(index, hidden_transform)

	_marks_instance = MultiMeshInstance3D.new()
	_marks_instance.name = "GameplaySkidMarks"
	_marks_instance.multimesh = _multimesh
	_marks_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_marks_instance)

	print("Gameplay skid marks ready: per-wheel slide tracks, ", MAX_MARKS, " recycled segments.")


func _bind_wheel_nodes(wheel_name: String) -> void:
	var ray: RayCast3D = car.get_node_or_null(wheel_name + "/Ray") as RayCast3D
	var steer_pivot: Node3D = car.get_node_or_null(wheel_name + "/Steer") as Node3D
	if is_instance_valid(ray) and is_instance_valid(steer_pivot):
		wheel_rays.append(ray)
		wheel_steer_pivots.append(steer_pivot)


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(car):
		return

	for wheel_index: int in range(4):
		_update_wheel_mark(wheel_index)


func _update_wheel_mark(wheel_index: int) -> void:
	# Normal driving is an exact no-slip bicycle state in the rewritten controller.
	# Roll/pitch suspension motion at an individual contact point must not be
	# misclassified as a gameplay skid. Handbrake / collision recovery remain free.
	if car.normal_drive_locked and not car.handbrake_active:
		_has_last_point[wheel_index] = false
		return

	var ray: RayCast3D = wheel_rays[wheel_index]
	if not car._contact_active[wheel_index]:
		_has_last_point[wheel_index] = false
		return

	var contact_point: Vector3 = car._contact_points[wheel_index]
	var normal: Vector3 = car._contact_normals[wheel_index]
	if normal.length_squared() < 0.0001:
		normal = Vector3.UP
	else:
		normal = normal.normalized()

	var point_velocity: Vector3 = car.get_velocity_at_world_point(contact_point)
	var ground_velocity: Vector3 = point_velocity.slide(normal)
	var ground_speed: float = ground_velocity.length()
	if ground_speed < MIN_GROUND_SPEED:
		_has_last_point[wheel_index] = false
		return

	var wheel_forward: Vector3 = wheel_steer_pivots[wheel_index].global_transform.basis.z.slide(normal)
	if wheel_forward.length_squared() < 0.0001:
		_has_last_point[wheel_index] = false
		return
	wheel_forward = wheel_forward.normalized()

	var wheel_side: Vector3 = normal.cross(wheel_forward)
	if wheel_side.length_squared() < 0.0001:
		_has_last_point[wheel_index] = false
		return
	wheel_side = wheel_side.normalized()

	var longitudinal_speed: float = ground_velocity.dot(wheel_forward)
	var lateral_speed: float = ground_velocity.dot(wheel_side)
	var slip_angle_degrees: float = absf(rad_to_deg(atan2(lateral_speed, maxf(absf(longitudinal_speed), 0.75))))
	var body_slip_degrees: float = absf(car.slip_angle_degrees)

	var wheel_strength: float = clampf(
		(slip_angle_degrees - SLIP_ANGLE_START_DEG) / (SLIP_ANGLE_FULL_DEG - SLIP_ANGLE_START_DEG),
		0.0,
		1.0
	)
	var body_strength: float = clampf(
		(body_slip_degrees - BODY_SLIP_START_DEG) / (BODY_SLIP_FULL_DEG - BODY_SLIP_START_DEG),
		0.0,
		1.0
	)
	var slide_strength: float = maxf(wheel_strength, body_strength)

	# A handbrake slide should visibly paint the rear tires even before the body
	# has accumulated a large slip angle.
	if car.handbrake_active and wheel_index >= 2:
		slide_strength = maxf(slide_strength, 0.82)

	# Suppress harmless steering scrub at very low lateral speed. Body slip and
	# handbrake can still override this because those are real gameplay slides.
	if absf(lateral_speed) < MIN_LATERAL_SPEED and body_strength <= 0.0 and not (car.handbrake_active and wheel_index >= 2):
		slide_strength = 0.0

	if slide_strength <= 0.02:
		_has_last_point[wheel_index] = false
		return

	if not _has_last_point[wheel_index]:
		_last_points[wheel_index] = contact_point
		_last_normals[wheel_index] = normal
		_has_last_point[wheel_index] = true
		return

	var previous_point: Vector3 = _last_points[wheel_index]
	var distance: float = previous_point.distance_to(contact_point)
	if distance > MAX_CONNECT_DISTANCE:
		_last_points[wheel_index] = contact_point
		_last_normals[wheel_index] = normal
		return
	if distance < MIN_MARK_DISTANCE:
		return

	var width: float = lerpf(MARK_WIDTH_MIN, MARK_WIDTH_MAX, slide_strength)
	_add_mark_segment(previous_point, contact_point, _last_normals[wheel_index], normal, width)
	_last_points[wheel_index] = contact_point
	_last_normals[wheel_index] = normal


func _add_mark_segment(point_a: Vector3, point_b: Vector3, normal_a: Vector3, normal_b: Vector3, width: float) -> void:
	var average_normal: Vector3 = normal_a + normal_b
	if average_normal.length_squared() < 0.0001:
		average_normal = Vector3.UP
	else:
		average_normal = average_normal.normalized()

	var direction: Vector3 = (point_b - point_a).slide(average_normal)
	var length: float = direction.length()
	if length < 0.001:
		return
	direction /= length

	var side: Vector3 = average_normal.cross(direction)
	if side.length_squared() < 0.0001:
		return
	side = side.normalized()

	var center: Vector3 = (point_a + point_b) * 0.5 + average_normal * MARK_LIFT
	var basis: Basis = Basis(
		side * width,
		average_normal * MARK_THICKNESS,
		direction * length
	)
	_multimesh.set_instance_transform(_next_mark_index, Transform3D(basis, center))

	_next_mark_index = (_next_mark_index + 1) % MAX_MARKS
