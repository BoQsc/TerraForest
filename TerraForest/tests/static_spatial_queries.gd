extends SceneTree
var checks:=0
var failures:=0
var output:="res://reports/static_spatial_queries"
var results:Array=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize()->void:run.call_deferred()
func pose(point:Vector3)->PackedFloat32Array:
	return PackedFloat32Array([1,0,0,point.x,0,1,0,point.y,0,0,1,point.z])
func fixture(count:int,layout:int)->void:
	var batch:Node3D=ClassDB.instantiate("NativeStaticBatch")
	var shape:=AABB(Vector3.ONE*-.5,Vector3.ONE)
	if layout==2:shape=AABB(Vector3(-2048,-.5,-.5),Vector3(4096,1,1))
	check(batch.configure_collision_only() and batch.configure_asset("test/spatial",BoxMesh.new()) and batch.configure_collision(shape,8,4,1),"loaded spatial fixture configures")
	var ids:=PackedInt64Array();var values:=PackedFloat32Array();var points:=PackedVector3Array()
	for index in count:
		var point:=Vector3((index-2048)*32+1,1,1)
		if layout==1:point=Vector3(int(index/256)-8,int(index/16)%16-8,index%16-8)*32+Vector3.ONE
		if layout==3:point=Vector3(index%10,int(index/10)%10,int(index/100))*3+Vector3.ONE
		ids.append(index+1);points.append(point);values.append_array(pose(point))
	check(batch.upsert_instances(ids,values),"loaded regions publish exact transforms")
	var spatial:Dictionary=batch.region_stats()
	check(spatial.collision_bounds_nodes==(1 if layout==3 else count) and spatial.collision_bounds_height<=24,"loaded index is exact and balanced")
	var snapshot:PackedByteArray=batch.capture_snapshot()
	var queries:Array[Transform3D]=[];var wanted:=PackedByteArray()
	for index in 64:
		queries.append(Transform3D(Basis.IDENTITY,points[(index*67)%count]));wanted.append(1)
	queries.append(Transform3D(Basis.IDENTITY,Vector3.ONE*1000000));wanted.append(0)
	var bounds:=AABB(Vector3.ONE*-.25,Vector3.ONE*.5)
	var began:=Time.get_ticks_usec();var valid:=true
	for iteration in 1024:
		valid=not batch.is_collision_region_ready(AABB(points[(iteration*67)%count]-.25*Vector3.ONE,Vector3.ONE*.5)) and valid
		valid=batch.is_collision_region_ready(AABB(Vector3.ONE*1000000,Vector3.ONE)) and valid
	var readiness_us:=Time.get_ticks_usec()-began
	check(valid,"loaded collision readiness distinguishes missing bodies from empty space")
	began=Time.get_ticks_usec();valid=true
	for iteration in 128:valid=batch.overlap_mask(queries,bounds)==wanted and valid
	var exclusion_us:=Time.get_ticks_usec()-began
	check(valid,"loaded exclusion remains exact for widely separated candidates")
	results.append({"regions":count,"layout":layout,"readiness_queries":2048,"readiness_us":readiness_us,"exclusion_batches":128,"candidates_per_batch":65,"exclusion_us":exclusion_us})
	results[-1]["index_node_bytes"]=spatial.collision_bounds_node_bytes
	var frame:=Transform3D(Basis(Vector3.UP,PI*.5).scaled(Vector3(2,1.5,.75)),Vector3(-300,12,40))
	batch.transform=frame
	var transformed:Array[Transform3D]=[]
	for query:Transform3D in queries:transformed.append(frame*query)
	check(batch.overlap_mask(transformed,bounds)==wanted,"loaded exclusion respects rotated and scaled collection frame")
	batch.transform=Transform3D.IDENTITY
	if layout==0:
		var moved:=Vector3(-900000,-70,400)
		check(batch.upsert_instances(PackedInt64Array([1]),pose(moved)),"moving between regions updates bounds")
		var moving_queries:Array[Transform3D]=[Transform3D(Basis.IDENTITY,points[0]),Transform3D(Basis.IDENTITY,moved)]
		check(batch.overlap_mask(moving_queries,bounds)==PackedByteArray([0,1]),"old region is no longer occupied and new region is")
		check(batch.remove_instances(PackedInt64Array([1])) and batch.overlap_mask(moving_queries,bounds)==PackedByteArray([0,0]),"removal erases spatial membership")
		check(batch.restore_snapshot(snapshot) and batch.overlap_mask(queries,bounds)==wanted,"snapshot replacement restores all spatial membership")
		check(batch.region_stats().collision_bounds_nodes==count,"snapshot rebuild leaves no stale spatial nodes")
		var key:=Vector3i(floori(points[0].x/32),0,0)
		var packet:PackedByteArray=batch.capture_region(key)
		check(batch.unload_region(packet) and not batch.is_collision_region_ready(AABB(points[0],Vector3.ONE*.1)),"unloaded region stays conservatively unavailable")
		check(batch.region_stats().collision_bounds_nodes==count-1,"unload removes the loaded spatial node")
		check(batch.restore_region(packet) and batch.capture_snapshot()==snapshot,"re-admission preserves exact authoritative bytes")
		batch.free();batch=ClassDB.instantiate("NativeStaticBatch")
		check(batch.configure_asset("test/spatial",BoxMesh.new()) and batch.configure_render_streaming(true,16,4,65536,1,4096) and batch.restore_snapshot(snapshot),"decorative streamed collection restores for bounded retirement")
		check(batch.begin_transient_clear(),"incremental clear starts")
		check(batch.overlap_mask(queries,bounds).count(1)==0 and batch.is_collision_region_ready(AABB(points[0],Vector3.ONE)),"retired collection immediately leaves live spatial queries")
		check(batch.region_stats().collision_bounds_nodes==0,"retired spatial tree is no longer live")
		var progress:Dictionary=batch.advance_transient_clear(1,10000)
		while progress.ok and not progress.complete:progress=batch.advance_transient_clear(64,10000)
		check(progress.ok and progress.complete,"incremental clear finishes without stale index ownership")
		check(batch.restore_snapshot(snapshot) and batch.clear_instances() and batch.overlap_mask(queries,bounds).count(1)==0,"synchronous reset clears spatial queries")
	batch.free()
func run()->void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--profile-dir="):output=argument.trim_prefix("--profile-dir=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	fixture(64,0);fixture(4096,0);fixture(4096,1);fixture(4096,2);fixture(1000,3)
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"cases":results},"  "))
	print("STATIC_SPATIAL_QUERIES checks=",checks," failures=",failures)
	quit(1 if failures else 0)
