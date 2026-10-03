# SPDX-License-Identifier: 0BSD
extends SceneTree
const Scene=preload("res://demo/world.tscn")
var game: Node3D
var failures:=0
var capture_costs: Array[Dictionary]=[]
var pending_images: Array[Dictionary]=[]
var observer_report: Dictionary={}
var frame_samples: Array[float]=[]
func capture_visual(path: String) -> void:
	var begin:=Time.get_ticks_usec()
	var pixels:=root.get_texture().get_image()
	var readback_end:=Time.get_ticks_usec()
	var cost: Dictionary={"path":path,"readback_ms":(readback_end-begin)/1000.0,"png_write_ms":0.0,"error":0,"png_phase":"after_scene_shutdown"}
	capture_costs.append(cost)
	pending_images.append({"path":path,"image":pixels,"cost":cost})
func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures+=1
func _initialize() -> void: call_deferred("run")
func key(code: int) -> void:
	var event:=InputEventKey.new();event.physical_keycode=code;event.pressed=true
	Input.parse_input_event(event);await process_frame
	event=InputEventKey.new();event.physical_keycode=code;event.pressed=false
	Input.parse_input_event(event);await process_frame
func click(button: int) -> void:
	var event:=InputEventMouseButton.new();event.button_index=button;event.pressed=true
	Input.parse_input_event(event);await process_frame
	event=InputEventMouseButton.new();event.button_index=button;event.pressed=false
	Input.parse_input_event(event);await process_frame
func run() -> void:
	game=Scene.instantiate();game.temporary_world=true;root.add_child(game)
	var deadline:=Time.get_ticks_msec()+30000
	while game.loading_active and Time.get_ticks_msec()<deadline: await process_frame
	check(not game.loading_active,"construction scene ready")
	if game.loading_active: finish();return
	game.fly=true;game._clear_motion()
	game.player_hud.equip(2)
	var base:=Vector3i(game.player.position.floor())+Vector3i(0,8,-8)
	var target:=base+Vector3i.UP
	var blocks=game.structures.blocks
	check(blocks.set_cells(PackedInt32Array([base.x,base.y,base.z,1])),"isolated native support block placed")
	game.camera.global_position=Vector3(base)+Vector3(0.5,5,4)
	game.camera.look_at(Vector3(base)+Vector3(0.5,1,0.5))
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	var hit: Dictionary=game._structure_target(false)
	check(hit.get("target",Vector3i())==target,"camera ray selects support top for placement")
	game._prefab_preview_timer=0;game._update_prefab_preview(0)
	check(game.prefab_preview.visible and game.prefab_preview.position==Vector3(target) and game.prefab_preview.scale==Vector3.ONE,"single-block preview outlines exact placement cell")
	check(game._prefab_preview_material.albedo_color==Color("66f2b3"),"clear target preview is green")
	await process_frame;await RenderingServer.frame_post_draw
	if DisplayServer.get_name()!="headless": capture_visual("res://reports/construction_preview.png")
	var safe_position: Vector3=game.player.position
	var view: Transform3D=game.camera.global_transform
	game.player.position=Vector3(target)+Vector3(0.5,0,0.5)
	game.camera.global_transform=view
	game._prefab_preview_timer=0;game._update_prefab_preview(0)
	check(game._prefab_preview_material.albedo_color==Color("ff705f"),"player overlap makes preview red")
	await click(MOUSE_BUTTON_RIGHT)
	check(blocks.get_cell(target)==0,"red player-overlap placement is rejected")
	game.player.position=safe_position;game.camera.global_transform=view
	game.construction_palette.shape.item_selected.emit(2)
	game.construction_palette.material.item_selected.emit(1)
	game.construction_palette.rotation_choice.item_selected.emit(1)
	game._prefab_preview_timer=0;game._update_prefab_preview(0)
	check(game.shape_preview.visible and game.shape_preview.mesh==blocks.preview_mesh(3,1),"ghost preview uses selected native stair rotation")
	await process_frame;await RenderingServer.frame_post_draw
	if DisplayServer.get_name()!="headless": capture_visual("res://reports/construction_shape_preview.png")
	await click(MOUSE_BUTTON_RIGHT)
	var expected:=3+(1<<3)+(1<<5)
	check(blocks.get_cell(target)==expected,"RMB places palette-selected wood stairs at 90 degrees")
	game._construction_history(false)
	check(blocks.get_cell(target)==0 and blocks.get_cell(base)==1,"undo removes placed stairs and preserves support")
	game._construction_history(true)
	check(blocks.get_cell(target)==expected,"redo restores exact shape rotation and material")
	game.camera.look_at(Vector3(target)+Vector3(0.5,0.25,0.5))
	hit=game._structure_target(true)
	check(hit.get("target",Vector3i())==target,"removal ray selects stair geometry")
	await click(MOUSE_BUTTON_LEFT)
	check(blocks.get_cell(target)==0,"LMB removes targeted stairs")
	game._construction_history(false)
	check(blocks.get_cell(target)==expected,"undo demolition restores stairs")
	game.player_hud.set_open(true)
	game._update_prefab_preview(0)
	check(not game.prefab_preview.visible,"inventory hides building preview")
	await click(MOUSE_BUTTON_LEFT)
	check(blocks.get_cell(target)==expected,"inventory prevents world demolition from mouse click")
	game.player_hud.set_open(false)
	# Isolate authoring files from the player's shared prefab library.
	game.prefab_library.directory="user://tests/capture_ui_%d" % Time.get_ticks_usec()
	game.prefab_library.assets.clear()
	game.camera.look_at(Vector3(base)+Vector3(0.5,0.25,0.5))
	await key(KEY_BRACKETLEFT)
	game.camera.look_at(Vector3(target)+Vector3(0.5,0.25,0.5))
	await key(KEY_BRACKETRIGHT)
	check(game.prefab_library.has_a and game.prefab_library.has_b,"palette marks both aimed block corners")
	check(game.capture_selection.bounds.visible and game.capture_selection.bounds.position==Vector3(base) and game.capture_selection.bounds.scale==Vector3(1,2,1),"selection outline exactly includes both chosen cells")
	check(game.capture_selection.marker_a.visible and game.capture_selection.marker_b.visible,"both corner markers are visible")
	game.player_hud.set_open(true);game._update_prefab_preview(0)
	check(not game.capture_selection.visible,"inventory hides capture selection")
	game.player_hud.set_open(false);game._update_prefab_preview(0)
	check(game.capture_selection.visible,"closing inventory restores capture selection")
	game.construction_palette.capture_requested.emit("save","Test stairs")
	check(game.prefab_library.assets.size()==1 and game.structure_prefab_index==game.structure_prefabs.size()-1,"capture selects saved prefab in palette")
	if game.prefab_library.assets.size()==1:
		check(game.prefab_library.assets[0].get_cell_count()==2,"captured building includes support and stairs")
		var authored: PackedInt32Array=game.prefab_library.assets[0].get_records()
		check(not game.construction_palette.archive_button.disabled,"personal prefab enables archive action")
		game.construction_palette.archive_button.pressed.emit()
		check(game.structure_prefab_index==-1 and game.prefab_library.assets.is_empty() and blocks.get_cell(target)==expected,"archive returns to blocks and preserves placed stairs")
		game.construction_palette.capture_requested.emit("restore","")
		check(game.structure_prefab_index==game.structure_prefabs.size()-1 and game.prefab_library.assets.size()==1 and game.prefab_library.assets[0].get_records()==authored,"restore selects exact archived prefab in palette")
	for file: String in DirAccess.get_files_at(game.prefab_library.directory): DirAccess.remove_absolute(game.prefab_library.directory.path_join(file))
	DirAccess.remove_absolute(game.prefab_library.directory.path_join("archive"))
	DirAccess.remove_absolute(game.prefab_library.directory)
	await process_frame;await RenderingServer.frame_post_draw
	if DisplayServer.get_name()!="headless":
		capture_visual("res://reports/construction_interaction.png")
		# Separate screenshot readback/PNG encoding from a short stationary runtime
		# sample. Streaming stays enabled; this is not an endurance/FPS pass gate.
		for i in 20: await process_frame
		var previous:=Time.get_ticks_usec()
		for i in 120:
			await process_frame
			var now:=Time.get_ticks_usec();frame_samples.append((now-previous)/1000.0);previous=now
		frame_samples.sort()
		var total:=0.0
		for value: float in frame_samples: total+=value
		observer_report={"scope":"120 stationary runtime frames after 20 post-readback frames; streaming enabled; PNG writes deferred until scene shutdown", "captures":capture_costs,
			"frames":frame_samples.size(),"p50_ms":frame_samples[60],"p95_ms":frame_samples[114],"max_ms":frame_samples[-1],"mean_fps":120000.0/total,
			"resolution":str(root.size),"max_fps":Engine.max_fps,"frame_intervals_ms":frame_samples}
	game.construction_palette.capture_requested.emit("clear","")
	check(not game.capture_selection.bounds.visible and not game.capture_selection.marker_a.visible and not game.capture_selection.marker_b.visible and not game.prefab_library.has_a,"clear removes selection and all markers")
	finish()
func finish() -> void:
	game.terrain.shutdown();game.free()
	for item: Dictionary in pending_images:
		var begin:=Time.get_ticks_usec()
		item.cost.error=item.image.save_png(item.path)
		item.cost.png_write_ms=(Time.get_ticks_usec()-begin)/1000.0
		if item.cost.error!=OK: failures+=1
	pending_images.clear()
	if not observer_report.is_empty():
		var output:=FileAccess.open("res://reports/construction_observer_cost.json",FileAccess.WRITE)
		output.store_string(JSON.stringify(observer_report,"  "));output.close()
		observer_report.erase("frame_intervals_ms");print("CONSTRUCTION_OBSERVER ",JSON.stringify(observer_report))
	quit(1 if failures else 0)
