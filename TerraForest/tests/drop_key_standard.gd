# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func key(pressed:bool=true,echo:bool=false,ctrl:bool=false)->void:
	var event:=InputEventKey.new();event.physical_keycode=KEY_G;event.keycode=KEY_G
	event.unicode=103
	event.pressed=pressed;event.echo=echo;event.ctrl_pressed=ctrl
	Input.parse_input_event(event);Input.flush_buffered_events()
func tap()->void:key();key(false)
func run()->void:
	var game=load("res://demo/world.tscn").instantiate()
	game.temporary_world=true;game.background_fps=60
	game.terrain.backend.disk_cache.enabled=false
	root.add_child(game)
	var deadline:=Time.get_ticks_msec()+60000
	while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
	check(not game.loading_active,"actual world starts with universal pickup providers")
	if game.loading_active:
		game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();quit(1);return
	game.set_physics_process(false);game._clear_motion();game.fly=false;game.app_focused=true
	if game.session_menu.developer:game.session_menu.toggle_developer()
	game.needs_floor_spawn=false;game.player.position.y+=10
	var floor_body:=StaticBody3D.new();floor_body.collision_layer=1
	var collider:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(12,.2,12);collider.shape=box
	floor_body.add_child(collider);game.add_child(floor_body);floor_body.global_position=game.player.global_position-Vector3.UP*.2
	await physics_frame;await physics_frame
	var hud=game.player_hud
	# Keep the existing belt, place a newly supported firearm in an empty slot.
	check(hud.inventory.grant(8,1,hud.inventory.snapshot().revision).ok,"rifle enters native inventory")
	var slot:=-1
	for i in 32:
		if hud.inventory.snapshot().slots[i].item==8:slot=i
	hud.equip_inventory(slot);Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	check(hud.action_hint.text.contains("G drop"),"firearm hint exposes the standard drop key")
	var before:PackedByteArray=hud.capture_snapshot()
	key(true,true);key(false);check(hud.capture_snapshot()==before,"keyboard repeat never drops")
	key(true,false,true);key(false);check(hud.capture_snapshot()==before,"Ctrl+G never drops")
	game.fly=true;tap();check(game.fly and hud.capture_snapshot()==before,"G in flight keeps the item and never changes flight mode");game.fly=false
	game.player_life.dead=true;tap();check(hud.capture_snapshot()==before,"G cannot discard items while dead");game.player_life.dead=false
	game.app_focused=false;tap();check(hud.capture_snapshot()==before,"unfocused G preserves inventory")
	game.app_focused=true;game.session_menu.set_open(true);tap()
	check(hud.capture_snapshot()==before,"session menu consumes G without dropping")
	game.session_menu.set_open(false);tap()
	check(hud.inventory.snapshot().slots[slot].count==0 and game.pickups.stores[0].statistics().active==1 and not game.fly,"real G drops the rifle exactly once and never toggles flight")
	game.pickups.update_view(0,game.player.global_position,true)
	check(game.pickups.render_status[0].rendered==1 and game.pickups.renderers[0].multimesh.mesh.get_surface_count()==1,"universal drop renders in one native batched mesh")
	var collected:Dictionary=game.pickups.collect_near(game.player.global_position,hud.inventory,game._pickup_reachable)
	check(collected.ok and collected.item==8,"rifle recollects through actual-world reach checks")
	# Inventory selections must never become G-drop targets.
	check(hud.inventory.grant(601,3,hud.inventory.snapshot().revision).ok,"coins enter inventory")
	var coins:=-1
	for i in 32:
		if hud.inventory.snapshot().slots[i].item==601:coins=i
	check(hud.inventory.transfer(coins,20,3,hud.inventory.snapshot().revision).ok,"coin stack moves to backpack")
	hud.refresh();hud.set_open(true);hud.select_slot(20)
	before=hud.capture_snapshot()
	var text:=LineEdit.new();hud.add_child(text);text.grab_focus();tap()
	check(hud.capture_snapshot()==before and text.text.to_lower()=="g","typing G enters text without dropping selected item")
	text.release_focus();text.queue_free();tap()
	check(hud.capture_snapshot()==before,"G with a selected backpack slot does not drop anything")
	hud.set_open(false)
	game.session_menu.toggle_developer();hud.set_open(true);hud.select_slot(20);tap()
	check(hud.capture_snapshot()==before and not game.fly,"G in the developer backpack does not drop or toggle flight")
	hud.set_open(false);tap()
	check(hud.capture_snapshot()==before and not game.fly,"G on the developer toolbelt does not drop or toggle flight")
	game.session_menu.toggle_developer();hud.equip_inventory(20)
	var held:int=hud.active_slot;tap()
	check(hud.inventory.snapshot().slots[held].item==601 and hud.inventory.snapshot().slots[held].count==2,"gameplay G drops exactly one held coin after equipping it")
	hud.set_open(true);hud.select_slot(held)
	if DisplayServer.get_name()!="headless":
		var capture_directory:="res://reports/universal_item_drop"
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--drop-evidence="):capture_directory=argument.get_slice("=",1)
		DirAccess.make_dir_recursive_absolute(capture_directory)
		for i in 3:await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(capture_directory.path_join("backpack.png"))==OK,"drop evidence image saves outside packaged resources")
	hud.set_open(false)
	game.shutdown_requested=true;check(await game.terrain.shutdown_after_edits(),"world shuts down cleanly")
	game.free();await process_frame;await process_frame
	print("DROP_KEY_STANDARD checks=",checks," failures=",failures)
	quit(1 if failures else 0)
func _initialize()->void:run.call_deferred()
