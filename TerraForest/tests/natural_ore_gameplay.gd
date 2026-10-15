# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
var responses:Array[Dictionary]=[]
var token:=8100
var walking:bool=false
var walk_rows:Array=[]
func walk_to(point:Vector3)->bool:
 game.set_physics_process(true);Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
 var began:=Time.get_ticks_msec();var tick:=0
 while Time.get_ticks_msec()-began<30000:
  var direction:Vector3=point-game.player.position;direction.y=0
  if direction.length()<0.25:break
  game.yaw=atan2(-direction.x,-direction.z);game.player.rotation.y=game.yaw
  game.camera.rotation=Vector3(-0.12,0,0);game.app_focused=true
  game.controls.set_key(KEY_W,true,Time.get_ticks_usec())
  await physics_frame;tick+=1
  if tick%15==0:walk_rows.append({"position":game.player.position,"floor":game.player.is_on_floor(),"loading":game.loading_active})
 game.controls.clear(Time.get_ticks_usec());game.set_physics_process(false)
 var remaining:Vector3=point-game.player.position;remaining.y=0
 print("CAVE_WALK ",JSON.stringify({"target":point,"finish":game.player.position,"remaining":remaining.length(),"milliseconds":Time.get_ticks_msec()-began}))
 return remaining.length()<0.4 and game.player.is_on_floor() and not game.fly
func densities(points:PackedVector3Array)->PackedFloat32Array:
 responses.clear();token+=1
 if not check(game.terrain.request_density_batch(points,token),"authoritative density query accepted"):return PackedFloat32Array()
 if not check(await wait_for(func():return not responses.is_empty(),15),"density query completes"):return PackedFloat32Array()
 if not check(responses[0].status=="ok" and responses[0].values.size()==points.size(),"density query matches current terrain"):return PackedFloat32Array()
 return responses[0].values
func run()->void:
 var slot:=""
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--route-evidence="):evidence=arg.trim_prefix("--route-evidence=")
  if arg.begins_with("--world-slot="):slot=arg.trim_prefix("--world-slot=")
 if evidence.is_empty() or not slot.begins_with("natural_ore_"):quit(2);return
 walking="--walk-iron" in OS.get_cmdline_user_args()
 game=load("res://demo/world.tscn").instantiate();game.max_fps=60;game.background_fps=60;root.add_child(game)
 if not check(await wait_for(func():return not game.loading_active,90),"copied natural cave world loads"):await finish();return
 game.set_physics_process(false);game._clear_motion()
 game.terrain.density_batch_ready.connect(func(result:Dictionary):
  if result.get("token")==token:responses.append(result))
 if not check(game.terrain.backend.world_generator==6 and game.terrain.backend.world_seed==1703 and game.construction_inventory.gameplay,"generator6 seed1703 ordinary mining gameplay"):await finish();return
 if "--reopen-route" in OS.get_cmdline_user_args():
  var expected:Dictionary=FileAccess.open(evidence,FileAccess.READ).get_var()
  check(game.player_hud.inventory.capture_storage_snapshot()==expected.inventory,"exact mined inventory and tool wear restore")
  for row:Dictionary in expected.rows:
   var restored:PackedFloat32Array=await densities(row.points)
   check(restored==row.after,"excavated density samples restore exactly for ore %d"%row.material)
  check(game.player_hud.reward_inbox.get_pending().is_empty(),"no pending or duplicate rewards after reopening")
 else:
  var candidates:Dictionary=FileAccess.open("res://reports/natural_ore_survey/candidates.bin",FileAccess.READ).get_var()
  var rows:Array=[]
  var materials:Array=[8] if walking else [8,9]
  var route:Dictionary={}
  if walking:
   route=preload("res://demo/cave_checkpoint.gd").route()
   if not check(not route.is_empty() and game.player.position.distance_to(route.points[0])<0.5 and not game.fly,"start at saved cave entrance without relocation"):await finish();return
  for material in materials:
   var surface:Vector3=candidates[material].surface
   if walking:
    game.headlamp.visible=true
    var along:float=(surface-route.points[0]).dot(route.direction)
    var center:Vector3=route.points[0]+route.direction*along
    if not check(await walk_to(center),"walk entrance corridor using ordinary player collision"):break
    if not check(await walk_to(surface+Vector3(0,0,1.2)),"walk from corridor to natural ore"):break
    game.camera.look_at(surface)
   else:
    aim(surface+Vector3(0,0.15,1.2),surface)
    game.terrain.focus=game.player.position;game._begin_loading("Preparing natural ore collision")
    if not check(await wait_for(func():return not game.loading_active,60),"natural ore collision arrives"):break
    for frame in 3:await physics_frame
    var ray:=PhysicsRayQueryParameters3D.create(surface+Vector3(0,3,1.2),surface+Vector3(0,-3,1.2),1)
    var floor_hit:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(ray)
    if not check(not floor_hit.is_empty(),"nearby natural floor supports mining viewpoint"):break
    aim(floor_hit.position+Vector3.UP*0.05,surface)
   game.headlamp.visible=true;game.player_hud.equip(0)
   var points:=PackedVector3Array()
   for x in [-0.4,0.0,0.4]:
    for y in [-0.6,-0.3,0.0]:
     for z in [-0.4,0.0,0.4]:points.append(surface+Vector3(x,y,z))
   var before:PackedFloat32Array=await densities(points)
   var counts_before:Dictionary={}
   for item in [201,202,203,211]:counts_before[item]=amount(item)
   var wear:int=game.player_hud.inventory.snapshot().slots[0].wear
   var target:Dictionary=game.world_attack.target()
   if not check(target.get("kind")=="terrain","ordinary pickaxe targets natural cave floor"):break
   game.world_attack.next_attack=0
   if not check(game.world_attack.attack(),"ordinary pickaxe strike accepted"):break
   if not check(await wait_for(func():return not game.terrain.pending_edit,20),"excavation publishes"):break
   var after:PackedFloat32Array=await densities(points)
   var removed:PackedInt64Array=game.terrain.last_edit_outcome.get("removed_samples",PackedInt64Array())
   check(removed.size()==16 and removed[material]>0,"strike actually removes natural ore %d"%material)
   if removed.size()==16:
    for pair in [[201,removed[0]+removed[1]],[202,removed[8]],[203,removed[9]],[211,removed[10]]]:
     check(amount(pair[0])-counts_before[pair[0]]==pair[1],"inventory reward equals removed material %d"%pair[0])
   check(before.size()==27 and after.size()==27 and before!=after,"mining changes sampled authoritative terrain")
   check(game.player_hud.inventory.snapshot().slots[0].wear>wear,"pickaxe wears through ordinary attack")
   check(game.player_hud.reward_inbox.get_pending().is_empty(),"ore delivered directly to inventory")
   rows.append({"material":material,"points":points,"before":before,"after":after,"removed":removed,"target":target.get("point",surface)})
   await RenderingServer.frame_post_draw
   root.get_texture().get_image().save_png(evidence+".%d.png"%material)
  check(rows.size()==materials.size(),"requested natural ore cases completed")
  var file:=FileAccess.open(evidence,FileAccess.WRITE);file.store_var({"inventory":game.player_hud.inventory.capture_storage_snapshot(),"rows":rows});file.close()
  file=FileAccess.open(evidence+".json",FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failures,"rows":rows,"walk":walk_rows},"  "));file.close()
 check(preload("res://addons/presentation/fullscreen_policy.gd").measurement(root).fair_graphical_sample,"1920x1080 fullscreen full render scale")
 await finish()
