# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
const Planner=preload("res://addons/structures/terrain_lot_planner.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
 var core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[42,17]))
 var layout:Dictionary=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(42,16)
 var plan:Dictionary=Planner.locate(core,layout.sites[3].position)
 if not plan.ok:quit(1);return
 var works:Dictionary=Planner.earthworks(plan)
 var terrain=preload("res://addons/volumetric_terrain/terrain_world.gd").new()
 terrain.diagnostics_pause_streaming=true;terrain.backend.world_generator=17;terrain.backend.world_seed=42
 root.add_child(terrain);terrain.start(StandardMaterial3D.new(),true)
 var deadline:int=Time.get_ticks_msec()+30000
 while not terrain.world_ready and Time.get_ticks_msec()<deadline:await process_frame
 var runner=preload("res://addons/structures/site_preparation.gd").new()
 var guard:Callable=func(_bounds:AABB)->String:return ""
 var failures:=0
 if not terrain.world_ready or not runner.begin(works,terrain,guard):failures+=1
 else:
  deadline=Time.get_ticks_msec()+30000
  while runner.status=="running" and Time.get_ticks_msec()<deadline:
   runner.tick(terrain,guard);await process_frame
  if runner.status!="complete" or runner.completed!=works.segments.size():failures+=1
 print("TERRAIN_LOT_PREPARATION completed=",runner.completed," expected=",works.segments.size()," status=",runner.status," reason=",runner.reason," failures=",failures)
 terrain.shutdown();terrain.free();quit(1 if failures else 0)
