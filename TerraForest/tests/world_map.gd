# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
func key_press(code:int)->void:
 game.app_focused=true # Synthetic input fixture owns focus; shell polling can foreground another window.
 var event:=InputEventKey.new();event.physical_keycode=code;event.pressed=true;Input.parse_input_event(event)
 await process_frame
 event=InputEventKey.new();event.physical_keycode=code;event.pressed=false;Input.parse_input_event(event)
 await process_frame
func mouse_button(at:Vector2,button:int,pressed:bool)->void:
 var event:=InputEventMouseButton.new();event.position=at;event.global_position=at;event.button_index=button;event.pressed=pressed;Input.parse_input_event(event)
 await process_frame
var profiles:Array=[]
func measure(label:String)->void:
 var samples:Array=[];var gpu:Array=[];var previous:=Time.get_ticks_usec()
 for frame in 120:
  await process_frame
  var now:=Time.get_ticks_usec();samples.append((now-previous)/1000.0);previous=now
  gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
 samples.sort();gpu.sort();profiles.append({"stage":label,"p95_ms":samples[113],"max_ms":samples.back(),"gpu_p95_ms":gpu[113]})
func run()->void:
 game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.max_fps=60;game.background_fps=60;root.add_child(game)
 if not check(await wait_for(func():return not game.loading_active,60),"saved world loads"):await done();return
 for frame in 30:await process_frame
 RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
 await measure("closed_before")
 var focus:Vector3=game.terrain.focus
 var inventory:PackedByteArray=game.player_hud.inventory.capture_storage_snapshot()
 var selected:int=game.player_hud.active_slot
 var models:bool=game.model_tool.active
 var revision:int=game.terrain.published_revision
 await key_press(KEY_M)
 var atlas=game.world_map
 if not check(atlas.opened and Input.mouse_mode==Input.MOUSE_MODE_VISIBLE and game.player_hud.inventory_open,"M opens modal map"):await done();return
 if not check(await wait_for(func():return atlas.texture!=null,10),"native worker publishes survey texture"):await done();return
 check(atlas.places.size()==9 and atlas.places.all(func(p):return not 'mine' in p.title.to_lower()),"five public settlements and four lakes; secrets excluded")
 check(atlas.roads.slice(4).all(func(r):return r.width==game.road_palette.prepared_streets[atlas.roads.find(r)-4].width),"authored road widths match saved full widths")
 check(atlas.roads.size()==4+game.road_palette.prepared_streets.size(),"base routes plus exact saved authored streets")
 await measure("open")
 var before:Vector3=game.player.position
 await key_press(KEY_W);await key_press(KEY_2)
 var at:Vector2=atlas.view.global_position+atlas.view.size*0.5
 var zoom:float=atlas.view.zoom
 await mouse_button(at,MOUSE_BUTTON_WHEEL_UP,true);await mouse_button(at,MOUSE_BUTTON_WHEEL_UP,false)
 check(atlas.view.zoom>zoom and game.player_hud.active_slot==selected,"wheel zooms instead of changing toolbelt")
 await mouse_button(at,MOUSE_BUTTON_LEFT,true)
 var motion:=InputEventMouseMotion.new();motion.position=at+Vector2(80,30);motion.relative=Vector2(80,30);motion.button_mask=MOUSE_BUTTON_MASK_LEFT;Input.parse_input_event(motion);await process_frame
 await mouse_button(at+Vector2(80,30),MOUSE_BUTTON_LEFT,false)
 check(atlas.view.center.distance_to(Vector2(before.x,before.z))>1,"mouse drag pans map")
 check(game.model_tool.active==models and game.terrain.published_revision==revision and game.player_hud.inventory.capture_storage_snapshot()==inventory,"map inputs preserve equipment, terrain and inventory")
 check(game.player.position.distance_to(before)<0.1 and game.controls.direction()==Vector3.ZERO,"map blocks player movement")
 atlas.view.overview()
 for frame in 6:await process_frame
 await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png("res://reports/world_map_overview.png")
 var no_overlap:=true
 for i in atlas.view.label_boxes.size():
  for j in range(i):
   if atlas.view.label_boxes[i].intersects(atlas.view.label_boxes[j]):no_overlap=false
 check(no_overlap,"overview place labels do not overlap")
 var north:Dictionary=atlas.places[3]
 var button:Button=atlas.destination_list.get_child(3)
 await mouse_button(button.get_global_rect().get_center(),MOUSE_BUTTON_LEFT,true);await mouse_button(button.get_global_rect().get_center(),MOUSE_BUTTON_LEFT,false)
 check(game.destination_guide.destination.get("title","")==north.title,"clicking destination starts tracking")
 atlas.view.center=Vector2(north.position.x,north.position.z);atlas.view.zoom=6;atlas.view.queue_redraw()
 for frame in 6:await process_frame
 await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png("res://reports/world_map_neighborhood.png")
 check(game.terrain.focus.distance_to(focus)<1,"opening and panning leave streaming focus local")
 var builds:int=atlas.builds
 await key_press(KEY_ESCAPE)
 check(not atlas.opened and not game.session_menu.visible_ui() and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED,"Escape returns directly to play")
 await key_press(KEY_M);check(atlas.opened and atlas.builds==builds,"reopening reuses resident texture without worker build")
 await key_press(KEY_M);check(not atlas.opened,"M closes map")
 await measure("closed_after")
 game.session_menu.toggle_developer()
 var dev_slot:int=game.player_hud.developer_slot
 await key_press(KEY_M)
 check(atlas.opened and not game.session_menu.developer_hud.panel.visible and game.player_hud.developer_slot==dev_slot,"development map keeps tool selection and hides editor HUD")
 await key_press(KEY_ESCAPE)
 check(not atlas.opened and game.session_menu.developer,"map close preserves development mode")
 game.session_menu.toggle_developer()
 await key_press(KEY_W)
 check(not game.session_menu.visible_ui() and game.player_hud.enabled,"gameplay UI restored")
 var file:=FileAccess.open("res://reports/world_map.json",FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failures,"profile":atlas.last_profile,"roads":atlas.roads.size(),"places":atlas.places.size(),"builds":atlas.builds,"frames":profiles},"  "));file.close()
 await done()
func done()->void:
 print("WORLD_MAP failures=",failures)
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;quit(1 if failures else 0)
