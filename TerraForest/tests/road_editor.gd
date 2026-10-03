# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures+=1
func _initialize() -> void: call_deferred("run")
func run() -> void:
	Engine.max_fps=60
	var game=load("res://demo/world.tscn").instantiate();game.temporary_world=true
	game.terrain.backend.world_generator=2;game.terrain.backend.world_seed=1703
	root.add_child(game)
	var deadline:=Time.get_ticks_msec()+30000
	while game.loading_active and Time.get_ticks_msec()<deadline: await process_frame
	check(not game.loading_active,"world starts with road editor")
	if not game.loading_active:
		game.set_physics_process(false);game._clear_motion();game.app_focused=true
		var panel=game.road_palette
		var camera_transform: Transform3D=game.camera.global_transform
		game.camera.global_position=game.player.global_position+Vector3(0,10,0)
		game.camera.look_at(game.player.global_position,Vector3.FORWARD)
		panel.action_requested.emit("start")
		check(panel.has_start,"mark button acquires terrain through actual physics ray")
		var original_start: Vector3=panel.start
		var blocker_cell:=Vector3i(game.player.global_position.floor())+Vector3i(0,5,0)
		game.structures.blocks.set_cells(PackedInt32Array([blocker_cell.x,blocker_cell.y,blocker_cell.z,1]))
		panel.action_requested.emit("start")
		check(panel.start==original_start and panel.status.text.contains("structure blocks"),"road aim cannot mark terrain through a building")
		game.structures.blocks.set_cells(PackedInt32Array([blocker_cell.x,blocker_cell.y,blocker_cell.z,0]))
		panel.mark(false,panel.start+Vector3(10,0,0))
		panel.action_requested.emit("build")
		check(panel.status.text.begins_with("Move clear"),"road overlapping player is rejected")
		game.camera.global_transform=camera_transform
		panel.mark(true,Vector3(400,180,400));panel.mark(false,Vector3(432,184,400))
		check(panel.validation_error().is_empty(),"graded selection accepted")
		check(game.road_preview.outline.get_surface_count()==1 and game.road_preview.appearance.albedo_color==Color("50e6b5"),"valid route produces green outline")
		var previous_rebuilds: int=game.road_preview.rebuilds
		panel.width.value=4
		check(game.road_preview.rebuilds==previous_rebuilds+1,"width control refreshes outline once")
		panel.width.value=3
		panel.finish.y=200
		panel.selection_changed.emit()
		check(game.road_preview.appearance.albedo_color==Color("ff705e"),"invalid grade produces red outline")
		check(not panel.validation_error().is_empty(),"excessive grade explained before submission")
		panel.finish.y=184
		panel.selection_changed.emit()
		game.player_hud.set_open(true);panel.action_requested.emit("clear")
		check(panel.has_start,"inventory blocks road editor actions")
		game.player_hud.set_open(false);game.app_focused=true
		panel.clearance.value=6
		game.structures.blocks.set_cells(PackedInt32Array([416,187,400,1]))
		panel.action_requested.emit("build")
		check(panel.status.text.begins_with("Road bounds overlap"),"road clearance protects building occupancy above pavement")
		game.structures.blocks.set_cells(PackedInt32Array([416,187,400,0]))
		panel.action_requested.emit("build")
		check(panel.status.text.begins_with("Road submitted"),"road panel routes construction to terrain worker")
		deadline=Time.get_ticks_msec()+10000
		while game.terrain.pending_edit and Time.get_ticks_msec()<deadline: await process_frame
		check(not game.terrain.pending_edit and game.terrain.latest_error.is_empty(),"editor road completes without worker error")
		panel.surface.select(1);panel.surface.item_selected.emit(1)
		check(panel.material_id()==1 and panel.build_button.text=="Grade stone foundation","foundation surface selects stone and updates action label")
		game.app_focused=true;panel.action_requested.emit("build")
		check(panel.status.text.begins_with("Foundation submitted"),"foundation panel routes grading through guarded world action")
		deadline=Time.get_ticks_msec()+10000
		while game.terrain.pending_edit and Time.get_ticks_msec()<deadline: await process_frame
		check(not game.terrain.pending_edit and game.terrain.latest_error.is_empty(),"editor foundation completes without worker error")
		Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
		previous_rebuilds=game.road_preview.rebuilds
		for frame in 3: await process_frame
		check(game.road_preview.rebuilds==previous_rebuilds,"unchanged selection does not rebuild preview each frame")
		check(panel.panel.visible and panel.panel.get_global_rect().end.y<900,"road panel visible and fits above toolbelt at 1080p")
		if DisplayServer.get_name()!="headless":
			game.camera.global_position=Vector3(440,205,428)
			game.camera.look_at(Vector3(416,181,400))
			for frame in 3: await process_frame
			await RenderingServer.frame_post_draw
			var screenshot:=root.get_texture().get_image()
			game.terrain.shutdown()
			screenshot.save_png("res://reports/road_editor.png")
	game.terrain.shutdown();game.queue_free();await process_frame
	quit(1 if failures else 0)
