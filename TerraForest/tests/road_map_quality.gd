extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
const Earthworks=preload("res://addons/world_runtime/generation_earthworks.gd")
var failures:=0
var checks:=0
func check(condition:bool,label:String)->void:
 checks+=1
 if not condition:failures+=1
 print("PASS " if condition else "FAIL ",label)
func sample(core:RefCounted,point:Vector3)->Dictionary:
 var packet:=Codec.point_command(point);packet.encode_u32(0,26)
 var reply:PackedByteArray=core.execute(packet)
 return {"material":reply.decode_u32(12),"density":reply.decode_float(16)}
func _initialize()->void:
 var core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[1703,25]))
 var center:=Vector3(1000,0,1000)
 center.y=ceilf(core.execute(Codec.point_command(center)).decode_float(12))+5.25
 var road:={"start":center-Vector3(24,0,24),"finish":center+Vector3(24,0,24),"half_width":3.0,"depth":6.0,"clearance":4.0,"material":4,"shoulder":4.0}
 var support:={"start":center-Vector3(0,0,24),"finish":center+Vector3(0,0,24),"half_width":5.0,"depth":6.0,"clearance":4.0,"material":1,"shoulder":4.0}
 var packets:=Earthworks.packets([road,support])
 check(packets.size()==2 and packets[0].decode_u32(40)==1 and packets[1].decode_u32(40)==4,"all grading precedes pavement without additional generation commands")
 check(core.bake_generated_earthworks(packets).get("ok",false),"crossing road and later earthwork fixture bakes")
 var missing:=0
 for along in range(-20,21):
  var point:=center+Vector3(along,-.5,along)
  if sample(core,point).material!=4:missing+=1
 check(missing==0,"all 41 road-center probes remain asphalt through later support crossing")
 check(sample(core,center-Vector3.UP*4).material!=4,"asphalt is a shallow surface, not the entire road embankment")
 var shoulder:=center+Vector3(-4,-3,4)
 check(sample(core,shoulder).material!=4,"rounded shoulder does not inherit asphalt")
 var stats:PackedByteArray=core.execute(Codec.command(0))
 var patch:Dictionary=core.survey_patch(1024,496,496,16,16)
 check(patch.get("ok",false) and patch.pixels.size()==16*16*4,"native high-resolution area survey stays bounded to a 16-pixel tile")
 check(core.execute(Codec.command(0))==stats,"detailed cartography never edits the terrain")
 var full:=Image.create_from_data(16,16,false,Image.FORMAT_RGBA8,patch.pixels)
 var split:=Image.create(16,16,false,Image.FORMAT_RGBA8)
 for depth in range(0,16,4):
  for across in range(0,16,4):
   var part:Dictionary=core.survey_patch(1024,496+across,496+depth,4,4)
   split.blit_rect(Image.create_from_data(4,4,false,Image.FORMAT_RGBA8,part.pixels),Rect2i(0,0,4,4),Vector2i(across,depth))
 check(full.get_data()==split.get_data(),"tile and sub-tile colors agree exactly without border seams")
 var recipe=ClassDB.instantiate("NativeWorldRecipe")
 var colored:PackedByteArray=recipe.render_biomes(patch.pixels,1703,0,Vector2i(496,496),16,1024)
 check(colored.size()==patch.pixels.size(),"high-resolution biome coordinates are accepted")
 var before:PackedByteArray=patch.pixels
 var mined:PackedByteArray=core.execute(Codec.brush(center,center,5,1,false,1))
 check(Codec.reply_ok(mined) and mined.decode_u32(16)>0,"pavement is destructible terrain")
 check(core.survey_patch(1024,496,496,16,16).pixels!=before,"mining immediately changes authoritative road map pixels")
 check(not core.survey_patch(1024,0,0,17,16).get("ok",false) and not core.survey_patch(1025,0,0,16,16).get("ok",false),"oversized live jobs rejected")
 print("ROAD_MAP_QUALITY checks=",checks," failures=",failures," tile_ms=",patch.get("generation_ms",-1))
 quit(1 if failures else 0)
