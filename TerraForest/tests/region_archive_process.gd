extends SceneTree
var path := ""
var mode := ""
var raw: RefCounted
var codec: RefCounted
var archive: RefCounted
const ASSET := "process/marker/v1"

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--archive-path="): path=arg.trim_prefix("--archive-path=")
		if arg.begins_with("--archive-mode="): mode=arg.trim_prefix("--archive-mode=")
	run.call_deferred()

func structures(revision: int) -> PackedByteArray:
	var world: Node3D = ClassDB.instantiate("NativeBlockWorld")
	world.set_cells(PackedInt32Array([-65,revision%128,0,1,64,0,revision%128,2]))
	var model: Node3D = ClassDB.instantiate("NativeStaticBatch")
	model.configure_asset(ASSET,BoxMesh.new())
	model.upsert_instances(PackedInt64Array([7000000001]),PackedFloat32Array([1,0,0,revision,0,1,0,0,0,0,1,0]))
	var bytes: PackedByteArray = codec.encode(world.capture_snapshot(),{ASSET:model.capture_snapshot()})
	world.free()
	model.free()
	return bytes

func snapshot(revision: int) -> PackedByteArray:
	var terrain := PackedByteArray()
	terrain.resize(8*1024*1024)
	terrain.fill(revision%251)
	terrain.encode_u32(0,revision)
	var water := PackedByteArray()
	water.resize(8)
	water.encode_u64(0,revision)
	return archive.encode({"terrain":terrain,"volumetric_water":water,"structures":structures(revision)})

func inspect(file: String) -> Dictionary:
	var bytes: PackedByteArray = archive.read(file)
	var disk: Dictionary = raw.decode(bytes)
	var restored: Dictionary = archive.decode(bytes)
	if not disk.get("ok",false) or not restored.get("ok",false): return {"ok":false}
	var reference: Dictionary = codec.decode_reference(disk.sections.structures)
	if not reference.ok: return {"ok":false}
	var terrain: PackedByteArray = restored.sections.terrain
	if terrain.size()!=8*1024*1024: return {"ok":false}
	var revision := terrain.decode_u32(0)
	var water: PackedByteArray = restored.sections.volumetric_water
	var expected := PackedByteArray()
	expected.resize(terrain.size())
	expected.fill(revision%251)
	expected.encode_u32(0,revision)
	return {"ok":terrain==expected and water.size()==8 and water.decode_u64(0)==revision and restored.sections.structures==structures(revision),"revision":revision}

func run() -> void:
	GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
	GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	raw=ClassDB.instantiate("NativeWorldArchive")
	codec=ClassDB.instantiate("NativeStructuresSnapshot")
	codec.configure_assets(PackedStringArray([ASSET]))
	archive=ClassDB.instantiate("NativeRegionWorldArchive")
	if not archive.configure(raw,codec):
		quit(2)
		return
	if mode=="probe":
		var store: RefCounted = ClassDB.instantiate("NativeBlockRegionStore")
		var ok: bool = not archive.acquire(path) and not store.open_store(path+".regions").ok
		store.close()
		print("PROBE_OK" if ok else "PROBE_FAIL")
		quit(0 if ok else 3)
		return
	if not archive.acquire(path):
		print("ACQUIRE_FAIL")
		quit(4)
		return
	if mode=="verify":
		var current := inspect(path)
		var backup := inspect(path+".bak")
		var ok: bool = current.ok and backup.ok
		if ok: ok=int(backup.revision)<=int(current.revision)
		var next := int(current.get("revision",0))+1
		for i in range(3):
			ok=ok and archive.publish(path,snapshot(next+i))==OK
		var after := inspect(path)
		var after_backup := inspect(path+".bak")
		ok=ok and after.ok and after_backup.ok and after.get("revision",-1)==next+2 and after_backup.get("revision",-1)==next+1 and archive.storage_stats().checkpoints<=2
		archive.release()
		var file := FileAccess.open(path+".verification.json",FileAccess.WRITE)
		file.store_string(JSON.stringify({"pass":ok,"before":current,"backup_before":backup,"after":after,"backup_after":after_backup},"  "))
		file.close()
		print("RECOVERY_OK" if ok else "RECOVERY_FAIL")
		quit(0 if ok else 5)
		return
	if mode!="writer":
		archive.release()
		quit(6)
		return
	for i in range(2):
		if archive.publish(path,snapshot(i))!=OK:
			archive.release()
			quit(7)
			return
	print("WRITER_READY")
	# Parent first verifies both independent leases, then permits continued saves.
	while not FileAccess.file_exists(path+".continue"):
		await process_frame
	var revision := 2
	while true:
		if archive.publish(path,snapshot(revision))!=OK:
			print("WRITE_FAIL")
			archive.release()
			quit(8)
			return
		revision+=1
		await process_frame
