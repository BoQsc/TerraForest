# SPDX-License-Identifier: 0BSD
extends "res://tests/world_browser_route.gd"
func finish_preparation()->void:
 for i in 120:
  if game._foundation_placement.is_empty():break
  game._advance_frontage_placement()
  await process_frame
 check(game._foundation_placement.is_empty() and game.construction_inventory.pending_prefab.is_empty(),"staged placement reaches terminal state")
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
  game.structure_mode=true;game.model_tool.active=false;game.app_focused=true
  game.structure_prefab_index=game.structure_prefabs.find(bridge);game.structure_rotation=1
  game._begin_direct_prefab(bridge,origin)
  check(not game._foundation_placement.is_empty(),"paid world starts staged direct placement")
  await finish_preparation()
  check(game.construction_inventory.reason=="Missing construction materials","insufficient materials reject complete bridge")
  check(before==game.structures.capture_snapshot() and items==inventory.capture_storage_snapshot(),"rejection preserves all blocks models and inventory")
  check(inventory.grant(102,56,inventory.snapshot().revision).ok and inventory.grant(104,24,inventory.snapshot().revision).ok,"fixture funds wood and railing recipe")
  game._begin_direct_prefab(bridge,origin)
  check(inventory.grant(201,1,inventory.snapshot().revision).ok,"inventory changes while placement is staged")
  var changed_items: PackedByteArray=inventory.capture_storage_snapshot()
  await finish_preparation()
  check(game.structures.capture_snapshot()==before and inventory.capture_storage_snapshot()==changed_items,"inventory revision conflict cancels without world edits or lost items")
  var wood_before:=0;var metal_before:=0
  for stack: Dictionary in inventory.snapshot().slots:
   if stack.item==102:wood_before+=int(stack.count)
   if stack.item==104:metal_before+=int(stack.count)
  game._begin_direct_prefab(bridge,origin)
  check(inventory.capture_storage_snapshot()==changed_items,"starting placement does not debit materials")
  await finish_preparation()
  var wood_after:=0;var metal_after:=0
  for stack: Dictionary in inventory.snapshot().slots:
   if stack.item==102:wood_after+=int(stack.count)
   if stack.item==104:metal_after+=int(stack.count)
  check(wood_before-wood_after==56 and metal_before-metal_after==24,"staged publication charges exactly 56 wood and 24 metal")
  check(game.structures.blocks.get_cell(origin)==41 and game.structures.model_collections()["architecture/metal_guardrail/v1"].get_ids().size()==6,"actual world publishes rotated bridge and all railings")
  FileAccess.open(path,FileAccess.WRITE).store_var(game.structures.capture_snapshot())
 else:
  check(game.structures.capture_snapshot()==FileAccess.open(path,FileAccess.READ).get_var(),"fresh process restores exact bridge blocks and batched rails")
