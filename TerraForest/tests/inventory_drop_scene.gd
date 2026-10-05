# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var item:=101
var selected:=4
func check(ok: bool,label: String) -> void:
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--drop-item="): item=int(argument.get_slice("=",1))
	var game=load("res://demo/world.tscn").instantiate();game.temporary_world=true
	root.add_child(game)
	var deadline:=Time.get_ticks_msec()+60000
	while game.loading_active and Time.get_ticks_msec()<deadline: await process_frame
	check(not game.loading_active,"world ready")
	if not game.loading_active:
		game.set_physics_process(false);game._clear_motion();game.fly=false
		game.player.position.y+=10
		var floor_body:=StaticBody3D.new();floor_body.collision_layer=1
		var collider:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(8,0.2,8);collider.shape=box
		floor_body.add_child(collider);game.add_child(floor_body)
		floor_body.global_position=game.player.global_position-Vector3.UP*0.2
		await physics_frame;await physics_frame
		if item>=201:
			game.player_hud.inventory.grant(item,5,game.player_hud.inventory.snapshot().revision)
			selected=8
		game.player_hud.set_open(true);game.player_hud.select_slot(selected)
		check(not game.player_hud.drop_button.disabled,"selected material enables inventory drop button")
		var before: int=game.player_hud.inventory.snapshot().slots[selected].count
		game.app_focused=false;game.player_hud.drop_button.pressed.emit()
		check(game.player_hud.inventory.snapshot().slots[selected].count==before,"unfocused drop rejected")
		game.app_focused=true;game.terrain.changed_since_save=false
		game.player_hud.drop_button.pressed.emit()
		print("DROP_NOTICE ",game.player_hud.message.text)
		check(game.player_hud.inventory.snapshot().slots[selected].count==before-1 and game.pickups.stores[item].statistics().active==1,"inventory button drops one supply on real physics support")
		check(game.terrain.changed_since_save,"drop marks combined world state for autosave")
		game.player_hud.drop_button.pressed.emit()
		check(game.player_hud.inventory.snapshot().slots[selected].count==before-1 and game.pickups.stores[item].statistics().active==1,"overlapping drop rejected without item loss")
		check(preload("res://addons/presentation/fullscreen_policy.gd").measurement(root).fair_graphical_sample,"1920x1080 fullscreen presentation")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://docs/evidence/resource_drops/inventory.png" if item>=201 else "res://docs/evidence/inventory_drop/inventory.png")
		game.player_hud.set_open(false)
		game.pickups.update_view(0,game.player.global_position,true)
		var result: Dictionary=game.pickups.collect_near(game.player.global_position+Vector3.UP*0.5,game.player_hud.inventory,game._pickup_reachable)
		check(result.ok and game.player_hud.inventory.snapshot().slots[selected].count==before,"dropped supply is reachable and recollects in scene")
	game.shutdown_requested=true
	check(await game.terrain.shutdown_after_edits(),"world drains cleanly after inventory interaction")
	game.free();await process_frame;await process_frame
	print("INVENTORY_DROP_SCENE failures=",failures)
	quit(1 if failures else 0)
