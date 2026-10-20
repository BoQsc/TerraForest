# SPDX-License-Identifier: 0BSD
extends "res://tests/village_shop_review.gd"
func run()->void:
 var game=load("res://demo/world.tscn").instantiate()
 game.temporary_world=true;game.max_fps=60;game.background_fps=60;root.add_child(game)
 if not await ready_world(game):quit(1);return
 var codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
 var core=ClassDB.instantiate("TerrainCore")
 core.execute(codec.command(6,[game.terrain.backend.world_seed,game.terrain.backend.world_generator]))
 var data:PackedByteArray=core.execute(codec.command(27))
 var lake:=Vector3(data.decode_float(48),data.decode_float(44),data.decode_float(56))
 var views:Array=[{"name":"lake","position":lake+Vector3(100,55,95),"target":lake},
 {"name":"mountain","position":Vector3(900,170,850),"target":Vector3(550,110,550)},
 {"name":"shore","position":lake+Vector3(48,3,24),"target":lake+Vector3(0,0,-25)}]
 for view:Dictionary in views:
  game.teleport(view.position)
  if not await ready_world(game):quit(1);return
  game.set_physics_process(false);game._clear_motion()
  game.camera.global_position=view.position;game.camera.look_at(view.target)
  for i in 120:await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://reports/natural_region_"+view.name+".png")
 print("NATURAL_REGION_REVIEW failures=0")
 game.free();quit()
