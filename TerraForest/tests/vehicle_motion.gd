# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	GDExtensionManager.load_extension("res://addons/vehicle_runtime/vehicle_runtime.gdextension")
	var policy: RefCounted=ClassDB.instantiate("NativeDrivingPolicy")
	var original=load("res://vehicle_demo/scenes/car.tscn").instantiate()
	original.set_script(load("res://vehicle_demo/scripts/car.gd"))
	original.freeze=true;root.add_child(original);original.set_physics_process(false);original.set_process(false)
	var body:=RigidBody3D.new();body.freeze=true;root.add_child(body)
	var error:=0.0
	for tick in 240:
		var up:=Vector3(sin(tick*0.1)*0.3,1,cos(tick*0.13)*0.3).normalized()
		for i in 4:
			original._load_active[i]=true;original._contact_normals[i]=up
		original.rotation=Vector3(0.1,sin(tick*0.03)*PI,0.2)
		body.basis=original.basis
		original._normal_mode=true;original._physics_override_time=0
		original._drive_speed=sin(tick*0.09)*70
		original._update_steering(sin(tick*0.07),1.0/120)
		policy.steering(sin(tick*0.07),absf(original._drive_speed),1.0/120)
		var v:=Vector3(3,2,-4);var w:=Vector3(0.2,0.3,-0.1)
		original.linear_velocity=v;body.linear_velocity=v
		original.angular_velocity=w;body.angular_velocity=w
		original._apply_vehicle_motion(0,0,false,false,1.0/120)
		var yaw: float=policy.apply_grounded(body,up,original._drive_speed)
		error=maxf(error,body.linear_velocity.distance_to(original.linear_velocity))
		error=maxf(error,body.angular_velocity.distance_to(original.angular_velocity))
		error=maxf(error,absf(rad_to_deg(yaw)-original.target_yaw_rate_degrees))
	var passed:=error<0.0001
	print("MOTION_PARITY ",{"passed":passed,"samples":240,"maximum_component_comparison_error":error})
	original.free();body.free();quit(0 if passed else 1)
