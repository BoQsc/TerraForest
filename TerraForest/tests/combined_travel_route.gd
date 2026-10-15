# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
var motion_rows:Array=[]
func vehicle_state(car: RigidBody3D) -> Dictionary:
 return {"position":car.position,"velocity":car.linear_velocity,"controls":car.controls_enabled,"W":Input.is_key_pressed(KEY_W),"S":Input.is_key_pressed(KEY_S),"freeze":car.freeze,"sleeping":car.sleeping,"waiting":car.streaming.waiting,"loaded_wheels":car.loaded_wheels,"normal":car._normal_mode,"drive_speed":car._drive_speed,"app_focused":game.app_focused,"window_focused":DisplayServer.window_is_focused(),"physics_frame":Engine.get_physics_frames(),"time_ms":Time.get_ticks_msec()}
func walk_to(target:Vector3,seconds:float=8.0)->bool:
 var deadline:int=Time.get_ticks_msec()+int(seconds*1000)
 while Time.get_ticks_msec()<deadline:
  var offset:Vector3=target-game.player.position;offset.y=0
  if offset.length()<0.3:break
  game.yaw=atan2(-offset.x,-offset.z);game.player.rotation.y=game.yaw
  game.camera.rotation=Vector3(-0.15,0,0);game.app_focused=true
  game.controls.set_key(KEY_W,true,Time.get_ticks_usec())
  await physics_frame
 game.controls.clear(Time.get_ticks_usec())
 var remaining:Vector3=target-game.player.position;remaining.y=0
 motion_rows.append({"target":target,"position":game.player.position,"remaining":remaining.length(),"on_floor":game.player.is_on_floor(),"loading":game.loading_active})
 return remaining.length()<0.4 and game.player.is_on_floor()
func key(code:int,pressed:bool)->void:
 var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=pressed
 Input.parse_input_event(event);Input.flush_buffered_events()
func run()->void:
 var slot:String=""
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--route-evidence="):evidence=arg.trim_prefix("--route-evidence=")
  if arg.begins_with("--world-slot="):slot=arg.trim_prefix("--world-slot=")
 if evidence.is_empty() or not slot.begins_with("combined_route_"):quit(2);return
 var expected:Dictionary=FileAccess.open(evidence,FileAccess.READ).get_var()
 game=load("res://demo/world.tscn").instantiate();root.add_child(game)
 if not check(await wait_for(func():return not game.loading_active,45),"earned settlement opens for movement"):await finish();return
 game.fly=false;game.needs_floor_spawn=false;game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
 var t:PackedFloat32Array=game.storage.collection.get_instance(expected.chest)
 var right:=Vector3(t[0],t[4],t[8]).normalized()
 var front:=Vector3(t[2],t[6],t[10]).normalized()
 # Block doorway occupies local x=[0,1]; attachments use the integer origin.
 var center:=Vector3(t[3],t[7],t[11])-right*2.0
 if not check(await walk_to(center+front*2),"walk from saved chest position into central aisle"):await finish();return
 if not game.doors.collection.get_ids().is_empty():
  if not check(await walk_to(center+front*4),"walk within reach of enclosed cottage door"):await finish();return
  game.camera.look_at(center+front*5.5+Vector3.UP)
  if not check(game.doors.try_interact(),"interact with generated cottage door before departure"):await finish();return
  for frame in 15:await physics_frame
 if not check(await walk_to(center+front*14.5),"walk through doorway and down stairs to street without jumping"):await finish();return
 var street:Dictionary=game.road_palette.prepared_streets[0]
 var a:Vector3=street.ends[0];var b:Vector3=street.ends[1];var direction:Vector3=(b-a).normalized()
 print("TRAVEL_STREET ",a," -> ",b)
 if not check(await walk_to(a+direction*2),"walk along street to vehicle departure point"):await finish();return
 game.yaw=atan2(-direction.x,-direction.z);game.player.rotation.y=game.yaw
 game.camera.look_at(a+direction*8)
 var place:String=game.world_vehicle.spawn(game)
 print("TRAVEL_VEHICLE ",place)
 if not check(game.world_vehicle.fleet.statistics().records==1,"normal vehicle placement on authored street"):await finish();return
 if not check(await walk_to(a+direction*5),"walk up to placed car"):await finish();return
 if not check(game.world_vehicle.enter(game),"enter nearby car"):await finish();return
 var car:RigidBody3D=game.world_vehicle.car
 for frame in 60:await physics_frame
 var start:Vector3=car.position
 var distance:float=minf(12.0,a.distance_to(b)-14.0)
 if not check(distance>=6.0,"authored street supports a meaningful short drive"):await finish();return
 key(KEY_W,true)
 var deadline:int=Time.get_ticks_msec()+10000
 while (car.position-start).dot(direction)<distance and Time.get_ticks_msec()<deadline:
  game.app_focused=true;await physics_frame
 key(KEY_W,false)
 var outbound:float=(car.position-start).dot(direction)
 key(KEY_S,true);deadline=Time.get_ticks_msec()+5000
 while car.linear_velocity.length()>0.15 and Time.get_ticks_msec()<deadline:await physics_frame
 key(KEY_S,false)
 check(outbound>=distance and car.linear_velocity.length()<0.15,"drive outbound and brake using keyboard input")
 for frame in 3:await physics_frame
 key(KEY_S,true);deadline=Time.get_ticks_msec()+10000
 print("REVERSE_START ",vehicle_state(car))
 var next_sample: int=Time.get_ticks_msec()+500
 while (car.position-start).dot(direction)>1.0 and Time.get_ticks_msec()<deadline:
  game.app_focused=true;await physics_frame
  if Time.get_ticks_msec()>=next_sample:
   print("REVERSE_SAMPLE ",vehicle_state(car));next_sample=Time.get_ticks_msec()+500
 print("REVERSE_END ",vehicle_state(car))
 key(KEY_S,false);key(KEY_W,true);deadline=Time.get_ticks_msec()+5000
 while car.linear_velocity.length()>0.15 and Time.get_ticks_msec()<deadline:await physics_frame
 key(KEY_W,false)
 check(car.position.distance_to(start)<3.0 and car.linear_velocity.length()<0.15,"reverse to departure point and stop without pose correction")
 print("TRAVEL_DISTANCE outbound=",outbound," return_error=",car.position.distance_to(start))
 print("TRAVEL_EXIT ",game.world_vehicle.exit_vehicle(game))
 if not check(not game.world_vehicle.driving,"exit stopped car restores walking"):await finish();return
 if not check(await walk_to(center+front*14.5),"walk from parked car back to cottage approach"):await finish();return
 if not check(await walk_to(center+front*2),"walk back up stairs through doorway without jumping"):await finish();return
 check(game.player_hud.inventory.capture_storage_snapshot()==expected.inventory and game.storage.store.capture_storage_snapshot()==expected.storage,"earned inventory and chest contents unchanged after travel")
 expected.hinges=game.doors.state.capture_storage_snapshot()
 expected.doors=game.doors.collection.capture_snapshot()
 var saved:=FileAccess.open(evidence,FileAccess.WRITE);saved.store_var(expected);saved.close()
 await finish()
func finish()->void:
 for code in [KEY_W,KEY_S,KEY_A,KEY_D]:key(code,false)
 if game!=null:
  game.controls.clear(Time.get_ticks_usec())
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png(evidence+".travel.png")
  var file:=FileAccess.open(evidence+".travel.json",FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failures,"walking":motion_rows},"  "));file.close()
 await super.finish()
