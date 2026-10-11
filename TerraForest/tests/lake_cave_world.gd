# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var failures:=0
var game: Node
var messages: Array[String]=[]
func check(ok: bool,label: String):
 if not ok:failures+=1
 print(("PASS " if ok else "FAIL ")+label)
func wait_for(predicate: Callable,seconds: float=20) -> bool:
 var deadline=Time.get_ticks_msec()+int(seconds*1000)
 while not predicate.call() and Time.get_ticks_msec()<deadline:await process_frame
 return predicate.call()
func _initialize():run.call_deferred()
func run():
 var slot=""
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--world-slot="):slot=arg.trim_prefix("--world-slot=")
 if not slot.begins_with("lake_cave_"):quit(2);return
 game=load("res://demo/world.tscn").instantiate();root.add_child(game);game.background_fps=60
 game.terrain.message_changed.connect(func(message: String):messages.append(message))
 check(await wait_for(func():return not game.loading_active and game.lakes.statistics().ready==4),"saved world publishes all four generated lakes")
 if failures:await finish();return
 var record: Dictionary=game.lakes._lakes[1]
 var seed: Vector3=record.seed;var pocket=seed+Vector3(20,-2,0)
 game.teleport(seed+Vector3(0,12,0),seed.y+12)
 check(await wait_for(func():return not game.loading_active),"lake terrain collision loads through normal travel gate")
 game.set_physics_process(false);game._clear_motion();game.fly=true;game.needs_floor_spawn=false
 check(record.bounds.has_point(pocket+Vector3(3,-3,3)),"cave fixture stays inside finite lake bounds")
 check(game.lakes.depth_at(pocket)==0,"prospective pocket is initially dry")
 check(game.terrain.sculpt_sphere(pocket,3),"carve separate submerged pocket in actual terrain")
 check(await wait_for(func():return not game.terrain.pending_edit and game.lakes.statistics().ready==4),"pocket terrain and lake rebake publish")
 check(game.lakes.depth_at(pocket)==0,"disconnected excavated pocket stays dry")
 var roof: Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(pocket,pocket+Vector3.UP*5,1))
 check(not roof.is_empty(),"excavated pocket retains real terrain roof")
 check(game.terrain.edit(Codec.brush(seed,pocket,2.5,0,false,1),seed.min(pocket),seed.max(pocket)),"carve submerged connection to lake")
 check(game.lakes.depth_at(seed)==0,"accepted connection edit immediately removes stale occupancy")
 check(await wait_for(func():return not game.terrain.pending_edit and game.lakes.statistics().ready==4),"connected terrain and water publish")
 check(game.lakes.depth_at(pocket)>5,"connected underground pocket fills below the lake level")
 game.player.position=pocket-Vector3(0,1.1,0);game.camera.rotation=Vector3.ZERO;game.water_camera.update()
 check(game._player_water_depth()>5 and game.water_camera.underwater,"actual player and camera recognize flooded cave")
 var transforms: Array[Transform3D]=[Transform3D(Basis(),pocket-Vector3.UP*2.5),Transform3D(Basis(),Vector3(pocket.x,record.level+2,pocket.z))]
 check(game.lakes.placement_mask(transforms)==PackedByteArray([1,0]),"vegetation exclusion distinguishes submerged cave floor and dry surface")
 var snapshot: PackedByteArray=game.lakes.capture_snapshot();var expected_depth: float=game.lakes.depth_at(pocket)
 game.player.position=seed+Vector3.UP*12;messages.clear();game.terrain.save_world()
 check(await wait_for(func():return messages.any(func(m):return m.begins_with("World saved and verified"))),"normal save publishes edited terrain and lake definition")
 var epoch: int=game.terrain.epoch;game.terrain.reload_world()
 check(await wait_for(func():return game.terrain.epoch>epoch and not game.loading_active and game.lakes.statistics().ready==4),"normal reload restores and republishes water")
 check(game.lakes.capture_snapshot()==snapshot and is_equal_approx(game.lakes.depth_at(pocket),expected_depth),"reload preserves connected cave occupancy and stable catalog")
 game.player.position=seed+Vector3(15,12,15);game.camera.look_at(seed)
 DirAccess.make_dir_recursive_absolute("res://reports/lake_cave_world")
 await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png("res://reports/lake_cave_world/surface.png")
 var file=FileAccess.open("res://reports/lake_cave_world/result.json",FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failures,"slot":slot,"seed":seed,"pocket":pocket,"depth":expected_depth,"roof":not roof.is_empty()},"  "));file.close()
 await finish()
func finish():
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame
 print("LAKE_CAVE_WORLD failures=",failures);quit(1 if failures else 0)
