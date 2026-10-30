# SPDX-License-Identifier: 0BSD
extends SceneTree
const ASSET:="test/model_horizon"
var checks:=0
var failures:=0
var output:="res://reports/model_horizon"
func _initialize()->void:
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func pose(point:Vector3)->PackedFloat32Array:
	return PackedFloat32Array([1,0,0,point.x,0,1,0,point.y,0,0,1,point.z])
func drain(horizon:Node,record_budget:int=1024,upload_budget:int=3)->bool:
	var deadline:=Time.get_ticks_msec()+30000
	while Time.get_ticks_msec()<deadline:
		horizon.advance(record_budget,upload_budget,10000)
		var state:Dictionary=horizon.statistics()
		if not state.error.is_empty():print("HORIZON_ERROR ",state);return false
		if state.ready:return true
		await process_frame
	return false
func run()->void:
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--view-output="):output=argument.trim_prefix("--view-output=")
	DirAccess.make_dir_recursive_absolute(output)
	GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
	var batch:Node3D=ClassDB.instantiate("NativeStaticBatch");root.add_child(batch)
	var mesh:=BoxMesh.new();mesh.size=Vector3(.4,.6,.8)
	check(batch.configure_asset(ASSET,mesh) and batch.configure_render_streaming(true,16,128,1048576,2,49152),"ordinary model source configures bounded local rendering")
	var ids:=PackedInt64Array();var values:=PackedFloat32Array()
	for index in 600:
		ids.append(index+1);values.append_array(pose(Vector3((index%20)*.8,1,(index/20)*.8)))
	ids.append(10001);values.append_array(pose(Vector3(2050,2,-8)))
	check(batch.upsert_instances(ids,values),"fixture includes dense near region and never-near distant prop")
	var original:PackedByteArray=batch.capture_snapshot()
	var near_packet:PackedByteArray=batch.capture_region(Vector3i.ZERO)
	var far_packet:PackedByteArray=batch.capture_region(Vector3i(64,0,-1))
	var blocks:Node3D=ClassDB.instantiate("NativeBlockWorld")
	var codec:RefCounted=ClassDB.instantiate("NativeStructuresSnapshot");codec.configure_assets(PackedStringArray([ASSET]))
	var raw:RefCounted=ClassDB.instantiate("NativeWorldArchive")
	var archive:RefCounted=ClassDB.instantiate("NativeRegionWorldArchive");archive.configure(raw,codec,true)
	var path:=ProjectSettings.globalize_path(output.path_join("fixture_%d.trw"%OS.get_process_id()))
	check(archive.acquire(path) and archive.publish(path,archive.encode({"terrain":PackedByteArray([1]),"structures":codec.encode(blocks.capture_snapshot(),{ASSET:original})}))==OK and archive.start_region_reads(8,64*1024*1024),"isolated archived fixture starts existing shared reader")
	var pin:PackedByteArray=archive.published_model_index(ASSET).checkpoint
	var horizon:Node=ClassDB.instantiate("NativeModelHorizon");root.add_child(horizon)
	check(not horizon.configure(archive,[batch,batch],{ASSET:pin}),"duplicate collection rejects without claiming renderer")
	check(horizon.configure(archive,[batch],{ASSET:pin}),"persistent visual owner replaces distance-limited representation")
	horizon.set_process(false)
	check(not batch.unload_region(near_packet),"retirement cannot erase the only unseeded transform source")
	horizon.advance(3,1,10000)
	check(horizon.statistics().last_records<=3 and horizon.statistics().last_uploads<=1 and not horizon.statistics().ready,"initial publication respects record and upload budgets")
	check(await drain(horizon) and horizon.represented_ids(batch)==ids,"all canonical models acquire visible ownership without a distance cutoff")
	check(batch.render_stats().resident_batches==0 and horizon.statistics().pages==4,"no duplicate near renderer or per-instance scene nodes remain")
	var first:MultiMeshInstance3D=batch.get_child(0)
	check(first.multimesh.mesh==mesh and first.multimesh.instance_count<=256,"draw pages share the exact source mesh in bounded batches")
	if DisplayServer.get_name()!="headless":check(first.multimesh.get_instance_transform(0).origin.is_equal_approx(Vector3.ZERO+Vector3(0,1,0)),"native GPU buffer retains first canonical transform")
	var before:Dictionary=horizon.statistics()
	for iteration in 12:horizon.advance()
	check(horizon.statistics().uploaded_bytes==before.uploaded_bytes and horizon.statistics().last_records==0,"idle scene does not rescan model records or upload transforms")
	batch.set_render_focus(Vector3(100000,10,100000))
	for frame in 4:await process_frame
	horizon.advance()
	check(horizon.represented_ids(batch)==ids and batch.render_stats().resident_batches==0,"arbitrarily distant player focus does not evict world visuals")
	check(batch.unload_region(far_packet) and batch.unload_region(near_packet),"canonical model regions retire while persistent visual pages remain")
	before=horizon.statistics();horizon.advance()
	check(batch.stats().instances==0 and horizon.represented_ids(batch)==ids and horizon.statistics().uploaded_bytes==before.uploaded_bytes,"cold retirement has no visual rebuild or gameplay hydration")
	check(batch.restore_region(near_packet),"near canonical region rehydrates independently of visuals")
	horizon.advance()
	check(horizon.represented_ids(batch)==ids and horizon.statistics().uploaded_bytes==before.uploaded_bytes,"near readmission does not duplicate or republish visual ownership")
	var history:RefCounted=ClassDB.instantiate("NativeStaticHistory");history.configure([batch],65536,32)
	check(history.erase(batch,2),"authoritative prop removal enters ordinary history")
	horizon.advance(8,1,10000)
	var remaining:=ids.duplicate();remaining.remove_at(1)
	check(horizon.represented_ids(batch)==remaining,"removing one prop never hides its unchanged page neighbors")
	check(history.undo() and await drain(horizon) and horizon.represented_ids(batch)==ids,"undo restores one identity without duplicate far instances")
	var moved:=pose(Vector3(-2048,5,512))
	check(batch.upsert_instances(PackedInt64Array([1]),moved),"canonical prop can move across distant owner regions")
	horizon.advance(8,1,10000)
	check(horizon.represented_ids(batch)==ids and horizon.statistics().last_uploads==1,"cross-region move updates its stable visual page without a two-page handoff")
	check(batch.remove_instances(PackedInt64Array([1])) and batch.upsert_instances(PackedInt64Array([1]),pose(Vector3(3,2,3))) and await drain(horizon) and horizon.represented_ids(batch)==ids,"remove and reinsert before publication keeps one GPU identity")
	check(batch.restore_region(far_packet),"far canonical source can be restored for checkpoint parity")
	check(batch.restore_snapshot(original),"whole-collection snapshot reset succeeds")
	check(await drain(horizon) and horizon.represented_ids(batch)==ids,"snapshot generation reset discards stale visuals and reconstructs exact IDs")
	check(batch.capture_snapshot()==original,"visual ownership never changes canonical snapshot bytes")
	var door:RefCounted=ClassDB.instantiate("NativeHingedDoors")
	check(door.configure(mesh.get_aabb(),Vector3.ZERO,90) and door.toggle(batch,1,AABB()).get("ok",false) and await drain(horizon),"native door interaction updates the shared visual owner")
	var door_visual:Dictionary=horizon.visual_record(batch,1)
	check(not door_visual.transform.basis.is_equal_approx(Basis.IDENTITY),"opened door has the authored rotation in its persistent page")
	check(door.toggle(batch,1,AABB()).get("ok",false) and await drain(horizon) and batch.capture_snapshot()==original,"closing door restores exact legacy placement without duplicate nodes")
	var prefab:Resource=ClassDB.instantiate("NativeBlockPrefab")
	var placement:RefCounted=ClassDB.instantiate("NativePrefabPlacement")
	check(prefab.configure(PackedInt32Array([0,0,0,1,0,2,0,1])) and prefab.configure_model_attachments([{"model":ASSET,"transform":Transform3D(Basis.IDENTITY,Vector3(.5,1.5,.5))}]),"isolated block prefab includes one canonical model attachment")
	var placed:Dictionary=placement.place(blocks,prefab,Vector3i(100,10,100),0,{ASSET:batch},[])
	check(placed.get("ok",false) and await drain(horizon) and horizon.represented_ids(batch).size()==602,"direct native prefab commit publishes its attached model: "+str(placed))
	check(batch.restore_snapshot(original) and await drain(horizon) and horizon.represented_ids(batch)==ids,"prefab rollback fixture leaves original visual identities")
	horizon.clear()
	check(batch.unload_region(near_packet) and batch.unload_region(far_packet),"metadata-only fresh bootstrap retires both source regions")
	check(horizon.configure(archive,[batch],{ASSET:pin}),"fresh renderer binds immutable unloaded model checkpoint")
	horizon.set_process(false);check(await drain(horizon) and horizon.represented_ids(batch)==ids,"never-near archive reads reconstruct all exact world visuals")
	check(batch.stats().instances==0 and batch.collision_stats().resident_bodies==0 and horizon.statistics().reads==2,"archived visual bootstrap does not load editable instances or physics")
	check(archive.region_read_stats().outstanding==0 and archive.region_read_stats().retained_checkpoint_keys==0,"completed bootstrap releases archive requests and checkpoint leases")
	var archived_stats:Dictionary=horizon.statistics()
	var transformed:=Transform3D(Basis.from_euler(Vector3(.1,.3,.2)).scaled(Vector3(1.2,.8,1.4)),Vector3(100,20,-200))
	batch.transform=transformed
	check(batch.get_child(0).get_parent()==batch and batch.get_child(0).global_transform.is_equal_approx(transformed*batch.get_child(0).transform),"collection transforms apply once through native page parenting")
	horizon.clear();batch.transform=Transform3D.IDENTITY
	check(horizon.configure(archive,[batch],{ASSET:pin}),"in-flight mutation fixture binds archived source")
	horizon.set_process(false);horizon.advance(1,1,10000)
	check(batch.restore_region(near_packet) and batch.remove_instances(PackedInt64Array([2])) and batch.upsert_instances(PackedInt64Array([3]),pose(Vector3(3,9,3))),"canonical admission and edits can overlap archived visual reads")
	check(await drain(horizon) and horizon.represented_ids(batch)==remaining and is_equal_approx(float(horizon.visual_record(batch,3).transform.origin.y),9.0),"older archive payload cannot resurrect removal or overwrite a newer pose")
	horizon.clear()
	check(batch.restore_snapshot(original) and batch.unload_region(near_packet) and batch.unload_region(far_packet) and horizon.configure(archive,[batch],{ASSET:pin}),"cancellation fixture queues fresh archived seeds")
	horizon.set_process(false);horizon.advance(1,1,10000);horizon.clear()
	for frame in 8:await process_frame
	check(archive.region_read_stats().outstanding==0 and archive.region_read_stats().retained_checkpoint_keys==0,"clearing pending bootstrap discards native requests and checkpoint pins")
	check(batch.restore_snapshot(original) and batch.clear_instances(),"dense pressure starts from clean canonical source")
	ids.resize(100000);values.resize(1200000)
	for index in 100000:
		ids[index]=index+1
		var value:=pose(Vector3((index%100)*.25,1+(index/10000)*.25,((index/100)%100)*.25))
		for component in 12:values[index*12+component]=value[component]
	check(batch.upsert_instances(ids,values) and horizon.configure(archive,[batch],{}),"100000 model instances configure without a global gameplay expansion")
	horizon.set_process(false)
	check(await drain(horizon,2048,8) and horizon.represented_ids(batch)==ids,"dense fixture reaches complete representation within bounded publications")
	var dense:Dictionary=horizon.statistics()
	check(dense.pages==391 and dense.gpu_transform_bytes==4800000 and dense.charged_bytes<64*1024*1024,"100000 props use 391 pages and 4.8 MB of transform buffers")
	var deleted:=PackedInt64Array([1,257,513,99999])
	check(batch.remove_instances(deleted),"multi-page deletion is accepted")
	horizon.advance(4,1,10000)
	check(horizon.statistics().rendered==99996 and horizon.statistics().last_uploads<=1,"bounded deletion removes exact GPU identities before deferred page compaction")
	var actual:PackedInt64Array=horizon.represented_ids(batch);var expected:=PackedInt64Array()
	for identity:int in ids:
		if not deleted.has(identity):expected.append(identity)
	check(actual==expected and await drain(horizon),"all 99996 unchanged dense records remain visible through single-upload budget")
	horizon.clear()
	check(horizon.configure(archive,[batch],{},16*1024*1024),"small explicit visual budget configures")
	horizon.set_process(false)
	for tick in 1000:
		horizon.advance(4096,32,10000)
		if not horizon.statistics().error.is_empty():break
	check(not horizon.statistics().ready and not horizon.statistics().error.is_empty() and horizon.statistics().charged_bytes<=16*1024*1024,"insufficient visual budget is explicit rather than silently pretending full coverage")
	var trim:=PackedInt64Array()
	for index in 99000:
		if not deleted.has(index+1001):trim.append(index+1001)
	check(batch.remove_instances(trim),"authoritative removals remain accepted under visual capacity pressure")
	var deadline:=Time.get_ticks_msec()+30000
	while not horizon.statistics().ready and Time.get_ticks_msec()<deadline:
		horizon.advance(4096,32,10000)
		await process_frame
	check(horizon.statistics().ready and horizon.represented_ids(batch)==batch.get_ids(),"capacity pressure recovers after removals without a world reload or missing identities")
	batch.free();horizon.advance()
	check(horizon.statistics().collections==0 and horizon.statistics().rendered==0 and horizon.statistics().gpu_transform_bytes==0,"destroying a source before the visual owner releases all of its draw pages")
	horizon.clear();horizon.free();blocks.free();archive.join_region_reads();archive.release()
	var counter:RefCounted=ClassDB.instantiate("NativeModelRenderPage")
	check(counter.live_pages()==0,"renderer teardown releases all native archived pages")
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"archived":archived_stats,"dense":dense},"  "))
	print("MODEL_HORIZON checks=",checks," failures=",failures)
	quit(1 if failures else 0)
