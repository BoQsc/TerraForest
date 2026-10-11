# SPDX-License-Identifier: 0BSD
extends RefCounted
const KEY: String="storage/wooden_chest/v1"
static func register(world: Node3D) -> Dictionary:
	var mesh: Mesh=load("res://addons/structures/prefabs/storage_chest_model.tres")
	var collection: Node3D=world.register_model(KEY,mesh)
	if collection==null: return {}
	if not collection.configure_collision(AABB(Vector3(-0.61,0,-0.38),Vector3(1.22,0.75,0.8)),64,256,8): return {}
	return {"title":"Wooden storage chest (E open)","mesh":mesh,"collection":collection,"scale":Vector3.ONE,"costs":PackedInt64Array([102,8]),"cost_label":"8 wood"}
