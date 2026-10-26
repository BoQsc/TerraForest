# SPDX-License-Identifier: 0BSD
extends SceneTree
const Asset=preload("res://addons/world_ecosystem/woodland_mesh.gd")
const Catalog=preload("res://addons/world_ecosystem/ground_catalog.gd")
class TerrainStub extends Node:
	var world_ready:=true
	var pending_edit:=false
	var stopping:=false
class BatchStub extends RefCounted:
	func remove_instances(_ids: PackedInt64Array) -> bool: return true
class CoverStub extends Node3D:
	var terrain: Node
	var removed: RefCounted
	var picker: RefCounted
	var seed:=1703
	var _dirty: Dictionary={}
	var _pending: Dictionary={}
	var resident: Dictionary={}
	var batches: Array=[]
var failures:=0
var checks:=0
var mesh_counts: Array=[]
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	GDExtensionManager.load_extension("res://addons/vegetation_runtime/vegetation_runtime.gdextension")
	var ui=preload("res://addons/player_runtime/player_hud.gd").GroundCatalog
	check(ui.ITEMS==Catalog.ITEMS and ui.COSTS==Catalog.COSTS and ui.NAMES==Catalog.NAMES,"standalone UI catalog matches ecosystem")
	var state=ClassDB.instantiate("NativeGroundCoverState");state.bind_world(1703,1)
	var picker=ClassDB.instantiate("NativeGroundCoverPicker")
	for species in Catalog.COUNT:
		var mesh:=Asset.build(species);var arrays:=mesh.surface_get_arrays(0)
		var valid:=true;var bounds:=mesh.custom_aabb
		for point: Vector3 in arrays[Mesh.ARRAY_VERTEX]: valid=valid and point.is_finite() and bounds.has_point(point)
		var full:=Asset.build(species,false)
		var near_count: int=full.surface_get_array_len(0)
		var all_points: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var far_count: int=all_points.size()-near_count
		check(far_count>0 and far_count<near_count and full.get_faces()==mesh.get_faces(),"LOD keeps near shape and reduces triangles %d"%species)
		for i in range(near_count,all_points.size(),3):valid=valid and (all_points[i+1]-all_points[i]).cross(all_points[i+2]-all_points[i]).length_squared()>1e-15
		mesh_counts.append({"species":species,"near_triangles":near_count/3,"far_triangles":far_count/3})
		var faces:=mesh.get_faces()
		for i in range(0,faces.size(),3):valid=valid and (faces[i+1]-faces[i]).cross(faces[i+2]-faces[i]).length_squared()>1e-15
		check(valid,"bounded nondegenerate geometry %d"%species)
		var pose:=Transform3D(Basis.IDENTITY,Vector3(970+species*2,20,970))
		var id: int=state.add(species,pose)
		check(id>0 and picker.replace_cell(Vector2i(30,30),state.query(Vector2i(30,30))),"authored identity and picker %d"%species)
		var hit: Dictionary=picker.pick(pose.origin+Vector3.UP*2,pose.origin-Vector3.UP)
		check(hit.hit and hit.species==species and hit.id==id,"individual selection %d"%species)
	var saved: PackedByteArray=state.capture_storage_snapshot()
	var restored=ClassDB.instantiate("NativeGroundCoverState")
	check(saved.decode_u64(8)==3 and restored.restore_storage_snapshot(saved) and restored.query(Vector2i(30,30))==state.query(Vector2i(30,30)),"v3 roundtrip retains all nine types")
	var legacy=ClassDB.instantiate("NativeGroundCoverState");legacy.bind_world(1703,1);legacy.add(2,Transform3D(Basis.IDENTITY,Vector3(970,20,970)));legacy.mark(32)
	var v1: PackedByteArray=legacy.capture_storage_snapshot();v1.encode_u64(8,1)
	check(restored.restore_storage_snapshot(v1) and restored.contains(32) and restored.query(Vector2i(30,30))[2].ids.size()==1,"v1 saves retain authored grass and removals")
	var v2:=v1.duplicate();v2.encode_u64(8,2)
	check(restored.restore_storage_snapshot(v2),"v2 saves remain readable")
	check(restored.restore_storage_snapshot(v1),"restore v1 baseline")
	var corrupt:=saved.duplicate();corrupt.encode_u64(8,1)
	check(not restored.restore_storage_snapshot(corrupt) and restored.capture_storage_snapshot()==v1,"v1 cannot smuggle expanded species and failure is atomic")
	var grass:=Asset.build(2);var material: ShaderMaterial=grass.surface_get_material(0)
	var original_faces:=grass.get_faces()
	check(material.get_shader_parameter("grass_detail_strength")==0.0,"generated grass texture defaults off")
	check(Asset.set_grass_detail(material,true),"generated texture loads without editor import")
	var texture: Texture2D=material.get_shader_parameter("grass_detail")
	check(texture.get_size()==Vector2(256,256) and texture.get_image().has_mipmaps(),"shared grass texture has bounded resolution and mipmaps")
	check(Asset.set_grass_detail(material,false) and material.get_shader_parameter("grass_detail_strength")==0.0 and original_faces==grass.get_faces(),"texture toggle restores off without geometry changes")
	var scatter=ClassDB.instantiate("NativeGroundCover");var counts: Array[int]=[0,0,0,0,0,0,0,0,0]
	for owner in 256:
		var data: Dictionary=scatter.candidates(Vector2i(owner%16+20,owner/16+20),1703)
		var normals:=PackedVector3Array();normals.resize(data.ids.size());normals.fill(Vector3.UP)
		var placed: Dictionary=scatter.place(data.ids,data.points,normals)
		var mask:=PackedByteArray();mask.resize(data.ids.size())
		var rows: Array=scatter.pack(placed.ids,placed.transforms,mask)
		for species in Catalog.COUNT: counts[species]+=rows[species].ids.size()
	var flowers: int=counts[3]+counts[4]+counts[5]
	check(flowers>80 and flowers<300 and counts[2]>9000 and counts[6]>100 and counts[7]>100 and counts[8]>30 and counts[8]<120,"rare accents over 16384 deterministic candidates")
	check(Catalog.COSTS[7]==102 and Catalog.REWARDS[7]==102,"twig wood cost and reward conserve resource")
	GDExtensionManager.load_extension("res://addons/player_runtime/player_runtime.gdextension")
	var inventory=ClassDB.instantiate("NativePlayerInventory");inventory.register_item(102,999)
	check(inventory.register_item(209,999),"bush reward registered before inventory mutations")
	var cover:=CoverStub.new();cover.terrain=TerrainStub.new();cover.add_child(cover.terrain);root.add_child(cover)
	cover.removed=ClassDB.instantiate("NativeGroundCoverState");cover.removed.bind_world(1703,1);cover.picker=picker
	var twig_id: int=cover.removed.add(7,Transform3D(Basis.IDENTITY,Vector3(970,20,970)))
	cover.resident[Vector2i(30,30)]=cover.removed.query(Vector2i(30,30));picker.replace_cell(Vector2i(30,30),cover.resident[Vector2i(30,30)])
	for i in 9:cover.batches.append(BatchStub.new())
	var interaction=preload("res://addons/world_ecosystem/ground_interaction.gd").new();interaction.cover=cover;interaction.scene_ray=func(_a: Vector3,_b: Vector3) -> Dictionary:return {}
	var gathered: Dictionary=interaction.collect(Vector3(970,22,970),Vector3(970,19,970),inventory,true)
	var slots: Array=inventory.snapshot().slots;var wood:=0
	for slot: Dictionary in slots:
		if slot.item==102:wood+=int(slot.count)
	check(gathered.ok and gathered.id==twig_id and wood==1 and cover.removed.profile().placed==0,"gameplay twig collection grants wood and erases exact authored record")
	check(not interaction.collect(Vector3(970,22,970),Vector3(970,19,970),inventory,true).ok,"same twig cannot be gathered twice")
	check(Catalog.HARVEST_ONLY.size()==Catalog.COUNT,"every species declares harvesting policy")
	for species in [6,8]:
		var bush_id:int=cover.removed.add(species,Transform3D(Basis.IDENTITY,Vector3(970,20,970)))
		cover.resident[Vector2i(30,30)]=cover.removed.query(Vector2i(30,30));picker.replace_cell(Vector2i(30,30),cover.resident[Vector2i(30,30)])
		var before_inventory:PackedByteArray=inventory.capture_storage_snapshot()
		var before_cover:PackedByteArray=cover.removed.capture_storage_snapshot()
		var pickup:Dictionary=interaction.collect(Vector3(970,22,970),Vector3(970,19,970),inventory,true)
		check(not pickup.ok and pickup.reason.contains("Strike"),"bush %d cannot be picked up with E"%species)
		check(inventory.capture_storage_snapshot()==before_inventory and cover.removed.capture_storage_snapshot()==before_cover,"rejected bush pickup changes neither inventory nor vegetation")
		check(not interaction.collect(Vector3(970,22,970),Vector3(970,19,970),inventory,true,null,bush_id+1).ok,"wrong harvest identity cannot remove bush")
		var harvested:Dictionary=interaction.collect(Vector3(970,22,970),Vector3(970,19,970),inventory,true,null,bush_id)
		print("BUSH_HARVEST species=",species," identity=",bush_id," result=",harvested)
		check(harvested.ok and harvested.id==bush_id and cover.removed.profile().placed==0,"finished harvest removes exact bush %d"%species)
		var reward:int=Catalog.REWARDS[species]
		var total:=0
		for slot:Dictionary in inventory.snapshot().slots:
			if slot.item==reward:total+=int(slot.count)
		check(total==(1 if species==6 else 2),"harvest grants existing species reward once")
		check(not interaction.collect(Vector3(970,22,970),Vector3(970,19,970),inventory,true,null,bush_id).ok,"stale bush cannot grant another reward")
		cover.removed.add(species,Transform3D(Basis.IDENTITY,Vector3(970,20,970)))
		cover.resident[Vector2i(30,30)]=cover.removed.query(Vector2i(30,30));picker.replace_cell(Vector2i(30,30),cover.resident[Vector2i(30,30)])
		before_inventory=inventory.capture_storage_snapshot()
		check(interaction.collect(Vector3(970,22,970),Vector3(970,19,970),inventory,false).ok and inventory.capture_storage_snapshot()==before_inventory,"developer removal remains available without rewards")
	cover.free()
	print("WOODLAND_ACCENTS ",JSON.stringify({"checks":checks,"failures":failures,"counts":counts,"meshes":mesh_counts}))
	quit(1 if failures else 0)
