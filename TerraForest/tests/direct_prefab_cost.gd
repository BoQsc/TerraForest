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
 game.set_process(false);game.set_physics_process(false);game._clear_motion();game.app_focused=true
 game.structure_mode=true;game.model_tool.active=false;game.construction_inventory.gameplay=false
 game.player.position=Vector3(2000,65,2000)
 Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
 var visibility: Dictionary={"changes":0}
 game.construction_palette.panel.visibility_changed.connect(func():visibility.changes+=1)
 var rows: Array=[]
 var maxima: Dictionary={}
 game.terrain.stage_measured.connect(func(label: String,ms: float):maxima[label]=maxf(float(maxima.get(label,0)),ms))
 for count in [4,64]:
  var base:=Vector3i(count*30,60,0)
  game.camera.global_position=Vector3(base)+Vector3(.5,5,4)
  game.camera.look_at(Vector3(base)+Vector3(.5,.5,.5))
  game.structures.blocks.set_cells(PackedInt32Array([base.x,base.y,base.z,65]));game.structures.blocks.flush_bakes()
  game.structures.blocks.set_focus(Vector3(base))
  for i in 5:await physics_frame
  var source: Resource=preload("res://addons/structures/furniture_catalog.gd").furnished_cottage()
  var asset: Resource=ClassDB.instantiate("NativeBlockPrefab")
  check(asset.compose_frontage([source],count/2,8,3,1703),"compose furnished population "+str(count))
  asset.resource_name="Placement cost fixture "+str(count)
  game.structure_prefabs.append(asset);game.structure_prefab_index=game.structure_prefabs.size()-1
  game.construction_palette.configure(game.structure_prefabs)
  var hit: Dictionary=game._structure_target(false)
  check(not hit.is_empty(),"real ray reaches population anchor")
  maxima.clear()
  var cells_before: int=game.structures.blocks.stats().cells
  var started:=Time.get_ticks_usec()
  game._edit_structure(false)
  var begin_us:=Time.get_ticks_usec()-started
  check(not game._foundation_placement.is_empty(),"population enters normal staged placement")
  var calls: Array=[];var frames: Array=[];var last_frame:=Time.get_ticks_usec()
  while not game._foundation_placement.is_empty() and calls.size()<300:
   started=Time.get_ticks_usec();game._advance_frontage_placement();calls.append(Time.get_ticks_usec()-started)
   await RenderingServer.frame_post_draw
   var now:=Time.get_ticks_usec();frames.append(now-last_frame);last_frame=now
  check(game._foundation_placement.is_empty() and game.construction_inventory.pending_prefab.is_empty(),"population finishes preparation")
  check(game.structures.blocks.stats().cells-cells_before==asset.get_cell_count(),"all population blocks published")
  var maximum: int=calls.max() if not calls.is_empty() else 0
  rows.append({"stages_ms":maxima.duplicate(),"cottages":count,"cells":asset.get_cell_count(),"attachments":asset.get_model_attachments().size(),"input_us":begin_us,"max_update_us":maximum,"calls_us":calls,"post_draw_intervals_us":frames})
  check(begin_us<=4000 and maximum<=4000,"world placement calls stay within 4 ms at "+str(count))
 check(visibility.changes==0,"placement notices do not toggle the docked construction panel")
 FileAccess.open("res://reports/direct_prefab_cost.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"rows":rows},"  "))
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame
 print("DIRECT_PREFAB_COST failures=",failures);quit(1 if failures else 0)
