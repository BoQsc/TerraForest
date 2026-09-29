extends SceneTree
var checks := 0
var failures := 0
var base := ""
var packets: Array[PackedByteArray] = []
var empty := PackedByteArray()

func _initialize() -> void:
	if not ClassDB.class_exists("NativeBlockRegionStore"):
		GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)

func folder(name: String) -> String:
	var path := base.path_join(name)
	DirAccess.make_dir_recursive_absolute(path)
	return path

func hash_of(bytes: PackedByteArray) -> PackedByteArray:
	return bytes.slice(bytes.size()-32)

func sha(bytes: PackedByteArray) -> PackedByteArray:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(bytes)
	return h.finish()

func write(path: String,bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path,FileAccess.WRITE)
	assert(file!=null)
	file.store_buffer(bytes)
	file.close()

func blob(path: String,bytes: PackedByteArray) -> String:
	return path.path_join("blobs").path_join(hash_of(bytes).hex_encode()+".tfrg")

func checkpoint_file(path: String,id: PackedByteArray) -> String:
	return path.path_join("checkpoints").path_join(id.hex_encode()+".tfrc")

func collect(store: RefCounted) -> bool:
	for i in range(200):
		var result: Dictionary = store.collect_garbage(1)
		if not result.ok or result.inspected>1: return false
		if result.complete: return true
	return false

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size()==3 and args[0]=="--checkpoint-child":
		child(args[1],args[2].hex_decode())
		return
	base=ProjectSettings.globalize_path("res://reports/rcp_%d_%d" % [OS.get_process_id(),Time.get_ticks_msec()])
	DirAccess.make_dir_recursive_absolute(base)
	for i in range(20):
		var world: Node3D = ClassDB.instantiate("NativeBlockWorld")
		world.set_cells(PackedInt32Array([1,i,0,1]))
		packets.append(world.capture_region(Vector3i.ZERO))
		world.free()
	check_retention()
	check_capacity()
	check_corruption()
	check_upgrade()
	check_pin_io_failure()
	check_async()
	var file := FileAccess.open("res://reports/block_region_checkpoints.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"scope":"Persistent checkpoint references and garbage-collection protection; not integrated whole-world roots or physical crash certification."},"  "))
	file.close()
	quit(1 if failures else 0)

func check_retention() -> void:
	var path := folder("retention")
	var store: RefCounted = ClassDB.instantiate("NativeBlockRegionStore")
	check(not store.pin_checkpoint().ok and store.list_checkpoints().is_empty(),"closed catalog cannot create checkpoint references")
	check(store.open_store(path).ok and FileAccess.file_exists(path.path_join("checkpoints.tfcp")),"store initializes committed retention metadata")
	check(not store.activate_checkpoint(empty).ok and not store.release_checkpoint(empty).ok and not store.read_checkpoint_region(empty,Vector3i.ZERO).ok,"checkpoint APIs reject malformed identities")
	store.publish_region(packets[0],empty)
	var pin: Dictionary = store.pin_checkpoint()
	check(pin.ok and pin.checkpoint.size()==32 and store.stats().checkpoints==1,"current catalog is published as a pinned immutable checkpoint")
	var id: PackedByteArray = pin.checkpoint
	check(store.pin_checkpoint().checkpoint==id and store.pin_checkpoint().unchanged and store.stats().checkpoints==1,"pinning the same catalog is idempotent")
	check(store.list_checkpoints()==id and store.checkpoint_regions(id).keys==PackedInt32Array([0,0,0]),"checkpoint index exposes stable identities and region keys")
	store.publish_region(packets[1],hash_of(packets[0]))
	store.publish_region(packets[2],hash_of(packets[1]))
	check(collect(store) and FileAccess.file_exists(blob(path,packets[0])) and store.read_checkpoint_region(id,Vector3i.ZERO).bytes==packets[0],"pinned old region survives publication beyond current and backup revisions")
	check(store.read_region(Vector3i.ZERO).bytes==packets[2],"reading checkpoint data does not change active catalog")
	store.close()
	var output: Array = []
	var code := OS.execute(OS.get_executable_path(),PackedStringArray(["--headless","--path",ProjectSettings.globalize_path("res://"),"--script","res://tests/block_region_checkpoints.gd","--quit-after","120","--","--checkpoint-child",path,id.hex_encode()]),output,true,false)
	for line in output: print(line)
	var report = JSON.parse_string(FileAccess.get_file_as_string(path.path_join("child.json")))
	check(code==0 and report is Dictionary and report.get("pass",false),"fresh engine process preserves and reads a pinned historical region after collection")
	check(store.open_store(path).ok and store.read_checkpoint_region(id,Vector3i.ZERO).bytes==packets[0],"pin survives lease release and reopen")
	var before: int = store.stats().generation
	check(store.activate_checkpoint(id).ok and store.stats().generation>before and store.read_region(Vector3i.ZERO).bytes==packets[0],"checkpoint activation publishes its catalog as a newer revision")
	check(store.stats().checkpoints==1,"activation retains checkpoint for its referencing save")
	store.publish_region(packets[3],hash_of(packets[0]))
	store.publish_region(packets[4],hash_of(packets[3]))
	check(store.release_checkpoint(id).ok and store.list_checkpoints().is_empty() and not store.read_checkpoint_region(id,Vector3i.ZERO).ok,"explicit release removes the pin and disables further checkpoint reads")
	check(collect(store) and not FileAccess.file_exists(blob(path,packets[0])) and not FileAccess.file_exists(checkpoint_file(path,id)),"released old data becomes collectible after it leaves current and backup")
	check(not store.release_checkpoint(id).ok and not store.activate_checkpoint(id).ok,"released checkpoint cannot be silently reactivated")
	store.close()

func child(path: String,id: PackedByteArray) -> void:
	var store: RefCounted = ClassDB.instantiate("NativeBlockRegionStore")
	var ok: bool = store.open_store(path).ok
	if ok:
		ok=collect(store) and store.list_checkpoints()==id
		var read: Dictionary = store.read_checkpoint_region(id,Vector3i.ZERO)
		var current: Dictionary = store.read_region(Vector3i.ZERO)
		ok=ok and read.ok and current.ok and read.bytes!=current.bytes
		var world: Node3D = ClassDB.instantiate("NativeBlockWorld")
		ok=ok and world.restore_region(read.bytes,world.capture_region(Vector3i.ZERO)) and world.get_cell(Vector3i(1,0,0))==1 and world.get_cell(Vector3i(1,2,0))==0
		world.free()
	store.close()
	write(path.path_join("child.json"),JSON.stringify({"pass":ok}).to_utf8_buffer())
	print("PASS " if ok else "FAIL ","fresh process checkpoint retention")
	quit(0 if ok else 1)

func check_capacity() -> void:
	var path := folder("capacity")
	var store: RefCounted = ClassDB.instantiate("NativeBlockRegionStore")
	store.open_store(path)
	var ids: Array[PackedByteArray] = []
	var previous := empty
	var ok := true
	for i in range(16):
		ok=store.publish_region(packets[i],previous).ok and ok
		var result: Dictionary = store.pin_checkpoint()
		ok=ok and result.ok
		ids.append(result.checkpoint)
		previous=hash_of(packets[i])
	check(ok and store.stats().checkpoints==16 and store.stats().pinned_unique_blobs==16,"checkpoint count is explicitly bounded to sixteen")
	store.publish_region(packets[16],previous)
	var before := FileAccess.get_file_as_bytes(path.path_join("checkpoints.tfcp"))
	check(not store.pin_checkpoint().ok and FileAccess.get_file_as_bytes(path.path_join("checkpoints.tfcp"))==before,"seventeenth checkpoint rejection preserves all existing references")
	check(collect(store) and FileAccess.file_exists(blob(path,packets[0])),"capacity does not evict the oldest pinned save")
	check(store.release_checkpoint(ids[0]).ok and store.pin_checkpoint().ok and store.stats().checkpoints==16,"explicitly releasing a save reference permits another checkpoint")
	check(collect(store) and not FileAccess.file_exists(blob(path,packets[0])) and FileAccess.file_exists(blob(path,packets[1])),"releasing one checkpoint leaves other pinned regions retained")
	store.close()
	check(store.open_store(path).ok and store.stats().checkpoints==16,"full checkpoint index validates after reopening")
	store.close()
	# Different catalogs may reference the same immutable region. Removing one
	# reference must not let collection discard the other checkpoint's data.
	path=folder("shared")
	store.open_store(path)
	store.publish_region(packets[0],empty)
	var first: PackedByteArray = store.pin_checkpoint().checkpoint
	var world: Node3D = ClassDB.instantiate("NativeBlockWorld")
	world.set_cells(PackedInt32Array([-1,0,0,1]))
	var other: PackedByteArray = world.capture_region(Vector3i(-1,0,0))
	world.free()
	store.publish_region(other,empty)
	var second: PackedByteArray = store.pin_checkpoint().checkpoint
	store.publish_region(packets[1],hash_of(packets[0]))
	store.publish_region(packets[2],hash_of(packets[1]))
	store.release_checkpoint(first)
	check(collect(store) and store.read_checkpoint_region(second,Vector3i.ZERO).bytes==packets[0],"shared blob reference counts preserve other checkpoints when one is released")
	store.activate_checkpoint(second)
	check(store.list_regions()==PackedInt32Array([-1,0,0,0,0,0]),"activation restores the checkpoint's complete signed region index")
	store.close()

func check_corruption() -> void:
	var path := folder("corruption")
	var store: RefCounted = ClassDB.instantiate("NativeBlockRegionStore")
	store.open_store(path)
	store.publish_region(packets[0],empty)
	var id: PackedByteArray = store.pin_checkpoint().checkpoint
	var index := FileAccess.get_file_as_bytes(path.path_join("checkpoints.tfcp"))
	write(path.path_join("checkpoints.tfcp"),PackedByteArray([1]))
	check(not store.publish_region(packets[1],hash_of(packets[0])).ok and not store.collect_garbage(1).ok and not store.release_checkpoint(id).ok and not store.pin_checkpoint().ok,"out-of-owner retention edits stop publication, collection and pin mutations")
	store.close()
	check(not store.open_store(path).ok and not store.open_store(path,true).ok,"corrupt pin index cannot be bypassed by catalog backup recovery")
	write(path.path_join("checkpoints.tfcp"),index)
	var file := checkpoint_file(path,id)
	var bytes := FileAccess.get_file_as_bytes(file)
	write(file,PackedByteArray([1]))
	check(not store.open_store(path).ok,"corrupt checkpoint catalog prevents opening rather than losing retention")
	write(file,bytes)
	DirAccess.remove_absolute(path.path_join("checkpoints.tfcp"))
	check(not store.open_store(path).ok,"missing retention index with checkpoint files is not inferred as empty")
	write(path.path_join("checkpoints.tfcp"),index)
	for variant in range(4):
		var malformed := index.slice(0,index.size()-32)
		match variant:
			0: malformed.encode_u32(8,17)
			1: malformed[0]^=1
			2:
				malformed.encode_u32(8,2)
				malformed.append_array(id)
			3: malformed.append(7)
		malformed.append_array(sha(malformed))
		write(path.path_join("checkpoints.tfcp"),malformed)
		check(not store.open_store(path).ok,"checksummed malformed retention index rejected case %d" % variant)
	write(path.path_join("checkpoints.tfcp"),index)
	check(store.open_store(path).ok,"restoring exact metadata recovers the store")
	write(blob(path,packets[0]),PackedByteArray([7]))
	check(not store.read_checkpoint_region(id,Vector3i.ZERO).ok and collect(store) and FileAccess.file_exists(blob(path,packets[0])),"checkpoint read validates blob integrity and collection preserves corrupt referenced data")
	store.close()

func check_upgrade() -> void:
	var path := folder("legacy")
	var store: RefCounted = ClassDB.instantiate("NativeBlockRegionStore")
	store.open_store(path)
	store.publish_region(packets[0],empty)
	store.close()
	var catalog := FileAccess.get_file_as_bytes(path.path_join("catalog.tfrc"))
	var legacy := catalog.slice(0,catalog.size()-32)
	legacy[4]=1
	legacy.append_array(sha(legacy))
	write(path.path_join("catalog.tfrc"),legacy)
	DirAccess.remove_absolute(path.path_join("checkpoints.tfcp"))
	check(store.open_store(path).ok and store.read_region(Vector3i.ZERO).bytes==packets[0],"legacy v1 catalog initializes retention metadata without changing authored bytes")
	var pin: Dictionary = store.pin_checkpoint()
	check(pin.ok and FileAccess.get_file_as_bytes(path.path_join("catalog.tfrc"))[4]==2,"first legacy checkpoint upgrades active catalog so old readers reject normal opening")
	store.close()
	path=folder("missing_empty_index")
	store.open_store(path)
	store.close()
	DirAccess.remove_absolute(path.path_join("checkpoints.tfcp"))
	check(not store.open_store(path).ok,"v2 catalog requires retention metadata even when checkpoint folder is empty")

func check_pin_io_failure() -> void:
	var path := folder("pin_io_failure")
	var store: RefCounted = ClassDB.instantiate("NativeBlockRegionStore")
	store.open_store(path)
	store.publish_region(packets[0],empty)
	var before := FileAccess.get_file_as_bytes(path.path_join("checkpoints.tfcp"))
	var expected := sha(FileAccess.get_file_as_bytes(path.path_join("catalog.tfrc")))
	# Windows FileAccess retains an open handle without delete sharing. Reads
	# still work, but atomic replacement must fail until the reader closes.
	var guard := FileAccess.open(path.path_join("checkpoints.tfcp"),FileAccess.READ)
	var pin: Dictionary = store.pin_checkpoint()
	check(not pin.ok and store.list_checkpoints().is_empty() and FileAccess.get_file_as_bytes(path.path_join("checkpoints.tfcp"))==before and FileAccess.file_exists(checkpoint_file(path,expected)),"failed retention-index replacement leaves no pin and only an uncommitted catalog file")
	guard.close()
	pin=store.pin_checkpoint()
	check(pin.ok and pin.checkpoint==expected,"retry adopts only an exactly matching uncommitted checkpoint file")
	guard=FileAccess.open(path.path_join("checkpoints.tfcp"),FileAccess.READ)
	check(not store.release_checkpoint(expected).ok and store.list_checkpoints()==expected and FileAccess.file_exists(checkpoint_file(path,expected)),"failed checkpoint release preserves both the reference and immutable catalog")
	guard.close()
	check(store.release_checkpoint(expected).ok,"checkpoint release succeeds after filesystem obstruction clears")
	store.close()

func wait_results(io: RefCounted,count: int) -> Array:
	var results: Array = []
	var deadline := Time.get_ticks_msec()+15000
	while results.size()<count and Time.get_ticks_msec()<deadline:
		results.append_array(io.poll(mini(64,count-results.size())))
		if results.size()<count: OS.delay_msec(1)
	return results

func check_async() -> void:
	var io: RefCounted = ClassDB.instantiate("NativeBlockRegionIO")
	io.start(folder("async"),16,8*1024*1024)
	var result := wait_results(io,1)
	check(result.size()==1 and result[0].ok,"background worker opens checkpoint-capable store")
	check(io.checkpoint_regions(empty)==0 and io.read_checkpoint_region(empty,Vector3i.ZERO)==0 and io.activate_checkpoint(empty)==0 and io.release_checkpoint(empty)==0,"queue checks checkpoint identity lengths before admission")
	io.publish_regions([packets[0]],[empty])
	var ticket: int = io.pin_checkpoint()
	result=wait_results(io,2)
	check(result.size()==2 and result[0].ok and result[1].ok and result[1].ticket==ticket,"FIFO checkpoint is captured after its queued publication")
	var id: PackedByteArray = result[1].checkpoint
	io.publish_regions([packets[1]],[hash_of(packets[0])])
	io.publish_regions([packets[2]],[hash_of(packets[1])])
	io.collect_garbage(256)
	io.read_checkpoint_region(id,Vector3i.ZERO)
	io.checkpoint_regions(id)
	io.list_checkpoints()
	result=wait_results(io,6)
	check(result.size()==6 and result[3].ok and result[3].bytes==packets[0] and result[4].keys==PackedInt32Array([0,0,0]) and result[5].checkpoints==id,"background checkpoint queries retain the saved version through later writes and cleanup")
	io.activate_checkpoint(id)
	io.read_region(Vector3i.ZERO)
	io.release_checkpoint(id)
	io.list_checkpoints()
	io.join()
	result=io.poll(64)
	check(result.size()==4 and result[0].ok and result[1].bytes==packets[0] and result[2].ok and result[3].checkpoints.is_empty(),"shutdown drains checkpoint activation/read/release operations in order")
	check(io.stats().outstanding==0 and io.stats().reserved_bytes==0,"checkpoint completions release all queue reservations")
