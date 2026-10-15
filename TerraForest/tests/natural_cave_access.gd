# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
func point(data:PackedByteArray,offset:int)->Vector3:
 return Vector3(data.decode_float(offset),data.decode_float(offset+4),data.decode_float(offset+8))
func _initialize()->void:
 GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
 var core=ClassDB.instantiate("TerrainCore")
 core.execute(Codec.command(6,[1703,4]))
 var epoch:int=core.execute(Codec.command(13)).decode_u32(12)
 var descriptors:PackedByteArray=core.execute(Codec.command(25))
 var routes:Array=[];var eligible:=0
 for cave in 4:
  var offset:=24+cave*5*28
  var entrance:=point(descriptors,offset);var bend:=point(descriptors,offset+12)
  var direction:Vector3=(bend-entrance);direction.y=0;direction=direction.normalized()
  var rows:Array=[];var missing:=0;var steep:=0;var blocked:=0
  for step in range(-12,41):
   var at:=entrance+direction*step
   # Above the mouth use the surface, inside start in the canonical capsule.
   var from:=at+Vector3.UP*20 if step<0 else entrance.lerp(bend,float(step)/Vector2(bend.x-entrance.x,bend.z-entrance.z).length())
   var floor_hit:Dictionary=Codec.decode_density_ray(core.execute(Codec.density_ray_command(from,Vector3(at.x,0,at.z),256,epoch,true)))
   if floor_hit.status!="hit":missing+=1;rows.append({"step":step,"status":floor_hit.status});continue
   if floor_hit.normal.y<cos(PI/4):steep+=1
   var foot:Vector3=floor_hit.position
   var head:Dictionary=Codec.decode_density_ray(core.execute(Codec.density_ray_command(foot+Vector3.UP*0.1,foot+Vector3.UP*1.9,16,epoch,true)))
   if head.status!="miss":blocked+=1
   rows.append({"step":step,"floor":[foot.x,foot.y,foot.z],"normal_y":floor_hit.normal.y,"headroom":head.status})
  var valid:bool=missing==0 and steep==0 and blocked==0
  if valid:eligible+=1
  routes.append({"cave":cave,"entrance":[entrance.x,entrance.y,entrance.z],"bend":[bend.x,bend.y,bend.z],"eligible":valid,"missing":missing,"steep":steep,"blocked":blocked,"samples":rows})
  print("CAVE_ACCESS cave=",cave," missing=",missing," steep=",steep," blocked=",blocked)
 DirAccess.make_dir_recursive_absolute("res://reports/natural_cave_access")
 var file:=FileAccess.open("res://reports/natural_cave_access/profile.json",FileAccess.WRITE)
 file.store_string(JSON.stringify({"seed":1703,"generator":4,"eligible":eligible,"routes":routes,"scope":"Density floor/headroom samples at one-metre spacing along canonical mouth centre lines. Does not prove capsule clearance, traversable mesh collision or discovery from settlement."},"  "));file.close()
 print("NATURAL_CAVE_ACCESS eligible=",eligible)
 quit(0 if eligible>0 else 1)
