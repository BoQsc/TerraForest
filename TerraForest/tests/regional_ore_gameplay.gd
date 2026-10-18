# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
func run()->void:
 if "--snapshot-readonly" not in OS.get_cmdline_user_args():quit(2);return
 game=load("res://demo/world.tscn").instantiate();game.max_fps=60;game.background_fps=60;root.add_child(game)
 if not check(await wait_for(func():return not game.loading_active,60),"integrated saved world loads"):await finish();return
 game.set_physics_process(false);game._clear_motion()
 var generator:int=game.terrain.backend.world_generator;var seed:int=game.terrain.backend.world_seed
 if not check(generator in [12,13] and game.construction_inventory.gameplay,"regional mining gameplay"):await finish();return
 var folder:="res://reports/regional_ore_survey"+("_%d"%seed if seed!=1703 else "")+("_g%d"%generator if generator!=12 else "")
 var candidates:Dictionary=FileAccess.open(folder+"/candidates.bin",FileAccess.READ).get_var()
 for material in [8,9]:
  var surface:Vector3=candidates[material].surface
  game.teleport(surface+Vector3(0,0.15,1.2))
  if not check(await wait_for(func():return not game.loading_active,45),"chamber collision ready"):break
  game.set_physics_process(false);aim(surface+Vector3(0,0.15,1.2),surface)
  game.headlamp.visible=true;game.player_hud.equip(0)
  for frame in 30:await process_frame
  var before:Dictionary={}
  for item in [201,202,203,211]:before[item]=amount(item)
  var wear:int=game.player_hud.inventory.snapshot().slots[0].wear
  var target:Dictionary=game.world_attack.target()
  if not check(target.get("kind")=="terrain","pickaxe targets chamber floor"):break
  game.world_attack.next_attack=0
  if not check(game.world_attack.attack(),"normal pickaxe attack accepted"):break
  if not check(await wait_for(func():return not game.terrain.pending_edit,20),"mining publishes"):break
  var removed:PackedInt64Array=game.terrain.last_edit_outcome.get("removed_samples",PackedInt64Array())
  check(removed.size()==16 and removed[material]>0,"natural ore removed: %d"%material)
  if removed.size()==16:
   for pair in [[201,removed[0]+removed[1]],[202,removed[8]],[203,removed[9]],[211,removed[10]]]:
    check(amount(pair[0])-before[pair[0]]==pair[1],"inventory equals removed material: %d"%pair[0])
  check(game.player_hud.inventory.snapshot().slots[0].wear>wear,"pickaxe wears normally")
  check(game.player_hud.reward_inbox.get_pending().is_empty(),"rewards delivered directly")
  print("REGIONAL_MINED material=",material," removed=",removed," target=",target.get("point"))
  for frame in 30:await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png(folder+"/mined_%d.png"%material)
 check(preload("res://addons/presentation/fullscreen_policy.gd").measurement(root).fair_graphical_sample,"1920x1080 fullscreen")
 await finish()
func finish()->void:
 game.shutdown_requested=true
 check(await game.terrain.shutdown_after_edits(),"pending terrain edits drained; read-only session does not save")
 game.free();await process_frame
 print("REGIONAL_ORE_GAMEPLAY failures=",failures)
 quit(1 if failures else 0)
