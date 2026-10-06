# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var checks:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var game=load("res://demo/world.tscn").instantiate();game.temporary_world=true
	root.add_child(game)
	var deadline:=Time.get_ticks_msec()+60000
	while game.loading_active and Time.get_ticks_msec()<deadline: await process_frame
	check(not game.loading_active,"world ready")
	if not game.loading_active:
		game.set_physics_process(false);game._clear_motion();game.player.position.y+=10
		var floor_body:=StaticBody3D.new();floor_body.collision_layer=1
		var collider:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(12,0.2,12);collider.shape=box
		floor_body.add_child(collider);game.add_child(floor_body)
		floor_body.global_position=game.player.global_position-Vector3.UP*0.2
		await physics_frame;await physics_frame
		game.camera.look_at(game.player.global_position+Vector3(0,-0.1,-4))
		game.model_tool.set_active(true);game.model_tool.edit_available=true
		check(game.model_tool.gameplay and game.model_tool.paid_placement.is_valid(),"gameplay world wires paid model placement")
		var before: int=game.player_hud.inventory.snapshot().slots[7].count
		game.terrain.changed_since_save=false
		var id: int=game.model_tool.edit(false)
		check(id>0 and game.player_hud.inventory.snapshot().slots[7].count==before-4,"actual model tool charges four metal for beam")
		check(game.terrain.changed_since_save,"model placement marks world save dirty")
		game.model_tool.refresh()
		check(game.model_tool.caption.text.contains("4 metal"),"model palette displays recipe cost")
		var steps: int=game.model_tool.history.stats().undo_steps
		var undo:=InputEventKey.new();undo.pressed=true;undo.physical_keycode=KEY_Z;undo.ctrl_pressed=true
		game.model_tool.handle_input(undo)
		check(game.model_tool.history.stats().undo_steps==steps and game.player_hud.inventory.snapshot().slots[7].count==before-4,"gameplay undo cannot reverse paid placement independently of inventory")
		game.fly=false
		Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
		var pickup_point: Vector3=game.player.global_position+Vector3(0.8,0.5,0)
		var supply: int=game.pickups.spawn(101,pickup_point)
		var select_event:=InputEventKey.new();select_event.pressed=true;select_event.physical_keycode=KEY_E
		deadline=Time.get_ticks_msec()+5000
		while Time.get_ticks_msec()<deadline:
			await physics_frame
			var hit: Dictionary=game.model_tool.ray()
			if not hit.is_empty() and hit.collider==game.model_tool.catalog[0].collection: break
		game.app_focused=false
		game._unhandled_input(select_event)
		check(game.model_tool.picked_id==0,"unfocused object selection is rejected")
		game.app_focused=true;game.model_tool.edit_available=true
		game._unhandled_input(select_event)
		check(game.model_tool.picked_id==id,"on-foot E routes to active object selection")
		check(game.pickups.stores[101].resolve_identity(supply)>0,"object selection leaves nearby pickup untouched")
		check(preload("res://addons/presentation/fullscreen_policy.gd").measurement(root).fair_graphical_sample,"1920x1080 fullscreen presentation")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://docs/evidence/interaction_routing/scene.png")
	game.shutdown_requested=true
	check(await game.terrain.shutdown_after_edits(),"world drains cleanly")
	game.free();await process_frame;await process_frame
	print("MODEL_INVENTORY_SCENE checks=",checks," failures=",failures)
	quit(1 if failures else 0)
