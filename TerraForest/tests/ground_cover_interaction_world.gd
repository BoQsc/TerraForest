# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,label: String) -> void:
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var game=load("res://demo/world.tscn").instantiate();game.temporary_world=true
	root.add_child(game)
	var deadline:=Time.get_ticks_msec()+60000
	while game.loading_active and Time.get_ticks_msec()<deadline: await process_frame
	check(not game.loading_active,"actual world becomes ready")
	game.set_physics_process(false);game._clear_motion()
	var cover=game.ground_cover
	check(game.ground_enabled,"normal-world ground cover enabled")
	deadline=Time.get_ticks_msec()+15000
	while cover.resident.size()<49 and Time.get_ticks_msec()<deadline: await process_frame
	check(cover.resident.size()==49 and cover.rejected_batches==0,"real support and exclusion masks publish 49 cells")
	var count:=0
	var target:=Vector3.ZERO
	var target_id:=0
	var target_species:=0
	for key in cover.resident:
		for species in cover.resident[key]:
			count+=species.ids.size()
			for i in range(species.ids.size()):
				var t: PackedFloat32Array=species.transforms
				var point:=Vector3(t[i*12+3],t[i*12+7],t[i*12+11])
				if target==Vector3.ZERO or point.distance_squared_to(game.player.global_position)<target.distance_squared_to(game.player.global_position): 
					target=point;target_id=species.ids[i];target_species=cover.resident[key].find(species)
	check(count>0 and count<=3136,"real terrain has bounded ground-cover population")
	game.camera.global_position=target+Vector3(0.7,1.5,1)
	game.camera.look_at(target+Vector3(0,0.2,0))
	for frame in range(60): await RenderingServer.frame_post_draw
	game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	var key:=InputEventKey.new();key.physical_keycode=KEY_H;key.pressed=true
	game._unhandled_input(key)
	check(game.ground_mode,"H activates normal-world ground-cover tool")
	var before_inventory: Dictionary=game.player_hud.inventory.snapshot()
	key.physical_keycode=KEY_1+target_species;game._unhandled_input(key)
	var click:=InputEventMouseButton.new();click.pressed=true;click.button_index=MOUSE_BUTTON_LEFT
	game._unhandled_input(click)
	check(cover.removed.contains(target_id),"normal LMB removes aimed natural ground cover")
	click.button_index=MOUSE_BUTTON_RIGHT;game._unhandled_input(click)
	check(cover.removed.profile().placed==1,"normal RMB places selected ground cover on actual terrain")
	check(game.player_hud.inventory.snapshot().slots==before_inventory.slots,"collect/place round trip preserves inventory contents in selected mode")
	deadline=Time.get_ticks_msec()+5000
	while not cover._dirty.is_empty() and Time.get_ticks_msec()<deadline: await process_frame
	check(cover._dirty.is_empty(),"authored placement finishes terrain publication")
	var render:=[]
	for batch in cover.batches:
		var stats: Dictionary=batch.render_stats();render.append(stats)
		check(stats.resident_instances>0 and stats.resident_transform_bytes<=stats.byte_limit,"species has bounded GPU residency")
	var presentation: Dictionary=load("res://addons/presentation/fullscreen_policy.gd").measurement(root)
	check(presentation.fair_graphical_sample and Engine.max_fps==60,"fullscreen 1080p with 60 FPS cap")
	DirAccess.make_dir_recursive_absolute("res://reports/ground_cover")
	root.get_texture().get_image().save_png("res://reports/ground_cover/interaction_world.png")
	var file:=FileAccess.open("res://reports/ground_cover/interaction_world.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"failures":failures,"population":count,"render":render,"presentation":presentation},"  "));file.close()
	cover.set_process(false)
	game.shutdown_requested=true
	await game.terrain.shutdown_after_edits();game.free()
	for frame in range(2): await process_frame
	print("GROUND_COVER_INTERACTION_WORLD failures=",failures)
	quit(1 if failures else 0)
