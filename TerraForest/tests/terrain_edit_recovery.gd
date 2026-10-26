extends SceneTree
const Terrain=preload("res://addons/volumetric_terrain/terrain_world.gd")
const Backend=preload("res://addons/volumetric_terrain/terrain_backend.gd")
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var failures:=0
var terrain:Node
var support_applied:=0
var support_snapshot:Dictionary={}
func capture_support(_bounds:AABB)->Array:
	return [{"ids":PackedInt64Array([1]),"points":PackedVector3Array([Vector3(128,65.92,128),Vector3(128,66.08,128)])}]
func apply_support(snapshot:Dictionary,result:Dictionary)->bool:
	support_applied+=1;support_snapshot=result
	return snapshot.ids==PackedInt64Array([1]) and result.before.density.size()==2 and result.after.density.size()==2
class QueueGate extends Backend:
	var reject_edit:=false
	func submit(job:Dictionary,priority:bool=false)->bool:
		if reject_edit and job.get("kind")=="edit":return false
		return super.submit(job,priority)
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func settled()->bool:
	var deadline:=Time.get_ticks_msec()+5000
	while terrain.pending_edit and Time.get_ticks_msec()<deadline:await process_frame
	return not terrain.pending_edit
func run()->void:
	terrain=Terrain.new();terrain.diagnostics_pause_streaming=true;terrain.backend=QueueGate.new()
	terrain.save_slot="recovery_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]
	terrain.backend.world_generator=5;terrain.backend.disk_cache.enabled=false
	root.add_child(terrain)
	check(terrain.start(StandardMaterial3D.new(),true)==OK,"isolated terrain starts")
	var deadline:=Time.get_ticks_msec()+5000
	while not terrain.world_ready and Time.get_ticks_msec()<deadline:await process_frame
	var center:=Vector3(128,64,128)
	check(terrain.sculpt_sphere(center,2,true) and await settled(),"initial edit publishes")
	terrain.register_edit_support(capture_support,apply_support)
	var stamps:Dictionary=terrain.stamps.duplicate()
	terrain.backend.reject_edit=true
	check(not terrain.sculpt_sphere(center,1,false) and not terrain.pending_edit,"bounded queue rejects without leaving an edit pending")
	check(terrain.world_ready and terrain.latest_error.is_empty() and terrain.stamps==stamps,"queue backpressure restores stamps without disabling terrain")
	terrain.backend.reject_edit=false
	var revision:int=terrain.density_revision
	var before:PackedByteArray=terrain.backend.native.execute(Codec.command(4,[3]))
	var outside:=Vector3(-100,64,-100)
	check(terrain.sculpt_sphere(outside,2,true) and await settled(),"out-of-world brush receives a worker outcome")
	check(terrain.last_edit_outcome.status=="rejected" and terrain.density_revision==revision,"rejected stroke does not mutate density")
	check(terrain.world_ready and terrain.latest_error.is_empty() and terrain.backend.write_allowed,"safe rejection keeps editing and saving available")
	check(terrain.backend.native.execute(Codec.command(4,[3]))==before,"rejection preserves every saved density byte")
	check(support_applied==0,"queue rejection and invalid edit never publish vegetation mutations")
	check(terrain.sculpt_sphere(center,1,false) and await settled() and terrain.density_revision>revision,"valid edit works immediately after rejection")
	check(support_applied==1 and support_snapshot.before.density.size()==2,"same-edit before/after support samples publish with successful terrain")
	check(terrain.sculpt_sphere(center,1,false) and await settled() and support_applied==1,"unchanged stroke cannot mutate vegetation state")
	if terrain.world_ready:
		var curved:=Codec.curved_road_bed(Vector3(100,64,100),Vector3(116,64,100),4,4,8,PackedFloat64Array([0,0,0,66]),0)
		check(terrain.edit(curved,Vector3.ZERO,Vector3.ONE) and await settled(),"inconsistent road profile is resolved by native validation")
		check(terrain.last_edit_outcome.status=="rejected" and terrain.world_ready and terrain.backend.write_allowed,"invalid road profile cannot disable unrelated terrain tools")
		check(terrain.sculpt_sphere(center,0.5,true) and await settled(),"minimum supported brush remains usable")
	terrain.shutdown();terrain.free()
	await process_frame
	var backend:=Backend.new();backend.world_generator=5;backend.disk_cache.enabled=false
	check(backend.start(true)==OK,"partial-batch safety backend starts")
	var started:=false;deadline=Time.get_ticks_msec()+5000
	while not started and Time.get_ticks_msec()<deadline:
		for result:Dictionary in backend.poll():
			if result.kind=="startup":started=true
		await process_frame
	var good:=Codec.brush(center,center,2,0,true,1)
	var bad:=Codec.brush(outside,outside,2,0,true,1)
	check(backend.submit({"kind":"edit","command":good,"commands":[good,bad],"tiles":[],"epoch":0,"ticket":1}),"mixed batch enters real worker")
	var outcome:Dictionary={};deadline=Time.get_ticks_msec()+5000
	while outcome.is_empty() and Time.get_ticks_msec()<deadline:
		for result:Dictionary in backend.poll():
			if result.kind=="edit":outcome=result
		await process_frame
	check(not outcome.is_empty() and not outcome.get("recoverable",false) and not backend.write_allowed,"partially applied batch still fails closed and protects saves")
	backend.stop();backend=null
	print("TERRAIN_EDIT_RECOVERY failures=",failures);quit(1 if failures else 0)
