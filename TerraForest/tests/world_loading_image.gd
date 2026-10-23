# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize()->void:run.call_deferred()
func run()->void:
 var game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;root.add_child(game)
 var failures:=0
 var found:=false
 for child:Node in game.loading_layer.find_children("*","TextureRect",true,false):
  if child is TextureRect and child.texture!=null:found=true
 if not found:failures+=1
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://reports/world_loading_image.png")
 var deadline:=Time.get_ticks_msec()+90000
 while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
 if game.loading_active:failures+=1
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free()
 print("WORLD_LOADING_IMAGE failures=",failures);quit(1 if failures else 0)
