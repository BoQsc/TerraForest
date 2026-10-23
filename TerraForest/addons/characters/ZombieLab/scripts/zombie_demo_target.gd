extends Node3D
## A visible, collidable target. Only validated controller contacts cause damage.

signal struck(damage: float)

const STANDING_BITE_RADIUS = 0.16
const STANDING_BITE_HEIGHT = 1.36
const LOW_BITE_RADIUS = 0.20
const LOW_BITE_HEIGHT = 0.26

var health = 100.0
var contacts = 0
var last_damage = 0.0
var low_mode = false
var contact_action = "bite"
var flash = 0.0
var target_material: StandardMaterial3D
var pad_root: Node3D
var low_pad_root: Node3D
var torso_pad: MeshInstance3D
var head_pad: MeshInstance3D
var low_pad: MeshInstance3D
var badge: Label3D
var body: StaticBody3D
var collider: CollisionShape3D


func _ready() -> void:
	name = "LiveDemoTarget"
	target_material = StandardMaterial3D.new()
	target_material.albedo_color = Color(0.18, 0.59, 0.59)
	target_material.roughness = 0.70
	target_material.metallic = 0.10
	pad_root = Node3D.new()
	add_child(pad_root)
	var dark = StandardMaterial3D.new()
	dark.albedo_color = Color(0.08, 0.13, 0.14)
	_add_box("TargetBase", Vector3(0, 0.035, 0), Vector3(0.40, 0.07, 0.40), dark, self)
	_add_box("TargetStem", Vector3(0, 0.75, 0), Vector3(0.065, 1.40, 0.065), dark, pad_root)
	torso_pad = _add_box("PaddedTorso", Vector3(0, 1.15, 0), Vector3(0.38, 0.58, 0.23), target_material, pad_root)
	head_pad = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = STANDING_BITE_RADIUS
	sphere.height = STANDING_BITE_RADIUS * 2.0
	sphere.radial_segments = 20
	sphere.rings = 10
	head_pad.mesh = sphere
	head_pad.material_override = target_material
	head_pad.position = Vector3(0, STANDING_BITE_HEIGHT, 0)
	pad_root.add_child(head_pad)
	for height in [1.08, 1.27]:
		_add_box("ContactMark", Vector3(0, height, -0.123), Vector3(0.20, 0.018, 0.006), dark, pad_root)
	low_pad_root = Node3D.new()
	low_pad_root.name = "RetractedLowTarget"
	add_child(low_pad_root)
	_add_box("LowTargetStem", Vector3(0, 0.20, 0), Vector3(0.065, 0.32, 0.065), dark, low_pad_root)
	low_pad = MeshInstance3D.new()
	var low_sphere = sphere.duplicate()
	low_sphere.radius = LOW_BITE_RADIUS
	low_sphere.height = LOW_BITE_RADIUS * 2.0
	low_pad.mesh = low_sphere
	low_pad.material_override = target_material
	low_pad.position = Vector3(0, LOW_BITE_HEIGHT, 0)
	low_pad_root.add_child(low_pad)
	badge = Label3D.new()
	badge.font_size = 24
	badge.pixel_size = 0.002
	badge.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	badge.outline_size = 4
	badge.modulate = Color(0.55, 0.95, 0.90)
	add_child(badge)
	body = StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	collider = CollisionShape3D.new()
	body.add_child(collider)
	set_low_mode(false)
	_update_badge()


func _add_box(label: String, at: Vector3, dimensions: Vector3, material: Material, parent: Node) -> MeshInstance3D:
	var visual = MeshInstance3D.new()
	visual.name = label
	var mesh = BoxMesh.new()
	mesh.size = dimensions
	visual.mesh = mesh
	visual.position = at
	visual.material_override = material
	parent.add_child(visual)
	return visual


func reset() -> void:
	health = 100.0
	contacts = 0
	last_damage = 0.0
	flash = 0.0
	pad_root.rotation = Vector3.ZERO
	low_pad_root.rotation = Vector3.ZERO
	set_contact_action("bite")
	set_low_mode(false)
	_update_badge()


func set_low_mode(enabled: bool) -> void:
	low_mode = enabled
	if pad_root == null:
		return
	pad_root.visible = not enabled
	low_pad_root.visible = enabled
	var shape = CapsuleShape3D.new()
	shape.radius = 0.16
	shape.height = 0.66 if enabled else 1.75
	collider.shape = shape
	collider.position.y = shape.height * 0.5
	badge.position = Vector3(0, 0.82 if enabled else 1.94, 0)
	_update_badge()


func set_contact_action(action: String) -> void:
	contact_action = action.to_lower()
	# The head-height pad retracts for hand stations, exposing the actual
	# rectangular striking surface instead of obscuring the incoming fingers.
	if is_instance_valid(head_pad):
		head_pad.visible = contact_action in ["approach", "bite"]


func set_enabled(enabled: bool) -> void:
	visible = enabled
	if is_instance_valid(body):
		body.collision_layer = 1 if enabled else 0


func get_zombie_attack_target_point(action: String) -> Vector3:
	if low_mode or action.to_lower().contains("crawl"):
		return low_pad.global_position
	if action.to_lower().contains("bite"):
		return head_pad.global_position
	return torso_pad.global_transform * Vector3(0, 0.07, 0)


func get_zombie_attack_radius() -> float:
	return 0.22


func get_zombie_attack_contact_shapes(action: String) -> Array:
	# These describe the visible padding exactly, including its current recoil.
	# The controller measures the animated lips/fingers against these surfaces.
	if low_mode or action.to_lower().contains("crawl"):
		return [{"type": "sphere", "transform": low_pad.global_transform, "radius": LOW_BITE_RADIUS}]
	if action.to_lower().contains("bite"):
		return [{"type": "sphere", "transform": head_pad.global_transform, "radius": STANDING_BITE_RADIUS}]
	return [{"type": "box", "transform": torso_pad.global_transform, "half_extents": Vector3(0.19, 0.29, 0.115)}]


func get_signed_contact_surface_distance(action: String, world_point: Vector3) -> float:
	var distance = INF
	for shape in get_zombie_attack_contact_shapes(action):
		var local_point: Vector3 = shape.transform.affine_inverse() * world_point
		if shape.type == "sphere":
			distance = minf(distance, local_point.length() - float(shape.radius))
		else:
			var edge: Vector3 = local_point.abs() - Vector3(shape.half_extents)
			var signed = edge.max(Vector3.ZERO).length() + minf(maxf(edge.x, maxf(edge.y, edge.z)), 0.0)
			distance = minf(distance, signed)
	return distance


func receive_zombie_attack(damage: float) -> void:
	health = maxf(0.0, health - damage)
	contacts += 1
	last_damage = damage
	flash = 0.35
	_update_badge()
	struck.emit(damage)


func _update_badge() -> void:
	if is_instance_valid(badge):
		badge.text = "%s  ·  %d HP" % ["LOW TARGET" if low_mode else "TARGET", roundi(health)]


func _physics_process(delta: float) -> void:
	flash = maxf(0.0, flash - delta)
	if target_material != null:
		target_material.albedo_color = Color(0.95, 0.36, 0.16) if flash > 0.0 else Color(0.18, 0.59, 0.59)
		var recoil_time = 0.35 - flash
		var is_hand_strike = contact_action in ["left", "right", "both"]
		var duration = 0.28 if is_hand_strike else 0.35
		var recoil = sin(clampf(recoil_time / duration, 0.0, 1.0) * PI) if flash > 0.0 else 0.0
		var angle = 0.09 if is_hand_strike else 0.045
		# The spring-mounted padding yields after contact, allowing follow-through.
		pad_root.rotation = Vector3(recoil * angle, 0, sin(flash * 57.0) * flash * 0.025)
		low_pad_root.rotation = Vector3(recoil * 0.045, 0, pad_root.rotation.z)
