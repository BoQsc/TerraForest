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
 var ok:bool=view.destinations.size()==10 and not menu.developer and view.find_children("*","Button",true,false).is_empty()
 menu.toggle_developer();menu.show_page("Session");menu.show_page("World")
 for frame in 3:await process_frame
 var buttons=view.find_children("*","Button",true,false)
 ok=ok and menu.developer and buttons.size()==10
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://reports/world_destinations_menu.png")
 var target:Vector3=view.destinations[1].position
 buttons[1].pressed.emit()
 ok=ok and game.loading_active and not menu.visible_ui()
 deadline=Time.get_ticks_msec()+60000
 while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
 ok=ok and not game.loading_active and Vector2(game.player.position.x-target.x,game.player.position.z-target.z).length()<2
 print("WORLD_DESTINATIONS_SCENE failures=",0 if ok else 1," arrived=",game.player.position," expected=",target)
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;quit(0 if ok else 1)
