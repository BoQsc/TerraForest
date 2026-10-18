# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize()->void:run.call_deferred()
func run()->void:
 var game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.max_fps=60;game.background_fps=60;root.add_child(game)
 var deadline:=Time.get_ticks_msec()+90000
 while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
 if game.loading_active:quit(1);return
 var menu=game.session_menu
 menu.show_page("World")
 for frame in 3:await process_frame
 var view=menu.pages.World.get_child(0)
 var buttons=view.find_children("*","Button",true,false)
 var ok:bool=view.destinations.size()==10 and not menu.developer and buttons.size()==10
 var original:Vector3=game.player.position
 buttons[1].pressed.emit()
 ok=ok and game.destination_guide.destination.title==view.destinations[1].title and not game.loading_active and game.player.position==original and not menu.visible_ui()
 game.destination_guide.refresh()
 ok=ok and game.destination_guide.panel.visible and not game.destination_guide.timer.is_stopped()
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://reports/world_destination_guide.png")
 menu.show_page("World");game.destination_guide.refresh()
 ok=ok and not game.destination_guide.panel.visible
 for control:Button in view.find_children("*","Button",true,false):
  if control.text.begins_with("Stop tracking:"):control.pressed.emit();break
 ok=ok and game.destination_guide.destination.is_empty() and game.destination_guide.timer.is_stopped()
 menu.toggle_developer();menu.show_page("Session");menu.show_page("World")
 for frame in 3:await process_frame
 buttons=view.find_children("*","Button",true,false)
 var travel_buttons:Array=[]
 for control:Button in buttons:
  if control.text=="Travel here":travel_buttons.append(control)
 ok=ok and menu.developer and travel_buttons.size()==10
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://reports/world_destinations_menu.png")
 var target:Vector3=view.destinations[1].position
 travel_buttons[1].pressed.emit()
 ok=ok and game.loading_active and not menu.visible_ui()
 deadline=Time.get_ticks_msec()+60000
 while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
 ok=ok and not game.loading_active and Vector2(game.player.position.x-target.x,game.player.position.z-target.z).length()<2
 print("WORLD_DESTINATIONS_SCENE failures=",0 if ok else 1," arrived=",game.player.position," expected=",target)
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;quit(0 if ok else 1)
