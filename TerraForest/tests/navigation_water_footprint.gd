# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
var water:RefCounted
var nav:Node3D
var scene:Node3D
var runs:Array=[]
const OFFSETS=[Vector3.ZERO,Vector3.RIGHT,Vector3.LEFT,Vector3.BACK,Vector3.FORWARD,Vector3(1,0,1),Vector3(-1,0,1),Vector3(1,0,-1),Vector3(-1,0,-1)]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func packet(slope:float)->PackedByteArray:
	# Existing v2 cut-cell fixture layout, restored by the production migrator.
	var catalog:PackedByteArray=ClassDB.instantiate("NativeLakeCatalog").encode([])
	var bytes:=PackedByteArray();bytes.resize(32+catalog.size()+9076);bytes.fill(0)
	bytes.encode_u32(0,0x31575256);bytes.encode_u32(4,2);bytes.encode_u32(8,catalog.size());bytes.encode_u32(12,1);bytes.encode_u64(16,60000)
	for i in catalog.size():bytes[32+i]=catalog[i]
	var base:int=32+catalog.size();bytes.encode_u64(base,(10<<24)|(10<<12)|10);bytes.encode_u32(base+8,1);bytes.encode_u32(base+12,1)
	for i in 512:bytes.encode_u16(base+16+i*12,500);bytes.encode_u16(base+18+i*12,500)
	var index:=3+8*3+64*3;bytes.encode_u16(base+16+index*12,250);bytes.encode_u64(base+20+index*12,60000)
	for i in 729:
		var x:float=40+(i%9)*.5;var y:float=40+((i/9)%9)*.5
		bytes.encode_float(base+6160+i*4,y-(41.5+(x-41.5)*slope))
	return bytes
func scalar(from:Vector3,middle:Vector3,to:Vector3,radius:float,shift:float)->bool:
	var span:=from-to;span.y=0
	var segments:=maxi(1,ceili(span.length()/.1))
	for i in range(segments+1):
		var t:=float(i)/segments
		var point:=from.lerp(middle,t*2) if t<=.5 else middle.lerp(to,(t-.5)*2)
		for offset:Vector3 in OFFSETS:
			if water.depth_at(point+offset*radius+Vector3(0,shift,0))>0:return false
	return true
func box(at:Vector3,size:Vector3)->void:
	var body:=StaticBody3D.new();scene.add_child(body);body.position=at
	var collider:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=size;collider.shape=shape;body.add_child(collider)
func ready(_bounds:AABB)->bool:return true
func plan(batched:bool)->Dictionary:
	nav.clear();nav.set_water_depth(water.depth_at,water.dry_footprint if batched else Callable())
	nav.set_agent(1,Vector3(40,41.5,41.75),Vector3(64,41.5,41.75),0,true)
	var result:Dictionary={"batched":batched,"planning_us":0,"planning_peak_us":0,"thread_cycles":0,"slowest":{},"hazard_us":0.0,"water_queries":0,"water_batches":0,"work":0}
	for tick in 1800:
		await physics_frame
		var stats:Dictionary=nav.advance(.00001,ready,Callable())
		result.planning_us+=stats.planning_us;result.work+=stats.route_work
		result.thread_cycles+=stats.planning_thread_cycles
		if stats.planning_us>result.planning_peak_us:result.planning_peak_us=stats.planning_us;result.slowest=stats.duplicate(true)
		for key:String in ["hazard_us","water_queries","water_batches"]:result[key]+=stats.query_profile[key]
		if nav.state(1) in ["following","blocked","unavailable","search_limit"]:
			result.ticks=tick+1;break
	result.state=nav.state(1);result.points=nav.route_points(1);runs.append(result);return result
func _initialize()->void:run.call_deferred()
func run()->void:
	water=ClassDB.instantiate("NativeRegionalWater")
	var rng:=RandomNumberGenerator.new();rng.seed=92741
	var comparisons:=0;var wet:=0;var dry:=0;var parity:=true
	for slope in [0.0,.5,-.5]:
		check(water.restore_snapshot(packet(slope)),"native water fixture restores slope %s"%slope)
		for i in 500:
			var a:=Vector3(rng.randf_range(41,42.1),rng.randf_range(42.2,42.8),rng.randf_range(41,42.1))
			var b:=a+Vector3(rng.randf_range(-.7,.7),rng.randf_range(-.2,.2),rng.randf_range(-.7,.7))
			var middle:=(a+b)*.5;middle.y+=rng.randf_range(-.15,.15)
			var radius:float=.4 if i%2==0 else .8
			var expected:=scalar(a,middle,b,radius,-.83)
			parity=parity and water.dry_footprint(a,middle,b,radius,-.83)==expected
			comparisons+=1
			if expected:dry+=1
			else:wet+=1
	check(parity and wet>0 and dry>0,"1500 deterministic flat/sloped wet and dry footprints match point queries")
	check(not water.dry_footprint(Vector3(NAN,0,0),Vector3.ZERO,Vector3.ZERO,.4,-.83) and not water.dry_footprint(Vector3.ZERO,Vector3.ZERO,Vector3(3,0,0),.4,-.83) and not water.dry_footprint(Vector3.ZERO,Vector3.ZERO,Vector3.ZERO,-1,-.83),"malformed and oversized requests reject safely")
	water.restore_snapshot(packet(0))
	scene=Node3D.new();root.add_child(scene);box(Vector3(52,41,41.75),Vector3(70,1,40));box(Vector3(52,43.5,41.75),Vector3(.4,4,8))
	nav=ClassDB.instantiate("NativeActorNavigator");scene.add_child(nav);nav.configure(1);nav.set_query_profiling(true)
	await physics_frame;await physics_frame
	var point:=await plan(false);var batch:=await plan(true)
	check(point.state=="following" and batch.state=="following" and point.points==batch.points and point.work==batch.work,"native batch preserves complete regional path and search work around actual water and wall")
	check(point.water_queries>0 and point.water_batches==0 and batch.water_queries==0 and batch.water_batches>0,"batch removes point-call crossings without removing footprint checks")
	var batch_repeat:=await plan(true);var point_repeat:=await plan(false)
	check(batch_repeat.state=="following" and point_repeat.state=="following" and batch_repeat.points==point.points and point_repeat.points==point.points and batch_repeat.work==point.work and point_repeat.work==point.work,"ABBA repeats preserve the same complete path and work after independent graph clears")
	nav.set_water_depth(water.depth_at,water.dry_footprint)
	nav.clear();nav.set_agent(1,Vector3(41.3,41.5,41.75),Vector3(42.3,41.5,41.75),0,true);nav.advance(.00001,ready,Callable())
	check(not nav.guard_motion(1,Vector3.RIGHT,.05),"intact water blocks the live square movement footprint")
	check(water.remove_bounds(AABB(Vector3(40,40,40),Vector3(4,4,4)))>0 and nav.guard_motion(1,Vector3.RIGHT,.05),"water removal reaches the next motion guard without a navigation-cache reset")
	water.restore_snapshot(packet(0))
	check(not nav.guard_motion(1,Vector3.RIGHT,.05),"restored water blocks the next guard without stale dry reuse")
	nav.clear();nav.set_agent(1,Vector3(40,41.5,40),Vector3(40.5,41.5,40),0,true)
	var observed:Dictionary=nav.advance(.00001,ready,func(_p:Vector3):return true)
	check(observed.query_profile.water_batches==0 and observed.query_profile.water_queries>0 and observed.query_profile.admission_queries>0,"custom admission preserves interleaved point-provider behavior")
	nav.set_water_depth(water.depth_at,func(_a:Vector3,_m:Vector3,_b:Vector3,_r:float,_s:float):return 1)
	nav.advance(.00001,ready,Callable())
	check(not nav.guard_motion(1,Vector3.RIGHT,.05),"invalid batch-provider return rejects rather than authorizing movement")
	nav.set_water_depth(water.depth_at)
	check(nav.guard_motion(1,Vector3.RIGHT,.05),"legacy point-only provider remains supported")
	var folder:="res://reports/navigation_water_footprint";DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"comparisons":comparisons,"wet":wet,"dry":dry,"runs":runs},"  "))
	scene.free();await process_frame;print("NAVIGATION_WATER_FOOTPRINT checks=",checks," failures=",failures);quit(1 if failures else 0)
