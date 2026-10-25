extends SceneTree
var game:Node
var checks:=0
var failures:=0
var folder:="res://reports/world_map_teleport"
func _initialize()->void:run.call_deferred()
func check(condition:bool,message:String)->bool:
 checks+=1
 if not condition:failures+=1
 print("PASS " if condition else "FAIL ",message);return condition
func until(predicate:Callable,seconds:int)->bool:
 var deadline:=Time.get_ticks_msec()+seconds*1000
 while not predicate.call() and Time.get_ticks_msec()<deadline:await process_frame
 return predicate.call()
func mouse(at:Vector2,pressed:bool,control:bool=false)->void:
 var event:=InputEventMouseButton.new();event.position=at;event.global_position=at;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.ctrl_pressed=control
 Input.parse_input_event(event);Input.flush_buffered_events();await process_frame
func click(at:Vector2,control:bool=false)->void:
 await mouse(at,true,control);await mouse(at,false,control)
func capture(name:String)->void:
 if DisplayServer.get_name()=="headless":return
 await process_frame;await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(folder.path_join(name+".png"))
func run()->void:
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
 game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.max_fps=60;game.background_fps=60;root.add_child(game)
 if not check(await until(func():return not game.loading_active and not game.needs_floor_spawn,60),"temporary world is playable"):await finish();return
 game.app_focused=true;game._clear_motion()
 var atlas=game.world_map;var menu=game.session_menu
 if menu.developer:menu.toggle_developer()
 var inventory:PackedByteArray=game.player_hud.inventory.capture_storage_snapshot()
 var revision:int=game.terrain.published_revision
 var token:int=game.spawn_token
 var origin:Vector3=game.player.position
 var target:=Vector3(origin.x+180,0,origin.z-120)
 atlas.set_open(true)
 if not check(await until(func():return atlas.texture!=null,15),"map survey is ready"):await finish();return
 atlas.view.overview();await process_frame
 var screen:Vector2=atlas.view.global_position+atlas.view.world_to_map(target)
 await click(screen,true)
 check(not atlas.travel_hint.visible and game.spawn_token==token and atlas.opened,"Ctrl-click cannot teleport gameplay players")
 check(not atlas.teleport_to(Vector2(target.x,target.z)),"direct request also enforces development mode")
 var place:Dictionary={"title":"Map click fixture","position":origin+Vector3(60,0,50)}
 atlas.places.append(place);atlas.view.queue_redraw();await process_frame
 await click(atlas.view.global_position+atlas.view.world_to_map(place.position))
 check(game.destination_guide.destination.get("title")==place.title and game.spawn_token==token,"ordinary marker clicks still track destinations")
 atlas.set_open(false);menu.toggle_developer();atlas.set_open(true)
 check(menu.developer and atlas.travel_hint.visible,"map explains Ctrl-click in development mode")
 atlas.view.zoom=2.5;atlas.view.center=Vector2(target.x-90,target.z+40);atlas.view.queue_redraw();await process_frame
 screen=atlas.view.global_position+atlas.view.world_to_map(target)
 await click(screen)
 check(game.spawn_token==token and atlas.opened,"plain development click does not teleport")
 await mouse(screen,true,true)
 var motion:=InputEventMouseMotion.new();motion.position=screen+Vector2(55,25);motion.global_position=motion.position;motion.relative=Vector2(55,25);motion.button_mask=MOUSE_BUTTON_MASK_LEFT;motion.ctrl_pressed=true
 var center:Vector2=atlas.view.center
 Input.parse_input_event(motion);Input.flush_buffered_events();await process_frame
 await mouse(screen+Vector2(55,25),false,true)
 check(game.spawn_token==token and atlas.view.center!=center and atlas.opened,"Ctrl-drag pans without teleporting")
 screen=atlas.view.global_position+atlas.view.world_to_map(target)
 await mouse(screen,true,true);await mouse(screen,false,false)
 check(game.spawn_token==token,"releasing Ctrl before the click completes cancels teleport")
 check(not atlas.teleport_to(Vector2(-10,500)) and not atlas.teleport_to(Vector2(INF,500)) and atlas.opened and game.spawn_token==token,"off-world and nonfinite targets do not move the player")
 game.world_vehicle.driving=true
 atlas.teleport_to(Vector2(target.x,target.z))
 game.world_vehicle.driving=false
 check(atlas.opened and game.spawn_token==token and atlas.travel_hint.text.contains("exit the vehicle"),"driving blocks teleport without ejecting or moving the vehicle")
 var preparation_status:String=game.site_preparation.status;game.site_preparation.status="running"
 atlas.teleport_to(Vector2(target.x,target.z))
 game.site_preparation.status=preparation_status
 check(atlas.opened and game.spawn_token==token,"active world preparation blocks travel")
 atlas.set_open(false);atlas.set_open(true)
 atlas.view.zoom=2.5;atlas.view.center=Vector2(target.x-90,target.z+40);atlas.view.queue_redraw();await process_frame
 screen=atlas.view.global_position+atlas.view.world_to_map(target)
 await capture("map_hint")
 await mouse(screen,true,true)
 check(game.spawn_token==token,"teleport waits for click release")
 game.navigation_residency.next_refresh=0
 game.navigation_residency.update(PackedVector3Array([game.player.global_position]))
 check(not game.terrain.navigation_interest.is_empty(),"previous encounter has active navigation residency before travel")
 await mouse(screen,false,true)
 if not check(game.terrain.navigation_interest.is_empty() and game.navigation_residency.last_points.is_empty(),"teleport clears previous encounter residency before changing terrain focus"):await finish();return
 check(game.spawn_token==token+1 and Vector2(game.pending_spawn.x,game.pending_spawn.z).distance_to(Vector2(target.x,target.z))<0.01,"Ctrl-click resolves the exact world point after map pan and zoom")
 check(not atlas.opened and not atlas.view.dragging and not menu.visible_ui() and game.loading_active,"map closes and starts the normal destination loading barrier")
 check(game.controls.direction()==Vector3.ZERO and game.player.velocity==Vector3.ZERO,"travel clears player movement and held actions")
 check(not atlas.teleport_to(Vector2(400,400)) and game.spawn_token==token+1,"closed map and in-progress travel reject repeat requests")
 await capture("loading")
 if not check(await until(func():return not game.loading_active and not game.waiting_spawn and not game.needs_floor_spawn,70),"destination collision and floor become playable"):await finish();return
 check(game.terrain.latest_error.is_empty(),"destination streaming preserves valid native planning state")
 game.navigation_residency.next_refresh=0
 game.navigation_residency.update(PackedVector3Array([game.player.global_position]))
 check(not game.terrain.navigation_interest.is_empty(),"navigation residency resumes normally at the destination")
 check(Vector2(game.player.position.x,game.player.position.z).distance_to(Vector2(target.x,target.z))<1.0 and game.player.position.y>0,"player arrives at the clicked horizontal position with resolved terrain height")
 check(menu.developer and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED and not game.player_hud.inventory_open,"development mode and normal mouse control survive arrival")
 check(game.player_hud.inventory.capture_storage_snapshot()==inventory and game.terrain.published_revision==revision,"teleport does not mutate inventory or terrain")
 await capture("arrival")
 await finish()
func finish()->void:
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;await process_frame
 FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"  "))
 print("WORLD_MAP_TELEPORT checks=",checks," failures=",failures);quit(1 if failures else 0)
