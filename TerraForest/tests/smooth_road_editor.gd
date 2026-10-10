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
	check(not game.loading_active,"main world ready")
	game.terrain.backend.disable_snapshot_writes()
	game.set_physics_process(false);game._clear_motion();game.app_focused=true
	game.player.position=Vector3(800,55,1250)
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	var p=game.road_palette
	p.width.value=4;p.depth.value=4;p.clearance.value=16
	p.mark(true,Vector3(784,50.86719,1310));p.mark(false,Vector3(672,59,1310))
	var revision: int=game.terrain.density_revision
	game._road_action("smooth")
	deadline=Time.get_ticks_msec()+20000
	while game.road_authoring.phase in ["request","sampling","fitting"] and Time.get_ticks_msec()<deadline:await process_frame
	check(game.road_authoring.phase=="ready","background profile becomes editor preview: "+p.status.text)
	check(game.terrain.density_revision==revision,"preview leaves terrain unchanged")
	check(p.build_button.text=="Build smooth road" and not p.build_button.disabled,"preview connects to build control")
	var accepted: bool=game.terrain.set_block(Vector3i(900,70,1350),1)
	deadline=Time.get_ticks_msec()+15000
	while game.terrain.pending_edit and Time.get_ticks_msec()<deadline:await process_frame
	await process_frame
	check(accepted and game.road_authoring.phase.is_empty(),"real terrain edit invalidates ready preview")
	revision=game.terrain.density_revision
	game._road_action("smooth")
	deadline=Time.get_ticks_msec()+20000
	while game.road_authoring.phase in ["request","sampling","fitting"] and Time.get_ticks_msec()<deadline:await process_frame
	p.width.value=3
	check(game.road_authoring.phase.is_empty(),"selection change discards stale profile")
	p.width.value=4;game._road_action("smooth")
	deadline=Time.get_ticks_msec()+20000
	while game.road_authoring.phase in ["request","sampling","fitting"] and Time.get_ticks_msec()<deadline:await process_frame
	check(game.road_authoring.phase=="ready","preview can be prepared again")
	game.player.position=game.road_authoring.points[0]+Vector3.UP
	game._road_action("build")
	deadline=Time.get_ticks_msec()+5000
	while game.road_authoring.phase=="building" and Time.get_ticks_msec()<deadline:await process_frame
	check(game.road_authoring.phase.is_empty() and game.terrain.density_revision==revision,"player overlap rejects construction before mutation")
	game.player.position=Vector3(800,55,1250)
	game._road_action("smooth")
	deadline=Time.get_ticks_msec()+20000
	while game.road_authoring.phase in ["request","sampling","fitting"] and Time.get_ticks_msec()<deadline:await process_frame
	game.camera.global_position=Vector3(795,75,1275);game.camera.look_at(Vector3(750,55,1310))
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://reports/smooth_road_editor")
	root.get_texture().get_image().save_png("res://reports/smooth_road_editor/preview.png")
	game._road_action("build")
	deadline=Time.get_ticks_msec()+30000
	while game.road_authoring.phase=="building" and Time.get_ticks_msec()<deadline:await process_frame
	check(game.road_authoring.phase=="complete","editor constructs all profile sections: "+p.status.text)
	check(game.terrain.density_revision>revision,"editor construction publishes terrain changes")
	check(not p.prepared_street.is_empty() and p.prepared_street.epoch==game.terrain.epoch,"completed smooth road registers street entrances")
	var file:=FileAccess.open("res://reports/smooth_road_editor/result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"failures":failures,"phase":game.road_authoring.phase,"status":p.status.text,"sections":game.road_authoring.section},"  "));file.close()
	await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png("res://reports/smooth_road_editor/built.png")
	game.terrain.shutdown();game.free();await process_frame;quit(1 if failures else 0)
