# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok: failures+=1
func _initialize() -> void: call_deferred("run")
func wait_placement(game: Node) -> void:
	var deadline:=Time.get_ticks_msec()+12000
	while not game._foundation_placement.is_empty() and Time.get_ticks_msec()<deadline: await process_frame
func wait_edit(game: Node) -> void:
	var deadline:=Time.get_ticks_msec()+15000
	while game.terrain.pending_edit and Time.get_ticks_msec()<deadline: await process_frame
func run() -> void:
	Engine.max_fps=60
	var game=load("res://demo/world.tscn").instantiate();game.temporary_world=true
	game.terrain.backend.world_generator=2;game.terrain.backend.world_seed=1703;root.add_child(game)
	var deadline:=Time.get_ticks_msec()+30000
	while game.loading_active and Time.get_ticks_msec()<deadline: await process_frame
	check(not game.loading_active,"world starts")
	if not game.loading_active:
		game.set_physics_process(false);game._clear_motion();game.app_focused=true;game.structure_mode=true
		var asset=ClassDB.instantiate("NativeBlockPrefab")
		asset.compose_frontage([load("res://addons/structures/prefabs/brick_cottage.tres")],3,8,3,1703)
		asset.set_meta("frontage_version",1);asset.resource_name="Six cottage test"
		game.structure_prefabs.append(asset);game.structure_prefab_index=game.structure_prefabs.size()-1
		game.construction_palette.configure(game.structure_prefabs)
		asset.changed.connect(game._invalidate_prefab_preview)
		check(asset.foundation_samples(Vector3i.ZERO,0,0).size()>512,"fixture requires multiple worker batches")
		var target:=Vector3i(400,230,400)
		game._begin_frontage_placement(asset,target);await wait_placement(game)
		check(game.foundation_check.status.begins_with("Unsupported") and game.structures.blocks.can_place_prefab(asset,target,0),"unsupported frontage rejected without placing cells")
		target=Vector3i(400,180,400)
		for z in [387,413]:
			check(game.terrain.construct_graded_bed(Vector3(400,180,z),Vector3(433,180,z),8,8,12,1),"foundation grading submitted")
			await wait_edit(game)
		game._begin_frontage_placement(asset,target)
		game.structure_rotation=1
		await wait_placement(game)
		check(game.foundation_check.status=="Placement cancelled" and game.structures.blocks.can_place_prefab(asset,target,0),"rotation change cancels deferred placement")
		game.structure_rotation=0
		game._begin_frontage_placement(asset,target);await wait_placement(game)
		check(game.foundation_check.status.begins_with("Fill lacks support") and game.structures.blocks.can_place_prefab(asset,target,0),"floating graded slab rejected despite solid surface probes")
		check(game.terrain.sculpt_sphere(Vector3(416,160,400),32,true,1),"controlled underlying hill added")
		await wait_edit(game)
		for z in [387,413]:
			game.terrain.construct_graded_bed(Vector3(400,180,z),Vector3(433,180,z),8,8,12,1)
			await wait_edit(game)
		check(game.terrain.sculpt_sphere(Vector3(404,183,389),1,true,1),"interior obstruction submitted above supported foundation")
		await wait_edit(game)
		game._begin_frontage_placement(asset,target);await wait_placement(game)
		check(game.foundation_check.status.begins_with("Terrain inside") and game.structures.blocks.can_place_prefab(asset,target,0),"terrain filling interior rejects placement despite supported floor")
		check(game.terrain.construct_graded_bed(Vector3(400,180,387),Vector3(433,180,387),8,8,12,1),"interior clearance grading submitted")
		await wait_edit(game)
		game._begin_frontage_placement(asset,target);await wait_placement(game)
		check(game.foundation_check.status=="supported" and not game.structures.blocks.can_place_prefab(asset,target,0),"supported six-cottage frontage commits after multiple batches")
		game.prefab_library.directory="user://frontage_editor_async_%d" % Time.get_ticks_usec()
		game.structure_prefab_index=0
		var previous_count: int=game.structure_prefabs.size()
		game._frontage_construction(64,8,3,1703,"Async editor frontage")
		deadline=Time.get_ticks_msec()+10000
		while game.structure_prefabs.size()==previous_count and Time.get_ticks_msec()<deadline: await process_frame
		check(game.structure_prefabs.size()==previous_count+1 and game.structure_prefabs.back().get_cell_count()==59904,"world authoring action publishes maximum frontage from worker")
		for file in DirAccess.get_files_at(game.prefab_library.directory): DirAccess.remove_absolute(game.prefab_library.directory.path_join(file))
		DirAccess.remove_absolute(game.prefab_library.directory)
	game.terrain.shutdown();game.queue_free();await process_frame
	quit(1 if failures else 0)
