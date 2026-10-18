# SPDX-License-Identifier: 0BSD
extends RefCounted
# Offline preparation only. No runtime callbacks and no replenishment of saves.
static func populate(game:Node)->Dictionary:
 var store=game.storage.store
 var collection=game.storage.collection
 if not store.get_ids().is_empty():return {"ok":false,"reason":"storage already populated"}
 var ids:PackedInt64Array=collection.get_ids()
 if ids.is_empty():return {"ok":false,"reason":"no generated chests"}
 var before:PackedByteArray=store.capture_storage_snapshot()
 var protected:Array[int]=[]
 var supply:RefCounted=ClassDB.instantiate("NativePlayerInventory")
 for item in [102,201,202,203,204]:supply.register_item(item,999)
 var rng:=RandomNumberGenerator.new();rng.seed=game.terrain.backend.world_seed
 # Stable placement identities give a deterministic traversal independent of
 # renderer residency. A fresh generator never uses the player's inventory.
 ids.sort()
 for id:int in ids:
  var records:PackedFloat32Array=collection.get_instance(id)
  var eastern:bool=records.size()>=12 and records[3]>1500
  var stock:Array=[[102,rng.randi_range(3,8)],[201,rng.randi_range(2,6)]]
  stock.append([202 if rng.randi_range(0,1)==0 else 203,rng.randi_range(1,3)] if eastern else [204,rng.randi_range(2,5)])
  if not collection.set_removal_protected(id,true):
   rollback(store,collection,before,protected);return {"ok":false,"reason":"chest unavailable"}
  protected.append(id)
  for row:Array in stock:
   var grant:Dictionary=supply.grant(row[0],row[1],supply.snapshot().revision)
   if not grant.ok:
    rollback(store,collection,before,protected);return {"ok":false,"reason":"supply rejected"}
   var slot:=-1
   var state:Dictionary=supply.snapshot()
   for i in state.slots.size():
    if state.slots[i].item==row[0]:slot=i;break
   var result:Dictionary=store.deposit(id,supply,slot,row[1],state.revision,store.snapshot(id).store_revision)
   if not result.ok:
    rollback(store,collection,before,protected);return {"ok":false,"reason":result.reason}
 game.terrain.changed_since_save=true
 return {"ok":true,"chests":ids.size(),"reason":"saved location supplies prepared"}
static func rollback(store:RefCounted,collection:Node3D,before:PackedByteArray,ids:Array[int])->void:
 store.restore_storage_snapshot(before)
 for id:int in ids:collection.set_removal_protected(id,false)
