# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,label: String)->void:
 print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
func _initialize()->void:run.call_deferred()
func run()->void:
 var game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;root.add_child(game)
 var deadline:=Time.get_ticks_msec()+45000
 while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
 check(not game.loading_active,"actual world ready")
 game.set_physics_process(false);game._clear_motion();game.app_focused=true
 game.structure_mode=true;game.model_tool.active=false;game.construction_inventory.gameplay=false
 game.player.position=Vector3(10,65,10)
 game.camera.global_position=Vector3(.5,65,4)
 game.camera.look_at(Vector3(.5,60.5,.5))
 game.structures.blocks.set_cells(PackedInt32Array([0,60,0,65]));game.structures.blocks.flush_bakes()
 game.structures.blocks.set_focus(Vector3(0,60,0))
 for i in 5:await physics_frame
 Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
 var hit: Dictionary=game._structure_target(false)
 check(not hit.is_empty(),"real camera ray targets the construction fixture")
 if not hit.is_empty():
  for i in game.structure_prefabs.size():
   if game.structure_prefabs[i].resource_name=="Timber footbridge with metal rails - 12 m span":game.structure_prefab_index=i;break
  var before: PackedByteArray=game.structures.capture_snapshot()
  var inventory: PackedByteArray=game.player_hud.inventory.capture_storage_snapshot()
  game._edit_structure(false)
  check(not game._foundation_placement.is_empty() and not game.construction_inventory.pending_prefab.is_empty(),"ordinary aimed placement starts native staging")
  check(game.structures.capture_snapshot()==before,"input handler does not publish blocks or models")
  game.structure_rotation=1
  game._advance_frontage_placement()
  check(game._foundation_placement.is_empty() and game.construction_inventory.pending_prefab.is_empty(),"changing rotation cancels staged placement")
  check(game.structures.capture_snapshot()==before and game.player_hud.inventory.capture_storage_snapshot()==inventory,"cancel preserves world and inventory")
  game.structure_rotation=0
  game._edit_structure(false)
  var slices:=0
  while not game._foundation_placement.is_empty() and slices<120:
   game._advance_frontage_placement();slices+=1
   await process_frame
  check(game._foundation_placement.is_empty() and game.construction_inventory.pending_prefab.is_empty(),"bounded preparation completes")
  check(game.structures.blocks.get_cell(hit.target)==33,"staged publication installs bridge deck at aimed cell")
  var rails=game.structures.model_collections()["architecture/metal_guardrail/v1"]
  check(rails.get_ids().size()==6,"same publication installs all six batched rails")
  print("DIRECT_PREFAB_SLICES ",slices)
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free()
 await process_frame
 print("DIRECT_PREFAB_STAGING failures=",failures);quit(1 if failures else 0)
