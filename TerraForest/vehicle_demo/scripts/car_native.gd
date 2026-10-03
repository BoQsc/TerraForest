# SPDX-License-Identifier: 0BSD
extends "res://vehicle_demo/scripts/car.gd"
var driving_policy: RefCounted
func _ready() -> void:
	GDExtensionManager.load_extension("res://addons/vehicle_runtime/vehicle_runtime.gdextension")
	driving_policy=ClassDB.instantiate("NativeDrivingPolicy")
	super._ready()
func _update_ground_state(handbrake: bool,delta: float) -> void:
	var was_normal:=_normal_mode
	super._update_ground_state(handbrake,delta)
	if not was_normal and _normal_mode: driving_policy.reset()
func reset_vehicle() -> void:
	super.reset_vehicle()
	if driving_policy!=null: driving_policy.reset()
func _update_steering(input_amount: float,delta: float) -> void:
	var speed_for_limit:=absf(_drive_speed) if _normal_mode else linear_velocity.slide(_support_normal()).length()
	var state: Vector3=driving_policy.steering(input_amount,speed_for_limit,delta)
	_steering_angle=state.x;_held_steer_cap=state.y;_steer_fraction=state.z
	_curvature_state=tan(_steering_angle)/WHEELBASE
	steering_degrees=rad_to_deg(_steering_angle);steering_limit_degrees=rad_to_deg(_held_steer_cap)
	commanded_turn_radius=0.0 if absf(_curvature_state)<0.00001 else 1.0/absf(_curvature_state)
	_update_ackermann_angles()
func _update_drive_speed_state(throttle: float,reverse_brake: float,parked: bool,delta: float) -> void:
	var result: Vector2=driving_policy.speed(_drive_speed,throttle,reverse_brake,parked,boost_amount,delta)
	_drive_speed=result.x;drive_force_newtons=result.y*mass
