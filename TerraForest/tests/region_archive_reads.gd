extends SceneTree
const RESERVATION := 2*1024*1024+96
const MODEL_RESERVATION := 5600232+96
var checks := 0
var failures := 0

func _initialize() -> void:
	GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
	run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)

func until(predicate: Callable) -> bool:
	var end := Time.get_ticks_msec()+15000
	while not predicate.call() and Time.get_ticks_msec()<end:
		await process_frame
	return predicate.call()

func collect(archive: RefCounted,count: int) -> Array:
	var results: Array = []
	var end := Time.get_ticks_msec()+15000
	while results.size()<count and Time.get_ticks_msec()<end:
		results.append_array(archive.poll_region_reads(mini(4,count-results.size())))
		if results.size()<count: await process_frame
	return results

func codec() -> RefCounted:
	var result: RefCounted = ClassDB.instantiate("NativeStructuresSnapshot")
	result.configure_assets(PackedStringArray())
	return result

func make_archive(c: RefCounted) -> RefCounted:
	var archive: RefCounted = ClassDB.instantiate("NativeRegionWorldArchive")
	archive.configure(ClassDB.instantiate("NativeWorldArchive"),c,true)
	return archive

func run() -> void:
	Engine.max_fps=240
	var directory := ProjectSettings.globalize_path("res://reports/archive_reads_%d_%d" % [OS.get_process_id(),Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(directory)
	var path := directory.path_join("world.trw")
	var c := codec()
	var archive := make_archive(c)
	check(not archive.start_region_reads(),"closed archive cannot start a region worker")
	check(archive.acquire(path),"archive acquires root and sidecar before read service starts")
	var w: Node3D = ClassDB.instantiate("NativeBlockWorld")
	w.set_cells(PackedInt32Array([-1,0,0,1,64,0,0,2]))
	var packet: PackedByteArray = w.capture_region(Vector3i(-1,0,0))
	var digest: PackedByteArray = packet.slice(packet.size()-32)
	var sections := {"terrain":PackedByteArray([1]),"structures":c.encode(w.capture_snapshot(),{})}
	check(archive.publish(path,archive.encode(sections))==OK,"read fixture publishes a complete world")
	var raw: RefCounted = ClassDB.instantiate("NativeWorldArchive")
	var checkpoint: PackedByteArray = c.decode_reference(raw.decode(archive.read(path)).sections.structures).checkpoint
	check(not archive.start_region_reads(0,RESERVATION) and not archive.start_region_reads(65,RESERVATION),"read request limits reject values outside the supported bound")
	check(not archive.start_region_reads(1,RESERVATION-1) and not archive.start_region_reads(1,128*1024*1024+1),"read byte limit must reserve a worst-case packet and stay bounded")
	check(archive.start_region_reads(2,2*RESERVATION) and not archive.start_region_reads(),"one persistent worker starts per archive lifecycle")
	var competing: RefCounted = ClassDB.instantiate("NativeBlockRegionStore")
	check(not competing.open_store(path+".regions").ok,"read service shares the exclusive existing store instead of opening another writer")
	var exposed_digest := digest.duplicate()
	var exposed_pin := checkpoint.duplicate()
	var first: int = archive.request_region_read(Vector3i(-1,0,0),exposed_digest,exposed_pin,17)
	exposed_digest[0]^=1
	exposed_pin[0]^=1
	var second: int = archive.request_region_read(Vector3i(-1,0,0),digest,checkpoint,18)
	check(first>0 and second>first,"requests receive increasing nonzero tickets")
	check(archive.request_region_read(Vector3i(-1,0,0),digest,checkpoint,19)==0,"count backpressure includes accepted active and pending reads")
	check(await until(func(): return archive.region_read_stats().completed==2),"accepted reads finish without scene polling")
	check(archive.region_read_stats().reserved_bytes==2*RESERVATION and archive.request_region_read(Vector3i(-1,0,0),digest,checkpoint,19)==0,"unread completions retain their full reservation and apply backpressure")
	check(archive.poll_region_reads(0).is_empty() and archive.poll_region_reads(65).is_empty() and archive.region_read_stats().outstanding==2,"invalid poll budgets do not release reservations")
	var results: Array = archive.poll_region_reads(1)
	check(results.size()==1 and results[0].ticket==first and results[0].epoch==17 and results[0].region==Vector3i(-1,0,0),"bounded polling preserves FIFO ticket epoch and region")
	check(results[0].ok and results[0].bytes==packet and results[0].expected_checksum==digest and results[0].checkpoint==checkpoint,"caller mutation cannot change accepted request digests or exact returned bytes")
	check(archive.region_read_stats().outstanding==1 and archive.region_read_stats().reserved_bytes==RESERVATION,"polling releases exactly one result reservation")
	results=archive.poll_region_reads(4)
	check(results.size()==1 and results[0].ticket==second and archive.region_read_stats().reserved_bytes==0,"remaining completion releases all queued payload accounting")
	archive.join_region_reads()
	check(archive.start_region_reads(8,RESERVATION),"stopped drained service can restart with a smaller byte budget")
	var third: int = archive.request_region_read(Vector3i(-1,0,0),digest,checkpoint,20)
	check(third>second and archive.request_region_read(Vector3i(-1,0,0),digest,checkpoint,20)==0,"byte backpressure applies independently of request count and tickets survive restart")
	results=await collect(archive,1)
	check(results.size()==1 and results[0].ok and archive.region_read_stats().high_bytes==RESERVATION,"restarted worker respects its new byte ceiling")
	check(archive.request_region_read(Vector3i(-1,0,0),PackedByteArray(),checkpoint,20)==0 and archive.request_region_read(Vector3i(-1,0,0),digest,PackedByteArray([1]),20)==0,"invalid digest lengths reject before queue admission")
	check(archive.request_region_read(Vector3i(-16385,0,0),digest,checkpoint,20)==0 and archive.request_region_read(Vector3i(-1,0,0),digest,checkpoint,-1)==0,"out-of-range regions and negative epochs reject before queue admission")
	var missing: int = archive.request_region_read(Vector3i(8,0,0),digest,checkpoint,21)
	results=await collect(archive,1)
	check(missing>0 and results.size()==1 and not results[0].ok and results[0].ticket==missing and results[0].epoch==21,"missing exact version yields an explicit failed completion")
	check(archive.region_read_stats().outstanding==0 and archive.region_read_stats().reserved_bytes==0,"failed result releases its reservation when consumed")
	# An old request carries the original epoch and cannot overwrite a newly
	# installed unavailable-region version even if a caller forgets its epoch gate.
	w.unload_region(packet)
	var delayed: int = archive.request_region_read(Vector3i(-1,0,0),digest,checkpoint,30)
	var changed: Node3D = ClassDB.instantiate("NativeBlockWorld")
	changed.set_cells(PackedInt32Array([-1,0,0,6]))
	changed.unload_region(changed.capture_region(Vector3i(-1,0,0)))
	var state: Dictionary = changed.capture_storage_state()
	w.restore_storage_state(state.resident,state.unavailable_keys,state.unavailable_checksums)
	results=await collect(archive,1)
	check(results.size()==1 and results[0].ticket==delayed and results[0].epoch!=31 and results[0].ok,"completed read keeps its submission epoch across scene replacement")
	check(not w.restore_region(results[0].bytes,PackedByteArray()) and not w.is_region_loaded(Vector3i(-1,0,0)),"old region data cannot replace a different expected version after scene reload")
	changed.free()
	archive.join_region_reads()
	check(archive.start_region_reads(4,4*RESERVATION),"read service restarts for concurrent save exercise")
	var generations: Array[PackedByteArray] = []
	w.restore_snapshot(c.decode(sections.structures).blocks)
	for i in range(32):
		w.set_cells(PackedInt32Array([64,0,0,1+i%6]))
		sections.structures=c.encode(w.capture_snapshot(),{})
		generations.append(archive.encode(sections))
	var writer := Thread.new()
	check(writer.start(func():
		for bytes in generations:
			if archive.publish(path,bytes)!=OK: return false
		return true)==OK,"save owner runs concurrently with background exact-version reads")
	var correct := true
	var accepted := 0
	var completed := 0
	var end := Time.get_ticks_msec()+15000
	while (accepted<100 or completed<accepted) and Time.get_ticks_msec()<end:
		if accepted<100:
			if archive.request_region_read(Vector3i(-1,0,0),digest,checkpoint,40)>0: accepted+=1
		for result in archive.poll_region_reads(4):
			completed+=1
			correct=correct and result.ok and result.bytes==packet and result.epoch==40
		await process_frame
	var saved: bool = writer.wait_to_finish()
	check(saved and accepted==100 and completed==100 and correct,"100 exact reads coexist with 32 checkpoint publications and pin retirement")
	var stats: Dictionary = archive.region_read_stats()
	check(stats.high_requests<=4 and stats.high_bytes<=4*RESERVATION and stats.outstanding==0,"concurrent workload stays within both queue budgets")
	check(archive.storage_stats().checkpoints<=2,"background reads do not leak checkpoint pins")
	var last: int = archive.request_region_read(Vector3i(-1,0,0),digest,checkpoint,50)
	var last_two: int = archive.request_region_read(Vector3i(-1,0,0),digest,checkpoint,51)
	archive.stop_region_reads()
	check(last>0 and last_two>last and archive.request_region_read(Vector3i(-1,0,0),digest,checkpoint,52)==0,"stop closes admission while retaining accepted requests")
	archive.release()
	stats=archive.region_read_stats()
	check(not stats.running and stats.pending==0 and stats.completed==2 and stats.finished==stats.accepted,"release drains accepted work and joins the reader before closing storage")
	check(not archive.acquire(path),"unconsumed old-world completions prevent archive reacquisition")
	results=archive.poll_region_reads(4)
	check(results.size()==2 and results[0].ticket==last and results[1].ticket==last_two and results[0].ok and results[1].ok,"accepted completions remain consumable after release")
	check(archive.acquire(path) and archive.start_region_reads(1,RESERVATION),"consuming completions permits a fresh archive lifecycle")
	check(archive.request_region_read(Vector3i(-1,0,0),digest,checkpoint,60)>last_two,"tickets remain unique across world release and reacquisition")
	results=await collect(archive,1)
	check(results.size()==1 and results[0].ok,"reacquired service still reads the exact retained active version")
	archive.join_region_reads()
	var blob := path+".regions/blobs/"+digest.hex_encode()+".tfrg"
	var file := FileAccess.open(blob,FileAccess.WRITE)
	file.store_buffer(PackedByteArray([1,2,3]))
	file.close()
	archive.start_region_reads(1,RESERVATION)
	archive.request_region_read(Vector3i(-1,0,0),digest,checkpoint,61)
	results=await collect(archive,1)
	check(results.size()==1 and not results[0].ok and not results[0].has("bytes"),"corrupt region produces failure without exposing an admissible payload")
	archive.release()
	check(archive.region_read_stats().outstanding==0 and archive.region_read_stats().reserved_bytes==0,"final shutdown leaves no reserved payloads")
	check_destructor(directory,c,packet,digest)
	await check_models(directory)
	w.free()
	var report := {"checks":checks,"failures":failures,"scope":"Bounded block/model reads sharing one world archive worker, concurrent publication, asset isolation and exact-version restore; automatic model admission remains pending."}
	file=FileAccess.open("res://reports/region_archive_reads.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	quit(1 if failures else 0)

func check_destructor(directory: String,c: RefCounted,packet: PackedByteArray,digest: PackedByteArray) -> void:
	var ok := true
	for i in range(12):
		var path := directory.path_join("destructor_%d.trw" % i)
		var archive := make_archive(c)
		ok=archive.acquire(path) and ok
		var w: Node3D = ClassDB.instantiate("NativeBlockWorld")
		w.restore_region(packet,w.capture_region(Vector3i(-1,0,0)))
		ok=archive.publish(path,archive.encode({"structures":c.encode(w.capture_snapshot(),{}),"terrain":PackedByteArray([1])}))==OK and ok
		w.free()
		archive.start_region_reads(4,4*RESERVATION)
		for j in range(4):
			ok=archive.request_region_read(Vector3i(-1,0,0),digest,PackedByteArray(),i)>0 and ok
		archive=null
		var raw: RefCounted = ClassDB.instantiate("NativeWorldArchive")
		var store: RefCounted = ClassDB.instantiate("NativeBlockRegionStore")
		ok=raw.acquire(path) and store.open_store(path+".regions").ok and ok
		store.close()
		raw.release()
	check(ok,"12 destructor cycles join queued readers and relinquish both file leases")

func model_pin(c: RefCounted,archive: RefCounted,path: String,asset: String) -> PackedByteArray:
	var raw: RefCounted=ClassDB.instantiate("NativeWorldArchive")
	var reference: PackedByteArray=c.decode_reference(raw.decode(archive.read(path)).sections.structures).models[asset]
	var size: int=reference.decode_u32(8)
	return reference.slice(12+size,44+size)

func check_models(directory: String) -> void:
	var c: RefCounted=ClassDB.instantiate("NativeStructuresSnapshot")
	c.configure_assets(PackedStringArray(["test/one","test/two"]))
	var archive := make_archive(c)
	var path := directory.path_join("mixed.trw")
	var batch: Node3D=ClassDB.instantiate("NativeStaticBatch")
	var other: Node3D=ClassDB.instantiate("NativeStaticBatch")
	batch.configure_asset("test/one",BoxMesh.new());other.configure_asset("test/two",BoxMesh.new())
	batch.upsert_instances(PackedInt64Array([1,2]),PackedFloat32Array([1,0,0,-1,0,1,0,0,0,0,1,0,1,0,0,65,0,1,0,0,0,0,1,0]))
	other.upsert_instances(PackedInt64Array([1]),PackedFloat32Array([1,0,0,-3,0,1,0,0,0,0,1,0]))
	var w: Node3D=ClassDB.instantiate("NativeBlockWorld")
	w.set_cells(PackedInt32Array([-1,0,0,1]))
	var block_packet: PackedByteArray=w.capture_region(Vector3i(-1,0,0))
	var packet: PackedByteArray=batch.capture_region(Vector3i(-1,0,0))
	var other_packet: PackedByteArray=other.capture_region(Vector3i(-1,0,0))
	var digest: PackedByteArray=packet.slice(packet.size()-32)
	var sections: Dictionary={"terrain":PackedByteArray([1]),"structures":c.encode(w.capture_snapshot(),{"test/one":batch.capture_snapshot(),"test/two":other.capture_snapshot()})}
	check(archive.acquire(path) and archive.publish(path,archive.encode(sections))==OK,"mixed reader fixture publishes block and two asset catalogs")
	var pin := model_pin(c,archive,path,"test/one")
	check(archive.start_region_reads(4,RESERVATION) and archive.request_model_region_read("test/one",Vector3i(-1,0,0),digest,pin,1)==0,"model read rejects a budget too small for its worst-case packet")
	archive.join_region_reads()
	check(archive.start_region_reads(4,RESERVATION+2*MODEL_RESERVATION),"one archive worker accepts a shared mixed-payload budget")
	check(archive.request_model_region_read("",Vector3i.ZERO,digest,pin,1)==0 and archive.request_model_region_read("test/unknown",Vector3i.ZERO,digest,pin,1)==0,"empty and unregistered model assets reject before queue admission")
	check(archive.request_model_region_read("test/one",Vector3i(32768,0,0),digest,pin,1)==0 and archive.request_model_region_read("test/one",Vector3i.ZERO,PackedByteArray(),pin,1)==0,"model region and checksum validation rejects malformed requests")
	var exposed := digest.duplicate()
	var first: int=archive.request_model_region_read("test/one",Vector3i(-1,0,0),exposed,pin,2)
	exposed[0]^=1
	var second: int=archive.request_region_read(Vector3i(-1,0,0),block_packet.slice(block_packet.size()-32),PackedByteArray(),3)
	var third: int=archive.request_model_region_read("test/two",Vector3i(-1,0,0),other_packet.slice(other_packet.size()-32),PackedByteArray(),4)
	check(first>0 and second>first and third>second,"block and model requests share monotonic tickets")
	check(await until(func(): return archive.region_read_stats().completed==3),"mixed requests finish on the same persistent worker")
	check(archive.region_read_stats().reserved_bytes==RESERVATION+2*MODEL_RESERVATION and archive.request_region_read(Vector3i(-1,0,0),digest,PackedByteArray(),5)==0,"unread mixed completions enforce shared byte backpressure")
	var blocks: Array=archive.poll_region_reads(4)
	check(blocks.size()==1 and blocks[0].ticket==second and blocks[0].bytes==block_packet,"block consumer never consumes model completions")
	check(archive.poll_model_region_reads(0).is_empty() and archive.region_read_stats().reserved_bytes==2*MODEL_RESERVATION,"invalid model polling cannot release reservations")
	var models: Array=archive.poll_model_region_reads(1)
	check(models.size()==1 and models[0].ok and models[0].ticket==first and models[0].asset=="test/one" and models[0].epoch==2 and models[0].bytes==packet,"model completion retains asset epoch exact bytes and owned request data")
	check(archive.region_read_stats().reserved_bytes==MODEL_RESERVATION,"model polling releases only its own payload reservation")
	models=archive.poll_model_region_reads(4)
	check(models.size()==1 and models[0].asset=="test/two" and models[0].bytes==other_packet and archive.region_read_stats().outstanding==0,"identical placement IDs and region coordinates remain isolated by asset")
	batch.upsert_instances(PackedInt64Array([1]),PackedFloat32Array([1,0,0,-2,0,1,0,0,0,0,1,0]))
	sections.structures=c.encode(w.capture_snapshot(),{"test/one":batch.capture_snapshot(),"test/two":other.capture_snapshot()})
	check(archive.publish(path,archive.encode(sections))==OK,"model publication replaces active version while retaining compound backup")
	archive.request_model_region_read("test/one",Vector3i(-1,0,0),digest,pin,6)
	archive.request_model_region_read("test/one",Vector3i(-1,0,0),digest,PackedByteArray(),7)
	await until(func(): return archive.region_read_stats().model_completed==2)
	models=archive.poll_model_region_reads(4)
	check(models.size()==2 and models[0].ok and models[0].bytes==packet and not models[1].ok,"exact old model version reads only through its retained checkpoint")
	var current: PackedByteArray=batch.capture_region(Vector3i(-1,0,0))
	batch.unload_region(current)
	check(not batch.restore_region(models[0].bytes) and not batch.is_region_loaded(Vector3i(-1,0,0)),"stale successful read cannot overwrite a newer unloaded model version")
	archive.request_model_region_read("test/one",Vector3i(-1,0,0),current.slice(current.size()-32),PackedByteArray(),8)
	await until(func(): return archive.region_read_stats().model_completed==1)
	models=archive.poll_model_region_reads(4)
	check(models.size()==1 and models[0].ok and batch.restore_region(models[0].bytes),"current model region restores directly from archive-owned background read")
	var generations: Array[PackedByteArray]=[]
	for i in range(16):
		batch.upsert_instances(PackedInt64Array([2]),PackedFloat32Array([1,0,0,65+i,0,1,0,0,0,0,1,0]))
		sections.structures=c.encode(w.capture_snapshot(),{"test/one":batch.capture_snapshot(),"test/two":other.capture_snapshot()})
		generations.append(archive.encode(sections))
	var writer := Thread.new()
	check(writer.start(func():
		for bytes in generations:
			if archive.publish(path,bytes)!=OK:return false
		return true)==OK,"compound writer runs alongside model and block reads")
	var accepted := 0
	var completed := 0
	var correct := true
	var end := Time.get_ticks_msec()+15000
	while (accepted<64 or completed<accepted) and Time.get_ticks_msec()<end:
		if accepted<64:
			var ticket: int=archive.request_model_region_read("test/one",Vector3i(-1,0,0),current.slice(current.size()-32),PackedByteArray(),9) if accepted%2==0 else archive.request_region_read(Vector3i(-1,0,0),block_packet.slice(block_packet.size()-32),PackedByteArray(),9)
			if ticket>0:accepted+=1
		for result in archive.poll_region_reads(4)+archive.poll_model_region_reads(4):
			completed+=1
			correct=correct and result.ok and result.epoch==9 and result.bytes==(current if result.has("asset") else block_packet)
		await process_frame
	check(writer.wait_to_finish() and accepted==64 and completed==64 and correct,"64 mixed exact reads coexist with 16 model catalog publications and cleanup")
	check(archive.region_read_stats().high_bytes<=RESERVATION+2*MODEL_RESERVATION and archive.region_read_stats().outstanding==0 and archive.region_read_stats().worker_starts==2,"mixed workload stays bounded with no per-asset workers")
	archive.request_model_region_read("test/one",Vector3i(-1,0,0),current.slice(current.size()-32),PackedByteArray(),10)
	archive.request_region_read(Vector3i(-1,0,0),block_packet.slice(block_packet.size()-32),PackedByteArray(),10)
	archive.release()
	check(archive.region_read_stats().completed==2 and not archive.acquire(path),"release drains both read kinds before closing stores and refuses reuse with unread results")
	blocks=archive.poll_region_reads(4);models=archive.poll_model_region_reads(4)
	check(blocks.size()==1 and models.size()==1 and blocks[0].ok and models[0].ok and archive.region_read_stats().reserved_bytes==0,"both result channels survive release and release all accounting")
	check(archive.acquire(path) and archive.start_region_reads(1,MODEL_RESERVATION),"model read service restarts after archive reacquisition")
	archive.request_model_region_read("test/two",Vector3i(-1,0,0),other_packet.slice(other_packet.size()-32),PackedByteArray(),11)
	await until(func(): return archive.region_read_stats().model_completed==1)
	models=archive.poll_model_region_reads(4)
	check(models.size()==1 and models[0].ok and models[0].bytes==other_packet,"worker lazily reopens persisted asset catalog without a scene-thread store open")
	archive.release()
	var model_dir := path+".models"
	check(DirAccess.rename_absolute(model_dir,model_dir+".held")==OK,"missing model sidecar fixture temporarily removes saved catalogs")
	archive.acquire(path);archive.start_region_reads(1,MODEL_RESERVATION)
	archive.request_model_region_read("test/two",Vector3i(-1,0,0),other_packet.slice(other_packet.size()-32),PackedByteArray(),12)
	await until(func(): return archive.region_read_stats().model_completed==1)
	models=archive.poll_model_region_reads(4)
	check(models.size()==1 and not models[0].ok and not models[0].has("bytes") and not DirAccess.dir_exists_absolute(model_dir),"missing model catalog fails on worker without inventing a replacement sidecar")
	archive.release()
	check(DirAccess.rename_absolute(model_dir+".held",model_dir)==OK,"missing sidecar fixture restores original catalogs")
	var hash := HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update("test/two".to_utf8_buffer())
	var blob := model_dir.path_join(hash.finish().hex_encode()).path_join("blobs").path_join(other_packet.slice(other_packet.size()-32).hex_encode()+".tfrg")
	var file := FileAccess.open(blob,FileAccess.WRITE);file.store_buffer(PackedByteArray([1,2,3]));file.close()
	archive.acquire(path);archive.start_region_reads(1,MODEL_RESERVATION)
	archive.request_model_region_read("test/two",Vector3i(-1,0,0),other_packet.slice(other_packet.size()-32),PackedByteArray(),13)
	await until(func(): return archive.region_read_stats().model_completed==1)
	models=archive.poll_model_region_reads(4)
	check(models.size()==1 and not models[0].ok and not models[0].has("bytes") and archive.region_read_stats().reserved_bytes==0,"corrupt model blob yields failed completion without payload and releases its reservation")
	archive.release();w.free();batch.free();other.free()
