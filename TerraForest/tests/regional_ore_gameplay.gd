# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
var profile_phase:="startup"
var profile_rows:Array=[]
var profile_stages:Dictionary={}
var profile_previous:=0
var capture_timings:Array=[]
func profile_frame()->void:
 var now:=Time.get_ticks_usec()
 if profile_previous>0:
  profile_rows.append({"phase":profile_phase,"frame_ms":(now-profile_previous)/1000.0,"cap":Engine.max_fps,"gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()),"render_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()),"engine_process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000,"engine_physics_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000,"terrain_queued":game.terrain.backend.queued(),"terrain_worker":game.terrain.backend.status(),"water_us":game.lakes.last_process_us,"ground_us":game.ground_cover.last_process_us,"forest_us":game.vegetation.last_process_us,"stages":profile_stages.duplicate()})
 profile_previous=now;profile_stages.clear()
func run()->void:
 if "--snapshot-readonly" not in OS.get_cmdline_user_args():quit(2);return
 game=load("res://demo/world.tscn").instantiate();game.max_fps=60;game.background_fps=60;root.add_child(game)
 if "--ore-profile" in OS.get_cmdline_user_args():
  RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
  game.terrain.stage_measured.connect(func(label:String,ms:float):profile_stages[label]=maxf(profile_stages.get(label,0),ms))
  process_frame.connect(profile_frame)
 if not check(await wait_for(func():return not game.loading_active,60),"integrated saved world loads"):await finish();return
 game.set_physics_process(false);game._clear_motion()
 var generator:int=game.terrain.backend.world_generator;var seed:int=game.terrain.backend.world_seed
 if not check(generator in [12,13] and game.construction_inventory.gameplay,"regional mining gameplay"):await finish();return
 var folder:="res://reports/regional_ore_survey"+("_%d"%seed if seed!=1703 else "")+("_g%d"%generator if generator!=12 else "")
 var candidates:Dictionary=FileAccess.open(folder+"/candidates.bin",FileAccess.READ).get_var()
 for material in [8,9]:
  profile_phase="travel_%d"%material
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
  profile_phase="strike_%d"%material
  if not check(game.world_attack.attack(),"normal pickaxe attack accepted"):break
  if not check(await wait_for(func():return not game.terrain.pending_edit,20),"mining publishes"):break
  var removed:PackedInt64Array=game.terrain.last_edit_outcome.get("removed_samples",PackedInt64Array())
  check(removed.size()==16 and removed[material]>0,"natural ore removed: %d"%material)
  if removed.size()==16:
   for pair in [[201,removed[0]+removed[1]],[202,removed[8]],[203,removed[9]],[211,removed[10]]]:
    check(amount(pair[0])-before[pair[0]]==pair[1],"inventory equals removed material: %d"%pair[0])
  check(game.player_hud.inventory.snapshot().slots[0].wear>wear,"pickaxe wears normally")
  check(game.player_hud.reward_inbox.get_pending().is_empty(),"rewards delivered directly")
  profile_phase="settle_%d"%material
  print("REGIONAL_MINED material=",material," removed=",removed," target=",target.get("point"))
  for frame in 30:await process_frame
  # Readback/PNG compression stalls the main thread and contaminates subsequent
  # frame intervals and the HUD's rolling FPS. Keep visual and timing runs separate.
  var capture_enabled:bool="--ore-no-capture" not in OS.get_cmdline_user_args() and ("--ore-profile" not in OS.get_cmdline_user_args() or "--ore-capture-with-profile" in OS.get_cmdline_user_args())
  if capture_enabled:
   await RenderingServer.frame_post_draw
   var capture_started:=Time.get_ticks_usec()
   root.get_texture().get_image().save_png(folder+"/mined_%d.png"%material)
   capture_timings.append({"material":material,"capture_ms":(Time.get_ticks_usec()-capture_started)/1000.0})
 check(preload("res://addons/presentation/fullscreen_policy.gd").measurement(root).fair_graphical_sample,"1920x1080 fullscreen")
 await finish()
func finish()->void:
 if process_frame.is_connected(profile_frame):
  process_frame.disconnect(profile_frame)
  var file:=FileAccess.open("res://reports/regional_ore_profile.json",FileAccess.WRITE);file.store_string(JSON.stringify(profile_rows));file.close()
  file=FileAccess.open("res://reports/regional_ore_captures.json",FileAccess.WRITE);file.store_string(JSON.stringify(capture_timings));file.close()
 game.shutdown_requested=true
 check(await game.terrain.shutdown_after_edits(),"pending terrain edits drained; read-only session does not save")
 game.free();await process_frame
 print("REGIONAL_ORE_GAMEPLAY failures=",failures)
 quit(1 if failures else 0)
