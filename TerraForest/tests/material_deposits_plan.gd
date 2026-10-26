extends SceneTree
const Plan=preload("res://addons/world_runtime/custom_world_plan.gd")
const Recipe=preload("res://addons/world_runtime/world_recipe.gd")
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var checks:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(condition:bool,title:String)->void:
 checks+=1;print("PASS " if condition else "FAIL ",title)
 if not condition:failures+=1
func run()->void:
 for extension in ["volumetric_terrain/terrain_core","structures/structures","world_runtime/world_runtime"]:GDExtensionManager.load_extension("res://addons/"+extension+".gdextension")
 var folder:="user://mineral_plan_check_"+Crypto.new().generate_random_bytes(8).hex_encode()
 var enabled:Dictionary=Recipe.DEFAULTS.duplicate()
 var on:=Plan.build(1703,23,enabled,folder)
 check(on.get("ok",false) and not on.get("material_deposits",[]).is_empty(),"default production plan contains native material deposits")
 if not on.get("ok",false):finish();return
 var cached:=Plan.build(1703,23,enabled,folder)
 check(cached.get("cache_hit",false) and cached.material_deposits==on.material_deposits and cached.plan_digest==on.plan_digest,"warm generation reuses exact deposit descriptors from the binary plan cache")
 var independent:=Plan.build(1703,23,enabled,folder+"_independent")
 check(independent.get("plan_digest","")==on.plan_digest,"independent cold plans have identical digests; timing diagnostics cannot change world identity")
 var disabled:=enabled.duplicate();disabled.material_veins=0
 var off:=Plan.build(1703,23,disabled,folder)
 check(off.get("ok",false) and not off.has("material_deposits") and off.plan_digest!=on.plan_digest,"disabled option generates no surface-deposit feature and has a separate cache identity")
 check(off.get("works",{})==on.works,"deposit option cannot change existing roads or earthworks")
 var core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[1703,23]))
 var original_core=ClassDB.instantiate("TerrainCore");original_core.execute(Codec.command(6,[1703,23]))
 var baked:Dictionary=core.bake_generated_earthworks(preload("res://addons/world_runtime/generation_earthworks.gd").packets(on.works.segments))
 var supports:bool=baked.get("ok",false);var veins:=true
 for deposit:Dictionary in on.material_deposits:
  var original:Vector3=deposit.position
  var query:=Codec.point_command(original);var reply:PackedByteArray=core.execute(query)
  supports=supports and reply==original_core.execute(query) and absf(reply.decode_float(12)-original.y)<.001
  query=Codec.point_command((deposit.start+deposit.finish)*.5);query.encode_u32(0,26);reply=core.execute(query)
  veins=veins and reply.decode_u32(12)==deposit.material and reply.decode_float(16)<0
 check(supports,"actual generated roads/foundations leave every mineral stone supported at its planned surface")
 check(veins,"actual generated earthworks preserve the matching buried material under every stone")
 var blank:=PackedByteArray();blank.resize(256*256*4);blank.fill(100)
 var preview:PackedByteArray=preload("res://addons/world_runtime/material_deposits.gd").preview_pixels(blank,on.material_deposits)
 check(preview.size()==blank.size() and preview!=blank and preload("res://addons/world_runtime/material_deposits.gd").preview_pixels(blank,[])==blank,"generation preview shows deposits only when enabled")
 DirAccess.make_dir_recursive_absolute("res://reports/material_deposits")
 FileAccess.open("res://reports/material_deposits/plan.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"count":on.material_deposits.size(),"native_plan_ms":on.mineral_plan_ms,"plan_digest":on.plan_digest,"off_digest":off.get("plan_digest",""),"cache_folder":folder},"  "))
 finish()
func finish()->void:
 print("MATERIAL_DEPOSITS_PLAN checks=",checks," failures=",failures);quit(1 if failures else 0)
