# SPDX-License-Identifier: 0BSD
extends SceneTree

var checks:=0
var failures:=0
var world:Node
var terrain:Node
var inventory:RefCounted
var persistence:RefCounted
var probe:CaptureProbe
var slot:="direct_teardown_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]

class CaptureProbe extends Node3D:
	var inventory:RefCounted
	var detached_captures:=0
	func capture()->PackedByteArray:
		if not is_inside_tree():detached_captures+=1
		return inventory.capture_storage_snapshot()

func _initialize()->void:run.call_deferred()

func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1
	print("PASS " if value else "FAIL ",label)

func wait_for(predicate:Callable)->bool:
	var deadline:=Time.get_ticks_msec()+20000
	while not predicate.call() and Time.get_ticks_msec()<deadline:await process_frame
	return predicate.call()

func open_world()->bool:
	world=Node.new();root.add_child(world)
	inventory=ClassDB.instantiate("NativePlayerInventory");inventory.register_item(101,999)
	terrain=load("res://addons/volumetric_terrain/terrain_world.gd").new()
	terrain.save_slot=slot;terrain.diagnostics_pause_streaming=true;terrain.require_published_shutdown=true
	terrain.backend.disk_cache.enabled=false;terrain.backend.world_generator=3;world.add_child(terrain)
	probe=CaptureProbe.new();probe.inventory=inventory;world.add_child(probe)
	persistence=load("res://addons/world_runtime/world_persistence.gd").new()
	if not persistence.register_component("player_loadout",probe.capture,inventory.restore_storage_snapshot,inventory,inventory.capture_storage_snapshot()) or persistence.attach(terrain)!=OK:return false
	return terrain.start(StandardMaterial3D.new(),false)==OK and await wait_for(func()->bool:return terrain.world_ready)

func dispose()->void:
	if is_instance_valid(world):world.free()
	persistence=null;inventory=null

func run()->void:
	Engine.max_fps=60
	GDExtensionManager.load_extension("res://addons/player_runtime/player_runtime.gdextension")
	GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
	if not check_open(await open_world()):return
	check(inventory.grant(101,7,inventory.snapshot().revision).ok,"baseline inventory is authored")
	var saved:={"received":false,"ok":false}
	terrain.save_completed.connect(func(ok:bool):saved.received=true;saved.ok=ok,CONNECT_ONE_SHOT)
	terrain.save_world()
	if not check_save(await wait_for(func()->bool:return saved.received) and saved.ok):return
	var path:="user://worlds/"+slot+".trw"
	var canonical:=FileAccess.get_sha256(path)
	check(inventory.grant(101,9,inventory.snapshot().revision).ok,"unsaved runtime state differs from baseline")
	root.remove_child(world)
	check(probe.detached_captures==0,"direct scene teardown never captures detached sibling providers")
	check(FileAccess.get_sha256(path)==canonical,"direct teardown preserves last verified compound checkpoint")
	dispose()
	if not check_open(await open_world()):return
	check(inventory.snapshot().slots[0].count==7,"fresh worker restores previous checkpoint, not teardown-time state")
	check(inventory.grant(101,3,inventory.snapshot().revision).ok,"normal graceful-close change authored")
	check(await terrain.shutdown_after_edits(),"normal graceful shutdown still saves attached provider state")
	root.remove_child(world)
	check(probe.detached_captures==0,"graceful close does not recapture after tree removal")
	dispose()
	if not check_open(await open_world()):return
	check(inventory.snapshot().slots[0].count==10,"graceful shutdown changes survive fresh worker restoration")
	check(await terrain.shutdown_after_edits(),"final normal shutdown completes")
	dispose();finish()

func check_open(value:bool)->bool:
	check(value,"isolated persistent world starts")
	if not value:dispose();finish()
	return value

func check_save(value:bool)->bool:
	check(value,"baseline compound checkpoint publishes")
	if not value:dispose();finish()
	return value

func finish()->void:
	print("DIRECT_TEARDOWN_CHECKPOINT checks=%d failures=%d"%[checks,failures])
	quit(1 if failures else 0)
