# SPDX-License-Identifier: 0BSD
extends "res://tests/menu_transition.gd"
func exercise(game:Node)->void:
	game.app_focused=true;game.player_view.entry.enabled=false;game.player_view.entry.pending=false
	game.player_view.entry.finish()
	for frame in 10:await physics_frame
	var anchor:Vector3=game.player.position
	check(game.player_life.restore(PackedByteArray()),"reset health in read-only fixture only")
	check(game.player_life.set_spawn(anchor,game.yaw) and game.player_life.clear(anchor),"saved respawn anchor supported and clear")
	var inventory:PackedByteArray=game.player_hud.capture_snapshot()
	var item:int=game.player_hud.active_item
	game.zombie_target.receive_zombie_attack(18)
	check(game.player_life.state.snapshot().health==82,"actual target damage reaches player health")
	game.zombie_target.receive_zombie_attack(1000)
	check(game.player_life.dead and not game._model_edit_available() and not game._movement_input_available(),"fatal hit blocks edits and movement")
	var dead_save:PackedByteArray=game.player_life.state.capture_storage_snapshot()
	check(game.player_life.restore(dead_save) and game.player_life.dead,"dead state restore restarts safe respawn")
	var deadline:=Time.get_ticks_msec()+60000
	while (game.player_life.dead or game.player_view.entry.pending or game.player_view.entry.active) and Time.get_ticks_msec()<deadline:
		game.app_focused=true;await process_frame
	check(not game.player_life.dead and not game.player_view.entry.active and game.player_view.entry.wake_starts==1,"real death returns through approved wake animation")
	check(game.player.position.distance_to(anchor)<.25 and game.player_life.clear(game.player.position),"respawn returns to supported saved anchor")
	check(game.player_hud.capture_snapshot()==inventory and game.player_hud.active_item==item,"respawn preserves loadout and selected item")
	check(game.player_life.state.snapshot().health==100,"respawn restores health")
	var obstacle:=StaticBody3D.new();obstacle.position=anchor+Vector3.UP*.9;obstacle.collision_layer=4
	var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(1.2,1.8,1.2);shape.shape=box;obstacle.add_child(shape);game.add_child(obstacle)
	await physics_frame
	check(not game.player_life.clear(anchor),"edited shelter obstruction rejects exact anchor")
	game.zombie_target.receive_zombie_attack(1000)
	deadline=Time.get_ticks_msec()+60000
	while (game.player_life.dead or game.player_view.entry.pending or game.player_view.entry.active) and Time.get_ticks_msec()<deadline:
		game.app_focused=true;await process_frame
	check(not game.player_life.dead and game.player_life.clear(game.player.position) and game.player.position.distance_to(anchor)>1.,"blocked shelter uses supported nearby space without noclip")
	check(game.player_view.entry.wake_starts==2 and game.player_hud.capture_snapshot()==inventory,"second respawn preserves items and plays wake once")
	obstacle.free()
	game.app_focused=false
