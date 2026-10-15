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
	# Site preparation requires the foundation base at local Y=0. Composition
	# shifts blocks and every attached model together without changing their fit.
	var grounded: Resource=ClassDB.instantiate("NativeBlockPrefab")
	if not grounded.compose([asset],PackedInt32Array([0,0,1,0,0])):return null
	grounded.resource_name="Furnished cottage with door and windows"
	return grounded

static func furnished_tower(floors: int=3) -> Resource:
	if floors<2 or floors>16:return null
	var source: Resource=load("res://addons/structures/prefabs/tower_floor.tres")
	var modules: Array[Resource]=[]
	var placements:=PackedInt32Array()
	for level in floors:
		var module: Resource=ClassDB.instantiate("NativeBlockPrefab")
		if not module.configure(source.get_records()):return null
		var attachments: Array=[]
		# Work areas stay outside the stair shaft and its eastern circulation aisle.
		for x in [-5.0,5.5]:
			attachments.append({"model":"furniture/table/v1","transform":Transform3D(Basis.IDENTITY,Vector3(x,1,-4))})
			attachments.append({"model":"furniture/chair/v1","transform":Transform3D(Basis.IDENTITY,Vector3(x,1,-2.5))})
		attachments.append({"model":"furniture/shelf/v1","transform":Transform3D(Basis.IDENTITY,Vector3(-5,1,5))})
		attachments.append({"model":"storage/wooden_chest/v1","transform":Transform3D(Basis.IDENTITY,Vector3(5.5,1,5))})
		# Three-metre window bands fit between the existing one-metre pillars.
		for p in [-5.5,-1.5,2.5,6.5]:
			attachments.append({"model":"architecture/wooden_window/v1","transform":Transform3D(Basis.IDENTITY.scaled(Vector3(1.5,1,1)),Vector3(p,2,-7.5))})
			for x in [-7.5,8.5]:
				attachments.append({"model":"architecture/wooden_window/v1","transform":Transform3D(Basis(Vector3.UP,PI/2).scaled(Vector3(1,1,1.5)),Vector3(x,2,p))})
		for p in [-5.5,6.5]:
			attachments.append({"model":"architecture/wooden_window/v1","transform":Transform3D(Basis.IDENTITY.scaled(Vector3(1.5,1,1)),Vector3(p,2,8.5))})
		if not module.configure_model_attachments(attachments):return null
		modules.append(module);placements.append_array(PackedInt32Array([level,0,level*4,0,0]))
	var tower: Resource=ClassDB.instantiate("NativeBlockPrefab")
	if not tower.compose(modules,placements):return null
	tower.resource_name="Furnished tower · %d floors"%floors
	return tower
