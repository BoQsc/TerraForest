# SPDX-License-Identifier: 0BSD
extends SceneTree
const ASSET:="test/dense_exclusion"
const BOUNDS:=AABB(Vector3.ONE*-0.01,Vector3.ONE*0.02)
var failures:=0
var checks:=0
var maximum_query_us:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func resolve(service:RefCounted,blocks:Node3D,models:Array,poses:Array[Transform3D])->PackedByteArray:
	var deadline:=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline:
		var began:=Time.get_ticks_usec()
		var result:PackedByteArray=service.overlap_mask(blocks,models,poses,BOUNDS)
		maximum_query_us=maxi(maximum_query_us,Time.get_ticks_usec()-began)
		if result.size()==poses.size():return result
		await process_frame
	return PackedByteArray()
func run()->void:
	GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
	var output:="res://reports/structure_exclusion_pressure"
	DirAccess.make_dir_recursive_absolute(output)
	var blocks:Node3D=ClassDB.instantiate("NativeBlockWorld")
	var cells:=PackedInt32Array()
	for owner in 270:cells.append_array(PackedInt32Array([owner*64,0,0,1]))
	check(blocks.set_cells(cells),"270 sparse block regions configure")
	var model:Node3D=ClassDB.instantiate("NativeStaticBatch")
	check(model.configure_collision_only() and model.configure_asset(ASSET,BoxMesh.new()) and model.configure_collision(AABB(Vector3.ONE*-0.02,Vector3.ONE*0.04),8,8,2),"dense collision-only model configures without rendering or bodies")
	var ids:=PackedInt64Array();var values:=PackedFloat32Array()
	for index in 100000:
		ids.append(index+1)
		values.append_array(PackedFloat32Array([1,0,0,(index%20)*0.5,0,1,0,int(index/400)*0.1,0,0,1,(int(index/20)%20)*0.5]))
	check(model.upsert_instances(ids,values),"100000-instance region admits bounded authoritative records")
	var poses:Array[Transform3D]=[Transform3D(Basis.IDENTITY,Vector3(0,1,0)),Transform3D(Basis.IDENTITY,Vector3(9.25,20,9.25)),Transform3D(Basis.IDENTITY,Vector3(9.5,20,9.5))]
	var service:RefCounted=ClassDB.instantiate("NativeStructureQueries")
	var expected:PackedByteArray=service.overlap_mask(blocks,[model],poses,BOUNDS)
	check(expected==PackedByteArray([1,0,1]),"dense resident oracle preserves spaces between small solids")
	var codec:RefCounted=ClassDB.instantiate("NativeStructuresSnapshot");codec.configure_assets(PackedStringArray([ASSET]))
	var raw:RefCounted=ClassDB.instantiate("NativeWorldArchive")
	var archive:RefCounted=ClassDB.instantiate("NativeRegionWorldArchive");archive.configure(raw,codec,true)
	var path:=ProjectSettings.globalize_path(output.path_join("fixture_%d.trw"%OS.get_process_id()))
	check(archive.acquire(path) and archive.publish(path,archive.encode({"terrain":PackedByteArray([1]),"structures":codec.encode(blocks.capture_snapshot(),{ASSET:model.capture_snapshot()})}))==OK and archive.start_region_reads(8,64*1024*1024),"dense fixture publishes and starts shared reader")
	var reference:Dictionary=codec.decode_reference(raw.decode(archive.read(path)).sections.structures)
	service.configure_archive(archive,reference.checkpoint)
	var record:PackedByteArray=reference.models[ASSET];var length:=record.decode_u32(8)
	var history:RefCounted=ClassDB.instantiate("NativeStaticHistory");history.configure([model],1048576,256)
	var scheduler:RefCounted=ClassDB.instantiate("NativeModelTransferScheduler")
	check(scheduler.configure(archive,history,4,32*1024*1024) and scheduler.register_collection(ASSET,model,record.slice(12+length,44+length)),"dense model checkpoint lease binds to source")
	var packet:PackedByteArray=model.capture_region(Vector3i.ZERO)
	check(model.unload_region(packet),"dense gameplay records retire")
	var began:=Time.get_ticks_usec()
	check(await resolve(service,blocks,[model],poses)==expected,"worker-built dense BVH matches resident oracle")
	var dense_ms:float=(Time.get_ticks_usec()-began)/1000.0
	var dense:Dictionary=service.exclusion_stats()
	check(dense.bytes<12*1024*1024 and model.stats().instances==0,"dense exact page is bounded and does not hydrate records")
	var retired:=true
	for owner in 270:retired=blocks.unload_region(blocks.capture_region(Vector3i(owner,0,0))) and retired
	check(retired,"sparse regions retire for cache pressure")
	var parity:=true
	for owner in 270:
		var batch:Array[Transform3D]=[Transform3D(Basis.IDENTITY,Vector3(owner*64+0.5,0.5,0.5)),Transform3D(Basis.IDENTITY,Vector3(owner*64+10,1,1))]
		parity=await resolve(service,blocks,[],batch)==PackedByteArray([1,0]) and parity
	check(parity,"270 exact far queries complete despite 256-page cache capacity")
	var pressure:Dictionary=service.exclusion_stats()
	check(pressure.pages<=256 and pressure.high_bytes<=pressure.byte_limit and pressure.evictions>=15,"global LRU respects page and byte caps across owners")
	var first:Array[Transform3D]=[Transform3D(Basis.IDENTITY,Vector3(10,1,1))]
	var reads:int=pressure.reads
	check(await resolve(service,blocks,[],first)==PackedByteArray([0]) and service.exclusion_stats().reads>reads,"evicted region reloads without changing occupancy")
	service.clear_exclusion_cache();scheduler=null;service=null;model.free();blocks.free();archive.join_region_reads();archive.release()
	var diagnostics:RefCounted=ClassDB.instantiate("NativeStructureQueries")
	check(diagnostics.exclusion_stats().live_pages==0,"pressure teardown releases every compact page")
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"maximum_query_us":maximum_query_us,"dense_ms":dense_ms,"dense":dense,"pressure":pressure},"  "))
	print("STRUCTURE_EXCLUSION_PRESSURE checks=",checks," failures=",failures)
	quit(1 if failures else 0)
