# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,label: String) -> void:
 print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
func _initialize() -> void:run.call_deferred()
func run() -> void:
 GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
 var store: RefCounted=ClassDB.instantiate("NativeEntityStore");store.configure(16)
 var id: int=store.spawn(Vector3.ZERO,Vector3.ZERO)
 var renderer: MultiMeshInstance3D=ClassDB.instantiate("NativeEntityRenderer");root.add_child(renderer)
 var mesh=load("res://addons/world_runtime/actor_mesh.gd").build()
 check(mesh.get_faces().size()==216,"shared six-part mesh has 72 triangles")
 check(renderer.configure(store,mesh,16,true),"animated instance layout configured")
 renderer.refresh(Vector3.ZERO,10,32)
 check(renderer.refresh_animated_positions(0.05).upload_bytes==0,"idle actor uploads nothing")
 store.set_position(id,Vector3(0.125,0,0));renderer.refresh_animated_positions(0.05)
 var data: Color=renderer.multimesh.get_instance_custom_data(0)
 check(is_equal_approx(data.r,0.5) and is_equal_approx(data.g,1),"actual displacement drives bounded phase and stride")
 check((-renderer.multimesh.get_instance_transform(0).basis.z).is_equal_approx(Vector3.RIGHT),"actor faces movement direction")
 renderer.refresh_animated_positions(0.05)
 check(renderer.multimesh.get_instance_custom_data(0).g==0,"stopped actor returns to idle")
 check(renderer.refresh_animated_positions(0.05).upload_bytes==0,"settled idle does not repeatedly upload")
 check(not renderer.refresh_animated_positions(NAN).ok,"invalid animation delta rejected")
 store.set_position(id,Vector3(5,0,0));renderer.refresh_animated_positions(0.05)
 data=renderer.multimesh.get_instance_custom_data(0)
 check(data.r==0 and data.g==0,"teleport resets gait without exaggerated stride")
 store.set_position(id,Vector3(5.125,0,0));renderer.refresh_animated_positions(0.05)
 renderer.refresh(Vector3(NAN,0,0),0,1)
 store.set_position(id,Vector3.ZERO);renderer.refresh(Vector3.ZERO,10,32)
 check(renderer.multimesh.get_instance_custom_data(0).r==0,"readmission starts clean gait state")
 var camera:=Camera3D.new();root.add_child(camera);camera.position=Vector3(3,0.8,1.4);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=3;camera.look_at(Vector3.ZERO);camera.current=true
 var light:=DirectionalLight3D.new();root.add_child(light);light.rotation_degrees=Vector3(-40,-30,0)
 Engine.max_fps=60
 store.set_position(id,Vector3(0,0,-0.25));renderer.refresh_animated_positions(0.1)
 for frame in 5:await process_frame
 await RenderingServer.frame_post_draw
 DirAccess.make_dir_recursive_absolute("res://reports")
 var walking:=root.get_texture().get_image()
 walking.save_png("res://reports/entity_gait.png")
 renderer.refresh_animated_positions(0.1)
 for frame in 5:await process_frame
 await RenderingServer.frame_post_draw
 var idle:=root.get_texture().get_image();idle.save_png("res://reports/entity_gait_idle.png")
 var changed:=0
 for y in range(0,idle.get_height(),4):
  for x in range(0,idle.get_width(),4):
   if walking.get_pixel(x,y)!=idle.get_pixel(x,y):changed+=1
 check(changed>100,"walking limbs visibly differ from idle at identical position and camera: %d samples"%changed)
 check(renderer.get_child_count()==0,"animated population has no per-actor scene nodes")
 # Exercise renderer residency across more distinct handles than its capacity.
 store=ClassDB.instantiate("NativeEntityStore")
 check(store.configure(1024),"separate population store configured")
 var population: PackedInt64Array=store.spawn_grid(1024,Vector3.ZERO,4,Vector3.ZERO)
 check(population.size()==1024,"population fixture allocated all identities")
 if population.size()!=1024:quit(1);return
 renderer.configure(store,mesh,256,true)
 var bounded:=true
 for i in range(0,1024,64):
  var selected: Dictionary=renderer.refresh(store.get_position(population[i]),16,4096)
  bounded=bounded and selected.ok and selected.gait_states==selected.rendered and selected.gait_states<=256
 check(bounded,"gait memory follows current render selection across 1024 identities")
 var selection: Dictionary=renderer.refresh(Vector3(30,0,30),64,4096)
 check(selection.rendered==256,"cost fixture has exactly 256 rendered actors")
 if selection.rendered!=256:quit(1);return
 var samples: Array=[]
 for moving in [0,16,256]:
  var times: Array[float]=[];var upload_bytes:=0
  for frame in 130:
   for j in moving:
    var handle: int=selection.ids[j]
    store.set_position(handle,store.get_position(handle)+Vector3(0,0,-0.02))
   var start:=Time.get_ticks_usec()
   var result: Dictionary=renderer.refresh_animated_positions(1.0/60)
   var elapsed: float=(Time.get_ticks_usec()-start)/1000.0
   if frame>=10:times.append(elapsed);upload_bytes+=int(result.upload_bytes)
   await process_frame
  var raw:=times.duplicate();times.sort()
  var p95: float=times[113];var maximum: float=times[-1]
  check(p95<=1 and maximum<=2,"256 selected/%d moving renderer CPU p95 %.3f ms max %.3f ms (1/2 ms gates)"%[moving,p95,maximum])
  check(upload_bytes==(0 if moving==0 else 120*256*64),"unchanged idle skips uploads; motion stays within fixed buffer budget")
  samples.append({"moving":moving,"renderer_ms":raw,"p95_ms":p95,"max_ms":maximum,"upload_bytes":upload_bytes})
 var file:=FileAccess.open("res://reports/entity_gait.json",FileAccess.WRITE)
 file.store_string(JSON.stringify({"failures":failures,"samples":samples,"visual_changed_samples":changed,"gpu":RenderingServer.get_video_adapter_name(),"cpu":OS.get_processor_name(),"viewport":str(root.size),"scope":"Native renderer CPU call only; excludes store mutations, selection, physics, GPU execution and frame pacing. 256 selected instances; 120 measured calls per phase after 10 warmup. Not a visible crowd, full actor-cost or thermal qualification."},"  "));file.close()
 renderer.free();camera.free();light.free();await process_frame;quit(1 if failures else 0)
