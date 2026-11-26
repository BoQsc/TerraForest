# SPDX-License-Identifier: 0BSD
extends SceneTree

const ASSET:="test/exclusion_arch"
const BOUNDS:=AABB(Vector3.ONE*-0.1,Vector3.ONE*0.2)
var checks:=0
var failures:=0
var queries:RefCounted
var blocks:Node3D
var models:Node3D
var archive:RefCounted
var candidates:Array[Transform3D]=[]
var output:="res://reports/structure_exclusion_paging"
var maximum_query_us:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func pose(point:Vector3)->PackedFloat32Array:
	return PackedFloat32Array([1,0,0,point.x,0,1,0,point.y,0,0,1,point.z])
func mask()->PackedByteArray:
	var began:=Time.get_ticks_usec()
	var result:PackedByteArray=queries.overlap_mask(blocks,[models],candidates,BOUNDS)
	maximum_query_us=maxi(maximum_query_us,Time.get_ticks_usec()-began)
	return result
func resolve()->PackedByteArray:
	var deadline:=Time.get_ticks_msec()+10000
	var result:=mask()
	while result.size()!=candidates.size() and Time.get_ticks_msec()<deadline:
		await process_frame
		result=mask()
	return result
func shared_queries()->void:
	var owner:Node3D=ClassDB.instantiate("NativeBlockWorld")
	owner.set_cells(PackedInt32Array([0,0,0,1]))
	var service:RefCounted=ClassDB.instantiate("NativeStructureQueries")
	var collections:Array=[]
	for collection in 4:
		var batch:Node3D=ClassDB.instantiate("NativeStaticBatch")
		batch.configure_collision_only();batch.configure_asset("test/shared_%d"%collection,BoxMesh.new())
		var parts:Array[AABB]=[AABB(Vector3(-2,0,-.5),Vector3(1,4,1)),AABB(Vector3(1,0,-.5),Vector3(1,4,1))]
		batch.configure_compound_collision(parts,8,8,2,64,32)
		var ids:=PackedInt64Array();var poses:=PackedFloat32Array()
		for index in 128:
			ids.append(index+1);poses.append_array(pose(Vector3(index*64,0,4+collection*8)))
		batch.upsert_instances(ids,poses);collections.append(batch)
	var probes:Array[Transform3D]=[]
	for z in range(0,33):
		for x in [-1.5,0.,1.5]:probes.append(Transform3D(Basis.IDENTITY,Vector3(x,.5,z)))
	for variant in 3:
		if variant==1:
			collections[1].transform=Transform3D(Basis(Vector3.UP,.4).scaled(Vector3(1.2,.9,.8)),Vector3(1,0,2))
		elif variant==2:
			collections[0].remove_instances(PackedInt64Array([1]))
			collections[2].upsert_instances(PackedInt64Array([1]),pose(Vector3(1,0,30)))
		var expected:PackedByteArray=owner.overlap_mask(probes,BOUNDS)
		for batch:Node3D in collections:
			var individual:PackedByteArray=batch.overlap_mask(probes,BOUNDS)
			for index in expected.size():expected[index]|=individual[index]
		check(service.overlap_mask(owner,collections,probes,BOUNDS)==expected,"shared query matches individual masks across frame/edit variant %d"%variant)
		var stats:Dictionary=service.exclusion_stats()
		if variant==0:
			check(stats.query_transforms==probes.size() and stats.query_frame_reuses>=collections.size(),"same-frame collections transform each candidate only once")
			check(stats.query_model_nodes<64,"spatial traversal prunes distant placement groups")
			check(expected[12]==1 and expected[13]==0 and expected[14]==1,"compound arch opening is preserved")
		else:check(stats.query_transforms==probes.size()*3,"different frames recompute only the necessary local boxes")
		if variant==2:check(expected[12]==0 and expected[91]==1,"removed and moved placements update indexed exclusion immediately")
	var invalid:Array[Transform3D]=[Transform3D(Basis.from_scale(Vector3.ZERO),Vector3.ZERO)]
	check(service.overlap_mask(owner,collections,invalid,BOUNDS).is_empty(),"invalid candidate rejects the entire shared packet")
	collections[0].scale=Vector3.ZERO
	check(service.overlap_mask(owner,collections,probes,BOUNDS).is_empty(),"invalid collection frame cannot reuse a valid packet")
	for batch:Node3D in collections:batch.free()
	owner.free()
func run()->void:
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--profile-dir="):output=argument.trim_prefix("--profile-dir=")
		if argument.begins_with("--check-evidence-dir="):output=argument.trim_prefix("--check-evidence-dir=")
	DirAccess.make_dir_recursive_absolute(output)
	GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
	shared_queries()
	blocks=ClassDB.instantiate("NativeBlockWorld")
	models=ClassDB.instantiate("NativeStaticBatch")
	queries=ClassDB.instantiate("NativeStructureQueries")
	check(blocks.set_cells(PackedInt32Array([-1,3,0,1,0,3,0,2,63,3,0,1,64,3,0,1,2,3,2,1])),"block fixture spans negative and positive 64m owners")
	check(models.configure_collision_only() and models.configure_asset(ASSET,BoxMesh.new()),"non-rendering model fixture configures")
	var parts:Array[AABB]=[AABB(Vector3(-2,0,-0.5),Vector3(1,4,1)),AABB(Vector3(1,0,-0.5),Vector3(1,4,1))]
	check(models.configure_compound_collision(parts,8,8,2,64,32),"compound model retains open arch")
	var poses:=pose(Vector3(4,3,4));poses.append_array(pose(Vector3(24,3,4)))
	check(models.upsert_instances(PackedInt64Array([1,2]),poses),"same-region models leave inter-instance gaps")
	for depth in range(-1,7):
		for across in range(-2,68):candidates.append(Transform3D(Basis.IDENTITY,Vector3(across+0.5,3.5,depth+0.5)))
	candidates.append(Transform3D(Basis.IDENTITY,Vector3(4,4,4)))
	var expected:=mask()
	check(expected.size()==candidates.size() and expected[-1]==0 and expected.count(1)>0,"resident reference includes solid cells and open compound gaps")
	var codec:RefCounted=ClassDB.instantiate("NativeStructuresSnapshot");codec.configure_assets(PackedStringArray([ASSET]))
	var raw:RefCounted=ClassDB.instantiate("NativeWorldArchive")
	archive=ClassDB.instantiate("NativeRegionWorldArchive");archive.configure(raw,codec,true)
	var path:=ProjectSettings.globalize_path(output.path_join("fixture_%d.trw"%OS.get_process_id()))
	var original_blocks:PackedByteArray=blocks.capture_snapshot()
	var original_models:PackedByteArray=models.capture_snapshot()
	check(archive.acquire(path) and archive.publish(path,archive.encode({"terrain":PackedByteArray([1]),"structures":codec.encode(original_blocks,{ASSET:original_models})}))==OK,"fixture publishes isolated immutable source")
	check(archive.start_region_reads(8,64*1024*1024),"single bounded archive read worker starts")
	var reference:Dictionary=codec.decode_reference(raw.decode(archive.read(path)).sections.structures)
	queries.configure_archive(archive,reference.checkpoint)
	var model_reference:PackedByteArray=reference.models[ASSET]
	var name_length:=model_reference.decode_u32(8)
	var pin:=model_reference.slice(12+name_length,44+name_length)
	var history:RefCounted=ClassDB.instantiate("NativeStaticHistory");history.configure([models],1048576,256)
	var scheduler:RefCounted=ClassDB.instantiate("NativeModelTransferScheduler")
	check(scheduler.configure(archive,history,4,32*1024*1024) and scheduler.register_collection(ASSET,models,pin),"model checkpoint is retained by native owner")
	var regions:Array[Vector3i]=[Vector3i(-1,0,0),Vector3i.ZERO,Vector3i(1,0,0)]
	var packets:Array[PackedByteArray]=[]
	for region:Vector3i in regions:
		var packet:PackedByteArray=blocks.capture_region(region);packets.append(packet)
		check(blocks.unload_region(packet),"block region retires "+str(region))
	var model_packet:PackedByteArray=models.capture_region(Vector3i.ZERO)
	check(models.unload_region(model_packet),"model records retire without changing authored content")
	var storage_before:Dictionary=blocks.capture_storage_state()
	check(mask().is_empty() and queries.exclusion_stats().state=="pending","uncached exact query waits instead of excluding entire unloaded regions")
	check(queries.exclusion_stats().pending<=2,"query service admits at most two archive reads")
	check(await resolve()==expected,"far block and compound-model exclusions exactly match resident reference")
	check(blocks.capture_storage_state()==storage_before and models.stats().instances==0,"read-only exclusion never hydrates gameplay records")
	check(blocks.overlap_mask([Transform3D(Basis.IDENTITY,Vector3(30,3,1))],BOUNDS)==PackedByteArray([1]),"ordinary construction still rejects unknown block regions")
	check(models.overlap_mask([Transform3D(Basis.IDENTITY,Vector3(4,4,4))],BOUNDS)==PackedByteArray([1]),"ordinary model placement remains conservative while unloaded")
	var reads:int=queries.exclusion_stats().reads
	var stable:=true
	for iteration in 64:stable=mask()==expected and stable
	check(stable and queries.exclusion_stats().reads==reads,"warm exact queries reuse checksum-bound pages without disk reads")
	var frame:=Transform3D(Basis(Vector3.UP,0.37).scaled(Vector3(1.25,1.5,0.75)),Vector3(300,18,-60))
	blocks.transform=frame;models.transform=frame
	var original_candidates:=candidates.duplicate()
	for index in candidates.size():candidates[index]=frame*candidates[index]
	check(mask()==expected,"collection rotation scale and translation preserve exact far membership")
	blocks.transform=Transform3D.IDENTITY;models.transform=Transform3D.IDENTITY;candidates=original_candidates
	check(models.begin_region_admission(model_packet),"incremental model admission begins")
	var admission:Dictionary=models.region_admission_stats()
	var admission_steps:=0
	while admission.active and admission_steps<100:
		stable=mask()==expected and stable
		admission=models.advance_region_admission(1,4096,2000)
		admission_steps+=1
	check(stable and not admission.active,"staged model admission cannot expose a partial exclusion set")
	check(models.stats().instances==2 and mask()==expected,"resident admission preserves complete membership")
	for index in regions.size():check(blocks.restore_region(packets[index],PackedByteArray()),"block region readmission "+str(regions[index]))
	check(mask()==expected,"all resident records have identical exclusions to distant pages")
	check(blocks.set_cells(PackedInt32Array([0,3,0,0])),"authoritative edit changes a cached region")
	var edited:=mask()
	check(edited!=expected,"resident edit ignores cached old occupancy")
	check(archive.publish(path,archive.encode({"terrain":PackedByteArray([1]),"structures":codec.encode(blocks.capture_snapshot(),{ASSET:models.capture_snapshot()})}))==OK,"edited geometry publishes a new digest")
	reference=codec.decode_reference(raw.decode(archive.read(path)).sections.structures)
	queries.configure_archive(archive,reference.checkpoint)
	var edited_packet:PackedByteArray=blocks.capture_region(Vector3i.ZERO)
	check(blocks.unload_region(edited_packet),"edited region retires to new immutable source")
	check(await resolve()==edited and queries.exclusion_stats().reads>reads,"new content digest cannot reuse pre-edit exclusion")
	var page:RefCounted=ClassDB.instantiate("NativeExclusionPage")
	var empty_parts:Array[AABB]=[]
	var checksum:=edited_packet.slice(edited_packet.size()-32)
	check(not page.load_packet(edited_packet,checksum,"",Vector3i(1,0,0),empty_parts),"compact decoder rejects mismatched region identity")
	check(page.load_packet(edited_packet,checksum,"",Vector3i.ZERO,empty_parts),"compact block decoder validates checksum and region")
	check(page.payload_bytes()<40000,"compact block region stays under 40KB rather than retaining full cells")
	check(not page.load_packet(edited_packet,checksum,"",Vector3i.ZERO,empty_parts),"published pages cannot be mutated by a second decode")
	var bad:=edited_packet.duplicate();bad[30]^=1
	var damaged:RefCounted=ClassDB.instantiate("NativeExclusionPage")
	check(not damaged.load_packet(bad,checksum,"",Vector3i.ZERO,empty_parts),"compact decoder rejects corrupted content")
	var metrics:Dictionary=queries.exclusion_stats()
	check(metrics.bytes<=metrics.byte_limit and metrics.high_bytes<=metrics.byte_limit and metrics.failures==0,"cache and in-flight page reservations respect shared 32MiB cap")
	queries.clear_exclusion_cache()
	check(mask().is_empty(),"cache reset starts a fresh asynchronous request")
	queries.clear_exclusion_cache()
	var deadline:=Time.get_ticks_msec()+5000
	while archive.region_read_stats().outstanding>0 and Time.get_ticks_msec()<deadline:await process_frame
	check(archive.region_read_stats().outstanding==0 and queries.exclusion_stats().bytes==0,"reset cancels owned pending active or completed reads without leaking reservations")
	page=null;damaged=null
	var cleanup_ok:=true
	for cycle in 24:
		var prior:Dictionary=archive.region_read_stats()
		mask()
		if cycle%3==1:
			var expected_finished:int=prior.finished+archive.region_read_stats().accepted-prior.accepted
			deadline=Time.get_ticks_msec()+5000
			while archive.region_read_stats().finished<expected_finished and Time.get_ticks_msec()<deadline:await process_frame
			cleanup_ok=archive.region_read_stats().finished>=expected_finished and cleanup_ok
		elif cycle%3==2:
			cleanup_ok=await resolve()==edited and cleanup_ok
		queries.clear_exclusion_cache()
		deadline=Time.get_ticks_msec()+5000
		while archive.region_read_stats().outstanding>0 and Time.get_ticks_msec()<deadline:await process_frame
		cleanup_ok=archive.region_read_stats().outstanding==0 and queries.exclusion_stats().bytes==0 and queries.exclusion_stats().live_pages==0 and cleanup_ok
	check(cleanup_ok,"24 pending completed and consumed page cycles release all payloads and reservations")
	queries.configure_archive(null,PackedByteArray())
	check(mask().is_empty() and queries.exclusion_stats().state=="unavailable","missing source returns unavailable rather than invented empty or solid geometry")
	archive.join_region_reads();queries.configure_archive(archive,reference.checkpoint)
	check(mask().is_empty() and queries.exclusion_stats().state=="unavailable","stopped archive worker cannot masquerade as pending work")
	scheduler=null;queries=null;models.free();blocks.free();archive.join_region_reads();archive.release()
	var diagnostics:RefCounted=ClassDB.instantiate("NativeStructureQueries")
	check(diagnostics.exclusion_stats().live_pages==0,"parity teardown releases every native exclusion page")
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"maximum_query_us":maximum_query_us,"metrics":metrics},"  "))
	print("STRUCTURE_EXCLUSION_PAGING checks=",checks," failures=",failures)
	quit(1 if failures else 0)
