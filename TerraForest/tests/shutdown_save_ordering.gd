# SPDX-License-Identifier: 0BSD
extends "res://tests/manual_save_ordering.gd"

func open_world() -> bool:
	inventory=ClassDB.instantiate("NativePlayerInventory");inventory.register_item(101,999)
	terrain=load("res://addons/volumetric_terrain/terrain_world.gd").new()
	terrain.save_slot=slot;terrain.diagnostics_pause_streaming=true;terrain.backend.disk_cache.enabled=false
	terrain.backend.world_generator=3;root.add_child(terrain)
	persistence=load("res://addons/world_runtime/world_persistence.gd").new()
	if not persistence.register_component("player_loadout",inventory.capture_storage_snapshot,inventory.restore_storage_snapshot,inventory,inventory.capture_storage_snapshot()) or persistence.attach(terrain)!=OK: return false
	terrain.backend.snapshot_capture=capture
	terrain.region_changed.connect(published)
	return terrain.start(StandardMaterial3D.new(),false)==OK and await wait_ready()

func run() -> void:
	Engine.max_fps=60
	slot="shutdown_save_order_%d"%OS.get_process_id()
	GDExtensionManager.load_extension("res://addons/player_runtime/player_runtime.gdextension")
	GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
	check(await open_world(),"isolated persistent world starts")
	if terrain.world_ready:
		var center:=Vector3(800,30,1310)
		var command:=Codec.brush(center,center,2,0,false,3)
		check(terrain.edit(command,center-Vector3.ONE*8,center+Vector3.ONE*8),"excavation admitted immediately before close")
		var before:=captures
		check(await terrain.shutdown_after_edits(),"graceful close waits for pending edit publication")
		check(granted and captures==before+1 and not terrain.pending_edit,"final snapshot captured after publication callback")
		check(not terrain.edit(command,center-Vector3.ONE*8,center+Vector3.ONE*8),"closing world rejects new edits")
		var revision: int=terrain.density_revision
		terrain.free();persistence=null;inventory=null
		check(await open_world(),"new worker reloads the shutdown save from disk")
		check(inventory.snapshot().slots[0].count==7 and terrain.density_revision==revision,"shutdown save preserves edited terrain and callback inventory together")
		check(await terrain.shutdown_after_edits(),"idle graceful close also completes")
		terrain.free();persistence=null;inventory=null
		check(await open_world(),"reopen verified baseline for failed-publication case")
		inventory.grant(101,9,inventory.snapshot().revision)
		var next_center:=center+Vector3(12,0,0)
		check(terrain.edit(Codec.brush(next_center,next_center,2,0,false,3),next_center-Vector3.ONE*8,next_center+Vector3.ONE*8),"second edit admitted before injected publication error")
		terrain.latest_error="Injected publication failure"
		check(not await terrain.shutdown_after_edits(),"failed publication blocks new shutdown snapshot")
		terrain.free();persistence=null;inventory=null
		check(await open_world(),"previous canonical save remains readable after failed close")
		check(inventory.snapshot().slots[0].count==7 and terrain.density_revision==revision,"failed close cannot overwrite the consistent baseline")
	terrain.shutdown();terrain.free()
	for suffix in [".trw",".trw.bak",".trw.lock"]: DirAccess.remove_absolute("user://worlds/"+slot+suffix)
	print("SHUTDOWN_SAVE_ORDERING ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(1 if failures else 0)
