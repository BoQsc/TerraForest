# SPDX-License-Identifier: 0BSD
extends "res://tests/regional_vehicle_travel.gd"
var reached:=0
var max_deviation:=0.0
var held:=0
var min_wheels:=4
var max_speed:=0.0
var frames:Array[float]=[]
func run()->void:
 game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.max_fps=60;game.background_fps=60;root.add_child(game)
 if not await ready_world(60):failure="world load timeout";await finish();return
 var center:Vector3=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(game.terrain.backend.world_seed,game.terrain.backend.world_generator).sites[3].position
 var saved_car:bool="--saved-northern-car" in OS.get_cmdline_user_args()
 var parking:Dictionary=preload("res://addons/structures/northern_lots.gd").parking(center)
 game.teleport(parking.pose.origin+parking.pose.basis.x*2.8 if saved_car else center+Vector3(0,0,70))
 if not await ready_world(45):failure="neighborhood load timeout";await finish();return
 var session=game.world_vehicle
 if not session.fleet_enabled:failure="fleet disabled";await finish();return
 var start:Vector3=game.player.position
 var id:=0
 if saved_car:
  var restored:Dictionary=session.storage.decode_fleet(session.capture_snapshot())
  if not restored.ok or restored.records.size()!=3:failure="three saved vehicles required";await finish();return
  for record:Dictionary in restored.records:
   if record.pose.origin.distance_to(parking.pose.origin)<0.1:id=record.identity
  if id==0:failure="northern saved bay vehicle missing";await finish();return
 else:id=session.fleet.spawn(Transform3D(Basis(Vector3.UP,PI),start+Vector3.UP*0.85))
 var deadline:=Time.get_ticks_msec()+15000
 while not session.activation.residents.has(id) and Time.get_ticks_msec()<deadline:await process_frame
 if not session.activation.residents.has(id):failure="vehicle activation timeout";await finish();return
 var car:RigidBody3D=session.activation.residents[id]
 game.app_focused=true;game.fly=false;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
 game.player.position=car.position+car.global_basis.x*2.8
 if saved_car:
  game.camera.global_position=game.player.position+Vector3.UP*1.62;game.camera.look_at(car.position)
  key(KEY_E,true);await process_frame;key(KEY_E,false)
 else:session.enter(game)
 if not session.driving:failure="entry failed";await finish();return
 for tick in 60:await physics_frame
 var offsets:Array[Vector2]=[Vector2(0,60),Vector2(-1,56),Vector2(-4,53),Vector2(-9,52),Vector2(-33,52),Vector2(-38,51),Vector2(-41,48),Vector2(-42,43),Vector2(-42,-43),Vector2(-41,-48),Vector2(-38,-51),Vector2(-33,-52),Vector2(33,-52),Vector2(38,-51),Vector2(41,-48),Vector2(42,-43),Vector2(42,43),Vector2(41,48),Vector2(38,51),Vector2(33,52),Vector2(9,52),Vector2(4,53),Vector2(1,56),Vector2(0,61),Vector2(0,85)]
 if saved_car:
  offsets.push_front(Vector2(0,63));offsets.push_front(Vector2(0,68));offsets.push_front(Vector2(-3,70))
 var roads:Array=preload("res://addons/structures/northern_lots.gd").street_segments(center)
 roads.append({"start":center+Vector3(0,0,-100),"finish":center+Vector3(0,0,100)})
 if saved_car:roads.append({"start":parking.start,"finish":parking.finish})
 var previous:=Time.get_ticks_usec();var sampled:=0;var target_start:=Time.get_ticks_msec()
 var route_start:=Time.get_ticks_msec()
 while reached<offsets.size() and Time.get_ticks_msec()-route_start<110000:
  var target:Vector3=center+Vector3(offsets[reached].x,0,offsets[reached].y)
  var here:Vector3=car.position;here.y=center.y
  if here.distance_to(target)<2.0:
   reached+=1;target_start=Time.get_ticks_msec()
   if reached==offsets.size():break
   continue
  if Time.get_ticks_msec()-target_start>18000:failure="waypoint stalled: "+str(reached);break
  var desired:Vector3=(target-here).normalized();var forward:Vector3=car.global_basis.z;forward.y=0;forward=forward.normalized()
  var angle:=atan2(forward.cross(desired).y,forward.dot(desired))
  game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
  key(KEY_W,car.speed_kph<18);key(KEY_S,car.speed_kph>22)
  key(KEY_A,angle>0.06);key(KEY_D,angle< -0.06)
  await process_frame
  var now:=Time.get_ticks_usec();frames.append((now-previous)/1000.0);previous=now
  max_speed=maxf(max_speed,car.speed_kph);min_wheels=mini(min_wheels,car.loaded_wheels)
  if car.streaming.waiting:held+=1
  var deviation:=INF
  for road:Dictionary in roads:
   var a:Vector3=road.start;var span:Vector3=road.finish-a;span.y=0
   var point:Vector3=car.position;point.y=a.y
   deviation=minf(deviation,point.distance_to(a+span*clampf((point-a).dot(span)/span.length_squared(),0,1)))
  max_deviation=maxf(max_deviation,deviation)
  if deviation>5 or absf(car.position.y-center.y)>2:failure="left supported road corridor";break
  if Time.get_ticks_msec()>=sampled:
   samples.append({"position":car.position,"speed_kph":car.speed_kph,"waypoint":reached,"angle":angle,"deviation":deviation,"waiting":car.streaming.waiting,"loaded_wheels":car.loaded_wheels});sampled=Time.get_ticks_msec()+200
 if reached<offsets.size() and failure.is_empty():failure="route deadline"
 for code in [KEY_W,KEY_S,KEY_A,KEY_D]:key(code,false)
 key(KEY_SPACE,true);deadline=Time.get_ticks_msec()+8000
 while car.linear_velocity.length()>0.15 and Time.get_ticks_msec()<deadline:await physics_frame
 key(KEY_SPACE,false)
 if max_deviation>3.1:failure+=" chassis center left lane clearance"
 if car.linear_velocity.length()>0.15:failure+=" stop failed"
 var map_checked:=false
 if saved_car and car.linear_velocity.length()<=0.15:
  game.app_focused=true
  key(KEY_M,true);await process_frame;key(KEY_M,false)
  key(KEY_W,true)
  for tick in 12:game.app_focused=true;await physics_frame
  map_checked=game.world_map.opened and not car.controls_enabled and car.linear_velocity.length()<0.15
  key(KEY_W,false);key(KEY_M,true);await process_frame;key(KEY_M,false)
  if not map_checked:failure+=" seated map failed to block vehicle throttle"
  key(KEY_E,true);await process_frame;key(KEY_E,false)
 else:session.exit_vehicle(game)
 var exit_message:="E exit" if saved_car else "adapter exit"
 var fleet_snapshot:PackedByteArray=session.capture_snapshot()
 var moved:Dictionary=session.storage.decode_fleet(fleet_snapshot)
 if not moved.ok or moved.records.size()!=3 or not session.fleet.get_record(id).pose.is_equal_approx(car.global_transform):failure+=" moved fleet record not captured"

 if session.driving:failure+=" safe exit failed: "+exit_message
 frames.sort()
 var file:=FileAccess.open("res://reports/neighborhood_vehicle_loop.json",FileAccess.WRITE)
 file.store_string(JSON.stringify({"failure":failure,"waypoints":reached,"expected":offsets.size(),"max_deviation_m":max_deviation,"max_speed_kph":max_speed,"minimum_loaded_wheels":min_wheels,"collision_hold_frames":held,"saved_vehicle":saved_car,"seated_map_checked":map_checked,"frame_p95_ms":frames[int(frames.size()*.95)] if not frames.is_empty() else 0,"frame_max_ms":frames.back() if not frames.is_empty() else 0,"samples":samples},"  "));file.close()
 game.camera.global_position=car.position+Vector3(12,8,12);game.camera.look_at(car.position)
 await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png("res://reports/neighborhood_vehicle_loop.png")
 await finish()
func finish()->void:
 for code in [KEY_W,KEY_S,KEY_A,KEY_D,KEY_SPACE]:key(code,false)
 print("NEIGHBORHOOD_VEHICLE_LOOP failures=",0 if failure.is_empty() else 1," reached=",reached," ",failure)
 await super.finish()
