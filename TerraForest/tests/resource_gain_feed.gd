# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
func row(item:int)->Dictionary:
	for entry:Dictionary in game.player_hud.resource_feed.active:
		if entry.item==item:return entry
	return {}
func run()->void:
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--gain-evidence-dir="):evidence=argument.trim_prefix("--gain-evidence-dir=")
	if evidence.is_empty():evidence="res://reports/resource_gain_feed"
	DirAccess.make_dir_recursive_absolute(evidence)
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;root.add_child(game)
	if not check(await wait_for(func():return not game.loading_active,45),"actual gameplay world loads"):await finish();return
	game.set_physics_process(false);game._clear_motion();game.app_focused=true;game.needs_floor_spawn=false
	var hud=game.player_hud;var feed=hud.resource_feed;var inventory:RefCounted=hud.inventory
	check(feed.active.is_empty() and not feed.is_processing(),"starter/loadout items produce no gain notifications")
	# Exercise the ordinary aimed E pickup path, including its HUD refresh.
	var point:Vector3=game.camera.global_position-game.camera.global_basis.z*1.3
	var identity:int=game.pickups.spawn(211,game.pickups.to_local(point))
	game._interact_on_foot()
	check(game.pickups.stores[211].resolve_identity(identity)==0 and row(211).get("count",0)==1 and row(211).icon.texture!=null,"E pickup shows the actual item icon and +1")
	identity=game.pickups.spawn(211,game.pickups.to_local(point));game._interact_on_foot()
	check(row(211).get("count",0)==2 and feed.active.size()==1,"rapid matching pickups combine into +2")
	var saved:PackedByteArray=hud.capture_snapshot()
	var source:int=slot_of(211);var count:int=inventory.snapshot().slots[source].count
	inventory.transfer(source,31,count,inventory.snapshot().revision);hud.refresh()
	check(row(211).count==2 and feed.active.size()==1,"moving a carried stack does not report another gain")
	feed.clear()
	# Native excavation receipt -> normal inventory delivery -> notification.
	var center:Vector3=game.player.global_position-Vector3.UP*.7
	check(game.terrain.sculpt_sphere(center,1.2,false),"real mining edit is admitted")
	check(await wait_for(func():return not game.terrain.pending_edit,15),"mining and resource accounting publish")
	var raw:=false
	for entry:Dictionary in feed.active:
		if entry.item in [201,202,203,211] and entry.count>0 and entry.icon.texture!=null:raw=true
	check(raw,"mined resources produce icon/quantity feedback after publication")
	inventory.grant(201,2,inventory.snapshot().revision);hud.refresh();feed.clear()
	hud.set_open(true);hud.craft_recipe(0)
	check(row(101).get("count",0)==1 and row(101).icon.texture!=null,"crafting a building block shows its icon and gained quantity")
	hud.set_open(false)
	hud.restore_snapshot(saved)
	check(feed.active.is_empty(),"restoring a saved inventory clears feedback without replaying its contents")
	inventory.grant(301,1,inventory.snapshot().revision);hud.refresh();feed.clear()
	var clothing:int=slot_of(301)
	hud.equipment.deposit(1,inventory,clothing,1,inventory.snapshot().revision,hud.equipment.snapshot(1).store_revision);hud.refresh()
	hud.equipment.withdraw(1,inventory,0,1,inventory.snapshot().revision,hud.equipment.snapshot(1).store_revision);hud.refresh()
	check(feed.active.is_empty(),"equipping and removing clothing does not invent gains")
	for item:int in [211,201,202,101,102,104]:
		inventory.grant(item,1,inventory.snapshot().revision);hud.refresh()
	await process_frame;await RenderingServer.frame_post_draw
	var bounds:Rect2=feed.get_global_rect()
	check(feed.active.size()==5 and bounds.position.x>root.size.x*.75 and bounds.end.x<=root.size.x and bounds.end.y<=root.size.y and bounds.position.y>root.size.y*.65,"feed stays small and bounded at the lower right")
	root.get_texture().get_image().save_png(evidence.path_join("gains.png"))
	await create_timer(3.2).timeout
	check(feed.active.is_empty() and not feed.visible and not feed.is_processing(),"notifications fade out and stop processing when idle")
	await finish()
func finish()->void:
	game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame
	print("RESOURCE_GAIN_FEED failures=",failures);quit(1 if failures else 0)
