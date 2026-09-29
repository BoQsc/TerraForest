extends SceneTree
var checks := 0
var failures := 0
var base := ""
var a1 := PackedByteArray()
var a2 := PackedByteArray()
var a3 := PackedByteArray()
var b1 := PackedByteArray()
var empty := PackedByteArray()

func _initialize() -> void:
	if not ClassDB.class_exists("NativeBlockRegionStore"):
		GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	run.call_deferred()

func sha(bytes: PackedByteArray) -> PackedByteArray:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish()

func resign(bytes: PackedByteArray) -> PackedByteArray:
	var payload := bytes.slice(0,bytes.size()-32)
	payload.append_array(sha(payload))
	return payload

func check(value: bool,label: String) -> void:
	checks+=1
	if not value: failures+=1
	print(("PASS " if value else "FAIL ")+label)

func folder(name: String) -> String:
	var path := base.path_join(name)
	DirAccess.make_dir_recursive_absolute(path)
	return path

func write(path: String,bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path,FileAccess.WRITE)
	assert(file!=null)
	file.store_buffer(bytes)
	file.flush()
	file.close()

func hash_of(packet: PackedByteArray) -> PackedByteArray:
	return packet.slice(packet.size()-32)

func blob_path(path: String,packet: PackedByteArray) -> String:
	return path.path_join("blobs").path_join(hash_of(packet).hex_encode()+".tfrg")

func collect(store: RefCounted) -> Dictionary:
	var removed := 0
	for i in range(100):
		var result: Dictionary = store.collect_garbage(1)
		if not result.ok or result.inspected>1: return {"ok":false,"deleted":removed}
		removed+=int(result.deleted)
		if result.complete: return {"ok":true,"deleted":removed}
	return {"ok":false,"deleted":removed}

func run() -> void:
	var reopen := ""
	var expected_sha := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--reopen-store="): reopen=arg.trim_prefix("--reopen-store=")
		if arg.begins_with("--expected-sha="): expected_sha=arg.trim_prefix("--expected-sha=")
	if not reopen.is_empty():
		reopen_in_process(reopen,expected_sha)
		return
	base=ProjectSettings.globalize_path("res://reports/rs_%d_%d" % [OS.get_process_id(),Time.get_ticks_msec()])
	DirAccess.make_dir_recursive_absolute(base)
	var world: Node3D = ClassDB.instantiate("NativeBlockWorld")
	world.set_cells(PackedInt32Array([1,0,0,1]))
	a1=world.capture_region(Vector3i.ZERO)
	world.set_cells(PackedInt32Array([1,0,0,2]))
	a2=world.capture_region(Vector3i.ZERO)
	world.set_cells(PackedInt32Array([1,0,0,3]))
	a3=world.capture_region(Vector3i.ZERO)
	world.set_cells(PackedInt32Array([-1,0,0,4]))
	b1=world.capture_region(Vector3i(-1,0,0))
	world.free()
	check_publication()
	check_collection()
	check_recovery()
	check_blob_corruption()
	check_external_changes()
	check_partial_io_failure()
	check_catalog_validation()
	check_restart()
	check_worker()
	var file := FileAccess.open("res://reports/block_region_store.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"scope":"Windows real-filesystem correctness, explicit recovery and worker-thread I/O; not physical power-loss or large-world throughput validation."},"  "))
	file.close()
	quit(1 if failures else 0)

func check_publication() -> void:
	var path := folder("pub")
	var store: RefCounted = ClassDB.instantiate("NativeBlockRegionStore")
	check(not store.publish_region(a1,empty).ok and not store.read_region(Vector3i.ZERO).ok,"closed store rejects publication and reads")
	check(not store.open_store("user://not_absolute").ok,"store requires an absolute filesystem directory")
	var opened: Dictionary = store.open_store(path)
	check(opened.ok and store.stats().generation==1 and store.list_regions().is_empty() and FileAccess.file_exists(path.path_join("catalog.tfrc")),"new store commits an empty catalog before any blob publication")
	check(not store.open_store(folder("other")).ok and store.stats().open,"reopening an active instance cannot abandon its lease")
	var competitor: RefCounted = ClassDB.instantiate("NativeBlockRegionStore")
	check(not competitor.open_store(path).ok,"exclusive OS lease rejects a second store owner")
	check(not store.publish_regions([],[]).ok and not store.publish_regions([a1],[]).ok,"empty and mismatched publication batches rejected")
	check(not store.publish_regions([17],[empty]).ok,"non-byte packet input rejected")
	var excessive: Array = []
	var expected: Array = []
	for i in range(65):
		excessive.append(a1)
		expected.append(empty)
	check(not store.publish_regions(excessive,expected).ok,"publication count is capped before validating or writing packets")
	check(not store.publish_regions([a1,a1],[empty,empty]).ok,"duplicate region in one batch rejected before writes")
	var corrupt := a1.duplicate()
	corrupt[30]^=1
	check(not store.publish_regions([b1,corrupt],[empty,empty]).ok and store.stats().regions==0 and DirAccess.get_files_at(path.path_join("blobs")).is_empty(),"invalid later packet rejects the entire batch without orphaning its earlier packet")
	check(store.publish_regions([a1,b1],[empty,empty]).ok and store.stats().generation==2,"two region blobs publish through one catalog generation")
	check(store.list_regions()==PackedInt32Array([-1,0,0,0,0,0]),"catalog keys are deterministic signed triples")
	check(store.checksum(Vector3i.ZERO)==hash_of(a1) and store.read_region(Vector3i.ZERO).bytes==a1,"catalog lookup verifies exact stored region bytes")
	check(not store.read_region(Vector3i(99,0,0)).ok,"absent catalog region is explicit rather than an empty packet")
	var catalog := FileAccess.get_file_as_bytes(path.path_join("catalog.tfrc"))
	check(not store.publish_region(a2,empty).ok and FileAccess.get_file_as_bytes(path.path_join("catalog.tfrc"))==catalog,"stale expected checksum cannot overwrite a committed region")
	check(store.publish_region(a1,hash_of(a1)).unchanged and store.stats().generation==2,"identical publication verifies the blob without advancing the catalog")
	check(store.publish_region(a2,hash_of(a1)).ok and store.read_region(Vector3i.ZERO).bytes==a2,"matching version condition advances a region")
	check(FileAccess.get_file_as_bytes(path.path_join("catalog.tfrc.bak"))==catalog,"previous complete catalog is retained as backup")
	check(not store.remove_region(Vector3i.ZERO,hash_of(a1)).ok and store.read_region(Vector3i.ZERO).bytes==a2,"stale delete cannot remove a newer region")
	check(store.remove_region(Vector3i.ZERO,hash_of(a2)).ok and not store.read_region(Vector3i.ZERO).ok and store.read_region(Vector3i(-1,0,0)).bytes==b1,"conditional removal preserves unrelated catalog entries")
	store.close()
	check(not store.stats().open and store.list_regions().is_empty(),"close releases in-memory catalog state")
	check(competitor.open_store(path).ok and competitor.read_region(Vector3i(-1,0,0)).bytes==b1,"a new owner reopens persisted catalog state after lease release")
	competitor.close()

func check_collection() -> void:
	var path := folder("gc")
	var store: RefCounted = ClassDB.instantiate("NativeBlockRegionStore")
	store.open_store(path)
	store.publish_region(a1,empty)
	store.publish_region(a2,hash_of(a1))
	store.publish_region(a3,hash_of(a2))
	write(blob_path(path,b1),b1) # Complete but uncommitted blob from an interrupted write.
	var note := path.path_join("blobs/notes.txt")
	write(note,"user note".to_utf8_buffer())
	var corrupt_name := path.path_join("blobs/"+"a".repeat(64)+".tfrg")
	write(corrupt_name,"not a region".to_utf8_buffer())
	var mismatch := path.path_join("blobs/"+"b".repeat(64)+".tfrg")
	write(mismatch,b1)
	check(not store.collect_garbage(0).ok and not store.collect_garbage(257).ok,"cleanup inspection budget is bounded")
	var result := collect(store)
	check(result.ok and result.deleted==2 and not FileAccess.file_exists(blob_path(path,a1)) and not FileAccess.file_exists(blob_path(path,b1)),"incremental cleanup removes obsolete and uncommitted valid blobs")
	check(FileAccess.file_exists(blob_path(path,a2)) and FileAccess.file_exists(blob_path(path,a3)),"cleanup preserves current and backup catalog references")
	check(FileAccess.file_exists(note) and FileAccess.file_exists(corrupt_name) and FileAccess.file_exists(mismatch),"cleanup preserves unrelated, corrupt and incorrectly named files")
	check(store.read_region(Vector3i.ZERO).bytes==a3,"cleanup does not change the current authored version")
	store.close()
	var opened: Dictionary = store.open_store(path,true)
	check(opened.ok and opened.recovered_from_backup and store.read_region(Vector3i.ZERO).bytes==a2,"backup selection is explicit even when the primary catalog is valid")
	check(not store.collect_garbage(8).ok,"cleanup is disabled until selected recovery is committed")
	check(store.publish_region(a2,hash_of(a2)).ok and not store.stats().recovered_from_backup and store.stats().generation==5,"publishing selected recovery advances beyond both known catalog generations")
	check(collect(store).ok and not FileAccess.file_exists(blob_path(path,a3)) and store.read_region(Vector3i.ZERO).bytes==a2,"cleanup uses recovered current and retained backup versions after commit")
	store.close()

func check_recovery() -> void:
	var path := folder("recovery")
	var store: RefCounted = ClassDB.instantiate("NativeBlockRegionStore")
	store.open_store(path)
	store.publish_region(a1,empty)
	store.publish_region(a2,hash_of(a1))
	store.close()
	var backup := FileAccess.get_file_as_bytes(path.path_join("catalog.tfrc.bak"))
	var broken := FileAccess.get_file_as_bytes(path.path_join("catalog.tfrc"))
	broken[20]^=1
	write(path.path_join("catalog.tfrc"),broken)
	var rejected: Dictionary = store.open_store(path)
	check(not rejected.ok and rejected.backup_available and FileAccess.get_file_as_bytes(path.path_join("catalog.tfrc"))==broken,"corrupt primary reports recovery availability without silently rolling back or rewriting files")
	check(store.open_store(path,true).ok and store.read_region(Vector3i.ZERO).bytes==a1,"explicit recovery reads the previous valid region version")
	check(store.publish_region(a3,hash_of(a1)).ok and store.read_region(Vector3i.ZERO).bytes==a3,"new publication replaces corrupt primary after explicit recovery")
	check(FileAccess.get_file_as_bytes(path.path_join("catalog.tfrc.bak"))==backup,"recovery never backs up the corrupt primary over the valid backup")
	store.close()
	write(path.path_join("catalog.tfrc"),broken)
	write(path.path_join("catalog.tfrc.bak"),PackedByteArray([1,2,3]))
	check(not store.open_store(path).ok and not store.open_store(path,true).ok,"two invalid catalogs never produce an empty successful world")
	var missing := folder("missing")
	store.open_store(missing)
	store.publish_region(a1,empty)
	store.close()
	DirAccess.remove_absolute(missing.path_join("catalog.tfrc"))
	DirAccess.remove_absolute(missing.path_join("catalog.tfrc.bak"))
	check(not store.open_store(missing).ok and FileAccess.get_file_as_bytes(blob_path(missing,a1))==a1,"existing blobs with missing catalogs cannot be reinitialized as an empty world")

func check_blob_corruption() -> void:
	var path := folder("blob")
	var store: RefCounted = ClassDB.instantiate("NativeBlockRegionStore")
	store.open_store(path)
	store.publish_region(a1,empty)
	store.close()
	var broken := a1.duplicate()
	broken[30]^=1
	write(blob_path(path,a1),broken)
	check(store.open_store(path).ok and not store.read_region(Vector3i.ZERO).ok,"lazy region read rejects a corrupted cataloged blob")
	write(blob_path(path,a1),a2)
	check(not store.read_region(Vector3i.ZERO).ok,"valid packet under the wrong content-addressed filename is rejected")
	var catalog := FileAccess.get_file_as_bytes(path.path_join("catalog.tfrc"))
	check(not store.publish_region(a1,hash_of(a1)).ok and FileAccess.get_file_as_bytes(path.path_join("catalog.tfrc"))==catalog,"immutable blob corruption prevents publication without changing the catalog")
	check(collect(store).ok and FileAccess.file_exists(blob_path(path,a1)),"cleanup preserves even a corrupt blob referenced by the catalog")
	store.close()
	DirAccess.remove_absolute(blob_path(path,a1))
	check(store.open_store(path).ok and not store.read_region(Vector3i.ZERO).ok,"missing cataloged blob is an explicit read failure")
	store.close()

func check_partial_io_failure() -> void:
	var path := folder("partial")
	var store: RefCounted = ClassDB.instantiate("NativeBlockRegionStore")
	store.open_store(path)
	var before := FileAccess.get_file_as_bytes(path.path_join("catalog.tfrc"))
	# A directory at the second blob's path forces a real filesystem failure
	# after the first valid blob is already published, without fault-injection APIs.
	DirAccess.make_dir_recursive_absolute(blob_path(path,b1))
	check(not store.publish_regions([a1,b1],[empty,empty]).ok and FileAccess.file_exists(blob_path(path,a1)) and store.stats().regions==0 and FileAccess.get_file_as_bytes(path.path_join("catalog.tfrc"))==before,"late blob I/O failure leaves the entire committed catalog unchanged")
	check(collect(store).ok and not FileAccess.file_exists(blob_path(path,a1)) and DirAccess.dir_exists_absolute(blob_path(path,b1)),"failed batch orphan is collectible while a conflicting directory is preserved")
	DirAccess.remove_absolute(blob_path(path,b1))
	check(store.publish_regions([a1,b1],[empty,empty]).ok and store.stats().regions==2,"batch can retry after the filesystem obstruction is removed")
	store.close()

func check_catalog_validation() -> void:
	var template := folder("template")
	var store: RefCounted = ClassDB.instantiate("NativeBlockRegionStore")
	store.open_store(template)
	store.publish_regions([a1,b1],[empty,empty])
	store.close()
	var valid := FileAccess.get_file_as_bytes(template.path_join("catalog.tfrc"))
	for variant in range(8):
		var bytes := valid.duplicate()
		match variant:
			0: bytes.encode_u32(16,65537)
			1: bytes.encode_u64(8,0)
			2: bytes[15]|=128
			3: bytes.encode_s32(20,16384)
			4: bytes.encode_s32(68,-1)
			5: bytes.encode_u32(64,99)
			6: bytes.encode_u32(64,2*1024*1024+1)
			7: bytes.append(0)
		bytes=resign(bytes)
		var path := folder("invalid%d" % variant)
		write(path.path_join("catalog.tfrc"),bytes)
		check(not store.open_store(path).ok,"checksummed malformed catalog rejected: count/generation/key/order/size/framing case %d" % variant)
	var oversized := valid.duplicate()
	oversized.resize(4*1024*1024+1)
	var huge := folder("oversized")
	write(huge.path_join("catalog.tfrc"),oversized)
	check(not store.open_store(huge).ok,"oversized catalog rejected before allocating its file contents")
	write(template.path_join("catalog.tfrc.bak"),PackedByteArray([7]))
	check(store.open_store(template).ok and not store.collect_garbage(1).ok,"invalid backup blocks cleanup even with a valid primary")
	check(store.publish_region(a2,hash_of(a1)).ok and collect(store).ok,"normal publication replaces an invalid backup with the verified previous primary")
	store.close()

func check_external_changes() -> void:
	var path := folder("external")
	var store: RefCounted = ClassDB.instantiate("NativeBlockRegionStore")
	store.open_store(path)
	store.publish_region(a1,empty)
	var original := FileAccess.get_file_as_bytes(path.path_join("catalog.tfrc"))
	var changed := original.duplicate()
	changed[0]^=1
	write(path.path_join("catalog.tfrc"),changed)
	check(not store.publish_region(b1,empty).ok and not store.collect_garbage(8).ok,"out-of-owner catalog changes stop publication and cleanup")
	check(not FileAccess.file_exists(blob_path(path,b1)) and FileAccess.get_file_as_bytes(path.path_join("catalog.tfrc"))==changed,"external change rejection leaves files untouched")
	write(path.path_join("catalog.tfrc"),original)
	write(path.path_join("catalog.tfrc.pending.interrupted"),"partial catalog".to_utf8_buffer())
	store.close()
	check(store.open_store(path).ok and store.read_region(Vector3i.ZERO).bytes==a1,"uncommitted pending catalog is ignored on reopening")
	store.close()

func check_restart() -> void:
	var path := folder("restart")
	var world: Node3D = ClassDB.instantiate("NativeBlockWorld")
	world.restore_region(a2,world.capture_region(Vector3i.ZERO))
	world.restore_region(b1,world.capture_region(Vector3i(-1,0,0)))
	var before: PackedByteArray = world.capture_snapshot()
	var store: RefCounted = ClassDB.instantiate("NativeBlockRegionStore")
	store.open_store(path)
	check(store.publish_regions([a2,b1],[empty,empty]).ok and world.unload_region(a2) and world.unload_region(b1),"persisted catalog packets acknowledge resident authored-region eviction")
	world.free()
	store.close()
	var output: Array = []
	var code := OS.execute(OS.get_executable_path(),PackedStringArray(["--headless","--path",ProjectSettings.globalize_path("res://"),"--script","res://tests/block_region_store.gd","--quit-after","120","--","--reopen-store="+path,"--expected-sha="+sha(before).hex_encode()]),output,true,false)
	for text in output: print(text)
	var child_report = JSON.parse_string(FileAccess.get_file_as_string(path.path_join("reopen_check.json")))
	check(code==0 and child_report is Dictionary and child_report.get("pass",false),"separate engine process reconstructs the exact world from committed disk files")
	store=ClassDB.instantiate("NativeBlockRegionStore")
	check(store.open_store(path).ok,"new store object reopens the committed catalog")
	world=ClassDB.instantiate("NativeBlockWorld")
	var keys: PackedInt32Array = store.list_regions()
	var restored := true
	for i in range(0,keys.size(),3):
		var key := Vector3i(keys[i],keys[i+1],keys[i+2])
		var read: Dictionary = store.read_region(key)
		restored=read.ok and world.restore_region(read.bytes,world.capture_region(key)) and restored
	check(restored and world.capture_snapshot()==before,"fresh world reconstructs exact authored bytes from disk catalog and blobs")
	write(ProjectSettings.globalize_path("res://reports/block_region_catalog.fixture"),FileAccess.get_file_as_bytes(path.path_join("catalog.tfrc")))
	world.free()
	store.close()

func reopen_in_process(path: String,expected_sha: String) -> void:
	var store: RefCounted = ClassDB.instantiate("NativeBlockRegionStore")
	var ok: bool = store.open_store(path).ok
	var world: Node3D = ClassDB.instantiate("NativeBlockWorld")
	var keys: PackedInt32Array = store.list_regions()
	for i in range(0,keys.size(),3):
		var key := Vector3i(keys[i],keys[i+1],keys[i+2])
		var result: Dictionary = store.read_region(key)
		ok=ok and result.ok and world.restore_region(result.bytes,world.capture_region(key))
	ok=ok and sha(world.capture_snapshot()).hex_encode()==expected_sha
	world.free()
	store.close()
	write(path.path_join("reopen_check.json"),JSON.stringify({"pass":ok}).to_utf8_buffer())
	print("PASS " if ok else "FAIL ","fresh engine process disk reconstruction")
	quit(0 if ok else 1)

func worker_io(path: String,ready: Semaphore,proceed: Semaphore) -> Dictionary:
	var store: RefCounted = ClassDB.instantiate("NativeBlockRegionStore")
	var opened: Dictionary = store.open_store(path)
	ready.post()
	proceed.wait()
	var published: Dictionary = store.publish_region(a1,empty)
	var read: Dictionary = store.read_region(Vector3i.ZERO)
	store.close()
	return {"ok":opened.ok and published.ok and read.ok and read.bytes==a1}

func check_worker() -> void:
	var path := folder("worker")
	var ready := Semaphore.new()
	var proceed := Semaphore.new()
	var worker := Thread.new()
	worker.start(worker_io.bind(path,ready,proceed))
	ready.wait()
	var competitor: RefCounted = ClassDB.instantiate("NativeBlockRegionStore")
	check(not competitor.open_store(path).ok,"I/O worker owns the same exclusive store lease")
	proceed.post()
	var result: Dictionary = worker.wait_to_finish()
	check(result.ok,"native publication and verification execute successfully on an I/O worker")
