class_name DrivingCar
extends RigidBody3D

signal driver_door_opened
signal driver_door_closed

# STABLE TURN CONTROLLER REWRITE V3 - NO PIVOT LAUNCH
# --------------------------------
# +Z is forward.
# Normal driving has one continuous no-slip bicycle mode. A/D changes the
# physical steering angle; yaw is v/L*tan(steer); planar velocity is written from
# that SAME yaw in the same physics frame. Temporary wheel-ray/axle unloading no
# longer kicks the car into another controller. Free physics is used only for
# confirmed air time, handbrake and hard impacts.

const DOOR_OPEN_TIME: float = 1.3
const DOOR_CLOSE_TIME: float = 1.0
const DOOR_OPEN_ANGLE: float = -1.2566370614
const ROAD_WHEEL_NAMES: Array[String] = [
	"Wheel_Front_Left",
	"Wheel_Front_Right",
	"Wheel_Rear_Left",
	"Wheel_Rear_Right"
]

# Visual crash deformation is deliberately small and cosmetic. Collision shapes
# and handling are never changed by dents. The body panels below are allowed to
# deform; wheels, glass, roof cargo, antennas and mechanical parts stay rigid.
const DAMAGE_MESH_NAMES: Array[String] = [
	"Body_shell",
	"Door_Rear_Left",
	"Door_Rear_Right",
	"Door_Front_Right",
	"Hood",
	"Front_fascia_and_lights",
	"Front_bumper_winch_and_guard",
	"Rear_bumper_and_spare_carrier",
	"Side_steps_and_mirrors"
]

# Loosely mounted cargo gets small visual secondary motion. These meshes remain
# children of the vehicle and never affect collision, mass or handling.
const ACCESSORY_MOTION_PROFILES: Dictionary = {
	"Cargo_duffel_Left": 1.00,
	"Cargo_duffel_Right": 1.00,
	"Fuel_can_Left_1": 0.62,
	"Fuel_can_Left_2": 0.62,
	"Fuel_can_Right_1": 0.62,
	"Fuel_can_Right_2": 0.62,
	"Cargo_case_Left": 0.48,
	"Cargo_case_Right": 0.48,
	"Cargo_centre_crate": 0.42,
	"Spare_wheel_roof": 0.36,
	"Spare_wheel_rear": 0.30
}
const DAMAGE_MIN_DELTA_V: float = 1.5
const DAMAGE_FULL_DELTA_V: float = 9.0
const DAMAGE_RADIUS_MIN: float = 0.30
const DAMAGE_RADIUS_MAX: float = 0.58
const DAMAGE_DEPTH_MIN: float = 0.012
const DAMAGE_DEPTH_MAX: float = 0.055

const WHEEL_COUNT: int = 4
const FRONT_LEFT_INDEX: int = 0
const FRONT_RIGHT_INDEX: int = 1
const REAR_LEFT_INDEX: int = 2
const REAR_RIGHT_INDEX: int = 3

const WHEEL_RADIUS: float = 0.466
const WHEELBASE: float = 2.726
const TRACK_WIDTH: float = 1.6876
const REAR_AXLE_FROM_COM: float = 1.2581

# Four-ray suspension. These forces only support the body vertically; they do
# not create lateral tire forces or decide the turn path.
const SUSPENSION_REST_LENGTH: float = 0.30
const SUSPENSION_TRAVEL: float = 0.14
const SPRING_STIFFNESS: float = 45000.0
const DAMPING_COMPRESSION: float = 6200.0
const DAMPING_REBOUND: float = 7600.0
const MAX_SUSPENSION_FORCE: float = 12000.0

# Steering model. A/D changes one normalized steering command. The physical
# front-wheel angle then follows at a fixed rate. A held turn keeps the steering
# cap it had when that turn began; slowing down cannot silently add steering.
# This removes the CSV-proven speed-drop hook without any curvature catch-up.
const LOW_SPEED_MAX_STEER_DEG: float = 26.0
# Smooth the DRIVER COMMAND as a normalized fraction so high-speed steering does
# not become instant merely because the allowed wheel angle is small. Full A/D
# takes about 0.33 s to build at every speed.
const STEER_INPUT_APPLY_RATE: float = 4.25
const STEER_INPUT_RELEASE_RATE: float = 5.25
const STEER_INPUT_REVERSE_RATE: float = 5.00
const STEER_WHEEL_TRACK_RATE_DEG: float = 120.0
# While a steering key is held, speed increases may reduce the safe steering cap
# immediately, but slowing/coasting restores authority at a controlled rate.
# This avoids both the old speed-drop hook and the newer coast-steering dead feel.
const STEER_CAP_RECOVERY_RATE_DEG: float = 9.0
const LATERAL_ACCEL_LIMIT: float = 13.0
const MAX_YAW_RATE_DEG: float = 85.0
const AIRBORNE_CONFIRM_TIME: float = 0.025
# A ray hit is not the same as a wheel carrying the car. Only count suspension
# as load-bearing once it has real spring compression. This prevents the long
# suspension rays from keeping the drive controller grounded after a ramp.
const SUPPORT_COMPRESSION_EPSILON: float = 0.006

# Free-mode timing. Ordinary steering stays in one continuous deterministic
# mode; there is no normal-driving lock blend anymore.
const HANDBRAKE_RELEASE_FREE_TIME: float = 0.10

# Longitudinal speed-state tuning. These are accelerations, not lateral grip.
const MAX_FORWARD_SPEED: float = 55.0 # 198 km/h
const BOOST_FORWARD_SPEED: float = 72.0 # 259 km/h
const FORWARD_ACCEL_LOW_SPEED: float = 8.8
const FORWARD_ACCEL_HIGH_SPEED: float = 1.7
const REVERSE_ACCEL: float = 5.8
const MAX_REVERSE_SPEED: float = 15.0
const SERVICE_BRAKE_DECEL: float = 14.0
const PARK_BRAKE_DECEL: float = 18.0
const COAST_DECEL: float = 1.45
const BOOST_ACCEL_MULTIPLIER: float = 1.42
const BOOST_BLEND_IN_RATE: float = 2.2
const BOOST_BLEND_OUT_RATE: float = 4.0

# Combined tire-grip budget for normal deterministic driving. Steering remains
# responsive, but engine acceleration is reduced when a tight turn is already
# consuming most of the available tire acceleration. This prevents a full-lock
# launch from feeling like the SUV is orbiting one rear wheel.
const TOTAL_GRIP_ACCEL: float = 13.5

# Free-physics controls used only during handbrake / impact recovery. Normal
# driving does not use these forces to steer.
const FREE_DRIVE_FORCE: float = 12000.0
const FREE_REVERSE_FORCE: float = 7000.0
const FREE_BRAKE_FORCE: float = 22000.0
const HANDBRAKE_FORCE: float = 9500.0

# Collision aftermath model. Godot's rigid-body solver now owns the actual crash
# impulse. We do NOT add an artificial push-back impulse anymore. Instead we use
# the measured horizontal contact impulse only to decide how long normal driving
# must stay disengaged so the solver's real rebound, scrape and off-center spin
# are allowed to play out.
const IMPACT_MIN_HORIZONTAL_IMPULSE: float = 950.0
const IMPACT_MIN_HORIZONTAL_RATIO: float = 0.58
const IMPACT_DELTA_V_FOR_FULL_RECOVERY: float = 11.0
const IMPACT_FREE_TIME_MIN: float = 0.10
const IMPACT_FREE_TIME_MAX: float = 0.62
const IMPACT_RECOVERY_COOLDOWN: float = 0.055

# Roll/pitch support only. No yaw torque is generated here.
const ROLL_LEVEL_STIFFNESS: float = 5200.0
const ROLL_DAMPING: float = 2500.0
const PITCH_LEVEL_STIFFNESS: float = 1100.0
const PITCH_DAMPING: float = 1300.0
const MAX_ROLL_TORQUE: float = 5200.0
const MAX_PITCH_TORQUE: float = 2300.0

@export_category("Visual Damage")
@export var visual_damage_enabled: bool = true
@export_range(0.25, 2.0, 0.05) var visual_damage_strength: float = 1.0

@export_category("Accessory Motion")
@export var accessory_motion_enabled: bool = true
@export_range(0.25, 2.0, 0.05) var accessory_motion_strength: float = 1.0

@onready var model_instance: Node3D = $VehicleVisual/Model
@onready var runtime_body_visual: Node3D = $VehicleVisual/RuntimeBody
@onready var driver_door_hinge: Node3D = $VehicleVisual/DriverDoorHinge
@onready var driver_door_visual: MeshInstance3D = $VehicleVisual/DriverDoorHinge/DriverDoorVisual

@onready var front_left_ray: RayCast3D = $FrontLeft/Ray
@onready var front_right_ray: RayCast3D = $FrontRight/Ray
@onready var rear_left_ray: RayCast3D = $RearLeft/Ray
@onready var rear_right_ray: RayCast3D = $RearRight/Ray

@onready var front_left_steer: Node3D = $FrontLeft/Steer
@onready var front_right_steer: Node3D = $FrontRight/Steer
@onready var rear_left_steer: Node3D = $RearLeft/Steer
@onready var rear_right_steer: Node3D = $RearRight/Steer

@onready var front_left_spin: Node3D = $FrontLeft/Steer/Spin
@onready var front_right_spin: Node3D = $FrontRight/Steer/Spin
@onready var rear_left_spin: Node3D = $RearLeft/Steer/Spin
@onready var rear_right_spin: Node3D = $RearRight/Steer/Spin

@onready var front_left_visual: MeshInstance3D = $FrontLeft/Steer/Spin/Visual
@onready var front_right_visual: MeshInstance3D = $FrontRight/Steer/Spin/Visual
@onready var rear_left_visual: MeshInstance3D = $RearLeft/Steer/Spin/Visual
@onready var rear_right_visual: MeshInstance3D = $RearRight/Steer/Spin/Visual

var wheel_rays: Array[RayCast3D] = []
var wheel_steer_pivots: Array[Node3D] = []
var wheel_spin_pivots: Array[Node3D] = []

var _contact_active: Array[bool] = [false, false, false, false]
var _load_active: Array[bool] = [false, false, false, false]
var _contact_points: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var _contact_normals: Array[Vector3] = [Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP]
var _spring_lengths: Array[float] = [SUSPENSION_REST_LENGTH, SUSPENSION_REST_LENGTH, SUSPENSION_REST_LENGTH, SUSPENSION_REST_LENGTH]
var _normal_forces: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _wheel_spin_angles: Array[float] = [0.0, 0.0, 0.0, 0.0]

# Public telemetry/API retained for the HUD, logger, camera and gameplay systems.
var body_mesh_count: int = 0
var speed_kph: float = 0.0
var forward_speed: float = 0.0
var grounded_wheels: int = 0
var loaded_wheels: int = 0
var drive_state: String = "N"
var drive_force_newtons: float = 0.0
var roll_degrees: float = 0.0
var steering_degrees: float = 0.0
var steering_limit_degrees: float = LOW_SPEED_MAX_STEER_DEG
var slip_angle_degrees: float = 0.0
var front_tire_slip_degrees: float = 0.0
var rear_tire_slip_degrees: float = 0.0
var yaw_rate_degrees: float = 0.0
var target_yaw_rate_degrees: float = 0.0
var commanded_turn_radius: float = 0.0
var handbrake_active: bool = false
var boost_active: bool = false
var boost_amount: float = 0.0
var controls_enabled: bool = true
var driver_door_open: bool = false

# True only when the deterministic no-slip bicycle state fully owns planar
# motion. Skid-mark code can use this to avoid treating suspension/roll motion
# as tire sliding during ordinary driving.
var normal_drive_locked: bool = false

# Deterministic normal-driving state.
var _drive_speed: float = 0.0
var _steer_fraction: float = 0.0
var _steering_angle: float = 0.0
var _front_left_angle: float = 0.0
var _front_right_angle: float = 0.0
var _curvature_state: float = 0.0 # retained for DRIVE_TRACE.csv
var _held_steer_sign: float = 0.0
var _held_steer_cap: float = deg_to_rad(LOW_SPEED_MAX_STEER_DEG)
var _physics_override_time: float = 0.0
var _handbrake_was_active: bool = false
var _normal_mode: bool = false
var _airborne_time: float = 0.0

var _door_tween: Tween
var _spawn_transform: Transform3D
var _reset_was_down: bool = false
var _impact_recovery_cooldown: float = 0.0

var _damage_visuals: Array[MeshInstance3D] = []
var _damage_original_meshes: Dictionary = {}
var _pending_damage: bool = false
var _pending_damage_world_point: Vector3 = Vector3.ZERO
var _pending_damage_severity: float = 0.0
var _damage_toggle_was_down: bool = false
var _damage_repair_was_down: bool = false
var damage_dent_count: int = 0

var _accessory_mounts: Array[Node3D] = []
var _accessory_base_transforms: Array[Transform3D] = []
var _accessory_position_offsets: Array[Vector3] = []
var _accessory_position_velocities: Array[Vector3] = []
var _accessory_rotation_offsets: Array[Vector3] = []
var _accessory_rotation_velocities: Array[Vector3] = []
var _accessory_profiles: Array[float] = []
var _accessory_prev_linear_velocity: Vector3 = Vector3.ZERO
var _accessory_prev_angular_velocity: Vector3 = Vector3.ZERO
var _accessory_motion_initialized: bool = false
var _accessory_toggle_was_down: bool = false


func _ready() -> void:
	wheel_rays.append(front_left_ray)
	wheel_rays.append(front_right_ray)
	wheel_rays.append(rear_left_ray)
	wheel_rays.append(rear_right_ray)
	wheel_steer_pivots.append(front_left_steer)
	wheel_steer_pivots.append(front_right_steer)
	wheel_steer_pivots.append(rear_left_steer)
	wheel_steer_pivots.append(rear_right_steer)
	wheel_spin_pivots.append(front_left_spin)
	wheel_spin_pivots.append(front_right_spin)
	wheel_spin_pivots.append(rear_left_spin)
	wheel_spin_pivots.append(rear_right_spin)

	_build_runtime_body_visuals()
	_bind_wheel_visual(front_left_visual, "Wheel_Front_Left")
	_bind_wheel_visual(front_right_visual, "Wheel_Front_Right")
	_bind_wheel_visual(rear_left_visual, "Wheel_Rear_Left")
	_bind_wheel_visual(rear_right_visual, "Wheel_Rear_Right")
	_bind_driver_door_visual()
	model_instance.visible = false
	_setup_visual_damage()

	_spawn_transform = global_transform
	print("Vehicle controller V3 ready: no-slip bicycle driving + no-pivot full-lock launch grip budget.")
	print("Vehicle runtime visuals ready: ", body_mesh_count, " fixed body meshes + animated driver door + 4 wheel meshes.")
	print("Visual mesh damage: ", "enabled" if visual_damage_enabled else "disabled", " (F8 toggle, F9 repair).")
	print("Mounted accessory motion: ", "enabled" if accessory_motion_enabled else "disabled", " (F10 toggle, ", _accessory_mounts.size(), " moving items).")


func _build_runtime_body_visuals() -> void:
	body_mesh_count = 0
	_accessory_mounts.clear()
	_accessory_base_transforms.clear()
	_accessory_position_offsets.clear()
	_accessory_position_velocities.clear()
	_accessory_rotation_offsets.clear()
	_accessory_rotation_velocities.clear()
	_accessory_profiles.clear()
	_accessory_motion_initialized = false
	for old_child: Node in runtime_body_visual.get_children():
		old_child.queue_free()

	var runtime_inverse: Transform3D = runtime_body_visual.global_transform.affine_inverse()
	_copy_runtime_body_meshes(model_instance, runtime_inverse)
	if body_mesh_count == 0:
		push_error("Vehicle GLB loaded, but no runtime body meshes were copied.")


func _copy_runtime_body_meshes(node: Node, runtime_inverse: Transform3D) -> void:
	for child: Node in node.get_children():
		if child is MeshInstance3D:
			var source_mesh: MeshInstance3D = child as MeshInstance3D
			var source_name: String = String(source_mesh.name)
			if not ROAD_WHEEL_NAMES.has(source_name) and source_name != "Door_Front_Left":
				var visual: MeshInstance3D = MeshInstance3D.new()
				visual.name = source_mesh.name
				visual.mesh = source_mesh.mesh
				visual.material_override = source_mesh.material_override
				var source_transform: Transform3D = runtime_inverse * source_mesh.global_transform
				if ACCESSORY_MOTION_PROFILES.has(source_name):
					var mount: Node3D = Node3D.new()
					mount.name = source_name + "_MotionMount"
					mount.transform = source_transform
					runtime_body_visual.add_child(mount)
					visual.transform = Transform3D.IDENTITY
					mount.add_child(visual)
					_register_accessory_mount(mount, source_name)
				else:
					visual.transform = source_transform
					runtime_body_visual.add_child(visual)
				body_mesh_count += 1
		_copy_runtime_body_meshes(child, runtime_inverse)


func _register_accessory_mount(mount: Node3D, source_name: String) -> void:
	_accessory_mounts.append(mount)
	_accessory_base_transforms.append(mount.transform)
	_accessory_position_offsets.append(Vector3.ZERO)
	_accessory_position_velocities.append(Vector3.ZERO)
	_accessory_rotation_offsets.append(Vector3.ZERO)
	_accessory_rotation_velocities.append(Vector3.ZERO)
	_accessory_profiles.append(float(ACCESSORY_MOTION_PROFILES.get(source_name, 0.5)))


func _update_accessory_motion_controls() -> void:
	var toggle_down: bool = Input.is_key_pressed(KEY_F10)
	if toggle_down and not _accessory_toggle_was_down:
		accessory_motion_enabled = not accessory_motion_enabled
		_reset_accessory_motion()
		print("Mounted accessory motion ", "ENABLED" if accessory_motion_enabled else "DISABLED", ".")
	_accessory_toggle_was_down = toggle_down


func _reset_accessory_motion() -> void:
	for index: int in range(_accessory_mounts.size()):
		var mount: Node3D = _accessory_mounts[index]
		if is_instance_valid(mount):
			mount.transform = _accessory_base_transforms[index]
		_accessory_position_offsets[index] = Vector3.ZERO
		_accessory_position_velocities[index] = Vector3.ZERO
		_accessory_rotation_offsets[index] = Vector3.ZERO
		_accessory_rotation_velocities[index] = Vector3.ZERO
	_accessory_prev_linear_velocity = linear_velocity
	_accessory_prev_angular_velocity = angular_velocity
	_accessory_motion_initialized = true


func _update_accessory_motion(delta: float) -> void:
	if _accessory_mounts.is_empty():
		return
	if not accessory_motion_enabled:
		_reset_accessory_motion()
		return
	if not _accessory_motion_initialized:
		_accessory_prev_linear_velocity = linear_velocity
		_accessory_prev_angular_velocity = angular_velocity
		_accessory_motion_initialized = true
		return

	var safe_delta: float = maxf(delta, 0.0001)
	var world_acceleration: Vector3 = (linear_velocity - _accessory_prev_linear_velocity) / safe_delta
	var world_angular_acceleration: Vector3 = (angular_velocity - _accessory_prev_angular_velocity) / safe_delta
	_accessory_prev_linear_velocity = linear_velocity
	_accessory_prev_angular_velocity = angular_velocity

	var inverse_basis: Basis = global_transform.basis.inverse()
	var local_acceleration: Vector3 = inverse_basis * world_acceleration
	var local_angular_acceleration: Vector3 = inverse_basis * world_angular_acceleration
	local_acceleration.x = clampf(local_acceleration.x, -18.0, 18.0)
	local_acceleration.y = clampf(local_acceleration.y, -24.0, 24.0)
	local_acceleration.z = clampf(local_acceleration.z, -18.0, 18.0)
	local_angular_acceleration.x = clampf(local_angular_acceleration.x, -8.0, 8.0)
	local_angular_acceleration.y = clampf(local_angular_acceleration.y, -8.0, 8.0)
	local_angular_acceleration.z = clampf(local_angular_acceleration.z, -8.0, 8.0)

	for index: int in range(_accessory_mounts.size()):
		var mount: Node3D = _accessory_mounts[index]
		if not is_instance_valid(mount):
			continue
		var profile: float = _accessory_profiles[index] * accessory_motion_strength
		var target_position: Vector3 = Vector3(
			-local_acceleration.x * 0.0017,
			-local_acceleration.y * 0.00065,
			-local_acceleration.z * 0.0016
		) * profile
		target_position.x = clampf(target_position.x, -0.032 * profile, 0.032 * profile)
		target_position.y = clampf(target_position.y, -0.014 * profile, 0.014 * profile)
		target_position.z = clampf(target_position.z, -0.030 * profile, 0.030 * profile)

		var target_rotation: Vector3 = Vector3(
			local_acceleration.z * 0.0028,
			-local_angular_acceleration.y * 0.010,
			-local_acceleration.x * 0.0030
		) * profile
		target_rotation.x = clampf(target_rotation.x, -0.075 * profile, 0.075 * profile)
		target_rotation.y = clampf(target_rotation.y, -0.055 * profile, 0.055 * profile)
		target_rotation.z = clampf(target_rotation.z, -0.080 * profile, 0.080 * profile)

		# Duffels use the softest spring; tied-down wheels/cases stay firmer. The
		# motion remains critically damped enough to avoid endless wobble.
		var softness: float = clampf(_accessory_profiles[index], 0.0, 1.0)
		var position_stiffness: float = lerpf(62.0, 34.0, softness)
		var position_damping: float = 1.75 * sqrt(position_stiffness)
		var rotation_stiffness: float = lerpf(56.0, 28.0, softness)
		var rotation_damping: float = 1.70 * sqrt(rotation_stiffness)

		var position_offset: Vector3 = _accessory_position_offsets[index]
		var position_velocity: Vector3 = _accessory_position_velocities[index]
		position_velocity += ((target_position - position_offset) * position_stiffness - position_velocity * position_damping) * safe_delta
		position_offset += position_velocity * safe_delta

		var rotation_offset: Vector3 = _accessory_rotation_offsets[index]
		var rotation_velocity: Vector3 = _accessory_rotation_velocities[index]
		rotation_velocity += ((target_rotation - rotation_offset) * rotation_stiffness - rotation_velocity * rotation_damping) * safe_delta
		rotation_offset += rotation_velocity * safe_delta

		_accessory_position_offsets[index] = position_offset
		_accessory_position_velocities[index] = position_velocity
		_accessory_rotation_offsets[index] = rotation_offset
		_accessory_rotation_velocities[index] = rotation_velocity

		var base_transform: Transform3D = _accessory_base_transforms[index]
		mount.transform = Transform3D(
			Basis.from_euler(rotation_offset) * base_transform.basis,
			base_transform.origin + position_offset
		)


func _bind_wheel_visual(visual: MeshInstance3D, source_name: String) -> void:
	var source: Node = model_instance.find_child(source_name, true, false)
	if not source is MeshInstance3D:
		push_error("Could not find wheel mesh in Vehicle.glb: " + source_name)
		return
	var source_mesh: MeshInstance3D = source as MeshInstance3D
	visual.mesh = source_mesh.mesh
	visual.material_override = source_mesh.material_override
	source_mesh.visible = false


func _bind_driver_door_visual() -> void:
	var source: Node = model_instance.find_child("Door_Front_Left", true, false)
	if not source is MeshInstance3D:
		push_error("Could not find Door_Front_Left in Vehicle.glb.")
		return
	var source_mesh: MeshInstance3D = source as MeshInstance3D
	driver_door_visual.mesh = source_mesh.mesh
	driver_door_visual.material_override = source_mesh.material_override
	source_mesh.visible = false
	driver_door_hinge.rotation.y = 0.0


func _setup_visual_damage() -> void:
	_damage_visuals.clear()
	_damage_original_meshes.clear()
	for child: Node in runtime_body_visual.get_children():
		if child is MeshInstance3D:
			var visual: MeshInstance3D = child as MeshInstance3D
			if DAMAGE_MESH_NAMES.has(String(visual.name)):
				_register_damage_visual(visual)
	# The animated left-front door is not inside RuntimeBody, so register it
	# explicitly. Its current hinge transform is respected when a dent is made.
	_register_damage_visual(driver_door_visual)


func _register_damage_visual(visual: MeshInstance3D) -> void:
	if not is_instance_valid(visual) or visual.mesh == null:
		return
	_damage_visuals.append(visual)
	_damage_original_meshes[visual.get_instance_id()] = visual.mesh


func repair_visual_damage() -> void:
	for visual: MeshInstance3D in _damage_visuals:
		if not is_instance_valid(visual):
			continue
		var key: int = visual.get_instance_id()
		if _damage_original_meshes.has(key):
			visual.mesh = _damage_original_meshes[key] as Mesh
	damage_dent_count = 0
	_pending_damage = false
	print("Visual vehicle dents repaired.")


func _queue_visual_damage(world_point: Vector3, impact_delta_v: float) -> void:
	if not visual_damage_enabled or impact_delta_v < DAMAGE_MIN_DELTA_V:
		return
	var severity: float = clampf(
		(impact_delta_v - DAMAGE_MIN_DELTA_V) / maxf(DAMAGE_FULL_DELTA_V - DAMAGE_MIN_DELTA_V, 0.001),
		0.0,
		1.0
	)
	_pending_damage = true
	_pending_damage_world_point = world_point
	_pending_damage_severity = maxf(_pending_damage_severity, severity)


func _apply_pending_visual_damage() -> void:
	if not _pending_damage:
		return
	var world_point: Vector3 = _pending_damage_world_point
	var severity: float = _pending_damage_severity
	_pending_damage = false
	_pending_damage_severity = 0.0
	if not visual_damage_enabled:
		return

	var radius: float = lerpf(DAMAGE_RADIUS_MIN, DAMAGE_RADIUS_MAX, severity)
	var depth: float = lerpf(DAMAGE_DEPTH_MIN, DAMAGE_DEPTH_MAX, severity) * visual_damage_strength
	var vehicle_center: Vector3 = global_position + global_transform.basis.y.normalized() * 0.28
	var dent_direction: Vector3 = vehicle_center - world_point
	if dent_direction.length_squared() < 0.0001:
		return
	dent_direction = dent_direction.normalized()

	var changed_any: bool = false
	for visual: MeshInstance3D in _damage_visuals:
		if not is_instance_valid(visual) or visual.mesh == null:
			continue
		var deformed_mesh: ArrayMesh = _build_dented_mesh(visual, world_point, dent_direction, radius, depth)
		if deformed_mesh != null:
			visual.mesh = deformed_mesh
			changed_any = true

	if changed_any:
		damage_dent_count += 1
		print("Visual dent #", damage_dent_count, " severity=", snappedf(severity, 0.01), " radius=", snappedf(radius, 0.01), "m depth=", snappedf(depth, 0.001), "m")


func _build_dented_mesh(visual: MeshInstance3D, world_point: Vector3, dent_direction: Vector3, radius: float, depth: float) -> ArrayMesh:
	var source_mesh: Mesh = visual.mesh
	if source_mesh == null or source_mesh.get_surface_count() <= 0:
		return null

	var surface_arrays: Array[Array] = []
	var changed_any: bool = false
	var world_to_local: Transform3D = visual.global_transform.affine_inverse()

	for surface_index: int in range(source_mesh.get_surface_count()):
		var arrays: Array = source_mesh.surface_get_arrays(surface_index).duplicate(true)
		var changed: bool = false
		if arrays.size() > Mesh.ARRAY_VERTEX and arrays[Mesh.ARRAY_VERTEX] != null:
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var modified: PackedVector3Array = vertices.duplicate()
			for vertex_index: int in range(modified.size()):
				var local_vertex: Vector3 = modified[vertex_index]
				var world_vertex: Vector3 = visual.global_transform * local_vertex
				var distance: float = world_vertex.distance_to(world_point)
				if distance >= radius:
					continue
				var t: float = 1.0 - distance / radius
				# Smooth cubic falloff keeps the outer edge of a dent from forming a
				# visible hard ring. Repeated crashes can accumulate naturally.
				var falloff: float = t * t * (3.0 - 2.0 * t)
				var deformed_world: Vector3 = world_vertex + dent_direction * (depth * falloff)
				modified[vertex_index] = world_to_local * deformed_world
				changed = true
			if changed:
				arrays[Mesh.ARRAY_VERTEX] = modified
				changed_any = true
		surface_arrays.append(arrays)

	if not changed_any:
		return null

	var output: ArrayMesh = ArrayMesh.new()
	for surface_index: int in range(source_mesh.get_surface_count()):
		var primitive: int = source_mesh.surface_get_primitive_type(surface_index)
		output.add_surface_from_arrays(primitive, surface_arrays[surface_index])
		output.surface_set_material(surface_index, source_mesh.surface_get_material(surface_index))
	return output


func _update_visual_damage_controls() -> void:
	var toggle_down: bool = Input.is_key_pressed(KEY_F8)
	if toggle_down and not _damage_toggle_was_down:
		visual_damage_enabled = not visual_damage_enabled
		print("Visual mesh damage ", "ENABLED" if visual_damage_enabled else "DISABLED", ". Existing dents are unchanged.")
	_damage_toggle_was_down = toggle_down

	var repair_down: bool = Input.is_key_pressed(KEY_F9)
	if repair_down and not _damage_repair_was_down:
		repair_visual_damage()
	_damage_repair_was_down = repair_down


func set_controls_enabled(enabled: bool) -> void:
	controls_enabled = enabled
	if not enabled:
		boost_active = false
		boost_amount = 0.0
		handbrake_active = false
		drive_force_newtons = 0.0


func open_driver_door() -> void:
	if driver_door_open:
		driver_door_opened.emit()
		return
	if is_instance_valid(_door_tween):
		_door_tween.kill()
	_door_tween = create_tween()
	_door_tween.set_trans(Tween.TRANS_QUAD)
	_door_tween.set_ease(Tween.EASE_OUT)
	_door_tween.tween_property(driver_door_hinge, "rotation:y", DOOR_OPEN_ANGLE, DOOR_OPEN_TIME)
	_door_tween.finished.connect(_on_driver_door_opened)


func close_driver_door() -> void:
	if not driver_door_open and is_zero_approx(driver_door_hinge.rotation.y):
		driver_door_closed.emit()
		return
	if is_instance_valid(_door_tween):
		_door_tween.kill()
	_door_tween = create_tween()
	_door_tween.set_trans(Tween.TRANS_QUAD)
	_door_tween.set_ease(Tween.EASE_IN_OUT)
	_door_tween.tween_property(driver_door_hinge, "rotation:y", 0.0, DOOR_CLOSE_TIME)
	_door_tween.finished.connect(_on_driver_door_closed)


func _on_driver_door_opened() -> void:
	driver_door_open = true
	driver_door_opened.emit()


func _on_driver_door_closed() -> void:
	driver_door_open = false
	driver_door_closed.emit()


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	# Let Godot solve the collision first. This hook no longer creates a fake
	# rebound. It only detects a meaningful mostly-horizontal chassis impact and
	# temporarily releases the deterministic drive controller so the solver's
	# physically generated velocity and angular velocity survive the crash.
	if _impact_recovery_cooldown > 0.0:
		return

	var strongest_horizontal_magnitude: float = 0.0
	var strongest_contact_index: int = -1
	for contact_index: int in range(state.get_contact_count()):
		var contact_impulse: Vector3 = state.get_contact_impulse(contact_index)
		var total_magnitude: float = contact_impulse.length()
		if total_magnitude < IMPACT_MIN_HORIZONTAL_IMPULSE:
			continue

		var horizontal_impulse: Vector3 = Vector3(contact_impulse.x, 0.0, contact_impulse.z)
		var horizontal_magnitude: float = horizontal_impulse.length()
		if horizontal_magnitude < IMPACT_MIN_HORIZONTAL_IMPULSE:
			continue
		if horizontal_magnitude < total_magnitude * IMPACT_MIN_HORIZONTAL_RATIO:
			continue

		if horizontal_magnitude > strongest_horizontal_magnitude:
			strongest_horizontal_magnitude = horizontal_magnitude
			strongest_contact_index = contact_index

	if strongest_horizontal_magnitude <= 0.0:
		return

	# Impulse / mass is an approximate collision delta-v. Use it only as crash
	# severity. A light brush gets a brief free-physics window; a hard wall hit
	# gets enough time for the natural rebound / rotation / scrape to settle.
	var impact_delta_v: float = strongest_horizontal_magnitude / maxf(mass, 1.0)
	var severity: float = clampf(impact_delta_v / IMPACT_DELTA_V_FOR_FULL_RECOVERY, 0.0, 1.0)
	var recovery_time: float = lerpf(IMPACT_FREE_TIME_MIN, IMPACT_FREE_TIME_MAX, severity)

	if strongest_contact_index >= 0 and visual_damage_enabled:
		# Despite its historical name, Godot returns this contact position in
		# global coordinates. Store it directly for the visual dent pass.
		var world_contact_point: Vector3 = state.get_contact_local_position(strongest_contact_index)
		_queue_visual_damage(world_contact_point, impact_delta_v)

	_physics_override_time = maxf(_physics_override_time, recovery_time)
	_normal_mode = false
	normal_drive_locked = false
	_impact_recovery_cooldown = IMPACT_RECOVERY_COOLDOWN


func _physics_process(delta: float) -> void:
	_impact_recovery_cooldown = maxf(_impact_recovery_cooldown - delta, 0.0)
	_physics_override_time = maxf(_physics_override_time - delta, 0.0)
	_apply_pending_visual_damage()
	_update_visual_damage_controls()
	_update_accessory_motion_controls()

	var steer_input: float = 0.0
	var throttle: float = 0.0
	var reverse_brake: float = 0.0
	var handbrake: bool = false
	var boost_pressed: bool = false

	if controls_enabled:
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			steer_input += 1.0
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			steer_input -= 1.0
		throttle = 1.0 if (Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)) else 0.0
		reverse_brake = 1.0 if (Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)) else 0.0
		handbrake = Input.is_key_pressed(KEY_SPACE)
		boost_pressed = Input.is_key_pressed(KEY_SHIFT)

	boost_active = controls_enabled and boost_pressed and throttle > 0.0 and not handbrake
	var boost_target: float = 1.0 if boost_active else 0.0
	var boost_rate: float = BOOST_BLEND_IN_RATE if boost_active else BOOST_BLEND_OUT_RATE
	boost_amount = move_toward(boost_amount, boost_target, boost_rate * delta)

	_update_wheel_contacts()
	_update_ground_state(handbrake, delta)
	_update_steering(steer_input, delta)
	_apply_suspension_forces()
	_apply_vehicle_motion(throttle, reverse_brake, handbrake, not controls_enabled, delta)
	_apply_body_stability()
	_update_wheel_slip_telemetry()
	_update_wheel_visuals(delta)
	_update_basic_telemetry()
	_update_accessory_motion(delta)
	_update_reset()

	_handbrake_was_active = handbrake

	if global_position.y < -10.0:
		reset_vehicle()


func _update_ground_state(handbrake: bool, delta: float) -> void:
	var stable_support: bool = _has_drive_support()
	var any_load: bool = loaded_wheels > 0

	# IMPORTANT: ray visibility is not ground support. The rays extend through the
	# full suspension droop, so they can still see the road after a ramp even when
	# every spring is fully extended. Only real spring compression counts here.
	# Once all four springs are unloaded for a tiny debounce window, release the
	# deterministic controller and preserve the rigid body's launch velocity.
	if any_load:
		_airborne_time = 0.0
	else:
		_airborne_time += delta

	if _handbrake_was_active and not handbrake:
		_physics_override_time = maxf(_physics_override_time, HANDBRAKE_RELEASE_FREE_TIME)

	var forced_free: bool = handbrake or _physics_override_time > 0.0 or _airborne_time >= AIRBORNE_CONFIRM_TIME
	if forced_free:
		_normal_mode = false
		normal_drive_locked = false
		return

	# While at least one suspension is genuinely loaded, temporary one-wheel
	# unloading does not change controller mode. Once every spring unloads, the
	# airborne debounce above releases the car into real rigid-body flight.
	if _normal_mode:
		normal_drive_locked = true
		return

	# Re-enter deterministic driving only when both axles have ground support.
	# Preserve the current horizontal momentum, but restart steering from center
	# so an old held key cannot create an instant turn on landing/after an impact.
	if stable_support:
		_drive_speed = _signed_planar_momentum_speed()
		_steer_fraction = 0.0
		_steering_angle = 0.0
		_front_left_angle = 0.0
		_front_right_angle = 0.0
		_curvature_state = 0.0
		_held_steer_sign = 0.0
		_held_steer_cap = _steer_cap_for_speed(absf(_drive_speed))
		_normal_mode = true
		normal_drive_locked = true


func _has_drive_support() -> bool:
	# Require ACTUAL suspension load on both axles. A ray can hit the road while a
	# wheel is still hanging at full droop, especially during takeoff/landing.
	var front_supported: bool = _load_active[FRONT_LEFT_INDEX] or _load_active[FRONT_RIGHT_INDEX]
	var rear_supported: bool = _load_active[REAR_LEFT_INDEX] or _load_active[REAR_RIGHT_INDEX]
	return front_supported and rear_supported


func _update_steering(input_amount: float, delta: float) -> void:
	var speed_for_limit: float = absf(_drive_speed)
	if not _normal_mode:
		var support_up: Vector3 = _support_normal()
		speed_for_limit = linear_velocity.slide(support_up).length()
	var instantaneous_cap: float = _steer_cap_for_speed(speed_for_limit)
	var input_sign: float = signf(input_amount)

	# The old anti-hook fix froze this cap for the whole steering hold. That stopped
	# the sudden tightening from the CSV, but it also meant a turn started while
	# coasting at high speed could remain weak forever as the car slowed.
	#
	# New rule:
	# - no steering input: track the current speed cap exactly, ready for next turn;
	# - speed rises while steering: shrink authority immediately for stability;
	# - speed falls while steering: restore authority only at a bounded rate.
	# This makes steering independent of throttle history without allowing a sudden
	# speed-drop hook.
	if is_zero_approx(input_amount):
		_held_steer_sign = 0.0
		_held_steer_cap = instantaneous_cap
	elif is_zero_approx(_held_steer_sign) or input_sign != _held_steer_sign:
		_held_steer_sign = input_sign
		_held_steer_cap = instantaneous_cap
	elif instantaneous_cap < _held_steer_cap:
		_held_steer_cap = instantaneous_cap
	else:
		_held_steer_cap = move_toward(
			_held_steer_cap,
			instantaneous_cap,
			deg_to_rad(STEER_CAP_RECOVERY_RATE_DEG) * delta
		)

	var fraction_rate: float = STEER_INPUT_APPLY_RATE
	if is_zero_approx(input_amount):
		fraction_rate = STEER_INPUT_RELEASE_RATE
	elif not is_zero_approx(_steer_fraction) and signf(_steer_fraction) != input_sign:
		fraction_rate = STEER_INPUT_REVERSE_RATE
	_steer_fraction = move_toward(_steer_fraction, input_amount, fraction_rate * delta)

	var target_angle: float = _steer_fraction * _held_steer_cap
	_steering_angle = move_toward(_steering_angle, target_angle, deg_to_rad(STEER_WHEEL_TRACK_RATE_DEG) * delta)
	if absf(_steering_angle) < 0.00005:
		_steering_angle = 0.0

	_curvature_state = tan(_steering_angle) / WHEELBASE
	steering_degrees = rad_to_deg(_steering_angle)
	steering_limit_degrees = rad_to_deg(_held_steer_cap)
	commanded_turn_radius = 0.0 if absf(_curvature_state) < 0.00001 else 1.0 / absf(_curvature_state)
	_update_ackermann_angles()


func _steer_cap_for_speed(speed_mps: float) -> float:
	var base_angle: float = deg_to_rad(LOW_SPEED_MAX_STEER_DEG)
	if speed_mps < 1.0:
		return base_angle
	var accel_angle: float = atan((LATERAL_ACCEL_LIMIT * WHEELBASE) / maxf(speed_mps * speed_mps, 1.0))
	return minf(base_angle, accel_angle)


func _update_ackermann_angles() -> void:
	if absf(_steering_angle) < 0.0001:
		_front_left_angle = 0.0
		_front_right_angle = 0.0
		return

	var direction_sign: float = signf(_steering_angle)
	var center_radius: float = absf(WHEELBASE / tan(_steering_angle))
	var half_track: float = TRACK_WIDTH * 0.5
	var inner_radius: float = maxf(center_radius - half_track, 0.25)
	var outer_radius: float = center_radius + half_track
	var inner_angle: float = atan(WHEELBASE / inner_radius) * direction_sign
	var outer_angle: float = atan(WHEELBASE / outer_radius) * direction_sign

	if direction_sign > 0.0:
		_front_left_angle = inner_angle
		_front_right_angle = outer_angle
	else:
		_front_left_angle = outer_angle
		_front_right_angle = inner_angle


func _update_wheel_contacts() -> void:
	grounded_wheels = 0
	loaded_wheels = 0
	for index: int in range(WHEEL_COUNT):
		var ray: RayCast3D = wheel_rays[index]
		ray.force_raycast_update()
		_load_active[index] = false
		if ray.is_colliding():
			var point: Vector3 = ray.get_collision_point()
			var normal: Vector3 = ray.get_collision_normal()
			if normal.length_squared() < 0.0001:
				normal = Vector3.UP
			else:
				normal = normal.normalized()
			var ray_down: Vector3 = -ray.global_transform.basis.y.normalized()
			var ray_distance: float = (point - ray.global_position).dot(ray_down)
			var spring_length: float = clampf(
				ray_distance - WHEEL_RADIUS,
				SUSPENSION_REST_LENGTH - SUSPENSION_TRAVEL,
				SUSPENSION_REST_LENGTH + SUSPENSION_TRAVEL
			)
			_contact_active[index] = true
			_contact_points[index] = point
			_contact_normals[index] = normal
			_spring_lengths[index] = spring_length
			grounded_wheels += 1

			# The wheel is load-bearing only when the spring is actually compressed.
			# A ray hit at full droop is proximity information, not physical support.
			var compression: float = SUSPENSION_REST_LENGTH - spring_length
			if compression > SUPPORT_COMPRESSION_EPSILON:
				_load_active[index] = true
				loaded_wheels += 1
		else:
			_contact_active[index] = false
			_contact_points[index] = ray.global_position + (-ray.global_transform.basis.y.normalized()) * (SUSPENSION_REST_LENGTH + SUSPENSION_TRAVEL + WHEEL_RADIUS)
			_contact_normals[index] = Vector3.UP
			_spring_lengths[index] = SUSPENSION_REST_LENGTH + SUSPENSION_TRAVEL
			_normal_forces[index] = 0.0


func _apply_suspension_forces() -> void:
	for index: int in range(WHEEL_COUNT):
		_normal_forces[index] = 0.0
		if not _contact_active[index]:
			continue

		var contact_point: Vector3 = _contact_points[index]
		var normal: Vector3 = _contact_normals[index]
		var compression: float = maxf(SUSPENSION_REST_LENGTH - _spring_lengths[index], 0.0)
		var point_velocity: Vector3 = get_velocity_at_world_point(contact_point)
		var normal_speed: float = point_velocity.dot(normal)
		var damping: float = DAMPING_COMPRESSION if normal_speed < 0.0 else DAMPING_REBOUND
		var spring_force: float = compression * SPRING_STIFFNESS - normal_speed * damping
		spring_force = clampf(spring_force, 0.0, MAX_SUSPENSION_FORCE)
		_normal_forces[index] = spring_force
		apply_force(normal * spring_force, contact_point - global_position)


func _apply_vehicle_motion(throttle: float, reverse_brake: float, handbrake: bool, parked: bool, delta: float) -> void:
	handbrake_active = handbrake
	drive_force_newtons = 0.0
	target_yaw_rate_degrees = 0.0

	var support_up: Vector3 = _support_normal()
	var body_forward: Vector3 = global_transform.basis.z.slide(support_up)
	if body_forward.length_squared() < 0.0001:
		body_forward = Vector3.MODEL_FRONT
	else:
		body_forward = body_forward.normalized()
	var body_side: Vector3 = support_up.cross(body_forward)
	if body_side.length_squared() < 0.0001:
		body_side = Vector3.RIGHT
	else:
		body_side = body_side.normalized()

	# There is no blend/catch-up state in normal driving anymore. Once normal
	# mode owns the car, every frame belongs to the same bicycle velocity field.
	# Free physics is reserved for confirmed air time, handbrake and hard impacts.
	if not _normal_mode or handbrake or _physics_override_time > 0.0:
		normal_drive_locked = false
		_apply_free_physics_controls(body_forward, throttle, reverse_brake, handbrake, parked)
		return

	_update_drive_speed_state(throttle, reverse_brake, parked, delta)

	# One equation decides the turn. No lateral tire correction, no yaw follower,
	# no curvature recovery and no contact-dependent blend can tighten it later.
	var desired_yaw_rate: float = _drive_speed * tan(_steering_angle) / WHEELBASE
	var max_yaw_rate: float = deg_to_rad(MAX_YAW_RATE_DEG)
	desired_yaw_rate = clampf(desired_yaw_rate, -max_yaw_rate, max_yaw_rate)
	target_yaw_rate_degrees = rad_to_deg(desired_yaw_rate)

	# Exact rigid-body field for a bicycle rotating around the rear axle: the rear
	# axle has zero lateral velocity while the COM carries the required small side
	# component. Because yaw and planar velocity are written together, there is no
	# body-turn-first / velocity-catches-up phase to feel as a slide.
	var desired_com_planar: Vector3 = body_forward * _drive_speed
	desired_com_planar += body_side * (desired_yaw_rate * REAR_AXLE_FROM_COM)
	var normal_velocity: Vector3 = support_up * linear_velocity.dot(support_up)
	linear_velocity = desired_com_planar + normal_velocity

	var current_yaw_rate: float = angular_velocity.dot(support_up)
	var non_yaw_angular_velocity: Vector3 = angular_velocity - support_up * current_yaw_rate
	angular_velocity = non_yaw_angular_velocity + support_up * desired_yaw_rate
	normal_drive_locked = true


func _update_drive_speed_state(throttle: float, reverse_brake: float, parked: bool, delta: float) -> void:
	var acceleration: float = 0.0
	var speed_limit: float = lerpf(MAX_FORWARD_SPEED, BOOST_FORWARD_SPEED, boost_amount)

	if parked:
		_drive_speed = move_toward(_drive_speed, 0.0, PARK_BRAKE_DECEL * delta)
		drive_force_newtons = 0.0
		return

	if throttle > 0.0 and reverse_brake > 0.0:
		_drive_speed = move_toward(_drive_speed, 0.0, SERVICE_BRAKE_DECEL * delta)
		return

	if throttle > 0.0:
		if _drive_speed < -0.4:
			_drive_speed = move_toward(_drive_speed, 0.0, SERVICE_BRAKE_DECEL * delta)
		else:
			var speed_ratio: float = clampf(maxf(_drive_speed, 0.0) / maxf(speed_limit, 0.001), 0.0, 1.0)
			acceleration = lerpf(FORWARD_ACCEL_LOW_SPEED, FORWARD_ACCEL_HIGH_SPEED, speed_ratio)
			acceleration *= (1.0 - speed_ratio)
			acceleration *= lerpf(1.0, BOOST_ACCEL_MULTIPLIER, boost_amount)

			# Friction-circle style launch limit. A straight launch still gets the full
			# engine acceleration, but a full-lock launch cannot simultaneously demand
			# maximum longitudinal acceleration and maximum cornering acceleration.
			var curvature_abs: float = absf(tan(_steering_angle) / WHEELBASE)
			var lateral_accel: float = _drive_speed * _drive_speed * curvature_abs
			var grip_remaining_sq: float = TOTAL_GRIP_ACCEL * TOTAL_GRIP_ACCEL - lateral_accel * lateral_accel
			var longitudinal_grip_limit: float = sqrt(maxf(grip_remaining_sq, 0.0))
			acceleration = minf(acceleration, longitudinal_grip_limit)
			_drive_speed = minf(_drive_speed + acceleration * delta, speed_limit)
	elif reverse_brake > 0.0:
		if _drive_speed > 0.4:
			_drive_speed = move_toward(_drive_speed, 0.0, SERVICE_BRAKE_DECEL * delta)
		else:
			var reverse_ratio: float = clampf(absf(_drive_speed) / MAX_REVERSE_SPEED, 0.0, 1.0)
			acceleration = -REVERSE_ACCEL * (1.0 - reverse_ratio)
			_drive_speed = maxf(_drive_speed + acceleration * delta, -MAX_REVERSE_SPEED)
	else:
		_drive_speed = move_toward(_drive_speed, 0.0, COAST_DECEL * delta)

	drive_force_newtons = acceleration * mass


func _apply_free_physics_controls(body_forward: Vector3, throttle: float, reverse_brake: float, handbrake: bool, parked: bool) -> void:
	# Free mode deliberately does not rewrite lateral velocity or yaw. It is used
	# for handbrake slides, airborne/landing recovery and the physical collision
	# aftermath window.
	if not _has_drive_support():
		return

	var forward_component: float = linear_velocity.dot(body_forward)
	if parked:
		if linear_velocity.length() > 0.1:
			apply_central_force(-linear_velocity.normalized() * FREE_BRAKE_FORCE)
		return

	if throttle > 0.0 and reverse_brake > 0.0:
		if linear_velocity.length() > 0.1:
			apply_central_force(-linear_velocity.normalized() * FREE_BRAKE_FORCE)
	elif throttle > 0.0:
		if forward_component < 60.0:
			apply_central_force(body_forward * FREE_DRIVE_FORCE * throttle)
	elif reverse_brake > 0.0:
		if forward_component > 1.0:
			apply_central_force(-body_forward * FREE_BRAKE_FORCE * reverse_brake)
		elif forward_component > -MAX_REVERSE_SPEED:
			apply_central_force(-body_forward * FREE_REVERSE_FORCE * reverse_brake)

	if handbrake:
		var planar: Vector3 = linear_velocity
		planar.y = 0.0
		if planar.length() > 0.1:
			apply_central_force(-planar.normalized() * HANDBRAKE_FORCE)


func _signed_planar_momentum_speed() -> float:
	var support_up: Vector3 = _support_normal()
	var body_forward: Vector3 = global_transform.basis.z.slide(support_up)
	if body_forward.length_squared() < 0.0001:
		body_forward = Vector3.MODEL_FRONT
	else:
		body_forward = body_forward.normalized()
	var planar: Vector3 = linear_velocity.slide(support_up)
	var magnitude: float = planar.length()
	if magnitude < 0.001:
		return 0.0
	var forward_component: float = planar.dot(body_forward)
	if absf(forward_component) > 0.15:
		return magnitude * signf(forward_component)
	if absf(_drive_speed) > 0.15:
		return magnitude * signf(_drive_speed)
	return magnitude


func _update_basic_telemetry() -> void:
	var support_up: Vector3 = _support_normal()
	var body_forward: Vector3 = global_transform.basis.z.slide(support_up)
	if body_forward.length_squared() < 0.0001:
		body_forward = Vector3.MODEL_FRONT
	else:
		body_forward = body_forward.normalized()
	var rear_planar_velocity: Vector3 = get_rear_axle_velocity().slide(support_up)
	forward_speed = rear_planar_velocity.dot(body_forward)
	speed_kph = rear_planar_velocity.length() * 3.6
	_update_slip_measurement(rear_planar_velocity)
	yaw_rate_degrees = rad_to_deg(angular_velocity.dot(support_up))

	if not controls_enabled:
		drive_state = "P"
	elif handbrake_active:
		drive_state = "HB"
	elif forward_speed > 0.8:
		drive_state = "D"
	elif forward_speed < -0.8:
		drive_state = "R"
	else:
		drive_state = "N"


func _update_wheel_slip_telemetry() -> void:
	var front_sum: float = 0.0
	var rear_sum: float = 0.0
	var front_count: int = 0
	var rear_count: int = 0
	for index: int in range(WHEEL_COUNT):
		if not _contact_active[index]:
			continue
		var normal: Vector3 = _contact_normals[index]
		var wheel_angle: float = _wheel_steer_angle(index)
		var wheel_forward: Vector3 = Basis(global_transform.basis.y.normalized(), wheel_angle) * global_transform.basis.z.normalized()
		wheel_forward = wheel_forward.slide(normal)
		if wheel_forward.length_squared() < 0.0001:
			continue
		wheel_forward = wheel_forward.normalized()
		var wheel_side: Vector3 = normal.cross(wheel_forward)
		if wheel_side.length_squared() < 0.0001:
			continue
		wheel_side = wheel_side.normalized()
		var point_velocity: Vector3 = get_velocity_at_world_point(_contact_points[index])
		var longitudinal_speed: float = point_velocity.dot(wheel_forward)
		var lateral_speed: float = point_velocity.dot(wheel_side)
		var slip_angle: float = rad_to_deg(atan2(lateral_speed, maxf(absf(longitudinal_speed), 0.25)))
		if index < 2:
			front_sum += absf(slip_angle)
			front_count += 1
		else:
			rear_sum += absf(slip_angle)
			rear_count += 1
	front_tire_slip_degrees = front_sum / float(maxi(front_count, 1))
	rear_tire_slip_degrees = rear_sum / float(maxi(rear_count, 1))


func _wheel_steer_angle(index: int) -> float:
	if index == FRONT_LEFT_INDEX:
		return _front_left_angle
	if index == FRONT_RIGHT_INDEX:
		return _front_right_angle
	return 0.0


func get_velocity_at_world_point(world_point: Vector3) -> Vector3:
	var center_of_mass_world: Vector3 = global_transform * center_of_mass
	var offset: Vector3 = world_point - center_of_mass_world
	return linear_velocity + angular_velocity.cross(offset)


func get_rear_axle_velocity() -> Vector3:
	var rear_axle_world: Vector3 = (rear_left_ray.global_position + rear_right_ray.global_position) * 0.5
	return get_velocity_at_world_point(rear_axle_world)


func _apply_body_stability() -> void:
	var planar_velocity: Vector3 = linear_velocity
	planar_velocity.y = 0.0
	var planar_speed: float = planar_velocity.length()

	if _has_drive_support():
		var support_up: Vector3 = _support_normal()
		var side_axis: Vector3 = global_transform.basis.x.normalized()
		var forward_axis: Vector3 = global_transform.basis.z.normalized()
		var roll_error: float = clampf(side_axis.dot(support_up), -1.0, 1.0)
		var pitch_error: float = clampf(forward_axis.dot(support_up), -1.0, 1.0)
		var roll_rate: float = angular_velocity.dot(forward_axis)
		var pitch_rate: float = angular_velocity.dot(side_axis)
		roll_degrees = rad_to_deg(asin(roll_error))

		var roll_torque: float = -roll_error * ROLL_LEVEL_STIFFNESS - roll_rate * ROLL_DAMPING
		var pitch_torque: float = pitch_error * PITCH_LEVEL_STIFFNESS - pitch_rate * PITCH_DAMPING
		roll_torque = clampf(roll_torque, -MAX_ROLL_TORQUE, MAX_ROLL_TORQUE)
		pitch_torque = clampf(pitch_torque, -MAX_PITCH_TORQUE, MAX_PITCH_TORQUE)
		var stability_torque: Vector3 = forward_axis * roll_torque + side_axis * pitch_torque
		stability_torque = stability_torque.slide(support_up)
		apply_torque(stability_torque)
	else:
		roll_degrees = 0.0

	if loaded_wheels >= 3 and planar_speed > 3.0:
		var downforce: float = minf(planar_speed * planar_speed * 0.55, 1450.0)
		apply_central_force(Vector3.DOWN * downforce)


func _support_normal() -> Vector3:
	var sum: Vector3 = Vector3.ZERO
	var count: int = 0
	# Prefer normals from wheels that are physically carrying spring load. This
	# avoids a distant ray hit below an airborne car redefining its support plane.
	for index: int in range(WHEEL_COUNT):
		if _load_active[index]:
			sum += _contact_normals[index]
			count += 1
	if count == 0 or sum.length_squared() < 0.0001:
		return Vector3.UP
	return sum.normalized()


func _update_slip_measurement(planar_velocity: Vector3) -> void:
	var support_up: Vector3 = _support_normal()
	var forward_axis: Vector3 = global_transform.basis.z.slide(support_up)
	if forward_axis.length_squared() < 0.0001:
		slip_angle_degrees = 0.0
		return
	forward_axis = forward_axis.normalized()
	var side_axis: Vector3 = support_up.cross(forward_axis)
	if side_axis.length_squared() < 0.0001:
		slip_angle_degrees = 0.0
		return
	side_axis = side_axis.normalized()
	var longitudinal_speed: float = planar_velocity.dot(forward_axis)
	var lateral_speed: float = planar_velocity.dot(side_axis)
	slip_angle_degrees = rad_to_deg(atan2(lateral_speed, maxf(absf(longitudinal_speed), 0.5)))


func _update_wheel_visuals(delta: float) -> void:
	for index: int in range(WHEEL_COUNT):
		var steer_pivot: Node3D = wheel_steer_pivots[index]
		var spin_pivot: Node3D = wheel_spin_pivots[index]
		steer_pivot.position.y = -_spring_lengths[index]
		steer_pivot.rotation.y = _wheel_steer_angle(index)

		var wheel_forward: Vector3 = Basis(global_transform.basis.y.normalized(), _wheel_steer_angle(index)) * global_transform.basis.z.normalized()
		var wheel_speed: float = linear_velocity.dot(wheel_forward)
		if _contact_active[index]:
			wheel_speed = get_velocity_at_world_point(_contact_points[index]).dot(wheel_forward)
		_wheel_spin_angles[index] = wrapf(_wheel_spin_angles[index] + (wheel_speed / WHEEL_RADIUS) * delta, -PI, PI)
		spin_pivot.rotation.x = _wheel_spin_angles[index]


func _update_reset() -> void:
	var reset_down: bool = Input.is_key_pressed(KEY_R)
	if reset_down and not _reset_was_down:
		reset_vehicle()
	_reset_was_down = reset_down


func reset_vehicle() -> void:
	var reset_transform: Transform3D = _spawn_transform
	reset_transform.origin += Vector3.UP * 0.04
	global_transform = reset_transform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_drive_speed = 0.0
	_steer_fraction = 0.0
	_steering_angle = 0.0
	_front_left_angle = 0.0
	_front_right_angle = 0.0
	_curvature_state = 0.0
	_held_steer_sign = 0.0
	_held_steer_cap = deg_to_rad(LOW_SPEED_MAX_STEER_DEG)
	_normal_mode = false
	_airborne_time = 0.0
	_physics_override_time = 0.0
	_handbrake_was_active = false
	normal_drive_locked = false
	_impact_recovery_cooldown = 0.0
	steering_degrees = 0.0
	steering_limit_degrees = LOW_SPEED_MAX_STEER_DEG
	commanded_turn_radius = 0.0
	target_yaw_rate_degrees = 0.0
	front_tire_slip_degrees = 0.0
	rear_tire_slip_degrees = 0.0
	boost_active = false
	boost_amount = 0.0
	handbrake_active = false
	drive_force_newtons = 0.0
	for index: int in range(WHEEL_COUNT):
		_wheel_spin_angles[index] = 0.0
	_reset_accessory_motion()
	sleeping = false
