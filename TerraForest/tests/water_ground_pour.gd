# SPDX-License-Identifier: 0BSD
extends SceneTree
var game:Node3D
var failures:=0
var results:Dictionary={}
func check(ok:bool,label:String):
 print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
func _initialize():call_deferred("run")
func click(button:int):
 game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
 var event:=InputEventMouseButton.new();event.button_index=button;event.pressed=true;game._unhandled_input(event)
func aim(point:Vector3):
 game.fly=true;game.needs_floor_spawn=false;game._clear_motion()
 game.pitch=-PI/2;game.yaw=0;game.player.rotation.y=0
 game.camera.global_position=point+Vector3.UP*1.6;game.camera.look_at(point,Vector3.FORWARD)
func run():
 game=load("res://demo/world.tscn").instantiate();root.add_child(game)
 var deadline:=Time.get_ticks_msec()+35000
 while not game.has_meta("water_bucket_review_ready") and Time.get_ticks_msec()<deadline:await process_frame
 check(game.has_meta("water_bucket_review_ready") and game.temporary_world,"Normal disposable bucket-review world is ready")
 if failures:await finish();return
 var total:int=game.lakes.statistics().water_ml
 click(MOUSE_BUTTON_LEFT)
 check(game.player_hud.active_item==411 and game.lakes.statistics().water_ml==total-10000,"One actual click fills the full bucket from the lake")
 if failures:await finish();return
 var origin:Vector3=game.player.global_position+Vector3(0,0,10)
 var ground:Dictionary={}
 # Select the gentlest of nine nearby natural surfaces; never sculpt a basin.
 for z in [-2,0,2]:
  for x in [-2,0,2]:
   var p:=origin+Vector3(x,0,z)
   var candidate:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(p+Vector3.UP*30,p-Vector3.UP*30,1))
   if not candidate.is_empty() and (ground.is_empty() or candidate.normal.y>ground.normal.y):ground=candidate
 check(not ground.is_empty(),"Untouched ground is available outside the authored lake")
 if failures:await finish();return
 var target:Vector3=ground.position;results.target=[target.x,target.y,target.z];results.slope_degrees=rad_to_deg(acos(ground.normal.y))
 check(not game.lakes.water.surface_near(target,3.0).is_finite(),"Pour target starts dry and is separate from the lake")
 if failures:await finish();return
 var before_pour:PackedByteArray=game.lakes.capture_snapshot()
 aim(target);click(MOUSE_BUTTON_RIGHT)
 deadline=Time.get_ticks_msec()+6000
 while game.player_hud.active_item!=401 and Time.get_ticks_msec()<deadline:await process_frame
 check(game.player_hud.active_item==401 and game.lakes.statistics().water_ml==total,"Actual right-click pours all ten litres onto unedited ground")
 if failures:await finish();return
 var initial_file:=FileAccess.open("res://reports/water_ground_initial.bin",FileAccess.WRITE)
 initial_file.store_buffer(game.lakes.capture_snapshot());initial_file.close()
 # Let normal simulation run for two seconds, rather than inspecting only the
 # immediate pour frame or freezing the water before it can leave the target.
 var started:=Time.get_ticks_msec()
 while Time.get_ticks_msec()-started<2000:await process_frame
 results.surface_contact=surface_contact(target)
 check(results.surface_contact.samples>0 and results.surface_contact.below_ground==0,"Sampled rendered pour triangles stay above actual terrain")
 results.after_two_seconds=game.lakes.statistics()
 results.water_delta=water_delta(before_pour,game.lakes.capture_snapshot(),target)
 results.local_components=local_components(results.water_delta.new_wet_cells)
 check(results.local_components.components.size()==1,"Gentle-ground full-bucket pour remains one connected body, without detached small pieces")
 var final_file:=FileAccess.open("res://reports/water_ground_after.bin",FileAccess.WRITE)
 final_file.store_buffer(game.lakes.capture_snapshot());final_file.close()
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://reports/water_ground_pour_target.png")
 # Aim inside the largest nearby wet footprint. The nearest point to the old
 # pour location can be a moving, almost-dry edge and is not a stable scoop aim.
 var surface:=Vector3.INF;var largest:=0
 for row:Dictionary in results.water_delta.new_wet_cells:
  if row.distance_m>3.0 or row.ml<=largest:continue
  var center:Vector3=row.geometry.wet_centroid
  center.y=row.geometry.head
  var hit:Dictionary=game.lakes.water.raycast_surface(center+Vector3.UP,center-Vector3.UP)
  if hit.hit and hit.normal.y>0.5:surface=hit.point;largest=row.ml
 check(surface.is_finite(),"Poured water remains visibly queryable near the natural-ground target after two seconds")
 if not surface.is_finite():await finish();return
 results.displacement_m=target.distance_to(surface)
 aim(surface)
 for frame in 3:await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://reports/water_ground_pour.png")
 var from:Vector3=game.camera.global_position;var to:Vector3=from-game.camera.global_basis.z*3.5
 var water_hit:Dictionary=game.lakes.water.raycast_surface(from,to)
 var terrain_hit:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from,to,1))
 results.scoop_aim={"from":from,"water":water_hit,"terrain_point":terrain_hit.get("position",Vector3.INF),"statistics":game.lakes.statistics(),"nearby_now":game.lakes.water.surface_near(surface,0.3)}
 if water_hit.hit:results.scoop_aim.geometry=game.lakes.water.cell_geometry(Vector3(water_hit.cell)*0.5+Vector3.ONE*0.25)
 click(MOUSE_BUTTON_LEFT)
 var held:int=game.player_hud.active_item-401
 results.recovered_litres=held
 check(held>=1 and held<=10 and game.lakes.statistics().water_ml==total-held*1000,"The visible ground water can be scooped with exact inventory/world transfer")
 await finish()
func local_components(rows:Array) -> Dictionary:
 return preload("res://tests/water_coherence_probe.gd").components(game.lakes.water,rows)
func surface_contact(target:Vector3) -> Dictionary:
 var report:Dictionary={"samples":0,"below_ground":0,"min_gap":INF,"max_gap":-INF,"rows":[]}
 for instance:MeshInstance3D in game.lakes._meshes.values():
  if instance.mesh==null:continue
  var vertices:PackedVector3Array=instance.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
  for i in range(0,vertices.size(),3):
   var a:Vector3=vertices[i];var b:Vector3=vertices[i+1];var c:Vector3=vertices[i+2]
   if (c-a).cross(b-a).y<=0:continue
   var point:Vector3=(a+b+c)/3.0
   if point.distance_to(target)>3:continue
   var ground:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP,point-Vector3.UP,1))
   if ground.is_empty():continue
   var gap:float=point.y-ground.position.y
   report.samples+=1;report.min_gap=minf(report.min_gap,gap);report.max_gap=maxf(report.max_gap,gap)
   if gap<0:report.below_ground+=1
   report.rows.append({"point":point,"gap":gap,"vertices":[a,b,c]})
 print("GROUND_SURFACE_CONTACT ",report.samples," below=",report.below_ground," gap=",report.min_gap,"..",report.max_gap)
 return report
func amounts(bytes:PackedByteArray) -> Dictionary:
 var found:Dictionary={};var size:=9076 if bytes.decode_u32(4)>=2 else 6160
 for r in bytes.decode_u32(12):
  var base:int=32+bytes.decode_u32(8)+r*size;var key:int=bytes.decode_u64(base)
  var region:=Vector3i((key>>24)&4095,(key>>12)&4095,key&4095)
  for i in 512:
   var ml:int=bytes.decode_u64(base+20+i*12)&0x7fffffffffffffff
   if ml:found[region*8+Vector3i(i%8,(i/8)%8,i/64)]=ml
 return found
func water_delta(before:PackedByteArray,after:PackedByteArray,target:Vector3) -> Dictionary:
 var old:=amounts(before);var current:=amounts(after);var rows:Array=[]
 for p:Vector3i in current:
  var change:int=current[p]-old.get(p,0)
  if change<=0:continue
  var center:=Vector3(p)*0.5+Vector3.ONE*0.25
  # Lake refill is not poured water. Newly wet cells outside its earlier store
  # identify the separate ground pour without depending on its final position.
  if old.has(p):continue
  rows.append({"cell":[p.x,p.y,p.z],"ml":change,"distance_m":center.distance_to(target),"geometry":game.lakes.water.cell_geometry(center)})
 return {"new_wet_cells":rows}
func finish():
 results.failures=failures
 var file:=FileAccess.open("res://reports/water_ground_pour.json",FileAccess.WRITE);file.store_string(JSON.stringify(results,"  "));file.close()
 game.terrain.shutdown();game.queue_free();await process_frame;await process_frame
 print("WATER_GROUND_POUR failures=",failures);quit(failures)
