# SPDX-License-Identifier: 0BSD
extends SceneTree
const Persistence=preload("res://addons/world_runtime/world_persistence.gd")
const Pickups=preload("res://addons/world_runtime/material_pickups.gd")
var failures:=0
func check(ok:bool,label:String)->void:
 if not ok:failures+=1
 print("PASS " if ok else "FAIL ",label)
func _initialize()->void:run.call_deferred()
func run()->void:
 GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
 var store=ClassDB.instantiate("NativeEntityStore");store.configure(1)
 var provider=Persistence.new()
 check(provider.register_component("pickups_401",store.capture_storage_snapshot,store.restore_storage_snapshot,store,store.capture_storage_snapshot()),"existing host provider registers")
 var before:Dictionary=provider._capture().sections
 var pickups=Pickups.new();root.add_child(pickups)
 for attempt in 2:
  check(not pickups.prepare(provider),"late registration conflict rejects attempt %d"%attempt)
  check(pickups.stores.is_empty() and pickups.stacks.is_empty() and pickups.renderers.is_empty() and pickups.get_child_count()==0,"failed prepare publishes no state or scene nodes")
  check(provider._capture().sections==before,"failed prepare preserves existing host registry exactly")
 var clean=Persistence.new()
 check(pickups.prepare(clean),"same adapter can retry against valid host")
 check(clean._providers.size()==Pickups.ITEMS.size()*2 and pickups.get_child_count()==Pickups.ITEMS.size(),"complete store and renderer set publishes together")
 check(pickups.prepare(clean) and pickups.get_child_count()==Pickups.ITEMS.size(),"same-host preparation is idempotent")
 check(not pickups.prepare(provider),"initialized adapter cannot pretend to register with another host")
 var entry:Dictionary={"name":"extra","capture":store.capture_storage_snapshot,"restore":store.restore_storage_snapshot,"validator":store,"empty":store.capture_storage_snapshot()}
 check(not provider.register_components([entry,entry]) and provider._capture().sections==before,"duplicate names within batch leave registry unchanged")
 var invalid:Dictionary=entry.duplicate();invalid.name="invalid";invalid.empty=PackedByteArray([0])
 check(not provider.register_components([entry,invalid]) and provider._capture().sections==before,"invalid late snapshot leaves earlier valid entry unpublished")
 pickups.free();await process_frame
 print("PICKUP_INITIALIZATION failures=",failures);quit(1 if failures else 0)
