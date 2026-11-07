# SPDX-License-Identifier: 0BSD
extends Node3D
## Capped pool of bullet-hole quads. One shared mesh and material keep a long
## firefight cheap; oldest holes are recycled, and every hole expires on its own.

const LIMIT := 96
const LIFETIME := 24.0
const SIZE := 0.055
var quad: QuadMesh
var material: StandardMaterial3D
var holes: Array[Dictionary] = []
var cursor := 0

func _ready() -> void:
	name = "BulletHoles"
	quad = QuadMesh.new(); quad.size = Vector2(SIZE, SIZE)
	material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(.04, .035, .03, .92)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	set_process(true)

func add(point: Vector3, normal: Vector3) -> bool:
	if not point.is_finite() or not normal.is_finite() or normal.length_squared() < .01: return false
	var entry: Dictionary
	if holes.size() < LIMIT:
		var fresh := MeshInstance3D.new(); fresh.mesh = quad; fresh.material_override = material
		fresh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(fresh); entry = {"node": fresh, "age": 0.0}; holes.append(entry)
	else:
		entry = holes[cursor]; cursor = (cursor + 1) % LIMIT; entry.age = 0.0
	var node: MeshInstance3D = entry.node
	var n := normal.normalized()
	node.global_position = point + n * .012
	# look_at cannot use an up vector parallel to the target on flat ground.
	node.look_at(node.global_position + n, Vector3.FORWARD if absf(n.dot(Vector3.UP)) > .99 else Vector3.UP)
	node.show()
	return true

func clear() -> void:
	for entry in holes: entry.node.queue_free()
	holes.clear(); cursor = 0

func _process(delta: float) -> void:
	for entry in holes:
		entry.age += delta
		if entry.age >= LIFETIME and entry.node.visible: entry.node.hide()
