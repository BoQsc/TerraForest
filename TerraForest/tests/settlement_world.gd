# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok: failures+=1
func wait_edit(game: Node) -> void:
	var deadline:=Time.get_ticks_msec()+15000
	while game.terrain.pending_edit and Time.get_ticks_msec()<deadline: await process_frame
	check(not game.terrain.pending_edit,"terrain edit publication finishes")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	Engine.max_fps=60
	var game=load("res://demo/world.tscn").instantiate();game.temporary_world=true
	game.terrain.backend.world_generator=2;game.terrain.backend.world_seed=1703;root.add_child(game)
	var deadline:=Time.get_ticks_msec()+30000
	while game.loading_active and Time.get_ticks_msec()<deadline: await process_frame
	check(not game.loading_active,"combined world starts")
	print("STARTUP_STATE ",{"reason":game.loading_reason,"ready":game.terrain.world_ready,"error":game.terrain.latest_error,"queued":game.terrain.backend.queued(),"worker":game.terrain.backend.status(),"terrain_processing":game.terrain.is_processing(),"world_processing":game.is_processing()})
	if game.loading_active: game.terrain.shutdown();game.free();quit(1);return
	game.set_physics_process(false);game._clear_motion();game.app_focused=true;game.structure_mode=true
	var origin:=Vector3i(ceili(game.player.position.x)+30,ceili(game.player.position.y)+2,ceili(game.player.position.z))
	var asset=ClassDB.instantiate("NativeBlockPrefab")
	asset.compose_frontage([load("res://addons/structures/prefabs/brick_cottage.tres")],8,8,3,1703)
	var survey=preload("res://addons/structures/site_survey.gd").new()
	var site: Dictionary=await survey.assess(game.terrain,asset,origin,0)
	check(site.ok,"whole footprint admits a bounded terrain grade")
	print("SITE_PLAN ",site)
	if not site.ok: game.terrain.shutdown();game.free();quit(1);return
	origin.y=site.grade
	var p:=Vector3(origin)
	var plan: Dictionary=preload("res://addons/structures/site_plan.gd").foundation(asset,origin,0,origin.y)
	check(plan.ok,"layout derives bounded foundation grading plan")
	if not plan.ok: game.terrain.shutdown();game.free();quit(1);return
	print("SITE_GRADING_SEGMENTS ",plan.segments.size())
	for segment: Dictionary in plan.segments:
		check(game.terrain.construct_graded_bed(segment.start,segment.finish,segment.half_width,segment.depth,segment.clearance,segment.material,segment.shoulder),"planned foundation grading accepted")
		await wait_edit(game)
	check(game.terrain.construct_road_bed(p,p+Vector3(93,0,0),5,8,12),"street paving accepted")
	await wait_edit(game)
	asset.set_meta("frontage_version",1);asset.resource_name="Combined world street"
	game.structure_prefabs.append(asset);game.structure_prefab_index=game.structure_prefabs.size()-1
	asset.changed.connect(game._invalidate_prefab_preview);game.construction_palette.configure(game.structure_prefabs)
	game._begin_frontage_placement(asset,origin)
	var validation_started:=Time.get_ticks_usec()
	deadline=Time.get_ticks_msec()+12000
	var next_trace:=0
	while not game._foundation_placement.is_empty() and Time.get_ticks_msec()<deadline:
		await process_frame
		if Time.get_ticks_msec()>=next_trace:
			next_trace=Time.get_ticks_msec()+1000
			print("FOUNDATION_PROGRESS ",{"offset":game.foundation_check.offset,"waiting":game.foundation_check.waiting,"deep":game.foundation_check.deep_support,"clearance":game.foundation_check.clearance,"queued":game.terrain.backend.queued(),"worker":game.terrain.backend.status(),"brush":game.terrain.foreground_brush})
	check(game.foundation_check.status=="supported" and not game.structures.blocks.can_place_prefab(asset,origin,0),"sixteen cottages pass live terrain checks and place")
	print("FOUNDATION_VALIDATION_MS ",(Time.get_ticks_usec()-validation_started)/1000.0)
	game.camera.global_position=p+Vector3(115,60,75);game.camera.look_at(p+Vector3(42,3,0))
	var intervals:=PackedFloat64Array();var previous:=Time.get_ticks_usec()
	for frame in 180:
		await process_frame
		var now:=Time.get_ticks_usec();intervals.append((now-previous)/1000.0);previous=now
	intervals.sort()
	var result:={"failures":failures,"origin":origin,"foundation_status":game.foundation_check.status,"frame_p95_ms":intervals[170],"frame_max_ms":intervals[-1],"structures":game.structures.blocks.stats(),"vegetation_roots":game.vegetation.renderer.roots.size(),"pending_vegetation_owners":game.ecosystem._reconcile.size(),"scope":"16 cottages on three live graded/paved terrain edits with live forest, followed by 180 graphical frames. No vehicle, populated-city or thermal guarantee."}
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://reports/settlement_world.png")
	var file:=FileAccess.open("res://reports/settlement_world.json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "));file.close()
	print(JSON.stringify(result));game.terrain.shutdown();game.queue_free();await process_frame;quit(1 if failures else 0)
