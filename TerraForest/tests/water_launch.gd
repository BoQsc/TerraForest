# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize():run.call_deferred()
func run():
 var game=load("res://demo/world.tscn").instantiate();root.add_child(game)
 var deadline:=Time.get_ticks_msec()+45000
 while Time.get_ticks_msec()<deadline:
  if game.lakes.statistics().ready==1 and not game.loading_active and game.equipped_tool==401:break
  await process_frame
 var ok:bool=game.lakes.statistics().ready==1 and game.equipped_tool==401 and not game.session_menu.developer
 var icon:Texture2D=preload("res://addons/player_runtime/item_icons.gd").texture(401)
 ok=ok and icon!=null and not icon.get_image().get_used_rect().size==Vector2i.ZERO
 var scene_ready:=false
 for item:Dictionary in game.lakes._lakes.values():
  while not item.scene.statistics().ready and Time.get_ticks_msec()<deadline:await process_frame
  scene_ready=item.scene.statistics().ready
 ok=ok and scene_ready
 # Position near the waterline, aiming down: exercise the real right/left click routing.
 if ok:
  var center:Vector3=game.lakes._lakes.values()[0].seed+Vector3(0,6,0)
  game.fly=true;game.player.global_position=center+Vector3(0,-2,10);game.camera.global_position=center+Vector3(0,-2,10);game.camera.look_at(center+Vector3(0,-4,8));game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
  var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true;game._unhandled_input(click)
  var slot:int=game.player_hud.active_slot
  ok=game.player_hud.inventory.snapshot().slots[slot].item==402
  click.button_index=MOUSE_BUTTON_RIGHT;game._unhandled_input(click)
  ok=ok and game.player_hud.inventory.snapshot().slots[slot].item==401
  if DisplayServer.get_name()!="headless":
   for i in 3:await RenderingServer.frame_post_draw
   root.get_texture().get_image().save_png("res://reports/water_launch.png")
 game.terrain.shutdown();game.queue_free();await process_frame;await process_frame
 print("WATER_LAUNCH failures=",int(not ok));quit(int(not ok))
