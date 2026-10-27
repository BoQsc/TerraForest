extends SceneTree

var game:Node
var checks:=0
var failures:=0
var folder:="res://reports/first_person_world"
var results:={}

func _initialize()->void:run.call_deferred()
func check(condition:bool,label:String)->bool:
	checks+=1;print("PASS " if condition else "FAIL ",label)
	if not condition:failures+=1
	return condition
func frames(count:int=3)->void:
	for frame in count:await process_frame
func photo(label:String)->void:
	await frames();await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(folder.path_join(label+".png"))==OK,"capture "+label)
func finish()->void:
	if game!=null:
		game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await frames(2)
	results.checks=checks;results.failures=failures
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify(results,"  "))
	print("FIRST_PERSON_WORLD checks=",checks," failures=",failures);quit(1 if failures else 0)

func run()->void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--viewmodel-evidence="):folder=argument.trim_prefix("--viewmodel-evidence=")
	folder=ProjectSettings.globalize_path(folder);DirAccess.make_dir_recursive_absolute(folder)
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60
	game.player_view.settings_path="";game.first_person_view.settings_path="";root.add_child(game)
	var deadline:=Time.get_ticks_msec()+60000
	while (game.loading_active or game.needs_floor_spawn) and Time.get_ticks_msec()<deadline:await process_frame
	if not check(not game.loading_active and not game.needs_floor_spawn,"temporary world becomes playable"):await finish();return
	game.set_physics_process(false);game._clear_motion();game.zombies.population_enabled=false;game.zombies.clear()
	game.session_menu.set_open(false);game.app_focused=true;game.player_hud.equip_item(1)
	game.tool_view.human.set_process(false);game.tool_view.human.animation_player.advance(.2)
	var protection:Node=game.first_person_view
	await frames(12);protection.update()
	var held:MeshInstance3D=game.tool_view.human.model.find_child("Equipment_Pickaxe",true,false)
	check(held!=null and held.is_visible_in_tree(),"ordinary equipment path exposes the authored pickaxe mesh")
	check(protection.active and protection.shadows_enabled,"normal gameplay starts with protection and world shadows enabled")
	var camera_transform:Transform3D=game.camera.global_transform
	results.camera_position=camera_transform.origin
	var original_profile:Dictionary=game.tool_view.attack_profile()
	check(protection.shadows.mirrors.size()>0 and protection.shadows.mirrors.size()<=protection.shadows.LIMIT,"real terrain and woodland use the bounded shadow-only set")
	await photo("forest_on")
	protection.set_enabled(false,false);await photo("forest_off")
	protection.set_enabled(true,false)
	var wall:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(5,5,.1);wall.mesh=box
	var material:=StandardMaterial3D.new();material.albedo_texture=load("res://addons/world_ecosystem/art/boulder_granite_v1.png");wall.material_override=material
	wall.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	game.camera.add_child(wall);wall.position=Vector3(0,0,-.25)
	protection.set_enabled(false,false);await photo("close_wall_off")
	protection.set_enabled(true,false);await photo("close_wall_on")
	check(game.camera.global_transform==camera_transform and game.tool_view.attack_profile()==original_profile,"near-wall rendering does not move the camera or modify attacks")
	wall.free()
	game.session_menu.set_open(true);game.session_menu.show_page("Player");await frames()
	check(not protection.active,"ESC menu hides first-person rendering")
	check(game.session_menu.first_person_toggle.button_pressed and game.session_menu.first_person_shadows_toggle.button_pressed,"Player menu exposes both enabled defaults")
	game.session_menu.first_person_toggle.button_pressed=false
	check(not protection.enabled and game.session_menu.first_person_shadows_toggle.disabled,"turning off protection disables its dependent shadow option")
	game.session_menu.first_person_toggle.button_pressed=true
	game.session_menu.first_person_shadows_toggle.button_pressed=false
	check(not protection.shadows_enabled,"Player shadow checkbox changes the renderer setting")
	game.session_menu.first_person_shadows_toggle.button_pressed=true
	await photo("player_settings")
	game.session_menu.set_open(false);await frames();check(protection.active,"resuming restores hands rendering")
	game.player_view.set_enabled(true,false);await frames()
	check(not protection.active and game.tool_view.human.third_person,"third-person camera restores ordinary whole-body rendering")
	await photo("third_person")
	game.player_view.set_enabled(false,false);await frames()
	check(protection.active and not game.tool_view.human.third_person,"returning to first person restores the protected layer")
	game.crouched=true;game.player_view.update();game.camera.position.y-=.5;await frames()
	check(protection.camera.global_transform.is_equal_approx(game.camera.global_transform),"crouching keeps both views aligned")
	await photo("crouched");game.crouched=false;game.player_view.update();game.camera.global_transform=camera_transform
	for item in [0,2,3,4,5,6,406]:
		game.tool_view.equip(item);game.tool_view.human._play(game.tool_view.human._motion_clip("Idle"),false,0)
		game.tool_view.human.animation_player.advance(.2);await frames()
		await photo("world_tool_"+str(item))
		check(protection.active,"world rendering covers equipment "+str(item))
	game.headlamp.toggle();await photo("headlamp_on");game.headlamp.toggle()
	var underwater:Environment=game.get_world_3d().environment.duplicate()
	underwater.fog_enabled=true;underwater.fog_light_color=Color("286170");underwater.fog_density=.3
	game.camera.environment=underwater;await frames()
	check(protection.camera.environment==underwater,"camera-local underwater environment reaches both cameras")
	await photo("underwater_environment");game.camera.environment=null
	game.tool_view.equip(1);game.tool_view.human.animation_player.advance(.2)
	root.content_scale_size=Vector2i(1280,720);await frames()
	check(protection.viewport.size==Vector2i(game.camera.get_viewport().get_visible_rect().size) and protection.image.size==Vector2(protection.viewport.size),"resized viewport and composite stay aligned")
	root.content_scale_size=Vector2i(1920,1080);await frames()
	check(protection.viewport.size==Vector2i(1920,1080),"returning to the original resolution restores the full-size pass")
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	RenderingServer.viewport_set_measure_render_time(protection.viewport.get_viewport_rid(),true)
	await frames(90)
	var samples:Array=[]
	for mode in [0,1,2,0,2]:
		protection.set_enabled(mode!=0,false);protection.set_shadows_enabled(mode==2,false);await frames(30)
		var times:Array=[]
		for frame in 90:
			await process_frame
			var begin:=Time.get_ticks_usec();protection.update()
			times.append({"main_gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()),"hands_gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(protection.viewport.get_viewport_rid()) if mode else 0.0,"sync_ms":(Time.get_ticks_usec()-begin)/1000.0,"shadow_refresh_ms":protection.shadows.refresh_ms,"casters":protection.shadows.mirrors.size()})
		samples.append({"mode":mode,"samples":times})
	results.performance=samples
	check(protection.shadows.mirrors.size()<=protection.shadows.LIMIT,"shadow references remain bounded through repeated toggles")
	await finish()
