# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
const NAMES=["terrain","blocks","cubes","models","doors","damage","containers","residents","corpses","trees","ground","water"]
const ORIGIN=Vector3i(1274,58,1274)
const SIZE=Vector3i(13,13,13)
var folder:=""
var checks:=0
var failures:=0

func _initialize()->void:
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--baseline-dir="):folder=argument.trim_prefix("--baseline-dir=")
	run.call_deferred()

func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1
	print("PASS " if value else "FAIL ",label)

func digest(text:String)->PackedByteArray:return text.sha256_buffer()

func seal(data:PackedByteArray)->PackedByteArray:
	var output:=data.slice(0,data.size()-32);var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(output);output.append_array(hash.finish());return output

func write(path:String,data:PackedByteArray)->void:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	check(file!=null,"open isolated fixture "+path.get_file())
	if file!=null:file.store_buffer(data);file.close()

func create_store(name:String,world:Variant=null)->RefCounted:
	if world==null:world=digest("world-one")
	var store:RefCounted=ClassDB.instantiate("NativeLocationBaselineStore")
	check(store.open_store(folder.path_join(name),world),"open native baseline store "+name)
	return store

func publish(store:RefCounted,key:int,sections:Dictionary,definition:Variant=null)->Dictionary:
	if definition==null:definition=digest("location-v1")
	var token:Dictionary=store.state();return store.publish_baseline(key,definition,sections,token.revision,token.owner)

func field(core:RefCounted,origin:=ORIGIN,size:=SIZE)->PackedByteArray:
	var token:Dictionary=core.field_patch_state();return core.capture_field_patch(origin,size,token.revision,token.epoch)

func contents(core:RefCounted)->Dictionary:
	var sections:={}
	for name:String in NAMES:sections[name]=PackedByteArray()
	sections.terrain=field(core)
	var water:RefCounted=ClassDB.instantiate("NativeRegionalWater");var token:Dictionary=water.water_patch_state()
	sections.water=water.capture_water_patch(Vector3i(2548,116,2548),Vector3i(26,26,26),token.revision,token.owner)
	sections.mod_example=PackedByteArray([1,2,3,4])
	check(core.validate_field_patch(sections.terrain) and water.validate_water_patch(sections.water),"fixture contains real native terrain/water patches; other owner slots explicitly empty")
	return sections

func packet(key:int,sections:Dictionary)->PackedByteArray:
	var identity:=PackedByteArray();identity.resize(16);identity.encode_u32(0,0x42514654);identity.encode_u32(4,1);identity.encode_u64(8,key)
	identity.append_array(digest("world-one"));identity.append_array(digest("location-v1"))
	var combined:={}
	for name in sections:combined[String(name)]=sections[name]
	combined["baseline_identity"]=identity
	return ClassDB.instantiate("NativeWorldArchive").encode(combined)

func blob_id(data:PackedByteArray)->PackedByteArray:
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(data);return hash.finish()

func run()->void:
	var core:RefCounted=ClassDB.instantiate("TerrainCore")
	check(Codec.reply_ok(core.execute(Codec.command(6,[1703,5]))),"real terrain owner configured")
	var sections:=contents(core)
	if "--reopen" in OS.get_cmdline_user_args():
		var restored:=create_store("durable")
		var manifest:=FileAccess.get_file_as_bytes(folder.path_join("manifest.bin"))
		check(restored.restore_storage_snapshot(manifest) and restored.capture_storage_snapshot()==manifest,"fresh process restores exact reference manifest")
		var loaded:Dictionary=restored.load_baseline(10,digest("location-v1"))
		check(loaded.ok and loaded.sections==sections,"fresh process loads original exact component bytes")
		check(Codec.reply_ok(core.execute(Codec.brush(Vector3(1280,64,1280),Vector3(1280,64,1280),3,0,true,3))),"normal edit after original baseline")
		check(field(core)!=loaded.sections.terrain,"live edit differs from preserved baseline")
		var outside:=Vector3(1266,64,1280)
		check(Codec.reply_ok(core.execute(Codec.brush(outside,outside,2,1,true,2))),"outside edit is authored")
		var preserved:=field(core,Vector3i(1263,61,1277),Vector3i(6,6,6));var token:Dictionary=core.field_patch_state()
		check(core.restore_field_patch(loaded.sections.terrain,token.revision,token.epoch).ok and field(core)==sections.terrain,"durable baseline restores real terrain through its native owner")
		check(field(core,Vector3i(1263,61,1277),Vector3i(6,6,6))==preserved,"outside terrain edit survives durable baseline restoration")
		check(restored.load_baseline(20,digest("location-v1")).ok,"other location still loads independently")
		finish();return
	var unopened:RefCounted=ClassDB.instantiate("NativeLocationBaselineStore")
	check(not unopened.open_store("relative",digest("world-one")) and not unopened.open_store(folder.path_join("invalid"),PackedByteArray()),"relative paths and missing world identity rejected")
	check(not unopened.restore_storage_snapshot(PackedByteArray()) and not publish(unopened,10,sections).ok,"unopened store cannot mutate or publish")
	var store:=create_store("durable");var before:PackedByteArray=store.capture_storage_snapshot()
	check(before.size()==80 and store.validate_snapshot(before),"empty world-bound manifest is bounded and valid")
	check(not unopened.open_store(folder.path_join("durable"),digest("world-one")),"exclusive directory writer lease")
	var token:Dictionary=store.state()
	check(not store.publish_baseline(10,digest("location-v1"),sections,token.revision-1,token.owner).ok,"stale revision rejected")
	check(not store.publish_baseline(10,digest("location-v1"),sections,token.revision,token.owner+1).ok,"wrong owner rejected")
	var missing:=sections.duplicate();missing.erase("water")
	check(not publish(store,10,missing).ok,"missing water owner cannot be silently omitted")
	missing=sections.duplicate();missing.baseline_identity=PackedByteArray()
	check(not publish(store,10,missing).ok,"caller cannot override world/location metadata")
	missing=sections.duplicate();missing.water="invalid"
	check(not publish(store,10,missing).ok and not publish(store,-1,sections).ok and not publish(store,10,sections,PackedByteArray()).ok,"invalid section/key/definition rejected")
	missing=sections.duplicate();missing["../escape"]=PackedByteArray()
	check(not publish(store,10,missing).ok,"invalid extension component names rejected")
	var large:=PackedByteArray();large.resize(16*1024*1024+1);missing=sections.duplicate();missing.mod_bulk=large
	check(not publish(store,10,missing).ok and store.capture_storage_snapshot()==before,"oversized baseline rejected before manifest mutation")
	large=PackedByteArray();missing={}
	var first:=publish(store,10,sections)
	check(first.ok and first.added and first.digest==blob_id(packet(10,sections)),"baseline publishes canonically through native archive: "+str(first))
	if not first.ok:
		finish();return
	check(store.load_baseline(10,digest("location-v1")).sections==sections,"exact component bytes roundtrip")
	var stable:PackedByteArray=store.capture_storage_snapshot();token=store.state()
	var reversed:={};var names:=sections.keys();names.reverse()
	for name:String in names:reversed[name]=sections[name]
	check(publish(store,10,reversed).ok and store.state()==token and store.capture_storage_snapshot()==stable,"idempotent publish ignores dictionary insertion order")
	missing=sections.duplicate();missing.mod_example=PackedByteArray([9])
	check(not publish(store,10,missing).ok and not publish(store,10,sections,digest("changed-definition")).ok,"edited state and changed definitions cannot overwrite original baseline")
	check(store.capture_storage_snapshot()==stable and not store.load_baseline(10,digest("wrong")).ok,"rejected change preserves references; wrong lookup definition rejected")
	check(publish(store,20,sections).ok,"second location publishes separately")
	var manifest:PackedByteArray=store.capture_storage_snapshot()
	check(manifest.size()==240 and store.state().locations==2,"manifest stores only two bounded references")
	write(folder.path_join("manifest.bin"),manifest)
	var path:=folder.path_join("durable").path_join(first.digest.hex_encode()+".baseline");var bytes:=FileAccess.get_file_as_bytes(path)
	check(DirAccess.rename_absolute(path,path+".absent")==OK,"temporarily hide owned baseline fixture")
	check(store.restore_storage_snapshot(manifest),"manifest restoration does not scan baseline payloads")
	check(not store.load_baseline(10,digest("location-v1")).ok and not publish(store,10,sections).ok,"missing baseline fails closed and is not recaptured from live edits")
	check(store.load_baseline(20,digest("location-v1")).ok,"missing first baseline does not hide second location")
	check(DirAccess.rename_absolute(path+".absent",path)==OK,"restore owned baseline fixture")
	var corrupted:=bytes.duplicate();corrupted[corrupted.size()-1]^=1;write(path,corrupted)
	check(not store.load_baseline(10,digest("location-v1")).ok and not publish(store,10,sections).ok,"corrupted baseline is neither accepted nor silently replaced")
	write(path,bytes)
	var loaded:Dictionary=store.load_baseline(10,digest("location-v1"));loaded.sections.mod_example[0]=99
	check(store.load_baseline(10,digest("location-v1")).sections==sections,"caller mutation cannot alter persistent original")
	for mutation in [0,4,8,12,16,48]:
		var broken:=manifest.duplicate();broken[mutation]^=128;broken=seal(broken)
		if mutation==16:check(not store.restore_storage_snapshot(broken),"wrong world identity rejected before changing manifest");continue
		check(not store.validate_snapshot(broken) and not store.restore_storage_snapshot(broken),"malformed reference rejected at byte "+str(mutation))
	var broken:=manifest.duplicate();broken.encode_u64(128,10);broken=seal(broken)
	check(not store.restore_storage_snapshot(broken),"duplicate ordered location IDs rejected")
	for invalid_size in [0,16*1024*1024+1]:
		broken=manifest.duplicate();broken.encode_u64(120,invalid_size);broken=seal(broken)
		check(not store.restore_storage_snapshot(broken),"invalid blob size rejected: "+str(invalid_size))
	broken=manifest.duplicate();broken[broken.size()-1]^=1
	check(not store.restore_storage_snapshot(broken),"manifest checksum damage rejected")
	broken=manifest.slice(0,manifest.size()-1)
	check(not store.restore_storage_snapshot(broken),"truncated manifest rejected")
	broken=manifest.duplicate();broken.append(0)
	check(not store.restore_storage_snapshot(broken),"extended manifest rejected")
	check(store.capture_storage_snapshot()==manifest,"all rejected manifest restores remain atomic")
	broken=manifest.duplicate();broken[56]^=1;broken=seal(broken)
	check(store.restore_storage_snapshot(broken) and not store.load_baseline(10,broken.slice(56,88)).ok,"changed definition inside re-signed manifest fails blob metadata binding")
	broken=manifest.duplicate();broken.encode_u64(48,11);broken=seal(broken)
	check(store.restore_storage_snapshot(broken) and not store.load_baseline(11,digest("location-v1")).ok,"changed location key fails blob metadata binding")
	check(store.restore_storage_snapshot(manifest),"original reference manifest restores")
	var foreign:=create_store("foreign",digest("world-two"));broken=manifest.duplicate()
	for index in 32:broken[16+index]=digest("world-two")[index]
	broken=seal(broken)
	check(DirAccess.copy_absolute(path,folder.path_join("foreign").path_join(path.get_file()))==OK,"copy owned fixture for cross-world refusal")
	check(foreign.restore_storage_snapshot(broken) and not foreign.load_baseline(10,digest("location-v1")).ok,"same seed/definition data cannot bypass world identity binding")
	var failures_store:=create_store("io-failure");var predicted:=blob_id(packet(30,sections));var blocked_path:=folder.path_join("io-failure").path_join(predicted.hex_encode()+".baseline")
	var blocker:RefCounted=ClassDB.instantiate("NativeWorldArchive");check(blocker.acquire(blocked_path),"hold only test-owned publication lease")
	check(not publish(failures_store,30,sections).ok and failures_store.state().locations==0,"writer contention cannot publish a dangling reference")
	blocker.release();check(publish(failures_store,30,sections).ok,"publication succeeds after writer lease release")
	blocked_path=folder.path_join("io-failure").path_join(blob_id(packet(31,sections)).hex_encode()+".baseline")
	check(DirAccess.make_dir_recursive_absolute(blocked_path)==OK,"create owned directory fault fixture")
	check(not publish(failures_store,31,sections).ok and failures_store.state().locations==1,"publication failure leaves earlier valid reference untouched")
	var capacity:=create_store("capacity")
	var capacity_ok:=true
	for key in range(1,129):capacity_ok=publish(capacity,key,sections).ok and capacity_ok
	var began:=Time.get_ticks_usec();var maximum:PackedByteArray=capacity.capture_storage_snapshot();var capture_us:=Time.get_ticks_usec()-began
	check(capacity_ok and maximum.size()==10320 and capacity.validate_snapshot(maximum),"128 locations use a 10,320-byte reference manifest")
	check(not publish(capacity,129,sections).ok and capacity.capture_storage_snapshot()==maximum,"location capacity rejects without evicting earlier baseline")
	broken=maximum.duplicate()
	for index in 128:broken.encode_u64(48+index*80+72,16*1024*1024)
	broken=seal(broken)
	check(not capacity.restore_storage_snapshot(broken),"aggregate referenced-byte limit is enforced")
	large.resize(15*1024*1024);large.fill(7);missing=sections.duplicate();missing.mod_bulk=large
	var bulk:=create_store("bulk");began=Time.get_ticks_usec();var worker:=Thread.new()
	check(worker.start(publish.bind(bulk,1,missing))==OK,"large immutable payload publishes on worker")
	var maximum_query_us:=0;var queries:=0;var observed_busy:=false;var coherent:=true
	while worker.is_alive():
		var query_begin:=Time.get_ticks_usec();var current:PackedByteArray=bulk.capture_storage_snapshot();var state:Dictionary=bulk.state()
		maximum_query_us=maxi(maximum_query_us,Time.get_ticks_usec()-query_begin);queries+=1
		observed_busy=observed_busy or state.io_active;coherent=coherent and current.size() in [80,160] and bulk.validate_snapshot(current)
		await process_frame
	var published:Dictionary=worker.wait_to_finish();var publish_us:=Time.get_ticks_usec()-began
	check(coherent and queries>0,"worker publication leaves manifest readable and atomically old or new")
	began=Time.get_ticks_usec();var received:Dictionary=bulk.load_baseline(1,digest("location-v1"));var read_us:=Time.get_ticks_usec()-began
	check(published.ok and received.ok and received.sections==missing,"large bounded extension payload publishes and reads exactly")
	print("LOCATION_BASELINE_TIMING manifest_bytes=",maximum.size()," capture_us=",capture_us," blob_bytes=",published.get("bytes",0)," publish_us=",publish_us," read_us=",read_us)
	print("LOCATION_BASELINE_WORKER queries=",queries," observed_busy=",observed_busy," maximum_query_us=",maximum_query_us)
	check(store.restore_storage_snapshot(PackedByteArray()) and store.state().locations==0,"legacy empty manifest leaves no invented baselines")
	check(store.restore_storage_snapshot(manifest) and store.load_baseline(10,digest("location-v1")).ok,"clearing references never deletes preserved originals")
	finish()

func finish()->void:
	print("LOCATION_BASELINE checks=",checks," failures=",failures);quit(1 if failures else 0)
