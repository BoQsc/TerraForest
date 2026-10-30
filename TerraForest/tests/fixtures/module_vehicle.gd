extends "res://addons/vehicle_runtime/vehicle_adapter.gd"

var enabled := false
var charge := 50
var camera_updates := 0

func install(body: RigidBody3D, _world: Node) -> bool:
	body.mass = 120
	return true

func controls(_body: RigidBody3D, value: bool) -> void:
	enabled = value

func capture_state(_body: RigidBody3D) -> PackedByteArray:
	return PackedByteArray([1, charge])

func restore_state(_body: RigidBody3D, state: PackedByteArray) -> bool:
	if state.is_empty(): charge = 50; return true
	if state.size() != 2 or state[0] != 1: return false
	charge = state[1]
	return true

func camera_update(body: RigidBody3D, camera: Camera3D, _delta: float) -> void:
	camera_updates += 1
	camera.global_position = body.global_position + Vector3(0, 3, -5)
	camera.look_at(body.global_position)
