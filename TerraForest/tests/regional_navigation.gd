# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
var scene:Node3D
var nav:Node3D
var peak_work:=0
var peak_us:=0
var peak_readiness_hits:=0
var pending:=false
var rows:Array=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func box(at:Vector3,size:Vector3)->StaticBody3D:
	var body:=StaticBody3D.new();body.position=at;scene.add_child(body)
	var shape:=BoxShape3D.new();shape.size=size;var collider:=CollisionShape3D.new();collider.shape=shape;body.add_child(collider);return body
func ready(bounds:AABB)->bool:return not pending or bounds.end.x<=12
func plan(start:Vector3,goal:Vector3,seconds:float=30,stop_unavailable:bool=true)->Dictionary:
	nav.set_agent(1,start,goal,0,true)
	for tick in int(seconds*Engine.physics_ticks_per_second):
		await physics_frame
		var measured:Dictionary=nav.advance(1.0/Engine.physics_ticks_per_second,ready,Callable())
		peak_work=maxi(peak_work,measured.route_work);peak_us=maxi(peak_us,measured.planning_us)
		peak_readiness_hits=maxi(peak_readiness_hits,measured.readiness_cache_hits)
		var state:Dictionary=nav.status(1)
		if tick%300==0:print("REGIONAL_PROGRESS ",JSON.stringify(state))
		if state.state in ["following","arrived","blocked","search_limit"] or stop_unavailable and state.state=="unavailable":
			rows.append({"start":start,"goal":goal,"tick":tick,"status":state,"points":nav.route_points(1)});print("REGIONAL_RESULT ",JSON.stringify(rows.back()));return state
	return nav.status(1)
func _initialize()->void:run.call_deferred()
func run()->void:
	scene=Node3D.new();root.add_child(scene);box(Vector3(24,-.5,0),Vector3(100,1,80))
	nav=ClassDB.instantiate("NativeActorNavigator");scene.add_child(nav);nav.configure(6)
	# A detour longer than the former local horizon, including a turn away from
	# the destination. No route hints or hand-authored waypoint sequence.
	var wall:=box(Vector3(20,2,0),Vector3(.4,4,28))
	await physics_frame;await physics_frame
	var state:=await plan(Vector3(0,0,0),Vector3(40,0,0),45)
	check(state.state=="following" and state.planner=="regional" and state.complete_path,"regional surface graph finds a complete forty-metre wall detour")
	check(state.get("portals",0)>=4 and state.get("regions",0)>=5,"complete route crosses multiple verified tile portals")
	check(not state.local_horizon and state.goal==Vector3(40,0,0),"planner retains actual destination instead of projecting a local horizon")
	nav.remove_agent(1);state=await plan(Vector3.ZERO,Vector3(40,0,0),15)
	check(state.state=="following" and state.graph_cache_hits>0,"another query reuses verified regional graph connections")
	wall.free();nav.clear();await physics_frame
	pending=true;state=await plan(Vector3.ZERO,Vector3(40,0,0),10)
	check(state.state=="unavailable" and not nav.interest_points().is_empty(),"unknown regional frontier requests residency and holds the body")
	pending=false;state=await plan(Vector3.ZERO,Vector3(40,0,0),20,false)
	check(state.state=="following","same regional search resumes after requested collision arrives")
	nav.clear()
	var blocks:Node3D=ClassDB.instantiate("NativeBlockWorld");scene.add_child(blocks);blocks.set_collision_radius(64)
	var tower:Resource=preload("res://addons/structures/furniture_catalog.gd").furnished_tower(3)
	check(blocks.set_cells(tower.get_records()),"actual three-storey tower block topology installs")
	blocks.flush_bakes();for tick in 90:await physics_frame
	state=await plan(Vector3(.5,0,12),Vector3(5.5,9,5),90)
	check(state.state=="following","regional graph connects entrance and two stair flights to actual upper floor")
	var points:PackedVector3Array=nav.route_points(1);var low:=false;var middle:=false;var high:=false
	for point in points:low=low or point.y<1.1;middle=middle or point.y>4.8 and point.y<5.2;high=high or point.y>8.8
	check(low and middle and high,"planned path retains separate ground, first and second floor surfaces")
	nav.clear()
	box(Vector3(220,-.5,0),Vector3(44,1,2))
	await physics_frame;await physics_frame
	state=await plan(Vector3(200,0,0),Vector3(240,0,0),15)
	check(state.state=="following","remote narrow causeway has a complete connected path")
	var gate:=box(Vector3(220,2,0),Vector3(.4,4,8));nav.invalidate();await physics_frame;await physics_frame
	state=await plan(Vector3(200,0,0),Vector3(240,0,0),15)
	check(state.state=="blocked","edited regional disconnection invalidates cached reachability and reports blocked")
	gate.free();nav.invalidate();await physics_frame;await physics_frame
	state=await plan(Vector3(200,0,0),Vector3(240,0,0),15)
	check(state.state=="following","removing the regional barrier restores connectivity")
	check(peak_work<=48 and state.get("graph_nodes",0)<=32768 and state.nodes<=16384,"regional queries and shared graph respect declared work and memory caps")
	check(peak_readiness_hits>0,"planning reuses positively ready containing boxes within its synchronous pass")
	DirAccess.make_dir_recursive_absolute("res://reports/regional_navigation")
	var file:=FileAccess.open("res://reports/regional_navigation/result.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures,"peak_work":peak_work,"peak_planning_us":peak_us,"routes":rows,"last":state},"  "));file.close()
	scene.free();await process_frame;print("REGIONAL_NAVIGATION checks=",checks," failures=",failures);quit(1 if failures else 0)
