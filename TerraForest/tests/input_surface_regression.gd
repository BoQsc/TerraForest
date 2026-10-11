# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var checks:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func key(code: int,pressed: bool) -> void:
	var e:=InputEventKey.new();e.physical_keycode=code;e.pressed=pressed;Input.parse_input_event(e);Input.flush_buffered_events()
func tap(code: int) -> void:key(code,true);key(code,false)
func wheel(button: int) -> void:
	var e:=InputEventMouseButton.new();e.button_index=button;e.pressed=true;Input.parse_input_event(e);Input.flush_buffered_events()
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.max_fps=60;game.background_fps=60;root.add_child(game)
	var deadline:=Time.get_ticks_msec()+45000
	while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
	check(not game.loading_active,"world ready")
	game.app_focused=true;game.needs_floor_spawn=false;game.player.position+=Vector3.UP*8;game.fly=true
	game._clear_motion();Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	key(KEY_W,true)
	for code in [KEY_1,KEY_2,KEY_3,KEY_4,KEY_5,KEY_6,KEY_7,KEY_8,KEY_9,KEY_0]:
		var before: Vector3=game.player.position
		tap(code)
		for i in 3:await physics_frame
		check(game.controls.direction()!=Vector3.ZERO and game.player.position.distance_to(before)>0.01,"held W continues through belt key "+str(code))
	tap(KEY_QUOTELEFT);await physics_frame
	check(game.session_menu.developer and game.controls.direction()!=Vector3.ZERO,"tilde mode switch preserves held W")
	var lamp: bool=game.headlamp.visible
	key(KEY_QUOTELEFT,true);tap(KEY_F)
	check(game.controls.direction()!=Vector3.ZERO and game.headlamp.visible==lamp,"tilde F preserves movement without toggling lamp")
	key(KEY_W,false)
	check(game.controls.direction()==Vector3.ZERO,"W release reaches controller during tilde chord")
	key(KEY_W,true)
	check(game.controls.direction()!=Vector3.ZERO,"W press reaches controller during tilde chord")
	key(KEY_QUOTELEFT,false)
	game.player_hud.equip(9);wheel(MOUSE_BUTTON_WHEEL_DOWN)
	check(game.player_hud.developer_slot==0 and game.controls.direction()!=Vector3.ZERO,"wheel down wraps belt without stopping movement")
	wheel(MOUSE_BUTTON_WHEEL_UP)
	check(game.player_hud.developer_slot==9 and game.equipped_tool==0,"wheel up wraps into empty hands")
	for i in 10:wheel(MOUSE_BUTTON_WHEEL_DOWN)
	check(game.player_hud.developer_slot==9,"wheel includes all ten slots")
	tap(KEY_QUOTELEFT)
	check(not game.session_menu.developer and game.controls.direction()!=Vector3.ZERO,"leaving development preserves held W")
	tap(KEY_ESCAPE)
	check(game.controls.direction()==Vector3.ZERO,"real menu opening clears movement")
	var slot: int=game.player_hud.active_slot;wheel(MOUSE_BUTTON_WHEEL_DOWN)
	check(game.player_hud.active_slot==slot,"menu wheel does not equip belt")
	key(KEY_W,false);tap(KEY_ESCAPE);game.player_hud.set_open(true);wheel(MOUSE_BUTTON_WHEEL_DOWN)
	check(game.player_hud.active_slot==slot,"inventory wheel does not equip belt")
	game.player_hud.set_open(false);game.set_physics_process(false);game._clear_motion()
	# Compare the very same excavated geometry, camera, textures and lighting.
	game.vegetation.hide()
	var origin:=Vector3(800,150,1310)
	var hit: Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(origin,origin-Vector3.UP*200,1))
	check(not hit.is_empty(),"terrain hit for excavation visual")
	if not hit.is_empty():
		var center: Vector3=hit.position-Vector3.UP*1.5
		check(game.terrain.edit(preload("res://addons/volumetric_terrain/mesh_codec.gd").brush(center,center-Vector3.UP*3,1.75,0,false,1),center-Vector3.UP*3,center),"excavation accepted")
		deadline=Time.get_ticks_msec()+15000
		while game.terrain.pending_edit and Time.get_ticks_msec()<deadline:await process_frame
		check(not game.terrain.pending_edit,"excavation published")
		game.camera.global_position=hit.position+Vector3(1.5,1.5,2);game.camera.look_at(center)
		for i in 120:await process_frame
		var mat: ShaderMaterial=game.terrain.material
		var fixed_shader: Shader=mat.shader
		var old_shader:=Shader.new()
		old_shader.code=fixed_shader.code.replace("pow(abs(face_normal),vec3(4.0))","pow(abs(n),vec3(4.0))")
		DirAccess.make_dir_recursive_absolute("res://reports/input_surface_regression")
		mat.shader=old_shader
		for i in 6:await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://reports/input_surface_regression/before.png")
		mat.shader=fixed_shader
		for i in 6:await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://reports/input_surface_regression/after.png")
	check(preload("res://addons/presentation/fullscreen_policy.gd").measurement(root).fair_graphical_sample and Engine.max_fps==60,"fullscreen 1080p cap60")
	game.shutdown_requested=true;check(await game.terrain.shutdown_after_edits(),"clean shutdown")
	game.free();await process_frame;await process_frame
	print("INPUT_SURFACE_REGRESSION checks=",checks," failures=",failures);quit(1 if failures else 0)
