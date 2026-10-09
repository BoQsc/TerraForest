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

static func recipes() -> Dictionary:
	return {"furniture/table/v1":PackedInt64Array([102,6]),"furniture/chair/v1":PackedInt64Array([102,3]),"furniture/shelf/v1":PackedInt64Array([102,8])}

static func furnished_cottage() -> Resource:
	var source: Resource=load("res://addons/structures/prefabs/brick_cottage.tres")
	var asset: Resource=ClassDB.instantiate("NativeBlockPrefab")
	if not asset.configure(source.get_records()): return null
	if not asset.configure_model_attachments([
		{"model":"furniture/table/v1","transform":Transform3D(Basis.IDENTITY,Vector3(-1.3,1,0))},
		{"model":"furniture/chair/v1","transform":Transform3D(Basis.IDENTITY,Vector3(-1.3,1,1.5))},
		{"model":"furniture/shelf/v1","transform":Transform3D(Basis(Vector3.UP,PI),Vector3(2.5,1,-2.3))}]): return null
	asset.resource_name="Furnished cottage"
	return asset
