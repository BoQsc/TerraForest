# SPDX-License-Identifier: 0BSD
extends RefCounted
const KEY: String="architecture/wooden_fence/v1"
static func recipe() -> PackedInt64Array:return PackedInt64Array([102,4])
static func register(world: Node3D) -> Dictionary:
	var mesh: Mesh=load("res://addons/structures/prefabs/fence_model.tres")
	var collection: Node3D=world.register_model(KEY,mesh)
	if collection==null:return {}
	# One continuous static proxy; no rigid body or collider for each rail/post.
	if not collection.configure_collision(AABB(Vector3(-0.09,0,-1),Vector3(0.18,1.3,2)),64,256,8):return {}
	return {"title":"Wooden fence","mesh":mesh,"collection":collection,"scale":Vector3.ONE,"costs":recipe(),"cost_label":"4 wood"}
