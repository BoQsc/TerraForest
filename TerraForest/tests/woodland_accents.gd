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
	check(saved.decode_u64(8)==2 and restored.restore_storage_snapshot(saved) and restored.query(Vector2i(30,30))==state.query(Vector2i(30,30)),"v2 roundtrip retains all eight types")
	var legacy=ClassDB.instantiate("NativeGroundCoverState");legacy.bind_world(1703,1);legacy.add(2,Transform3D(Basis.IDENTITY,Vector3(970,20,970)));legacy.mark(32)
	var v1: PackedByteArray=legacy.capture_storage_snapshot();v1.encode_u64(8,1)
	check(restored.restore_storage_snapshot(v1) and restored.contains(32) and restored.query(Vector2i(30,30))[2].ids.size()==1,"v1 saves retain authored grass and removals")
	var corrupt:=saved.duplicate();corrupt.encode_u64(8,1)
	check(not restored.restore_storage_snapshot(corrupt) and restored.capture_storage_snapshot()==v1,"v1 cannot smuggle expanded species and failure is atomic")
	var scatter=ClassDB.instantiate("NativeGroundCover");var counts: Array[int]=[0,0,0,0,0,0,0,0]
	for owner in 256:
		var data: Dictionary=scatter.candidates(Vector2i(owner%16+20,owner/16+20),1703)
		var normals:=PackedVector3Array();normals.resize(data.ids.size());normals.fill(Vector3.UP)
		var placed: Dictionary=scatter.place(data.ids,data.points,normals)
		var mask:=PackedByteArray();mask.resize(data.ids.size())
		var rows: Array=scatter.pack(placed.ids,placed.transforms,mask)
		for species in Catalog.COUNT: counts[species]+=rows[species].ids.size()
	var flowers: int=counts[3]+counts[4]+counts[5]
	check(flowers>80 and flowers<300 and counts[2]>9000 and counts[6]>100 and counts[7]>100,"rare accents over 16384 deterministic candidates")
	check(Catalog.COSTS[7]==102 and Catalog.REWARDS[7]==102,"twig wood cost and reward conserve resource")
	GDExtensionManager.load_extension("res://addons/player_runtime/player_runtime.gdextension")
	var inventory=ClassDB.instantiate("NativePlayerInventory");inventory.register_item(102,999)
	var cover:=CoverStub.new();cover.terrain=TerrainStub.new();cover.add_child(cover.terrain);root.add_child(cover)
	cover.removed=ClassDB.instantiate("NativeGroundCoverState");cover.removed.bind_world(1703,1);cover.picker=picker
	var twig_id: int=cover.removed.add(7,Transform3D(Basis.IDENTITY,Vector3(970,20,970)))
	cover.resident[Vector2i(30,30)]=cover.removed.query(Vector2i(30,30));picker.replace_cell(Vector2i(30,30),cover.resident[Vector2i(30,30)])
	for i in 8:cover.batches.append(BatchStub.new())
	var interaction=preload("res://addons/world_ecosystem/ground_interaction.gd").new();interaction.cover=cover;interaction.scene_ray=func(_a: Vector3,_b: Vector3) -> Dictionary:return {}
	var gathered: Dictionary=interaction.collect(Vector3(970,22,970),Vector3(970,19,970),inventory,true)
	var slots: Array=inventory.snapshot().slots;var wood:=0
	for slot: Dictionary in slots:
		if slot.item==102:wood+=int(slot.count)
	check(gathered.ok and gathered.id==twig_id and wood==1 and cover.removed.profile().placed==0,"gameplay twig collection grants wood and erases exact authored record")
	check(not interaction.collect(Vector3(970,22,970),Vector3(970,19,970),inventory,true).ok,"same twig cannot be gathered twice")
	cover.free()
	print("WOODLAND_ACCENTS ",JSON.stringify({"checks":checks,"failures":failures,"counts":counts}))
	quit(1 if failures else 0)
