# SPDX-License-Identifier: 0BSD
extends "res://tests/actor_navigation.gd"
func run()->void:
 Engine.max_fps=60
 var scene:=Node3D.new();root.add_child(scene)
 var blocks: Node3D=ClassDB.instantiate("NativeBlockWorld");scene.add_child(blocks)
 var bridge: Resource=preload("res://addons/structures/bridge_catalog.gd").footbridge()
 check(blocks.place_prefab(bridge,Vector3i.ZERO,0),"production bridge prefab placed")
 var banks:=PackedInt32Array()
 for x in range(-4,4):
  for z in range(-5,17):
   if z<0 or z>=12:banks.append_array(PackedInt32Array([x,-1,z,65]))
 blocks.set_cells(banks);blocks.flush_bakes()
 for i in 4:await physics_frame
 var persistence=preload("res://addons/world_runtime/world_persistence.gd").new()
 actors=preload("res://addons/world_runtime/actor_world.gd").new();scene.add_child(actors)
 var opposing: bool="--opposing" in OS.get_cmdline_user_args()
 check(actors.prepare(persistence) and actors.enable(2 if opposing else 1),"bounded actor world prepares")
 var start:=Vector3(0,.93,-2);var end:=Vector3(0,.93,14)
 var id: int=actors.spawn(start);var handle: int=actors.store.resolve_identity(id)
 check(actors.orders.set_patrol(id,end),"patrol spans both bridge approaches")
 var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("91abb8");environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.65;scene.add_child(environment)
 var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-45,30,0);scene.add_child(sun)
 var camera:=Camera3D.new();scene.add_child(camera);camera.position=Vector3(14,12,22);camera.look_at(Vector3(0,1,6));camera.current=true
 var ids:Array[int]=[id];var actor_handles:Array[int]=[handle];var completed:Array[int]=[0];var previous:Array[Vector3]=[end]
 if opposing:
  var other: int=actors.spawn(end);ids.append(other);actor_handles.append(actors.store.resolve_identity(other));completed.append(0);previous.append(start)
  check(actors.orders.set_patrol(other,start),"opposing actor receives reverse patrol")
 var legs:=0;var minimum_height:=100.0;var minimum_separation:=100.0;var peak_work:=0;var trace:Array=[]
 for tick in 1680:
  await physics_frame
  actors.update_simulation(1.0/60,Vector3(0,1,6),true,func(bounds: AABB):return blocks.is_collision_region_ready(bounds))
  var positions:Array[Vector3]=[];var statuses:Array=[]
  for i in ids.size():
   var position: Vector3=actors.store.get_position(actor_handles[i]);positions.append(position)
   minimum_height=minf(minimum_height,position.y)
   var target: Vector3=actors.orders.get_target(ids[i]).target
   if target!=previous[i]:completed[i]+=1;previous[i]=target
   statuses.append(actors.pool.navigation_status(actor_handles[i]))
  if opposing:
   # Capsule centres can differ in height on stairs. Measure distance between
   # their vertical centre segments, not full centre-to-centre distance.
   var offset:=positions[0]-positions[1];offset.y=maxf(0,absf(offset.y)-1.1)
   minimum_separation=minf(minimum_separation,offset.length())
  legs=completed.min()
  peak_work=maxi(peak_work,int(actors.simulation_status.get("route_work",0)))
  if tick%30==0:trace.append({"frame":tick,"positions":positions,"routes":statuses,"completed":completed.duplicate()})
  if legs>=2:break
 check(legs>=2,"actor climbs bridge stairs crosses and returns on patrol")
 check(minimum_height>.85,"actor never falls through deck or banks")
 check(peak_work<=12 and int(actors.status.get("active",0))<=(2 if opposing else 1),"existing route-work and active-body budgets retained")
 if opposing:check(minimum_separation>=.699,"opposing capsules do not overlap during crossing")
 root.size=Vector2i(1920,1080);DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
 await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://reports/actor_bridge.png")
 FileAccess.open("res://reports/actor_bridge.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"legs":legs,"minimum_height":minimum_height,"peak_route_work":peak_work,"opposing":opposing,"completed":completed,"minimum_separation":minimum_separation,"trace":trace},"  "))
 scene.free();await process_frame
 print("ACTOR_BRIDGE legs=",legs," failures=",failures);quit(1 if failures else 0)
