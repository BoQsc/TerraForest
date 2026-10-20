# SPDX-License-Identifier: 0BSD
extends "res://tests/northern_tower_walk.gd"
func ground_walk(target:Vector3)->bool:
 var deadline:=Time.get_ticks_msec()+int(4000+game.player.position.distance_to(target)*350)
 while Time.get_ticks_msec()<deadline:
  var offset:Vector3=target-game.player.position;offset.y=0
  if offset.length()<0.3 and game.player.is_on_floor():game.controls.clear(Time.get_ticks_usec());return true
  game.yaw=atan2(-offset.x,-offset.z);game.player.rotation.y=game.yaw;game.camera.rotation=Vector3.ZERO
  game.controls.set_key(KEY_W,true,Time.get_ticks_usec())
  await physics_frame;game.app_focused=true;game._physics_process(1.0/60)
 game.controls.clear(Time.get_ticks_usec());return false
func run()->void:
 game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.max_fps=60;game.background_fps=60;root.add_child(game)
 if not check(await wait_for(func():return not game.loading_active,60),"world loads"):await done();return
 var site:=1
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--access-site="):site=arg.trim_prefix("--access-site=").to_int()
 var center:Vector3=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(game.terrain.backend.world_seed,game.terrain.backend.world_generator).sites[site].position
 game.teleport(center)
 if not check(await wait_for(func():return not game.loading_active,45),"destination residency ready before discovering entrances"):await done();return
 game.set_physics_process(false);game._clear_motion();game.fly=false;game.needs_floor_spawn=false;game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
 var doors:Array=[]
 for id:int in game.doors.collection.get_ids():
  var p:PackedFloat32Array=game.doors.collection.get_instance(id)
  var pose:=Transform3D(Basis(Vector3(p[0],p[4],p[8]),Vector3(p[1],p[5],p[9]),Vector3(p[2],p[6],p[10])).orthonormalized(),Vector3(p[3],p[7],p[11]))
  if Vector2(pose.origin.x-center.x,pose.origin.z-center.z).length()<120:doors.append({"id":id,"pose":pose})
 if not check(not doors.is_empty(),"destination has resident entrances"):await done();return
 doors.sort_custom(func(a,b):return a.pose.origin.distance_squared_to(center)<b.pose.origin.distance_squared_to(center))
 var door:Dictionary=doors[0];var approach:Vector3=door.pose*Vector3(0.5,0,4)
 var nodes:Array[Vector3]=[];var edges:Array=[];var nearest:=Vector3.ZERO;var best:=INF;var edge_index:=-1
 for street:Dictionary in game.road_palette.prepared_streets:
  var a:Vector3=street.ends[0];var b:Vector3=street.ends[1]
  if a.distance_to(center)>150 or b.distance_to(center)>150:continue
  var ids:Array[int]=[]
  for point:Vector3 in [a,b]:
   var id:=-1
   for i in nodes.size():
    if Vector2(point.x-nodes[i].x,point.z-nodes[i].z).length()<0.1:id=i;break
   if id<0:id=nodes.size();nodes.append(point)
   ids.append(id)
  edges.append(ids)
  var span:=b-a;var q:Vector3=a+span*clampf((approach-a).dot(span)/span.length_squared(),0,1)
  var distance:float=Vector2(q.x-approach.x,q.z-approach.z).length()
  if distance<best:best=distance;nearest=q;edge_index=edges.size()-1
 # Split saved segments at endpoints on other segments, the arterial origin,
 # and the entrance projection. An intersection need not be a segment endpoint.
 var start:=nodes.size();nodes.append(center)
 var destination:=nodes.size();nodes.append(nearest)
 var split_edges:Array=[]
 for edge:Array in edges:
  var a:Vector3=nodes[edge[0]];var b:Vector3=nodes[edge[1]];var span:=b-a
  var on_line:Array=[]
  for i in nodes.size():
   var t:float=(nodes[i]-a).dot(span)/span.length_squared()
   if t>=-0.001 and t<=1.001 and nodes[i].distance_to(a+span*t)<0.1:on_line.append({"id":i,"t":t})
  on_line.sort_custom(func(a,b):return a.t<b.t)
  for i in range(1,on_line.size()):split_edges.append([on_line[i-1].id,on_line[i].id])
 edges=split_edges
 if not check(edge_index>=0 and edges.any(func(edge):return start in edge),"saved street graph connects arterial origin"):await done();return
 var previous:Dictionary={start:-1};var queue:Array[int]=[start];var goal:=-1
 while not queue.is_empty():
  var node:int=queue.pop_front()
  if node==destination:goal=node;break
  for edge:Array in edges:
   if node not in edge:continue
   var other:int=edge[1] if edge[0]==node else edge[0]
   if not previous.has(other):previous[other]=node;queue.append(other)
 if not check(goal>=0,"street graph reaches selected entrance frontage"):await done();return
 var route:Array[Vector3]=[]
 while goal>=0:route.push_front(nodes[goal]);goal=previous[goal]
 route.append(approach)
 for point:Vector3 in route:
  var reached:bool=await ground_walk(point);trace.append({"target":point,"position":game.player.position,"reached":reached})
  if not check(reached,"walk connected street waypoint "+str(point)):await done();return
 if not check(await go(door.pose,Vector3(0.5,0,0.8)),"walk entrance steps from street"):await done();return
 game.camera.look_at(door.pose*Vector3(0.5,1,0));use()
 if not check(game.doors.state.is_open(door.id),"open destination door"):await done();return
 for tick in 15:await physics_frame
 check(await go(door.pose,Vector3(0.5,0,-1.5)),"enter building from arterial without teleport")
 await done()
func done()->void:
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://reports/regional_connected_access.png")
 FileAccess.open("res://reports/regional_connected_access.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"trace":trace},"  "))
 print("REGIONAL_CONNECTED_ACCESS failures=",failures)
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();quit(1 if failures else 0)
