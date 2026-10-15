# SPDX-License-Identifier: 0BSD
extends RefCounted
const KEY: String="architecture/wooden_door/v1"
static func recipe() -> PackedInt64Array:return PackedInt64Array([102,6])
static func register(world: Node3D) -> Dictionary:
	var mesh: Mesh=load("res://addons/structures/prefabs/door_model.tres")
	var collection: Node3D=world.register_model(KEY,mesh)
	if collection==null:return {}
	if not collection.configure_collision(AABB(Vector3(0,0,-0.07),Vector3(1,2.2,0.14)),64,256,8):return {}
	return {"title":"Wooden door (E open / close)","mesh":mesh,"collection":collection,"scale":Vector3.ONE,"costs":recipe(),"cost_label":"6 wood"}
