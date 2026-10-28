extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var failures:=0
var checks:=0
func check(condition:bool,message:String)->void:
 checks+=1
 if not condition:failures+=1
 print("PASS " if condition else "FAIL ",message)
func _initialize()->void:
 var recipe=ClassDB.instantiate("NativeWorldRecipe")
 var source:=Image.create(256,256,false,Image.FORMAT_RGBA8);source.fill(Color(.35,.48,.24))
 var bytes:=source.get_data()
 var full:=Image.create_from_data(256,256,false,Image.FORMAT_RGBA8,recipe.render_biomes(bytes,1703,0))
 var patch:=source.get_region(Rect2i(120,132,4,4))
 check(recipe.render_biomes(patch.get_data(),1703,0,Vector2i(120,132),4)==full.get_region(Rect2i(120,132,4,4)).get_data(),"edited patches use identical woodland coordinates and palette")
 source.fill(Color(.22,.23,.24));bytes=source.get_data()
 check(recipe.render_biomes(bytes,1703,0)==bytes,"asphalt is never painted green by woodland")
 source.fill(Color(.75,.76,.77));bytes=source.get_data()
 check(recipe.render_biomes(bytes,1703,0)==bytes,"stone and snow retain their material colors")
 var atlas=preload("res://addons/world_runtime/world_map.gd").new()
 check(not atlas.show_roads and not atlas.show_deposits and not atlas.show_places and not atlas.show_grid,"physical map starts without generated annotations")
 atlas.free()
 var raster=ClassDB.instantiate("NativeSurfaceMapRaster")
 var red:=Color(.6,.2,.1);var green:=Color(.1,.6,.2)
 check(raster.offer(PackedVector3Array([Vector3(100,20,100)]),PackedColorArray([red])) and raster.offer(PackedVector3Array([Vector3(100,30,100)]),PackedColorArray([green])),"native color raster admits overlapping heights")
 check(raster.accept_prefix(0,PackedByteArray([1])),"surface mask accepts selected roof")
 var painted:=Image.create_from_data(256,256,false,Image.FORMAT_RGBA8,raster.pixels(Color.WHITE))
 var roof:=painted.get_pixel(12,12)
 check(roof.g>roof.r and roof.a>0,"highest surface owns its material color")
 check(not raster.offer(PackedVector3Array([Vector3(100,30,100)]),PackedColorArray([red,green])),"mismatched colors rejected without mutation")
 var prefab=ClassDB.instantiate("NativeBlockPrefab")
 check(prefab.configure(PackedInt32Array([0,0,0,1,0,1,0,65,1,0,0,33])),"mixed block fixture configured")
 var sampled:Dictionary=prefab.survey_surface()
 check(sampled.points.size()==2 and sampled.colors[0].r>sampled.colors[1].r,"prefab preview surveys top blocks, not enclosing box")
 var core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[1703,25]))
 var base:=Image.create(256,256,false,Image.FORMAT_RGBA8);base.fill(Color(.35,.48,.24))
 var road:={"start":Vector3(200,50,1000),"finish":Vector3(600,50,1000),"half_width":6.0,"material":4}
 var pavement:=Image.create_from_data(256,256,false,Image.FORMAT_RGBA8,core.render_plan_map(base.get_data(),[road],[]))
 check(pavement.get_pixel(50,128).g<base.get_pixel(50,128).g and pavement.get_pixel(50,124)==base.get_pixel(50,124),"preview pavement uses physical width and asphalt color")
 for material:int in [1,2,3,4,8,9]:
  core.execute(Codec.command(6,[1703,25]))
  var center:=Vector3(128.5*2000/256,100,128.5*2000/256)
  center.y=core.execute(Codec.point_command(center)).decode_float(12)+8
  var packet:=Codec.brush(center,center,4,1,true,material)
  if material==4:packet=Codec.graded_bed(center-Vector3(4,0,0),center+Vector3(4,0,0),4,8,4,4)
  if material in [8,9]:
   core.execute(Codec.brush(center,center,4,1,true,1))
   packet=Codec.brush(center+Vector3.UP*5,center-Vector3.UP*5,1.6,4,true,material);packet.encode_u32(0,41)
  check(Codec.reply_ok(core.execute(packet)),"valid native material fixture %d"%material)
  var sampled_patch:Dictionary=core.survey_patch(256,128,128,1,1)
  var material_pixel:=Image.create_from_data(1,1,false,Image.FORMAT_RGBA8,sampled_patch.pixels).get_pixel(0,0)
  var matches:=false
  match material:
   1:matches=absf(material_pixel.r-material_pixel.g)<.04 and material_pixel.r>material_pixel.b
   2,9:matches=material_pixel.r>material_pixel.g and material_pixel.g>material_pixel.b
   3,8:matches=material_pixel.b>material_pixel.r
   4:matches=maxf(material_pixel.r,maxf(material_pixel.g,material_pixel.b))<.3
  check(matches,"edited terrain keeps actual material palette %d"%material)
 core.execute(Codec.command(6,[1703,25]))
 var center:=Vector3(128.5*2000/256,100,128.5*2000/256)
 center.y=core.execute(Codec.point_command(center)).decode_float(12)
 check(Codec.reply_ok(core.execute(Codec.graded_bed(center-Vector3(8,0,0),center+Vector3(8,0,0),8,8,4,4))),"actual pavement fixture uses road editing protocol")
 var asphalt:Dictionary=core.survey_patch(256,128,128,1,1)
 core.execute(Codec.brush(center,center+Vector3.UP*12,14,1,false,1))
 var mined:Dictionary=core.survey_patch(256,128,128,1,1)
 check(asphalt.pixels!=mined.pixels,"mining pavement removes its map color instead of keeping a planned road")
 var styles:Array=preload("res://demo/world_creation_panel.gd").STYLES
 check(styles[4].values[0]==0,"regional belt defaults to woodland rather than sparse grassland")
 print("NATURAL_MAP checks=",checks," failures=",failures)
 quit(1 if failures else 0)
