class_name DrivingGameController
extends Node3D

const STATE_DRIVING: String = "DRIVING"
const STATE_EXITING: String = "EXITING"
const STATE_ON_FOOT: String = "ON_FOOT"
const STATE_ENTERING: String = "ENTERING"
const ENTER_DISTANCE: float = 2.75

@onready var car: Variant = $Car
@onready var character: Variant = $Character
@onready var chase_camera: Variant = $ChaseCamera
@onready var hud: Variant = $HUD

var _e_was_down: bool = false
var _state: String = STATE_DRIVING


func _ready() -> void:
	character.set_active(false)
	car.driver_door_opened.connect(_on_driver_door_opened)
	car.driver_door_closed.connect(_on_driver_door_closed)
	chase_camera.follow_vehicle(car)
	hud.set_mode(STATE_DRIVING)


func _process(_delta: float) -> void:
	var e_down: bool = Input.is_key_pressed(KEY_E)
	if e_down and not _e_was_down:
		if _state == STATE_DRIVING:
			_start_exit_sequence()
		elif _state == STATE_ON_FOOT and _can_enter_vehicle():
			_start_entry_sequence()
	_e_was_down = e_down


func _start_exit_sequence() -> void:
	_state = STATE_EXITING
	car.set_controls_enabled(false)
	hud.set_mode(STATE_EXITING)
	car.open_driver_door()


func _on_driver_door_opened() -> void:
	if _state != STATE_EXITING:
		return

	var spawn_position: Vector3 = _find_character_spawn_position()
	var forward_axis: Vector3 = car.global_transform.basis.z
	forward_axis.y = 0.0
	if forward_axis.length_squared() < 0.0001:
		forward_axis = Vector3.MODEL_FRONT
	else:
		forward_axis = forward_axis.normalized()

	character.global_position = spawn_position
	character.rotation = Vector3(0.0, atan2(forward_axis.x, forward_axis.z), 0.0)
	character.set_active(true)
	chase_camera.follow_character(character)
	_state = STATE_ON_FOOT
	hud.set_mode(STATE_ON_FOOT)


func _start_entry_sequence() -> void:
	_state = STATE_ENTERING
	character.set_active(false)
	chase_camera.follow_vehicle(car)
	hud.set_mode(STATE_ENTERING)
	car.close_driver_door()


func _on_driver_door_closed() -> void:
	if _state != STATE_ENTERING:
		return

	car.set_controls_enabled(true)
	_state = STATE_DRIVING
	hud.set_mode(STATE_DRIVING)


func _can_enter_vehicle() -> bool:
	if not character.active:
		return false
	var entry_position: Vector3 = _find_character_spawn_position()
	var offset: Vector3 = character.global_position - entry_position
	offset.y = 0.0
	return offset.length() <= ENTER_DISTANCE


func _find_character_spawn_position() -> Vector3:
	var side_axis: Vector3 = car.global_transform.basis.x
	side_axis.y = 0.0
	if side_axis.length_squared() < 0.0001:
		side_axis = Vector3.RIGHT
	else:
		side_axis = side_axis.normalized()

	var forward_axis: Vector3 = car.global_transform.basis.z
	forward_axis.y = 0.0
	if forward_axis.length_squared() < 0.0001:
		forward_axis = Vector3.MODEL_FRONT
	else:
		forward_axis = forward_axis.normalized()

	var desired: Vector3 = car.global_position + side_axis * 1.75 + forward_axis * 0.55
	var ray_from: Vector3 = desired + Vector3.UP * 2.5
	var ray_to: Vector3 = desired + Vector3.DOWN * 5.0
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_from, ray_to)
	var exclusions: Array[RID] = [car.get_rid()]
	query.exclude = exclusions
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.has("position"):
		var hit_position: Vector3 = hit["position"]
		return hit_position + Vector3.UP * 0.04

	return desired + Vector3.DOWN * 0.58
