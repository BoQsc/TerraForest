# SPDX-License-Identifier: 0BSD
extends RefCounted
const KEY: String="architecture/metal_guardrail/v1"
static func recipe() -> PackedInt64Array:return PackedInt64Array([104,4])
static func register(world: Node3D) -> Dictionary:
	var mesh: Mesh=load("res://addons/structures/prefabs/guardrail_model.tres")
	var collection: Node3D=world.register_model(KEY,mesh)
	if collection==null:return {}
	# One thin continuous proxy prevents snagging on bars; no rigid-body simulation.
	if not collection.configure_collision(AABB(Vector3(-0.06,0,-2),Vector3(0.12,1.1,4)),64,256,8):return {}
	return {"title":"Metal guardrail","mesh":mesh,"collection":collection,"scale":Vector3.ONE,"costs":recipe(),"cost_label":"4 metal"}
