# SPDX-License-Identifier: 0BSD
extends "res://tests/world_browser_route.gd"
func inspect_world(reopen: bool)->void:
 var path:=report.path_join("patrol.bin")
 if reopen:
  var expected: Dictionary=FileAccess.open(path,FileAccess.READ).get_var()
  check(game.actors.orders.capture_storage_snapshot()==expected.orders,"fresh world preserves patrol endpoints and active leg exactly")
  check(game.actors.store.resolve_identity(expected.id)!=0,"fresh world resolves persistent patrol actor")
  return
 var ground_ray:=PhysicsRayQueryParameters3D.create(game.player.global_position+Vector3(3,10,0),game.player.global_position+Vector3(3,-10,0),3,[game.player.get_rid()])
 var hit: Dictionary=game.get_world_3d().direct_space_state.intersect_ray(ground_ray)
 if not check(not hit.is_empty(),"nearby actual terrain supplies patrol destination"):return
 var id: int=game.actors.spawn(game.player.global_position+Vector3(0,.93,0))
 if not check(id>0,"persistent actor authored beside player"):return
 game.actor_authoring.selected_identity=id;game.actor_authoring.selected_epoch=game.terrain.epoch
 var camera_pose: Transform3D=game.camera.global_transform
 game.camera.global_position=hit.position+Vector3(0,3,0)
 game.camera.look_at(hit.position,Vector3.FORWARD)
 game.session_menu.toggle_developer()
 game.session_menu.patrol_actor()
 var order: Dictionary=game.actors.orders.get_target(id)
 check(order.present and order.get("patrol",false),"development UI patrol action authors aimed terrain endpoint")
 game.camera.global_transform=camera_pose
 game.session_menu.toggle_developer()
 var file:=FileAccess.open(path,FileAccess.WRITE);file.store_var({"id":id,"orders":game.actors.orders.capture_storage_snapshot()});file.close()
