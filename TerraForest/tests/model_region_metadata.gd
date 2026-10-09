# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks := 0
var failures := 0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func signed_bytes(bytes: PackedByteArray) -> PackedByteArray:
	var out:=bytes.slice(0,bytes.size()-32)
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(out);out.append_array(hash.finish());return out
func write(path: String,bytes: PackedByteArray) -> void:
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(bytes);file.close()
func batch(asset: String) -> Node3D:
	var result: Node3D=ClassDB.instantiate("NativeStaticBatch")
	result.configure_collision_only();result.configure_asset(asset,BoxMesh.new())
	result.configure_collision(AABB(Vector3(40,-2,-4),Vector3(10,4,8)),64,8,8)
	return result
func _initialize() -> void:run.call_deferred()
func run() -> void:
	GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	DirAccess.make_dir_recursive_absolute("res://reports")
	var path:=ProjectSettings.globalize_path("res://reports/model_metadata_%d_%d" % [OS.get_process_id(),Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(path)
	var source:=batch("test/metadata")
	var ids:=PackedInt64Array();ids.resize(100000)
	var transforms:=PackedFloat32Array();transforms.resize(1200000)
	for i in 100000:
		ids[i]=i+1
		var pose:=PackedFloat32Array([-2,0.5,0,int(i/1000)*64+(i%10)*0.1,0,3,0,0,0,0,1,0])
		for j in 12:transforms[i*12+j]=pose[j]
	check(source.upsert_instances(ids,transforms),"100000 reflected scaled and sheared placements span 100 origin regions")
	var original: PackedByteArray=source.capture_snapshot()
	var store: RefCounted=ClassDB.instantiate("NativeModelRegionStore")
	check(store.open_store(path,"test/metadata").ok and store.publish_snapshot(original).ok,"large collection publishes into immutable region catalog")
	var pin: PackedByteArray=store.pin_checkpoint().checkpoint
	var read: Dictionary=store.read_metadata(pin)
	check(read.ok and not read.cache_hit and read.cache_written and read.regions_read==100,"first metadata build verifies region packets individually and persists derived manifest")
	var metadata: PackedByteArray=read.metadata
	check(metadata.size()<850000 and original.size()>5600000,"manifest stores IDs and region basis bounds instead of all instance transforms")
	read=store.read_metadata(pin)
	check(read.ok and read.cache_hit and read.regions_read==0 and read.metadata==metadata,"cached metadata reuses exact checkpoint manifest without region reads")
	var live:=batch("test/metadata")
	check(live.validate_metadata(metadata) and live.restore_metadata(metadata),"fresh scene bootstraps from validated checkpoint metadata")
	var stats: Dictionary=live.region_stats()
	check(stats.resident_instances==0 and stats.resident_transform_bytes==0 and stats.logical_instances==100000 and stats.reserved_ids==100000 and stats.unloaded_regions==100,"bootstrap reserves 100000 identities with zero resident transforms")
	check(live.capture_snapshot().is_empty() and live.get_instance(1).is_empty(),"unloaded bootstrap cannot masquerade as a complete snapshot")
	check(not live.upsert_instances(PackedInt64Array([1]),PackedFloat32Array([1,0,0,9000,0,1,0,0,0,0,1,0])),"metadata-reserved identity cannot be stolen in an empty region")
	check(not live.is_collision_region_ready(AABB(Vector3(-100,-1,0),Vector3.ONE)),"conservative reflected/sheared bounds block readiness far outside origin region")
	check(live.is_collision_region_ready(AABB(Vector3(10000,0,0),Vector3.ONE)),"empty distant space remains ready with all objects unloaded")
	var queries: Array[Transform3D]=[Transform3D(Basis.IDENTITY,Vector3(-100,0,0)),Transform3D(Basis.IDENTITY,Vector3(10000,0,0))]
	check(live.overlap_mask(queries,AABB(Vector3(-0.25,-0.25,-0.25),Vector3.ONE*0.5))==PackedByteArray([1,0]),"vegetation exclusion uses bootstrap bounds before any model region admission")
	var region: Dictionary=store.read_checkpoint_region(pin,Vector3i.ZERO)
	check(region.ok and live.restore_region(region.bytes) and live.region_stats().resident_instances==1000 and live.region_stats().reserved_ids==99000,"one exact region admits only 1000 nearby transforms from metadata bootstrap")
	var state: Dictionary=live.capture_storage_state()
	check(store.publish_storage_state(state.resident,state.unavailable_keys,state.unavailable_checksums,pin).ok,"bootstrapped partial collection can save while 99000 transforms remain unloaded")
	var corrupt:=metadata.duplicate();corrupt[corrupt.size()-1]^=1
	check(not live.restore_metadata(corrupt) and live.region_stats().resident_instances==1000,"corrupt manifest fails before replacing existing resident state")
	var first:=48+metadata.decode_u32(8)
	var bad:=metadata.duplicate();bad.encode_float(first+48,NAN);bad=signed_bytes(bad)
	check(not live.validate_metadata(bad),"valid checksum cannot admit nonfinite basis bounds")
	bad=metadata.duplicate();bad.encode_u64(first+84+8000+84,1);bad=signed_bytes(bad)
	check(not live.validate_metadata(bad),"manifest rejects duplicate identities across different regions")
	bad=metadata.duplicate();bad.encode_s32(first,32768);bad=signed_bytes(bad)
	check(not live.validate_metadata(bad),"manifest rejects out-of-range origin regions")
	var other:=batch("test/other")
	check(not other.restore_metadata(metadata),"checkpoint metadata cannot restore into a different asset")
	other.free()
	var exact:=true
	for i in range(1,100):
		region=store.read_checkpoint_region(pin,Vector3i(i*2,0,0))
		exact=region.ok and live.restore_region(region.bytes) and exact
	check(exact and live.capture_snapshot()==original and live.region_stats().reserved_ids==0,"all 100 regions reconstruct byte-exact original after metadata-only startup")
	store.close()
	check(store.open_store(path,"test/metadata").ok,"catalog reopens from disk")
	read=store.read_metadata(pin)
	check(read.ok and read.cache_hit and read.regions_read==0 and read.metadata==metadata,"cached manifest survives store reopen")
	var cache:=path.path_join("checkpoints").path_join(pin.hex_encode()+".tfmd")
	write(cache,PackedByteArray([1,2,3]))
	read=store.read_metadata(pin)
	check(read.ok and not read.cache_hit and read.cache_written and read.metadata==metadata,"corrupt derived cache regenerates from authoritative region blobs")
	var duplicate:=batch("test/metadata")
	duplicate.upsert_instances(PackedInt64Array([1]),PackedFloat32Array([1,0,0,9600,0,1,0,0,0,0,1,0]))
	check(store.publish_region(duplicate.capture_region(Vector3i(300,0,0)),PackedByteArray()).ok,"low-level fixture creates a cross-region duplicate ID catalog")
	var invalid_pin: PackedByteArray=store.pin_checkpoint().checkpoint
	check(not store.read_metadata(invalid_pin).ok,"metadata generation refuses globally duplicate IDs even from valid individual packets")
	store.release_checkpoint(invalid_pin);duplicate.free()
	DirAccess.remove_absolute(cache)
	var source_region: PackedByteArray=source.capture_region(Vector3i.ZERO)
	var blob:=path.path_join("blobs").path_join(source_region.slice(source_region.size()-32).hex_encode()+".tfrg")
	write(blob,PackedByteArray([1,2,3]))
	check(not store.read_metadata(pin).ok and not FileAccess.file_exists(cache),"uncached bootstrap fails on corrupt authoritative region without writing a manifest")
	write(blob,source_region);store.read_metadata(pin)
	check(store.release_checkpoint(pin).ok and not FileAccess.file_exists(cache) and not store.read_metadata(pin).ok,"retiring checkpoint removes derived manifest and prevents stale metadata reads")
	store.close();source.free();live.free()
	var report:=FileAccess.open("res://reports/model_region_metadata.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures,"metadata_bytes":metadata.size(),"full_snapshot_bytes":original.size(),"bootstrap":stats,"scope":"100000-placement metadata bootstrap, exact lazy restoration, conservative bounds and cached catalog manifests; not main-world automatic model paging."},"  "));report.close()
	quit(1 if failures else 0)
