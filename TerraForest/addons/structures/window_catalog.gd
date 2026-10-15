# SPDX-License-Identifier: 0BSD
extends RefCounted
const KEY: String="architecture/wooden_window/v1"
static func recipe() -> PackedInt64Array:
	# Provisional whole-window recipe until glass crafting is introduced.
	return PackedInt64Array([102,4])
static func register(world: Node3D) -> Dictionary:
	var mesh: Mesh=load("res://addons/structures/prefabs/window_model.tres")
	var collection: Node3D=world.register_model(KEY,mesh)
	if collection==null:return {}
	if not collection.configure_collision(AABB(Vector3(-1,0,-0.1),Vector3(2,2,0.2)),64,256,8):return {}
	return {"title":"Wood framed window","mesh":mesh,"collection":collection,"scale":Vector3.ONE,"costs":recipe(),"cost_label":"4 wood"}
