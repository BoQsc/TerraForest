extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
const Deposits=preload("res://addons/world_runtime/material_deposits.gd")
var game:Node
var checks:=0
var failures:=0
var folder:="res://reports/material_deposits/world"
var timings:Array=[]
func _initialize()->void:run.call_deferred()
func check(condition:bool,title:String)->bool:
 checks+=1;print("PASS " if condition else "FAIL ",title)
 if not condition:failures+=1
 return condition
func wait_for(condition:Callable,seconds:float=60)->bool:
 var deadline:=Time.get_ticks_msec()+int(seconds*1000)
 while not condition.call() and Time.get_ticks_msec()<deadline:await process_frame
 return condition.call()
func photograph(label:String)->void:
 if DisplayServer.get_name()=="headless":return
 await RenderingServer.frame_post_draw
 check(root.get_texture().get_image().save_png(folder.path_join(label+".png"))==OK,"screenshot: "+label)
func count_item(item:int)->int:
 var count:=0
 for slot:Dictionary in game.player_hud.inventory.snapshot().slots:
  if slot.item==item:count+=int(slot.count)
 return count
func run()->void:
 for argument in OS.get_cmdline_user_args():
  if argument.begins_with("--mineral-evidence="):folder=argument.trim_prefix("--mineral-evidence=")
 folder=ProjectSettings.globalize_path(folder);DirAccess.make_dir_recursive_absolute(folder)
 game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;game.player_view.settings_path="";root.add_child(game)
 if not check(await wait_for(func():return not game.loading_active and not game.needs_floor_spawn),"temporary world loads"):await finish();return
 game.set_physics_process(false);game._clear_motion();game.app_focused=true;game.zombies.population_enabled=false;game.zombies.clear()
 var core=ClassDB.instantiate("TerrainCore");var seed_value:int=game.terrain.backend.world_seed;var generator:int=game.terrain.backend.world_generator
 core.execute(Codec.command(6,[seed_value,generator]))
 var plan:Dictionary=core.plan_material_deposits([])
 if not check(plan.get("ok",false) and not plan.deposits.is_empty(),"native deposit plan available"):await finish();return
 check(game.material_deposits.describe(seed_value,generator).is_empty(),"legacy/disabled world has no automatic surface deposits")
 if not check(game.material_deposits.publish(seed_value,generator,plan.deposits,game.structures),"exact native plan publishes into real model storage"):await finish();return
 check(not game.material_deposits.publish(seed_value,generator,plan.deposits,game.structures),"duplicate generation cannot resurrect mined stones")
 var saved_metadata:PackedByteArray=game.material_deposits.store.capture_snapshot()
 var saved_damage:PackedByteArray
 for material in [8,9]:
  var candidates:Array=plan.deposits.filter(func(value):return value.material==material)
  var deposit:Dictionary=candidates[0]
  var collection:Node3D=game.structures.model(Deposits.KEYS[material])
  game.teleport(deposit.position+Vector3(2,2,2))
  if not check(await wait_for(func():return not game.loading_active and game.structures.is_collision_region_ready(AABB(deposit.position-Vector3.ONE*3,Vector3.ONE*6))),"outcrop streams with bounded native collision"):continue
  game.set_physics_process(false);game._clear_motion();game.app_focused=true;game.player_hud.equip(0)
  game.camera.global_position=deposit.transform.origin+Vector3(1.8,1.1,1.8);game.camera.look_at(deposit.transform.origin)
  await process_frame;await process_frame
  var target:Dictionary=game.world_attack.target()
  if not check(target.get("asset","")==Deposits.KEYS[material] and target.get("id",0)==deposit.id,"player pickaxe ray resolves the correct mineral stone"):print("OBSERVED_TARGET ",target);continue
  check(target.health==Deposits.HEALTH and target.health>240,"mineral outcrop has higher durability than common boulders")
  await photograph("iron" if material==8 else "copper")
  var before:=count_item(material+194)
  for strike in 11:
   var started:=Time.get_ticks_usec()
   var accepted:bool=game.world_attack.apply_target(target)
   timings.append((Time.get_ticks_usec()-started)/1000.0)
   if not accepted:check(false,"pickaxe strike accepted: "+str(strike));break
  check(not collection.get_instance(deposit.id).is_empty() and count_item(material+194)==before+11,"stone survives eleven pickaxe strikes while each strike grants one matching ore")
  saved_damage=game.world_attack.durability.capture_storage_snapshot()
  var restore_damage=ClassDB.instantiate("NativeWorldDurability")
  check(restore_damage.restore_storage_snapshot(saved_damage) and restore_damage.capture_storage_snapshot()==saved_damage,"partial mineral-stone damage restores exactly")
  check(game.world_attack.apply_target(target) and collection.get_instance(deposit.id).is_empty() and count_item(material+194)==before+12+1+Deposits.REWARD,"twelfth pickaxe strike removes stone with a larger finishing ore payout")
  var saved:PackedByteArray=collection.capture_snapshot()
  check(collection.restore_snapshot(saved) and collection.get_instance(deposit.id).is_empty(),"mined stone stays absent after native model reload")
  check(game.material_deposits.store.capture_snapshot()==saved_metadata,"mining surface clue retains the real underground-deposit map location")
 game.world_map.set_open(true)
 check(game.world_map.deposits.size()==plan.deposits.size(),"world map shows every generated material deposit")
 await wait_for(func():return game.world_map.texture!=null)
 game.world_map.view.overview();await photograph("map")
 game.world_map.show_deposits=false;game.world_map.view.queue_redraw();await process_frame
 check(game.material_deposits.store.capture_snapshot()==saved_metadata,"map layer toggle does not mutate deposits")
 game.world_map.set_open(false)
 await finish()
func finish()->void:
 if game!=null:
  game.session_menu.set_open(false);await game.terrain.shutdown_after_edits();game.queue_free();await process_frame;await process_frame
 FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"strike_ms":timings},"  "))
 print("MATERIAL_DEPOSITS_WORLD checks=",checks," failures=",failures);quit(1 if failures else 0)
