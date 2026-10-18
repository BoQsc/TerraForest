# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,label: String)->bool:
 print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
 return ok
func _initialize()->void:run.call_deferred()
func move_to(player: CharacterBody3D,movement: RefCounted,target: Vector3)->bool:
 for tick in 360:
  await physics_frame
  var direction:=target-player.position;direction.y=0
  if direction.length()<.12 and absf(player.position.y-target.y)<.15 and player.is_on_floor():return true
  player.velocity=movement.walking_velocity(direction.normalized() if direction.length()>.12 else Vector3.ZERO,player.velocity,1.0/60,false,player.is_on_floor(),false)
  movement.move_grounded(player,1.0/60)
 return false
func run()->void:
 var metal_rails: bool="--metal-rails" in OS.get_cmdline_user_args()
 var wood: int=56 if metal_rails else 92
 Engine.max_fps=60
 var world=preload("res://addons/structures/structures_world.gd").new();root.add_child(world)
 check(world.prepare(),"native bridge world prepares")
 var entry: Dictionary=preload("res://addons/structures/guardrail_catalog.gd").register(world)
 var bridge: Resource=preload("res://addons/structures/bridge_catalog.gd").footbridge(metal_rails)
 check(bridge!=null and bridge.get_cell_count()==wood and bridge.get_model_attachments().size()==(6 if metal_rails else 0),"bridge has expected editable blocks and railing attachments")
 var inventory=ClassDB.instantiate("NativePlayerInventory")
 inventory.register_item(102,999);inventory.register_item(104,999)
 inventory.grant(102,wood,0)
 if metal_rails:inventory.grant(104,24,inventory.snapshot().revision)
 var builder=preload("res://addons/player_runtime/construction_inventory.gd").new();builder.gameplay=true
 if not check(builder.place_prefab(world.blocks,inventory,bridge,Vector3i.ZERO,0,world.model_collections(),preload("res://addons/structures/construction_catalog.gd").recipes(),[]),"bridge places through paid native prefab transaction"):
  print(builder.reason);world.free();quit(1);return
 check(inventory.snapshot().slots[0].count==0 and inventory.snapshot().slots[1].count==0,"bridge consumes exact wood and railing metal")
 var banks:=PackedInt32Array()
 for x in range(-4,4):
  for z in range(-5,17):
   if z<0 or z>=12:banks.append_array(PackedInt32Array([x,-1,z,65]))
 check(world.blocks.set_cells(banks),"two separate banks leave an unsupported 12 m gap")
 world.blocks.flush_bakes();world.set_model_focus(Vector3(0,1,6))
 for i in 20:await physics_frame
 check(world.is_collision_region_ready(AABB(Vector3(-4,-1,-5),Vector3(8,4,22))),"bridge and approach collision resident")
 var player:=CharacterBody3D.new();player.collision_mask=2;player.floor_snap_length=.35;player.floor_max_angle=deg_to_rad(48);player.floor_constant_speed=true;player.safe_margin=.01
 var collider:=CollisionShape3D.new();var capsule:=CapsuleShape3D.new();capsule.radius=.34;capsule.height=1.8;collider.shape=capsule;collider.position.y=.9;player.add_child(collider);root.add_child(player)
 var movement: RefCounted=ClassDB.instantiate("NativePlayerMovement")
 player.position=Vector3(.5,.05,-3)
 check(await move_to(player,movement,Vector3(.5,1,6)),"walks from bank up stairs to midspan without jumping")
 check(await move_to(player,movement,Vector3(.5,0,15)),"walks across the gap and down far stairs")
 check(await move_to(player,movement,Vector3(.5,0,-3)),"returns across bridge without jumping")
 player.position=Vector3(0,1.02,6);player.velocity=Vector3.ZERO
 for i in 75:
  await physics_frame
  player.velocity=movement.walking_velocity(Vector3.RIGHT,player.velocity,1.0/60,false,player.is_on_floor(),false)
  movement.move_grounded(player,1.0/60)
 check(player.position.x<(1.7 if metal_rails else 1.5) and player.position.y>.9,"side rail prevents walking off the span")
 var saved: PackedByteArray=world.capture_snapshot()
 check(not saved.is_empty() and world.restore_snapshot(saved) and world.capture_snapshot()==saved,"compound save restores exact bridge blocks and rails")
 var prefab: Resource=world.blocks.capture_prefab(Vector3i(-2,0,-1),Vector3i(4,3,14))
 check(prefab!=null and prefab.get_cell_count()==wood,"bridge remains individually editable and capturable")
 var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("91abb8");environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.65;root.add_child(environment)
 var sun:=DirectionalLight3D.new();root.add_child(sun);sun.rotation_degrees=Vector3(-45,30,0)
 var camera:=Camera3D.new();root.add_child(camera);camera.position=Vector3(13,10,21);camera.look_at(Vector3(0,0,6));camera.current=true
 root.size=Vector2i(1920,1080);DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
 await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://reports/bridge_metal_traversal.png" if metal_rails else "res://reports/bridge_traversal.png")
 player.free();world.free();print("BRIDGE_TRAVERSAL failures=",failures);quit(1 if failures else 0)
