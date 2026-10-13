# SPDX-License-Identifier: 0BSD
extends SceneTree
var game
func _initialize():call_deferred("run")
func run():
 game=load("res://demo/world.tscn").instantiate();game.background_fps=60;root.add_child(game)
 var deadline:=Time.get_ticks_msec()+35000
 while not game.has_meta("water_bucket_review_ready") and Time.get_ticks_msec()<deadline:await process_frame
 if not game.has_meta("water_bucket_review_ready"):quit(1);return
 game.set_process(false);game.set_physics_process(false);game._clear_motion()
 var entry:Dictionary=game.lakes._lakes.values()[0]
 var center:=Vector3(entry.seed.x,entry.level,entry.seed.z)
 var start:=center+Vector3(3,4,0)
 var hit:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(start,start-Vector3.UP*20,1))
 if hit.is_empty():quit(1);return
 if not game.terrain.sculpt_sphere(hit.position-Vector3.UP*0.4,1.5):quit(1);return
 deadline=Time.get_ticks_msec()+10000
 while Time.get_ticks_msec()<deadline:
  await process_frame
  if not game.terrain.pending_edit and game.lakes.statistics().render_ready:break
 if game.terrain.pending_edit or not game.lakes.statistics().render_ready:quit(1);return
 game.camera.global_position=hit.position+Vector3(0,1.6,2)
 game.camera.look_at(hit.position-Vector3.UP*.4,Vector3.UP)
 game.water_camera.update()
 print("UNDERWATER_DEPTH ",game.lakes.depth_at(game.camera.global_position))
 var shader:Shader=game.lakes._material.shader
 var installed:=shader.code
 var frames:Array[Image]=[]
 for underside_ripples:bool in [true,false]:
  for phase in [0.0,20.0]:
   var code:String=installed.replace("max(n.y, 0.0)","abs(n.y)") if underside_ripples else installed
   shader.code=code.replace("TIME",str(phase))
   for frame in 8:await process_frame
   await RenderingServer.frame_post_draw
   frames.append(root.get_texture().get_image())
 shader.code=installed
 frames[0].save_png("res://reports/water_underside_before.png")
 frames[2].save_png("res://reports/water_underside_after.png")
 var variation:Array[float]=[0.0,0.0];var samples:=0
 # Exposed downward-facing water above the newly excavated floor, no HUD.
 for y in range(300,440,3):
  for x in range(650,1150,3):
   for pair in 2:
    var a:=frames[pair*2].get_pixel(x,y);var b:=frames[pair*2+1].get_pixel(x,y)
    variation[pair]+=absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)
   samples+=3
 for i in 2:variation[i]=variation[i]*255/samples
 var ok:bool=variation[0]>0.1 and variation[1]<variation[0]*0.15
 var report:Dictionary={"failures":0 if ok else 1,"before_phase_difference":variation[0],"after_phase_difference":variation[1],"scope":"Fixed actual-world excavation view; downward-facing surface ROI under two ripple phases"}
 var file:=FileAccess.open("res://reports/water_underside_visual.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
 print(JSON.stringify(report))
 game.terrain.shutdown();game.queue_free();await process_frame;await process_frame
 print("WATER_UNDERSIDE_VISUAL failures=",0 if ok else 1);quit(0 if ok else 1)
