# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
var folder:=""
func _initialize()->void:
 for value:String in OS.get_cmdline_user_args():
  if value.begins_with("--check-evidence-dir="):folder=value.trim_prefix("--check-evidence-dir=")
 run.call_deferred()
func check(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1
 print("PASS " if ok else "FAIL ",label)
func save_json(name:String,value:Variant)->void:
 FileAccess.open(folder.path_join(name),FileAccess.WRITE).store_string(JSON.stringify(value,"  "))
func run()->void:
 if folder.is_empty():quit(2);return
 var native:RefCounted=ClassDB.instantiate("NativeLandformLab")
 var library:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://addons/world_runtime/assets/landform_library.json"))
 var rows:Array=[]
 for case:Dictionary in library.cases:
  var compiled:Dictionary=native.compile(library,case.id,1703)
  check(compiled.get("ok",false),case.id+" native compilation")
  if not compiled.get("ok",false):print(compiled);continue
  var bytes:PackedByteArray=compiled.program
  check(bytes==native.compile(library,case.id,1703).program,case.id+" deterministic binary program")
  check(native.validate(bytes),case.id+" binary validation")
  for offset in [0,4,8,24,28,32,bytes.size()-1]:
   var bad:=bytes.duplicate();bad[offset]^=1;check(not native.validate(bad),case.id+" corrupt program rejected "+str(offset))
  for seed_value in [1703,901,42]:
   var seeded:Dictionary=native.compile(library,case.id,seed_value)
   var raster:Dictionary=native.raster(seeded.program,257,false)
   check(raster.get("ok",false),case.id+" native raster "+str(seed_value))
   if not raster.get("ok",false):continue
   var m:Dictionary=raster.metrics
   check(m.lake_components==1 and m.lake_boundary_cells==0 and m.lake_area_m2>12000,case.id+" connected bounded lake "+str(seed_value))
   check(m.spilling_lake_components==0,case.id+" actual basin has no outlet to the sea "+str(seed_value))
   check(m.woodland_fraction>.06 and m.grass_fraction>.25,case.id+" woodland and ground-cover potential "+str(seed_value))
   check(m.height_min>=0 and m.height_max<256 and m.program_bytes<25000,case.id+" finite compact world bounds")
   rows.append({"case":case.id,"seed":seed_value,"compile_ms":seeded.compile_ms,"metrics":m})
   if seed_value==1703:
    FileAccess.open(folder.path_join(case.id+".lfp"),FileAccess.WRITE).store_buffer(bytes)
    Image.create_from_data(257,257,false,Image.FORMAT_RGBA8,raster.pixels).save_png(folder.path_join(case.id+"_terrain.png"))
    Image.create_from_data(257,257,false,Image.FORMAT_RGBA8,raster.ecology_pixels).save_png(folder.path_join(case.id+"_ecology.png"))
    var repeat:Dictionary=native.raster(bytes,257,false)
    check(repeat.heights==raster.heights and repeat.pixels==raster.pixels,case.id+" exact repeated sample output")
    var changed:Dictionary=native.raster(native.compile(library,case.id,901).program,257,false)
    check(changed.heights!=raster.heights,case.id+" seed changes terrain detail")
 check(not native.compile(library,"missing",1703).ok,"unknown case rejected")
 var bad_library:Dictionary=library.duplicate(true);bad_library.cases[0].instances[0].scale=20
 check(not native.compile(bad_library,library.cases[0].id,1703).ok,"unbounded authoring transform rejected")
 check(not native.raster(PackedByteArray(),257,false).ok,"empty program rejected")
 save_json("metrics.json",{"checks":checks,"failures":failures,"cases":rows,"scope":"Native landform compilation/raster only; not Generate-to-play or frame-rate acceptance."})
 if "--capture-lab" in OS.get_cmdline_user_args() and failures==0:
  var scene=load("res://demo/generation_lab.tscn").instantiate();root.add_child(scene)
  for i in library.cases.size():
   if i>0:scene.choose(i)
   var deadline:=Time.get_ticks_msec()+30000
   while not scene.ready_for_review and Time.get_ticks_msec()<deadline:await process_frame
   check(scene.ready_for_review,"interactive module preview "+str(i))
   for frame in 5:await RenderingServer.frame_post_draw
   root.get_texture().get_image().save_png(folder.path_join(library.cases[i].id+"_3d.png"))
  scene.queue_free();await process_frame
 print("GENERATION_LAB checks=",checks," failures=",failures);quit(1 if failures else 0)
