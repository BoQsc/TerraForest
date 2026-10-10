# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var game=load("res://demo/world.tscn").instantiate();root.add_child(game)
	var deadline:=Time.get_ticks_msec()+60000
	while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
	game.terrain.backend.disable_snapshot_writes()
	check(not game.loading_active and game.actors.pool!=null,"main world enables bounded actor simulation")
	var start: Vector3=game.road_palette.prepared_streets[0].ends[0]+Vector3(5,0,0)
	game.fly=true;game.needs_floor_spawn=false;game.player.position=start+Vector3(0,4,5);game._clear_motion();game.app_focused=true
	var identity: int=game.actors.spawn(start+Vector3.UP*2)
	for i in 120:await physics_frame
	var handle: int=game.actors.store.resolve_identity(identity)
	var settled: Vector3=game.actors.store.get_position(handle)
	check(game.actors.pool.active_handles().has(handle),"normal physics loop activates nearby saved record")
	check(absf(settled.y-start.y-0.9)<0.15,"native idle simulation settles capsule on terrain")
	check(game.actors.renderer.multimesh.visible_instance_count==1,"normal loop renders nearby actor")
	var nodes:=PackedInt64Array()
	for child in game.actors.pool.get_children():nodes.append(child.get_instance_id())
	game.player.position+=Vector3(800,0,0)
	for i in 30:await physics_frame
	check(game.actors.pool.active_handles().is_empty(),"travel retires distant actor from physics pool")
	check(game.actors.store.get_position(handle)==settled,"retired actor record remains at settled position")
	game.player.position=start+Vector3(0,4,5)
	for i in 60:await physics_frame
	check(game.actors.pool.active_handles().has(handle),"return reactivates same identity")
	var after:=PackedInt64Array()
	for child in game.actors.pool.get_children():after.append(child.get_instance_id())
	check(nodes==after and after.size()==16,"travel reuses fixed16 collision bodies")
	game.actors.update_simulation(1.0/60,start,false,game._actor_collision_ready)
	check(game.actors.pool.active_handles().is_empty() and game.actors.renderer.multimesh.visible_instance_count==0,"world unavailability immediately suspends simulation and rendering")
	DirAccess.make_dir_recursive_absolute("res://reports/actor_world_activation")
	var file:=FileAccess.open("res://reports/actor_world_activation/result.json",FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failures,"identity":identity,"settled":settled}));file.close()
	game.terrain.shutdown();game.free();await process_frame;quit(1 if failures else 0)
