extends SceneTree

var failures:=0
var checks:Array[Dictionary]=[]

func check(ok:bool,label:String)->void:
	checks.append({"pass":ok,"name":label})
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)

func visible_count(batch:Node)->int:
	var count:=0
	for child:Node in batch.get_children():
		if child is MultiMeshInstance3D and child.visible:count+=child.multimesh.instance_count
	return count

func drain(batch:Node,expected:int)->bool:
	for frame_index in 180:
		await process_frame
		var stats:Dictionary=batch.render_stats()
		if stats.retained_render_bytes>stats.byte_limit or stats.retired_batches+stats.resident_batches>stats.batch_limit:return false
		if stats.retired_batches==0 and stats.resident_instances==expected and stats.pending_batches==0:return true
	return false

func _initialize()->void:run.call_deferred()

func run()->void:
	GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	var batch=ClassDB.instantiate("NativeStaticBatch");root.add_child(batch)
	check(batch.configure_asset("retirement/vegetation",BoxMesh.new()) and batch.configure_appearance_fade() and batch.configure_render_streaming(true,512,64,64*8192,8,8192),"bounded production-size vegetation pages")
	var identities:=PackedInt64Array();var poses:Array[Transform3D]=[]
	for index in 8192:
		identities.append(index+1)
		poses.append(Transform3D(Basis.IDENTITY,Vector3((index/128)*4,index%128/128.0,1)))
	check(batch.upsert_transforms(identities,poses) and await drain(batch,8192),"all synthetic vegetation pages resident")
	var original:PackedByteArray=batch.capture_snapshot()
	var before:Dictionary=batch.render_stats()
	check(batch.remove_instances(identities),"bulk removal accepted")
	var removed:Dictionary=batch.render_stats()
	check(batch.get_ids().is_empty() and visible_count(batch)==0,"all removed identities disappear immediately before cleanup")
	check(removed.retired_batches==before.resident_batches and removed.retained_render_bytes==before.retained_render_bytes,"hidden GPU pages remain fully accounted until actual release")
	check(removed.resident_instances==0 and removed.appearance_records==0,"removed picking/render slots and fade records do not survive")
	check(await drain(batch,0),"bounded native frame cleanup drains all hidden pages")
	check(batch.render_stats().retained_render_bytes==0 and batch.get_child_count()<=16,"cleanup retains only the bounded empty reusable page pool")
	check(batch.restore_snapshot(original) and await drain(batch,8192),"page reuse restores exact authoritative instances")
	check(batch.capture_snapshot()==original and visible_count(batch)==8192,"reused nodes become visible without old instances")
	batch.set_render_focus(Vector3(2000,0,0))
	await process_frame;await process_frame
	check(visible_count(batch)==0,"travel hides departed pages without waiting for resource cleanup")
	batch.set_render_focus(Vector3.ZERO)
	check(await drain(batch,8192) and visible_count(batch)==8192,"rapid travel return recovers all pages within combined memory budget")
	check(batch.remove_instances(identities),"second mass removal accepted")
	check(batch.begin_transient_clear(),"reset admitted with only hidden retirement remaining")
	var reset:Dictionary={}
	for iteration in 200:
		reset=batch.advance_transient_clear(64,100)
		if reset.complete:break
	check(reset.get("ok",false) and reset.get("complete",false) and batch.render_stats().retained_render_bytes==0,"incremental reset also drains pending hidden render ownership")
	check(batch.restore_snapshot(original) and await drain(batch,8192),"collection restored for strict reconfiguration")
	check(batch.remove_instances(identities) and batch.configure_render_streaming(true,512,1,8192,1,8192),"lowering budgets synchronously drains obsolete ownership")
	check(batch.render_stats().retained_render_bytes==0,"configuration cannot leave hidden buffers above a reduced cap")
	check(batch.clear_instances() and batch.get_child_count()==0,"explicit clear releases retirement and pooled nodes")
	batch.free();await process_frame
	var folder:=ProjectSettings.globalize_path("res://reports")
	DirAccess.make_dir_recursive_absolute(folder)
	FileAccess.open(folder.path_join("vegetation_page_retirement.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"scope":"GPU page visibility, byte ownership, deferred cleanup, rapid return and reset. Not a frame-pacing measurement."},"  "))
	print("VEGETATION_PAGE_RETIREMENT failures=",failures);quit(1 if failures else 0)
