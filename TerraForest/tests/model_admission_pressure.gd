# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var checks:=0
var measurements: Array=[]
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	DirAccess.make_dir_recursive_absolute("res://reports")
	for spec in [[1000,1000],[10000,10000],[100000,100000],[100000,1000]]:
		measure(spec[0],spec[1])
	var qualified:=failures==0 and measurements.size()==4
	var transfer_qualified:=qualified
	for row in measurements:
		qualified=qualified and row.restore_region_max_us<=2000
		transfer_qualified=transfer_qualified and row.restore_region_max_us<=2000 and row.capture_region_us.max()<=2000 and row.unload_region_us.max()<=2000
	var report: Dictionary={"checks":checks,"failures":failures,"measurements":measurements,"runtime_admission_budget_us":2000,"runtime_admission_qualified":qualified,"runtime_transfer_qualified":transfer_qualified,"scope":"Headless native CPU lower bound; no GPU, render upload or physics body creation. Metadata installation is separately timed. Not FPS or cross-host comparison."}
	var file:=FileAccess.open("res://reports/model_admission_pressure.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print("MODEL_ADMISSION_PRESSURE ",JSON.stringify(report))
	print("RUNTIME_MODEL_PAGING_GATE ","PASS" if transfer_qualified else "FAIL: synchronous region transfer exceeds the 2 ms CPU allowance")
	quit(1 if failures else (0 if transfer_qualified else 2))
func measure(total: int,per_region: int) -> void:
	var source: Node3D=ClassDB.instantiate("NativeStaticBatch")
	source.configure_collision_only();source.configure_asset("test/admission",BoxMesh.new())
	var ids:=PackedInt64Array();ids.resize(total)
	var transforms:=PackedFloat32Array();transforms.resize(total*12)
	for i in total:
		ids[i]=i+1
		transforms[i*12]=1;transforms[i*12+5]=1;transforms[i*12+10]=1
		transforms[i*12+3]=int(i/per_region)*64+(i%10)
		transforms[i*12+7]=int(i/10)%10;transforms[i*12+11]=int(i/100)%10
	check(source.upsert_instances(ids,transforms),"pressure fixture admits %d placements with %d per region" % [total,per_region])
	var path:=ProjectSettings.globalize_path("res://reports/model_admission_%d_%d" % [OS.get_process_id(),Time.get_ticks_usec()]);DirAccess.make_dir_recursive_absolute(path)
	var store: RefCounted=ClassDB.instantiate("NativeModelRegionStore")
	var saved: bool=store.open_store(path,"test/admission").ok and store.publish_snapshot(source.capture_snapshot()).ok
	check(saved,"pressure fixture persists source regions")
	if not saved:
		store.close();source.free();return
	var pin: PackedByteArray=store.pin_checkpoint().checkpoint
	var metadata: PackedByteArray=store.read_metadata(pin).metadata
	var packet: PackedByteArray=source.capture_region(Vector3i.ZERO)
	if packet.size()>4*1024*1024:
		var direct: RefCounted=ClassDB.instantiate("NativeModelRegionStore")
		DirAccess.make_dir_recursive_absolute(path+".direct")
		var published: bool=direct.open_store(path+".direct","test/admission").ok and direct.publish_region(packet,PackedByteArray()).ok
		check(published and direct.read_region(Vector3i.ZERO).bytes==packet,"direct region publication also verifies blobs above the 4 MiB catalog ceiling")
		direct.close()
	var live: Node3D=ClassDB.instantiate("NativeStaticBatch")
	live.configure_collision_only();live.configure_asset("test/admission",BoxMesh.new())
	var metadata_us: Array=[];var admission_us: Array=[];var capture_us: Array=[];var unload_us: Array=[]
	var exact:=true
	for repeat in 4:
		var start:=Time.get_ticks_usec();var restored: bool=live.restore_metadata(metadata);var elapsed:=Time.get_ticks_usec()-start
		if repeat:metadata_us.append(elapsed)
		start=Time.get_ticks_usec();restored=live.restore_region(packet) and restored;elapsed=Time.get_ticks_usec()-start
		if repeat:admission_us.append(elapsed)
		start=Time.get_ticks_usec();var captured: PackedByteArray=live.capture_region(Vector3i.ZERO);elapsed=Time.get_ticks_usec()-start
		if repeat:capture_us.append(elapsed)
		start=Time.get_ticks_usec();restored=live.unload_region(captured) and restored;elapsed=Time.get_ticks_usec()-start
		if repeat:unload_us.append(elapsed)
		exact=restored and captured==packet and live.region_stats().logical_instances==total and live.region_stats().resident_instances==0 and exact
	check(exact,"pressure transfers preserve every logical identity and exact region bytes")
	measurements.append({"logical_instances":total,"region_instances":per_region,"packet_bytes":packet.size(),"metadata_bytes":metadata.size(),"restore_metadata_us":metadata_us,"restore_region_us":admission_us,"restore_region_max_us":admission_us.max(),"capture_region_us":capture_us,"unload_region_us":unload_us})
	store.close();source.free();live.free()
