# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok: failures+=1
func _initialize() -> void: call_deferred("run")
func run() -> void:
	Engine.max_fps=60
	var game=load("res://demo/world.tscn").instantiate();game.temporary_world=true
	game.terrain.backend.world_generator=2;root.add_child(game)
	var deadline:=Time.get_ticks_msec()+30000
	while game.loading_active and Time.get_ticks_msec()<deadline: await process_frame
	check(not game.loading_active,"world starts")
	if game.loading_active: game.terrain.shutdown();game.free();quit(1);return
	game.set_physics_process(false);game._clear_motion();game.app_focused=true;game.structure_mode=true
	var asset=ClassDB.instantiate("NativeBlockPrefab")
	asset.compose_frontage([load("res://addons/structures/prefabs/brick_cottage.tres")],2,8,3,1703)
	asset.set_meta("frontage_version",1);asset.resource_name="Survey fixture"
	game.structure_prefabs.append(asset);game.structure_prefab_index=game.structure_prefabs.size()-1
	game.construction_palette.configure(game.structure_prefabs)
	game._sync_construction_palette()
	game.camera.global_position=game.player.global_position+Vector3(0,15,0)
	game.camera.look_at(game.player.global_position+Vector3(10,-5,0))
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	await physics_frame;await process_frame
	check(not game._structure_target(false).is_empty(),"editor camera has a real terrain target")
	var revision: int=game.terrain.density_revision
	game.construction_palette.survey_button.pressed.emit()
	check(game.construction_palette.survey_busy and game.construction_palette.survey_button.disabled,"button starts asynchronous survey and prevents duplicate requests")
	deadline=Time.get_ticks_msec()+17000
	while game.construction_palette.survey_busy and Time.get_ticks_msec()<deadline: await process_frame
	check(not game.construction_palette.survey_busy and game.construction_palette.survey_dialog.visible and "Suggested base Y" in game.construction_palette.survey_dialog.dialog_text,"survey displays a usable grade proposal")
	check(game.terrain.density_revision==revision and game.structures.blocks.stats().cells==0,"survey changes neither terrain nor structures")
	await process_frame
	check(game.construction_palette.panel.visible and game.construction_palette.panel.get_global_rect().end.y<=1080,"visible construction panel fits 1080p")
	print("PANEL_RECT ",game.construction_palette.panel.get_global_rect())
	print("SURVEY_DIALOG ",game.construction_palette.survey_dialog.dialog_text)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://reports/settlement_survey_editor.png")
	var original_player: Vector3=game.player.global_position
	game.player.global_position=Vector3(game._survey_plan.target)
	game.construction_palette.preparation_requested.emit()
	print("PREPARATION_GUARD ",game.construction_palette.survey_dialog.dialog_text," state=",game.site_preparation.status)
	check(game.site_preparation.status!="running" and game.terrain.density_revision==revision and "outside" in game.construction_palette.survey_dialog.dialog_text,"player inside complete foundation envelope rejects preparation")
	game.player.global_position=original_player-Vector3(100,0,0)
	game.construction_palette.preparation_requested.emit()
	print("PREPARATION_ADMISSION ",game.site_preparation.status," ",game.site_preparation.reason)
	check(game.site_preparation.status=="running","editor admits preparation after player moves clear")
	deadline=Time.get_ticks_msec()+30000
	while game.site_preparation.status=="running" and Time.get_ticks_msec()<deadline: await process_frame
	check(game.site_preparation.status=="complete" and game.site_preparation.completed==game.site_preparation.plan.segments.size(),"all real terrain grading sections publish")
	check(game.terrain.density_revision==revision+game.site_preparation.completed and game.structures.blocks.stats().cells==0,"preparation changes terrain only by its accepted edit count")
	var prepared_target: Vector3i=game.site_preparation.plan.target
	game.construction_palette.survey_dialog.hide()
	game.construction_palette.preparation_status_requested.emit()
	check(game.construction_palette.place_prepared_button.visible,"completed site can be reopened for exact placement")
	game.camera.global_position+=Vector3(20,0,0)
	game.construction_palette.survey_dialog.custom_action.emit("place_prepared")
	check(not game._foundation_placement.is_empty() and game._foundation_placement.target==prepared_target,"dialog placement captures prepared target despite changed aim")
	await process_frame
	game.construction_palette.survey_dialog.canceled.emit()
	check(game._foundation_placement.is_empty() and game.structures.blocks.stats().cells==0,"closing dialog cancels pending validation without inserting blocks")
	game.construction_palette.preparation_status_requested.emit()
	game.construction_palette.survey_dialog.custom_action.emit("place_prepared")
	deadline=Time.get_ticks_msec()+12000
	while not game._foundation_placement.is_empty() and Time.get_ticks_msec()<deadline: await process_frame
	check(game.foundation_check.status=="supported" and game.structures.blocks.stats().cells==asset.get_records().size()/4,"prepared site places exactly one prefab after full validation")
	game.camera.global_position=Vector3(prepared_target)+Vector3(45,35,45)
	game.camera.look_at(Vector3(prepared_target)+Vector3(10,3,0))
	for frame in 60: await process_frame
	check(game.construction_palette.survey_dialog.has_focus() and Engine.max_fps==60,"focused survey dialog retains 60 FPS cap")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://reports/settlement_prepared_placement.png")
	var placed_cells: int=game.structures.blocks.stats().cells
	game.construction_palette.survey_dialog.custom_action.emit("place_prepared")
	check(game.structures.blocks.stats().cells==placed_cells and game._foundation_placement.is_empty(),"repeated placement cannot duplicate the prepared building")
	game.player.global_position=original_player
	game.construction_palette.survey_dialog.hide()
	game.app_focused=true
	game.camera.global_position=original_player+Vector3(0,15,0)
	game.camera.look_at(original_player+Vector3(10,-5,0))
	game.construction_palette.survey_button.pressed.emit()
	check(game.construction_palette.survey_busy,"replacement survey really starts before rotation invalidation")
	game.structure_rotation=(game.structure_rotation+1)%4
	deadline=Time.get_ticks_msec()+17000
	while game.construction_palette.survey_busy and Time.get_ticks_msec()<deadline: await process_frame
	check("Selection changed" in game.construction_palette.survey_dialog.dialog_text,"rotation change invalidates in-flight proposal")
	game.player.global_position=original_player-Vector3(100,0,0)
	var prepared: Dictionary=game.site_preparation.plan
	var target: Vector3i=prepared.target
	game.structures.blocks.set_cells(PackedInt32Array([target.x,target.y,target.z,1]))
	check("buildings" in game._site_protection_error(prepared.bounds),"existing structure inside plan rejects grading")
	game.structures.blocks.set_cells(PackedInt32Array([target.x,target.y,target.z,0]))
	game.world_vehicle._install_vehicle(game,Transform3D(Basis.IDENTITY,Vector3(target)+Vector3.UP))
	check("vehicle" in game._site_protection_error(prepared.bounds),"parked vehicle inside plan rejects grading")
	game.terrain.shutdown();game.queue_free();await process_frame;quit(1 if failures else 0)
