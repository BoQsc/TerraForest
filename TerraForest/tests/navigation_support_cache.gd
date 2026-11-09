# SPDX-License-Identifier: 0BSD
extends SceneTree
var scene:Node3D
var nav:Node3D
var checks:=0
var failures:=0
var available:=true
var runs:Array=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func box(at:Vector3,size:Vector3)->StaticBody3D:
	var body:=StaticBody3D.new();body.position=at;scene.add_child(body)
	var collider:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=size;collider.shape=shape;body.add_child(collider);return body
func ready(_bounds:AABB)->bool:return available
func plan()->Dictionary:
	nav.set_agent(1,Vector3.ZERO,Vector3(24,0,0),0,true)
	var totals:Dictionary={"hits":0,"misses":0,"rays":0,"raycasts":0,"planning_us":0}
	for tick in 1800:
		await physics_frame
		var measured:Dictionary=nav.advance(1.0/60,ready,Callable())
		totals.hits+=measured.support_cache_hits;totals.misses+=measured.support_cache_misses
		totals.rays+=measured.query_profile.support_rays;totals.planning_us+=measured.planning_us
		totals.raycasts+=measured.query_profile.support_raycasts
		totals.bytes=measured.support_cache_bytes;totals.limit=measured.support_cache_limit
		if nav.state(1) in ["following","blocked","unavailable","search_limit"]:
			totals.state=nav.state(1);totals.points=nav.route_points(1);totals.ticks=tick+1;runs.append(totals);return totals
	totals.state="timeout";runs.append(totals);return totals
func _initialize()->void:run.call_deferred()
func run()->void:
	scene=Node3D.new();root.add_child(scene)
	var floor_body:=box(Vector3(12,-.5,0),Vector3(60,1,40))
	box(Vector3(12,2,0),Vector3(.4,4,8))
	nav=ClassDB.instantiate("NativeActorNavigator");scene.add_child(nav);nav.configure(1);nav.set_query_profiling(true)
	await physics_frame;await physics_frame
	nav.set_support_cache_enabled(false)
	var control:=await plan()
	nav.clear();nav.set_support_cache_enabled(true)
	var cached:=await plan()
	check(control.state=="following" and cached.state=="following","live and cached support both find the actual wall detour")
	check(control.points==cached.points,"exact cached ray answers preserve the complete path byte-for-byte")
	check(cached.hits>0 and cached.misses<cached.rays and cached.hits+cached.misses==cached.rays,"shared support cache avoids real physics rays without removing samples")
	check(control.raycasts==control.rays and cached.raycasts==cached.misses,"profiling distinguishes requested support samples from physical raycasts")
	check(cached.limit==65536 and cached.bytes<=4*1024*1024,"support cache has fixed entry and memory bounds")
	floor_body.position.y+=.2;nav.invalidate(AABB(Vector3(-18,-1,-20),Vector3(60,2,40)))
	await physics_frame;await physics_frame
	var raised:=await plan();var correct:bool=raised.state=="following"
	if correct:
		for point:Vector3 in raised.points:
			if point.distance_to(Vector3.ZERO)>.01:correct=correct and point.y>.19
	check(correct,"geometry invalidation re-queries the raised floor instead of returning cached old heights")
	nav.set_exclusions([floor_body.get_rid()])
	var excluded:=await plan()
	check(excluded.state=="blocked","changed recipient exclusions cannot reuse a now-excluded support surface")
	nav.set_exclusions([])
	check((await plan()).state=="following","restoring the query policy restores physical support")
	nav.remove_agent(1);available=false
	check((await plan()).state=="unavailable","warm support and edge caches still require current collision coverage")
	available=true;nav.clear();await plan()
	floor_body.free();await physics_frame;await physics_frame
	check(not nav.guard_motion(1,Vector3.RIGHT,.05),"movement guards query live physics even before an edit notification")
	var folder:="res://reports/navigation_support_cache";DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"runs":runs},"  "))
	scene.free();await process_frame;print("NAVIGATION_SUPPORT_CACHE checks=",checks," failures=",failures);quit(1 if failures else 0)
