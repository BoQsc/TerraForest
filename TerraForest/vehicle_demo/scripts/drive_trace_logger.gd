class_name DriveTraceLogger
extends Node

@export var car_path: NodePath = ^"../Car"

const TRACE_FILE_NAME: String = "DRIVE_TRACE.csv"
const FLUSH_INTERVAL: float = 0.50
const WHEEL_NAMES: Array[String] = ["FrontLeft", "FrontRight", "RearLeft", "RearRight"]

var car: Variant = null
var wheel_rays: Array[RayCast3D] = []
var wheel_steer_pivots: Array[Node3D] = []
var recording: bool = false
var _file: FileAccess
var _elapsed: float = 0.0
var _flush_elapsed: float = 0.0
var _f6_was_down: bool = false
var _f7_was_down: bool = false
var trace_path: String = ""


func _ready() -> void:
	car = get_node_or_null(car_path)
	if not is_instance_valid(car):
		push_error("DriveTraceLogger car_path does not point to DrivingCar.")
		set_physics_process(false)
		return

	for wheel_name: String in WHEEL_NAMES:
		var ray: RayCast3D = car.get_node_or_null(wheel_name + "/Ray") as RayCast3D
		var steer_pivot: Node3D = car.get_node_or_null(wheel_name + "/Steer") as Node3D
		if not is_instance_valid(ray) or not is_instance_valid(steer_pivot):
			push_error("DriveTraceLogger could not bind wheel: " + wheel_name)
			set_physics_process(false)
			return
		wheel_rays.append(ray)
		wheel_steer_pivots.append(steer_pivot)

	trace_path = ProjectSettings.globalize_path("res://vehicle_demo/" + TRACE_FILE_NAME)
	print("Drive telemetry disabled by default. F6 starts a new capture; F7 stops it.")


func _exit_tree() -> void:
	_stop_capture()


func _physics_process(delta: float) -> void:
	var f6_down: bool = Input.is_key_pressed(KEY_F6)
	var f7_down: bool = Input.is_key_pressed(KEY_F7)
	if f6_down and not _f6_was_down:
		_start_new_capture()
	if f7_down and not _f7_was_down:
		_stop_capture()
	_f6_was_down = f6_down
	_f7_was_down = f7_down

	if not recording or not is_instance_valid(_file) or not is_instance_valid(car):
		return

	_elapsed += delta
	_flush_elapsed += delta
	_write_frame()
	if _flush_elapsed >= FLUSH_INTERVAL:
		_file.flush()
		_flush_elapsed = 0.0


func _start_new_capture() -> void:
	_stop_capture()
	_file = FileAccess.open(trace_path, FileAccess.WRITE)
	if not is_instance_valid(_file):
		push_error("Could not open drive trace for writing: " + trace_path)
		return

	_elapsed = 0.0
	_flush_elapsed = 0.0
	recording = true
	_file.store_line("time_s,physics_frame,pos_x,pos_y,pos_z,vel_x,vel_y,vel_z,speed_kph,forward_speed_mps,body_heading_deg,velocity_heading_deg,body_slip_deg,yaw_rate_deg_s,target_yaw_rate_deg_s,steer_input,steer_deg,steer_limit_deg,curvature_1pm,turn_radius_m,throttle,reverse_brake,handbrake,boost,grounded,drive_force_n,fl_slip_deg,fr_slip_deg,rl_slip_deg,rr_slip_deg,fl_lat_mps,fr_lat_mps,rl_lat_mps,rr_lat_mps,fl_skid,fr_skid,rl_skid,rr_skid")
	_file.flush()
	print("Drive trace recording started: ", trace_path)
	print("F6 = restart/clear trace, F7 = stop and flush trace.")


func _stop_capture() -> void:
	if is_instance_valid(_file):
		_file.flush()
		_file.close()
	_file = null
	if recording:
		print("Drive trace saved: ", trace_path)
	recording = false


func _write_frame() -> void:
	var position: Vector3 = car.global_position
	var velocity: Vector3 = car.get_rear_axle_velocity()
	var planar_velocity: Vector3 = velocity
	planar_velocity.y = 0.0

	var body_forward: Vector3 = car.global_transform.basis.z
	body_forward.y = 0.0
	if body_forward.length_squared() < 0.000001:
		body_forward = Vector3.MODEL_FRONT
	else:
		body_forward = body_forward.normalized()

	var body_heading_deg: float = rad_to_deg(atan2(body_forward.x, body_forward.z))
	var velocity_heading_deg: float = body_heading_deg
	if planar_velocity.length_squared() > 0.000001:
		velocity_heading_deg = rad_to_deg(atan2(planar_velocity.x, planar_velocity.z))

	var steer_input: float = 0.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		steer_input += 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		steer_input -= 1.0
	var throttle: float = 1.0 if (Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)) else 0.0
	var reverse_brake: float = 1.0 if (Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)) else 0.0
	var handbrake: bool = Input.is_key_pressed(KEY_SPACE)
	var boost: bool = Input.is_key_pressed(KEY_SHIFT)

	var wheel_slips: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var wheel_lateral_speeds: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var wheel_skids: Array[int] = [0, 0, 0, 0]
	for wheel_index: int in range(4):
		_measure_wheel(wheel_index, wheel_slips, wheel_lateral_speeds, wheel_skids)

	var curvature: float = float(car.get("_curvature_state"))
	var turn_radius: float = float(car.commanded_turn_radius)
	var fields: PackedStringArray = PackedStringArray([
		"%.6f" % _elapsed,
		str(Engine.get_physics_frames()),
		"%.6f" % position.x,
		"%.6f" % position.y,
		"%.6f" % position.z,
		"%.6f" % velocity.x,
		"%.6f" % velocity.y,
		"%.6f" % velocity.z,
		"%.4f" % car.speed_kph,
		"%.6f" % car.forward_speed,
		"%.5f" % body_heading_deg,
		"%.5f" % velocity_heading_deg,
		"%.5f" % car.slip_angle_degrees,
		"%.5f" % car.yaw_rate_degrees,
		"%.5f" % car.target_yaw_rate_degrees,
		"%.3f" % steer_input,
		"%.5f" % car.steering_degrees,
		"%.5f" % car.steering_limit_degrees,
		"%.8f" % curvature,
		"%.6f" % turn_radius,
		"%.3f" % throttle,
		"%.3f" % reverse_brake,
		"1" if handbrake else "0",
		"1" if boost else "0",
		str(car.grounded_wheels),
		"%.3f" % car.drive_force_newtons,
		"%.5f" % wheel_slips[0],
		"%.5f" % wheel_slips[1],
		"%.5f" % wheel_slips[2],
		"%.5f" % wheel_slips[3],
		"%.6f" % wheel_lateral_speeds[0],
		"%.6f" % wheel_lateral_speeds[1],
		"%.6f" % wheel_lateral_speeds[2],
		"%.6f" % wheel_lateral_speeds[3],
		str(wheel_skids[0]),
		str(wheel_skids[1]),
		str(wheel_skids[2]),
		str(wheel_skids[3])
	])
	_file.store_line(",".join(fields))


func _measure_wheel(wheel_index: int, wheel_slips: Array[float], wheel_lateral_speeds: Array[float], wheel_skids: Array[int]) -> void:
	var ray: RayCast3D = wheel_rays[wheel_index]
	ray.force_raycast_update()
	if not ray.is_colliding():
		return

	var contact_point: Vector3 = ray.get_collision_point()
	var normal: Vector3 = ray.get_collision_normal()
	if normal.length_squared() < 0.000001:
		normal = Vector3.UP
	else:
		normal = normal.normalized()

	var point_velocity: Vector3 = car.get_velocity_at_world_point(contact_point)
	var ground_velocity: Vector3 = point_velocity.slide(normal)
	var wheel_forward: Vector3 = wheel_steer_pivots[wheel_index].global_transform.basis.z.slide(normal)
	if wheel_forward.length_squared() < 0.000001:
		return
	wheel_forward = wheel_forward.normalized()
	var wheel_side: Vector3 = normal.cross(wheel_forward)
	if wheel_side.length_squared() < 0.000001:
		return
	wheel_side = wheel_side.normalized()

	var longitudinal_speed: float = ground_velocity.dot(wheel_forward)
	var lateral_speed: float = ground_velocity.dot(wheel_side)
	var slip_deg: float = rad_to_deg(atan2(lateral_speed, maxf(absf(longitudinal_speed), 0.75)))
	wheel_slips[wheel_index] = slip_deg
	wheel_lateral_speeds[wheel_index] = lateral_speed

	var body_slip_abs: float = absf(car.slip_angle_degrees)
	var skid: bool = absf(slip_deg) >= 2.0 or (body_slip_abs >= 1.5 and absf(lateral_speed) >= 0.25)
	if car.handbrake_active and wheel_index >= 2:
		skid = true
	wheel_skids[wheel_index] = 1 if skid else 0
