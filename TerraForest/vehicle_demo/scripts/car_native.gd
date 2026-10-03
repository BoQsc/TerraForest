# SPDX-License-Identifier: 0BSD
extends "res://vehicle_demo/scripts/car.gd"
var driving_policy: RefCounted
var suspension: RefCounted
var visual_damage: RefCounted
func _ready() -> void:
	GDExtensionManager.load_extension("res://addons/vehicle_runtime/vehicle_runtime.gdextension")
	driving_policy=ClassDB.instantiate("NativeDrivingPolicy")
	suspension=ClassDB.instantiate("NativeVehicleSuspension")
	visual_damage=ClassDB.instantiate("NativeVehicleDamage")
	super._ready()
	for ray in wheel_rays: ray.enabled=false # Native pass explicitly updates once.
func _build_dented_mesh(visual: MeshInstance3D,world_point: Vector3,dent_direction: Vector3,radius: float,depth: float) -> ArrayMesh:
	return visual_damage.dent(visual.mesh,visual.global_transform,world_point,dent_direction,radius,depth)
func _update_wheel_contacts() -> void:
	var samples: PackedFloat32Array=suspension.sample_and_apply(self,wheel_rays)
	grounded_wheels=0;loaded_wheels=0
	if samples.size()!=40:
		set_physics_process(false);push_error("Vehicle suspension contacts unavailable");return
	# Temporary compatibility adapter for the original visual/telemetry scripts.
	for i in 4:
		var offset:=i*10
		_contact_active[i]=samples[offset]>0;_load_active[i]=samples[offset+1]>0
		_spring_lengths[i]=samples[offset+2];_normal_forces[i]=samples[offset+3]
		_contact_points[i]=Vector3(samples[offset+4],samples[offset+5],samples[offset+6])
		_contact_normals[i]=Vector3(samples[offset+7],samples[offset+8],samples[offset+9])
		if _contact_active[i]: grounded_wheels+=1
		if _load_active[i]: loaded_wheels+=1
func _apply_suspension_forces() -> void:
	pass # Applied by the native contact pass exactly once per physics tick.
func _apply_vehicle_motion(throttle: float,reverse_brake: float,handbrake: bool,parked: bool,delta: float) -> void:
	handbrake_active=handbrake;drive_force_newtons=0;target_yaw_rate_degrees=0
	if not _normal_mode or handbrake or _physics_override_time>0:
		normal_drive_locked=false
		driving_policy.apply_free(self,_support_normal(),throttle,reverse_brake,handbrake,parked,_has_drive_support())
		return
	_update_drive_speed_state(throttle,reverse_brake,parked,delta)
	target_yaw_rate_degrees=rad_to_deg(driving_policy.apply_grounded(self,_support_normal(),_drive_speed))
	normal_drive_locked=true
func _apply_body_stability() -> void:
	roll_degrees=driving_policy.stabilize(self,_support_normal(),_has_drive_support(),loaded_wheels)
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
