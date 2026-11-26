# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,label: String) -> void:
	if not ok: failures+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize() -> void:
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	run.call_deferred()
func run() -> void:
	var source:=""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--object-state="): source=argument.trim_prefix("--object-state=")
	var file:=FileAccess.open(source,FileAccess.READ)
	if file==null or file.get_length()>4*1024*1024: check(false,"bounded native state fixture available"); quit(1); return
	var state: Variant=bytes_to_var(file.get_buffer(file.get_length()))
	if not state is Dictionary or not state.get("structures") is PackedByteArray or not state.get("containers") is Dictionary: check(false,"valid native state fixture"); quit(1); return
	var game=load("res://demo/world.tscn").instantiate(); game.temporary_world=true; game.terrain.backend.disk_cache.enabled=false; root.add_child(game)
	var deadline:=Time.get_ticks_msec()+90000
	while game.loading_active and Time.get_ticks_msec()<deadline: game.app_focused=true; await process_frame
	check(not game.loading_active,"fresh process initializes ordinary game providers")
	game.set_physics_process(false)
	for key: String in state.containers: check(game.pack_storage.restore_pack(state.containers[key],key),"fresh-process container restore "+key)
	check(game.storage.restore_structures(state.structures),"ordinary restore owner restores structures and protection")
	check(game.structures.capture_storage_snapshot()==state.structures,"fresh-process model and building state is byte exact")
	var found:=false
	for key: String in game.pack_storage.stores:
		var store: RefCounted=game.pack_storage.stores[key]
		for id: int in store.get_ids():
			found=true
			check(store.snapshot(id).slots[0].item==225 and game.structures.model(key).is_removal_protected(id),"stored contents and removal guard survive process restart")
	check(found,"fresh process contains the player-filled outdoor container")
	game.shutdown_requested=true; check(await game.terrain.shutdown_after_edits(),"fresh process shuts down cleanly"); game.free(); await process_frame
	print("OBJECT_SYSTEM_RESTORE failures=",failures); quit(1 if failures else 0)
