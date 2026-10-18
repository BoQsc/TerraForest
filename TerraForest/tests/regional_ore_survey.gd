# SPDX-License-Identifier: 0BSD
# Read-only survey of the three owned chambers in the current regional generator.
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
func _initialize()->void:run.call_deferred()
func run()->void:
 var seed:=1703
 var generator:=12
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--survey-seed="):seed=int(arg.trim_prefix("--survey-seed="))
  if arg.begins_with("--survey-generator="):generator=int(arg.trim_prefix("--survey-generator="))
 var core=ClassDB.instantiate("TerrainCore")
 if not Codec.reply_ok(core.execute(Codec.command(6,[seed,generator]))):quit(1);return
 var descriptors:PackedByteArray=core.execute(Codec.command(25))
 if not Codec.reply_ok(descriptors) or descriptors.size()<24+7*28:quit(1);return
 var epoch:int=core.execute(Codec.command(13)).decode_u32(12)
 var found:Dictionary={};var queries:=0;var floor_hits:=0;var chambers:Array=[]
 var deeper:bool="--survey-deeper" in OS.get_cmdline_user_args()
 for index in [2,4,6]:
  var offset:int=24+index*28
  var center:=Vector3(descriptors.decode_float(offset),descriptors.decode_float(offset+4),descriptors.decode_float(offset+8))
  var radius:float=descriptors.decode_float(offset+24)
  chambers.append({"index":index,"floor":center.y,"radius":radius})
  for dx in range(-int(radius)+2,int(radius)-1,2):
   for dz in range(-int(radius)+2,int(radius)-1,2):
    if Vector2(dx,dz).length()>radius-2:continue
    var origin:Vector3=center+Vector3(dx,3,dz)
    var hit:Dictionary=Codec.decode_density_ray(core.execute(Codec.density_ray_command(origin,origin-Vector3.UP*6,256,epoch,true)))
    queries+=1
    if hit.get("status")!="hit" or hit.normal.y<0.85:continue
    floor_hits+=1
    for depth in ([0.5,1.0,2.0,3.0,4.0] if deeper else [0.5]):
     var point:Vector3=hit.position-Vector3.UP*depth
     var packet:=Codec.point_command(point);packet.encode_u32(0,26)
     var sample:PackedByteArray=core.execute(packet)
     if not Codec.reply_ok(sample) or sample.size()<24:quit(1);return
     var material:int=sample.decode_u32(12)
     if material not in [8,9] or sample.decode_float(16)>=0 or absf(sample.decode_float(20))<0.9 or found.has(material):continue
     found[material]={"material":material,"surface":hit.position,"sample":point,"chamber":index,"depth":depth}
  if deeper:
   # Test walls at standing interaction height as well as chamber floors.
   # Exclude steep normals so these samples describe side walls, not ceilings.
   for direction_index in 32:
    var angle:float=TAU*direction_index/32.0
    var direction:=Vector3(cos(angle),0,sin(angle))
    var origin:=center+Vector3.UP*1.5
    var hit:Dictionary=Codec.decode_density_ray(core.execute(Codec.density_ray_command(origin,origin+direction*(radius+4),256,epoch,true)))
    queries+=1
    if hit.get("status")!="hit" or absf(hit.normal.y)>0.5:continue
    for depth in [0.5,1.0,2.0,3.0,4.0]:
     var point:Vector3=hit.position-hit.normal*depth
     var packet:=Codec.point_command(point);packet.encode_u32(0,26)
     var sample:PackedByteArray=core.execute(packet)
     if not Codec.reply_ok(sample) or sample.size()<24:quit(1);return
     var material:int=sample.decode_u32(12)
     if material not in [8,9] or sample.decode_float(16)>=0 or absf(sample.decode_float(20))<0.9 or found.has(material):continue
     found[material]={"material":material,"surface":hit.position,"sample":point,"chamber":index,"depth":depth,"wall":true}
 var folder:="res://reports/regional_ore_survey"
 if seed!=1703:folder+="_%d"%seed
 if generator!=12:folder+="_g%d"%generator
 if deeper:folder+="_deep"
 DirAccess.make_dir_recursive_absolute(folder)
 var file:=FileAccess.open(folder+"/candidates.bin",FileAccess.WRITE);file.store_var(found);file.close()
 file=FileAccess.open(folder+"/result.json",FileAccess.WRITE)
 file.store_string(JSON.stringify({"seed":seed,"generator":generator,"candidates":found,"queries":queries,"floor_hits":floor_hits,"chambers":chambers},"  "));file.close()
 print("REGIONAL_ORE_SURVEY seed=",seed," ",found," failures=",0 if found.size()==2 else 1)
 quit(0 if found.size()==2 else 1)
