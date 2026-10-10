# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var aim:=Vector3.ZERO
func check(ok: bool,label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func press(game: Node,remove: bool=false,key: int=KEY_J) -> void:
	game.camera.global_position=aim+Vector3.UP*6;game.camera.look_at(aim,Vector3.FORWARD)
	var event:=InputEventKey.new();event.physical_keycode=key;event.pressed=true;event.shift_pressed=remove;game._unhandled_input(event)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var game=load("res://demo/world.tscn").instantiate();root.add_child(game)
	var deadline:=Time.get_ticks_msec()+60000
	while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
	game.terrain.backend.disable_snapshot_writes();game.set_physics_process(false);game._clear_motion();game.app_focused=true
	var point: Vector3=game.road_palette.prepared_streets[0].ends[0]+Vector3(6,0,0)
	aim=point
	game.player.position=point+Vector3(0,3,5);game.terrain.focus=point
	game.camera.global_position=point+Vector3.UP*6;game.camera.look_at(point,Vector3.FORWARD);Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	deadline=Time.get_ticks_msec()+15000
	while not game._actor_collision_ready(AABB(point-Vector3.ONE*2,Vector3.ONE*4)) and Time.get_ticks_msec()<deadline:await process_frame
	var count: int=game.actors.store.statistics().active
	press(game)
	check(game.actors.store.statistics().active==count+1,"J places an actor on clear loaded road: "+game._lake_notice)
	await physics_frame;await physics_frame
	press(game)
	check(game.actors.store.statistics().active==count+1,"occupied actor position rejects duplicate placement")
	game.construction_inventory.gameplay=true;press(game,true)
	check(game.actors.store.statistics().active==count+1,"gameplay mode rejects free actor removal")
	game.construction_inventory.gameplay=false
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE;press(game,true)
	check(game.actors.store.statistics().active==count+1,"released input rejects actor edits")
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED;press(game,true)
	check(game.actors.store.statistics().active==count,"Shift+J removes the aimed actor: "+game._lake_notice)
	await physics_frame;await physics_frame
	press(game)
	check(game.actors.store.statistics().active==count+1,"placement works again after proxy retirement")
	await physics_frame;await physics_frame
	press(game,false,KEY_K)
	var identity: int=game.actor_authoring.selected_identity
	check(identity>0,"K selects aimed actor by persistent identity")
	aim=point+Vector3(5,0,0)
	press(game,false,KEY_K)
	check(game.actors.orders.get_target(identity).present,"K issues destination order on clear ground: "+game._lake_notice)
	var handle: int=game.actors.store.resolve_identity(identity)
	var initial: Vector3=game.actors.store.get_position(handle)
	var render_tracks:=true
	for i in 60:
		await physics_frame
		game.actors.update_simulation(1.0/60,point,true,game._actor_collision_ready)
		render_tracks=render_tracks and game.actors.renderer.multimesh.get_instance_transform(0).origin.is_equal_approx(game.actors.store.get_position(handle))
	check(render_tracks,"rendered position follows every simulated movement tick")
	check(game.actors.store.get_position(handle).x>initial.x+2,"editor-issued order moves actor through native simulation")
	var snapshot: PackedByteArray=game.actors.orders.capture_storage_snapshot()
	game.construction_inventory.gameplay=true;press(game,true,KEY_K)
	check(game.actors.orders.capture_storage_snapshot()==snapshot,"gameplay mode cannot clear editor order")
	game.construction_inventory.gameplay=false;press(game,true,KEY_K)
	check(not game.actors.orders.get_target(identity).present,"Shift+K clears selected actor order")
	var stopped: Vector3=game.actors.store.get_position(handle)
	for i in 30:
		await physics_frame
		game.actors.update_simulation(1.0/60,point,true,game._actor_collision_ready)
	check(absf(game.actors.store.get_position(handle).x-stopped.x)<0.001,"stop halts horizontal movement")
	game.actor_authoring.selected_epoch=-1;press(game,true,KEY_K)
	check(game.actor_authoring.selected_identity==0,"selection from prior world epoch is discarded")
	game.camera.global_position=point+Vector3(3,2,5);game.camera.look_at(point+Vector3.UP)
	await create_timer(0.6).timeout;await RenderingServer.frame_post_draw
	check(game.telemetry.text.contains("J Place actor"),"editor controls appear in HUD")
	DirAccess.make_dir_recursive_absolute("res://reports/actor_editor")
	root.get_texture().get_image().save_png("res://reports/actor_editor/world.png")
	var file:=FileAccess.open("res://reports/actor_editor/result.json",FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failures}));file.close()
	game.terrain.shutdown();game.free();await process_frame;quit(1 if failures else 0)
