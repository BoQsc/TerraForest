# SPDX-License-Identifier: 0BSD
extends SceneTree
const Terrain=preload("res://addons/volumetric_terrain/terrain_world.gd")
const Lakes=preload("res://addons/volumetric_water/lake_world.gd")
const Persistence=preload("res://addons/world_runtime/world_persistence.gd")
var terrain: Node
var lakes: Node
var persistence: RefCounted
var failures:=0
var slot:="generated_lakes_test_%d" % OS.get_process_id()
var saved:=false
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures+=1
func until(predicate: Callable) -> bool:
	var deadline:=Time.get_ticks_msec()+15000
	while not predicate.call() and Time.get_ticks_msec()<deadline: await process_frame
	return predicate.call()
func start() -> void:
	terrain=Terrain.new();terrain.save_slot=slot;terrain.diagnostics_pause_streaming=true
	terrain.backend.world_generator=4;terrain.backend.world_seed=1703;root.add_child(terrain)
	lakes=Lakes.new();lakes.terrain=terrain;root.add_child(lakes)
	persistence=Persistence.new()
	check(persistence.register_component("volumetric_water",lakes.capture_snapshot,lakes.restore_snapshot,lakes.snapshot_validator(),lakes.empty_snapshot()) and persistence.attach(terrain)==OK,"lake persistence provider attaches")
	terrain.message_changed.connect(func(value: String):
		if value.begins_with("World saved and verified"): saved=true)
	check(terrain.start(StandardMaterial3D.new(),false)==OK,"generated world starts")
func close() -> void:
	terrain.shutdown();lakes.free();terrain.free();persistence=null
func run() -> void:
	Engine.max_fps=60
	start()
	check(await until(func(): return lakes.statistics().ready==4),"fresh world automatically bakes four generated lakes")
	var initial: PackedByteArray=lakes.capture_snapshot()
	lakes.remove_lake(1)
	var expected: PackedByteArray=lakes.capture_snapshot()
	check(expected!=initial and lakes.statistics().lakes==3,"one generated lake can be removed")
	saved=false;terrain.save_world()
	check(await until(func(): return saved),"compound world with modified lake catalog saves")
	close();start()
	check(await until(func(): return lakes.statistics().ready==3),"saved world rebakes remaining lakes")
	check(lakes.capture_snapshot()==expected and not lakes._lakes.has(1),"reload preserves catalog and does not respawn removed generated lake")
	terrain.reload_world(true)
	check(await until(func(): return lakes.statistics().ready==4),"explicit reset regenerates the initial four lakes")
	check(lakes.capture_snapshot()==initial,"reset restores deterministic original lake catalog")
	close()
	var path:=ProjectSettings.globalize_path("user://worlds/"+slot+".trw")
	for suffix in ["",".bak",".lock"]:
		if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(path+suffix)
	quit(1 if failures else 0)
