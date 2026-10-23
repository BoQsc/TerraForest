# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
var forest:Node
var structures:Node
var ecosystem:Node
const OUTPUT="res://reports/block_forest_continuity"
func rendered()->Dictionary:
 var result:Dictionary={}
 for cell:Dictionary in forest.renderer.cells.values():
  for tier in 5:
   var node:MultiMeshInstance3D=cell.nodes[tier]
   if node==null:continue
   var ids:Array=cell.slot_ids[tier]
   if not check(node.visible and node.multimesh.visible_instance_count==ids.size(),"tier %d visible prefix matches identities"%tier):continue
   for i in ids.size():
    result[Vector2i(ids[i],tier)]=[node.multimesh.get_instance_transform(i),node.multimesh.get_instance_custom_data(i)]
 return result
func capture(name:String)->void:
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(OUTPUT+"/"+name+".png")
func run()->void:
 DirAccess.make_dir_recursive_absolute(OUTPUT)
 var world:=Node3D.new();root.add_child(world)
 var camera:=Camera3D.new();world.add_child(camera);camera.position=Vector3(35,16,76);camera.look_at(Vector3(30,7,24));camera.current=true
 var light:=DirectionalLight3D.new();world.add_child(light);light.rotation_degrees=Vector3(-55,-30,0);light.shadow_enabled=true;light.directional_shadow_max_distance=160
 var environment:=WorldEnvironment.new();world.add_child(environment);environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color(.23,.34,.45);environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.25
 var floor_mesh:=MeshInstance3D.new();floor_mesh.mesh=PlaneMesh.new();floor_mesh.mesh.size=Vector2(360,360);world.add_child(floor_mesh)
 var floor_material:=StandardMaterial3D.new();floor_material.albedo_color=Color(.3,.35,.22);floor_mesh.material_override=floor_material
 structures=preload("res://addons/structures/structures_world.gd").new();world.add_child(structures);check(structures.prepare(),"native structures ready")
 forest=preload("res://addons/vegetation/vegetation_world.gd").new();world.add_child(forest);forest.camera=camera;forest.wind_strength=0
 check(forest.enable_trunk_collision() and forest.initialize()==OK,"production forest ready")
 ecosystem=preload("res://addons/world_ecosystem/world_ecosystem.gd").new();ecosystem.structures=structures;ecosystem.vegetation=forest;structures.vegetation_changed.connect(ecosystem._structure_region_changed)
 var transforms:Array[Transform3D]=[];var ids:=PackedInt64Array()
 for z in 4:
  for x in 4:
   ids.append(1+ids.size());transforms.append(Transform3D(Basis.IDENTITY,Vector3(8+x*16,0,8+z*16)))
 ecosystem._samples[Vector2i.ZERO]={"ids":ids,"transforms":transforms,"active":PackedInt64Array(),"published":false};ecosystem._publish_samples(Vector2i.ZERO)
 await create_timer(.5).timeout
 await capture("before")
 var before:=rendered();var before_roots:Dictionary=forest.renderer.roots.duplicate(true)
 check(before.size()>=32,"trees and near shadows rendered")
 check(structures.blocks.set_cells(PackedInt32Array([8,0,8,1])),"single block placed through native API")
 ecosystem._publish_samples(Vector2i.ZERO)
 check(forest.renderer.roots.size()==15 and not forest.renderer.roots.has(1),"only overlapping tree removed")
 for frame in 4:
  await capture("after_%d"%frame)
  var after:=rendered();var stable:=true
  for key:Vector2i in before:
   if key.x==1:continue
   stable=stable and after.has(key) and after[key]==before[key]
  check(stable,"frame %d survivor tree/shadow MultiMesh transforms and fades unchanged"%frame)
  var poses_unchanged:=true
  for id in forest.renderer.roots:poses_unchanged=poses_unchanged and forest.renderer.roots[id].t==before_roots[id].t
  check(poses_unchanged,"all surviving root poses unchanged")
 print("BLOCK_FOREST_CONTINUITY ",{"failures":failures,"before_rows":before.size(),"after_roots":forest.renderer.roots.size(),"scope":"production native block exclusion, real forest renderer and per-frame MultiMesh records"})
 structures.vegetation_changed.disconnect(ecosystem._structure_region_changed);ecosystem.free();world.queue_free();await process_frame;quit(1 if failures else 0)
