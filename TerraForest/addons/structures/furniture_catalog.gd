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

static func furnished_cottage(with_storage: bool=false) -> Resource:
	var source: Resource=load("res://addons/structures/prefabs/brick_cottage.tres")
	var asset: Resource=ClassDB.instantiate("NativeBlockPrefab")
	if not asset.configure(source.get_records()): return null
	if not asset.configure_model_attachments([
		{"model":"furniture/table/v1","transform":Transform3D(Basis.IDENTITY,Vector3(-1.3,1,0))},
		{"model":"furniture/chair/v1","transform":Transform3D(Basis.IDENTITY,Vector3(-1.3,1,1.5))},
		{"model":"furniture/shelf/v1","transform":Transform3D(Basis(Vector3.UP,PI),Vector3(2.5,1,-2.3))}]): return null
	if with_storage:
		var attachments: Array=asset.get_model_attachments()
		attachments.append({"model":"storage/wooden_chest/v1","transform":Transform3D(Basis.IDENTITY,Vector3(2.5,1,0))})
		if not asset.configure_model_attachments(attachments): return null
	asset.resource_name="Furnished cottage with storage" if with_storage else "Furnished cottage"
	return asset

# Provisional dismantling yield: partial recovery, not a full construction refund.
static func salvage_recipes() -> Dictionary:
	return {"furniture/table/v1":PackedInt64Array([102,3]),"furniture/chair/v1":PackedInt64Array([102,1]),"furniture/shelf/v1":PackedInt64Array([102,4])}

static func enclosed_cottage() -> Resource:
	var asset: Resource=furnished_cottage(true)
	if asset==null:return null
	var attachments: Array=asset.get_model_attachments()
	# Existing one-metre-wide, two-metre-high doorway; retain its stair approach.
	attachments.append({"model":"architecture/wooden_door/v1","transform":Transform3D(Basis.IDENTITY.scaled(Vector3(1,0.9,1)),Vector3(0,1,5.5))})
	for z in [-4.5,5.5]:
		for x in [-1.5,2.5]:
			attachments.append({"model":"architecture/wooden_window/v1","transform":Transform3D(Basis.IDENTITY.scaled(Vector3(0.5,1,1)),Vector3(x,2,z))})
	for x in [-3.5,4.5]:
		for z in [-1,2]:
			attachments.append({"model":"architecture/wooden_window/v1","transform":Transform3D(Basis(Vector3.UP,PI/2),Vector3(x,2,z))})
	if not asset.configure_model_attachments(attachments):return null
	asset.resource_name="Furnished cottage with door and windows"
	return asset
