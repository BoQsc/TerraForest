# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
func click(text:String)->bool:
 for child in game.session_menu.developer_hud.content.get_children():
  if child is Button and child.text==text:child.pressed.emit();return true
 return check(false,"button exists: "+text)
func run()->void:
 var slot:=""
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--route-evidence="):evidence=arg.trim_prefix("--route-evidence=")
  if arg.begins_with("--world-slot="):slot=arg.trim_prefix("--world-slot=")
 if evidence.is_empty() or not slot.begins_with("actor_ui_"):quit(2);return
 game=load("res://demo/world.tscn").instantiate();game.background_fps=60;root.add_child(game)
 if not check(await wait_for(func():return not game.loading_active,45),"settlement copy loads"):await finish();return
 game.set_physics_process(false);game._clear_motion();game.app_focused=true
 if "--reopen-actors" in OS.get_cmdline_user_args():
  var saved:Dictionary=FileAccess.open(evidence,FileAccess.READ).get_var()
  check(game.actors.store.capture_storage_snapshot()==saved.actors,"actor identity and position restore exactly")
  check(game.actors.orders.capture_storage_snapshot()==saved.orders,"actor order restores exactly")
  check(game.actors.pool!=null,"restored actor simulation enabled")
  game.actors.select_near(saved.position)
  check(game.actors.pool.active_handles().has(game.actors.store.resolve_identity(saved.identity)),"saved actor activates after fresh reopen")
  await finish();return
 if not game.session_menu.developer:game.session_menu.toggle_developer()
 game.session_menu.activate_developer_slot(8);game.session_menu.developer_hud.refresh()
 check(game.actors.pool==null,"normal launch starts without actor simulation")
 click("Enable actor simulation")
 if not check(game.actors.pool!=null,"HUD enables native simulation without restart"):await finish();return
 var street:Dictionary=game.road_palette.prepared_streets[0]
 var direction:Vector3=(street.ends[1]-street.ends[0]).normalized()
 var side:=Vector3(-direction.z,0,direction.x)
 var start:Vector3=street.ends[0]+direction*6
 var goal:Vector3=start+direction*5
 game.player.position=start+side*3;game.terrain.focus=start
 for frame in 90:await physics_frame
 game.camera.global_position=start+side*3+Vector3.UP*2;game.camera.look_at(start)
 Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
 click("Place actor at aim")
 for frame in 4:await physics_frame
 game.camera.look_at(start+Vector3.UP*.93)
 click("Select / send at aim")
 var identity:int=game.actor_authoring.selected_identity
 if not check(identity!=0,"HUD places and selects grounded actor"):await finish();return
 game.camera.global_position=goal+side*3+Vector3.UP*2;game.camera.look_at(goal)
 click("Select / send at aim")
 if not check(game.actors.orders.get_target(identity).present,"HUD sends selected actor to real street hit"):await finish();return
 var handle:int=game.actors.store.resolve_identity(identity)
 var target:Vector3=game.actors.orders.get_target(identity).target
 for frame in 300:
  await physics_frame
  game.actors.update_simulation(1.0/60,start,true,game._actor_collision_ready)
 var position:Vector3=game.actors.store.get_position(handle)
 check(position.distance_to(target)<.3,"authored actor reaches commanded destination")
 check(game.actors.pool.navigation_status(handle).state=="arrived","route reports arrival")
 game.player.position=goal+side*3+Vector3.UP*.05
 game.camera.position=Vector3(0,1.62,0);game.camera.look_at(position)
 var file:=FileAccess.open(evidence,FileAccess.WRITE)
 file.store_var({"actors":game.actors.store.capture_storage_snapshot(),"orders":game.actors.orders.capture_storage_snapshot(),"identity":identity,"position":position});file.close()
 await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(evidence+".png")
 await finish()
