# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
func run()->void:
 var slot:=""
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--route-evidence="):evidence=arg.trim_prefix("--route-evidence=")
  if arg.begins_with("--world-slot="):slot=arg.trim_prefix("--world-slot=")
 if evidence.is_empty() or not slot.begins_with("geology_route_"):quit(2);return
 game=load("res://demo/world.tscn").instantiate();root.add_child(game)
 if not check(await wait_for(func():return not game.loading_active,60),"copied geology world opens"):await finish();return
 game.set_physics_process(false);game._clear_motion()
 check(game.construction_inventory.gameplay and not game.session_menu.developer,"normal mining gameplay active")
 if "--reopen-route" in OS.get_cmdline_user_args():
  var expected:Dictionary=FileAccess.open(evidence,FileAccess.READ).get_var()
  check(game.player_hud.inventory.capture_storage_snapshot()==expected.inventory,"mined ore and tool wear restore exactly")
  check(amount(202)==expected.iron and amount(203)==expected.copper,"both ore quantities survive fresh reopen")
 else:
  var rows:Array=[]
  for pair in [[202,Vector3(364,113,368)],[203,Vector3(368,109,332)]]:
   var item:int=pair[0];var ore:Vector3=pair[1]
   aim(ore-Vector3(3,2,0),ore)
   game.terrain.focus=game.player.position;game._begin_loading("Preparing ore face")
   if not check(await wait_for(func():return not game.loading_active,40),"ore collision arrives"):break
   game.headlamp.visible=true;game.player_hud.equip(0)
   for frame in 5:await physics_frame
   var before:int=amount(item);var wear:int=game.player_hud.inventory.snapshot().slots[0].wear
   for strike in 8:
    var target:Dictionary=game.world_attack.target()
    if not check(target.get("kind")=="terrain","pickaxe targets actual ore-face terrain"):break
    game.world_attack.next_attack=0
    if not check(game.world_attack.attack(),"ordinary pickaxe attack accepted"):break
    if not check(await wait_for(func():return not game.terrain.pending_edit,15),"mining publishes"):break
    rows.append({"item":item,"strike":strike,"target":target,"outcome":game.terrain.last_edit_outcome,"quantity":amount(item)})
    if amount(item)>before:break
   check(amount(item)>before,"ore %d enters inventory directly"%item)
   check(game.player_hud.inventory.snapshot().slots[0].wear>wear,"successful mining wears pickaxe")
   check(game.player_hud.reward_inbox.get_pending().is_empty(),"no unclaimed materials with available inventory room")
   await RenderingServer.frame_post_draw
   root.get_texture().get_image().save_png(evidence+".%d.png"%item)
  var file:=FileAccess.open(evidence,FileAccess.WRITE)
  file.store_var({"inventory":game.player_hud.inventory.capture_storage_snapshot(),"iron":amount(202),"copper":amount(203)});file.close()
  file=FileAccess.open(evidence+".json",FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failures,"strikes":rows},"  "));file.close()
 await finish()
