# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
func run()->void:
 var reopen:=false;var slot:=""
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--route-evidence="):evidence=arg.trim_prefix("--route-evidence=")
  if arg.begins_with("--world-slot="):slot=arg.trim_prefix("--world-slot=")
  if arg=="--reopen-route":reopen=true
 if evidence.is_empty() or not slot.begins_with("population_"):quit(2);return
 game=load("res://demo/world.tscn").instantiate();root.add_child(game)
 if not check(await wait_for(func():return not game.loading_active,60),"copied settlement opens"):await finish();return
 game.set_physics_process(false);game._clear_motion()
 if reopen:
  var expected: Dictionary=FileAccess.open(evidence,FileAccess.READ).get_var()
  check(game.actors.store.capture_storage_snapshot()==expected.actors,"fresh reopen restores exact resident identities and positions")
  check(game.actors.orders.capture_storage_snapshot()==expected.orders,"fresh reopen restores patrol endpoints and current legs")
  check(game.actors.store.statistics().active==2,"reopen does not duplicate residents")
 else:
  if not check(not game.road_palette.prepared_streets.is_empty(),"prepared street available"):await finish();return
  var street: Dictionary=game.road_palette.prepared_streets[0]
  var center: Vector3=(street.ends[0]+street.ends[1])*.5
  var direction: Vector3=(street.ends[1]-street.ends[0]).normalized()
  var side:=Vector3(-direction.z,0,direction.x)
  game.player.position=center+side*3+Vector3.UP*1.5;game.terrain.focus=game.player.position
  game.structures.set_model_focus(game.player.position)
  check(await wait_for(func():return game._actor_collision_ready(AABB(center-Vector3(6,1,6),Vector3(12,4,12))),20),"street collision available before population")
  game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED;game.session_menu.toggle_developer()
  game.session_menu.populate_settlement()
  if not check(game.actors.store.statistics().active==2,"development action creates two street residents"):await finish();return
  var orders: PackedByteArray=game.actors.orders.capture_storage_snapshot()
  var state: PackedByteArray=game.actors.store.capture_storage_snapshot()
  game.session_menu.populate_settlement()
  check(game.actors.store.capture_storage_snapshot()==state and game.actors.orders.capture_storage_snapshot()==orders,"repeated population refuses duplicates without mutation")
  var handles: PackedInt64Array=game.actors.store.query_sphere(center,16,4,64).ids
  var goals: Dictionary={}
  for handle in handles:goals[game.actors.store.persistent_id(handle)]=game.actors.orders.get_target(game.actors.store.persistent_id(handle)).target
  var reversed: Dictionary={}
  for tick in 600:
   await physics_frame
   game.actors.update_simulation(1.0/60,game.player.position,true,game._actor_collision_ready)
   for id in goals:
    if game.actors.orders.get_target(id).target!=goals[id]:reversed[id]=true
   if reversed.size()==2:break
  check(reversed.size()==2,"both residents walk to the other street endpoint and reverse")
  game.session_menu.toggle_developer()
  FileAccess.open(evidence,FileAccess.WRITE).store_var({"actors":game.actors.store.capture_storage_snapshot(),"orders":game.actors.orders.capture_storage_snapshot()})
  game.camera.global_position=center+side*10+Vector3.UP*7;game.camera.look_at(center)
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(evidence+(".reopened.png" if reopen else ".created.png"))
 await finish()
