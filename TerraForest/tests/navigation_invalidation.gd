# SPDX-License-Identifier: 0BSD
extends SceneTree
var scene:Node3D
var nav:Node3D
var checks:=0
var failures:=0
var available:=true
var rows:Array=[]
var edits:Array=[]
var published:Array[AABB]=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func box(at:Vector3,size:Vector3)->StaticBody3D:
	var body:=StaticBody3D.new();body.position=at;scene.add_child(body)
	var collider:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=size;collider.shape=shape;body.add_child(collider);return body
func ready(_bounds:AABB)->bool:return available
func plan(id:int,start:Vector3,goal:Vector3,label:String)->Dictionary:
	nav.set_agent(id,start,goal,0,true)
	var result:Dictionary={"label":label,"work":0,"planning_us":0,"peak_us":0,"ticks":0}
	for tick in 2400:
		await physics_frame
		# This fixture owns no moving bodies. Tiny elapsed simulation time keeps
		# completed comparison routes from triggering the physical stuck timer.
		var measured:Dictionary=nav.advance(.00001,ready,Callable())
		result.work+=measured.route_work;result.planning_us+=measured.planning_us
		result.peak_us=maxi(result.peak_us,measured.planning_us);result.ticks=tick+1
		if nav.state(id) in ["following","arrived","blocked","unavailable","search_limit"]:break
	result.state=nav.state(id);result.points=nav.route_points(id);result.graph=nav.invalidation_stats()
	rows.append(result);print("INVALIDATION_RESULT ",JSON.stringify(result));return result
func edit(bounds:AABB)->Dictionary:
	nav.invalidate(bounds);var result:Dictionary=nav.invalidation_stats();edits.append(result);return result
func _initialize()->void:run.call_deferred()
func run()->void:
	scene=Node3D.new();root.add_child(scene)
	box(Vector3(12,-.5,40),Vector3(70,1,160))
	box(Vector3(12,2,0),Vector3(.4,4,8));box(Vector3(12,2,80),Vector3(.4,4,8))
	nav=ClassDB.instantiate("NativeActorNavigator");scene.add_child(nav);nav.configure(4)
	await physics_frame;await physics_frame
	var near:=await plan(1,Vector3.ZERO,Vector3(24,0,0),"near_cold")
	var far:=await plan(2,Vector3(0,0,80),Vector3(24,0,80),"far_cold")
	check(near.state=="following" and far.state=="following","two distant regional detours are complete")
	var before:Dictionary=nav.invalidation_stats()
	# Replacing geometry with identical content still publishes a local edit.
	var region:=AABB(Vector3(8,-1,-2),Vector3(5,5,4))
	var local:=edit(region)
	check(not local.global and local.queries_reset==1 and nav.state(1)=="idle" and nav.state(2)=="following","local edit resets only the intersecting pursuit")
	check(nav.route_points(2)==far.points,"unaffected pursuit retains its exact complete path")
	check(local.vertices_retired>0 and local.edges_reset>0 and local.live_vertices>0 and local.vertices_scanned<before.live_vertices,"spatial invalidation retires local supports and edges without scanning the distant graph")
	var warm:=await plan(1,Vector3.ZERO,Vector3(24,0,0),"near_local_replan")
	check(warm.state=="following" and warm.points==near.points,"local recertification preserves the unchanged geometry's exact route")
	check(nav.state(2)=="following" and nav.route_points(2)==far.points,"far route stays valid while affected query replans")
	nav.remove_agent(2);edit(AABB())
	var cold:=await plan(1,Vector3.ZERO,Vector3(24,0,0),"near_global_replan")
	check(cold.state=="following" and cold.points==warm.points and warm.work<cold.work,"local replan performs less route work than global rebuild with identical path")
	var slots:Array=[]
	for cycle in 6:
		edit(region);var rebuilt:=await plan(1,Vector3.ZERO,Vector3(24,0,0),"recycle_%d"%cycle)
		slots.append(rebuilt.graph.allocated_slots)
		check(rebuilt.state=="following" and rebuilt.points==cold.points,"recycled slots preserve exact path after edit %d"%cycle)
	check(slots[-1]==slots[-2] and slots[-1]<=cold.graph.allocated_slots,"repeated edits reuse bounded vertex slots instead of growing retired storage")
	# Mutate a connection actually used by the warm detour, then compare with
	# a cold rebuild. Removing it exercises cached failures too: the original
	# central wall still prevents the direct-corridor fast path in both runs.
	var detour_bounds:=AABB(Vector3(11,0,4.5),Vector3(2,4,3))
	var detour_gate:=box(Vector3(12,2,6),Vector3(2,4,3));edit(detour_bounds)
	await physics_frame;await physics_frame
	var closed_warm:=await plan(1,Vector3.ZERO,Vector3(24,0,0),"detour_closed_local")
	edit(AABB());var closed_cold:=await plan(1,Vector3.ZERO,Vector3(24,0,0),"detour_closed_global")
	check(closed_warm.state=="following" and closed_warm.points!=cold.points and closed_warm.points==closed_cold.points,"edited warm positive edges produce the same safe detour as a cold rebuild")
	detour_gate.free();edit(detour_bounds);await physics_frame;await physics_frame
	var open_warm:=await plan(1,Vector3.ZERO,Vector3(24,0,0),"detour_opened_local")
	edit(AABB());var open_cold:=await plan(1,Vector3.ZERO,Vector3(24,0,0),"detour_opened_global")
	check(open_warm.state=="following" and open_warm.points==cold.points and open_warm.points==open_cold.points,"removed obstruction recertifies negative edges and restores the exact cold path")
	nav.clear()
	var floor_body:=box(Vector3(220,-.5,0),Vector3(44,1,2))
	await physics_frame;await physics_frame
	check((await plan(1,Vector3(200,0,0),Vector3(240,0,0),"causeway_open")).state=="following","narrow causeway starts connected")
	var gate_bounds:=AABB(Vector3(219.8,0,-4),Vector3(.4,4,8))
	var gate:=box(Vector3(220,2,0),Vector3(.4,4,8));edit(gate_bounds)
	await physics_frame;await physics_frame
	check((await plan(1,Vector3(200,0,0),Vector3(240,0,0),"causeway_closed")).state=="blocked","new local barrier invalidates positive connectivity")
	gate.free();edit(gate_bounds);await physics_frame;await physics_frame
	check((await plan(1,Vector3(200,0,0),Vector3(240,0,0),"causeway_reopened")).state=="following","removed local barrier invalidates negative certificates")
	floor_body.position.y+=1;edit(AABB(Vector3(198,-1,-1),Vector3(44,2,2)))
	await physics_frame;await physics_frame
	nav.remove_agent(1) # New feet/goal after the fixture teleports the entire causeway.
	var raised:=await plan(1,Vector3(200,1,0),Vector3(240,1,0),"causeway_raised")
	var correct:bool=raised.state=="following"
	for point:Vector3 in raised.points:correct=correct and absf(point.y-1)<.01
	check(correct,"height edits retire old supports and publish only the raised route")
	nav.remove_agent(1);available=false
	check((await plan(1,Vector3(200,1,0),Vector3(240,1,0),"unavailable")).state=="unavailable","retained graph still checks live collision residency")
	available=true;nav.set_exclusions([floor_body.get_rid()])
	check(nav.invalidation_stats().global and nav.invalidation_stats().live_vertices==0 and (await plan(1,Vector3(200,1,0),Vector3(240,1,0),"excluded_floor")).state=="blocked","recipient policy change remains a global barrier")
	nav.set_exclusions([]);await plan(1,Vector3(200,1,0),Vector3(240,1,0),"restored_floor")
	floor_body.free();await physics_frame;await physics_frame
	check(not nav.guard_motion(1,Vector3.RIGHT,.05),"motion guard checks current support before any edit signal")
	var count_before:int=nav.invalidation_stats().count
	edit(AABB(Vector3(999,0,0),Vector3.ONE));edit(AABB())
	nav.set_query_profiling(true)
	var profiled:Dictionary=nav.advance(.00001,ready,Callable())
	check(profiled.invalidation.count==count_before+2 and profiled.invalidation.global and profiled.invalidation.total_us>=profiled.invalidation.max_us,"trace diagnostics retain cumulative invalidations between physics captures")
	nav.set_query_profiling(false)
	check(not nav.advance(.00001,ready,Callable()).has("invalidation"),"ordinary navigation ticks omit opt-in invalidation diagnostics")
	nav.clear()
	for height in [0,8]:
		box(Vector3(412,height-.5,0),Vector3(60,1,40));box(Vector3(412,height+2,0),Vector3(.4,4,8))
	await physics_frame;await physics_frame
	var lower:=await plan(1,Vector3(400,0,0),Vector3(424,0,0),"lower_storey")
	var upper:=await plan(2,Vector3(400,8,0),Vector3(424,8,0),"upper_storey")
	check(lower.state=="following" and upper.state=="following","coincident horizontal detours retain distinct supported storeys")
	var storey_edit:=edit(AABB(Vector3(408,-1,-2),Vector3(5,5,4)))
	check(storey_edit.queries_reset==1 and nav.state(1)=="idle" and nav.state(2)=="following" and nav.route_points(2)==upper.points,"lower-storey edit preserves the exact upper-storey pursuit")
	if not "--native-only" in OS.get_cmdline_user_args():check_host()
	var folder:="res://reports/navigation_invalidation";DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"runs":rows,"edits":edits,"slots":slots},"  "))
	scene.free();await process_frame;print("NAVIGATION_INVALIDATION checks=",checks," failures=",failures);quit(1 if failures else 0)

func check_host()->void:
	# Verify the actual building host forwards native changed-cell bounds in
	# world space, while unbounded model policy changes retain the full barrier.
	var structures:Node3D=load("res://addons/structures/structures_world.gd").new()
	structures.position=Vector3(500,0,0);scene.add_child(structures)
	check(structures.prepare(),"real building host prepares")
	structures.obstacles_changed.connect(func(bounds:AABB):published.append(bounds))
	structures.blocks.set_cells(PackedInt32Array([8,0,8,1]))
	check(published.size()==1 and published[0].has_point(Vector3(508.5,.5,8.5)) and published[0].size.length()<4,"native block edit publishes local transformed navigation bounds")
	structures._exclusion_changed()
	check(published.size()==2 and published.back().size==Vector3.ZERO,"unbounded model changes preserve global invalidation")
