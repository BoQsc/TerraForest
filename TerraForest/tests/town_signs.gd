# SPDX-License-Identifier: 0BSD
extends SceneTree
const Signs=preload("res://addons/world_runtime/town_signs.gd")
const Plan=preload("res://addons/world_runtime/town_sign_plan.gd")
var failures:=0
var checks:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func run()->void:
	var structures:=preload("res://addons/structures/structures_world.gd").new();root.add_child(structures)
	var signs:=Signs.new();root.add_child(signs)
	var persistence:=preload("res://addons/world_runtime/world_persistence.gd").new()
	check(structures.prepare() and signs.prepare(persistence,structures),"common native body and optional metadata register before catalog seal")
	var pose:=Transform3D(Basis(Vector3.UP,.7),Vector3(500,60,600))
	check(signs.collection.upsert_transforms(PackedInt64Array([1]),[pose]),"native model accepts precise three-box sign")
	check(signs.store.set_plan(1703,29,[{"id":1,"title":Plan.town_name(1703,0),"detail":"Roadside town entrance","position":pose.origin}],[]),"town name accepted by native persistent metadata")
	signs.sync_labels()
	check(signs.labels.size()==1 and signs.labels[1].transform.origin.is_equal_approx(pose*Vector3(0,1.88,.04)),"physical lettering follows saved native model pose")
	check(signs.lettering("Hollow Creek").get_aabb().size.x<=2.49,"long town name fits inside board")
	var metadata:PackedByteArray=signs.store.capture_snapshot();var models:PackedByteArray=signs.collection.capture_snapshot()
	check(signs.collection.remove_instances(PackedInt64Array([1])),"sign follows ordinary native destruction")
	await process_frame
	check(signs.labels.is_empty(),"destroying sign removes its lettering without frame polling")
	check(signs.restore_snapshot(metadata) and signs.labels.is_empty(),"restoring metadata cannot resurrect a destroyed body")
	check(signs.collection.restore_snapshot(models),"native sign snapshot restores")
	await process_frame
	check(signs.labels.size()==1,"body restoration recreates lettering from retained metadata")
	var region:PackedByteArray=signs.collection.capture_region(Vector3i(15,1,18))
	check(not region.is_empty() and signs.collection.unload_region(region) and signs.labels.is_empty(),"region retirement removes lettering with unavailable body")
	check(signs.collection.restore_region(region) and signs.labels.size()==1,"region admission recreates exactly one label")
	check(signs.restore_snapshot(PackedByteArray()) and signs.labels.is_empty(),"old worlds with no sign metadata remain empty")
	check(preload("res://addons/structures/construction_catalog.gd").salvage_recipes(structures.object_definitions)[Signs.KEY]==PackedInt64Array([102,2]),"destruction uses existing wood salvage definition")
	var road:={"start":Vector3(200,60,200),"finish":Vector3(200,60,400),"half_width":4,"shoulder":3}
	var site:={"town":0,"district":0,"center":Vector3(200,60,300),"roads":[road],"lots":[]}
	var candidates:Dictionary=Plan.candidates([site],{})
	check(candidates[0].size()>=2,"single town without regional links still has approach candidates")
	var valid:=true
	for candidate:Dictionary in candidates[0]:
		valid=valid and Plan.clear(candidate.transform,[road],[]) and candidate.transform.basis.z.dot(candidate.approach-site.center)>0
	check(valid,"every candidate clears road and walking margin and faces arriving traffic")
	check(not Plan.clear(Transform3D(Basis.IDENTITY,Vector3(205,60,300)),[road],[]),"reject sign inside road shoulder")
	check(Plan.town_name(1703,0)!=Plan.town_name(1703,1) and Plan.town_name(1703,1)!=Plan.town_name(1703,2),"towns in same world have distinct deterministic names")
	signs.free();structures.free();await process_frame
	print("TOWN_SIGNS checks=",checks," failures=",failures);quit(1 if failures else 0)
