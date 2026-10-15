# SPDX-License-Identifier: 0BSD
# Read-only authoring survey; no terrain or inventory edits.
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
const Checkpoint=preload("res://demo/cave_checkpoint.gd")
func _initialize()->void:run.call_deferred()
func run()->void:
 var core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[1703,6]))
 var descriptors:PackedByteArray=core.execute(Codec.command(25))
 var epoch:int=core.execute(Codec.command(13)).decode_u32(12)
 var found:Dictionary={};var queries:=0
 for index in 20:
  var offset:=24+index*28
  var a:Vector3=Checkpoint.point(descriptors,offset);var b:Vector3=Checkpoint.point(descriptors,offset+12)
  var radius:float=descriptors.decode_float(offset+24)
  for step in range(0,maxi(1,ceili(a.distance_to(b)/4))+1):
   var center:Vector3=a.lerp(b,float(step)/maxi(1,ceili(a.distance_to(b)/4)))
   for dx in range(-int(radius)+2,int(radius)-1,2):
    for dz in range(-int(radius)+2,int(radius)-1,2):
     var from:Vector3=center+Vector3(dx,0,dz)
     var hit:Dictionary=Codec.decode_density_ray(core.execute(Codec.density_ray_command(from,from-Vector3.UP*(radius+5),256,epoch,true)))
     queries+=1
     if hit.get("status")!="hit" or hit.normal.y<0.85 or from.y-hit.position.y<2.0:continue
     var point:Vector3=hit.position-Vector3.UP*0.5
     var packet:=Codec.point_command(point);packet.encode_u32(0,26)
     var sample:PackedByteArray=core.execute(packet);var material:int=sample.decode_u32(12)
     if material not in [8,9] or sample.decode_float(16)>=0 or absf(sample.decode_float(20))<0.9 or found.has(material):continue
     found[material]={"material":material,"surface":hit.position,"sample":point,"capsule":index}
     print("NATURAL_ORE ",found[material])
    if found.size()==2:break
   if found.size()==2:break
  if found.size()==2:break
 DirAccess.make_dir_recursive_absolute("res://reports/natural_ore_survey")
 var file:=FileAccess.open("res://reports/natural_ore_survey/candidates.bin",FileAccess.WRITE);file.store_var(found);file.close()
 file=FileAccess.open("res://reports/natural_ore_survey/result.json",FileAccess.WRITE);file.store_string(JSON.stringify({"candidates":found,"queries":queries},"  "));file.close()
 print("NATURAL_ORE_SURVEY failures=",0 if found.size()==2 else 1)
 quit(0 if found.size()==2 else 1)
