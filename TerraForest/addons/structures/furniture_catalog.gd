# SPDX-License-Identifier: 0BSD
extends RefCounted
# Stable asset keys are persistence identities. Baked meshes share native pages.
static func register(world: Node3D) -> Array[Dictionary]:
	var entries: Array[Dictionary]=[]
	for name in ["table","chair","shelf"]:
		var mesh: Mesh=load("res://addons/structures/prefabs/"+name+"_model.tres")
		var collection: Node3D=world.register_model("furniture/"+name+"/v1",mesh)
		if collection==null: return []
		if not collection.configure_compound_collision(mesh.get_meta("collision_boxes"),64,256,8,1792,56): return []
		var cost: int={"table":6,"chair":3,"shelf":8}[name]
		entries.append({"title":"Wooden "+name,"mesh":mesh,"collection":collection,"scale":Vector3.ONE,"costs":PackedInt64Array([102,cost]),"cost_label":"%d wood"%cost})
	return entries
