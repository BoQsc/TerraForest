# SPDX-License-Identifier: 0BSD
extends SceneTree
var scene:Node3D
var nav:Node3D
var batch:Node3D
var checks:=0
var failures:=0
var changes:Array[AABB]=[]
var rows:Array=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func box(at:Vector3,size:Vector3)->StaticBody3D:
	var body:=StaticBody3D.new();scene.add_child(body);body.position=at
	var collider:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=size;collider.shape=shape;body.add_child(collider);return body
func ready(_bounds:AABB)->bool:return true
func settle()->void:
	for frame in 4:await physics_frame
func plan(id:int,start:Vector3,goal:Vector3,label:String)->Dictionary:
	nav.set_agent(id,start,goal,0,true)
	var row:Dictionary={"label":label,"work":0,"planning_us":0,"ticks":0}
	for tick in 2400:
		await physics_frame
		# Planning-only fixture: no body motion or accumulated stuck time.
		var measured:Dictionary=nav.advance(.00001,ready,Callable())
		row.work+=measured.route_work;row.planning_us+=measured.planning_us;row.ticks=tick+1
		if nav.state(id) in ["following","blocked","unavailable","search_limit"]:break
	row.state=nav.state(id);row.points=nav.route_points(id);row.invalidation=nav.invalidation_stats()
	rows.append(row);print("MODEL_NAV_RESULT ",JSON.stringify(row));return row
func changed(bounds:AABB)->void:
	changes.append(bounds);nav.invalidate(bounds)
func _initialize()->void:run.call_deferred()
func run()->void:
	scene=Node3D.new();root.add_child(scene)
	box(Vector3(12,-.5,40),Vector3(70,1,160))
	box(Vector3(12,2,0),Vector3(.4,4,8));box(Vector3(12,2,80),Vector3(.4,4,8))
	nav=ClassDB.instantiate("NativeActorNavigator");scene.add_child(nav);nav.configure(4)
	batch=ClassDB.instantiate("NativeStaticBatch");scene.add_child(batch)
	var mesh:=BoxMesh.new();mesh.size=Vector3(.4,2.2,1)
	batch.configure_asset("test/door_navigation/v1",mesh)
	batch.configure_collision(AABB(-mesh.size*.5,mesh.size),128,8,4)
	batch.obstacles_changed.connect(changed)
	var pose:=Transform3D(Basis.IDENTITY,Vector3(12,1.1,6))
	check(batch.upsert_transforms(PackedInt64Array([1]),[pose]),"native conditional obstacle installs")
	await settle()
	var rid:RID=batch.collision_body_for(1);var bounds:AABB=batch.instance_obstacle_bounds(1)
	check(rid.is_valid() and bounds.has_point(pose.origin),"native collision owner supplies world bounds for its RID")
	check(nav.set_interactions_scoped([rid],[bounds]),"bounded door planning policy installs")
	var near:=await plan(1,Vector3.ZERO,Vector3(24,0,0),"conditional_near")
	var far:=await plan(2,Vector3(0,0,80),Vector3(24,0,80),"unrelated_far")
	check(near.state=="following" and far.state=="following","both real regional detours complete with conditional planning")
	var before:Dictionary=nav.invalidation_stats()
	check(nav.set_interactions_scoped([rid],[bounds]) and nav.invalidation_stats().count==before.count,"unchanged bounded policy does not invalidate any query")
	nav.set_agent(3,Vector3(11.6,0,6),Vector3(14,0,6),0,true);nav.advance(.00001,ready,Callable())
	check(not nav.guard_motion(3,Vector3.RIGHT,.5),"planning exclusion never disables the intact door's live movement collision")
	nav.remove_agent(3)
	var first_global:int=nav.invalidation_stats().global_count
	check(batch.remove_instances(PackedInt64Array([1])) and changes.back()==bounds,"removal publishes the retired model's old bounds")
	check(nav.state(1)=="idle" and nav.state(2)=="following" and nav.route_points(2)==far.points,"model removal preserves the unrelated complete pursuit")
	check(nav.set_interactions_scoped([],[]),"removed RID policy uses retained old bounds")
	check(nav.invalidation_stats().global_count==first_global and nav.invalidation_stats().live_vertices>0 and nav.state(2)=="following","geometry and policy changes retain shared graph and distant query")
	await settle()
	var warm:=await plan(1,Vector3.ZERO,Vector3(24,0,0),"door_removed_local")
	nav.remove_agent(2);nav.invalidate()
	var cold:=await plan(1,Vector3.ZERO,Vector3(24,0,0),"door_removed_global")
	check(warm.state=="following" and warm.points==cold.points and warm.work<cold.work,"removed door replans through retained connections with exact cold-path parity and less work")
	batch.upsert_transforms(PackedInt64Array([1]),[pose]);await settle()
	rid=batch.collision_body_for(1)
	var untouched:Dictionary=nav.invalidation_stats()
	check(not nav.set_interactions_scoped([rid,rid],[bounds,bounds]) and nav.invalidation_stats().count==untouched.count,"duplicate RIDs reject atomically")
	check(not nav.set_interactions_scoped([rid],[AABB()]) and nav.invalidation_stats().count==untouched.count,"unknown bounds reject without silently omitting the current obstacle")
	nav.set_interactions([rid]);var legacy_count:int=nav.invalidation_stats().global_count
	check(nav.set_interactions_scoped([rid],[bounds]) and nav.invalidation_stats().global_count==legacy_count+1,"transition from unbounded policy retains one conservative global barrier")
	var history:RefCounted=ClassDB.instantiate("NativeStaticHistory")
	check(history.configure([batch],1048576,64),"native edit history registers collision owner")
	var old:AABB=batch.instance_obstacle_bounds(1);var moved:=pose;moved.origin.x+=8
	var packed:=PackedFloat32Array()
	for axis in 3:
		for column in 3:packed.append(moved.basis[column][axis])
		packed.append(moved.origin[axis])
	var count:=changes.size()
	check(history.update(batch,1,packed,AABB()),"journalled model move commits")
	var after:AABB=batch.instance_obstacle_bounds(1)
	check(changes.size()==count+1 and changes.back().encloses(old) and changes.back().encloses(after),"deferred history publishes the union of old and new bounds once")
	count=changes.size()
	check(history.undo(AABB()) and changes.size()==count+1 and changes.back().encloses(old) and changes.back().encloses(after),"undo retains complete movement invalidation bounds")
	count=changes.size()
	check(not batch.upsert_transforms(PackedInt64Array([1,1]),[pose,moved]) and changes.size()==count,"rejected model edit emits no navigation change")
	# Whole-collection transform/prototype changes lack bounded old geometry.
	batch.position=Vector3(1,0,0);await settle()
	check(changes.back().size==Vector3.ZERO,"unbounded collection transform remains a global barrier")
	nav.set_query_profiling(true);var measured:Dictionary=nav.advance(.00001,ready,Callable())
	check(measured.planning_thread_cycles>=0 and measured.planning_thread_cpu_us>=0,"profiled planning records actual thread cycles and quantized CPU time")
	nav.set_query_profiling(false);measured=nav.advance(.00001,ready,Callable())
	check(not measured.has("planning_thread_cycles") and not measured.has("planning_thread_cpu_us"),"ordinary passes omit thread profiling work")
	var folder:="res://reports/navigation_model_changes";DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"runs":rows,"changes":changes},"  "))
	scene.free();await process_frame;print("NAVIGATION_MODEL_CHANGES checks=",checks," failures=",failures);quit(1 if failures else 0)
