# SPDX-License-Identifier: 0BSD
extends SceneTree
const ASSET:="test/retention"
var checks:=0
var failures:=0
var archive: RefCounted
var codec: RefCounted
var raw: RefCounted
var world: Node3D
var batch: Node3D
var path: String
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize() -> void:run.call_deferred()
func until(count: int) -> bool:
	var end:=Time.get_ticks_msec()+10000
	while archive.region_read_stats().completed<count and Time.get_ticks_msec()<end:await process_frame
	return archive.region_read_stats().completed>=count
func sections(version: int) -> PackedByteArray:
	world.set_cells(PackedInt32Array([0,0,0,1+version%6]))
	batch.upsert_instances(PackedInt64Array([1]),PackedFloat32Array([1,0,0,1+version/100.0,0,1,0,0,0,0,1,0]))
	return archive.encode({"terrain":PackedByteArray([1]),"structures":codec.encode(world.capture_snapshot(),{ASSET:batch.capture_snapshot()})})
func pins() -> Dictionary:
	var root: Dictionary=codec.decode_reference(raw.decode(archive.read(path)).sections.structures)
	var model: PackedByteArray=root.models[ASSET];var length:=model.decode_u32(8)
	return {"block":root.checkpoint,"model":model.slice(12+length,44+length)}
func model_folder() -> String:
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(ASSET.to_utf8_buffer())
	return (path+".models").path_join(hash.finish().hex_encode())
func pin_exists(pin: PackedByteArray,model: bool) -> bool:
	return FileAccess.file_exists((model_folder() if model else path+".regions").path_join("checkpoints").path_join(pin.hex_encode()+".tfrc"))
func publish_range(first: int,last: int) -> bool:
	for version in range(first,last+1):
		if archive.publish(path,sections(version))!=OK:return false
	return true
func run() -> void:
	GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
	Engine.max_fps=240
	DirAccess.make_dir_recursive_absolute("res://reports")
	path=ProjectSettings.globalize_path("res://reports/checkpoint_retention_%d_%d.trw" % [OS.get_process_id(),Time.get_ticks_usec()])
	codec=ClassDB.instantiate("NativeStructuresSnapshot");codec.configure_assets(PackedStringArray([ASSET]))
	raw=ClassDB.instantiate("NativeWorldArchive");archive=ClassDB.instantiate("NativeRegionWorldArchive");archive.configure(raw,codec,true)
	check(archive.region_read_stats().checkpoint_lease_limit==1024 and not archive.configure_checkpoint_retention(0) and not archive.configure_checkpoint_retention(4097) and archive.configure_checkpoint_retention(64),"lease budget is configurable and bounded without imposing a 64-asset default ceiling")
	world=ClassDB.instantiate("NativeBlockWorld");batch=ClassDB.instantiate("NativeStaticBatch");batch.configure_collision_only();batch.configure_asset(ASSET,BoxMesh.new())
	check(archive.retain_read_checkpoint(ASSET,PackedByteArray())==0 and archive.acquire(path),"closed archive cannot retain and fixture acquires storage")
	check(archive.publish(path,sections(0))==OK and archive.start_region_reads(8,32*1024*1024),"fixture starts one shared read worker")
	var original:=pins();var block_packet: PackedByteArray=world.capture_region(Vector3i.ZERO);var model_packet: PackedByteArray=batch.capture_region(Vector3i.ZERO)
	check(archive.request_checkpoint_region_read(Vector3i.ZERO,block_packet.slice(block_packet.size()-32),original.block,1)>0 and archive.request_model_metadata(ASSET,original.model,1)>0 and await until(2),"block and metadata completions remain unread")
	check(archive.region_read_stats().retained_checkpoint_keys==2,"outstanding reads retain both checkpoint namespaces")
	check(publish_range(1,3) and pin_exists(original.block,false) and pin_exists(original.model,true),"unread results protect old pins after multiple root rotations")
	check(archive.request_model_checkpoint_region_read(ASSET,Vector3i.ZERO,model_packet.slice(model_packet.size()-32),original.model,1)>0 and await until(3),"protected old model checkpoint still serves exact region bytes")
	var blocks: Array=archive.poll_region_reads(8);var models: Array=archive.poll_model_region_reads(8)
	check(blocks.size()==1 and blocks[0].ok and blocks[0].bytes==block_packet and models.size()==2 and models[0].ok and models[1].ok and models[1].bytes==model_packet,"old block, model and metadata reads survive cleanup")
	check(archive.region_read_stats().retained_checkpoint_keys==0 and archive.publish(path,sections(4))==OK and not pin_exists(original.block,false) and not pin_exists(original.model,true),"polling releases automatic retention and next publication reclaims old pins")
	archive.request_model_metadata(ASSET,original.model,2);await until(1);models=archive.poll_model_region_reads(8)
	check(models.size()==1 and not models[0].ok and archive.region_read_stats().retained_checkpoint_keys==0,"already retired checkpoint fails explicitly and does not leak retention")
	var kept:=pins();block_packet=world.capture_region(Vector3i.ZERO);model_packet=batch.capture_region(Vector3i.ZERO)
	var block_lease: int=archive.retain_read_checkpoint("",kept.block)
	var model_lease: int=archive.retain_read_checkpoint(ASSET,kept.model)
	var duplicate_lease: int=archive.retain_read_checkpoint(ASSET,kept.model)
	check(block_lease>0 and model_lease>block_lease and duplicate_lease>model_lease,"explicit leases have distinct monotonic handles")
	check(archive.retain_read_checkpoint("unknown",kept.model)==0 and archive.retain_read_checkpoint(ASSET,PackedByteArray([1]))==0 and not archive.release_read_checkpoint(0),"invalid lease requests cannot alter retention")
	var duplicates:=PackedInt64Array()
	for i in 61:duplicates.append(archive.retain_read_checkpoint(ASSET,kept.model))
	check(not duplicates.has(0) and archive.region_read_stats().checkpoint_leases==64 and archive.region_read_stats().retained_checkpoint_keys==2 and archive.retain_read_checkpoint(ASSET,kept.model)==0,"64-handle bound applies even when leases share the same pin")
	check(not archive.configure_checkpoint_retention(63) and archive.region_read_stats().checkpoint_leases==64,"lowering lease budget cannot revoke active holders")
	for lease in duplicates:archive.release_read_checkpoint(lease)
	check(publish_range(5,8) and pin_exists(kept.block,false) and pin_exists(kept.model,true),"explicit leases retain old versions after results have been consumed")
	archive.request_region_read(Vector3i.ZERO,block_packet.slice(block_packet.size()-32),kept.block,3)
	archive.request_model_region_read(ASSET,Vector3i.ZERO,model_packet.slice(model_packet.size()-32),kept.model,3)
	await until(2);blocks=archive.poll_region_reads(8);models=archive.poll_model_region_reads(8)
	check(blocks.size()==1 and blocks[0].ok and blocks[0].bytes==block_packet and models.size()==1 and models[0].ok and models[0].bytes==model_packet,"leased exact versions remain readable across new saves")
	# Active catalog has newer bytes. A retained old pin must not certify them.
	var active_block: PackedByteArray=world.capture_region(Vector3i.ZERO)
	var active_model: PackedByteArray=batch.capture_region(Vector3i.ZERO)
	check(archive.request_checkpoint_region_read(Vector3i.ZERO,active_block.slice(active_block.size()-32),PackedByteArray(),30)==0 and archive.request_model_checkpoint_region_read("",Vector3i.ZERO,active_model.slice(active_model.size()-32),kept.model,30)==0,"strict reads reject missing checkpoint and empty model identity")
	archive.request_checkpoint_region_read(Vector3i.ZERO,active_block.slice(active_block.size()-32),kept.block,30)
	archive.request_model_checkpoint_region_read(ASSET,Vector3i.ZERO,active_model.slice(active_model.size()-32),kept.model,30)
	await until(2);blocks=archive.poll_region_reads(8);models=archive.poll_model_region_reads(8)
	check(blocks.size()==1 and models.size()==1 and not blocks[0].ok and not models[0].ok and not blocks[0].has("bytes") and not models[0].has("bytes") and not blocks[0].checkpoint_verified and not models[0].checkpoint_verified,"strict checkpoint mismatch cannot return newer active bytes or expose unwanted payload")
	archive.request_region_read(Vector3i.ZERO,active_block.slice(active_block.size()-32),kept.block,31)
	archive.request_model_region_read(ASSET,Vector3i.ZERO,active_model.slice(active_model.size()-32),kept.model,31)
	await until(2);blocks=archive.poll_region_reads(8);models=archive.poll_model_region_reads(8)
	check(blocks.size()==1 and models.size()==1 and blocks[0].ok and models[0].ok and blocks[0].bytes==active_block and models[0].bytes==active_model and not blocks[0].checkpoint_verified and not models[0].checkpoint_verified,"fallback API remains compatible but does not certify checkpoint ownership")
	archive.request_checkpoint_region_read(Vector3i.ZERO,block_packet.slice(block_packet.size()-32),kept.block,32)
	archive.request_model_checkpoint_region_read(ASSET,Vector3i.ZERO,model_packet.slice(model_packet.size()-32),kept.model,32)
	await until(2);blocks=archive.poll_region_reads(8);models=archive.poll_model_region_reads(8)
	check(blocks.size()==1 and models.size()==1 and blocks[0].ok and models[0].ok and blocks[0].bytes==block_packet and models[0].bytes==model_packet and blocks[0].checkpoint_verified and models[0].checkpoint_verified and models[0].epoch==32,"strict reads certify exact older bytes in retained checkpoints")
	var nonexistent:=PackedByteArray();nonexistent.resize(32)
	archive.request_checkpoint_region_read(Vector3i.ZERO,active_block.slice(active_block.size()-32),nonexistent,33)
	archive.request_model_checkpoint_region_read(ASSET,Vector3i.ZERO,active_model.slice(active_model.size()-32),nonexistent,33)
	await until(2);blocks=archive.poll_region_reads(8);models=archive.poll_model_region_reads(8)
	check(blocks.size()==1 and models.size()==1 and not blocks[0].ok and not models[0].ok and not blocks[0].has("bytes") and not models[0].has("bytes"),"absent checkpoint fails even when active catalog contains requested bytes")
	check(archive.release_read_checkpoint(model_lease) and not archive.release_read_checkpoint(model_lease) and archive.publish(path,sections(9))==OK and pin_exists(kept.model,true),"releasing one handle cannot drop another holder's pin")
	check(archive.release_read_checkpoint(duplicate_lease) and archive.release_read_checkpoint(block_lease) and archive.publish(path,sections(10))==OK and not pin_exists(kept.model,true) and not pin_exists(kept.block,false),"last explicit release allows later cleanup in both stores")
	# Retention is not existence validation. A caller must verify a read after
	# reserving an arbitrary supplied checkpoint before installing its metadata.
	var absent:=PackedByteArray();absent.resize(32)
	var absent_lease: int=archive.retain_read_checkpoint(ASSET,absent)
	archive.request_model_metadata(ASSET,absent,4);await until(1);models=archive.poll_model_region_reads(8)
	check(absent_lease>0 and models.size()==1 and not models[0].ok and archive.release_read_checkpoint(absent_lease),"reservation cannot resurrect an absent checkpoint or manufacture a successful read")
	kept=pins();block_packet=world.capture_region(Vector3i.ZERO)
	block_lease=archive.retain_read_checkpoint("",kept.block);model_lease=archive.retain_read_checkpoint(ASSET,kept.model)
	var generations: Array[PackedByteArray]=[]
	for version in range(11,27):generations.append(sections(version))
	var writer:=Thread.new()
	check(writer.start(func():
		for bytes in generations:
			if archive.publish(path,bytes)!=OK:return false
		return true)==OK,"save worker starts checkpoint rotation during retained reads")
	var accepted:=0;var completed:=0;var correct:=true;var end:=Time.get_ticks_msec()+15000
	while (accepted<64 or completed<accepted) and Time.get_ticks_msec()<end:
		if accepted<64:
			var ticket: int=archive.request_model_metadata(ASSET,kept.model,5) if accepted%2 else archive.request_checkpoint_region_read(Vector3i.ZERO,block_packet.slice(block_packet.size()-32),kept.block,5)
			if ticket>0:accepted+=1
		for result in archive.poll_region_reads(8)+archive.poll_model_region_reads(8):
			completed+=1;correct=correct and result.ok and result.epoch==5
			if result.has("bytes"):correct=correct and result.bytes==block_packet
		await process_frame
	check(writer.wait_to_finish() and accepted==64 and completed==64 and correct,"64 retained reads coexist with 16 saves and checkpoint cleanup")
	check(archive.region_read_stats().checkpoint_leases==2 and archive.region_read_stats().retained_checkpoint_keys==2 and archive.region_read_stats().reserved_bytes==0,"concurrent readers release temporary references without dropping explicit leases")
	var root_before: PackedByteArray=archive.read(path)
	var backup_path:=path+".bak";var backup:=FileAccess.get_file_as_bytes(backup_path)
	var damaged_backup:=FileAccess.open(backup_path,FileAccess.WRITE);damaged_backup.store_buffer(PackedByteArray([1,2,3]));damaged_backup.close()
	check(archive.publish(path,sections(27))==ERR_FILE_CORRUPT and archive.read(path)==root_before and not archive.region_read_stats().checkpoint_sweep_active,"failed root validation leaves canonical save intact and releases retention gate")
	var probe_lease: int=archive.retain_read_checkpoint(ASSET,kept.model)
	check(probe_lease>0 and archive.release_read_checkpoint(probe_lease),"retention admission resumes after failed cleanup")
	damaged_backup=FileAccess.open(backup_path,FileAccess.WRITE);damaged_backup.store_buffer(backup);damaged_backup.close()
	check(archive.publish(path,sections(27))==OK,"restored backup permits publication after failed cleanup")
	archive.request_model_metadata(ASSET,kept.model,6);await until(1)
	archive.release()
	check(archive.region_read_stats().checkpoint_leases==0 and archive.region_read_stats().retained_checkpoint_keys==0 and not archive.release_read_checkpoint(model_lease),"archive release ends disk-retention leases without reusing their handles")
	check(not archive.acquire(path),"unread completion still blocks world reuse after release")
	models=archive.poll_model_region_reads(8)
	check(models.size()==1 and models[0].ok and archive.acquire(path),"completed payload survives release but its disk lease does not")
	kept=pins();var fresh: int=archive.retain_read_checkpoint(ASSET,kept.model)
	check(fresh>model_lease and not archive.release_read_checkpoint(block_lease) and archive.release_read_checkpoint(fresh),"new lifecycle cannot be affected by stale lease releases")
	archive.release();world.free();batch.free()
	var file:=FileAccess.open("res://reports/region_checkpoint_retention.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"checkpoint_busy_rejections":archive.region_read_stats().checkpoint_busy_rejections,"scope":"Automatic outstanding-read retention and bounded explicit block/model checkpoint leases; concurrent saves, cleanup and lifecycle. No rendering/performance qualification."},"  "));file.close()
	print("REGION_CHECKPOINT_RETENTION checks=",checks," failures=",failures)
	quit(1 if failures else 0)
