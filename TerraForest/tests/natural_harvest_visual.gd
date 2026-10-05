# SPDX-License-Identifier: 0BSD
extends SceneTree
const Presentation=preload("res://addons/presentation/fullscreen_policy.gd")
var failures:=0
var checks:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize() -> void: call_deferred("run")
func picture(name: String) -> void:
	for frame in range(6): await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/evidence/natural_harvest/"+name+".png")
func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://docs/evidence/natural_harvest")
	var game=load("res://demo/world.tscn").instantiate();game.temporary_world=true
	root.add_child(game)
	var deadline:=Time.get_ticks_msec()+60000
	while (game.loading_active or game.vegetation.renderer.roots.is_empty()) and Time.get_ticks_msec()<deadline: await process_frame
	check(not game.loading_active and not game.vegetation.renderer.roots.is_empty(),"natural forest and terrain become ready")
	print("NATURAL_STARTUP ",JSON.stringify({"loading":game.loading_active,"world_ready":game.terrain.world_ready,"error":game.terrain.latest_error,"worker":game.terrain.backend.status(),"queued":game.terrain.backend.queued(),"trees":game.vegetation.renderer.roots.size()}))
	if not game.loading_active and not game.vegetation.renderer.roots.is_empty():
		game.set_physics_process(false);game._clear_motion()
		var selected:=0;var distance:=INF
		for id: int in game.vegetation.renderer.roots:
			var pose: Transform3D=game.vegetation.renderer.roots[id].t
			var d:=pose.origin.distance_squared_to(game.player.global_position)
			if d<distance: distance=d;selected=id
		var tree: Transform3D=game.vegetation.renderer.roots[selected].t
		game.camera.global_position=tree.origin+Vector3(0,1.7,2)
		game.camera.look_at(tree.origin+Vector3(0,1.7,0))
		game.ecosystem.set_process(false)
		for tick in range(12): await physics_frame
		var origin: Vector3=game.camera.global_position
		var hit: Dictionary=game.structures.blocks.raycast_scene(origin,origin-game.camera.global_basis.z*2.5,7,[game.player.get_rid()])
		check(not hit.is_empty() and hit.collider==game.vegetation.trunk_collision and game.vegetation.trunk_collision.placement_for_body(hit.rid)==selected,"natural trunk is the nearest unobstructed interaction hit")
		await picture("before")
		var previous: Dictionary={}
		for id: int in game.vegetation.renderer.roots: previous[id]=game.vegetation.renderer.roots[id].t
		game.fly=false;game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
		var event:=InputEventKey.new();event.physical_keycode=KEY_E;event.pressed=true
		game._unhandled_input(event)
		check(game.ecosystem.harvest_state.contains(selected) and not game.vegetation.renderer.roots.has(selected),"E harvests the naturally generated aimed tree")
		var unchanged:=true
		for id: int in previous:
			if id!=selected and (not game.vegetation.renderer.roots.has(id) or game.vegetation.renderer.roots[id].t!=previous[id]): unchanged=false
		check(unchanged,"all other resident tree identities and transforms survive unchanged")
		await picture("after")
		check(game.player_hud.inventory.can_afford(PackedInt64Array([102,68]),game.player_hud.inventory.snapshot().revision).ok,"natural harvest grants four wood")
		check(Presentation.measurement(root).fair_graphical_sample and Engine.max_fps==60,"visual check uses fullscreen 1920x1080 and 60 FPS cap")
		print("NATURAL_TARGET ",JSON.stringify({"id":selected,"root":str(tree.origin),"resident_before":previous.size(),"resident_after":game.vegetation.renderer.roots.size()}))
	game.shutdown_requested=true
	await game.terrain.shutdown_after_edits();game.free()
	for frame in range(2): await process_frame
	print("NATURAL_HARVEST ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(1 if failures else 0)
