# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,label: String) -> void:
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;root.add_child(game)
	var deadline:=Time.get_ticks_msec()+60000
	while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
	check(not game.loading_active,"main world ready")
	game.set_physics_process(false);game._clear_motion();game.app_focused=true
	var base: Vector3i=Vector3i(game.player.position.snapped(Vector3.ONE))+Vector3i(0,12,0)
	game.player.position=Vector3(base)+Vector3(12,1,12);game.needs_floor_spawn=false
	var inv: RefCounted=game.player_hud.inventory
	check(inv.grant_items(PackedInt64Array([101,5000,102,5000,103,5000,104,5000]),inv.snapshot().revision).ok,"supply paid interior fixture")
	var asset: Resource=game.structure_prefabs[4]
	check(asset.get_model_attachments().size()==4,"normal palette furnished cottage includes chest")
	check(game._place_combined_prefab(asset,base,0),"normal paid prefab route places furnished storage interior")
	var target:=Vector3(base)+Vector3(2.5,1,0)
	game.player.position=target+Vector3(0,0.05,1.6);game.fly=false
	game.structures.set_model_focus(target);game.structures.blocks.set_focus(target)
	for i in 60:await physics_frame
	game.camera.global_position=target+Vector3(0,1.67,1.6);game.camera.look_at(target+Vector3(0,0.4,0))
	game._set_player_tool_mode(false,false,1);Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	for i in 5:await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://reports/storage_interior")
	root.get_texture().get_image().save_png("res://reports/storage_interior/exterior.png")
	var event:=InputEventKey.new();event.pressed=true;event.physical_keycode=KEY_E;game._unhandled_input(event)
	check(game.storage.opened,"E reaches chest inside furnished cottage")
	if game.storage.opened:
		var slot:=-1
		for i in 32:
			if inv.snapshot().slots[i].item==102:slot=i
		game.storage.player_list.select(slot);game.storage.quantity.get_line_edit().text="2"
		check(game.storage.move_selected(true),"interior chest accepts wood through normal UI")
		for i in 5:await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://reports/storage_interior/open.png")
		game.storage.close()
	check(preload("res://addons/presentation/fullscreen_policy.gd").measurement(root).fair_graphical_sample and Engine.max_fps==60,"fullscreen1080p cap60")
	game.shutdown_requested=true;check(await game.terrain.shutdown_after_edits(),"normal shutdown")
	game.free();await process_frame;await process_frame
	print("STORAGE_INTERIOR failures=",failures);quit(1 if failures else 0)
