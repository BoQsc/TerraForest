# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func pose(x: float) -> PackedFloat32Array:
	return PackedFloat32Array([1,0,0,x,0,1,0,0,0,0,1,0])
func hash_of(bytes: PackedByteArray) -> PackedByteArray: return bytes.slice(bytes.size()-32)
func write(path: String,bytes: PackedByteArray) -> void:
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(bytes);file.close()
func cleanup(path: String) -> void:
	for name in DirAccess.get_directories_at(path): cleanup(path.path_join(name))
	for name in DirAccess.get_files_at(path): DirAccess.remove_absolute(path.path_join(name))
	DirAccess.remove_absolute(path)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	var args:=OS.get_cmdline_user_args()
	if args.size()==4 and args[0]=="--reopen-model":
		var reopened=ClassDB.instantiate("NativeModelRegionStore")
		var ok: bool=reopened.open_store(args[1],"test/asset").ok
		if ok:
			var current: Dictionary=reopened.read_region(Vector3i.ZERO)
			var old: Dictionary=reopened.read_checkpoint_region(args[3].hex_decode(),Vector3i.ZERO)
			ok=current.ok and old.ok and hash_of(current.bytes).hex_encode()==args[2] and current.bytes!=old.bytes
		reopened.close();quit(0 if ok else 1);return
	var folder:=ProjectSettings.globalize_path("user://model_catalog_"+str(OS.get_process_id())+"_"+str(Time.get_ticks_usec()))
	DirAccess.make_dir_recursive_absolute(folder)
	var batch=ClassDB.instantiate("NativeStaticBatch");batch.configure_collision_only()
	batch.configure_asset("test/asset",BoxMesh.new())
	batch.upsert_instances(PackedInt64Array([1,2]),pose(1)+pose(-1))
	var original: PackedByteArray=batch.capture_region(Vector3i.ZERO)
	var negative: PackedByteArray=batch.capture_region(Vector3i(-1,0,0))
	var store=ClassDB.instantiate("NativeModelRegionStore")
	check(store.open_store(folder,"test/asset").ok,"new asset-bound model catalog opens")
	var rival=ClassDB.instantiate("NativeModelRegionStore")
	check(not rival.open_store(folder,"test/asset").ok,"second writer cannot acquire directory lease")
	check(store.publish_regions([original,negative],[PackedByteArray(),PackedByteArray()]).ok,"atomic publication admits two signed model regions")
	check(store.read_region(Vector3i.ZERO).bytes==original,"catalog reads exact checked model packet")
	var generation: int=store.stats().generation
	check(store.publish_region(original,hash_of(original)).ok and store.stats().generation==generation,"unchanged publication avoids generation churn")
	var pin: Dictionary=store.pin_checkpoint()
	check(pin.ok,"model catalog checkpoint pins old region versions")
	var checkpoint: PackedByteArray=pin.checkpoint
	batch.upsert_instances(PackedInt64Array([1]),pose(5))
	var newer: PackedByteArray=batch.capture_region(Vector3i.ZERO)
	check(not store.publish_region(newer,PackedByteArray()).ok,"stale expected checksum cannot overwrite committed region")
	check(store.publish_region(newer,hash_of(original)).ok,"matching expected checksum publishes new model version")
	check(store.read_checkpoint_region(checkpoint,Vector3i.ZERO).bytes==original,"checkpoint retains earlier packet after edit")
	var foreign=ClassDB.instantiate("NativeStaticBatch");foreign.configure_collision_only();foreign.configure_asset("test/other",BoxMesh.new())
	var wrong: PackedByteArray=foreign.capture_region(Vector3i(1,0,0))
	check(not store.publish_regions([negative,wrong],[hash_of(negative),PackedByteArray()]).ok and store.stats().regions==2,"mixed-asset batch rejects without partial publication")
	foreign.free()
	var block=ClassDB.instantiate("NativeBlockWorld")
	check(not store.publish_region(block.capture_region(Vector3i(3,0,0)),PackedByteArray()).ok,"model catalog rejects block packets")
	block.free()
	check(store.remove_region(Vector3i(-1,0,0),hash_of(negative)).ok,"conditional removal commits region deletion")
	var collected:=true
	for i in 10:
		var result: Dictionary=store.collect_garbage(1)
		collected=collected and result.ok and result.inspected<=1
	check(collected and store.read_checkpoint_region(checkpoint,Vector3i(-1,0,0)).bytes==negative,"bounded collection preserves checkpoint-only region")
	store.close()
	var child_output: Array=[]
	var child:=OS.execute(OS.get_executable_path(),["--headless","--path",ProjectSettings.globalize_path("res://"),"--script","res://tests/model_region_store.gd","--","--reopen-model",folder,hash_of(newer).hex_encode(),checkpoint.hex_encode()],child_output,true)
	check(child==0,"separate engine process reopens current and checkpoint model versions")
	check(not rival.open_store(folder,"test/other").ok,"reopening under another asset identity fails")
	var blocks=ClassDB.instantiate("NativeBlockRegionStore")
	check(not blocks.open_store(folder).ok,"block catalog reader rejects model catalog format")
	check(store.open_store(folder,"test/asset").ok and store.read_region(Vector3i.ZERO).bytes==newer,"disk reopen restores committed model version")
	check(store.read_checkpoint_region(checkpoint,Vector3i.ZERO).bytes==original,"checkpoint retention survives disk reopen")
	check(store.activate_checkpoint(checkpoint).ok and store.read_region(Vector3i(-1,0,0)).bytes==negative,"checkpoint activation restores deleted region")
	check(batch.unload_region(newer),"live collection unloads its captured version")
	check(not batch.restore_region(store.read_region(Vector3i.ZERO).bytes),"older checkpoint cannot overwrite live unloaded version")
	check(store.publish_region(newer,hash_of(original)).ok and batch.restore_region(store.read_region(Vector3i.ZERO).bytes),"committed matching packet restores live unloaded records")
	var blob:=folder.path_join("blobs").path_join(hash_of(newer).hex_encode()+".tfrg")
	write(blob,PackedByteArray([1,2,3]))
	check(not store.read_region(Vector3i.ZERO).ok,"corrupt immutable blob is detected on read")
	check(not store.publish_region(newer,hash_of(newer)).ok,"publication refuses to overwrite corrupted immutable data")
	write(blob,newer)
	store.close()
	write(folder.path_join("catalog.tfrc"),PackedByteArray([1,2,3]))
	check(not store.open_store(folder,"test/asset").ok,"corrupt primary catalog requires explicit recovery")
	check(store.open_store(folder,"test/asset",true).ok and store.read_region(Vector3i.ZERO).bytes==original,"explicit backup recovery reads prior committed catalog")
	check(store.publish_region(newer,hash_of(original)).ok,"recovered catalog can publish a new commit")
	check(store.release_checkpoint(checkpoint).ok,"checkpoint release is explicit")
	store.close();batch.free()
	cleanup(folder)
	DirAccess.make_dir_recursive_absolute("res://reports")
	var report:=FileAccess.open("res://reports/model_region_store.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures}));report.close()
	print("MODEL_REGION_STORE checks=",checks," failures=",failures)
	quit(1 if failures else 0)
