extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var checks:=0
var failures:=0
var profiles:Array=[]
func _initialize()->void:run.call_deferred()
func check(condition:bool,title:String)->bool:
 checks+=1;print("PASS " if condition else "FAIL ",title)
 if not condition:failures+=1
 return condition
func run()->void:
 GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
 GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
 var core=ClassDB.instantiate("TerrainCore")
 for seed_value in [0,42,1703,2147483647]:
  for generator in [17,23]:
   core.execute(Codec.command(6,[seed_value,generator]))
   var before:PackedByteArray=core.execute(Codec.command(4))
   var result:Dictionary=core.plan_material_deposits([])
   if not check(result.get("ok",false) and result.deposits.size()>0 and result.deposits.size()<=100,"bounded nonempty native plan: %d/%d"%[seed_value,generator]):continue
   profiles.append({"seed":seed_value,"generator":generator,"count":result.deposits.size(),"worker_ms":result.worker_ms,"candidates":result.candidates})
   check(result.deposits==core.plan_material_deposits([]).deposits,"repeat generation is deterministic")
   check(core.execute(Codec.command(4))==before,"planning does not author density pages or mutate terrain")
   var ore_ok:=true;var support_ok:=true;var identities:Dictionary={};var materials:Dictionary={}
   for deposit:Dictionary in result.deposits:
    var center:Vector3=(deposit.start+deposit.finish)*.5
    var query:=Codec.point_command(center);query.encode_u32(0,26)
    var reply:PackedByteArray=core.execute(query)
    ore_ok=ore_ok and reply.decode_float(16)<0 and signf(reply.decode_float(20))==(1 if deposit.material==8 else -1) and absf(reply.decode_float(20))>.99
    identities[deposit.id]=true;materials[deposit.material]=true
    var point:Vector3=deposit.position
    support_ok=support_ok and absf(center.x-point.x)<.001 and absf(center.z-point.z)<.001 and point.y-center.y>=10 and point.y-center.y<=38
   check(ore_ok,"every surface marker lies directly over actual solid ore of the same material")
   check(support_ok and identities.size()==result.deposits.size() and materials.size()==2,"bounded depth, stable unique identities and both materials")
   var storage=ClassDB.instantiate("NativeGeneratedRegion")
   check(storage.set_plan(seed_value,generator,result.deposits,[]),"native binary deposit metadata accepts the exact plan")
   var restored=ClassDB.instantiate("NativeGeneratedRegion")
   check(restored.restore_snapshot(storage.capture_snapshot()) and restored.capture_snapshot()==storage.capture_snapshot(),"deposit metadata restores byte-exactly")
   var first:Dictionary=result.deposits[0]
   var exclusion:Dictionary={"start":first.position-Vector3(3,0,0),"finish":first.position+Vector3(3,0,0),"half_width":12.0,"shoulder":8.0}
   var excluded:Dictionary=core.plan_material_deposits([exclusion])
   check(excluded.ok and not excluded.deposits.any(func(deposit):return deposit.id==first.id),"road and construction earthworks exclude surface stones")
   var samples:Dictionary={}
   for deposit:Dictionary in result.deposits:
    var center:Vector3=(deposit.start+deposit.finish)*.5
    for height in range(ceili(center.y),floori(deposit.position.y)+1):
     var sample:=Vector3(deposit.position.x,height,deposit.position.z)
     samples[sample]=core.execute(Codec.point_command(sample)).decode_float(16)
   var baked:Dictionary=core.bake_generated_earthworks(preload("res://addons/world_runtime/generation_earthworks.gd").packets([],result.deposits))
   profiles[-1]["bake_ms"]=baked.get("worker_ms",0)
   profiles[-1]["pages"]=core.execute(Codec.command(0)).decode_u32(20)
   check(baked.get("ok",false) and baked.completed==result.deposits.size(),"native material-only bake connects every marker without additional density geometry")
   var continuous:=true;var density_unchanged:=true
   for deposit:Dictionary in result.deposits:
    var center:Vector3=(deposit.start+deposit.finish)*.5
    for height in range(ceili(center.y),floori(deposit.position.y)+1):
     var sample:=Vector3(deposit.position.x,height,deposit.position.z)
     var query:=Codec.point_command(sample);query.encode_u32(0,26)
     var reply:PackedByteArray=core.execute(query)
     var valid:bool=reply.decode_u32(12)==deposit.material and reply.decode_float(16)<0
     valid=valid or (height==floori(deposit.position.y) and float(samples[sample])>=0 and reply.decode_float(16)>=0)
     continuous=continuous and valid
     density_unchanged=density_unchanged and absf(reply.decode_float(16)-float(samples[sample]))<=.001
   check(continuous,"all solid samples from the surface down every marker column contain matching ore; boundary air stays air")
   check(density_unchanged,"ore connection does not fill caves, change hills or alter surface height")
 check(not core.plan_material_deposits([{"start":Vector3.ZERO}]).get("ok",true),"incomplete exclusion fails safely")
 check(not core.plan_material_deposits([{"start":Vector3.ZERO,"finish":Vector3.ONE,"half_width":NAN,"shoulder":0.0}]).get("ok",true),"nonfinite exclusion fails safely")
 var unchanged:PackedByteArray=core.execute(Codec.command(4))
 var malformed:=Codec.brush(Vector3(100,30,100),Vector3(100,20,100),NAN,4,true,8);malformed.encode_u32(0,41)
 check(not Codec.reply_ok(core.execute(malformed)) and core.execute(Codec.command(4))==unchanged,"invalid mineral connector leaves the entire terrain unchanged")
 core.execute(Codec.command(6,[1703,23]))
 var deposit:Dictionary=core.plan_material_deposits([]).deposits[0]
 core.bake_generated_earthworks(preload("res://addons/world_runtime/generation_earthworks.gd").packets([],[deposit]))
 var point:Vector3=deposit.position-Vector3.UP*2
 var receipt:PackedByteArray=core.execute(Codec.brush(point,point,1.8,0,false,0))
 check(Codec.reply_ok(receipt) and receipt.decode_u32(16)>0,"real vein can be mined through ordinary terrain edits")
 check(Codec.excavation_samples(receipt)[deposit.material]>0,"digging immediately below the marker yields its material")
 check(core.execute(Codec.point_command(point)).decode_float(16)>0,"mining removes authoritative ore density")
 var snapshot:=Codec.command(5);snapshot.append_array(core.execute(Codec.command(4)).slice(12))
 var restored=ClassDB.instantiate("TerrainCore")
 check(Codec.reply_ok(restored.execute(snapshot)) and restored.execute(Codec.point_command(point))==core.execute(Codec.point_command(point)),"mined vein survives terrain save/reload")
 DirAccess.make_dir_recursive_absolute("res://reports/material_deposits")
 FileAccess.open("res://reports/material_deposits/native.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"profiles":profiles},"  "))
 print("MATERIAL_DEPOSITS_NATIVE checks=",checks," failures=",failures);quit(1 if failures else 0)
