# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func pose(x: float) -> PackedFloat32Array:
	return PackedFloat32Array([1,0,0,x,0,1,0,0,0,0,1,0])
func _initialize() -> void: run.call_deferred()
func run() -> void:
	GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	var batch: Node3D=ClassDB.instantiate("NativeStaticBatch");root.add_child(batch)
	batch.configure_collision_only() # Cold region fixture: no resident render pages.
	var mesh:=BoxMesh.new();batch.configure_asset("test/owned",mesh)
	var history: RefCounted=ClassDB.instantiate("NativeStaticHistory");history.configure([batch],1048576,256)
	var id: int=history.insert(batch,pose(1),AABB())
	check(id>0 and batch.set_removal_protected(id,true),"placement owner enables removal protection")
	check(batch.set_removal_protected(id,true) and batch.is_removal_protected(id),"protection is idempotent")
	check(not batch.set_removal_protected(0,true) and not batch.set_removal_protected(999,true),"invalid or unknown placement cannot be protected")
	var before: PackedByteArray=batch.capture_snapshot()
	var undo_before: int=history.stats().undo_steps
	check(not history.undo(AABB()) and batch.capture_snapshot()==before and history.stats().undo_steps==undo_before,"undo cannot delete protected insertion or consume history")
	check(not history.erase(batch,id) and batch.capture_snapshot()==before,"journal removal respects ownership")
	var other: int=history.insert(batch,pose(64),AABB())
	before=batch.capture_snapshot()
	check(not batch.remove_instances(PackedInt64Array([other,id])) and batch.capture_snapshot()==before,"mixed removal preflights all IDs before deleting any")
	check(history.undo(AABB()) and batch.get_instance(other).is_empty(),"unrelated unprotected insertion can still be undone")
	check(history.redo(AABB()) and not batch.get_instance(other).is_empty(),"unrelated redo remains available")
	check(history.update(batch,id,pose(3),AABB()) and batch.is_removal_protected(id),"movement retains protected identity")
	check(history.undo(AABB()) and batch.get_instance(id)==pose(1),"transform undo retains protected contents owner")
	before=batch.capture_snapshot()
	check(not batch.set_instances(mesh,pose(9)) and batch.capture_snapshot()==before,"legacy bulk replacement cannot reassign owned IDs")
	check(not batch.restore_snapshot(before) and batch.capture_snapshot()==before,"whole snapshot restore requires explicit ownership handoff")
	var packet: PackedByteArray=batch.capture_region(Vector3i.ZERO)
	check(batch.unload_region(packet) and batch.is_removal_protected(id) and batch.get_instance(id).is_empty(),"stream retirement preserves ownership while releasing placement residency")
	check(batch.set_removal_protected(id,true),"unloaded reserved identity remains protectable")
	check(not batch.upsert_instances(PackedInt64Array([id]),pose(128)),"unloaded protected identity cannot be stolen")
	check(batch.restore_region(packet) and batch.is_removal_protected(id),"stream admission restores placement with ownership intact")
	check(not batch.remove_instances(PackedInt64Array([id])),"restored protected placement still rejects deletion")
	check(batch.begin_region_retirement(packet),"incremental retirement accepts protected cold region")
	check(not batch.set_removal_protected(id,false),"ownership cannot be released during an active region transfer")
	var progress: Dictionary=batch.region_admission_stats()
	for step in 128:
		if not progress.active:break
		progress=batch.advance_region_retirement(1,1024,500)
	check(not progress.active and not batch.is_region_loaded(Vector3i.ZERO) and batch.is_removal_protected(id),"incremental retirement retains ownership after freeing resident records")
	check(batch.begin_region_admission(packet),"incremental admission accepts protected reserved identity")
	progress=batch.region_admission_stats()
	for step in 128:
		if not progress.active:break
		progress=batch.advance_region_admission(1,1024,500)
	check(not progress.active and batch.capture_snapshot()==before and batch.is_removal_protected(id),"incremental admission restores exact geometry and preserves ownership")
	check(not batch.remove_instances(PackedInt64Array([id])),"incrementally restored placement rejects deletion")
	# Generate real immutable metadata, then exercise replacement entry points.
	var store: RefCounted=ClassDB.instantiate("NativeModelRegionStore")
	var path:=ProjectSettings.globalize_path("res://reports/model_protection_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(path)
	check(store.open_store(path,"test/owned").ok and store.publish_snapshot(before).ok,"fixture publishes model ownership geometry")
	var checkpoint: PackedByteArray=store.pin_checkpoint().checkpoint
	var metadata: PackedByteArray=store.read_metadata(checkpoint).metadata
	check(batch.validate_metadata(metadata) and not batch.restore_metadata(metadata) and batch.capture_snapshot()==before,"valid metadata cannot bypass ownership protection")
	var codec: RefCounted=ClassDB.instantiate("NativeStructuresSnapshot");codec.configure_assets(PackedStringArray(["test/owned"]))
	var block_checkpoint:=PackedByteArray();block_checkpoint.resize(32);block_checkpoint.fill(7)
	var bootstrap: PackedByteArray=codec.encode_bootstrap(block_checkpoint,PackedInt32Array(),PackedByteArray(),{"test/owned":metadata})
	var blocks: Node3D=ClassDB.instantiate("NativeBlockWorld");root.add_child(blocks)
	blocks.set_cells(PackedInt32Array([1,1,1,1]))
	var blocks_before: PackedByteArray=blocks.capture_snapshot()
	check(not bootstrap.is_empty() and not codec.restore_bootstrap(bootstrap,blocks,{"test/owned":batch}) and blocks.capture_snapshot()==blocks_before and batch.capture_snapshot()==before,"combined bootstrap rejects before changing either blocks or models")
	check(batch.set_removal_protected(id,false) and not batch.is_removal_protected(id),"content owner explicitly releases protection")
	check(history.erase(batch,id),"empty released container may be deleted through history")
	check(history.undo(AABB()) and not batch.is_removal_protected(id),"restoring empty geometry does not fabricate contents ownership")
	check(batch.restore_snapshot(before),"whole snapshot restore succeeds after ownership handoff")
	check(batch.restore_metadata(metadata),"metadata bootstrap succeeds after ownership handoff")
	check(batch.set_removal_protected(id,true),"content owner can rebuild protection against startup reserved IDs")
	check(batch.restore_region(packet) and not batch.remove_instances(PackedInt64Array([id])),"startup admission keeps rebuilt protection")
	var world: Node3D=load("res://addons/structures/structures_world.gd").new();root.add_child(world)
	var owned: Node3D=world.register_model("test/owned",mesh)
	var empty_world: PackedByteArray=world.capture_snapshot()
	world.blocks.set_cells(PackedInt32Array([2,2,2,1]));owned.upsert_instances(PackedInt64Array([8]),pose(4));owned.set_removal_protected(8,true)
	var world_blocks: PackedByteArray=world.blocks.capture_snapshot()
	var world_models: PackedByteArray=owned.capture_snapshot()
	check(not world.restore_snapshot(empty_world) and world.blocks.capture_snapshot()==world_blocks and owned.capture_snapshot()==world_models,"scene full restore preflights ownership before touching blocks")
	check(not world.restore_storage_snapshot(empty_world) and world.blocks.capture_snapshot()==world_blocks and owned.capture_snapshot()==world_models,"scene storage restore preflights ownership before touching blocks")
	owned.set_removal_protected(8,false)
	check(world.restore_storage_snapshot(empty_world) and world.blocks.get_cell(Vector3i(2,2,2))==0 and owned.get_ids().is_empty(),"coordinated restore works after content owner releases protection")
	world.free()
	blocks.free();batch.free()
	var report: Dictionary={"checks":checks,"failures":failures,"scope":"runtime model ownership interlock; contents store and UI not integrated"}
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file:=FileAccess.open("res://reports/model_removal_protection.json",FileAccess.WRITE);file.store_string(JSON.stringify(report));file.close()
	print("MODEL_REMOVAL_PROTECTION ",JSON.stringify(report));quit(1 if failures else 0)
