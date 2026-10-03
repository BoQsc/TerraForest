# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok: failures+=1
func guard(_bounds: AABB) -> String: return ""
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var terrain=preload("res://addons/volumetric_terrain/terrain_world.gd").new()
	terrain.diagnostics_pause_streaming=true;terrain.backend.world_generator=2;root.add_child(terrain)
	terrain.start(StandardMaterial3D.new(),true)
	var deadline:=Time.get_ticks_msec()+30000
	while not terrain.world_ready and Time.get_ticks_msec()<deadline: await process_frame
	check(terrain.world_ready,"native terrain worker starts")
	var segment={"start":Vector3(400,180,400),"finish":Vector3(420,180,400),"half_width":4.0,"depth":8.0,"clearance":12.0,"material":1,"shoulder":0.0}
	var plan={"ok":true,"bounds":AABB(Vector3(396,172,396),Vector3(28,20,8)),"segments":[segment,segment.duplicate()]}
	var runner=preload("res://addons/structures/site_preparation.gd").new()
	var revision: int=terrain.density_revision
	check(runner.begin(plan,terrain,guard),"repeated-section preparation admitted")
	deadline=Time.get_ticks_msec()+15000
	while runner.status=="running" and Time.get_ticks_msec()<deadline:
		runner.tick(terrain,guard);await process_frame
	check(runner.status=="complete" and runner.completed==2,"changed section and identical no-op both complete")
	check(terrain.density_revision==revision+1 and terrain.last_edit_outcome.status=="unchanged","native no-op preserves revision and supplies explicit outcome")
	check(runner.begin(plan,terrain,guard),"already prepared site can be submitted again")
	deadline=Time.get_ticks_msec()+15000
	while runner.status=="running" and Time.get_ticks_msec()<deadline:
		runner.tick(terrain,guard);await process_frame
	check(runner.status=="complete" and runner.completed==2 and terrain.density_revision==revision+1,"entire already prepared site completes without changing terrain")
	print("FINAL_OUTCOME ",terrain.last_edit_outcome)
	terrain.shutdown();terrain.free();quit(1 if failures else 0)
