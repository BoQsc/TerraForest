# SPDX-License-Identifier: 0BSD
extends SceneTree
const Persistence=preload("res://addons/world_runtime/world_persistence.gd")
const NAMES=["terrain","blocks","cubes","models","doors","damage","containers","residents","corpses","trees","ground","water"]
var folder:=""
var checks:=0
var failures:=0

class Backend extends RefCounted:
	var save_path:=""
	var temporary:=false
	var readonly_snapshot:=false
	var snapshot_codec:RefCounted
	var snapshot_capture:Callable
	var snapshot_preparers:Dictionary={}
	var snapshot_validators:Dictionary={}

class Host extends Node:
	var backend:=Backend.new()
	var world_ready:=false
	var _started:=false
	var snapshot_restore_ok:=true
	var prepared_snapshot_components:Dictionary={}
	var begin:Callable
	var step:Callable
	func configure_snapshot_restore(first:Callable,next:Callable)->void:begin=first;step=next

func _initialize()->void:
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--baseline-dir="):folder=argument.trim_prefix("--baseline-dir=").path_join("publication")
	run.call_deferred()

func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1
	print("PASS " if value else "FAIL ",label)

func write(path:String,data:PackedByteArray)->void:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	check(file!=null,"write isolated fixture "+path.get_file())
	if file!=null:file.store_buffer(data);file.close()

func publish(store:RefCounted,key:int,sections:Dictionary)->Dictionary:
	var state:Dictionary=store.state()
	return store.publish_baseline(key,"location-v1".sha256_buffer(),sections,state.revision,state.owner)

func reopen()->void:
	var archive:RefCounted=ClassDB.instantiate("NativeWorldArchive")
	var root_path:=folder.path_join("copy.trw")
	var decoded:Dictionary=archive.decode(archive.read(root_path))
	check(decoded.ok,"fresh process reads published compound root")
	var host:=Host.new();host.backend.save_path=root_path;host.backend.readonly_snapshot=true
	var persistence:=Persistence.new()
	check(persistence.attach(host)==OK,"fresh process attaches actual persistence provider")
	host.begin.call(decoded.sections,9);check(host.step.call(0) and host.snapshot_restore_ok,"fresh process restores compact baseline manifest")
	var store:RefCounted=persistence.location_baselines
	check(store.state().locations==1 and store.load_baseline(10,"location-v1".sha256_buffer()).ok,"published world reopens its selected original without source directory")
	check(store.verify_references().ok and store.verify_references().locations==1,"generation verifier checks selected references without directory scan")
	check(not publish(store,30,{}).ok and not store.initialize_world("new".sha256_buffer()),"read-only world cannot publish or replace generation identity")
	check(persistence._capture().sections.location_baselines_v1==decoded.sections.location_baselines_v1,"compound capture preserves exact reference manifest")
	check(not FileAccess.file_exists(root_path+".baselines/baselines.lock"),"read-only open creates no sidecar writer lock")
	host.free()

func run()->void:
	if "--reopen" in OS.get_cmdline_user_args():reopen();finish();return
	DirAccess.make_dir_recursive_absolute(folder)
	var path:=folder.path_join("source.trw")
	var host:=Host.new();host.backend.save_path=path
	var persistence:=Persistence.new()
	check(persistence.attach(host)==OK,"production persistence registers baseline references")
	host.begin.call({},7);check(host.step.call(0) and host.snapshot_restore_ok,"legacy world restores without baseline references")
	check(persistence._capture().sections.location_baselines_v1.is_empty() and not DirAccess.dir_exists_absolute(path+".baselines"),"legacy world remains baseline-free without filesystem writes")
	check(persistence.location_baselines.verify_references().ok,"legacy verification does not require a directory")
	host.world_ready=true
	check(persistence.initialize_location_baselines(),"new generation initializes independent world identity")
	check(not persistence.initialize_location_baselines(),"generation identity cannot be replaced")
	var store:RefCounted=persistence.location_baselines
	check(not DirAccess.dir_exists_absolute(path+".baselines"),"identity initialization performs no directory work")
	var sections:Dictionary={}
	for name:String in NAMES:sections[name]=PackedByteArray()
	sections.terrain=PackedByteArray([7,8,9]);sections.mod_example=PackedByteArray([1,2])
	var first:=publish(store,10,sections)
	check(first.ok,"generation baseline first write creates lazy store")
	if not first.ok:host.free();finish();return
	var manifest:PackedByteArray=store.capture_storage_snapshot()
	var orphan:=publish(store,20,sections)
	check(orphan.ok and store.restore_storage_snapshot(manifest),"unreferenced immutable original retained only in source")
	var archive:RefCounted=ClassDB.instantiate("NativeWorldArchive")
	var saved:Dictionary=persistence._capture().sections;saved["terrain"]=PackedByteArray([1,2,3])
	var canonical:PackedByteArray=archive.encode(saved)
	var saved_ok:bool=not canonical.is_empty() and archive.acquire(path) and archive.publish(path,canonical)==OK
	check(saved_ok,"actual provider reference captured in compound world")
	archive.release()
	if not saved_ok:host.free();finish();return
	check(not persistence.initialize_location_baselines(),"existing saved world is never recaptured as generation")
	var result:Dictionary=archive.clone_world(folder,"source","copy")
	check(result.ok and result.files==1 and result.bytes==first.bytes,"publication copies only one referenced baseline")
	if not result.ok:print(result);host.free();finish();return
	var filename:String=first.digest.hex_encode()+".baseline"
	check(DirAccess.get_files_at(folder.path_join("copy.trw.baselines"))==PackedStringArray([filename]),"publication excludes orphan payloads and lease files")
	check(archive.read(folder.path_join("copy.trw"))==canonical,"publication preserves world identity and manifest exactly")
	var original_path:=path+".baselines/"+filename
	var packet:=FileAccess.get_file_as_bytes(original_path)
	check(not archive.clone_world(folder,"source","copy").ok,"publication refuses overwrite")
	DirAccess.make_dir_recursive_absolute(folder.path_join("existing.trw.baselines"))
	check(not archive.clone_world(folder,"source","existing").ok,"destination baseline sidecar blocks publication")
	for suffix:String in ["regions","models","water","terrain"]:
		DirAccess.make_dir_recursive_absolute(path+"."+suffix)
		write(path+"."+suffix+"/data.bin",PackedByteArray([4,5]))
	for phase in 6:
		var destination:="interrupted_%d"%phase
		var stopped:Dictionary=archive.clone_world(folder,"source",destination,phase)
		check(not stopped.ok and stopped.has("staging") and not FileAccess.file_exists(folder.path_join(destination+".trw")),"phase %d interruption never publishes root early"%phase)
		var recovered:Dictionary=archive.recover_world(folder,destination)
		check(recovered.ok and recovered.get("recovered",false),"phase %d recovery verifies selected baselines"%phase)
		check(FileAccess.get_file_as_bytes(folder.path_join(destination+".trw.baselines/"+filename))==packet,"recovery preserves exact original payload")
	var damaged:Dictionary=archive.clone_world(folder,"source","damaged",1)
	if not damaged.has("staging"):check(false,"failed to create interrupted fixture: "+str(damaged));host.free();finish();return
	var damaged_path:String=damaged.staging.path_join("baselines/"+filename)
	write(damaged_path,PackedByteArray([0]))
	check(not archive.recover_world(folder,"damaged").ok and not FileAccess.file_exists(folder.path_join("damaged.trw")),"damaged baseline prevents recovery root publication")
	check(DirAccess.dir_exists_absolute(damaged.staging.path_join("models")),"failed baseline verification does not promote other pending owners")
	write(damaged_path,packet)
	check(archive.recover_world(folder,"damaged").ok,"repairing isolated damaged fixture permits verified recovery")
	check(DirAccess.rename_absolute(original_path,original_path+".held")==OK,"temporarily withhold owned fixture baseline")
	var missing:Dictionary=archive.clone_world(folder,"source","missing")
	check(not store.verify_references().ok,"generated-world verifier rejects missing referenced original")
	check(not missing.ok and not FileAccess.file_exists(folder.path_join("missing.trw")),"missing referenced original rejects publication")
	check(not archive.recover_world(folder,"missing").get("recovered",false),"incomplete baseline copy cannot recover into playable world")
	check(DirAccess.rename_absolute(original_path+".held",original_path)==OK,"restore owned fixture original")
	write(original_path,PackedByteArray([8]))
	check(not store.verify_references().ok,"generated-world verifier rejects corrupt original")
	check(not archive.clone_world(folder,"source","corrupt").ok,"corrupt original rejects publication")
	write(original_path,packet)
	var altered:=manifest.duplicate();altered[16]^=1
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(altered.slice(0,altered.size()-32))
	altered=altered.slice(0,altered.size()-32);altered.append_array(hash.finish())
	var forged:=saved.duplicate();forged.location_baselines_v1=altered
	var forged_path:=folder.path_join("forged.trw")
	check(archive.acquire(forged_path) and archive.publish(forged_path,archive.encode(forged))==OK,"write checksummed wrong-world manifest fixture");archive.release()
	DirAccess.make_dir_recursive_absolute(forged_path+".baselines");write(forged_path+".baselines/"+filename,packet)
	check(not archive.clone_world(folder,"forged","forged_copy").ok,"re-signed wrong-world manifest cannot publish another world's original")
	var generated:="combined_stage_"+"a".repeat(32)
	check(archive.clone_world(folder,"source",generated).ok,"create isolated generation publication fixture")
	var retired:Dictionary=archive.clone_world(folder,generated,"published",-1,true)
	check(retired.ok and retired.get("source_retired",false) and not DirAccess.dir_exists_absolute(folder.path_join(generated+".trw.baselines")),"completed generation retires redundant baseline sidecar")
	check(FileAccess.get_file_as_bytes(folder.path_join("published.trw.baselines/"+filename))==packet,"retirement preserves published immutable original")
	check(FileAccess.file_exists(path+".baselines/"+orphan.digest.hex_encode()+".baseline"),"ordinary source and its unreferenced evidence remain untouched")
	var legacy_path:=folder.path_join("legacy.trw")
	check(archive.acquire(legacy_path) and archive.publish(legacy_path,archive.encode({"terrain":PackedByteArray([1])}))==OK,"write legacy fixture");archive.release()
	DirAccess.make_dir_recursive_absolute(legacy_path+".baselines");write(legacy_path+".baselines/unreferenced",PackedByteArray([9]))
	check(archive.clone_world(folder,"legacy","legacy_copy").ok and not DirAccess.dir_exists_absolute(folder.path_join("legacy_copy.trw.baselines")),"legacy publication does not copy unreferenced directory contents")
	host.free();store=null;persistence=null
	check(DirAccess.rename_absolute(path+".baselines",path+".baselines.held")==OK,"remove source from fresh-process lookup path")
	finish()

func finish()->void:
	print("LOCATION_PUBLICATION checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
