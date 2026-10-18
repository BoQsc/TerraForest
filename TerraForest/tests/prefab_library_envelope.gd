# SPDX-License-Identifier: 0BSD
extends SceneTree
const Library=preload("res://addons/structures/prefab_library.gd")
var failures:=0
func check(ok: bool,label: String)->bool:
 print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
 return ok
func _initialize()->void:run.call_deferred()
func run()->void:
 GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
 var world=preload("res://addons/structures/structures_world.gd").new();root.add_child(world);world.prepare()
 var catalog=preload("res://addons/structures/furniture_catalog.gd");catalog.register(world)
 world.blocks.set_cells(PackedInt32Array([20,20,20,1]))
 var table=world.model("furniture/table/v1")
 table.upsert_instances(PackedInt64Array([1]),PackedFloat32Array([1,0,0,23,0,1,0,20,0,0,1,20]))
 var library=Library.new();library.directory="user://envelope_library_"+str(OS.get_process_id())+"_"+str(Time.get_ticks_usec())
 library.select_corner(true,Vector3i(20,19,18));library.select_corner(false,Vector3i(26,23,22))
 var captured: Dictionary=library.capture(world.blocks,"Overhanging furniture",world.model_collections().values())
 if check(captured.ok,"library captures blocks and overhanging object"):
  check(captured.asset.get_model_attachments().size()==1 and captured.asset.get_attachment_envelope()==AABB(Vector3.ZERO,Vector3(7,5,5)),"capture retains complete selected volume")
  var placement=ClassDB.instantiate("NativePrefabPlacement")
  check(placement.place(world.blocks,captured.asset,Vector3i(60,20,20),1,world.model_collections(),[]).ok,"captured overhang places through native rotated transaction")
  var expected=ClassDB.instantiate("NativeBlockPrefab")
  check(expected.compose_frontage([captured.asset],1,8,3,1703),"reference layout uses explicit envelope")
  check(library.begin_frontage(captured.asset,1,8,3,1703,"Overhang street").ok,"background frontage starts")
  var result: Dictionary={};var deadline:=Time.get_ticks_msec()+10000
  while result.is_empty() and Time.get_ticks_msec()<deadline:
   await process_frame;result=library.poll_frontage()
  if check(result.get("ok",false),"background frontage publishes"):
   check(result.asset.get_bounds()==expected.get_bounds() and result.asset.get_records()==expected.get_records() and result.asset.get_model_attachments()==expected.get_model_attachments(),"worker preserves source envelope and exact layout")
  var reloaded=Library.new();reloaded.directory=library.directory;reloaded.load_library()
  check(reloaded.assets.size()==2,"fresh library reopens both assets")
  for asset: Resource in reloaded.assets:
   check(asset.get_attachment_envelope().size!=Vector3.ZERO,"library verification preserves explicit envelope")
 library.shutdown_frontage();world.free()
 print("PREFAB_LIBRARY_ENVELOPE failures=",failures);quit(1 if failures else 0)
