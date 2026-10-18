# SPDX-License-Identifier: 0BSD
extends "res://tests/world_browser_route.gd"
func inspect_world(reopen: bool)->void:
 var bridge: Resource
 for asset: Resource in game.structure_prefabs:
  if asset.resource_name=="Timber footbridge with metal rails - 12 m span":bridge=asset;break
 if not check(bridge!=null,"main-world palette includes metal-railed bridge"):return
 var path:=report.path_join("bridge.bin")
 if not reopen:
  var origin:=Vector3i(game.player.position.floor())+Vector3i(30,40,0)
  var inventory=game.player_hud.inventory
  var metal:=0
  for stack: Dictionary in inventory.snapshot().slots:
   if stack.item==104:metal+=int(stack.count)
  if metal>0:check(inventory.consume_items(PackedInt64Array([104,metal]),inventory.snapshot().revision).ok,"remove fixture metal to test unaffordable bridge")
  var before: PackedByteArray=game.structures.capture_snapshot()
  var items: PackedByteArray=inventory.capture_storage_snapshot()
  var models: Dictionary=game.structures.model_collections()
  var recipes: Dictionary=preload("res://addons/structures/construction_catalog.gd").recipes()
  check(not game.construction_inventory.place_prefab(game.structures.blocks,inventory,bridge,origin,1,models,recipes,[]),"insufficient materials reject complete bridge")
  check(before==game.structures.capture_snapshot() and items==inventory.capture_storage_snapshot(),"rejection preserves all blocks models and inventory")
  check(inventory.grant(102,56,inventory.snapshot().revision).ok and inventory.grant(104,24,inventory.snapshot().revision).ok,"fixture funds wood and railing recipe")
  check(game.construction_inventory.place_prefab(game.structures.blocks,inventory,bridge,origin,1,models,recipes,[]),"actual world places rotated paid metal-railed bridge")
  print("Bridge placement reason: ",game.construction_inventory.reason)
  FileAccess.open(path,FileAccess.WRITE).store_var(game.structures.capture_snapshot())
 else:
  check(game.structures.capture_snapshot()==FileAccess.open(path,FileAccess.READ).get_var(),"fresh process restores exact bridge blocks and batched rails")
