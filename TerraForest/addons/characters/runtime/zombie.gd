extends CharacterBody3D
## Modular zombie controller. CC0-1.0. Godot 4.5+, no addons.
## See assets/zombie.revisions.json and README.md for the model profiles.
## A severed chain is baked once at its CURRENT pose into articulated rigid parts.
## The remaining corpse uses native, constrained PhysicalBone3D simulation.

signal damaged(part: String, remaining: float)
signal limb_severed(part: String)
signal died()
signal attack_landed(damage: float)
signal attack_started(action: String)
signal attack_contact(action: String, damage: float, world_point: Vector3)
signal attack_missed(action: String, reason: String)
signal action_finished(action: String)
signal movement_mode_changed(mode: String)

const MODEL_PATH := "res://addons/characters/runtime/assets/Zombie.r4.glb"
const DRAG_WALK = preload("res://addons/characters/runtime/assets/Zombie.drag_walk.res")
const DRAG_WALK_REFERENCE_SPEED := 0.45
const WORLD_LAYER := 1
const PLAYER_LAYER := 2
const CHARACTER_LAYER := 1 << 16
const HIT_LAYER := 1 << 17
const RAGDOLL_LAYER := 1 << 18
const BODY_COLLISION_MASK := WORLD_LAYER | PLAYER_LAYER | 4 | RAGDOLL_LAYER
const DETACHED_COLLISION_MASK := WORLD_LAYER | PLAYER_LAYER | 4 | CHARACTER_LAYER | RAGDOLL_LAYER
const SOLE_FRICTION := 0.2
const ANIMATION_FPS := 60.0
# R4 action identity is independent of the preserved Original/R2 attack.
# Contact is tested against the evaluated hand/head mesh at the clip marker.
const R4_ATTACKS := {
	"bite": {"clip": "Zombie_Attack_Bite", "reach": 0.64, "damage": 1.15, "parts": ["head"], "angle": 52.0},
	"left": {"clip": "Zombie_Attack_Left", "reach": 1.12, "damage": 0.85, "parts": ["hand_l"], "angle": 66.0},
	"right": {"clip": "Zombie_Attack_Right", "reach": 1.16, "damage": 1.0, "parts": ["hand_r"], "angle": 66.0},
	"both": {"clip": "Zombie_Attack_Both", "reach": 1.10, "damage": 1.5, "parts": ["hand_l", "hand_r"], "angle": 58.0},
	"crawl_bite": {"clip": "Zombie_Crawl_Bite", "reach": 0.86, "damage": 0.85, "parts": ["head"], "angle": 58.0}
}
# Contact depenetration uses a velocity channel separate from joint constraints.
# Recover fitted shapes gradually so one body is not pushed away from its joint.
const CONTACT_RECOVERY_BIAS := 0.1
const PARTS := {
	"torso": {"mesh": "Torso", "bone": "Spine2", "tip": "Neck", "radius": 0.17, "mass": 19.0, "health": 180.0, "parent": ""},
	"head": {"mesh": "Head", "bone": "Head", "tip": "", "radius": 0.105, "mass": 4.5, "health": 50.0, "parent": "torso"},
	"upper_arm_l": {"mesh": "UpperArm_L", "bone": "LeftArm", "tip": "LeftForeArm", "radius": 0.057, "mass": 2.2, "health": 50.0, "parent": "torso"},
	"forearm_l": {"mesh": "Forearm_L", "bone": "LeftForeArm", "tip": "LeftHand", "radius": 0.045, "mass": 1.5, "health": 38.0, "parent": "upper_arm_l"},
	"hand_l": {"mesh": "Hand_L", "bone": "LeftHand", "tip": "", "radius": 0.042, "mass": 0.5, "health": 24.0, "parent": "forearm_l"},
	"upper_arm_r": {"mesh": "UpperArm_R", "bone": "RightArm", "tip": "RightForeArm", "radius": 0.057, "mass": 2.2, "health": 50.0, "parent": "torso"},
	"forearm_r": {"mesh": "Forearm_R", "bone": "RightForeArm", "tip": "RightHand", "radius": 0.045, "mass": 1.5, "health": 38.0, "parent": "upper_arm_r"},
	"hand_r": {"mesh": "Hand_R", "bone": "RightHand", "tip": "", "radius": 0.042, "mass": 0.5, "health": 24.0, "parent": "forearm_r"},
	"thigh_l": {"mesh": "Thigh_L", "bone": "LeftUpLeg", "tip": "LeftLeg", "radius": 0.088, "mass": 7.0, "health": 65.0, "parent": "torso"},
	"shin_l": {"mesh": "Shin_L", "bone": "LeftLeg", "tip": "LeftFoot", "radius": 0.062, "mass": 3.2, "health": 52.0, "parent": "thigh_l"},
	"foot_l": {"mesh": "Foot_L", "bone": "LeftFoot", "tip": "LeftToeBase", "radius": 0.053, "mass": 1.0, "health": 32.0, "parent": "shin_l"},
	"thigh_r": {"mesh": "Thigh_R", "bone": "RightUpLeg", "tip": "RightLeg", "radius": 0.088, "mass": 7.0, "health": 65.0, "parent": "torso"},
	"shin_r": {"mesh": "Shin_R", "bone": "RightLeg", "tip": "RightFoot", "radius": 0.062, "mass": 3.2, "health": 52.0, "parent": "thigh_r"},
	"foot_r": {"mesh": "Foot_R", "bone": "RightFoot", "tip": "RightToeBase", "radius": 0.053, "mass": 1.0, "health": 32.0, "parent": "shin_r"}
}

@export var model_scene: PackedScene
@export_file("*.glb") var model_path := MODEL_PATH
@export var revision_id := "r4"
@export_file("*.json") var behavior_contract_path := ""
@export var attack_strike_seconds := 0.6398
@export var walk_reference_speed := 0.72 # Preserved original walk's reference.
@export var dragging_walk := true
@export var behavior_enabled := false
@export var walk_speed := 0.72
@export var chase_speed_multiplier := 1.2
@export var crawl_speed_multiplier := 1.25
@export var attack_distance := 1.25
@export var attack_damage := 12.0
@export var turn_speed := 3.6
@export var gravity := 9.8

var target: Node3D
var crowd_steering := Vector3.ZERO
var navigator: Node3D
var navigation_target := Vector3.INF
var behavior_goal := Vector3.INF
var awareness_state := "idle"
var navigation_attack_clear := true
var navigation_motor: RefCounted
var alive := true
var state := "idle"
var health := 180.0
var limb_health: Dictionary = {}
var anatomy:RefCounted
var geometry_template:RefCounted
var missing: Dictionary = {}
var part_meshes: Dictionary = {}
var caps: Dictionary = {}
var hit_areas: Dictionary = {}
var physical_bones: Dictionary = {}
var detached_parts: Array[RigidBody3D] = []
var collision_exemptions: Array[Dictionary] = []
var skeleton: Skeleton3D
var animation_player: AnimationPlayer
var simulator: PhysicalBoneSimulator3D
var model: Node3D
var capsule: CollisionShape3D
var initialized := false
var _death_pose: Array[Transform3D] = []
var _body_specs: Dictionary = {}
var _shape_cache: Dictionary = {}
var _attack_timer := 0.0
var _attack_sent := false
var _hit_timer := 0.0
var _current_clip := ""
var _manual_clip := ""
var _death_velocity := Vector3.ZERO
var behavior_contract: Dictionary = {}
var _r4_enabled := false
var _active_action := ""
var _action_time := 0.0
var _last_attack := ""
var _attack_sequence := 0
var _contact_count := 0
var _miss_count := 0
var _last_contact: Dictionary = {}
var _last_rejection := ""
var _action_cooldown := 0.0
var _crawling := false
var _crawl_transition := false
var _movement_mode := "standing"
var _traversal_state := "none"
var _jump_took_off := false
var _jump_landed := false
var _jump_direction := Vector3.ZERO
var _jump_forward_speed := 0.7
var _model_origin := Vector3.ZERO
var _saved_floor_snap := 0.1
var _ladder: Dictionary = {}
var _ladder_time := 0.0
var _ladder_blocked_time := 0.0
var _crawl_shape_fraction := 0.0
var _contact_standoff := INF
var _tracked_target_id := 0
var _animation_cursor_valid := false
var initialization_us:Dictionary={}


func _ready() -> void:
	configure(model_scene)


func configure(scene: PackedScene = null) -> void:
	if initialized:
		return
	var measured_begin:=Time.get_ticks_usec()
	if scene == null:
		scene = load(model_path) as PackedScene
	if scene == null:
		push_error("Zombie model was not found: " + model_path)
		return
	model_scene = scene
	model = scene.instantiate() as Node3D
	model.name = "Model"
	add_child(model)
	skeleton = _find_type(model, "Skeleton3D") as Skeleton3D
	animation_player = _find_type(model, "AnimationPlayer") as AnimationPlayer
	if animation_player!=null and revision_id=="r4":
		animation_player.add_animation_library("drag_walk",DRAG_WALK)
	if skeleton == null:
		push_error("Zombie model requires a Skeleton3D.")
		return
	initialization_us["scene"]=Time.get_ticks_usec()-measured_begin;measured_begin=Time.get_ticks_usec()
	for part: String in PARTS:
		var spec: Dictionary = PARTS[part]
		limb_health[part] = float(spec.health)
		missing[part] = false
		var mesh := model.find_child("Z_" + String(spec.mesh), true, false) as MeshInstance3D
		if mesh != null:
			part_meshes[part] = mesh
			mesh.set_meta("limb_key", part)
		else:
			push_warning("Missing zombie mesh: Z_" + String(spec.mesh))
		if part != "torso":
			var pair := {}
			for side: String in ["body", "detached"]:
				var cap := model.find_child("Z_Cap_" + String(spec.mesh) + "_" + side, true, false) as MeshInstance3D
				if cap != null:
					cap.hide()
					pair[side] = cap
			caps[part] = pair
	collision_layer = CHARACTER_LAYER
	collision_mask = 15 | CHARACTER_LAYER
	floor_max_angle = deg_to_rad(45.0)
	capsule = CollisionShape3D.new()
	capsule.name = "MovementCapsule"
	var shape := CapsuleShape3D.new()
	shape.radius = 0.24
	shape.height = 1.74
	capsule.shape = shape
	capsule.position.y = shape.height * 0.5
	add_child(capsule)
	initialization_us["parts"]=Time.get_ticks_usec()-measured_begin;measured_begin=Time.get_ticks_usec()
	anatomy=ClassDB.instantiate("NativeZombieAnatomy")
	if anatomy==null or not anatomy.configure(PARTS) or not anatomy.set_hit_meshes(skeleton,part_meshes,geometry_template):
		push_error("Zombie native anatomy initialization failed");return
	geometry_template=null
	initialization_us["anatomy"]=Time.get_ticks_usec()-measured_begin;measured_begin=Time.get_ticks_usec()
	_fit_collision_shapes()
	if _shape_cache.size()!=15:
		push_error("Zombie collision geometry initialization failed");return
	initialization_us["shape fit"]=Time.get_ticks_usec()-measured_begin;measured_begin=Time.get_ticks_usec()
	_build_hit_areas()
	initialization_us["hit areas"]=Time.get_ticks_usec()-measured_begin;measured_begin=Time.get_ticks_usec()
	_build_ragdoll()
	initialization_us["ragdoll"]=Time.get_ticks_usec()-measured_begin;measured_begin=Time.get_ticks_usec()
	initialized = true
	_load_behavior_contract()
	_model_origin = model.position
	_play_animation("Zombie_Idle")
	if animation_player != null:
		animation_player.advance(0.0)
	initialization_us["animation"]=Time.get_ticks_usec()-measured_begin
	print("Zombie ready: ", part_meshes.size(), " parts, ", hit_areas.size(), " hit regions, ", physical_bones.size(), " physical bones.")


func _find_type(node: Node, type_name: String) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var found := _find_type(child, type_name)
		if found != null:
			return found
	return null


func _shape_spec(part: String) -> Dictionary:
	if _shape_cache.has(part):
		return _shape_cache[part]
	var spec: Dictionary = PARTS[part]
	var length := 0.15
	var offset := Vector3(0, 0.065, 0)
	var bone := skeleton.find_bone(String(spec.bone))
	var tip := skeleton.find_bone(String(spec.tip)) if spec.tip != "" else -1
	var basis := Basis.IDENTITY
	if bone >= 0 and tip >= 0:
		var head_pose := skeleton.get_bone_global_rest(bone)
		var end := head_pose.affine_inverse() * skeleton.get_bone_global_rest(tip).origin
		length = maxf(end.length(), 0.08)
		offset = end * 0.5
		basis = Basis(Quaternion(Vector3.UP, end.normalized()))
	if part == "torso":
		length = 0.40
		offset = Vector3(0, -0.07, 0)
	elif part == "head":
		length = 0.24
		offset = Vector3(0, 0.095, 0)
	elif part.begins_with("hand"):
		length = 0.17
		offset = Vector3(0, 0.075, 0)
	elif part.begins_with("foot"):
		# A capsule along the sloping ankle-to-toe bone extends below the sole.
		# Keep the foot proxy level in the rest stance, with clearance above the
		# floor, so starting a ragdoll does not force its ankles apart.
		var foot_rest := skeleton.get_bone_global_rest(bone)
		var center := foot_rest * offset
		center.y = foot_rest.origin.y - 0.024
		var foot_box := BoxShape3D.new()
		foot_box.size = Vector3(0.112, 0.105, 0.24)
		foot_box.margin = 0.005
		return {
			"shape": foot_box,
			"offset": foot_rest.affine_inverse() * Transform3D(Basis.IDENTITY, center),
			"length": 0.24
		}
	var shape := CapsuleShape3D.new()
	shape.radius = float(spec.radius)
	shape.height = maxf(length, shape.radius * 2.0 + 0.005)
	shape.margin = 0.008
	return {"shape": shape, "offset": Transform3D(basis, offset), "length": length}


func _fit_collision_shapes() -> void:
	_shape_cache=anatomy.fit_collision_shapes()


func _pose_shape_spec(part: String, pelvis: bool = false) -> Dictionary:
	var key := "pelvis" if pelvis else part
	if not _shape_cache.has(key) or not part_meshes.has(part):
		return _shape_spec(part)
	var info: Dictionary = _shape_cache[key].duplicate()
	var bone_name := "Hips" if pelvis else String(PARTS[part].bone)
	var index := skeleton.find_bone(bone_name)
	var body_world := skeleton.global_transform * _current_bone_pose(index) * Transform3D(info.offset)
	var all_points:PackedVector3Array=anatomy.sample_vertices(part,body_world.affine_inverse())
	var points := PackedVector3Array()
	if info.has("source_indices"):
		for vertex: int in info.source_indices:
			points.append(all_points[vertex])
	else:
		points = all_points
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	shape.margin = 0.003
	shape.custom_solver_bias = CONTACT_RECOVERY_BIAS
	info.shape = shape
	return info


func _refresh_pose_collision_shapes() -> void:
	# Sample the evaluated skin once at death. This preserves curled fingers and
	# blended joint boundaries, then freezes the proxy with its rigid segment.
	# Body offsets stay unchanged so the joint's anchor never jumps on refit.
	for bone_name: String in physical_bones:
		var body: PhysicalBone3D = physical_bones[bone_name]
		var pelvis := bone_name == "Hips"
		var part := String(body.get_meta("limb_key"))
		var info := _pose_shape_spec(part, pelvis)
		if _r4_enabled and part.begins_with("hand"):
			var body_world := skeleton.global_transform * _current_bone_pose(body.get_bone_id()) * body.body_offset
			_install_hand_compound(body, part, body_world.affine_inverse())
		else:
			for child in body.get_children():
				if child is CollisionShape3D:
					child.shape = info.shape
		var area: Area3D = skeleton.find_child("Hit_pelvis", true, false) as Area3D if pelvis else hit_areas.get(part)
		if area != null:
			for child in area.get_children():
				if child is CollisionShape3D:
					child.shape = info.shape


func _install_hand_compound(body: PhysicsBody3D, part: String, to_local: Transform3D) -> void:
	# A single hull fills the opening between a curled palm and its fingers.
	# Around a ladder rung that creates a deep fictitious intersection. Keep
	# the real grip opening with native hulls per palm/finger bone segment.
	var groups:Dictionary=anatomy.hand_groups(part,to_local)
	for child in body.get_children():
		if child is CollisionShape3D:
			body.remove_child(child)
			child.queue_free()
	var installed: Array[String] = []
	for group: String in groups:
		var points: PackedVector3Array = groups[group]
		if points.size() < 4:
			continue
		var shape := ConvexPolygonShape3D.new()
		shape.points = points
		shape.margin = 0.002
		shape.custom_solver_bias = CONTACT_RECOVERY_BIAS
		var collision := CollisionShape3D.new()
		collision.name = "Grip_" + group
		collision.shape = shape
		body.add_child(collision)
		installed.append(group)
	body.set_meta("hand_proxy_groups", installed)


func _build_hit_areas() -> void:
	for part: String in PARTS:
		var bone := skeleton.find_bone(String(PARTS[part].bone))
		if bone < 0:
			continue
		var attachment := BoneAttachment3D.new()
		attachment.name = "HitAnchor_" + part
		skeleton.add_child(attachment)
		attachment.bone_name = String(PARTS[part].bone)
		var area := Area3D.new()
		area.name = "Hit_" + part
		area.collision_layer = HIT_LAYER
		area.collision_mask = 0
		area.monitoring = false
		area.monitorable = true
		area.set_meta("limb_key", part)
		area.set_meta("zombie", self)
		attachment.add_child(area)
		var shape_info := _shape_spec(part)
		var shape_node := CollisionShape3D.new()
		shape_node.shape = shape_info.shape
		shape_node.transform = shape_info.offset
		area.add_child(shape_node)
		hit_areas[part] = area
	# A separate pelvis hit area maps to torso health and closes the abdomen gap.
	var pelvis := BoneAttachment3D.new()
	pelvis.name = "HitAnchor_pelvis"
	skeleton.add_child(pelvis)
	pelvis.bone_name = "Hips"
	var area := Area3D.new()
	area.name = "Hit_pelvis"
	area.collision_layer = HIT_LAYER
	area.collision_mask = 0
	area.monitoring = false
	area.set_meta("limb_key", "torso")
	area.set_meta("zombie", self)
	pelvis.add_child(area)
	var shape_node := CollisionShape3D.new()
	if _shape_cache.has("pelvis"):
		shape_node.shape = _shape_cache.pelvis.shape
		shape_node.transform = _shape_cache.pelvis.offset
	else:
		var box := BoxShape3D.new()
		box.size = Vector3(0.32, 0.28, 0.24)
		shape_node.shape = box
	area.add_child(shape_node)


func _build_ragdoll() -> void:
	simulator = PhysicalBoneSimulator3D.new()
	simulator.name = "RagdollSimulator"
	skeleton.add_child(simulator)
	simulator.active = false
	_add_physical_bone("Hips", "torso", true)
	for part: String in PARTS:
		_add_physical_bone(String(PARTS[part].bone), part, false)
	# Neighboring proxies meet or overlap at a shared joint. Every other pair
	# remains collidable, including opposite limbs and hands against the torso.
	for bone_name: String in physical_bones:
		var physical: PhysicalBone3D = physical_bones[bone_name]
		var ancestor := skeleton.get_bone_parent(physical.get_bone_id())
		while ancestor >= 0:
			var ancestor_name := skeleton.get_bone_name(ancestor)
			if physical_bones.has(ancestor_name):
				_exempt_joint_neighbors(physical, physical_bones[ancestor_name])
				break
			ancestor = skeleton.get_bone_parent(ancestor)


func _exempt_joint_neighbors(body_a: PhysicsBody3D, body_b: PhysicsBody3D) -> void:
	body_a.add_collision_exception_with(body_b)
	body_b.add_collision_exception_with(body_a)
	collision_exemptions.append({"body_a": body_a, "body_b": body_b, "reason": "direct_joint_neighbors"})


func _remove_body_exceptions(body: PhysicsBody3D) -> void:
	# Godot's body exception list can retain a freed body's RID. Remove both
	# directions while both objects still exist, before severing either body.
	var kept: Array[Dictionary] = []
	for entry in collision_exemptions:
		if not is_instance_valid(entry.body_a) or not is_instance_valid(entry.body_b):
			continue
		if entry.body_a == body or entry.body_b == body:
			entry.body_a.remove_collision_exception_with(entry.body_b)
			entry.body_b.remove_collision_exception_with(entry.body_a)
		else:
			kept.append(entry)
	collision_exemptions = kept


func get_collision_policy() -> Dictionary:
	# Diagnostics describe the actual pair exclusions; there is no per-zombie
	# blanket exception and no exception between an arm and its own hand.
	var pairs: Array[Dictionary] = []
	for entry in collision_exemptions:
		if is_instance_valid(entry.body_a) and is_instance_valid(entry.body_b):
			pairs.append({
				"a": String(entry.body_a.name), "b": String(entry.body_b.name),
				"reason": String(entry.reason), "body_a": entry.body_a, "body_b": entry.body_b
			})
	return {
		"ragdoll_layer": RAGDOLL_LAYER, "ragdoll_mask": BODY_COLLISION_MASK,
		"detached_mask": DETACHED_COLLISION_MASK, "excluded_pairs": pairs
	}


func _add_physical_bone(bone_name: String, part: String, pelvis: bool) -> void:
	var index := skeleton.find_bone(bone_name)
	if index < 0:
		return
	var physical:PhysicalBone3D=ClassDB.instantiate("NativeZombiePhysicalBone")
	physical.disable_mode=CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	physical.name = "Physical_" + bone_name
	physical.collision_layer = 0
	physical.collision_mask = 0
	physical.mass = 10.0 if pelvis else float(PARTS[part].mass)
	# Let a falling foot slide instead of pinning its sole and stretching the
	# ankle while the much heavier leg and torso continue to fall.
	physical.friction = SOLE_FRICTION if part.begins_with("foot") else 0.85
	physical.bounce = 0.0
	physical.linear_damp = 0.12
	physical.angular_damp = 0.6
	physical.can_sleep = true
	physical.set_meta("limb_key", part)
	physical.set_meta("zombie", self)
	simulator.add_child(physical)
	physical.set("bone_name", bone_name)
	# PhysicalBone3D does not expose the RigidBody3D continuous_cd property.
	# Enable the same native server feature to catch fast limb/body contacts.
	PhysicsServer3D.body_set_enable_continuous_collision_detection(physical.get_rid(), true)
	var shape_node := CollisionShape3D.new()
	var info := _shape_spec(part)
	if pelvis:
		if _shape_cache.has("pelvis"):
			shape_node.shape = _shape_cache.pelvis.shape
			physical.body_offset = _shape_cache.pelvis.offset
		else:
			var box := BoxShape3D.new()
			box.size = Vector3(0.28, 0.21, 0.22)
			box.margin = 0.008
			shape_node.shape = box
			physical.body_offset = Transform3D.IDENTITY
	else:
		shape_node.shape = info.shape
		physical.body_offset = info.offset
	physical.add_child(shape_node)
	# ConeTwist uses local X as its twist axis. Blender bones extend along Y.
	# Rotating the joint frame aligns the limited twist with the limb length.
	physical.joint_offset = physical.body_offset.affine_inverse() * Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3.ZERO)
	if pelvis:
		physical.joint_type = PhysicalBone3D.JOINT_TYPE_NONE
	else:
		physical.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
		var swing := 35.0
		var twist := 25.0
		if part.begins_with("upper_arm"):
			swing = 75.0
			twist = 45.0
		elif part.begins_with("thigh"):
			swing = 45.0
		elif part.begins_with("forearm") or part.begins_with("shin"):
			# The cone acts as a conservative flexible elbow/knee, with limited twist.
			# Its frame starts at the sampled live pose; no snapping to bind pose.
			swing = 55.0
			twist = 8.0
		elif part == "head":
			swing = 30.0
			twist = 32.0
		elif part == "torso":
			swing = 24.0
			twist = 20.0
		physical.set("joint_constraints/swing_span", swing)
		physical.set("joint_constraints/twist_span", twist)
		physical.set("joint_constraints/bias", 0.3)
		physical.set("joint_constraints/softness", 0.85)
		physical.set("joint_constraints/relaxation", 1.0)
		if part.begins_with("hand") or part.begins_with("foot") or part.begins_with("forearm"):
			# Lock translation when a bent forearm bears against the torso.
			# The same constraint keeps wrists and ankles attached on impact.
			var ankle := part.begins_with("foot")
			var elbow := part.begins_with("forearm")
			physical.joint_type = PhysicalBone3D.JOINT_TYPE_6DOF
			if not elbow:
				physical.mass = 1.25 if ankle else 0.75
				physical.angular_damp = 1.5
			for axis: String in ["x", "y", "z"]:
				var prefix := "joint_constraints/" + axis + "/"
				physical.set(prefix + "linear_limit_enabled", true)
				physical.set(prefix + "linear_limit_lower", 0.0)
				physical.set(prefix + "linear_limit_upper", 0.0)
				physical.set(prefix + "linear_limit_softness", 0.95)
				# Godot's 6DOF positional recovery uses this nonzero default.
				physical.set(prefix + "linear_restitution", 0.5)
				physical.set(prefix + "linear_damping", 1.0)
				physical.set(prefix + "angular_limit_enabled", true)
				var limit := (12.0 if axis == "x" else 25.0) if ankle else (18.0 if axis == "x" else 30.0)
				if elbow:
					limit = 8.0 if axis == "x" else 55.0
				physical.set(prefix + "angular_limit_lower", -limit)
				physical.set(prefix + "angular_limit_upper", limit)
				physical.set(prefix + "angular_limit_softness", 0.85)
				physical.set(prefix + "angular_restitution", 0.0)
				physical.set(prefix + "angular_damping", 1.0)
				physical.set(prefix + "erp", 0.15)
	physical_bones[bone_name] = physical
	_body_specs[bone_name] = {"part": part, "offset": physical.body_offset}


func _load_behavior_contract() -> void:
	if revision_id != "r4":
		return
	var path := behavior_contract_path if not behavior_contract_path.is_empty() else model_path.get_basename() + ".behavior.json"
	if not FileAccess.file_exists(path):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or String(parsed.get("revision_id", "")) != "r4":
		return
	behavior_contract = parsed
	if not behavior_contract.get("actions", {}) is Dictionary:
		return
	for clip: String in behavior_contract.actions:
		if _animation_key(clip).is_empty():
			return
	_r4_enabled = true
	# R4 playback and its physical controller advance on the same clock. A
	# paused inspector remains paused because advance is called only if playing.
	animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for clip: String in behavior_contract.actions:
		animation_player.get_animation(_animation_key(clip)).loop_mode = Animation.LOOP_LINEAR if bool(behavior_contract.actions[clip].get("loop", false)) else Animation.LOOP_NONE


func _animation_key(clip: String) -> String:
	if animation_player == null:
		return ""
	if animation_player.has_animation(clip):
		return clip
	for candidate in animation_player.get_animation_list():
		if String(candidate).get_file() == clip:
			return String(candidate)
	return ""


func _action_spec(clip: String) -> Dictionary:
	return behavior_contract.get("actions", {}).get(clip, {})


func _action_duration(clip: String, fallback: float) -> float:
	return float(_action_spec(clip).get("duration_seconds", fallback))


func _has_full_arm(side: String) -> bool:
	for part: String in ["upper_arm_" + side, "forearm_" + side, "hand_" + side]:
		if missing.get(part, false):
			return false
	return true


func _has_standing_legs() -> bool:
	for part: String in ["thigh_l", "thigh_r", "shin_l", "shin_r", "foot_l", "foot_r"]:
		if missing.get(part, false):
			return false
	return true


func _attack_is_eligible(action: String) -> bool:
	if not _r4_enabled or not alive or not R4_ATTACKS.has(action) or missing.get("head", false):
		return false
	if _crawling:
		return action == "crawl_bite"
	if _crawl_transition or action == "crawl_bite":
		return false
	if action == "left":
		return _has_full_arm("l")
	if action == "right":
		return _has_full_arm("r")
	if action == "both":
		return _has_full_arm("l") and _has_full_arm("r")
	return action == "bite"


func get_available_attacks() -> Array[String]:
	var actions: Array[String] = []
	for action: String in R4_ATTACKS:
		if _attack_is_eligible(action):
			actions.append(action)
	return actions


func _normalize_attack(action: String) -> String:
	for key: String in R4_ATTACKS:
		if action == String(R4_ATTACKS[key].clip):
			return key
	if action == "bite" and _crawling:
		return "crawl_bite"
	return action


func _target_distance() -> float:
	if not is_instance_valid(target):
		return INF
	var offset := target.global_position - global_position
	offset.y = 0.0
	return offset.length()


func _choose_attack() -> String:
	var choices: Array[String] = []
	var distance := _target_distance()
	for action: String in get_available_attacks():
		if distance <= float(R4_ATTACKS[action].reach):
			choices.append(action)
	if choices.size() > 1:
		choices.erase(_last_attack)
	if choices.is_empty():
		return ""
	# Deterministic rotation makes variety repeatable in the lab while still
	# responding to the actual range and available anatomy on every attack.
	var order: Array = R4_ATTACKS.keys()
	for offset in order.size():
		var index := (_attack_sequence + offset) % order.size()
		var candidate := String(order[index])
		if choices.has(candidate):
			_attack_sequence = (index + 1) % order.size()
			return candidate
	return ""


func request_attack(action: String = "") -> bool:
	if not _r4_enabled or not initialized or not alive:
		_last_rejection = "R4 behavior assets are required"
		return false
	if not _active_action.is_empty() or _hit_timer > 0.0 or _action_cooldown > 0.0:
		_last_rejection = "Another action is recovering"
		return false
	action = _choose_attack() if action.is_empty() else _normalize_attack(action)
	if not _attack_is_eligible(action):
		_last_rejection = "Attack requires an available head and its specified limb chain"
		return false
	if not is_instance_valid(target) or _target_distance() > float(R4_ATTACKS[action].reach):
		_last_rejection = "Target is outside this attack's reach"
		return false
	_manual_clip = ""
	_active_action = action
	_action_time = 0.0
	_attack_timer = 0.0
	_attack_sent = false
	_last_rejection = ""
	_last_attack = action
	state = "crawl_attack" if _crawling else "attack"
	velocity.x = 0.0
	velocity.z = 0.0
	_play_animation(String(R4_ATTACKS[action].clip), true)
	animation_player.advance(0.0)
	attack_started.emit(action)
	return true


func get_crawl_speed() -> float:
	if not _r4_enabled:
		return 0.0
	var arms := 0
	var condition := 1.0
	for side: String in ["l", "r"]:
		if _has_full_arm(side):
			arms += 1
			condition *= _arm_condition(side)
	return float(behavior_contract.get("crawl", {}).get("authored_speed_mps", 0.32)) * crawl_speed_multiplier * (0.0 if arms == 0 else 0.58 if arms == 1 else 1.0) * condition

func _arm_condition(side:String)->float:
	if not _has_full_arm(side):return 0.0
	var condition:=1.0
	for section:String in ["upper_arm_","forearm_","hand_"]:
		var key:=section+side
		condition=minf(condition,lerpf(.65,1.0,float(limb_health[key])/float(PARTS[key].health)))
	return condition


func get_behavior_snapshot() -> Dictionary:
	return {
		"revision_id": revision_id, "r4_actions_enabled": _r4_enabled,
		"alive": alive, "state": state, "behavior_enabled": behavior_enabled,
		"movement_mode": _movement_mode, "active_action": _active_action,
		"action_time": _action_time, "contact_count": _contact_count,
		"miss_count": _miss_count, "last_contact": _last_contact.duplicate(true),
		"last_rejection": _last_rejection, "last_attack": _last_attack,
		"available_attacks": get_available_attacks(), "traversal_state": _traversal_state,
		"crawling": _crawling, "crawl_transition": _crawl_transition,
		"crawl_speed": get_crawl_speed(), "standing_legs": _has_standing_legs(),
		"left_arm": _has_full_arm("l"), "right_arm": _has_full_arm("r"),
		"target_distance": _target_distance() if is_instance_valid(target) else null, "clip": _current_clip,
		"awareness": awareness_state, "intent_goal": behavior_goal,
		"health":health,"maximum_health":PARTS.torso.health,"ragdoll":anatomy.ragdoll_stats() if anatomy!=null else {},
		"animation_time": animation_player.current_animation_position if animation_player != null and _animation_cursor_valid else 0.0,
		"learned_contact_distance": _contact_standoff if is_finite(_contact_standoff) else null,
		"grounded": is_on_floor(), "position": global_position, "velocity": velocity
	}


func _set_movement_mode(mode: String) -> void:
	if _movement_mode != mode:
		_movement_mode = mode
		movement_mode_changed.emit(mode)


func _finish_action() -> void:
	var finished := _active_action
	_active_action = ""
	_action_time = 0.0
	_attack_timer = 0.0
	_attack_sent = false
	if not finished.is_empty():
		action_finished.emit(finished)


func _cancel_attack() -> void:
	if R4_ATTACKS.has(_active_action):
		_active_action = ""
		_action_time = 0.0
		_attack_timer = 0.0
		_attack_sent = false


func _set_crawl_capsule(fraction: float) -> void:
	_crawl_shape_fraction = clampf(fraction, 0.0, 1.0)
	var shape := capsule.shape as CapsuleShape3D
	if shape == null:
		return
	shape.height = lerpf(1.74, 1.20, _crawl_shape_fraction)
	capsule.rotation.x = _crawl_shape_fraction * PI * 0.5
	# The prone head reaches about +0.63m. Keep this locomotion proxy behind
	# that contact surface, so its rounded front does not stop a bite early.
	capsule.position = Vector3(0.0, shape.radius + (shape.height * 0.5 - shape.radius) * cos(capsule.rotation.x), -0.12 * _crawl_shape_fraction)


func _start_crawl() -> void:
	if not _r4_enabled or not alive or _crawling or _crawl_transition:
		return
	_cancel_attack()
	cancel_traversal()
	_manual_clip = ""
	_hit_timer = 0.0
	_crawl_transition = true
	_active_action = "to_crawl"
	_action_time = 0.0
	state = "to_crawl"
	_set_movement_mode("to_crawl")
	_play_animation("Zombie_To_Crawl", true)
	animation_player.advance(0.0)


func _gravity_step(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = -0.1


func _physics_r4(delta: float) -> void:
	var target_id := target.get_instance_id() if is_instance_valid(target) else 0
	if target_id != _tracked_target_id:
		_tracked_target_id = target_id
		_contact_standoff = INF
	var animation_advancing := animation_player != null and animation_player.is_playing()
	if animation_advancing:
		animation_player.advance(delta)
	_action_cooldown = maxf(_action_cooldown - delta, 0.0)
	var was_hit := _hit_timer > 0.0
	_hit_timer = maxf(_hit_timer - delta, 0.0)
	velocity.x = move_toward(velocity.x, 0.0, delta * 4.0)
	velocity.z = move_toward(velocity.z, 0.0, delta * 4.0)
	if _traversal_state.begins_with("ladder"):
		_tick_ladder(delta)
		return
	if _active_action == "jump":
		_tick_jump(delta)
		return
	_gravity_step(delta)
	if _crawl_transition:
		# Inspection can pause or seek this transition while gravity stays live.
		# Derive the capsule and action cursor from the evaluated animation, so
		# a paused frame cannot silently finish the drop and switch to idle.
		if _animation_cursor_valid:
			_action_time = animation_player.current_animation_position
		var duration := _action_duration("Zombie_To_Crawl", 0.8)
		_set_crawl_capsule(smoothstep(0.0, duration, _action_time))
		if animation_advancing and _action_time + 0.00001 >= duration:
			_crawl_transition = false
			_crawling = true
			_set_crawl_capsule(1.0)
			_set_movement_mode("crawling")
			_finish_action()
			_play_animation("Zombie_Crawl_Idle")
		move_and_slide()
		return
	if _hit_timer > 0.0:
		state = "crawl_stagger" if _crawling else "stagger"
	elif not _active_action.is_empty() and R4_ATTACKS.has(_active_action):
		_tick_attack(delta)
	elif not _manual_clip.is_empty():
		state = "preview"
		if was_hit:
			_play_animation(_manual_clip)
	elif behavior_enabled and is_instance_valid(target):
		_tick_pursuit(delta)
	elif behavior_enabled and behavior_goal.is_finite():
		_tick_navigation(delta,behavior_goal,0.6)
	else:
		state = "crawl_idle" if _crawling else "idle"
		_play_animation("Zombie_Crawl_Idle" if _crawling else "Zombie_Idle")
	var movement_start := global_position
	if navigation_motor!=null and not _crawling:
		navigation_motor.move_grounded(self,delta)
	else:
		move_and_slide()
	if dragging_walk and not _crawling and state == "shamble" and _current_clip == _animation_key("Zombie_Walk_Drag_Right"):
		# The next pose advances by the distance the body actually travelled.
		# Collision/route guards can reduce a requested step to zero. Advancing
		# at the requested speed would make the planted boots skate in place.
		var travelled := global_position - movement_start
		travelled.y = 0.0
		animation_player.speed_scale = travelled.length() / maxf(delta * DRAG_WALK_REFERENCE_SPEED, 0.000001)


func _face_target(delta: float, factor: float = 1.0) -> void:
	if not is_instance_valid(target):
		return
	var offset := target.global_position - global_position
	offset.y = 0.0
	_face_direction(offset, delta, factor)


func _face_direction(offset: Vector3, delta: float, factor: float = 1.0) -> void:
	if offset.length_squared() > 0.0004:
		rotation.y = lerp_angle(rotation.y, atan2(offset.x, offset.z), minf(turn_speed * factor * delta, 1.0))


func _tick_pursuit(delta: float) -> void:
	var distance := _target_distance()
	var preferred_reach := 0.76 if _crawling else 0.62 if not _has_full_arm("l") and not _has_full_arm("r") else 0.96
	preferred_reach = minf(preferred_reach, _contact_standoff)
	if target.has_method("get_zombie_attack_radius"):
		# A learned contact distance cannot require interpenetrating the player.
		# Keep the prone proxy behind the mouth so this still fits bite reach.
		var shape := capsule.shape as CapsuleShape3D
		var front := shape.height * 0.5 + capsule.position.z if _crawling else shape.radius
		var target_radius := clampf(float(target.call("get_zombie_attack_radius")), 0.01, 0.60)
		preferred_reach = maxf(preferred_reach, front + target_radius + 0.02)
	if distance <= preferred_reach:
		_face_target(delta, 0.75 if _crawling else 1.0)
	if distance <= preferred_reach and navigation_attack_clear and _action_cooldown <= 0.0:
		if request_attack():
			return
	if distance > preferred_reach or not navigation_attack_clear:
		_tick_navigation(delta,target.global_position,0.0)
	else:
		state = "crawl_idle" if _crawling else "idle"
		_play_animation("Zombie_Crawl_Idle" if _crawling else "Zombie_Idle")


func _tick_navigation(delta:float,goal:Vector3,stop_distance:float)->void:
	var offset:=goal-global_position;offset.y=0
	if offset.length()>stop_distance:
		var direction := offset
		if is_instance_valid(navigator):
			if not navigation_target.is_finite() or global_position.distance_to(navigation_target)<0.025:
				velocity.x=0;velocity.z=0;state="crawl_idle" if _crawling else "idle"
				_play_animation("Zombie_Crawl_Idle" if _crawling else "Zombie_Idle")
				return
			direction=navigation_target-global_position
		direction.y = 0.0
		# The bounded host crowd supplies separation and a route past a peer.
		# Turn into that route so locomotion keeps following the facing pose.
		direction = (direction.normalized() + crowd_steering).normalized()
		_face_direction(direction, delta, 0.75 if _crawling else 1.0)
		var speed := get_crawl_speed() if _crawling else walk_speed * get_walk_multiplier()
		if not _crawling and awareness_state=="chase":speed*=chase_speed_multiplier
		if speed <= 0.0001:
			state = "crawl_idle" if _crawling else "idle"
			_play_animation("Zombie_Crawl_Idle" if _crawling else "Zombie_Idle")
			return
		var facing := global_basis.z
		facing.y = 0.0
		# Turn before committing to full speed; a zombie cannot strafe backwards
		# while its planted-foot animation still faces the target's old bearing.
		speed *= clampf((facing.normalized().dot(direction.normalized()) + 0.15) / 1.15, 0.0, 1.0)
		var movement := direction.normalized() * speed
		if is_instance_valid(navigator) and not navigator.guard_motion(get_instance_id(),movement,speed*delta):
			movement=Vector3.ZERO
		velocity.x = movement.x
		velocity.z = movement.z
		state = "crawl" if _crawling else "shamble"
		_play_animation("Zombie_Crawl" if _crawling else _standing_walk_clip())
		var authored_speed := float(behavior_contract.get("crawl", {}).get("authored_speed_mps", 0.32)) if _crawling else _standing_walk_reference_speed()
		animation_player.speed_scale = speed / authored_speed if authored_speed > 0.0001 else 1.0
	else:
		state = "crawl_idle" if _crawling else "idle"
		_play_animation("Zombie_Crawl_Idle" if _crawling else "Zombie_Idle")


func _tick_attack(delta: float) -> void:
	if not _attack_is_eligible(_active_action):
		_last_rejection = "Required attack limb was lost before contact"
		_cancel_attack()
		return
	var action := _active_action
	var spec: Dictionary = R4_ATTACKS[action]
	var contact_time := float(_action_spec(String(spec.clip)).get("contact_time_seconds", attack_strike_seconds))
	_action_time += delta
	_attack_timer = _action_time
	# Most turning happens during the tell. The strike keeps its committed
	# direction, allowing a moving target to evade it instead of being tracked.
	if _action_time < contact_time * 0.65:
		_face_target(delta, 0.5)
	if _action_time + 0.00001 >= contact_time and not _attack_sent:
		_attack_sent = true
		_attempt_contact(action)
	if _action_time + 0.00001 >= _action_duration(String(spec.clip), 1.6):
		_action_cooldown = 0.10
		_finish_action()


func _attempt_contact(action: String) -> void:
	var failure := ""
	var spec: Dictionary = R4_ATTACKS[action]
	if not _attack_is_eligible(action):
		failure = "limb unavailable"
	elif not is_instance_valid(target):
		failure = "target unavailable"
	elif _target_distance() > float(spec.reach):
		failure = "target moved out of range"
	else:
		var direction := target.global_position - global_position
		direction.y = 0.0
		if direction.length_squared() > 0.0004 and global_basis.z.dot(direction.normalized()) < cos(deg_to_rad(float(spec.angle))):
			failure = "target left the strike arc"
	var contact := {}
	if failure.is_empty():
		contact = _find_attack_contact(action)
		if not bool(contact.get("valid", false)):
			failure = String(contact.get("reason", "animated contact surface missed"))
	if not failure.is_empty():
		if failure == "animated contact surface missed" and contact.has("surface_gap"):
			var horizontal_gap := float(contact.get("horizontal_gap", 0.0))
			var vertical_gap := float(contact.get("vertical_gap", 0.0))
			# A thin pad can need a closer approach than a broad capsule. Learn
			# from the actual miss, then walk closer after recovery. Height or
			# wall failures do not cause the zombie to press into an obstacle.
			if horizontal_gap > vertical_gap * 0.75:
				var desired := _target_distance() - maxf(float(contact.surface_gap) - 0.018, 0.025)
				_contact_standoff = minf(_contact_standoff, maxf(0.73 if _crawling else 0.43, desired))
		_miss_count += 1
		_last_contact = {"action": action, "landed": false, "reason": failure, "action_time": _action_time, "surface_gap": contact.get("surface_gap", -1.0)}
		attack_missed.emit(action, failure)
		return
	var damage := attack_damage * float(spec.damage)
	for side: String in (["l"] if action == "left" else ["r"] if action == "right" else ["l", "r"] if action == "both" else []):
		damage *= _arm_condition(side)
	var point: Vector3 = contact.point
	var recipient := target
	_contact_count += 1
	_last_contact = {"action": action, "landed": true, "damage": damage, "point": point, "action_time": _action_time, "surface_distance": contact.surface_distance, "visible_target_shapes": contact.get("visible_target_shapes", false)}
	attack_contact.emit(action, damage, point)
	attack_landed.emit(damage)
	if is_instance_valid(recipient) and recipient.has_method("receive_zombie_attack"):
		recipient.call("receive_zombie_attack", damage)


func _find_attack_contact(action: String) -> Dictionary:
	if not is_instance_valid(target):
		return {"valid": false, "reason": "target unavailable"}
	skeleton.force_update_all_bone_transforms()
	var use_point := target.has_method("get_zombie_attack_target_point")
	var target_point: Vector3 = target.call("get_zombie_attack_target_point", action) if use_point else target.global_position
	if not target_point.is_finite():
		return {"valid": false, "reason": "invalid target contact position"}
	var radius := clampf(float(target.call("get_zombie_attack_radius")), 0.01, 0.60) if target.has_method("get_zombie_attack_radius") else 0.28
	var contact_shapes: Array = []
	if target.has_method("get_zombie_attack_contact_shapes"):
		var supplied = target.call("get_zombie_attack_contact_shapes", action)
		if supplied is Array:
			contact_shapes = supplied
	var best_distance := INF
	var best_point := Vector3.ZERO
	var best_target := target_point
	var mouth_region: Dictionary = behavior_contract.get("contact_regions", {}).get("mouth", {})
	var mouth_minimum: Array = mouth_region.get("bind_min_godot_m", [-0.027, 1.597, 0.098])
	var mouth_maximum: Array = mouth_region.get("bind_max_godot_m", [0.027, 1.624, 0.122])
	var mouth_min := Vector3(float(mouth_minimum[0]), float(mouth_minimum[1]), float(mouth_minimum[2]))
	var mouth_max := Vector3(float(mouth_maximum[0]), float(mouth_maximum[1]), float(mouth_maximum[2]))
	for part: String in R4_ATTACKS[action].parts:
		if not part_meshes.has(part) or missing.get(part, false):
			continue
		var contact:Dictionary=anatomy.closest_contact(part,target_point,use_point,contact_shapes,AABB(mouth_min,mouth_max-mouth_min))
		if not contact.is_empty() and contact.distance<best_distance:
			best_distance=contact.distance;best_point=contact.point;best_target=contact.target
	# A small swept-contact allowance covers the interval between integer pose
	# samples without extending the character's actual reach by another arm.
	if best_distance > (radius if contact_shapes.is_empty() else 0.0) + 0.055:
		var separation := best_target - best_point
		var horizontal := Vector2(separation.x, separation.z).length()
		return {"valid": false, "reason": "animated contact surface missed", "surface_distance": best_distance, "surface_gap": best_distance - (radius if contact_shapes.is_empty() else 0.0), "horizontal_gap": horizontal, "vertical_gap": absf(separation.y)}
	# Check from the body side of the stroke. Starting inside an extended hand
	# could miss a thin wall that the animated fingers had already crossed.
	var ray_origin := Vector3(global_position.x, best_point.y, global_position.z)
	var query := PhysicsRayQueryParameters3D.create(ray_origin, best_target, 7)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var collider = hit.get("collider")
		var intended_surface:bool=target.has_method("accepts_zombie_attack_surface") and bool(target.call("accepts_zombie_attack_surface",hit))
		var recipient_body:bool=collider is Node and (target.is_ancestor_of(collider) or collider.is_ancestor_of(target))
		if not intended_surface and collider != target and not recipient_body:
			return {"valid": false, "reason": "solid world object blocked contact"}
	return {"valid": true, "point": best_point, "surface_distance": best_distance, "visible_target_shapes": not contact_shapes.is_empty()}


func _closest_target_surface(shape: Dictionary, world_point: Vector3) -> Dictionary:
	if not shape.get("transform") is Transform3D:
		return {}
	var transform: Transform3D = shape.transform
	if not transform.is_finite() or absf(transform.basis.determinant()) < 0.000001:
		return {}
	var point := transform.affine_inverse() * world_point
	var closest := point
	if String(shape.get("type", "")) == "sphere":
		var radius := float(shape.get("radius", 0.0))
		if not is_finite(radius) or radius <= 0.0:
			return {}
		closest = point.limit_length(radius)
	elif String(shape.get("type", "")) == "box":
		if not shape.get("half_extents") is Vector3:
			return {}
		var half: Vector3 = shape.half_extents
		if not half.is_finite() or minf(half.x, minf(half.y, half.z)) <= 0.0:
			return {}
		closest = point.clamp(-half, half)
	else:
		return {}
	return {"point": transform * closest}


func request_jump(forward_speed: float = 0.70) -> bool:
	if not _r4_enabled or not alive or not _has_standing_legs() or _crawling or _crawl_transition:
		_last_rejection = "Jump requires both complete legs"
		return false
	if not _active_action.is_empty() or _hit_timer > 0.0 or not is_on_floor() or not is_finite(forward_speed):
		_last_rejection = "Jump requires a grounded zombie with no action in progress"
		return false
	_active_action = "jump"
	_action_time = 0.0
	_manual_clip = ""
	_jump_took_off = false
	_jump_landed = false
	_jump_forward_speed = clampf(forward_speed, 0.0, 1.8)
	_jump_direction = global_basis.z
	_jump_direction.y = 0.0
	_jump_direction = _jump_direction.normalized()
	_saved_floor_snap = floor_snap_length
	floor_snap_length = 0.0
	_traversal_state = "jump_anticipation"
	state = "jump"
	_set_movement_mode("jumping")
	_last_rejection = ""
	_play_animation("Zombie_Jump", true)
	animation_player.advance(0.0)
	return true


func _jump_authored_elevation(time: float) -> float:
	var samples: Array = behavior_contract.get("jump", {}).get("elevation_m", [])
	if samples.is_empty():
		return 0.0
	var frame := clampf(time * ANIMATION_FPS, 0.0, float(samples.size() - 1))
	var index := int(floor(frame))
	return lerpf(float(samples[index]), float(samples[mini(index + 1, samples.size() - 1)]), frame - index)


func _tick_jump(delta: float) -> void:
	if not _has_standing_legs():
		cancel_traversal()
		_start_crawl()
		return
	var jump: Dictionary = behavior_contract.get("jump", {})
	var takeoff_time := float(jump.get("takeoff_frame", 21)) / ANIMATION_FPS
	var landing_time := float(jump.get("landing_frame", 44)) / ANIMATION_FPS
	_action_time = animation_player.current_animation_position
	if not _jump_took_off and _action_time + 0.00001 >= takeoff_time:
		_jump_took_off = true
		# The half-step correction matches the authored continuous ballistic
		# curve while CharacterBody3D still resolves every physical contact.
		velocity.y = float(jump.get("takeoff_velocity_mps", 1.8783333333)) + gravity * delta * 0.5
		_traversal_state = "jump_airborne"
	elif _jump_took_off and not _jump_landed:
		velocity.y -= gravity * delta
	else:
		_gravity_step(delta)
	if _jump_took_off and not _jump_landed:
		velocity.x = _jump_direction.x * _jump_forward_speed
		velocity.z = _jump_direction.z * _jump_forward_speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, delta * 6.0)
		velocity.z = move_toward(velocity.z, 0.0, delta * 6.0)
	model.position.y = _model_origin.y - _jump_authored_elevation(_action_time)
	move_and_slide()
	if _jump_took_off and not _jump_landed and is_on_floor() and _action_time > takeoff_time + 0.025:
		_jump_landed = true
		_traversal_state = "jump_landing"
		animation_player.play(_current_clip, 0.0)
		animation_player.seek(landing_time, true)
		_action_time = landing_time
		model.position.y = _model_origin.y
	elif _jump_took_off and not _jump_landed and _action_time >= landing_time:
		# A ledge can make the real fall longer than the in-place preview.
		# Hold the pre-landing pose until actual floor contact arrives.
		animation_player.seek(landing_time - 1.0 / ANIMATION_FPS, true)
		animation_player.pause()
		_action_time = landing_time - 1.0 / ANIMATION_FPS
		model.position.y = _model_origin.y - _jump_authored_elevation(_action_time)
	if _jump_landed and _action_time + 0.00001 >= _action_duration("Zombie_Jump", 1.2):
		floor_snap_length = _saved_floor_snap
		model.position = _model_origin
		_traversal_state = "none"
		_set_movement_mode("standing")
		_finish_action()


func request_climb(ladder: Dictionary) -> bool:
	if not _r4_enabled or not alive or not _has_standing_legs() or not _has_full_arm("l") or not _has_full_arm("r"):
		_last_rejection = "Ladder climbing requires both full arm chains and both legs"
		return false
	if not _active_action.is_empty() or _hit_timer > 0.0 or not is_on_floor():
		_last_rejection = "Ladder entry requires a grounded zombie with no action in progress"
		return false
	if not ladder.get("base") is Vector3 or not ladder.get("facing") is Vector3 or not ladder.get("exit") is Vector3:
		_last_rejection = "Ladder requires base, facing and exit world vectors"
		return false
	var base: Vector3 = ladder.base
	var facing: Vector3 = ladder.facing
	var endpoint: Vector3 = ladder.exit
	var height := float(ladder.get("height", 0.0))
	if not base.is_finite() or not facing.is_finite() or not endpoint.is_finite() or not is_finite(height) or height < 0.2 or height > 6.0:
		_last_rejection = "Ladder geometry is invalid"
		return false
	facing.y = 0.0
	if facing.length_squared() < 0.5:
		_last_rejection = "Ladder facing must define a horizontal direction"
		return false
	facing = facing.normalized()
	var offset := float(behavior_contract.get("ladder", {}).get("plane_forward_m", 0.4))
	var entry := base - facing * offset
	entry.y = global_position.y
	var horizontal := entry - global_position
	horizontal.y = 0.0
	if horizontal.length() > 0.65 or absf(global_position.y - base.y) > 0.22:
		_last_rejection = "Move to the ladder before requesting a climb"
		return false
	if absf(endpoint.y - (entry.y + height)) > 0.12 or not _supported_endpoint(endpoint):
		_last_rejection = "Ladder exit needs a real platform at the climb height"
		return false
	_ladder = {"base": base, "facing": facing, "entry": entry, "height": height, "exit": endpoint, "top_y": entry.y + height}
	_ladder_time = 0.0
	_ladder_blocked_time = 0.0
	_active_action = "climb"
	_action_time = 0.0
	_manual_clip = ""
	_traversal_state = "ladder_align"
	_saved_floor_snap = floor_snap_length
	floor_snap_length = 0.0
	state = "climb"
	_set_movement_mode("climbing")
	_last_rejection = ""
	_play_animation("Zombie_Idle")
	return true


func _supported_endpoint(point: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.12, point - Vector3.UP * 0.18, WORLD_LAYER)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and (hit.get("normal", Vector3.ZERO) as Vector3).dot(Vector3.UP) >= 0.7


func _tick_ladder(delta: float) -> void:
	if not _has_standing_legs() or not _has_full_arm("l") or not _has_full_arm("r"):
		_last_rejection = "Lost a supporting limb while climbing"
		cancel_traversal()
		if not _has_standing_legs():
			_start_crawl()
		return
	_action_time += delta
	_ladder_time += delta
	var facing: Vector3 = _ladder.facing
	rotation.y = lerp_angle(rotation.y, atan2(facing.x, facing.z), minf(delta * 8.0, 1.0))
	if _traversal_state == "ladder_align":
		_gravity_step(delta)
		var direction: Vector3 = _ladder.entry - global_position
		direction.y = 0.0
		var movement := direction.limit_length(1.4 * delta) / delta
		velocity.x = movement.x
		velocity.z = movement.z
		move_and_slide()
		if direction.length() < 0.025 and _ladder_time > 0.20:
			_traversal_state = "ladder_climb"
			_ladder_time = 0.0
			motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
			_play_animation("Zombie_Climb_Ladder", true)
			animation_player.advance(0.0)
		elif _ladder_time > 1.0:
			_last_rejection = "Ladder entry is obstructed"
			cancel_traversal()
		return
	if _traversal_state == "ladder_climb":
		var speed := float(behavior_contract.get("ladder", {}).get("authored_speed_mps", 0.3))
		var remaining := float(_ladder.top_y) - global_position.y
		velocity = Vector3.UP * minf(speed, maxf(remaining, 0.0) / delta)
		var before := global_position
		move_and_slide()
		_ladder_blocked_time = _ladder_blocked_time + delta if global_position.y - before.y < speed * delta * 0.3 and remaining > 0.008 else 0.0
		if _ladder_blocked_time > 0.25:
			_last_rejection = "A solid object blocked the climb"
			cancel_traversal()
		elif remaining <= 0.004:
			_traversal_state = "ladder_exit"
			_ladder_time = 0.0
			_play_animation(_standing_walk_clip())
		return
	if _traversal_state == "ladder_exit":
		var direction: Vector3 = _ladder.exit - global_position
		direction.y = 0.0
		var movement := direction.limit_length(0.70 * delta) / delta
		velocity = Vector3(movement.x, 0.0, movement.z)
		if direction.length_squared() > 0.0004:
			rotation.y = lerp_angle(rotation.y, atan2(direction.x, direction.z), minf(delta * 5.0, 1.0))
		var authored_speed:=_standing_walk_reference_speed()
		animation_player.speed_scale = 0.70 / authored_speed if authored_speed > 0.0001 else 1.0
		move_and_slide()
		if direction.length() < 0.025 and _supported_endpoint(global_position):
			motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
			floor_snap_length = _saved_floor_snap
			_traversal_state = "none"
			_ladder.clear()
			_set_movement_mode("standing")
			_finish_action()
		elif _ladder_time > 2.5:
			_last_rejection = "The exit platform cannot be reached"
			cancel_traversal()


func cancel_traversal() -> void:
	if _traversal_state == "none":
		return
	_traversal_state = "none"
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	floor_snap_length = _saved_floor_snap
	model.position = _model_origin
	_ladder.clear()
	_active_action = ""
	_action_time = 0.0
	_set_movement_mode("crawling" if _crawling else "standing")


func set_behavior(enabled: bool) -> void:
	if not alive:return
	# The host refreshes availability every tick. Reapplying the same mode must
	# preserve an attack's contact marker and any traversal already in progress.
	if enabled == behavior_enabled:
		return
	if _r4_enabled:
		_cancel_attack()
		cancel_traversal()
	if enabled != behavior_enabled:
		_attack_timer = 0.0
		_attack_sent = false
		if enabled and animation_player != null and not _crawl_transition:
			# A same-name play call can resume a manual or paused attack. Start
			# AI playback from zero so its strike timer and animation agree.
			animation_player.stop(true)
			_animation_cursor_valid = false
	behavior_enabled = enabled
	_manual_clip = ""
	if alive and not enabled and not _crawl_transition:
		state = "crawl_idle" if _crawling else "idle"
		_play_animation("Zombie_Crawl_Idle" if _crawling else "Zombie_Idle")

func set_behavior_target(destination: Node3D) -> void:
	if target==destination:return
	_cancel_attack();cancel_traversal()
	target=destination


func play_clip(clip_name: String) -> void:
	if not alive:
		return
	if _r4_enabled:
		_cancel_attack()
		cancel_traversal()
		if _crawl_transition:
			if clip_name == "Zombie_To_Crawl":
				behavior_enabled = false
				return
			# Choosing a different preview explicitly ends the drop. The missing
			# legs still require a prone body and a compatible preview animation.
			_crawl_transition = false
			_crawling = true
			_set_crawl_capsule(1.0)
			_set_movement_mode("crawling")
			_finish_action()
		if _crawling:
			if clip_name in ["Zombie_Idle", "Zombie_Jump", "Zombie_Climb_Ladder", "Zombie_To_Crawl"]:
				clip_name = "Zombie_Crawl_Idle"
			elif clip_name in ["Zombie_Walk", "Zombie_Shamble", "Zombie_Walk_Drag_Right"]:
				clip_name = "Zombie_Crawl"
			elif clip_name.begins_with("Zombie_Attack"):
				clip_name = "Zombie_Crawl_Bite"
			elif clip_name == "Zombie_Hit":
				clip_name = "Zombie_Crawl_Hit"
	behavior_enabled = false
	_hit_timer = 0.0
	_attack_timer = 0.0
	_attack_sent = false
	_manual_clip = "Zombie_Walk" if clip_name == "Zombie_Shamble" else clip_name
	state = "preview"
	_play_animation(_manual_clip, true)


func get_walk_multiplier() -> float:
	var multiplier := 1.0
	for part: String in ["thigh_l", "thigh_r", "shin_l", "shin_r", "foot_l", "foot_r"]:
		if missing.get(part, false):
			return 0.0
		var ratio := float(limb_health.get(part, 0.0)) / float(PARTS[part].health)
		multiplier *= lerpf(0.55, 1.0, clampf(ratio, 0.0, 1.0))
	return multiplier

func _standing_walk_clip() -> String:
	return "Zombie_Walk_Drag_Right" if dragging_walk and _r4_enabled else "Zombie_Walk"

func _standing_walk_reference_speed() -> float:
	return DRAG_WALK_REFERENCE_SPEED if dragging_walk and _r4_enabled else walk_reference_speed


func get_attack_multiplier() -> float:
	var value := 0.0
	for side: String in ["l", "r"]:
		if not missing.get("upper_arm_" + side, false):
			value += 0.5 if not missing.get("hand_" + side, false) else 0.2
	return value


func _physics_process(delta: float) -> void:
	if anatomy!=null:anatomy.advance_ragdolls(delta)
	if not initialized or not alive:
		return
	if _r4_enabled:
		_physics_r4(delta)
		return
	var was_hit := _hit_timer > 0.0
	_hit_timer = maxf(_hit_timer - delta, 0.0)
	if was_hit and _hit_timer <= 0.0 and _manual_clip != "":
		_play_animation(_manual_clip)
	velocity.x = move_toward(velocity.x, 0.0, delta * 3.0)
	velocity.z = move_toward(velocity.z, 0.0, delta * 3.0)
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = -0.1
	if _hit_timer > 0.0:
		state = "stagger"
		_attack_timer = 0.0
		_attack_sent = false
	elif behavior_enabled and is_instance_valid(target):
		var direction := target.global_position - global_position
		direction.y = 0.0
		var distance := direction.length()
		if distance > 0.02:
			rotation.y = lerp_angle(rotation.y, atan2(direction.x, direction.z), minf(turn_speed * delta, 1.0))
		if distance > attack_distance:
			state = "shamble"
			_attack_timer = 0.0
			_attack_sent = false
			var speed := walk_speed * get_walk_multiplier()
			var movement := direction.normalized() * speed
			velocity.x = movement.x
			velocity.z = movement.z
			if _hit_timer <= 0.0:
				_play_animation("Zombie_Walk")
			if animation_player != null:
				# R3/R4 provide an authored stride speed. Original/R2 retain
				# their preserved, unscaled animation cadence.
				animation_player.speed_scale = speed / walk_reference_speed if walk_reference_speed > 0.0001 else 1.0
		else:
			state = "attack"
			if _hit_timer <= 0.0:
				_play_animation("Zombie_Attack")
			_attack_timer += delta
			var attack_length := 1.6
			if animation_player != null and animation_player.current_animation_length > 0.1:
				attack_length = animation_player.current_animation_length
			if _attack_timer >= attack_strike_seconds and not _attack_sent:
				_attack_sent = true
				var damage := attack_damage * get_attack_multiplier()
				if damage > 0.0 and distance <= attack_distance + 0.2:
					attack_landed.emit(damage)
					if target.has_method("receive_zombie_attack"):
						target.call("receive_zombie_attack", damage)
			if _attack_timer >= attack_length:
				_attack_timer = 0.0
				_attack_sent = false
				_play_animation("Zombie_Attack", true)
	elif _manual_clip == "" and _hit_timer <= 0.0:
		state = "idle"
		_play_animation("Zombie_Idle")
	move_and_slide()


func _play_animation(clip_name: String, restart: bool = false) -> void:
	if animation_player == null:
		return
	var key := clip_name
	if not animation_player.has_animation(key):
		for candidate in animation_player.get_animation_list():
			if String(candidate).get_file() == clip_name:
				key = String(candidate)
				break
	if not animation_player.has_animation(key):
		return
	if clip_name == "Zombie_Idle" or clip_name == "Zombie_Walk":
		animation_player.get_animation(key).loop_mode = Animation.LOOP_LINEAR
	if key == _current_clip and not restart and animation_player.is_playing():
		return
	if restart:
		# A same-name play resumes its old cursor, even when paused. Reset
		# playback while retaining the evaluated pose until play is processed.
		animation_player.stop(true)
	animation_player.speed_scale = 1.0
	animation_player.play(key, 0.16 if not restart else 0.0)
	_animation_cursor_valid = true
	_current_clip = key


func receive_hit(part: String, damage: float, world_point: Vector3 = Vector3.ZERO, impulse: Vector3 = Vector3.ZERO, force_sever: bool = false, impact: String = "melee") -> void:
	if not initialized or not PARTS.has(part) or missing.get(part, false):
		return
	if not is_finite(damage) or not impulse.is_finite() or not world_point.is_finite():
		return
	var result:Dictionary=anatomy.hit(part,damage,force_sever,impact)
	if not result.ok:return
	health=float(result.health);limb_health=anatomy.snapshot().limbs
	damaged.emit(part, health)
	if result.sever:
		sever_limb(part, impulse)
		if alive and result.dead:die(impulse)
		return
	if not alive:
		_apply_body_impulse(part, impulse, world_point)
		return
	if result.dead:
		die(impulse)
	else:
		if _r4_enabled:
			_cancel_attack()
			cancel_traversal()
			if _crawl_transition:
				return
			_hit_timer = _action_duration("Zombie_Crawl_Hit", 0.5) if _crawling else 0.45
			_play_animation("Zombie_Crawl_Hit" if _crawling else "Zombie_Hit", true)
		else:
			_hit_timer = 0.45
			_play_animation("Zombie_Hit", true)


func apply_hit(part: String, damage: float, world_point: Vector3 = Vector3.ZERO, impulse: Vector3 = Vector3.ZERO, force_sever: bool = false, impact: String = "melee") -> void:
	receive_hit(part, damage, world_point, impulse, force_sever, impact)


func restore_population_vitals(bytes: PackedByteArray) -> bool:
	var validator = ClassDB.instantiate("NativeZombieAnatomy")
	if not validator.configure(PARTS) or not validator.restore_vitals(bytes) or not validator.snapshot().alive:return false
	var saved: Dictionary = validator.snapshot()
	for part: String in PARTS:
		if saved.missing[part] and not missing.get(part, false):sever_limb(part)
	for detached in detached_parts:
		if is_instance_valid(detached):detached.queue_free()
	detached_parts.clear()
	if not anatomy.restore_vitals(bytes):return false
	health = saved.health; limb_health = saved.limbs
	if not _has_standing_legs():
		_crawl_transition = false; _crawling = true; _active_action = ""; _action_time = 0.0
		_set_crawl_capsule(1.0); _set_movement_mode("crawling")
		state = "crawl_idle"; _play_animation("Zombie_Crawl_Idle", true)
		animation_player.advance(0.0)
	return true

func sever_limb(part: String, impulse: Vector3 = Vector3.ZERO) -> void:
	if not initialized or not PARTS.has(part) or missing.get(part, false):
		return
	if part == "torso":
		die(impulse)
		return
	if not impulse.is_finite():
		return
	var chain: Array[String] = []
	_collect_chain(part, chain)
	anatomy.detach(part);health=float(anatomy.snapshot().health)
	skeleton.force_update_all_bone_transforms()
	_spawn_detached(part, chain, impulse)
	for removed: String in chain:
		missing[removed] = true
		limb_health[removed] = 0.0
		if part_meshes.has(removed):
			part_meshes[removed].hide()
		if hit_areas.has(removed):
			hit_areas[removed].collision_layer = 0
		var bone_name := String(PARTS[removed].bone)
		if physical_bones.has(bone_name):
			var physical: PhysicalBone3D = physical_bones[bone_name]
			physical.collision_layer = 0
			physical.collision_mask = 0
			_remove_body_exceptions(physical)
			physical.joint_type = PhysicalBone3D.JOINT_TYPE_NONE
			simulator.remove_child(physical)
			physical.queue_free()
			physical_bones.erase(bone_name)
	for cut: String in caps:
		if chain.has(cut) or chain.has(String(PARTS[cut].parent)):
			for cap in caps[cut].values():
				cap.hide()
	if caps.has(part) and caps[part].has("body"):
		caps[part].body.show()
	limb_severed.emit(part)
	print("Zombie severed ", part, ": ", chain)
	if alive:
		if part == "head":
			die(impulse * 0.5)
		elif part.begins_with("thigh") or part.begins_with("shin") or part.begins_with("foot"):
			if _r4_enabled:
				_start_crawl()
			else:
				die(impulse * 0.5)
		elif _r4_enabled:
			if R4_ATTACKS.has(_active_action) and not _attack_is_eligible(_active_action):
				_cancel_attack()
			if _traversal_state.begins_with("ladder") and (not _has_full_arm("l") or not _has_full_arm("r")):
				cancel_traversal()


func _collect_chain(part: String, chain: Array[String]) -> void:
	if missing.get(part, false):
		return
	chain.append(part)
	for child: String in PARTS:
		if PARTS[child].parent == part:
			_collect_chain(child, chain)


func die(impulse: Vector3 = Vector3.ZERO) -> void:
	if not initialized or not alive:
		return
	alive = false
	anatomy.kill();health=0.0;limb_health=anatomy.snapshot().limbs
	state = "ragdoll"
	behavior_enabled = false
	_active_action = ""
	_crawl_transition = false
	_traversal_state = "none"
	_set_movement_mode("ragdoll")
	_death_velocity = velocity
	velocity = Vector3.ZERO
	_death_pose.clear()
	skeleton.force_update_all_bone_transforms()
	for index in skeleton.get_bone_count():
		_death_pose.append(skeleton.get_bone_global_pose(index))
	if animation_player != null:
		animation_player.stop(true)
		_animation_cursor_valid = false
		animation_player.active = false
	capsule.set_deferred("disabled", true)
	collision_layer = 0
	collision_mask = 0
	call_deferred("_begin_ragdoll", impulse)
	died.emit()
	print("Zombie ragdoll started with ", physical_bones.size(), " physical bones.")


func ragdoll(impulse: Vector3 = Vector3.ZERO) -> void:
	die(impulse)


func _begin_ragdoll(impulse: Vector3) -> void:
	if not is_inside_tree() or simulator == null:
		return
	var saved_constraints: Dictionary = {}
	for bone_name: String in physical_bones:
		var physical: PhysicalBone3D = physical_bones[bone_name]
		if physical.joint_type == PhysicalBone3D.JOINT_TYPE_NONE:
			continue
		var parameters := {"type": physical.joint_type}
		for property in physical.get_property_list():
			if String(property.name).begins_with("joint_constraints/"):
				parameters[property.name] = physical.get(property.name)
				if String(property.name).ends_with("spring_enabled") or String(property.name).ends_with("motor_enabled"):parameters[property.name]=false
		saved_constraints[bone_name] = parameters
		physical.joint_type = PhysicalBone3D.JOINT_TYPE_NONE
	_refresh_pose_collision_shapes()
	simulator.active = true
	simulator.physical_bones_start_simulation()
	# Starting the simulator resets native bodies to its cached skeleton pose.
	# Transfer the sampled death pose afterwards, to both the scene nodes and
	# physics server, before creating any joint against those body transforms.
	for bone_name: String in physical_bones:
		var physical: PhysicalBone3D = physical_bones[bone_name]
		var index := skeleton.find_bone(bone_name)
		var body_pose := skeleton.global_transform * _death_pose[index] * physical.body_offset
		physical.global_transform = body_pose
		PhysicsServer3D.body_set_state(physical.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, body_pose)
		physical.collision_layer = RAGDOLL_LAYER
		physical.collision_mask = BODY_COLLISION_MASK
	# Rebuild constraints against the animated pose at death. Bind-pose joint
	# frames would otherwise try to pull the fresh ragdoll back into a T pose.
	for bone_name: String in saved_constraints:
		var physical: PhysicalBone3D = physical_bones[bone_name]
		var parameters: Dictionary = saved_constraints[bone_name]
		physical.joint_type = int(parameters.type)
		for property: String in parameters:
			if property != "type":
				physical.set(property, parameters[property])
	for physical: PhysicalBone3D in physical_bones.values():
		physical.linear_velocity = _death_velocity
	_apply_body_impulse("torso", impulse)
	anatomy.track_ragdoll(physical_bones.values())


func _apply_body_impulse(part: String, impulse: Vector3, point: Vector3 = Vector3.ZERO) -> void:
	var bone_name := String(PARTS[part].bone)
	if not physical_bones.has(bone_name):
		bone_name = "Hips"
	if physical_bones.has(bone_name):
		var physical: PhysicalBone3D = physical_bones[bone_name]
		if point == Vector3.ZERO:
			physical.apply_central_impulse(impulse)
		else:
			physical.apply_impulse(impulse, point - physical.global_position)


func _current_bone_pose(index: int) -> Transform3D:
	if alive or _death_pose.is_empty():
		return skeleton.get_bone_global_pose(index)
	if not simulator.is_simulating_physics():
		return _death_pose[index]
	var ancestor := index
	while ancestor >= 0:
		var bone_name := skeleton.get_bone_name(ancestor)
		if physical_bones.has(bone_name):
			var physical: PhysicalBone3D = physical_bones[bone_name]
			var pose := skeleton.global_transform.affine_inverse() * physical.global_transform * physical.body_offset.affine_inverse()
			return pose * _death_pose[ancestor].affine_inverse() * _death_pose[index]
		ancestor = skeleton.get_bone_parent(ancestor)
	return _death_pose[index]


func _new_detached_body(part: String) -> RigidBody3D:
	var body:RigidBody3D=ClassDB.instantiate("NativeZombieRigidPart")
	body.disable_mode=CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	body.name = "Detached_" + part
	body.set_meta("limb_key", part)
	body.collision_layer = RAGDOLL_LAYER
	body.collision_mask = DETACHED_COLLISION_MASK
	body.linear_damp = 0.16
	body.angular_damp = 1.5 if part.begins_with("hand") or part.begins_with("foot") else 0.65
	body.continuous_cd = true
	var material := PhysicsMaterial.new()
	material.friction = SOLE_FRICTION if part.begins_with("foot") else 0.85
	material.bounce = 0.05
	body.physics_material_override = material
	body.mass = maxf(float(PARTS[part].mass), 0.1)
	if part.begins_with("hand"):
		body.mass = 0.75
	elif part.begins_with("foot"):
		body.mass = 1.25
	return body


func _new_detached_joint(part: String) -> Joint3D:
	if part.begins_with("hand") or part.begins_with("foot") or part.begins_with("forearm"):
		# Severed upper-arm chains retain the same elbow translation lock.
		var joint := Generic6DOFJoint3D.new()
		var ankle := part.begins_with("foot")
		var elbow := part.begins_with("forearm")
		for axis: String in ["x", "y", "z"]:
			var linear := "linear_limit_" + axis + "/"
			joint.set(linear + "enabled", true)
			joint.set(linear + "lower_distance", 0.0)
			joint.set(linear + "upper_distance", 0.0)
			joint.set(linear + "softness", 0.95)
			joint.set(linear + "restitution", 0.5)
			joint.set(linear + "damping", 1.0)
			var angular := "angular_limit_" + axis + "/"
			var degrees := (12.0 if axis == "x" else 25.0) if ankle else (18.0 if axis == "x" else 30.0)
			if elbow:
				degrees = 8.0 if axis == "x" else 55.0
			joint.set(angular + "enabled", true)
			joint.set(angular + "lower_angle", -deg_to_rad(degrees))
			joint.set(angular + "upper_angle", deg_to_rad(degrees))
			joint.set(angular + "softness", 0.85)
			joint.set(angular + "restitution", 0.0)
			joint.set(angular + "damping", 1.0)
			joint.set(angular + "erp", 0.15)
		for property:Dictionary in joint.get_property_list():
			var key:=String(property.name)
			if (key.contains("motor") or key.contains("spring")) and key.ends_with("enabled"):joint.set(key,false)
		return joint
	var joint := ConeTwistJoint3D.new()
	joint.swing_span = deg_to_rad(55.0)
	joint.twist_span = deg_to_rad(8.0)
	joint.bias = 0.3
	joint.softness = 0.85
	joint.relaxation = 1.0
	return joint


func _spawn_detached(part: String, chain: Array[String], impulse: Vector3) -> void:
	var root_body := _new_detached_body(part)
	get_parent().add_child(root_body)
	var bodies: Dictionary = {}
	var total_mass := 0.0
	for key: String in chain:
		var body := root_body if key == part else _new_detached_body(key)
		if key != part:
			# Child bodies belong to this severed group for cleanup, but each uses
			# its own world transform so parent motion is not applied a second time.
			body.top_level = true
			root_body.add_child(body)
		var bone_index := skeleton.find_bone(String(PARTS[key].bone))
		var info := _pose_shape_spec(key)
		var world := skeleton.global_transform * _current_bone_pose(bone_index) * Transform3D(info.offset)
		body.global_position = world.origin
		var to_local := body.global_transform.affine_inverse()
		if part_meshes.has(key):
			_attach_baked_mesh(body, part_meshes[key], to_local)
		if _r4_enabled and key.begins_with("hand"):
			_install_hand_compound(body, key, to_local)
		else:
			var collision := CollisionShape3D.new()
			collision.shape = info.shape
			collision.transform = to_local * world
			body.add_child(collision)
		body.linear_velocity = velocity
		body.angular_velocity = Vector3(0.4, 0.25, -0.3)
		if not alive and physical_bones.has(String(PARTS[key].bone)):
			var original: PhysicalBone3D = physical_bones[String(PARTS[key].bone)]
			body.linear_velocity = original.linear_velocity
			body.angular_velocity = original.angular_velocity
		bodies[key] = body
		total_mass += body.mass
	for key: String in chain:
		var parent_part := String(PARTS[key].parent)
		if not bodies.has(parent_part):
			continue
		var parent_body: RigidBody3D = bodies[parent_part]
		var child_body: RigidBody3D = bodies[key]
		var joint := _new_detached_joint(key)
		joint.name = "Joint_" + key
		joint.top_level = true
		root_body.add_child(joint)
		var bone_index := skeleton.find_bone(String(PARTS[key].bone))
		var bone_world := skeleton.global_transform * _current_bone_pose(bone_index)
		joint.global_transform = bone_world * Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3.ZERO)
		joint.node_a = joint.get_path_to(parent_body)
		joint.node_b = joint.get_path_to(child_body)
		joint.exclude_nodes_from_collision = true
		_exempt_joint_neighbors(parent_body, child_body)
		joint.set_meta("body_a", parent_body)
		joint.set_meta("body_b", child_body)
		joint.set_meta("anchor_a", parent_body.to_local(joint.global_position))
		joint.set_meta("anchor_b", child_body.to_local(joint.global_position))
	# Include the cut surface at this new root. Rigid sections can rotate apart
	# at their internal joints, so cap both sides of those joints as well.
	if caps.has(part) and caps[part].has("detached"):
		_attach_baked_mesh(root_body, caps[part].detached, root_body.global_transform.affine_inverse())
	for cut: String in caps:
		var cap_owner := String(PARTS[cut].parent)
		if not bodies.has(cap_owner):
			continue
		var body: RigidBody3D = bodies[cap_owner]
		if bodies.has(cut):
			if caps[cut].has("body"):
				_attach_baked_mesh(body, caps[cut].body, body.global_transform.affine_inverse())
			if caps[cut].has("detached"):
				var child_body: RigidBody3D = bodies[cut]
				_attach_baked_mesh(child_body, caps[cut].detached, child_body.global_transform.affine_inverse())
		elif caps[cut].has("body") and caps[cut].body.visible:
			# Preserve older distal stumps when their parent is severed later.
			_attach_baked_mesh(body, caps[cut].body, body.global_transform.affine_inverse())
	for body: RigidBody3D in bodies.values():
		body.apply_central_impulse(impulse * (body.mass / maxf(total_mass, 0.1)))
	root_body.set_meta("segment_bodies", bodies.values())
	root_body.set_meta("total_mass", total_mass)
	detached_parts.append(root_body)
	anatomy.track_ragdoll(bodies.values())


func _attach_baked_mesh(body: RigidBody3D, source: MeshInstance3D, to_local: Transform3D) -> void:
	var instance := MeshInstance3D.new()
	instance.name = source.name
	instance.mesh = _bake_cpu(source, to_local)
	instance.skeleton = NodePath("")
	instance.skin = null
	body.add_child(instance)


func _bake_cpu(source: MeshInstance3D, to_local: Transform3D) -> ArrayMesh:
	# Standard CPU linear-blend skinning avoids a GPU readback and works headless.
	# Meshes in the supplied GLB are identity children of the imported skeleton.
	var result := ArrayMesh.new()
	var binds: Array[Transform3D] = []
	var skin := source.skin
	if skin != null:
		for bind in skin.get_bind_count():
			var name := skin.get_bind_name(bind)
			var index := skeleton.find_bone(name) if name != &"" else skin.get_bind_bone(bind)
			var transform := _current_bone_pose(index) * skin.get_bind_pose(bind) if index >= 0 else Transform3D.IDENTITY
			binds.append(to_local * skeleton.global_transform * transform)
	var unskinned := to_local * source.global_transform
	for surface in source.mesh.get_surface_count():
		var arrays := source.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT] if arrays[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES] if arrays[Mesh.ARRAY_BONES] != null else PackedInt32Array()
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS] if arrays[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
		var count := vertices.size()
		# Head BiteOpen is a native glTF morph, evaluated before skinning. Keep
		# that mouth pose when a head is severed or sampled for a real bite.
		if source.mesh is ArrayMesh and source.mesh.get_blend_shape_count() > 0:
			var morphs: Array = (source.mesh as ArrayMesh).surface_get_blend_shape_arrays(surface)
			var base_vertices := vertices.duplicate()
			var base_normals := normals.duplicate()
			var relative := (source.mesh as ArrayMesh).blend_shape_mode == Mesh.BLEND_SHAPE_MODE_RELATIVE
			for morph in mini(morphs.size(), source.mesh.get_blend_shape_count()):
				var amount := source.get_blend_shape_value(morph)
				if not is_finite(amount) or absf(amount) < 0.000001:
					continue
				var shape_arrays: Array = morphs[morph]
				if shape_arrays.size() < Mesh.ARRAY_MAX:
					continue
				var morph_vertices: PackedVector3Array = shape_arrays[Mesh.ARRAY_VERTEX] if shape_arrays[Mesh.ARRAY_VERTEX] != null else PackedVector3Array()
				var morph_normals: PackedVector3Array = shape_arrays[Mesh.ARRAY_NORMAL] if shape_arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
				for vertex in count:
					if morph_vertices.size() == count:
						vertices[vertex] += (morph_vertices[vertex] if relative else morph_vertices[vertex] - base_vertices[vertex]) * amount
					if morph_normals.size() == count and normals.size() == count:
						normals[vertex] += (morph_normals[vertex] if relative else morph_normals[vertex] - base_normals[vertex]) * amount
		var influences := bones.size() / count if count > 0 else 0
		for vertex in count:
			var position := Vector3.ZERO
			var normal := Vector3.ZERO
			var tangent := Vector3.ZERO
			var total := 0.0
			var initial_normal := normals[vertex] if normals.size() == count else Vector3.UP
			var initial_tangent := Vector3(tangents[vertex * 4], tangents[vertex * 4 + 1], tangents[vertex * 4 + 2]) if tangents.size() == count * 4 else Vector3.RIGHT
			for influence in influences:
				var weight := weights[vertex * influences + influence]
				var bind := bones[vertex * influences + influence]
				if weight <= 0.0 or bind < 0 or bind >= binds.size():
					continue
				var transform: Transform3D = binds[bind]
				position += (transform * vertices[vertex]) * weight
				normal += (transform.basis * initial_normal) * weight
				tangent += (transform.basis * initial_tangent) * weight
				total += weight
			if total <= 0.00001:
				position = unskinned * vertices[vertex]
				normal = unskinned.basis * initial_normal
				tangent = unskinned.basis * initial_tangent
			else:
				position /= total
			vertices[vertex] = position
			if normals.size() == count:
				normals[vertex] = normal.normalized()
			if tangents.size() == count * 4:
				tangent = tangent.normalized()
				tangents[vertex * 4] = tangent.x
				tangents[vertex * 4 + 1] = tangent.y
				tangents[vertex * 4 + 2] = tangent.z
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals if not normals.is_empty() else null
		arrays[Mesh.ARRAY_TANGENT] = tangents if not tangents.is_empty() else null
		arrays[Mesh.ARRAY_BONES] = null
		arrays[Mesh.ARRAY_WEIGHTS] = null
		# Imported extra UV sets can occupy FLOAT custom channels. Their format
		# bits must survive the copy; omitting them makes Godot expect byte data.
		var custom_formats := 0
		if source.mesh is ArrayMesh:
			custom_formats = (source.mesh as ArrayMesh).surface_get_format(surface) & (4095 << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, custom_formats)
		result.surface_set_material(result.get_surface_count() - 1, source.get_active_material(surface))
	return result


func _exit_tree() -> void:
	for body in detached_parts:
		if is_instance_valid(body) and not body.is_queued_for_deletion():
			body.queue_free()
