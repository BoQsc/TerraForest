# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var checks:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func pose(x: float,y: float=0,z: float=0) -> PackedFloat32Array:
	return PackedFloat32Array([1,0,0,x,0,1,0,y,0,0,1,z])
func signed_packet(bytes: PackedByteArray) -> PackedByteArray:
	var payload:=bytes.slice(0,bytes.size()-32)
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(payload)
	payload.append_array(hash.finish());return payload
func _initialize() -> void: call_deferred("run")
func run() -> void:
	GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	var batch=ClassDB.instantiate("NativeStaticBatch");root.add_child(batch)
	batch.configure_asset("tests/region_model",BoxMesh.new())
	batch.configure_render_streaming(true,128,8,65536,2,4096)
	batch.configure_collision(AABB(Vector3(-2,-1,-1),Vector3(4,2,2)),128,8,8)
	var ids:=PackedInt64Array([1,99,2]);var transforms:=pose(1);transforms.append_array(pose(31));transforms.append_array(pose(-1))
	check(batch.upsert_instances(ids,transforms),"fixture spans positive and negative origin regions")
	var original: PackedByteArray=batch.capture_snapshot()
	var packet: PackedByteArray=batch.capture_region(Vector3i.ZERO)
	check(batch.validate_region_snapshot(packet) and not packet.is_empty(),"region packet validates asset and checksum")
	check(batch.capture_region(Vector3i(32768,0,0)).is_empty(),"out-of-range region rejected")
	var damaged:=packet.duplicate();damaged[damaged.size()-1]^=1
	check(not batch.unload_region(damaged) and batch.capture_snapshot()==original,"corrupt packet cannot mutate collection")
	var wrong_region:=packet.duplicate();wrong_region.encode_s32(8,1);wrong_region=signed_packet(wrong_region)
	check(not batch.validate_region_snapshot(wrong_region),"valid checksum cannot disguise records in the wrong region")
	batch.upsert_instances(PackedInt64Array([1]),pose(2))
	check(not batch.unload_region(packet),"stale capture cannot discard a newer edit")
	batch.restore_snapshot(original)
	for frame in 10: await physics_frame
	check(batch.collision_stats().resident_bodies==3 and batch.render_stats().resident_instances==3,"fixture admits native collision and render residency before unload")
	var history=ClassDB.instantiate("NativeStaticHistory");history.configure([batch],1048576,256)
	history.update(batch,2,pose(-2),AABB())
	var negative: PackedFloat32Array=batch.get_instance(2)
	check(batch.unload_region(packet),"matching region unload succeeds")
	check(batch.stats().instances==1 and batch.get_instance(2)==negative and batch.get_instance(1).is_empty(),"unload frees selected records and preserves neighboring region")
	check(batch.collision_stats().resident_bodies<=1 and batch.render_stats().resident_instances<=1,"unload immediately releases region bodies and render buffers")
	check(history.stats().undo_steps==0,"region transfer forms explicit history barrier")
	check(not batch.is_region_loaded(Vector3i.ZERO) and batch.is_region_loaded(Vector3i(-1,0,0)),"availability distinguishes unknown from resident regions")
	check(batch.capture_snapshot().is_empty() and batch.capture_region(Vector3i.ZERO).is_empty(),"incomplete collection cannot masquerade as a full save")
	check(not batch.set_instances(BoxMesh.new(),pose(4)),"legacy full-set mutation cannot silently drop unloaded data")
	check(not batch.configure_asset("tests/other",BoxMesh.new()),"unloaded bounds prevent incompatible asset replacement")
	check(not batch.configure_collision(AABB(Vector3.ZERO,Vector3.ONE),64,8,8),"unloaded bounds prevent proxy reconfiguration")
	check(not batch.can_insert_instance(pose(4),AABB()) and not batch.upsert_instances(PackedInt64Array([101]),pose(4)),"authoring in unloaded origin region rejected")
	check(not batch.upsert_instances(PackedInt64Array([1]),pose(80)),"reserved unloaded ID cannot be stolen in another region")
	check(not batch.is_collision_region_ready(AABB(Vector3(32,-0.5,-0.5),Vector3.ONE)),"unloaded extended model bounds block collision readiness beyond origin region")
	check(batch.is_collision_region_ready(AABB(Vector3(500,0,0),Vector3.ONE)),"distant empty space remains collision ready")
	var queries: Array[Transform3D]=[Transform3D(Basis.IDENTITY,Vector3(32,0,0)),Transform3D(Basis.IDENTITY,Vector3(500,0,0))]
	check(batch.overlap_mask(queries,AABB(Vector3(-0.25,-0.25,-0.25),Vector3.ONE*0.5))==PackedByteArray([1,0]),"vegetation exclusion stays conservative for unloaded bounds")
	check(batch.insert_instance(pose(80),AABB())==100,"new placement IDs account for resident and reserved records")
	check(not batch.restore_region(damaged) and not batch.is_region_loaded(Vector3i.ZERO),"corrupt reload preserves unavailable state")
	check(batch.restore_region(packet) and batch.get_instance(1)==pose(1) and batch.get_instance(99)==pose(31),"exact packet restores stable IDs and transforms")
	check(not batch.restore_region(packet),"duplicate restore cannot replace resident edits")
	check(batch.region_stats().reserved_ids==0 and batch.region_stats().unloaded_regions==0,"restore releases reservations")
	for frame in 10: await physics_frame
	check(batch.collision_stats().resident_bodies==4 and batch.render_stats().resident_instances==4,"restored records reenter bounded render and collision admission")
	batch.remove_instances(PackedInt64Array([100]));batch.upsert_instances(PackedInt64Array([2]),pose(-1))
	check(batch.capture_snapshot()==original,"whole snapshot round trips byte exactly")
	var empty: PackedByteArray=batch.capture_region(Vector3i(10,0,0))
	check(batch.unload_region(empty) and batch.restore_region(empty),"empty region round trip is explicit")
	check(batch.unload_region(packet) and batch.restore_snapshot(original) and batch.region_stats().unloaded_regions==0,"explicit whole-world restore replaces reservations")
	batch.free();await process_frame
	await pressure()
	DirAccess.make_dir_recursive_absolute("res://reports")
	var report:=FileAccess.open("res://reports/static_model_regions.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures}));report.close()
	print("STATIC_MODEL_REGIONS checks=",checks," failures=",failures)
	quit(1 if failures else 0)
func pressure() -> void:
	var batch=ClassDB.instantiate("NativeStaticBatch");root.add_child(batch)
	batch.configure_collision_only();batch.configure_asset("tests/region_pressure",BoxMesh.new())
	var ids:=PackedInt64Array();ids.resize(100000)
	var transforms:=PackedFloat32Array();transforms.resize(1200000)
	for i in 100000:
		ids[i]=i+1
		var t:=pose(int(i/1000)*32+(i%10),int(i/10)%10,int(i/100)%10)
		for j in 12: transforms[i*12+j]=t[j]
	check(batch.upsert_instances(ids,transforms),"100000 placements admitted across 100 regions")
	var original: PackedByteArray=batch.capture_snapshot()
	var folder: String="user://model_region_test_"+str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(folder)
	var all_written:=true;var all_unloaded:=true;var max_packet:=0
	var begin:=Time.get_ticks_usec()
	for region in 99:
		var packet: PackedByteArray=batch.capture_region(Vector3i(region,0,0))
		max_packet=maxi(max_packet,packet.size())
		var file:=FileAccess.open(folder+"/"+str(region)+".bin",FileAccess.WRITE)
		if file==null: all_written=false;break
		file.store_buffer(packet);file.close()
		var readback:=FileAccess.get_file_as_bytes(folder+"/"+str(region)+".bin")
		all_written=all_written and readback==packet
		if readback==packet: all_unloaded=batch.unload_region(packet) and all_unloaded
	var stats: Dictionary=batch.region_stats()
	check(all_written and all_unloaded,"99 region packets survive disk readback before unload")
	check(stats.resident_instances==1000 and stats.logical_instances==100000 and stats.reserved_ids==99000,"pressure retains 1000 resident transforms and reserves 99000 unloaded IDs")
	check(stats.resident_transform_bytes==48000 and batch.capture_snapshot().is_empty(),"transform payload shrinks from 4.8 MB to 48 KB and incomplete save is rejected")
	check(not batch.can_insert_instance(pose(4000),AABB()),"logical capacity includes unloaded instances")
	print("REGION_PRESSURE ",{"stats":stats,"max_packet_bytes":max_packet,"capture_write_unload_us":Time.get_ticks_usec()-begin})
	var all_restored:=true
	for region in 99:
		var path:=folder+"/"+str(region)+".bin"
		all_restored=batch.restore_region(FileAccess.get_file_as_bytes(path)) and all_restored
		DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(folder)
	check(all_restored and batch.capture_snapshot()==original,"100000-placement disk transfer restores byte-exact whole snapshot")
	batch.free();await process_frame
