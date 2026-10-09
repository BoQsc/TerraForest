# SPDX-License-Identifier: 0BSD
extends SceneTree
const DIR="res://reports/generated_settlement_return/"
const Checkpoint=preload("res://tests/connected_world_reopen.gd")
var checks: Array=[]
var phases: Array=[]
func check(ok: bool,label: String) -> void:
	checks.append({"ok":ok,"label":label});print("PASS " if ok else "FAIL ",label)
func _initialize() -> void:run.call_deferred()
func model_state(game: Node) -> Dictionary:
	var state: Dictionary={}
	for key in ["table","chair","shelf"]:
		var batch: Node=game.structures.model("furniture/"+key+"/v1")
		state[key]={"render":batch.render_stats(),"collision":batch.collision_stats()}
	return state
func resident(state: Dictionary,wanted: int) -> bool:
	for item: Dictionary in state.values():
		if item.render.resident_instances!=wanted or item.collision.resident_bodies!=wanted:return false
	return true
func run() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence/staged_placement/manifest.json"))
	var game=load("res://demo/world.tscn").instantiate();root.add_child(game)
	var deadline:=Time.get_ticks_msec()+60000
	while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
	if game.terrain.save_slot!=manifest.slot:
		check(false,"disposable checkpoint slot required");game.terrain.shutdown();quit(1);return
	check(not game.loading_active,"saved world ready")
	check(preload("res://addons/presentation/fullscreen_policy.gd").measurement(root).fair_graphical_sample and Engine.max_fps==60,"fullscreen1080p cap60")
	game.set_physics_process(false);game._clear_motion();game.fly=true;game.needs_floor_spawn=false
	var target:=Vector3(manifest.target[0],manifest.target[1],manifest.target[2])
	var home:=target+Vector3(4.5,3,0)
	var before: Dictionary=Checkpoint.snapshots(game)
	var cover: PackedByteArray=game.ground_cover.removed.capture_storage_snapshot()
	for phase in ["home","away","return"]:
		var start:=Time.get_ticks_msec()
		game.player.position=home+(Vector3(800,80,0) if phase=="away" else Vector3.ZERO)
		game.terrain.focus=game.player.position
		game.camera.look_at(game.player.position+Vector3(0,0,-10))
		deadline=Time.get_ticks_msec()+15000
		var wanted:=0 if phase=="away" else 4
		# Require multiple process ticks, including focus propagation and native residency work.
		for frame in 10:await process_frame
		while not resident(model_state(game),wanted) and Time.get_ticks_msec()<deadline:await process_frame
		var state:=model_state(game)
		check(resident(state,wanted),phase+" furniture render and collision population")
		phases.append({"phase":phase,"wait_ms":Time.get_ticks_msec()-start,"models":state,"blocks":game.structures.blocks.streaming_stats(),"paging":game.structures.region_paging_stats()})
		if phase=="away":continue
		var bounds:=AABB(target+Vector3(-2,-2,-24),Vector3(18,16,64))
		deadline=Time.get_ticks_msec()+15000
		while not game.structures.blocks.is_collision_region_ready(bounds) and Time.get_ticks_msec()<deadline:await process_frame
		check(game.structures.blocks.is_collision_region_ready(bounds),phase+" building collision ready")
		if phase=="return":
			var after: Dictionary=Checkpoint.snapshots(game)
			for key: String in before:check(after[key]==before[key],"exact "+key+" state after departure and return")
			check(game.ground_cover.removed.capture_storage_snapshot()==cover,"ground-cover edits preserved across travel")
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(DIR+"returned.png")
	check(phases[1].paging.evicted>phases[0].paging.evicted and phases[1].blocks.mesh_payload_bytes==0,"departure evicts block regions and rendered meshes")
	check(phases[2].paging.admitted>phases[1].paging.admitted and phases[2].paging.failed_reads==0,"return readmits block regions without read errors")
	game.shutdown_requested=true
	check(await game.terrain.shutdown_after_edits(),"normal save after return")
	var failed:=checks.filter(func(row):return not row.ok).size()
	var result:={"checks":checks,"failures":failed,"phases":phases,"scope":"800m focus relocation out and back in the combined saved world. Verifies eviction/readmission and exact authoring state, not continuous player/vehicle travel, terrain arrival latency, dense populations or frame performance."}
	var file:=FileAccess.open(DIR+"result.json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "));file.close()
	game.free();await process_frame;quit(1 if failed else 0)
