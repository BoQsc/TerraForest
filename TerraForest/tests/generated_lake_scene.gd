# SPDX-License-Identifier: 0BSD
extends SceneTree
const Scene=preload("res://demo/world.tscn")
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var failures:=0
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures+=1
func run() -> void:
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	var probe: RefCounted=ClassDB.instantiate("TerrainCore")
	probe.execute(Codec.command(6,[1703,4]))
	var definition: PackedByteArray=probe.execute(Codec.command(27))
	var center:=Vector3(definition.decode_float(48),definition.decode_float(44),definition.decode_float(56))
	probe=null
	var game=Scene.instantiate();game.temporary_world=true;game.terrain.backend.world_generator=4
	root.add_child(game)
	game.set_process_input(false);game.set_process_unhandled_input(false)
	game.player_hud.set_process_unhandled_input(false)
	var progress: Dictionary={"slices":0,"statuses":{},"terrain_ready_ms":-1}
	var begun:=Time.get_ticks_msec()
	game.terrain.lake_slice_ready.connect(func(_token: int,status: int,_epoch: int,_revision: int):
		progress.slices+=1;progress.statuses[str(status)]=progress.statuses.get(str(status),0)+1)
	var destination:=center+Vector3(35,25,35)
	game.fly=true
	# The world initializes its own default spawn; request the fixture destination
	# after that callback so the normal readiness gate loads the lake's terrain.
	game.terrain.initialized.connect(func(_message: String): game.teleport(destination,destination.y))
	var deadline:=Time.get_ticks_msec()+25000
	while (game.loading_active or game.lakes.depth_at(center-Vector3.UP*4)<=0) and Time.get_ticks_msec()<deadline:
		if game.terrain.world_ready and progress.terrain_ready_ms<0: progress.terrain_ready_ms=Time.get_ticks_msec()-begun
		await process_frame
	progress.elapsed_ms=Time.get_ticks_msec()-begun
	progress.lakes=game.lakes.statistics();progress.queued=game.terrain.backend.queued();progress.worker=game.terrain.backend.status()
	progress.loading=game.loading_active;progress.pending_edit=game.terrain.pending_edit;progress.foreground_brush=game.terrain.foreground_brush
	print("LAKE_PROGRESS ",JSON.stringify(progress))
	check(not game.loading_active and game.lakes.depth_at(center-Vector3.UP*4)>0,"nearby generated lake and player ready within 25 seconds")
	game.fly=true;game._clear_motion();game.player_hud.set_open(false)
	check(game.player.position.distance_to(destination)<0.1,"visual observer reached lake through destination loading")
	game.camera.look_at(center)
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	check(game.lakes.depth_at(center-Vector3.UP*4)>3.9,"generated lake has submerged occupancy in scene")
	check(game.lakes.depth_at(center+Vector3.UP)==0,"generated lake rejects above-water query")
	for i in 10: await process_frame
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://reports/generated_lake_scene.png")
	game.terrain.shutdown();game.free();quit(1 if failures else 0)
