class_name SimpleDriverCharacter
extends CharacterBody3D

@export var walk_speed: float = 4.6
@export var backward_speed: float = 3.5
@export var sprint_speed: float = 8.2
@export var sprint_backward_speed: float = 5.2
@export var acceleration: float = 14.0
@export var sprint_acceleration: float = 20.0
@export var turn_speed: float = 10.0

@onready var collision_shape: CollisionShape3D = $CollisionShape3D

var active: bool = false
var gravity_strength: float = 9.8


func _ready() -> void:
	gravity_strength = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))


func set_active(enabled: bool) -> void:
	active = enabled
	visible = enabled
	collision_shape.set_deferred("disabled", not enabled)
	if not enabled:
		velocity = Vector3.ZERO


func _physics_process(delta: float) -> void:
	if not active:
		return

	var input_x: float = 0.0
	var input_z: float = 0.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		input_x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		input_x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		input_z += 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		input_z -= 1.0

	var movement: Vector3 = _camera_relative_direction(input_x, input_z)
	var moving_backward: bool = input_z < -0.001
	var sprinting: bool = Input.is_key_pressed(KEY_SHIFT) and movement.length_squared() > 0.001
	var movement_speed: float = walk_speed
	if moving_backward:
		movement_speed = sprint_backward_speed if sprinting else backward_speed
	elif sprinting:
		movement_speed = sprint_speed
	var target_horizontal: Vector3 = movement * movement_speed
	var horizontal: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	var active_acceleration: float = sprint_acceleration if sprinting else acceleration
	var accel_weight: float = 1.0 - exp(-active_acceleration * delta)
	horizontal = horizontal.lerp(target_horizontal, accel_weight)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	if is_on_floor():
		if velocity.y < 0.0:
			velocity.y = -0.5
	else:
		velocity.y -= gravity_strength * delta

	if movement.length_squared() > 0.001:
		# Backward input is true backpedaling: move opposite the facing direction
		# instead of rotating the character 180 degrees and walking forward.
		var facing_direction: Vector3 = -movement if moving_backward else movement
		var target_yaw: float = atan2(facing_direction.x, facing_direction.z)
		var turn_weight: float = 1.0 - exp(-turn_speed * delta)
		rotation.y = lerp_angle(rotation.y, target_yaw, turn_weight)

	move_and_slide()


func _camera_relative_direction(input_x: float, input_z: float) -> Vector3:
	var raw_input: Vector2 = Vector2(input_x, input_z)
	if raw_input.length_squared() > 1.0:
		raw_input = raw_input.normalized()
	if raw_input.length_squared() < 0.0001:
		return Vector3.ZERO

	var camera: Camera3D = get_viewport().get_camera_3d()
	if not is_instance_valid(camera):
		return Vector3(raw_input.x, 0.0, raw_input.y).normalized()

	var camera_forward: Vector3 = -camera.global_transform.basis.z
	camera_forward.y = 0.0
	if camera_forward.length_squared() < 0.0001:
		camera_forward = Vector3.MODEL_FRONT
	else:
		camera_forward = camera_forward.normalized()

	var camera_right: Vector3 = camera.global_transform.basis.x
	camera_right.y = 0.0
	if camera_right.length_squared() < 0.0001:
		camera_right = Vector3.RIGHT
	else:
		camera_right = camera_right.normalized()

	return (camera_right * raw_input.x + camera_forward * raw_input.y).normalized()
