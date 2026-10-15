# SPDX-License-Identifier: 0BSD
extends "res://tests/world_browser_route.gd"
func inspect_world(reopen: bool)->void:
 var bridge: Resource
 for asset: Resource in game.structure_prefabs:
  if asset.resource_name=="Timber footbridge · 12 m span":bridge=asset;break
 if not check(bridge!=null,"main-world construction palette includes footbridge"):return
 var path:=report.path_join("bridge.bin")
 if not reopen:
  var origin:=Vector3i(game.player.position.floor())+Vector3i(30,40,0)
  var inventory=game.player_hud.inventory
  var before: PackedByteArray=game.structures.blocks.capture_snapshot()
  var items: PackedByteArray=inventory.capture_storage_snapshot()
  check(not game.construction_inventory.place_prefab(game.structures.blocks,inventory,bridge,origin,1),"insufficient gameplay wood rejects complete bridge")
  check(before==game.structures.blocks.capture_snapshot() and items==inventory.capture_storage_snapshot(),"rejected bridge changes neither world nor inventory")
  check(inventory.grant(102,35,inventory.snapshot().revision).ok,"fixture provides remaining earned-material equivalent")
  check(game.construction_inventory.place_prefab(game.structures.blocks,inventory,bridge,origin,1),"actual world accepts paid quarter-turned bridge")
  var file:=FileAccess.open(path,FileAccess.WRITE);file.store_var(game.structures.blocks.capture_snapshot());file.close()
 else:
  check(game.structures.blocks.capture_snapshot()==FileAccess.open(path,FileAccess.READ).get_var(),"fresh process restores exact bridge blocks and rotation")
