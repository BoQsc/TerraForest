extends SceneTree
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

func run() -> void:
	var path := ProjectSettings.globalize_path("res://reports/root_%d_%d" % [OS.get_process_id(),Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(path)
	var store: RefCounted = ClassDB.instantiate("NativeBlockRegionStore")
	var world: Node3D = ClassDB.instantiate("NativeBlockWorld")
	var empty: PackedByteArray = world.capture_snapshot()
	world.set_cells(PackedInt32Array([-65,0,0,1,-1,0,0,2,0,0,0,3,64,0,0,4]))
	var original: PackedByteArray = world.capture_snapshot()
	check(not store.publish_block_snapshot(original).ok,"closed store rejects whole-block conversion")
	check(store.open_store(path).ok and store.publish_block_snapshot(original).ok,"complete snapshot splits into committed native regions")
	check(store.list_regions()==PackedInt32Array([-2,0,0,-1,0,0,0,0,0,1,0,0]),"split uses signed floor region coordinates")
	var id: PackedByteArray = store.pin_checkpoint().checkpoint
	check(store.read_block_checkpoint(id).blocks==original,"checkpoint reconstructs byte-exact canonical block snapshot")
	var generation: int = store.stats().generation
	check(store.publish_block_snapshot(original).unchanged and store.stats().generation==generation,"identical complete snapshot avoids catalog revision churn")
	var corrupt := original.duplicate()
	corrupt[0]^=1
	check(not store.publish_block_snapshot(corrupt).ok and store.stats().generation==generation,"invalid complete snapshot preserves active catalog")
	world.restore_snapshot(empty)
	world.set_cells(PackedInt32Array([64,0,0,6]))
	var newer: PackedByteArray = world.capture_snapshot()
	check(store.publish_block_snapshot(newer).ok and store.list_regions()==PackedInt32Array([1,0,0]),"replacement snapshot removes regions absent from newer state")
	check(store.read_block_checkpoint(id).blocks==original,"replacement does not change pinned previous snapshot")
	check(store.publish_block_snapshot(empty).ok and store.list_regions().is_empty(),"empty snapshot clears active region index")
	var empty_id: PackedByteArray = store.pin_checkpoint().checkpoint
	check(store.read_block_checkpoint(empty_id).blocks==empty,"empty checkpoint reconstructs valid empty block encoding")
	store.close()
	check(store.open_store(path).ok and store.read_block_checkpoint(id).blocks==original,"complete reconstruction survives store reopening")
	var codec: RefCounted = ClassDB.instantiate("NativeStructuresSnapshot")
	codec.configure_assets(PackedStringArray())
	var reference: PackedByteArray = codec.encode_reference(id,{})
	var decoded: Dictionary = codec.decode_reference(reference)
	check(not reference.is_empty() and decoded.ok and decoded.checkpoint==id and decoded.models.is_empty(),"native reference bundle carries exact checkpoint identity")
	check(not codec.validate_snapshot(reference) and not codec.decode(reference).ok,"reference cannot be mistaken for resident building snapshot")
	check(not codec.decode_reference(codec.encode(original,{})).ok,"resident bundle is not interpreted as checkpoint reference")
	check(codec.encode_reference(PackedByteArray([1]),{}).is_empty(),"reference encoding rejects invalid identity length")
	corrupt=reference.duplicate()
	corrupt[20]^=1
	check(not codec.decode_reference(corrupt).ok,"reference checksum protects checkpoint identity")
	var models: Node3D = ClassDB.instantiate("NativeStaticBatch")
	check(models.configure_asset("architecture/test/v1",BoxMesh.new()),"reference model fixture binds an asset")
	var model_bytes: PackedByteArray = models.capture_snapshot()
	codec=ClassDB.instantiate("NativeStructuresSnapshot")
	codec.configure_assets(PackedStringArray(["architecture/test/v1"]))
	reference=codec.encode_reference(id,{"architecture/test/v1":model_bytes})
	decoded=codec.decode_reference(reference)
	check(decoded.ok and decoded.models["architecture/test/v1"]==model_bytes,"reference preserves model snapshot and asset binding")
	var rebuilt: PackedByteArray = codec.encode(store.read_block_checkpoint(decoded.checkpoint).blocks,decoded.models)
	check(codec.validate_snapshot(rebuilt) and codec.decode(rebuilt).blocks==original,"checkpoint and model reference reconstruct ordinary validated structure bundle")
	var wrong: RefCounted = ClassDB.instantiate("NativeStructuresSnapshot")
	wrong.configure_assets(PackedStringArray())
	check(not wrong.decode_reference(reference).ok,"unknown referenced model asset rejects before restore")
	models.free()
	world.free()
	store.close()
	check_adapter(path.path_join("world.trw"),original,newer,empty)
	var file := FileAccess.open("res://reports/region_world_archive.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"scope":"Native complete-block conversion and checkpoint-reference codec; world-file adapter integration pending."},"  "))
	file.close()
	quit(1 if failures else 0)

func check_adapter(path: String,original: PackedByteArray,newer: PackedByteArray,empty: PackedByteArray) -> void:
	var raw: RefCounted = ClassDB.instantiate("NativeWorldArchive")
	var codec: RefCounted = ClassDB.instantiate("NativeStructuresSnapshot")
	codec.configure_assets(PackedStringArray())
	var adapter: RefCounted = ClassDB.instantiate("NativeRegionWorldArchive")
	check(adapter.configure(raw,codec) and not adapter.configure(raw,codec),"region archive configuration is immutable")
	check(adapter.acquire(path),"region archive owns world root and sibling region directory")
	var competing: RefCounted = ClassDB.instantiate("NativeWorldArchive")
	check(not competing.acquire(path),"region archive retains canonical world lease")
	var sections := {"terrain":PackedByteArray([1,2,3]),"water":PackedByteArray([8,9]),"structures":codec.encode(original,{})}
	var first: PackedByteArray = adapter.encode(sections)
	check(adapter.publish(path,first)==OK,"adapter commits regions and pin before world root")
	var disk: PackedByteArray = adapter.read(path)
	var root: Dictionary = raw.decode(disk)
	check(root.ok and codec.decode_reference(root.sections.structures).ok and root.sections.terrain==sections.terrain and root.sections.water==sections.water,"world root stores reference while other sections remain exact")
	var restored: Dictionary = adapter.decode(disk)
	check(restored.ok and restored.sections.structures==sections.structures,"adapter reconstructs complete scene-compatible structures")
	sections.structures=codec.encode(newer,{})
	sections.terrain=PackedByteArray([4,5,6])
	check(adapter.publish(path,adapter.encode(sections))==OK,"second compound save publishes new checkpoint and terrain")
	check(adapter.decode(adapter.read(path+".bak")).sections.structures==codec.encode(original,{}),"world backup retains matching historical building checkpoint")
	var ok := true
	for i in range(24):
		sections.structures=codec.encode(original if i%2==0 else newer,{})
		ok=adapter.publish(path,adapter.encode(sections))==OK and ok
		ok=adapter.storage_stats().checkpoints<=2 and ok
	check(ok,"24 additional saves retire only unreferenced pins without exhausting checkpoint capacity")
	var before: PackedByteArray = adapter.read(path)
	# Holding the canonical root denies replacement while allowing readback.
	var guard := FileAccess.open(path,FileAccess.READ)
	sections.structures=codec.encode(empty,{})
	check(adapter.publish(path,adapter.encode(sections))!=OK and adapter.read(path)==before,"failed world-root replacement preserves prior canonical file")
	check(adapter.decode(adapter.read(path)).ok and adapter.decode(adapter.read(path+".bak")).ok,"failed publication leaves both actual roots reconstructible")
	guard.close()
	check(adapter.publish(path,adapter.encode(sections))==OK and adapter.storage_stats().checkpoints<=2,"save retries after failed publication and retires orphan pin")
	adapter.release()
	check(competing.acquire(path),"release relinquishes canonical root lease")
	competing.release()
	check(adapter.acquire(path) and adapter.decode(adapter.read(path)).sections.structures==codec.encode(empty,{}),"reopen reconstructs committed empty structure snapshot")
	var corrupt: PackedByteArray = adapter.read(path)
	corrupt[20]^=1
	check(not adapter.decode(corrupt).ok,"corrupt root never produces restored addon state")
	adapter.release()
