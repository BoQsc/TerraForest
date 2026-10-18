# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var failures:=0
func check(ok:bool,label:String)->void:
 print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
func _initialize()->void:run.call_deferred()
func run()->void:
 var game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;root.add_child(game)
 var deadline:=Time.get_ticks_msec()+60000
 while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
 if game.loading_active or game.terrain.backend.world_generator!=8:quit(1);return
 game.set_physics_process(false);game._clear_motion()
 var core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[game.terrain.backend.world_seed,8]))
 var desc:PackedByteArray=core.execute(Codec.command(25));var at:=24+2*28
 var center:=Vector3(desc.decode_float(at),desc.decode_float(at+4),desc.decode_float(at+8))
 game.teleport(center+Vector3(0,3,0))
 deadline=Time.get_ticks_msec()+45000
 while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
 check(not game.loading_active,"actual saved world streams the chamber through normal loading")
 for i in 60:await physics_frame
 var supported:=true
 for x in [-15,0,15]:
  for z in [-15,0,15]:
   var p:=center+Vector3(x,4,z)
   var hit:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(p,p-Vector3.UP*8,1))
   supported=supported and not hit.is_empty()
   if not hit.is_empty():supported=supported and absf(hit.position.y-center.y)<0.2 and hit.normal.y>0.98
 check(supported,"nine real physics rays find a level thirty-metre-wide chamber floor")
 game.player.position=center+Vector3(20,2,0);game.camera.position=Vector3(0,1.6,0)
 game.camera.look_at(center+Vector3(30,8,-5));game.headlamp.visible=true
 for i in 30:await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://reports/chamber_headlamp.png")
 # Explicit test-only fill exposes the chamber geometry for visual inspection.
 var inspection:=OmniLight3D.new();inspection.omni_range=75;inspection.light_energy=3;inspection.shadow_enabled=false
 game.add_child(inspection);inspection.global_position=center+Vector3(0,18,0)
 game.camera.global_position=center+Vector3(20,10,20);game.camera.look_at(center+Vector3(-10,12,-10))
 for i in 30:await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://reports/chamber_geometry_inspection.png")
 print("CHAMBER_WORLD failures=",failures," center=",center)
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;quit(1 if failures else 0)
