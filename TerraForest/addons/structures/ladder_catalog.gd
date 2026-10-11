# SPDX-License-Identifier: 0BSD
extends RefCounted
const KEY: String="architecture/wooden_ladder/v1"
static func register(world: Node3D) -> Dictionary:
	var mesh: Mesh=load("res://addons/structures/prefabs/ladder_model.tres")
	var collection: Node3D=world.register_model(KEY,mesh)
	if collection==null: return {}
	# A single thin solid proxy prevents the capsule catching between rungs.
	if not collection.configure_collision(AABB(Vector3(-0.45,0,-0.06),Vector3(0.9,3.6,0.12)),64,128,8): return {}
	return {"title":"Wooden ladder (W/S climb, Space jump off)","mesh":mesh,"collection":collection,"scale":Vector3.ONE,"costs":recipe(),"cost_label":"6 wood"}

static func recipe() -> PackedInt64Array:
	return PackedInt64Array([102,6])
