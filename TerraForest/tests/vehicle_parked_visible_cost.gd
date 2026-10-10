# SPDX-License-Identifier: 0BSD
extends "res://tests/actor_population_cost.gd"
func run() -> void:
 Engine.max_fps=60
 GDExtensionManager.load_extension("res://addons/vehicle_runtime/vehicle_runtime.gdextension")
 var scene:=Node3D.new();root.add_child(scene)
 var camera:=Camera3D.new();scene.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=65
 var center:=Vector3(800,50,800)
 camera.position=center+Vector3(0,65,25);camera.look_at(center);camera.current=true
 var light:=DirectionalLight3D.new();scene.add_child(light);light.rotation_degrees=Vector3(-65,-25,0);light.shadow_enabled=true
 var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color(0.15,0.18,0.22);environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=0.5;scene.add_child(environment)
 var floor_mesh:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(70,60);floor_mesh.mesh=plane;floor_mesh.position=center-Vector3.UP;scene.add_child(floor_mesh)
 var car=load("res://vehicle_demo/scenes/car.tscn").instantiate();scene.add_child(car);car.freeze=true;car.set_physics_process(false);car.set_controls_enabled(false);car.collision_layer=0;car.collision_mask=0
 var parts: Array=[]
 for node: MeshInstance3D in car.find_children("*","MeshInstance3D",true,false):
  if node.mesh!=null and node.is_visible_in_tree():parts.append({"mesh":node.mesh,"transform":car.global_transform.affine_inverse()*node.global_transform,"material":node.material_override})
 var fleet: RefCounted=ClassDB.instantiate("NativeVehicleFleet")
 var renderer: Node3D=ClassDB.instantiate("NativeParkedVehicleRenderer");scene.add_child(renderer)
 check(renderer.configure(fleet,parts,64),"actual car prototype configures")
 car.hide()
 var viewport:=root.get_viewport_rid();RenderingServer.viewport_set_measure_render_time(viewport,true)
 var folder:="res://reports/vehicle_parked_visible_cost";DirAccess.make_dir_recursive_absolute(folder)
 for count in [0,1,16,64]:
  while fleet.statistics().records<count:
   var i: int=fleet.statistics().records
   var point:=center+Vector3((i%8-3.5)*6,0,(i/8-3.5)*6)
   fleet.spawn(Transform3D(Basis.IDENTITY,point))
   for corner in [Vector3(-3,0,-3),Vector3(3,0,3),Vector3(-3,2,3),Vector3(3,2,-3)]:
    check(not camera.is_position_behind(point+corner) and Rect2(Vector2.ZERO,root.get_visible_rect().size).has_point(camera.unproject_position(point+corner)),"vehicle %d bounds in view"%i)
  var result: Dictionary=renderer.refresh(center,128,PackedInt64Array(),4096)
  check(result.rendered==count,"all %d records represented"%count)
  for tick in 30:await process_frame
  var rows: Array=[];var previous:=Time.get_ticks_usec()
  for tick in 120:
   await process_frame;await RenderingServer.frame_post_draw
   var now:=Time.get_ticks_usec()
   rows.append({"frame_ms":(now-previous)/1000.0,"gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(viewport),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)});previous=now
  var stats: Dictionary={}
  for field in ["frame_ms","gpu_ms","draw_calls","primitives"]:stats[field]=summary(rows,field)
  phases.append({"count":count,"rows":rows,"summary":stats})
  check(stats.frame_ms.p95<=18.5,"%d visible frame p95 <=18.5ms"%count)
  print(count," visible ",JSON.stringify(stats))
  root.get_texture().get_image().save_png(folder+"/%d.png"%count)
 var file:=FileAccess.open(folder+"/result.json",FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failures,"parts":parts.size(),"phases":phases},"  "));file.close()
 scene.free();await process_frame;quit(1 if failures else 0)
