# SPDX-License-Identifier: 0BSD
extends "res://tests/world_map_cache.gd"
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
func run()->void:
 if not "--snapshot-readonly" in OS.get_cmdline_user_args():quit(2);return
 game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.max_fps=60;game.background_fps=60;root.add_child(game)
 if not check(await wait_for(func():return not game.loading_active,60),"saved generated world opens read-only"):await done();return
 game.world_map.set_open(true)
 var water=game.world_map.water_survey
 if not check(await wait_for(func():return water.complete and water.io==null and water.texture!=null,60),"actual saved water map ready"):await done();return
 var archive=ClassDB.instantiate("NativeWorldArchive")
 var snapshot:Dictionary=archive.decode(FileAccess.get_file_as_bytes(game.terrain.backend.save_path))
 var core=ClassDB.instantiate("TerrainCore");var load_packet:=Codec.command(5);load_packet.append_array(snapshot.sections.terrain)
 if not check(Codec.reply_ok(core.execute(load_packet)),"isolated survey loads the saved terrain archive"):await done();return
 var predicted:PackedByteArray=preload("res://addons/world_runtime/world_generation_plan.gd").water_preview(core,game.terrain.backend.world_generator)
 var actual_image:Image=water.texture.get_image()
 var actual:PackedByteArray=actual_image.get_data()
 var size:int=actual_image.get_width();var actual_count:=0;var predicted_count:=0;var misses:=0
 for z in range(19,size-19):
  for x in range(19,size-19):
   var a:bool=actual[(x+z*size)*4+3]>0;var p:bool=predicted[(x+z*size)*4+3]>0
   actual_count+=int(a);predicted_count+=int(p)
   if a==p:continue
   var neighbour:=false
   for dz in range(-1,2):
    for dx in range(-1,2):
     var i:int=(x+dx+(z+dz)*size)*4+3
     if (predicted[i]>0 if a else actual[i]>0):neighbour=true
   if not neighbour:misses+=1
 check(actual_count>0 and predicted_count>0 and misses==0,"generated surface preview matches saved inland water within one regional map pixel")
 FileAccess.open("res://reports/generation_lake_map.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"seed":game.terrain.backend.world_seed,"generator":game.terrain.backend.world_generator,"actual_pixels":actual_count,"preview_pixels":predicted_count,"misses_beyond_one_pixel":misses,"map_size":size,"scope":"Saved generated bowls at regional map resolution; shoreline precision is one pixel, not edited arbitrary water-volume equivalence"},"  "))
 await done()
