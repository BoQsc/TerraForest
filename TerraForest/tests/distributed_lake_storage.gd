extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var failures:=0
func check(accepted:bool,label:String)->void:
 if not accepted:failures+=1
 print("PASS " if accepted else "FAIL ",label)
func _initialize()->void:
 var reports:Array=[]
 for seed_value in [0,42,1703]:
  var core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[seed_value,25]))
  var definitions:Dictionary=preload("res://addons/volumetric_terrain/generated_lakes.gd").describe(core,25)
  var catalog:PackedByteArray=ClassDB.instantiate("NativeLakeCatalog").encode(definitions.records)
  var revision:int=core.execute(Codec.command(0)).decode_u32(12);var epoch:int=core.execute(Codec.command(13)).decode_u32(12)
  var baked:Dictionary=ClassDB.instantiate("NativeGeneratedLakeBake").run(core,catalog,revision,epoch)
  check(baked.get("ok",false),"twelve lakes fit native bake budgets, seed="+str(seed_value))
  if not baked.get("ok",false):print("LAKE_BUDGET_FAILURE ",baked);continue
  var water=ClassDB.instantiate("NativeRegionalWater")
  check(water.restore_snapshot(baked.snapshot),"complete native lake snapshot restores")
  var stats:Dictionary=water.statistics()
  var captured:Variant=water.capture_storage_snapshot(catalog)
  var bytes:PackedByteArray=captured.serialize_snapshot() if captured is RefCounted else captured
  check(not bytes.is_empty() and bytes==baked.snapshot,"restored lakes can save again with exact quantities and contacts")
  check(stats.resident_cell_bytes<128*1024*1024,"loaded contacts remain within snapshot allocation budget")
  baked.erase("snapshot");baked["seed"]=seed_value;baked["resident_cell_bytes"]=stats.resident_cell_bytes;reports.append(baked)
  captured=null;water=null
 DirAccess.make_dir_recursive_absolute("res://reports/distributed_generation")
 FileAccess.open("res://reports/distributed_generation/lake_storage.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"records":reports},"  "))
 print("DISTRIBUTED_LAKE_STORAGE failures=",failures)
 quit(1 if failures else 0)
