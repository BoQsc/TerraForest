# SPDX-License-Identifier: 0BSD
extends RefCounted
const KEY: String="architecture/metal_guardrail/v1"
const STAIR_KEY: String="architecture/metal_stairrail/v1"
static func recipe() -> PackedInt64Array:return PackedInt64Array([104,4])
static func register(world: Node3D) -> Dictionary:
	var mesh: Mesh=load("res://addons/structures/prefabs/guardrail_model.tres")
	var collection: Node3D=world.register_model(KEY,mesh)
	if collection==null:return {}
	# One thin continuous proxy prevents snagging on bars; no rigid-body simulation.
	if not collection.configure_collision(AABB(Vector3(-0.06,0,-2),Vector3(0.12,1.1,4)),64,256,8):return {}
	var stair: Node3D=world.register_model(STAIR_KEY,mesh)
	if stair==null:return {}
	# Four thin top-rail sections keep conservative placement bounds out of the
	# steps while blocking the standing player. Gaps below bars remain open.
	var parts: Array[AABB]=[]
	for i in 4:parts.append(AABB(Vector3(-0.06,1,-2+i),Vector3(0.12,0.1,1)))
	if not stair.configure_compound_collision(parts,64,128,8,512,32):return {}
	return {"title":"Metal guardrail","mesh":mesh,"collection":collection,"scale":Vector3.ONE,"costs":recipe(),"cost_label":"4 metal"}
