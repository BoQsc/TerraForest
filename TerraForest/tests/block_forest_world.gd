# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
const OUTPUT="res://reports/block_forest_world"
func rendered()->Dictionary:
 var result:Dictionary={}
 for cell:Dictionary in game.vegetation.renderer.cells.values():
  for tier in 5:
   var node:MultiMeshInstance3D=cell.nodes[tier]
   if node==null:continue
   var ids:Array=cell.slot_ids[tier]
   if not node.visible or node.multimesh.visible_instance_count!=ids.size():result[Vector2i(-1,tier)]=[]
   for i in ids.size():result[Vector2i(ids[i],tier)]=[node.multimesh.get_instance_transform(i),node.multimesh.get_instance_custom_data(i)]
 return result
func settled()->bool:
 var eco=game.ecosystem
 return eco.resident.size()==eco._wanted.size() and eco._requests.is_empty() and eco._reconcile.is_empty() and eco._resample.is_empty()
func finish()->void:
 print("BLOCK_FOREST_WORLD failures=",failures)
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;quit(1 if failures else 0)
func run()->void:
 DirAccess.make_dir_recursive_absolute(OUTPUT)
 game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;game.max_fps=60;root.add_child(game)
 if not check(await wait_for(func():return not game.loading_active,60),"world ready"):await finish();return
 game.set_physics_process(false);game._clear_motion();game.vegetation.wind_strength=0
 if not check(await wait_for(settled,15),"forest settles before construction"):await finish();return
 var forest=game.vegetation.renderer
 var target_id:int=forest.roots.keys()[0]
 for id:int in forest.roots:
  if forest.roots[id].t.origin.distance_squared_to(game.camera.global_position)<forest.roots[target_id].t.origin.distance_squared_to(game.camera.global_position):target_id=id
 var target:Vector3=forest.roots[target_id].t.origin
 # Place beside the tree, outside its solid trunk, while still beneath its canopy.
 target+=Vector3(3,0,0)
 game.camera.global_position=target+Vector3(0,2.5,2);game.camera.look_at(target+Vector3(0,.5,0));game.app_focused=true
 if game.session_menu.developer:game.session_menu.toggle_developer()
 game.session_menu.set_open(false);Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
 game.player_hud.equip(4)
 check(game.player_hud.active_item==101 and game.structure_mode,"slot 5 equips brick in gameplay")
 await create_timer(.4).timeout
 if not check(await wait_for(settled,10),"camera residency settles before baseline"):await finish();return
 await create_timer(.4).timeout
 var before:Dictionary=forest.roots.duplicate(true)
 var count:int=before.size();check(count>100,"natural forest present")
 var before_gpu:=rendered()
 var before_revision:int=forest.canopy_revision
 var before_rebuilds:int=forest.stats.full_rebuilds
 var hit:Dictionary=game._structure_target(false)
 if not check(not hit.is_empty(),"actual terrain placement ray hits"):await finish();return
 var cell:Vector3i=hit.target
 var expected:Dictionary={};var bounds:=AABB(Vector3(cell),Vector3.ONE)
 var old_canopy:Dictionary={}
 for id:int in before:
  if (before[id].t*game.vegetation.assets.meshes[0].get_aabb().grow(2)).intersects(bounds):old_canopy[id]=true
  if (before[id].t*AABB(Vector3(-.35,0,-.35),Vector3(.7,8,.7))).intersects(bounds):expected[id]=true
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(OUTPUT+"/before.png")
 var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_RIGHT;click.pressed=true
 game._unhandled_input(click)
 check(game.structures.blocks.get_cell(cell)==1,"actual gameplay construction placed one block")
 if not check(await wait_for(settled,8),"bounded exclusion settles"):await finish();return
 var removed:Array=[];var unexpected:Array=[]
 for id:int in before:
  if not forest.roots.has(id):
   removed.append(id)
   if not expected.has(id):unexpected.append(id)
 print("BLOCK_FOREST_COUNTS ",{"before":count,"after":forest.roots.size(),"expected_removed":expected.keys(),"canopy_overlap":old_canopy.keys(),"removed":removed,"unexpected":unexpected,"cell":cell,"rejected":game.ecosystem.rejected_batches})
 check(not old_canopy.is_empty() and expected.is_empty(),"fixture is beneath nearby crowns and clear of every solid trunk")
 check(unexpected.is_empty() and removed.size()==expected.size(),"brick below branches preserves every tree")
 for frame in 4:
  await RenderingServer.frame_post_draw
  check(rendered()==before_gpu,"frame %d preserves every tree and shadow MultiMesh record"%frame)
 check(forest.canopy_revision==before_revision and forest.stats.full_rebuilds==before_rebuilds,"canopy-only overlap triggers no forest or shadow-mask rebuild")
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(OUTPUT+"/after.png")
 FileAccess.open(OUTPUT+"/result.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"before":count,"after":forest.roots.size(),"canopy_overlaps":old_canopy.size(),"unexpected_removed":unexpected,"rendered_records":before_gpu.size(),"scope":"Character Preview flags; real slot-5 brick, paid inventory debit, right-click input, native exclusion, rendered survivor records and shadows at 1920x1080."},"  "))
 await finish()
