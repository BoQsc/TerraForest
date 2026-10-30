# SPDX-License-Identifier: 0BSD
extends SceneTree
class Damage extends RefCounted:
	var amount:=0
	func damage(_key:String,_maximum:int)->int:return amount
var failures:=0
var checks:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func encode(poses:Array[Transform3D])->PackedFloat32Array:
	var result:=PackedFloat32Array()
	for pose:Transform3D in poses:
		for row in 3:result.append_array(PackedFloat32Array([pose.basis.x[row],pose.basis.y[row],pose.basis.z[row],pose.origin[row]]))
	return result
func run()->void:
	GDExtensionManager.load_extension("res://addons/vegetation_runtime/vegetation_runtime.gdextension")
	var native:RefCounted=ClassDB.instantiate("NativeGroundCover")
	var all_ids:=PackedInt64Array();var valid:=true;var maximum:=0;var selected:=0
	var shelters:Array=[PackedVector3Array(),PackedVector3Array(),PackedVector3Array(),PackedVector3Array()]
	for row in 32:
		for column in 32:
			var owner:=Vector2i(column,row);var candidates:Dictionary=native.boulder_candidates(owner,1703)
			maximum=maxi(maximum,candidates.ids.size());all_ids.append_array(candidates.ids)
			var normals:=PackedVector3Array();normals.resize(candidates.ids.size());normals.fill(Vector3.UP)
			var placed:Dictionary=native.place(candidates.ids,candidates.points,normals)
			var mask:=PackedByteArray();mask.resize(placed.ids.size())
			var packed:Dictionary=native.pack_boulders(placed.ids,placed.transforms,mask,shelters)
			valid=valid and not packed.is_empty() and packed.ids==candidates.ids and packed.owners.size()==4
			for part in 4:
				var cell:=owner*2+Vector2i(part%2,part/2)
				var legacy:Dictionary=native.candidates(cell,1703)
				var up:=PackedVector3Array();up.resize(legacy.ids.size());up.fill(Vector3.UP)
				var supported:Dictionary=native.place(legacy.ids,legacy.points,up)
				var excluded:=PackedByteArray();excluded.resize(supported.ids.size())
				var expected:Dictionary=native.boulder_rows(native.pack(supported.ids,supported.transforms,excluded)[0])
				valid=valid and expected==packed.owners[part]
				selected+=expected.ids.size()
	check(valid and maximum<=64 and selected==all_ids.size() and selected>500,"all world boulders match legacy IDs and poses without sampling grass")
	check(native.boulder_candidates(Vector2i(-1,0),1703).ids.is_empty() and native.boulder_candidates(Vector2i.ZERO,-1).ids.is_empty(),"invalid owners and seeds produce no candidates")
	var geometry:Mesh=preload("res://addons/world_ecosystem/woodland_mesh.gd").build(0,false)
	var distant:Mesh=preload("res://addons/world_ecosystem/woodland_mesh.gd").build(0,false,false,true)
	check(distant.surface_get_array_index_len(0)<geometry.surface_get_array_index_len(0)/4,"distant whole-boulder tier reduces triangle cost by more than fourfold")
	var material:=ShaderMaterial.new();material.shader=preload("res://addons/world_ecosystem/boulder_fracture.gdshader")
	var damage:=Damage.new()
	var renderer:Node3D=ClassDB.instantiate("NativeBoulderFracture");root.add_child(renderer)
	check(renderer.configure(geometry,material,damage) and renderer.configure_horizon(distant),"native two-tier fracture renderer configures")
	check(not renderer.configure_horizon(distant),"horizon cannot reconfigure live renderer ownership")
	var pose:=Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*12),Vector3.ZERO)
	check(renderer.upsert_rows(PackedInt64Array([1]),encode([pose])),"canonical boulder admits")
	renderer.advance_view(Vector3.ZERO,1)
	check(renderer.statistics().near==1 and renderer.statistics().far==0,"near view uses detailed tier only")
	renderer.advance_view(Vector3(88,0,0),1)
	check(renderer.statistics().near==1 and renderer.statistics().far==1,"transition keeps both complementary tiers present")
	renderer.advance_view(Vector3(100000,0,0),1)
	check(renderer.statistics().near==0 and renderer.statistics().far==1,"distant boulder never retires at former grass range")
	renderer.advance_view(Vector3(176,0,0),2)
	check(renderer.statistics().near==1 and renderer.statistics().far==1,"projection scale preserves transition during zoom")
	for stage in [1,2]:
		damage.amount=stage*80
		check(renderer.sync_damage(1) and renderer.stage(1)==stage,"damage updates both geometry tiers at stage "+str(stage))
		check(renderer.stage_mesh(stage+4).surface_get_array_len(0)<renderer.stage_mesh(stage).surface_get_array_len(0),"fractured far tier remains cheaper")
	check(renderer.finish(1) and renderer.stage(1)==3,"finishing fracture animates in the shared renderer")
	var deadline:=Time.get_ticks_msec()+2700
	while Time.get_ticks_msec()<deadline:await process_frame
	renderer.advance(Vector3.ZERO)
	check(renderer.statistics().roots==0 and renderer.statistics().near==0 and renderer.statistics().far==0,"finished debris releases both tiers")
	damage.amount=0
	var ids:=PackedInt64Array();var poses:Array[Transform3D]=[]
	for index in 2048:ids.append(index+1);poses.append(Transform3D(pose.basis,Vector3((index%64)*32,0,(index/64)*32)))
	check(renderer.upsert_rows(ids,encode(poses)) and renderer.statistics().roots==2048,"world-sized renderer exceeds old 512-root limit within explicit 4096 cap")
	renderer.advance_view(Vector3(100000,0,0),1)
	check(renderer.statistics().far==2048 and renderer.statistics().near==0,"all world roots remain represented at distance")
	var invalid:=encode([Transform3D(Basis.IDENTITY,Vector3(NAN,0,0))])
	check(not renderer.upsert_rows(PackedInt64Array([9000]),invalid) and renderer.statistics().roots==2048,"invalid publication cannot mutate live roots")
	renderer.clear();check(renderer.statistics().roots==0 and renderer.statistics().far==0,"reset removes all far and near records")
	var picker:RefCounted=ClassDB.instantiate("NativeGroundCoverPicker")
	check(picker.configure_owner_limit(3969) and not picker.configure_owner_limit(3970),"global sparse interaction ownership has a bounded configuration")
	var owners_ok:=true
	for index in 256:
		var cell:=Vector2i(index%16,index/16)
		var rows:Array=[]
		for species in 9:rows.append({"ids":PackedInt64Array(),"transforms":PackedFloat32Array()})
		rows[0]={"ids":PackedInt64Array([index+1]),"transforms":encode([Transform3D(pose.basis,Vector3(cell.x*32+16,2,cell.y*32+16))])}
		owners_ok=picker.replace_cell(cell,rows) and owners_ok
	check(owners_ok,"sparse boulder interaction pages exceed local 121-owner limit")
	var hit:Dictionary=picker.pick(Vector3(496,3,502),Vector3(496,3,494))
	check(hit.hit and hit.id==256 and hit.large,"never-local boulder is pickable through bounded spatial query")
	renderer.free()
	DirAccess.make_dir_recursive_absolute("res://reports")
	FileAccess.open("res://reports/boulder_horizon_native.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"world_candidates":selected,"max_candidates_per_page":maximum}))
	print("BOULDER_HORIZON_NATIVE checks=",checks," failures=",failures)
	quit(1 if failures else 0)
