# SPDX-License-Identifier: 0BSD
# One-time checkpoint setup; all field queries use an independent native world.
extends RefCounted
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
static func point(data:PackedByteArray,offset:int)->Vector3:
 return Vector3(data.decode_float(offset),data.decode_float(offset+4),data.decode_float(offset+8))
static func route(generator:int=6,seed_value:int=1703,cave:int=0)->Dictionary:
 if generator!=6 or cave<0 or cave>=4:return {}
 if not ClassDB.class_exists("TerrainCore"):GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
 var core=ClassDB.instantiate("TerrainCore")
 if not Codec.reply_ok(core.execute(Codec.command(6,[seed_value,generator]))):return {}
 var descriptors:PackedByteArray=core.execute(Codec.command(25))
 if not Codec.reply_ok(descriptors) or descriptors.size()!=584:return {}
 var offset:=24+cave*5*28
 var entrance:=point(descriptors,offset);var bend:=point(descriptors,offset+12)
 var direction:=bend-entrance;direction.y=0
 var length:float=direction.length();direction=direction.normalized()
 var epoch:int=core.execute(Codec.command(13)).decode_u32(12)
 var points:=PackedVector3Array()
 for distance in [-12.0,20.0,40.0,60.0]:
  var from:Vector3=entrance+direction*distance+Vector3.UP*20 if distance<0 else entrance.lerp(bend,distance/length)
  var hit:Dictionary=Codec.decode_density_ray(core.execute(Codec.density_ray_command(from,Vector3(from.x,0,from.z),256,epoch,true)))
  if hit.status!="hit":return {}
  points.append(hit.position)
 return {"points":points,"direction":direction,"generator":generator,"seed":seed_value,"cave":cave}
static func position_player(game:Node,description:Dictionary)->void:
 game.set_physics_process(false);game._clear_motion();game.needs_floor_spawn=false;game.fly=false
 game.player.position=description.points[0]+Vector3.UP*0.1
 var direction:Vector3=description.direction
 game.yaw=atan2(-direction.x,-direction.z);game.player.rotation.y=game.yaw
 game.pitch=-0.12;game.camera.rotation=Vector3(game.pitch,0,0)
 game.terrain.focus=game.player.position
 game._begin_loading("Preparing cave entrance")
