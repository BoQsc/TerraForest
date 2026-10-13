# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok:bool,label:String):
 print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
func inventory():
 var result=ClassDB.instantiate("NativePlayerInventory")
 for item in range(401,412):result.register_item(item,1)
 result.register_item(201,64)
 return result
func _initialize():
 GDExtensionManager.load_extension("res://addons/player_runtime/player_runtime.gdextension")
 var source=inventory();source.grant(401,1,0)
 check(source.exchange_water(0,false,source.snapshot().revision,1000000),"One cubic metre fits in explicit water quantity")
 check(source.snapshot().slots[0].item==401 and source.snapshot().slots[0].water_ml==1000000,"Item identity stays stable while exact amount changes")
 var before:Dictionary=source.snapshot()
 check(not source.exchange_water(0,false,before.revision,1) and source.snapshot()==before,"Overflow is atomic")
 check(not source.exchange_water(0,true,-1,1000) and source.snapshot()==before,"Stale exchange is atomic")
 check(not source.exchange_bucket(0,true,before.revision,1) and source.snapshot()==before,"Legacy API cannot erase explicit large contents")
 var target=inventory()
 check(source.transfer_to(target,0,1,before.revision,0).ok and target.snapshot().slots[0].water_ml==1000000,"Inventory transfer preserves full volume")
 var store=ClassDB.instantiate("NativeContainerStore");store.configure(target,8)
 check(store.deposit(7,target,0,1,target.snapshot().revision,store.snapshot(7).store_revision).ok,"Full water carrier can be dropped/stored through the shared container path")
 var bytes:PackedByteArray=store.capture_storage_snapshot();var loaded=ClassDB.instantiate("NativeContainerStore");loaded.configure(target,8)
 check(loaded.restore_storage_snapshot(bytes) and loaded.snapshot(7).slots[0].water_ml==1000000,"Container archive preserves all millilitres")
 check(loaded.withdraw(7,target,0,1,target.snapshot().revision,loaded.snapshot(7).store_revision).ok and target.snapshot().slots[0].water_ml==1000000,"Pickup/withdrawal preserves full volume")
 check(target.exchange_water(0,true,target.snapshot().revision,999999) and target.snapshot().slots[0].water_ml==1,"Partial pours preserve sub-litre remainder")
 target.grant(401,1,target.snapshot().revision)
 check(target.transfer(0,1,1,target.snapshot().revision).ok and target.snapshot().slots[1].water_ml==1,"Two same-item carriers swap without losing distinct contents")
 check(loaded.drag_slots(9,target,false,true,1,3,1,target.snapshot().revision,loaded.snapshot(9).store_revision).ok and loaded.snapshot(9).slots[3].water_ml==1,"Exact-slot chest drag preserves water metadata")
 check(loaded.drag_slots(9,target,false,true,0,3,1,target.snapshot().revision,loaded.snapshot(9).store_revision).ok and target.snapshot().slots[0].water_ml==1 and loaded.snapshot(9).slots[3].water_ml==0,"Cross-container same-item swap keeps each carrier's contents")
 target.transfer(0,1,1,target.snapshot().revision)
 var saved:PackedByteArray=target.capture_storage_snapshot();var reopened=inventory()
 check(reopened.restore_storage_snapshot(saved) and reopened.capture_storage_snapshot()==saved,"Player quantity archive roundtrips exactly")
 for stride in [8,12]:
  var legacy:=PackedByteArray();legacy.resize(8+32*stride);legacy.fill(0)
  legacy.encode_u32(0,0x31564654 if stride==8 else 0x32564654);legacy.encode_u32(4,32)
  legacy.encode_u32(8,411);legacy.encode_u32(12,1)
  var old=inventory()
  check(old.restore_storage_snapshot(legacy) and old.snapshot().slots[0].water_ml==10000,"Old inventory retains ten litres, not one cubic metre (stride %d)"%stride)
  var chest:=PackedByteArray();chest.resize(24+legacy.size());chest.fill(0)
  chest.encode_u32(0,0x53434654);chest.encode_u32(4,1 if stride==8 else 2);chest.encode_u64(8,1);chest.encode_u64(16,7)
  for i in legacy.size():chest[24+i]=legacy[i]
  var prior=ClassDB.instantiate("NativeContainerStore");prior.configure(old,8)
  check(prior.restore_storage_snapshot(chest) and prior.snapshot(7).slots[0].water_ml==10000,"Old chest/dropped-stack archive preserves ten litres (stride %d)"%stride)
 var invalid:=saved.duplicate();invalid.encode_u32(20+16,1000001)
 before=reopened.snapshot()
 check(not reopened.restore_storage_snapshot(invalid) and reopened.snapshot()==before,"Invalid saved capacity rejects without mutation")
 var dictionary:Dictionary=reopened.snapshot();dictionary.slots[1].water_ml=-1
 check(not reopened.restore(dictionary,reopened.snapshot().revision).ok and reopened.snapshot()==before,"Negative dictionary quantity rejects without mutation")
 DirAccess.make_dir_recursive_absolute("res://reports")
 var file:=FileAccess.open("res://reports/water_inventory.json",FileAccess.WRITE)
 file.store_string(JSON.stringify({"failures":failures}));file.close()
 print("WATER_INVENTORY failures=",failures);quit(failures)
