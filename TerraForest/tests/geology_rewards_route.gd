# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
func run()->void:
 var slot:=""
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--route-evidence="):evidence=arg.trim_prefix("--route-evidence=")
  if arg.begins_with("--world-slot="):slot=arg.trim_prefix("--world-slot=")
 if evidence.is_empty() or not slot.begins_with("geology_route_"):quit(2);return
 game=load("res://demo/world.tscn").instantiate();game.max_fps=60;game.background_fps=60;root.add_child(game)
 if not check(await wait_for(func():return not game.loading_active,60),"copied geology world opens"):await finish();return
 game.set_physics_process(false);game._clear_motion()
 check(game.construction_inventory.gameplay and not game.session_menu.developer,"normal mining gameplay active")
 if "--reopen-route" in OS.get_cmdline_user_args():
  var expected:Dictionary=FileAccess.open(evidence,FileAccess.READ).get_var()
  check(game.player_hud.inventory.capture_storage_snapshot()==expected.inventory,"mined ore and tool wear restore exactly")
  check(game.structures.blocks.get_cell(expected.cell)==expected.word,"crafted metal placement restores exactly")
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
    if target.is_empty():
     var start:Vector3=game.camera.global_position
     var end:Vector3=start-game.camera.global_basis.z*8.0
     var long_hit:Dictionary=game.structures.blocks.raycast_scene(start,end,3,[game.player.get_rid()])
     var replies:Array=[]
     var receive:=func(result:Dictionary):
      if result.get("token")==9001:replies.append(result)
     game.terrain.density_ray_received.connect(receive)
     game.terrain.request_density_ray(start,end,9001)
     await wait_for(func():return not replies.is_empty(),5)
     game.terrain.density_ray_received.disconnect(receive)
     print("ORE_TARGET_DIAGNOSTIC ",JSON.stringify({"start":start,"long_physics":long_hit,"native":replies,"retry":game.world_attack.target(),"previous":rows}))
     if not long_hit.is_empty() and not replies.is_empty() and replies[0].get("status")=="hit" and start.distance_to(long_hit.position)>3.5 and start.distance_to(replies[0].position)>3.5:
      var destination:float=game.player.position.x+0.9
      game.yaw=-PI/2;game.player.rotation.y=game.yaw
      game.pitch=0;game.camera.rotation=Vector3.ZERO
      game.set_physics_process(true)
      var deadline:int=Time.get_ticks_msec()+2000
      while game.player.position.x<destination and Time.get_ticks_msec()<deadline:
       game.app_focused=true;game.controls.set_key(KEY_W,true,Time.get_ticks_usec());await physics_frame
      game.controls.clear(Time.get_ticks_usec());game.set_physics_process(false)
      check(game.player.position.x>=destination,"walk closer to excavated face using normal collision")
      game.camera.look_at(ore+Vector3(0.5,0,0))
      target=game.world_attack.target()
    if not check(target.get("kind")=="terrain","pickaxe targets actual ore-face terrain"):break
    game.world_attack.next_attack=0
    if not check(await preload("res://tests/swing_driver.gd").strike(game),"ordinary pickaxe attack accepted"):break
    if not check(await wait_for(func():return not game.terrain.pending_edit,15),"mining publishes"):break
    rows.append({"item":item,"strike":strike,"target":target,"outcome":game.terrain.last_edit_outcome,"quantity":amount(item)})
    if amount(item)>=before+2:break
   check(amount(item)>=before+2,"two ore %d enter inventory directly"%item)
   check(game.player_hud.inventory.snapshot().slots[0].wear>wear,"successful mining wears pickaxe")
   check(game.player_hud.reward_inbox.get_pending().is_empty(),"no unclaimed materials with available inventory room")
   await RenderingServer.frame_post_draw
   root.get_texture().get_image().save_png(evidence+".%d.png"%item)
  if not check(amount(202)>=2 and amount(203)>=2,"earned ores cover both metal recipes"):await finish();return
  var iron_before:int=amount(202);var copper_before:int=amount(203);var metal_before:int=amount(104)
  game.player_hud.set_open(true)
  game.player_hud.recipe_buttons[2].pressed.emit();game.player_hud.recipe_buttons[3].pressed.emit()
  check(amount(202)==iron_before-2 and amount(203)==copper_before-2 and amount(104)==metal_before+2,"crafting buttons consume earned ores for two metal blocks")
  game.player_hud.drop_stack("player",9,game.player_hud.drag_data("player",slot_of(104)))
  game.player_hud.set_open(false);game.player_hud.equip(9)
  game.camera.look_at(game.player.position+Vector3(-1.5,-2.0,0))
  var hit:Dictionary=game._structure_target(false)
  if not check(not hit.is_empty(),"crafted metal targets tunnel floor"):await finish();return
  var cell:Vector3i=hit.target
  var click:=InputEventMouseButton.new();click.pressed=true;click.button_index=MOUSE_BUTTON_RIGHT
  game._unhandled_input(click)
  var word:int=game.structures.blocks.get_cell(cell)
  check(amount(104)==metal_before+1 and word!=0 and ((word>>5)&3)==3,"right click consumes one crafted metal block and places metal")
  game.player_hud.equip(8)
  for frame in 60:await physics_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png(evidence+".built.png")
  var file:=FileAccess.open(evidence,FileAccess.WRITE)
  file.store_var({"inventory":game.player_hud.inventory.capture_storage_snapshot(),"iron":amount(202),"copper":amount(203),"cell":cell,"word":word});file.close()
  file=FileAccess.open(evidence+".json",FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failures,"strikes":rows},"  "));file.close()
 await finish()
