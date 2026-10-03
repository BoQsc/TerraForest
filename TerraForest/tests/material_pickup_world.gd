# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var game: Node3D
func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures+=1
func press_collect() -> void:
	var event:=InputEventKey.new();event.physical_keycode=KEY_E;event.pressed=true
	game._unhandled_input(event)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true
	game.terrain.backend.world_generator=2;game.terrain.backend.world_seed=1703
	root.add_child(game)
	var deadline:=Time.get_ticks_msec()+30000
	while game.loading_active and Time.get_ticks_msec()<deadline: await process_frame
	check(not game.loading_active,"world ready with pickup providers")
	if game.loading_active:
		print("STARTUP_CONTEXT ",{"ready":game.terrain.world_ready,"worker":game.terrain.backend.status(),"queued":game.terrain.backend.queued(),"error":game.terrain.latest_error,"reason":game.loading_reason,"generator":game.terrain.backend.world_generator})
		finish();return
	game.set_physics_process(false);game.fly=false;game._clear_motion()
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	var point: Vector3=game.player.global_position+Vector3(0.8,1,0)
	var id: int=game.pickups.spawn(101,point)
	game.pickups.update_view(0,game.player.global_position,true)
	check(game.pickups.render_status[101].rendered==1,"authored pickup rendered in actual world")
	var blocker:=StaticBody3D.new();blocker.collision_layer=2
	var collision:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=Vector3.ONE*0.2;collision.shape=shape
	blocker.add_child(collision);game.add_child(blocker)
	blocker.global_position=(game.camera.global_position+point)*0.5
	await physics_frame;await physics_frame
	check(not game._pickup_reachable(point),"building collision layer obstructs pickup ray")
	game.app_focused=true
	press_collect()
	check(game.pickups.stores[101].resolve_identity(id)>0,"E cannot collect through obstruction")
	blocker.free();await physics_frame;await physics_frame
	game.player_hud.set_open(true);press_collect()
	check(game.pickups.stores[101].resolve_identity(id)>0,"inventory modal blocks world collection")
	game.player_hud.set_open(false)
	game.app_focused=false;press_collect()
	check(game.pickups.stores[101].resolve_identity(id)>0,"unfocused window ignores collection")
	# Input is injected directly; OS focus can belong to the automated test runner.
	game.app_focused=true
	press_collect()
	check(game.pickups.stores[101].resolve_identity(id)==0 and game.player_hud.state.slots[4].item==101,"E transfers reachable material into visible inventory")
	var saved: Dictionary=game.persistence._capture()
	check(saved.sections.has("pickups_101") and saved.sections.has("player_loadout"),"world capture includes pickups and inventory together")
	game.structure_mode=true;game.model_tool.set_active(false);game._sync_player_tool()
	var base:=Vector3i(game.player.position.floor())+Vector3i(3,3,0)
	game.structures.blocks.set_cells(PackedInt32Array([base.x,base.y,base.z,1]))
	var supply_point:=Vector3(base)+Vector3(0.5,1.2,0.5)
	deadline=Time.get_ticks_msec()+8000
	while not game.structures.is_collision_region_ready(AABB(supply_point-Vector3.ONE*0.2,Vector3.ONE*0.4)) and Time.get_ticks_msec()<deadline: await process_frame
	game.camera.global_position=Vector3(base)+Vector3(0.5,4,0.5)
	game.camera.look_at(Vector3(base)+Vector3(0.5,1,0.5),Vector3.FORWARD)
	game.app_focused=true
	game.construction_palette.supply.select(1)
	game.construction_palette.supply_button.pressed.emit()
	check(game.pickups.stores[102].statistics().active==1,"editor button authors selected wood supply on aimed support")
	game.construction_palette.supply_button.pressed.emit()
	check(game.pickups.stores[102].statistics().active==1,"repeated placement rejects overlapping supply")
	game.prefab_library.directory="user://tests/stack_editor_%d_%d" % [OS.get_process_id(),Time.get_ticks_usec()]
	game.prefab_library.assets.clear();game.prefab_library._paths.clear()
	var module_index: int=-1
	for i in game.structure_prefabs.size():
		if game.structure_prefabs[i].resource_name=="Tower floor": module_index=i
	game.construction_palette.prefab.item_selected.emit(module_index+1)
	game.construction_palette.capture_name.text="Test stacked tower"
	game.construction_palette.stack_count.value=4
	game.construction_palette.stack_button.pressed.emit()
	var assembled: Resource=game.structure_prefabs[game.structure_prefab_index]
	check(assembled.resource_name=="Test stacked tower" and assembled.get_cell_count()==game.structure_prefabs[module_index].get_cell_count()*4,"editor stacks selected floor module into reusable building")
	var reopened:=preload("res://addons/structures/prefab_library.gd").new()
	reopened.directory=game.prefab_library.directory;reopened.load_library()
	check(reopened.assets.size()==1 and reopened.assets[0].get_records()==assembled.get_records(),"editor assembly persists in personal prefab library")
	game.construction_palette.stack_count.value=32
	game.construction_palette.capture_name.text=""
	game.construction_palette.stack_button.pressed.emit()
	check(game.prefab_library.assets.size()==1,"invalid assembly name cannot publish another asset")
	await process_frame;await RenderingServer.frame_post_draw
	check(game.construction_palette.panel.position.y+game.construction_palette.panel.size.y<900,"expanded editor fits above toolbelt at 1080p")
	var editor_pixels: Image
	if DisplayServer.get_name()!="headless": editor_pixels=root.get_texture().get_image()
	game.player_hud.set_open(true)
	await process_frame;await RenderingServer.frame_post_draw
	var pixels: Image
	if DisplayServer.get_name()!="headless": pixels=root.get_texture().get_image()
	for filename: String in DirAccess.get_files_at(reopened.directory): DirAccess.remove_absolute(reopened.directory.path_join(filename))
	DirAccess.remove_absolute(reopened.directory)
	game.terrain.shutdown();game.free()
	if pixels!=null: pixels.save_png("res://reports/material_pickup_world.png")
	if editor_pixels!=null: editor_pixels.save_png("res://reports/material_pickup_editor.png")
	var file:=FileAccess.open("res://reports/material_pickup_world.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"failures":failures,"scope":"actual world input visibility occlusion and inventory capture; no endurance claim"}));file.close()
	quit(1 if failures else 0)
func finish() -> void:
	game.terrain.shutdown();game.free();quit(1)
