# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func ticks(n:int)->void:
	for tick in n:await physics_frame
func _initialize()->void:run.call_deferred()
func run()->void:
	var planner:RefCounted=ClassDB.instantiate("NativeTerrainPlanner")
	var focus:=Vector3(800,50,800)
	var base:Dictionary=planner.requests(focus,true,{},{},[])
	var interest:=PackedVector3Array([focus+Vector3(80,0,0)])
	var plan:Dictionary=planner.requests_navigation(focus,true,Vector3.ZERO,Vector3.INF,interest,{},{},[])
	check(plan.ok and plan.requested_keys.size()>base.requested_keys.size(),"navigation adds bounded terrain detail beside the player's existing refinement")
	check(plan.requests[0]==base.requests[0],"navigation leaves primary player activation first")
	var excessive:=PackedVector3Array();excessive.resize(9);excessive.fill(focus)
	check(not planner.requests_navigation(focus,true,Vector3.ZERO,Vector3.INF,excessive,{},{},[]).ok,"terrain rejects more than eight interests")
	check(not planner.requests_navigation(focus,true,Vector3.ZERO,Vector3.INF,PackedVector3Array([focus+Vector3.RIGHT*129]),{},{},[]).ok,"terrain rejects interests beyond its declared input domain")
	var blocks:Node3D=ClassDB.instantiate("NativeBlockWorld");root.add_child(blocks);blocks.set_collision_radius(4);blocks.set_focus(Vector3.ZERO)
	blocks.set_cells(PackedInt32Array([80,0,0,1]));blocks.flush_bakes();await ticks(5)
	var region:=AABB(Vector3(80,0,0),Vector3.ONE)
	check(not blocks.is_collision_region_ready(region),"distant authored block is not falsely reported as resident collision")
	check(blocks.set_navigation_interest(PackedVector3Array([Vector3(80,1,0)])),"bounded block interest admits")
	await ticks(8)
	check(blocks.is_collision_region_ready(region),"block interest publishes collision without changing player focus")
	blocks.set_navigation_interest(PackedVector3Array());await ticks(8)
	check(not blocks.is_collision_region_ready(region),"releasing interests retires distant block collision")
	var batch:Node3D=ClassDB.instantiate("NativeStaticBatch");root.add_child(batch);var mesh:=BoxMesh.new();mesh.size=Vector3.ONE
	batch.configure_asset("test/navigation/v1",mesh);batch.configure_collision(AABB(-Vector3.ONE*.5,Vector3.ONE),4,1,1)
	batch.upsert_transforms(PackedInt64Array([1,2]),[Transform3D(Basis.IDENTITY,Vector3.ZERO),Transform3D(Basis.IDENTITY,Vector3(80,0,0))])
	batch.set_collision_focus(Vector3.ZERO);await ticks(5)
	var snapshot:PackedByteArray=batch.capture_snapshot()
	batch.set_navigation_interest(PackedVector3Array([Vector3(80,0,0)]));await ticks(5)
	check(batch.collision_body_for(1).is_valid() and not batch.collision_body_for(2).is_valid(),"player proxy keeps priority when navigation competes for a full body budget")
	check(batch.collision_stats().resident_bodies<=1,"navigation cannot exceed model proxy budget")
	check(not batch.set_navigation_interest(excessive) and batch.capture_snapshot()==snapshot,"rejected navigation interests cannot mutate authoritative model placements")
	batch.free();blocks.free();await process_frame
	print("NAVIGATION_RESIDENCY checks=",checks," failures=",failures);quit(1 if failures else 0)
