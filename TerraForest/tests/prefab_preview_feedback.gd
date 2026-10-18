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
  var plain: Resource=ClassDB.instantiate("NativeBlockPrefab")
  plain.configure(PackedInt32Array([0,0,0,33]))
  var attached: Resource=preload("res://addons/structures/bridge_catalog.gd").footbridge(true)
  var before: PackedByteArray=game.structures.capture_snapshot()
  game.structure_prefabs.append(plain);game.structure_prefab_index=game.structure_prefabs.size()-1
  game._invalidate_prefab_preview();game._update_prefab_preview(1)
  check(game.prefab_preview.visible and game._prefab_preview_material.albedo_color==Color("66f2b3"),"clear block-only prefab shows green")
  game.structure_prefabs.append(attached);game.structure_prefab_index=game.structure_prefabs.size()-1
  game._invalidate_prefab_preview();game._update_prefab_preview(1)
  check(game.prefab_preview.visible and game._prefab_preview_material.albedo_color==Color("edc66a"),"furnished prefab shows amber for deferred attachment checks")
  check(before==game.structures.capture_snapshot(),"preview checks do not change blocks or models")
  game.player_hud.developer_slot=3
  game.session_menu.developer_hud.displayed_slot=-1;game.session_menu.developer_hud.refresh()
  await process_frame
  await RenderingServer.frame_post_draw
  var panel: Control=game.session_menu.developer_hud.panel
  check(panel.visible and panel.get_global_rect().end.y<1080,"construction legend fits the visible developer panel")
  root.get_texture().get_image().save_png("res://reports/prefab_preview_feedback.png")
  game.player.position=Vector3(hit.target)+Vector3(0,1,2)
  game.camera.global_position=Vector3(.5,65,4);game.camera.look_at(Vector3(.5,60.5,.5))
  game._update_prefab_preview(1)
  check(game._prefab_preview_material.albedo_color==Color("ff705f"),"player overlap overrides amber with blocked red")
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free()
 await process_frame
 print("PREFAB_PREVIEW_FEEDBACK failures=",failures);quit(1 if failures else 0)
