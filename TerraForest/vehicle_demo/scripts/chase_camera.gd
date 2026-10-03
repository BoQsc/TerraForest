class_name VehicleChaseCamera
extends Camera3D

@export var target_path: NodePath = ^"../Car"
@export var distance: float = 7.2
@export var height: float = 3.0
@export var look_height: float = 0.65
@export var look_ahead: float = 1.8
@export var follow_speed: float = 7.5

var target: Node3D
var use_speed_fov: bool = true
var base_fov: float = 72.0
var _smoothed_forward: Vector3 = Vector3.MODEL_FRONT


func _ready() -> void:
	target = get_node_or_null(target_path) as Node3D
	current = true
	fov = base_fov
	near = 0.08
	if is_instance_valid(target):
		_snap_to_target()
	else:
		push_error("ChaseCamera target_path does not point to a Node3D.")


func follow_vehicle(vehicle: Node3D) -> void:
	target = vehicle
	distance = 7.2
	height = 3.0
	look_height = 0.65
	look_ahead = 1.8
	follow_speed = 7.5
	base_fov = 72.0
	use_speed_fov = true
	_snap_to_target()


func follow_character(character: Node3D) -> void:
	target = character
	distance = 5.0
	height = 2.5
	look_height = 1.15
	look_ahead = 0.65
	follow_speed = 8.5
	base_fov = 70.0
	use_speed_fov = false
	_snap_to_target()


func _process(delta: float) -> void:
	if not is_instance_valid(target):
		return

	var forward: Vector3 = target.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.001:
		forward = Vector3.MODEL_FRONT
	else:
		forward = forward.normalized()

	# Use one smoothed direction for both camera position and look-at. Previously
	# the position lagged behind while the look direction snapped to the car's new
	# heading, which exaggerated lateral swing during a turn.
	var direction_weight: float = 1.0 - exp(-8.0 * delta)
	_smoothed_forward = _smoothed_forward.lerp(forward, direction_weight)
	if _smoothed_forward.length_squared() < 0.001:
		_smoothed_forward = forward
	else:
		_smoothed_forward = _smoothed_forward.normalized()
	var desired_position: Vector3 = target.global_position - _smoothed_forward * distance + Vector3.UP * height
	var follow_weight: float = 1.0 - exp(-follow_speed * delta)
	global_position = global_position.lerp(desired_position, follow_weight)

	var look_target: Vector3 = target.global_position + _smoothed_forward * look_ahead + Vector3.UP * look_height
	look_at(look_target, Vector3.UP)

	var target_fov: float = base_fov
	if use_speed_fov:
		var speed: float = float(target.get("speed_kph"))
		target_fov += clampf(speed / 140.0, 0.0, 1.0) * 10.0
	fov = lerpf(fov, target_fov, 1.0 - exp(-4.0 * delta))


func _snap_to_target() -> void:
	if not is_instance_valid(target):
		return
	var forward: Vector3 = target.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.001:
		forward = Vector3.MODEL_FRONT
	else:
		forward = forward.normalized()
	_smoothed_forward = forward
	global_position = target.global_position - forward * distance + Vector3.UP * height
	look_at(target.global_position + forward * look_ahead + Vector3.UP * look_height, Vector3.UP)
