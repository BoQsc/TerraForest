# SPDX-License-Identifier: 0BSD
extends "res://tests/regional_road_travel.gd"
func key(code:int,pressed:bool)->void:
 var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=pressed
 Input.parse_input_event(event);Input.flush_buffered_events()
func run()->void:
 game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.max_fps=60;game.background_fps=60;root.add_child(game)
 if not await ready_world(90):failure="world load timeout";await finish();return
 var layout:Dictionary=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(game.terrain.backend.world_seed,game.terrain.backend.world_generator)
 var hub:Vector3=layout.sites[0].position
 var west:Vector3=layout.sites[1].position
 var direction:Vector3=west-hub;direction.y=0;direction=direction.normalized()
 game.teleport(hub+direction*100)
 if not await ready_world(60):failure="departure timeout";await finish();return
 game.fly=false;game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
 var session=game.world_vehicle
 if not session.fleet_enabled:failure="fleet disabled";await finish();return
 var start:Vector3=game.player.position
 var heading:=Basis(Vector3.UP,atan2(direction.x,direction.z))
 var id:int=session.fleet.spawn(Transform3D(heading,start+Vector3.UP*0.85))
 var deadline:=Time.get_ticks_msec()+15000
 while not session.activation.residents.has(id) and Time.get_ticks_msec()<deadline:await process_frame
 if not session.activation.residents.has(id):failure="vehicle activation timeout";await finish();return
 var car:RigidBody3D=session.activation.residents[id]
 game.player.position=car.position+car.global_basis.x*2.8
 if not session.enter(game):failure="vehicle entry failed";await finish();return
 for tick in 60:await physics_frame
 start=car.position
 var distance:float=Vector2(west.x-start.x,west.z-start.z).length()-150
 var max_speed:=0.0;var hold_frames:=0;var frames:Array[float]=[]
 var slow_frames:Array=[];var max_hold_run:=0;var hold_run:=0
 var previous:=Time.get_ticks_usec();var next_sample:=Time.get_ticks_msec()
 deadline=Time.get_ticks_msec()+60000
 while (car.position-start).dot(direction)<distance and Time.get_ticks_msec()<deadline:
  game.app_focused=true;key(KEY_W,true)
  await process_frame
  var now:=Time.get_ticks_usec();frames.append(float(now-previous)/1000.0);previous=now
  max_speed=maxf(max_speed,car.speed_kph)
  if car.streaming.waiting:hold_frames+=1;hold_run+=1
  else:hold_run=0
  max_hold_run=maxi(max_hold_run,hold_run)
  if frames.back()>25.0:
   slow_frames.append({"ms":frames.back(),"distance_m":(car.position-start).dot(direction),"speed_kph":car.speed_kph,"waiting":car.streaming.waiting,"models":game.model_paging.last_state.duplicate() if game.model_paging!=null else {},"model_coordinator_us":game.model_paging.last_process_us if game.model_paging!=null else 0,"save":game.terrain.backend.save_profile()})
  if Time.get_ticks_msec()>=next_sample:
   samples.append({"position":[car.position.x,car.position.y,car.position.z],"speed_kph":car.speed_kph,"waiting":car.streaming.waiting,"loaded_wheels":car.loaded_wheels})
   next_sample=Time.get_ticks_msec()+500
 var travelled:float=(car.position-start).dot(direction)
 var brake_start:Vector3=car.position
 key(KEY_W,false);key(KEY_SPACE,true)
 deadline=Time.get_ticks_msec()+8000
 while car.linear_velocity.length()>0.15 and Time.get_ticks_msec()<deadline:await physics_frame
 key(KEY_SPACE,false)
 var final_offset:Vector3=car.position-hub;final_offset.y=0
 var road_length:float=Vector2(west.x-hub.x,west.z-hub.z).length()
 var along:float=final_offset.dot(direction)
 var lane_error:float=(final_offset-direction*along).length()
 if along<0 or along>road_length or lane_error>3.0:failure="stopped outside paved arterial corridor"
 var surface:Dictionary={}
 var receive:=func(token:int,points:PackedVector3Array,normals:PackedVector3Array,_epoch:int,_revision:int):
  if token==77291:surface["points"]=points;surface["normals"]=normals
 game.terrain.surface_batch_ready.connect(receive)
 deadline=Time.get_ticks_msec()+5000
 var accepted:=false
 while surface.is_empty() and Time.get_ticks_msec()<deadline:
  if not accepted:accepted=game.terrain.request_surface_batch(PackedVector3Array([car.position]),77291)
  await process_frame
 game.terrain.surface_batch_ready.disconnect(receive)
 if surface.is_empty() or surface.normals[0]!=Vector3.ZERO:failure+=" stop surface is not paved"
 if travelled<distance:failure+=" did not reach western approach"
 if car.linear_velocity.length()>0.15:failure+=" braking failed"
 frames.sort()
 var result:={"failure":failure,"seed":game.terrain.backend.world_seed,"generator":game.terrain.backend.world_generator,"final_position":[car.position.x,car.position.y,car.position.z],"braking_distance_m":car.position.distance_to(brake_start),"stop_lane_error_m":lane_error,"stop_remaining_m":road_length-along,"distance_m":travelled,"target_m":distance,"max_speed_kph":max_speed,"collision_hold_frames":hold_frames,"max_consecutive_hold_frames":max_hold_run,"slow_frames":slow_frames,"model_region_paging":game.model_region_paging,"frame_p95_ms":frames[int(frames.size()*.95)] if not frames.is_empty() else 0,"frame_max_ms":frames[-1] if not frames.is_empty() else 0,"samples":samples,"scope":"One full-throttle regional arterial drive then handbrake; no pose correction after entry. Arrival is not performance qualification."}
 var file:=FileAccess.open("res://reports/regional_vehicle_travel.json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "));file.close()
 await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png("res://reports/regional_vehicle_travel.png")
 await finish()
func finish()->void:
 key(KEY_W,false);key(KEY_SPACE,false)
 print("REGIONAL_VEHICLE_TRAVEL failures=",0 if failure.is_empty() else 1," ",failure)
 await super.finish()
