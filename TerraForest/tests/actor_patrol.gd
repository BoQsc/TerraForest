# SPDX-License-Identifier: 0BSD
extends "res://tests/actor_navigation.gd"
func run()->void:
 Engine.max_fps=60
 var scene:=Node3D.new();root.add_child(scene)
 box(scene,Vector3(0,-.5,0),Vector3(12,1,8),Color("34473d"))
 var persistence=preload("res://addons/world_runtime/world_persistence.gd").new()
 actors=preload("res://addons/world_runtime/actor_world.gd").new();scene.add_child(actors)
 check(actors.prepare(persistence) and actors.enable(1),"existing bounded actor world enables")
 var start:=Vector3(-2,.93,0);var end:=Vector3(2,.93,0)
 var id: int=actors.spawn(start);var handle: int=actors.store.resolve_identity(id)
 check(actors.orders.set_target(id,end),"legacy single destination accepted")
 var legacy: PackedByteArray=actors.orders.capture_storage_snapshot()
 check(legacy.decode_u32(4)==1 and actors.orders.restore_storage_snapshot(legacy),"single orders retain legacy encoding")
 check(actors.orders.set_patrol(id,end),"two-point patrol starts at actor location")
 var saved: PackedByteArray=actors.orders.capture_storage_snapshot()
 check(saved.decode_u32(4)==2 and actors.orders.get_target(id).other==start,"patrol saves both endpoints and active leg")
 for point in [start,Vector3(30,.93,0),Vector3(INF,0,0)]:
  check(not actors.orders.set_patrol(id,point) and actors.orders.capture_storage_snapshot()==saved,"invalid or oversized patrol rejects atomically")
 var bad:=saved.duplicate();bad.encode_u32(72,2)
 check(not actors.orders.restore_storage_snapshot(bad) and actors.orders.capture_storage_snapshot()==saved,"invalid patrol mode rejects atomically")
 bad=saved.duplicate();bad.encode_double(48,NAN)
 check(not actors.orders.restore_storage_snapshot(bad) and actors.orders.capture_storage_snapshot()==saved,"invalid patrol endpoint rejects atomically")
 actors.store.set_position(handle,end);actors.select_near(Vector3.ZERO)
 await physics_frame
 actors.pool.settle(1.0/60,func(_bounds: AABB):return false)
 check(actors.orders.get_target(id).target==end,"unavailable collision cannot advance patrol")
 actors.store.set_position(handle,start);actors.suspend()
 var reversals:=0;var previous:=end;var reloaded:=false
 for tick in 720:
  await physics_frame
  actors.update_simulation(1.0/60,Vector3.ZERO,true,func(_bounds: AABB):return true)
  var target: Vector3=actors.orders.get_target(id).target
  if target!=previous:
   reversals+=1;previous=target
   if not reloaded:
    var position_bytes: PackedByteArray=actors.store.capture_storage_snapshot()
    var order_bytes: PackedByteArray=actors.orders.capture_storage_snapshot()
    check(actors._restore(position_bytes) and actors.orders.restore_storage_snapshot(order_bytes),"mid-patrol actor and order restore")
    check(actors.orders.capture_storage_snapshot()==order_bytes,"restoration preserves the returning leg exactly")
    handle=actors.store.resolve_identity(id);reloaded=true
  if reversals>=4:break
 check(reversals>=4,"rendered actor walks four patrol legs through bounded native routing")
 var frozen: PackedByteArray=actors.orders.capture_storage_snapshot()
 actors.suspend()
 for tick in 10:
  await physics_frame
  actors.update_simulation(1.0/60,Vector3(1000,0,0),true,func(_bounds: AABB):return true)
 check(actors.orders.capture_storage_snapshot()==frozen,"inactive patrol retains its leg without background advancement")
 check(actors.orders.clear_target(id) and not actors.orders.get_target(id).present,"Stop clears patrol")
 check(actors.orders.restore_storage_snapshot(legacy) and not actors.orders.get_target(id).patrol,"legacy order restoration clears patrol behavior")
 var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("17252c");environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.7;scene.add_child(environment)
 var camera:=Camera3D.new();scene.add_child(camera);camera.position=Vector3(8,7,9);camera.look_at(Vector3.ZERO);camera.current=true
 for point in [start,end]:box(scene,point-Vector3.UP*.87,Vector3(.6,.08,.6),Color("75dba1"),0)
 actors.select_near(Vector3.ZERO)
 root.size=Vector2i(1920,1080);DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
 await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://reports/actor_patrol.png")
 scene.free();await process_frame
 print("ACTOR_PATROL reversals=",reversals," failures=",failures);quit(1 if failures else 0)
