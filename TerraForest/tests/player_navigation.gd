extends SceneTree

class SessionWorld extends "res://demo/world.gd":
	var close_requests:=0
	func _notification(what:int)->void:
		if what==NOTIFICATION_WM_CLOSE_REQUEST:close_requests+=1
		else:super._notification(what)

var game:Node
var checks:=0
var failures:=0
var folder:="res://reports/player_navigation"

func _initialize()->void:run.call_deferred()
func check(condition:bool,label:String)->bool:
	checks+=1;print("PASS " if condition else "FAIL ",label)
	if not condition:failures+=1
	return condition
func frames(count:int=3)->void:
	for frame in count:await process_frame
func until(predicate:Callable,seconds:int)->bool:
	var deadline:=Time.get_ticks_msec()+seconds*1000
	while not predicate.call() and Time.get_ticks_msec()<deadline:await process_frame
	return predicate.call()
func mouse(point:Vector2,button:int)->void:
	for down:bool in [true,false]:
		var event:=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=button;event.pressed=down
		Input.parse_input_event(event);Input.flush_buffered_events();await process_frame
func escape()->void:
	for down:bool in [true,false]:
		var event:=InputEventKey.new();event.physical_keycode=KEY_ESCAPE;event.pressed=down
		Input.parse_input_event(event);Input.flush_buffered_events();await process_frame
func capture(label:String)->void:
	await frames();await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(folder.path_join(label+".png"))==OK,"capture "+label)
func run()->void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--navigation-evidence="):folder=argument.trim_prefix("--navigation-evidence=")
	folder=ProjectSettings.globalize_path(folder);DirAccess.make_dir_recursive_absolute(folder)
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	game=SessionWorld.new();game.temporary_world=true;game.background_fps=60;game.player_view.settings_path="";game.first_person_view.settings_path="";root.add_child(game)
	if not check(await until(func():return not game.loading_active and not game.needs_floor_spawn and game.session_menu.ready_to_dock,65),"temporary player world is ready"):await finish();return
	game.set_physics_process(false);game._clear_motion();game.app_focused=true;game.zombies.population_enabled=false;game.zombies.clear()
	var menu:CanvasLayer=game.session_menu;var atlas:CanvasLayer=game.world_map;var store:RefCounted=game.map_markers;var guide:CanvasLayer=game.destination_guide
	menu.set_open(true);await frames()
	check(menu.close_button.global_position.x>menu.panel.get_global_rect().get_center().x and menu.close_button.global_position.y<menu.panel.position.y+80,"X close control occupies the session header's top right")
	check(not menu.panel.find_children("*","Button",true,false).any(func(button):return button.text.begins_with("Resume")),"old Resume button is removed")
	check(menu.quit_button.is_visible_in_tree() and menu.quit_button.get_parent()!=menu.pages.Session,"additional Save and quit is always accessible in the sidebar")
	await capture("session")
	menu.quit_button.pressed.emit()
	check(game.close_requests==1 and not menu.confirmation.visible,"sidebar Save and quit uses the existing shutdown path without confirmation")
	menu.show_page("Player");await mouse(menu.close_button.get_global_rect().get_center(),MOUSE_BUTTON_LEFT)
	check(not menu.opened and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED,"header X returns directly to gameplay from another page")
	menu.show_page("Dev Spawner");await frames()
	check(menu.spawner.vehicle_button.is_visible_in_tree() and not menu.dev_bag.has_method("spawn_vehicle"),"live vehicle action belongs only to Dev Spawner")
	await capture("dev_spawner")
	menu.show_page("Dev Bag");check(menu.dev_bag.entries.has(501),"Dev Bag still offers carried vehicle inventory items")
	menu.set_open(false);await frames()
	check(guide.compass.visible and not guide.compass.has_marker,"top-centre compass is present without an active destination")
	var revision:int=game.terrain.published_revision;var inventory:PackedByteArray=game.player_hud.inventory.capture_storage_snapshot();var builds:int
	atlas.set_open(true)
	if not check(await until(func():return atlas.texture!=null,15),"cached world map is ready for ordinary-player markers"):await finish();return
	builds=atlas.builds;var spawn_token:int=game.spawn_token
	atlas.view.zoom=4;atlas.view.center=Vector2(game.player.position.x,game.player.position.z);atlas.view.queue_redraw();await frames()
	var target:Vector2=atlas.view.center+Vector2(110,-90);var screen:Vector2=atlas.view.global_position+atlas.view.world_to_map(Vector3(target.x,0,target.y))
	await mouse(screen,MOUSE_BUTTON_RIGHT)
	if not check(atlas.context_menu.visible and atlas.context_actions.has("mark") and not menu.developer,"right-click opens an embedded marker context menu in gameplay"):await finish();return
	check(atlas.context_menu.get_global_rect().has_point(screen) and root.get_visible_rect().encloses(atlas.context_menu.get_global_rect()),"context menu appears at the click and stays inside the viewport")
	await capture("map_context")
	atlas.context_actions.mark.pressed.emit();await frames()
	check(store.markers.size()==1 and Vector2(store.markers[0].point).distance_to(target)<.01 and store.active_id==1,"context mark resolves the exact pan/zoom world position and starts navigation")
	check(guide.destination.get("marker_id",0)==1 and atlas.marker_list.item_count==2 and not atlas.context_menu.visible,"new marker appears in the saved list and tracking state")
	check(game.spawn_token==spawn_token and game.terrain.published_revision==revision and game.player_hud.inventory.capture_storage_snapshot()==inventory and game.terrain.changed_since_save,"markers dirty the save without teleporting, editing terrain or granting items")
	var other:Vector2=atlas.view.center+Vector2(-120,-130)
	await mouse(atlas.view.global_position+atlas.view.world_to_map(Vector3(other.x,0,other.y)),MOUSE_BUTTON_RIGHT);atlas.context_actions.mark.pressed.emit()
	check(store.markers.size()==2 and store.active_id==2,"placing a new destination keeps the older marker")
	await mouse(screen,MOUSE_BUTTON_RIGHT);check(atlas.context_marker==1 and atlas.context_actions.has("track"),"right-clicking an old marker exposes navigation and removal actions")
	atlas.context_actions.track.pressed.emit();check(store.active_id==1,"old saved markers can become active again")
	await mouse(atlas.view.global_position+atlas.view.world_to_map(Vector3(other.x,0,other.y)),MOUSE_BUTTON_RIGHT);atlas.context_actions.remove.pressed.emit()
	check(store.markers.size()==1 and store.active_id==1,"removing an old inactive marker leaves the destination intact")
	await mouse(screen,MOUSE_BUTTON_RIGHT);atlas.context_actions.untrack.pressed.emit()
	check(store.active_id==0 and store.markers.size()==1 and guide.destination.is_empty(),"stop navigating untracks without deleting the marker")
	atlas.marker_list.item_selected.emit(1);check(store.active_id==1,"saved-marker dropdown selects the retained destination")
	await mouse(screen,MOUSE_BUTTON_RIGHT);await escape()
	check(atlas.opened and not atlas.context_menu.visible and not menu.opened,"first Escape dismisses only the map context menu")
	await capture("map_markers")
	var snapshot:PackedByteArray=game.persistence._capture().sections.map_markers_v1
	store.restore_snapshot(PackedByteArray())
	check(store.markers.is_empty() and guide.destination.is_empty() and atlas.marker_list.item_count==1,"empty world restoration clears old marker UI and navigation")
	check(game.persistence._providers.map_markers_v1.restore.call(snapshot) and store.active_id==1 and guide.destination.get("marker_id",0)==1,"registered binary save provider restores markers and the active compass destination")
	await escape();await frames()
	check(not atlas.opened and not menu.visible_ui() and guide.compass.visible and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED,"next Escape returns directly to gameplay with compass navigation")
	var point:Vector3=store.describe(1).position;point.y=game.camera.global_position.y;game.camera.look_at(point);await frames()
	check(guide.compass.has_marker and absf(guide.compass.bearing)<.01 and absf(guide.compass.marker_offset())<2,"facing the marked destination centres its compass symbol")
	guide.refresh();check(guide.caption.text.contains("Marker 1") and not guide.caption.text.contains("above") and not guide.caption.text.contains("below"),"map markers show horizontal distance without a false underground elevation")
	await capture("compass_ahead")
	game.camera.rotate_y(PI);await frames()
	check(absf(guide.compass.bearing)>PI*.5 and absf(guide.compass.marker_offset())>guide.compass.size.x*.45,"behind-the-player destinations remain visible as an edge direction indicator")
	await capture("compass_behind")
	root.content_scale_size=Vector2i(1280,720);await frames()
	check(absf(guide.compass.position.x+guide.compass.size.x*.5-root.get_visible_rect().size.x*.5)<1 and guide.compass.position.y>=20,"compass remains centred and slightly below the top after resizing")
	root.content_scale_size=Vector2i(1920,1080);await frames()
	atlas.set_open(true);check(atlas.builds==builds,"marker operations and reopening reuse the original cached survey")
	atlas.open_context(atlas.view.world_to_map(Vector3(store.find(1).point.x,0,store.find(1).point.y)));atlas.context_actions.remove.pressed.emit()
	check(store.markers.is_empty() and guide.destination.is_empty(),"unmarking the active destination clears saved navigation")
	atlas.set_open(false);await frames();check(guide.compass.visible and not guide.compass.has_marker,"clearing navigation keeps the cardinal compass")
	await finish()
func finish()->void:
	if game!=null:game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await frames(2)
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"  "))
	print("PLAYER_NAVIGATION checks=",checks," failures=",failures);quit(1 if failures else 0)
