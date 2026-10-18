# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok:bool,label:String)->bool:
 print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
 return ok
func _initialize()->void:run.call_deferred()
func run()->void:
 var game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;root.add_child(game)
 var deadline:=Time.get_ticks_msec()+45000
 while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
 if not check(not game.loading_active,"actual world ready"):quit(1);return
 game.set_physics_process(false);game._clear_motion();game.app_focused=true
 if not game.session_menu.developer:game.session_menu.toggle_developer()
 if game.actors.pool==null:game.actors.enable()
 # Real native block floors isolate authoring from variable generated street grades.
 var anchor:=Vector3(floorf(game.player.position.x),ceilf(game.player.position.y)+12,floorf(game.player.position.z))
 var cells:=PackedInt32Array()
 for center in [-12,12]:
  for x in range(center-4,center+5):
   for z in range(-9,10):cells.append_array(PackedInt32Array([int(anchor.x)+x,int(anchor.y)-1,int(anchor.z)+z,65]))
 game.structures.blocks.set_cells(cells);game.structures.blocks.flush_bakes()
 game.structures.blocks.set_focus(anchor)
 game.road_palette.prepared_streets=[{"ends":[anchor+Vector3(-12,0,-8),anchor+Vector3(-12,0,8)]},{"ends":[anchor+Vector3(12,0,-8),anchor+Vector3(12,0,8)]}]
 game.player.position=anchor+Vector3(-9,.1,0);game.terrain.focus=game.player.position
 deadline=Time.get_ticks_msec()+20000
 var area:=AABB(anchor+Vector3(-17,-1,-6),Vector3(34,4,12))
 while not game._actor_collision_ready(area) and Time.get_ticks_msec()<deadline:await process_frame
 print("COLLISION_READY ",game.terrain.is_collision_region_ready(area)," ",game.structures.is_collision_region_ready(area)," ",game.vegetation.is_collision_region_ready(area))
 for i in 3:await physics_frame
 Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
 var first: Dictionary=game._populate_settlement_actors();print("FIRST_POPULATION ",first)
 if check(first.ok,"populate first street through actual world action"):
  var original: Dictionary={}
  for id in first.ids:
   original[id]={"position":game.actors.store.get_position(game.actors.store.resolve_identity(id)),"order":game.actors.orders.get_target(id)}
  game.player.position=anchor+Vector3(15,.1,0);game.terrain.focus=game.player.position
  for i in 5:await physics_frame
  var second: Dictionary=game._populate_settlement_actors();print("SECOND_POPULATION ",second)
  if check(second.ok,"second street accepts residents while first population exists"):
   check(game.actors.store.statistics().active==4,"two streets own four distinct residents")
   for id in original:
    check(game.actors.store.get_position(game.actors.store.resolve_identity(id))==original[id].position and game.actors.orders.get_target(id)==original[id].order,"existing resident identity position and order preserved")
   var before: PackedByteArray=game.actors.store.capture_storage_snapshot()
   var orders: PackedByteArray=game.actors.orders.capture_storage_snapshot()
   game.actors.suspend()
   var repeated: Dictionary=game._populate_settlement_actors()
   check(not repeated.ok and game.actors.store.capture_storage_snapshot()==before and game.actors.orders.capture_storage_snapshot()==orders,"dormant street residents block duplicates without mutation")
   var goals: Dictionary={}
   for id in first.ids+second.ids:goals[id]=game.actors.orders.get_target(id).target
   var reversed: Dictionary={}
   var peak_step:=0.0
   var previous: Dictionary={}
   for id in goals:previous[id]=game.actors.store.get_position(game.actors.store.resolve_identity(id))
   game.fly=false;game.needs_floor_spawn=false;game.set_physics_process(true)
   for tick in 600:
    await physics_frame
    for id in goals:
     if game.actors.orders.get_target(id).target!=goals[id]:reversed[id]=true
    var fallen:=false
    for id in goals:
     var point: Vector3=game.actors.store.get_position(game.actors.store.resolve_identity(id))
     peak_step=maxf(peak_step,point.distance_to(previous[id]))
     if point.distance_to(previous[id])>.2:print("JUMP frame=",tick," id=",id," from=",previous[id]," to=",point)
     previous[id]=point
     if point.y<anchor.y+.65:
      var ray:=PhysicsRayQueryParameters3D.create(Vector3(point.x,anchor.y+2,point.z),Vector3(point.x,anchor.y-1,point.z),2)
      print("FALL frame=",tick," actor=",id," position=",point," floor_ray=",game.get_world_3d().direct_space_state.intersect_ray(ray)," block=",game.structures.blocks.get_cell(Vector3i(floori(point.x),int(anchor.y)-1,floori(point.z))))
      fallen=true
    if fallen or reversed.size()==4:break
   game.set_physics_process(false)
   for id in goals:
    var handle: int=game.actors.store.resolve_identity(id)
    print("RESIDENT ",id," position=",game.actors.store.get_position(handle)," goal=",goals[id]," navigation=",game.actors.pool.navigation_status(handle))
   check(peak_step<.2,"reactivated residents never jump between pooled body positions")
   print("PEAK_RESIDENT_STEP ",peak_step)
   check(reversed.size()==4,"all four residents walk and reverse on their own streets")
   # Fresh owners verify both populations and patrol legs serialize together.
   var store=ClassDB.instantiate("NativeEntityStore");store.configure(1024)
   check(store.restore_storage_snapshot(game.actors.store.capture_storage_snapshot()),"combined population restores into fresh native owner")
   var restored=ClassDB.instantiate("NativeActorOrders");restored.configure(store)
   check(restored.restore_storage_snapshot(game.actors.orders.capture_storage_snapshot()) and restored.capture_storage_snapshot()==game.actors.orders.capture_storage_snapshot(),"all patrol legs restore exactly")
   check(store.capture_storage_snapshot()==game.actors.store.capture_storage_snapshot(),"all resident identities and positions restore exactly")
 game.camera.global_position=anchor+Vector3(0,17,22);game.camera.look_at(anchor)
 await RenderingServer.frame_post_draw
 DirAccess.make_dir_recursive_absolute("res://reports/settlement_multiple_streets")
 root.get_texture().get_image().save_png("res://reports/settlement_multiple_streets/world.png")
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame
 print("MULTIPLE_STREETS failures=",failures);quit(1 if failures else 0)
