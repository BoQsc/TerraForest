extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var failures:=0
var checks:=0
func check(condition:bool,message:String)->void:
 checks+=1
 if not condition:failures+=1
 print("PASS " if condition else "FAIL ",message)
func _initialize()->void:run.call_deferred()
func run()->void:
 for addon:String in ["world_runtime","vegetation_runtime","volumetric_terrain"]:
  GDExtensionManager.load_extension("res://addons/%s/%s.gdextension"%[addon,"terrain_core" if addon=="volumetric_terrain" else addon])
 var codec=ClassDB.instantiate("NativeWorldRecipe")
 var options:Dictionary={"biome":1,"settlements":3,"districts":2,"network":1,"trails":2}
 var bytes:PackedByteArray=codec.encode(options)
 check(bytes.size()==28 and codec.decode(bytes)==options and codec.restore_snapshot(bytes),"native recipe storage round trip")
 var modern:=options.duplicate();modern["road_grid"]=1
 var modern_bytes:PackedByteArray=codec.encode(modern)
 check(modern_bytes.size()==32 and codec.decode(modern_bytes)==modern,"native road preference roundtrip retains v1 compatibility")
 var invalid_road:=modern_bytes.duplicate();invalid_road.encode_u32(28,2)
 check(not codec.validate_snapshot(invalid_road),"invalid road preference rejected")
 modern.road_grid=2
 var connected:PackedByteArray=codec.encode(modern)
 check(connected.size()==32 and connected.decode_u32(4)==3 and codec.decode(connected)==modern,"connected grading has separate durable recipe identity")
 modern.road_grid=3
 var footprint:PackedByteArray=codec.encode(modern)
 check(footprint.size()==32 and footprint.decode_u32(4)==4 and codec.decode(footprint)==modern,"native footprint policy has independent generation identity")
 var mismatched:=footprint.duplicate();mismatched.encode_u32(4,3)
 check(not codec.validate_snapshot(mismatched),"new policy cannot masquerade as a legacy recipe")
 check(not codec.validate_snapshot(modern_bytes.slice(0,28)),"truncated version-two recipe cannot masquerade as legacy")
 for offset in range(0,28,4):
  var corrupt:=bytes.duplicate();corrupt.encode_u32(offset,0xffffffff)
  check(not codec.restore_snapshot(corrupt) and codec.capture_snapshot()==bytes,"malformed recipe field cannot mutate live state")
 var invalid:=options.duplicate();invalid.biome=1.5
 check(codec.encode(invalid).is_empty(),"reject noninteger settings")
 invalid=options.duplicate();invalid["unknown"]=1
 check(codec.encode(invalid).is_empty(),"reject unknown settings")
 var pixels:=PackedByteArray();pixels.resize(256*256*4);pixels.fill(128)
 var woodland:PackedByteArray=codec.render_biomes(pixels,1703,0)
 var meadow:PackedByteArray=codec.render_biomes(pixels,1703,2)
 check(woodland.size()==pixels.size() and woodland!=meadow and meadow==codec.render_biomes(pixels,1703,2),"native biome map is deterministic and profile-specific")
 var scatter=ClassDB.instantiate("NativeVegetationScatter")
 var totals:=[0,0,0];var stable:=true
 for row in 32:
  for column in 32:
   var previous:=PackedInt64Array()
   for profile in 3:
    var result:Dictionary=scatter.candidates(Vector2i(column,row),1703,.82,true,profile);totals[profile]+=result.ids.size()
    if profile>0:
     for identity:int in result.ids:stable=stable and identity in previous
    previous=result.ids
 check(stable and totals[0]>totals[1] and totals[1]>totals[2] and totals[2]>0,"native ecology uses ordered biomes without changing retained IDs")
 var core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[1703,21]))
 check(not core.plan_region_network([],[],false,0,1703).ok,"empty road graph fails safely")
 var exits:Array=[];var network:Dictionary={}
 for coordinate in range(800,1201,64):
  var points:=PackedVector3Array([Vector3(coordinate,0,1000),Vector3(coordinate+96,0,1000)])
  var query:=Codec.command(37,[2]);query.append_array(points.to_byte_array());var heights:PackedByteArray=core.execute(query)
  if not Codec.reply_ok(heights) or heights.size()!=28:continue
  points[0].y=heights.decode_float(12);points[1].y=heights.decode_float(20)
  exits=[PackedVector3Array([points[0]]),PackedVector3Array([points[1]])]
  network=core.plan_region_network(exits,[],false,0,1703)
  if network.get("ok",false):break
 check(network.get("ok",false) and network.get("links",[]).size()==1,"native graph produces a real terrain-fitting connection")
 if network.get("ok",false):
  check(network==core.plan_region_network(exits,[],false,0,1703),"native network is deterministic")
  var points:PackedVector3Array=network.points
  var center:Vector3=points[0].lerp(points[1],.5)+Vector3.UP*10
  var across:=Vector3.UP.cross(points[1]-points[0]).normalized()*4
  var blocked:Dictionary=core.plan_region_network(exits,[],false,0,1703,[{"start":center-across,"finish":center+across}])
  check(not blocked.ok and blocked.get("crossing_rejections",0)>0,"different-height crossings are rejected rather than stamped over streets")
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://reports"))
 FileAccess.open("res://reports/world_recipe_native.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"variant":core.build_variant(),"tree_counts":totals},"  "))
 print("WORLD_RECIPE_NATIVE checks=",checks," failures=",failures);quit(1 if failures else 0)
