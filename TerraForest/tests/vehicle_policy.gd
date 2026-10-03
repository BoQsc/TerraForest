# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize() -> void:
	GDExtensionManager.load_extension("res://addons/vehicle_runtime/vehicle_runtime.gdextension")
	var native: RefCounted=ClassDB.instantiate("NativeDrivingPolicy")
	var original=load("res://vehicle_demo/scripts/car.gd").new()
	original._normal_mode=true
	var max_steer_error:=0.0;var max_speed_error:=0.0
	for tick in 3600:
		var delta:=1.0/120.0 if tick<1800 else 1.0/60.0
		var input: float=[0.0,1.0,-1.0,0.5,0.0][(tick/120)%5]
		original._drive_speed=sin(tick*0.011)*65
		original._update_steering(input,delta)
		var result: Vector3=native.steering(input,absf(original._drive_speed),delta)
		max_steer_error=maxf(max_steer_error,absf(result.x-original._steering_angle))
		var throttle: float=1.0 if tick%7<4 else 0.0
		var reverse: float=1.0 if tick%9<3 else 0.0
		var parked:=tick%13==0
		original.boost_amount=(tick%101)/100.0
		var speed: Vector2=native.speed(original._drive_speed,throttle,reverse,parked,original.boost_amount,delta)
		original._update_drive_speed_state(throttle,reverse,parked,delta)
		max_speed_error=maxf(max_speed_error,absf(speed.x-original._drive_speed))
	print("POLICY_PARITY ",{"samples":3600,"max_steering_error_rad":max_steer_error,"max_speed_error_mps":max_speed_error})
	var passed:=max_steer_error<0.000001 and max_speed_error<0.00001
	print("PASS original vehicle steering and speed parity" if passed else "FAIL vehicle policy parity")
	original.free();quit(0 if passed else 1)
