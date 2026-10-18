# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
const Supplies=preload("res://addons/world_runtime/settlement_supplies.gd")
func run()->void:
 if "--snapshot-readonly" not in OS.get_cmdline_user_args():quit(2);return
 game=load("res://demo/world.tscn").instantiate();game.max_fps=60;game.background_fps=60;root.add_child(game)
 if not check(await wait_for(func():return not game.loading_active,60),"integrated world loads"):
  print("SUPPLIES_LOAD_STATE ",game.terrain.loading_state(game.player.position,game.fly)," label=",game.loading_label.text," player=",game.player.position)
  await finish();return
 game.set_physics_process(false)
 var player_before:PackedByteArray=game.player_hud.inventory.capture_storage_snapshot()
 if game.storage.store.get_ids().is_empty():
  var empty:PackedByteArray=game.storage.store.capture_storage_snapshot()
  var result:Dictionary=Supplies.populate(game)
  if not check(result.ok,"offline supplies populated"):await finish();return
  var first:PackedByteArray=game.storage.store.capture_storage_snapshot()
  for id:int in game.storage.collection.get_ids():game.storage.collection.set_removal_protected(id,false)
  game.storage.store.restore_storage_snapshot(empty)
  check(Supplies.populate(game).ok and game.storage.store.capture_storage_snapshot()==first,"same seed and identities produce identical supply contents")
 var bytes:PackedByteArray=game.storage.store.capture_storage_snapshot()
 check(not Supplies.populate(game).ok and game.storage.store.capture_storage_snapshot()==bytes,"repeat preparation refuses without overwriting contents")
 check(game.player_hud.inventory.capture_storage_snapshot()==player_before,"stocking never changes player inventory")
 var ids:PackedInt64Array=game.storage.collection.get_ids()
 check(ids.size()>20 and game.storage.store.get_ids().size()==ids.size(),"every generated chest contains saved supplies")
 for id:int in ids:
  check(game.storage.collection.is_removal_protected(id),"stocked chest protected: %d"%id)
 var id:int=ids[0]
 var before:Dictionary=game.storage.store.snapshot(id)
 var item:int=before.slots[0].item;var quantity:int=before.slots[0].count
 var owned:int=amount(item)
 var moved:Dictionary=game.storage.store.withdraw(id,game.player_hud.inventory,0,quantity,game.player_hud.inventory.snapshot().revision,before.store_revision)
 check(moved.ok and amount(item)==owned+quantity,"ordinary native withdrawal transfers generated supply")
 check(game.storage.store.restore_storage_snapshot(bytes) and game.storage.store.capture_storage_snapshot()==bytes,"supplies roundtrip exactly")
 await finish()
func finish()->void:
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame
 print("REGIONAL_SUPPLIES failures=",failures);quit(1 if failures else 0)
