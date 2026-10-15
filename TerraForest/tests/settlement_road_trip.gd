# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_travel_route.gd"
var road_points:=PackedVector3Array()
var samples:Array=[]
func run()->void:
 var slot:=""
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--route-evidence="):evidence=arg.trim_prefix("--route-evidence=")
  if arg.begins_with("--world-slot="):slot=arg.trim_prefix("--world-slot=")
 if evidence.is_empty() or not slot.begins_with("road_trip_"):quit(2);return
 game=load("res://demo/world.tscn").instantiate();game.background_fps=60;root.add_child(game)
 if not check(await wait_for(func():return not game.loading_active,45),"settlement copy opens"):await finish();return
 game.set_physics_process(false);game._clear_motion();game.app_focused=true
 if "--reopen-trip" in OS.get_cmdline_user_args():
  var expected:Dictionary=FileAccess.open(evidence+".expected",FileAccess.READ).get_var()
  check(game.road_palette.capture_anchors()==expected.anchors,"extended road entrances restore exactly")
  check(game.world_vehicle.capture_snapshot()==expected.vehicle,"parked vehicle restores exactly")
  check(game._saved_pose==expected.pose,"saved on-foot arrival pose restores exactly")
  await finish();return
 var p=game.road_palette
 var street:Dictionary=p.prepared_streets[0]
 var a:Vector3=street.ends[0];var direction:Vector3=(a-street.ends[1]).normalized()
 p.width.value=4;p.depth.value=4;p.clearance.value=16
 p.mark(true,a);p.mark(false,a+direction*112)
 game._road_action("smooth")
 await wait_for(func():return game.road_authoring.phase not in ["request","sampling","fitting"],20)
 if not check(game.road_authoring.phase=="ready","terrain-following extension preview: "+p.status.text):await finish();return
 road_points=game.road_authoring.points.duplicate()
 game._road_action("build")
 await wait_for(func():return game.road_authoring.phase!="building",40)
 if not check(game.road_authoring.phase=="complete","connected road constructed: "+p.status.text):await finish();return
 # Fixture starts at the existing street; all measured travel uses normal physics/input.
 game.player.position=a-direction*8+Vector3.UP*2
 game.fly=false;game.needs_floor_spawn=false;game.set_physics_process(true)
 game.yaw=atan2(-direction.x,-direction.z);game.player.rotation.y=game.yaw
 game.camera.look_at(a-direction*2);Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
 for frame in 120:await physics_frame
 game.camera.look_at(a-direction*2)
 print("ROAD_TRIP_SPAWN ",game.world_vehicle.spawn(game))
 if not check(game.world_vehicle.fleet.statistics().records==1,"vehicle placed at departure"):await finish();return
 if not check(await walk_to(a-direction*5),"walk to vehicle"):await finish();return
 if not check(game.world_vehicle.enter(game),"enter vehicle"):await finish();return
 var car:RigidBody3D=game.world_vehicle.car
 for frame in 60:await physics_frame
 var start:Vector3=car.position
 var deadline:int=Time.get_ticks_msec()+20000
 var next_sample:=0
 var boundaries:Dictionary={}
 key(KEY_W,true)
 while (car.position-start).dot(direction)<88 and Time.get_ticks_msec()<deadline:
  game.app_focused=true
  if Time.get_ticks_msec()>=next_sample:
   next_sample=Time.get_ticks_msec()+100
   var region:=Vector2i(floori(car.position.x/16),floori(car.position.z/16))
   boundaries[region]=true
   samples.append({"position":car.position,"speed":car.linear_velocity.length(),"held":car.freeze,"region":region,"fps":Engine.get_frames_per_second()})
  await physics_frame
 key(KEY_W,false);key(KEY_S,true)
 deadline=Time.get_ticks_msec()+5000
 while car.linear_velocity.length()>0.15 and Time.get_ticks_msec()<deadline:await physics_frame
 key(KEY_S,false)
 var travelled:float=(car.position-start).dot(direction)
 check(travelled>=88 and boundaries.size()>=5,"drive at least 88 m across five collision regions: %.2f m / %d regions" % [travelled,boundaries.size()])
 check(car.linear_velocity.length()<0.15,"normal brake stops the car")
 check(absf((car.position-start).dot(Vector3(direction.z,0,-direction.x)))<3,"car remains on road")
 print("ROAD_TRIP_EXIT ",game.world_vehicle.exit_vehicle(game))
 check(not game.world_vehicle.driving,"exit at road destination")
 game.set_physics_process(false);game._clear_motion()
 var expected_file:=FileAccess.open(evidence+".expected",FileAccess.WRITE)
 expected_file.store_var({"anchors":p.capture_anchors(),"vehicle":game.world_vehicle.capture_snapshot(),"pose":game._capture_player_pose()});expected_file.close()
 check(preload("res://addons/presentation/fullscreen_policy.gd").measurement(root).fair_graphical_sample,"1920x1080 fullscreen full render scale")
 await finish()
func finish()->void:
 var file:=FileAccess.open(evidence+(".reopen.json" if "--reopen-trip" in OS.get_cmdline_user_args() else ".road.json"),FileAccess.WRITE)
 file.store_string(JSON.stringify({"failures":failures,"road":road_points,"samples":samples},"  "));file.close()
 if "--reopen-trip" in OS.get_cmdline_user_args():evidence+=".reopen"
 await super.finish()
