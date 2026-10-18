# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,label: String)->void:
 print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
func _initialize()->void:run.call_deferred()
func run()->void:
 GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
 GDExtensionManager.load_extension("res://addons/player_runtime/player_runtime.gdextension")
 var world=preload("res://addons/structures/structures_world.gd").new();root.add_child(world);world.prepare()
 var catalog=preload("res://addons/structures/furniture_catalog.gd");catalog.register(world)
 var asset=ClassDB.instantiate("NativeBlockPrefab")
 asset.configure(PackedInt32Array([0,0,0,1]))
 asset.configure_model_attachments([{"model":"furniture/table/v1","transform":Transform3D(Basis.IDENTITY,Vector3(3,0,0))}])
 var coordinator=preload("res://addons/player_runtime/construction_inventory.gd").new()
 var inventory=ClassDB.instantiate("NativePlayerInventory")
 var models: Dictionary=world.model_collections()
 check(not coordinator.place_prefab(world.blocks,inventory,asset,Vector3i(20,20,20),0,models,{},[]),"undeclared overhang rejected")
 var envelope:=AABB(Vector3(1,-1,-2),Vector3(5,4,4))
 check(asset.configure_attachment_envelope(envelope),"explicit attachment envelope accepted")
 for bad in [AABB(Vector3(NAN,0,0),Vector3.ONE),AABB(Vector3.ZERO,Vector3(-1,2,2)),AABB(Vector3(4096,0,0),Vector3.ONE)]:
  check(not asset.configure_attachment_envelope(bad) and asset.get_attachment_envelope()==envelope,"invalid envelope preserves definition")
 for turn in 4:
  var origin:=Vector3i(20+turn*20,20,20)
  var overhang:=Vector3(3,.5,0)
  for rotation in turn:overhang=Vector3(1-overhang.z,overhang.y,overhang.x)
  var protection:=AABB(Vector3(origin)+overhang-Vector3.ONE*.1,Vector3.ONE*.2)
  var before: PackedByteArray=world.capture_snapshot()
  check(not coordinator.place_prefab(world.blocks,inventory,asset,origin,turn,models,{},[protection]) and before==world.capture_snapshot(),"expanded rotated bounds protect actors")
  check(coordinator.place_prefab(world.blocks,inventory,asset,origin,turn,models,{},[]),"declared rotated attachment places: "+coordinator.reason)
 var transaction=ClassDB.instantiate("NativePrefabPlacement")
 var retained: PackedByteArray=world.capture_snapshot()
 check(transaction.begin(world.blocks,asset,Vector3i(200,20,20),0,models,[]).ok,"staged placement starts")
 asset.configure_attachment_envelope(envelope.grow(.1))
 check(not transaction.advance(100,10,1000).ok and world.capture_snapshot()==retained,"changed envelope cancels staged placement without mutation")
 asset.configure_attachment_envelope(envelope)
 var composed=ClassDB.instantiate("NativeBlockPrefab")
 check(composed.compose([asset],PackedInt32Array([0,10,0,0,1])) and composed.get_bounds()==asset.placement_bounds(Vector3i(10,0,0),1),"composition retains rotated attachment envelope")
 var path: String="user://envelope_"+str(OS.get_process_id())+".tres"
 check(ResourceSaver.save(asset,path)==OK,"resource saves explicit envelope")
 var restored: Resource=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
 check(restored!=null and restored.get_attachment_envelope()==envelope and restored.get_bounds()==asset.get_bounds(),"fresh resource load retains envelope")
 DirAccess.remove_absolute(path)
 check(asset.configure_attachment_envelope(AABB()) and asset.get_bounds()==AABB(Vector3.ZERO,Vector3.ONE),"empty envelope restores legacy block bounds")
 world.free();print("PREFAB_ENVELOPE failures=",failures);quit(1 if failures else 0)
