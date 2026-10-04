# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
const Backend=preload("res://addons/volumetric_terrain/terrain_backend.gd")
var checks:=0
var failures:=0
var inventory: RefCounted
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize() -> void: call_deferred("run")
func capture() -> Dictionary:
	return {"epoch":0,"sections":{"player_loadout":inventory.capture_storage_snapshot()}}
func edit_job() -> Dictionary:
	var center:=Vector3(800,8,1310)
	return {"kind":"edit","command":Codec.brush(center,center,2,0,false,1),"epoch":0,"ticket":1,"tiles":[],"geometry_lo":center-Vector3.ONE*8,"geometry_hi":center+Vector3.ONE*8}
func run() -> void:
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	GDExtensionManager.load_extension("res://addons/player_runtime/player_runtime.gdextension")
	GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
	inventory=ClassDB.instantiate("NativePlayerInventory");inventory.register_item(101,999);inventory.grant(101,1,0)
	var backend=Backend.new();backend.native=ClassDB.instantiate("TerrainCore")
	backend.snapshot_codec=ClassDB.instantiate("NativeWorldArchive");backend.snapshot_capture=capture
	backend.snapshot_validators={"player_loadout":inventory};backend.disk_cache.enabled=false
	var path:="user://worlds/save_barrier_%d_%d.trw"%[OS.get_process_id(),Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute("user://worlds");backend.save_path=path
	check(backend.submit({"kind":"save"}),"save captures original addon state before worker starts")
	inventory.grant(101,1,inventory.snapshot().revision)
	check(backend.submit(edit_job(),true),"later priority mutation admitted")
	check(backend.jobs[0].kind=="save" and backend.jobs[1].kind=="edit","priority edit cannot overtake captured save")
	check(backend.start(false)==OK,"real worker starts deterministic queued workload")
	var saved:=false;var edited:=false;var deadline:=Time.get_ticks_msec()+10000
	while not (saved and edited) and Time.get_ticks_msec()<deadline:
		for result: Dictionary in backend.poll():
			if result.get("kind")=="message" and str(result.get("message")).begins_with("World saved and verified"): saved=true
			if result.get("kind")=="edit_done": edited=true
		await process_frame
	check(saved and edited,"save and later native edit both finish")
	var edited_core: RefCounted=backend.native
	backend.disable_snapshot_writes();backend.stop()
	var archive=ClassDB.instantiate("NativeWorldArchive")
	var decoded: Dictionary=archive.decode(archive.read(ProjectSettings.globalize_path(path)))
	check(decoded.ok,"saved compound archive validates")
	if decoded.ok:
		var original=ClassDB.instantiate("NativePlayerInventory");original.register_item(101,999)
		check(original.restore_storage_snapshot(decoded.sections.player_loadout) and original.snapshot().slots[0].count==1,"queued save retains addon state from its own capture")
		var saved_core=ClassDB.instantiate("TerrainCore")
		var restore:=Codec.command(5);restore.append_array(decoded.sections.terrain)
		check(Codec.reply_ok(saved_core.execute(restore)) and saved_core.execute(Codec.command(0)).decode_u32(12)==0 and edited_core.execute(Codec.command(0)).decode_u32(12)>0,"saved terrain precedes later edit while live worker still applies it")
	for suffix in ["",".bak",".lock"]: DirAccess.remove_absolute(path+suffix)
	var queue=Backend.new();queue.native=ClassDB.instantiate("TerrainCore")
	queue.submit({"kind":"mesh","key":Vector3i(1024,1024,16),"epoch":0,"stamp":0})
	queue.submit(edit_job(),true)
	check(queue.jobs[0].kind=="edit" and queue.jobs[1].kind=="mesh","edit retains priority over unrelated background mesh")
	queue.submit({"kind":"load","epoch":1},true)
	check(queue.jobs[0].kind=="edit" and queue.jobs[1].kind=="load","load cannot reorder accepted mutation")
	queue.submit({"kind":"save"});queue.submit({"kind":"reset","epoch":2},true)
	check(queue.jobs[-2].kind=="save" and queue.jobs[-1].kind=="reset","reset stays behind last save barrier")
	print("SAVE_QUEUE_BARRIER ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(1 if failures else 0)
