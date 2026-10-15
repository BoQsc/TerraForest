# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,label: String)->void:
 print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
func _initialize()->void:run.call_deferred()
func run()->void:
 Engine.max_fps=60
 var world: Node3D=ClassDB.instantiate("NativeBlockWorld");root.add_child(world)
 var inventory=ClassDB.instantiate("NativePlayerInventory")
 var coordinator=preload("res://addons/player_runtime/construction_inventory.gd").new();coordinator.gameplay=true
 for material in 4:inventory.register_item(101+material,64)
 for material in 4:
  check(inventory.grant(101+material,4,inventory.snapshot().revision).ok,"grant column materials")
  for rotation in 4:
   check(coordinator.place_block(world,inventory,Vector3i(material*3,0,rotation*3),7+rotation*8+material*32),"paid column material %d rotation %d"%[material,rotation])
 check(inventory.snapshot().slots[0].count==0,"column placement debits material")
 world.flush_bakes();world.set_process(false)
 await physics_frame
 await physics_frame
 var preview: Mesh=world.preview_mesh(7,0)
 var arrays: Array=preview.surface_get_arrays(0)
 var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
 var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
 var valid:=indices.size()==144
 for i in range(0,indices.size(),3):
  var a:=vertices[indices[i]];var b:=vertices[indices[i+1]];var c:=vertices[indices[i+2]]
  valid=valid and (c-a).cross(b-a).dot((a+b+c)/3.0-Vector3(.5,.5,.5))>0.00001
 check(valid,"48 nondegenerate outward-facing triangles")
 for material in 4:
  for rotation in 4:
   var offset:=Vector3(material*3,0,rotation*3)
   for ray in [[Vector3(.5,2,.5),Vector3(.5,-1,.5)],[Vector3(-1,.5,.5),Vector3(2,.5,.5)],[Vector3(-1,.5,.25),Vector3(2,.5,.25)]]:
    var start: Vector3=offset+ray[0];var end: Vector3=offset+ray[1]
    var authored: Dictionary=world.raycast_cells(start,end)
    var physics: Dictionary=world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(start,end,2))
    check(not authored.is_empty() and not physics.is_empty() and authored.position.distance_to(physics.position)<.001,"rendered collision matches authoritative cylinder")
 check(world.raycast_cells(Vector3(.97,5,.97),Vector3(.97,-1,.97)).is_empty(),"column corners remain empty")
 world.configure_history(1048576,16)
 check(world.set_cells(PackedInt32Array([0,0,0,0])) and world.get_cell(Vector3i.ZERO)==0,"column removes through normal block editing")
 check(world.undo() and world.get_cell(Vector3i.ZERO)==7,"undo restores column word")
 var snapshot: PackedByteArray=world.capture_snapshot()
 var restored=ClassDB.instantiate("NativeBlockWorld")
 check(restored.restore_snapshot(snapshot) and restored.capture_snapshot()==snapshot,"all cylinder words survive snapshot restore exactly")
 var prefab=world.capture_prefab(Vector3i.ZERO,Vector3i(10,1,10))
 check(restored.place_prefab(prefab,Vector3i(0,0,20),1),"captured columns compose as rotated prefab")
 restored.free()
 var camera:=Camera3D.new();root.add_child(camera);camera.position=Vector3(15,13,18);camera.look_at(Vector3(4.5,0,4.5));camera.current=true
 var sun:=DirectionalLight3D.new();root.add_child(sun);sun.rotation_degrees=Vector3(-40,-25,0)
 var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color(.16,.19,.23);environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.5;root.add_child(environment)
 if DisplayServer.get_name()!="headless":
  root.size=Vector2i(1920,1080)
  DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
  await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://reports/block_cylinder.png")
 world.free()
 print("BLOCK_CYLINDER failures=",failures);quit(1 if failures else 0)
