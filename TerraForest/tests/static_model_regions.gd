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
	batch.remove_instances(PackedInt64Array([99]))
	batch.upsert_instances(PackedInt64Array([98]),pose(31))
	check(not batch.unload_region(packet),"same-count region with replaced identity cannot accept stale capture")
	batch.restore_snapshot(original)
	var signed_zero:=original.duplicate()
	# First record, second float: change +0 to -0, then sign the snapshot.
	signed_zero.encode_u32(16+signed_zero.decode_u32(8)+8+4,0x80000000)
	signed_zero=signed_packet(signed_zero)
	check(batch.restore_snapshot(signed_zero) and batch.capture_snapshot()==signed_zero,"snapshot preserves signed-zero transform bits")
	check(not batch.unload_region(packet),"numerically equal signed-zero change rejects byte-stale region capture")
	var signed_region: PackedByteArray=batch.capture_region(Vector3i.ZERO)
	check(batch.unload_region(signed_region) and batch.restore_region(signed_region) and batch.capture_snapshot()==signed_zero,"matching signed-zero region unload and restore remain byte exact")
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
	check_history_transfers()
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
func check_history_transfers() -> void:
	var a=ClassDB.instantiate("NativeStaticBatch");a.configure_collision_only();a.configure_asset("test/history_regions",BoxMesh.new())
	var b=ClassDB.instantiate("NativeStaticBatch");b.configure_collision_only();b.configure_asset("test/other_history",BoxMesh.new())
	a.upsert_instances(PackedInt64Array([1,2,3]),pose(1)+pose(65)+pose(-1))
	b.upsert_instances(PackedInt64Array([1]),pose(1))
	var history=ClassDB.instantiate("NativeStaticHistory");history.configure([a,b],1048576,256)
	history.update(a,1,pose(33),AABB())
	check(history.region_has_history(a,Vector3i.ZERO) and history.region_has_history(a,Vector3i(1,0,0)),"history pins both source and destination of cross-region move")
	check(not history.unload_region(a,a.capture_region(Vector3i.ZERO)) and not history.unload_region(a,a.capture_region(Vector3i(1,0,0))),"history-aware unload rejects pinned regions including empty move source")
	var packet: PackedByteArray=a.capture_region(Vector3i(2,0,0))
	var before: Dictionary=history.stats()
	check(history.unload_region(a,packet) and history.stats().undo_steps==before.undo_steps and history.stats().barriers==before.barriers,"unrelated unload preserves undo and revision cursor")
	check(history.undo() and a.get_instance(1)==pose(1),"undo still works while unrelated region is unloaded")
	check(history.region_has_history(a,Vector3i(1,0,0)),"redo history keeps currently empty destination pinned")
	check(history.restore_region(a,packet) and history.stats().redo_steps==1,"reload preserves redo stack")
	check(history.redo() and a.get_instance(1)==pose(33),"redo remains exact after unload and reload")
	var corrupted:=packet.duplicate();corrupted[0]^=1
	check(not history.unload_region(a,corrupted) and history.stats().undo_steps==1,"rejected transfer preserves journal")
	var other_packet: PackedByteArray=b.capture_region(Vector3i.ZERO)
	check(not history.region_has_history(b,Vector3i.ZERO) and history.unload_region(b,other_packet),"same coordinates in another collection are not pinned")
	check(history.restore_region(b,other_packet) and history.stats().undo_steps==1,"other collection reload preserves existing undo")
	history.erase(a,3)
	check(history.region_has_history(a,Vector3i(-1,0,0)) and not history.unload_region(a,a.capture_region(Vector3i(-1,0,0))),"erased object's signed region remains pinned for undo")
	check(history.undo() and a.get_instance(3)==pose(-1),"deletion undo restores reserved history location")
	var observer: Dictionary={"reentered":true,"steps":0}
	a.changed.connect(func(): observer.reentered=history.undo();observer.steps=history.stats().undo_steps,CONNECT_ONE_SHOT)
	check(history.unload_region(a,packet) and not observer.reentered and observer.steps==1,"transfer observer sees intact history and cannot replay reentrantly")
	check(history.restore_region(a,packet),"reload after observer succeeds")
	var callback:=func(): b.upsert_instances(PackedInt64Array([8]),pose(120))
	a.changed.connect(callback,CONNECT_ONE_SHOT)
	check(history.unload_region(a,packet) and history.stats().undo_steps==0 and history.stats().redo_steps==0,"external callback mutation still invalidates history after residency transfer")
	history.restore_region(a,packet)
	history.configure([a],1048576,1)
	history.update(a,1,pose(34),AABB());history.update(a,2,pose(66),AABB())
	check(not history.region_has_history(a,Vector3i(1,0,0)) and history.region_has_history(a,Vector3i(2,0,0)),"history eviction releases region pin when no retained record refers to it")
	check(history.unload_region(a,a.capture_region(Vector3i(1,0,0))) and history.undo() and a.get_instance(2)==pose(65),"eviction-eligible region unload preserves remaining bounded undo")
	check(history.region_has_history(b,Vector3i.ZERO) and not history.unload_region(b,other_packet),"unregistered collection is conservatively ineligible")
	a.free();b.free()
