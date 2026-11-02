# SPDX-License-Identifier: 0BSD
extends SceneTree
const Terrain=preload("res://addons/volumetric_terrain/terrain_world.gd")
const Persistence=preload("res://addons/world_runtime/world_persistence.gd")
const NAMES=["terrain","blocks","cubes","models","doors","damage","containers","residents","corpses","trees","ground","water"]
var checks:=0
var failures:=0
var terrain:Node3D
var persistence:RefCounted
var slot:=""
var saved:=false
var save_ok:=false

func _initialize()->void:
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--world-slot="):slot=argument.trim_prefix("--world-slot=")
	run.call_deferred()

func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1
	print("PASS " if value else "FAIL ",label)

func until(predicate:Callable)->bool:
	var deadline:=Time.get_ticks_msec()+20000
	while not predicate.call() and Time.get_ticks_msec()<deadline:await process_frame
	return predicate.call()

func open_world()->bool:
	terrain=Terrain.new();terrain.save_slot=slot;terrain.diagnostics_pause_streaming=true;root.add_child(terrain)
	persistence=Persistence.new()
	if persistence.attach(terrain)!=OK or terrain.start(StandardMaterial3D.new(),false)!=OK:return false
	return await until(func():return terrain.world_ready)

func close_world()->void:
	terrain.shutdown();terrain.free();terrain=null;persistence=null

func run()->void:
	if not slot.begins_with("check_") or FileAccess.file_exists("user://worlds/"+slot+".trw"):check(false,"requires unique owned fixture slot");finish();return
	check(await open_world(),"real terrain worker initializes baseline provider")
	if not terrain.world_ready:close_world();finish();return
	check(persistence.initialize_location_baselines(),"normal generation identity hook accepts fresh ready world")
	var store:RefCounted=persistence.location_baselines
	var identity:PackedByteArray=store.capture_storage_snapshot()
	check(identity.size()==80,"generation identity stored in bounded empty manifest")
	var field:RefCounted=terrain.backend.native;var token:Dictionary=field.field_patch_state()
	var sections:Dictionary={}
	for name:String in NAMES:sections[name]=PackedByteArray()
	sections.terrain=field.capture_field_patch(Vector3i(799,49,1309),Vector3i(3,3,3),token.revision,token.epoch)
	check(field.validate_field_patch(sections.terrain),"fixture captures real terrain owner patch")
	var current:Dictionary=store.state();var worker:=Thread.new()
	check(worker.start(store.publish_baseline.bind(10,"fixture-v1".sha256_buffer(),sections,current.revision,current.owner))==OK,"original publication schedules off main thread")
	await until(func():return not worker.is_alive())
	var publication:Dictionary=worker.wait_to_finish();check(publication.ok,"original publication completes before save")
	var references:PackedByteArray=store.capture_storage_snapshot()
	saved=false;save_ok=false
	terrain.save_completed.connect(func(ok:bool):saved=true;save_ok=ok,CONNECT_ONE_SHOT)
	terrain.save_world()
	check(await until(func():return saved) and save_ok,"actual worker saves compound root with original references")
	var path:String=ProjectSettings.globalize_path(terrain.backend.save_path)
	store=null;field=null;close_world();await process_frame
	var archive:RefCounted=ClassDB.instantiate("NativeWorldArchive")
	var decoded:Dictionary=archive.decode(archive.read(path))
	check(decoded.ok and decoded.sections.location_baselines_v1==references,"canonical terrain world contains exact reference bytes")
	check(await open_world(),"actual terrain backend reopens compound save")
	check(persistence.location_baselines.capture_storage_snapshot()==references,"actual staged restore preserves world and location identity")
	var loaded:Dictionary=persistence.location_baselines.load_baseline(10,"fixture-v1".sha256_buffer())
	check(loaded.ok and loaded.sections==sections,"restored runtime resolves original owner payload")
	check(not persistence.initialize_location_baselines(),"played world cannot initialize or replace generation original")
	close_world();await process_frame
	var copied:Dictionary=archive.clone_world(path.get_base_dir(),slot,slot+"_copy")
	check(copied.ok,"real terrain world and original sidecar publish together")
	slot+="_copy"
	check(await open_world(),"cloned real world loads through normal terrain backend")
	check(persistence.location_baselines.capture_storage_snapshot()==references and persistence.location_baselines.load_baseline(10,"fixture-v1".sha256_buffer()).ok,"clone resolves its own original after runtime restore")
	close_world();finish()

func finish()->void:
	print("LOCATION_BASELINE_WORLD checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
