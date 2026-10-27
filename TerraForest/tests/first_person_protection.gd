extends SceneTree

class Fixture extends Node3D:
	var camera:=Camera3D.new()
	var tool_view=preload("res://addons/player_runtime/tool_view.gd").new()
	var player_view:={"active":false}
	var world_vehicle:={"driving":false}
	var session_menu:={"first_person_toggle":CheckButton.new(),"first_person_shadows_toggle":CheckButton.new()}
	var temporary_world:=true
	var loading_active:=false
	var shutdown_requested:=false
	var config_path:=""
	var first_person_view=preload("res://addons/player_runtime/first_person_view.gd").new()
	func _ready()->void:
		add_child(camera);camera.position=Vector3(0,1.65,0);camera.near=.08
		camera.add_child(tool_view);add_child(session_menu.first_person_toggle)
		add_child(session_menu.first_person_shadows_toggle);session_menu.first_person_toggle.hide();session_menu.first_person_shadows_toggle.hide()
		first_person_view.settings_path=config_path;add_child(first_person_view);first_person_view.prepare(self)

var game:Fixture
var checks:=0
var failures:=0
var folder:="res://reports/first_person_protection"
var results:={}

func _initialize()->void:run.call_deferred()
func check(condition:bool,label:String)->bool:
	checks+=1;print("PASS " if condition else "FAIL ",label)
	if not condition:failures+=1
	return condition
func frames(count:int=3)->void:
	for frame in count:await process_frame
func photo(label:String)->Image:
	await frames();await RenderingServer.frame_post_draw
	var captured:=root.get_texture().get_image()
	check(captured.save_png(folder.path_join(label+".png"))==OK,"capture "+label)
	return captured
func difference(before:Image,after:Image)->Dictionary:
	var changed:=0;var sum:=0.0
	for row in range(0,before.get_height(),2):
		for column in range(0,before.get_width(),2):
			var first:=before.get_pixel(column,row);var second:=after.get_pixel(column,row)
			var distance:=maxf(absf(first.r-second.r),maxf(absf(first.g-second.g),absf(first.b-second.b)))
			if distance>.035:changed+=1
			sum+=distance
	var pixels:float=ceil(before.get_height()/2.0)*ceil(before.get_width()/2.0)
	return {"changed_fraction":changed/pixels,"mean_error":sum/pixels}
func run()->void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--viewmodel-evidence="):folder=argument.trim_prefix("--viewmodel-evidence=")
	folder=ProjectSettings.globalize_path(folder);DirAccess.make_dir_recursive_absolute(folder)
	var environment:=Environment.new();environment.background_mode=Environment.BG_COLOR;environment.background_color=Color("556875")
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.ambient_light_color=Color("bdc7d2");environment.ambient_light_energy=.45
	var world_environment:=WorldEnvironment.new();world_environment.environment=environment;root.add_child(world_environment)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-40,-25,0);root.add_child(sun)
	game=Fixture.new();root.add_child(game);game.tool_view.set_process(false);game.tool_view.human.set_process(false)
	game.tool_view.equip(1);game.tool_view.human.animation_player.advance(0)
	var protection:Node=game.first_person_view;protection.update()
	check(protection.enabled and protection.active and game.session_menu.first_person_toggle.button_pressed,"clipping protection defaults on")
	check(not protection.shadows_enabled and not protection.shadows.active and protection.shadows.mirrors.is_empty(),"world shadows default off without allocating shadow-only instances")
	check(protection.viewport.world_3d==game.get_world_3d() and not protection.viewport.audio_listener_enable_3d,"one shared world and no second listener")
	check(protection.camera.cull_mask==1<<18 and not (game.camera.cull_mask&(1<<18)),"separate depth pass sees only protected geometry")
	check(protection.image.mouse_filter==Control.MOUSE_FILTER_IGNORE and protection.canvas.layer==0,"composite stays below HUD without intercepting input")
	check(game.tool_view.human.body_mesh.mesh==protection.meshes.BODY,"body remainder stays in world-depth pass")
	var boots:MeshInstance3D=game.tool_view.human.model.find_child("Wardrobe_Boots",true,false)
	check(boots.layers==1<<19,"legs and boots are not drawn through world meshes")
	var transform:=game.camera.global_transform;var profile:Dictionary=game.tool_view.attack_profile()
	var contacts:Array=[];game.tool_view.attack_contact.connect(func(identity:int):contacts.append(identity))
	check(game.tool_view.begin_attack(702),"protected animation starts without changing attack admission")
	game.tool_view.human._process(profile.contact-.01);protection.update()
	check(contacts.is_empty(),"protection does not trigger early hits")
	protection.set_enabled(false,false);protection.set_enabled(true,false)
	game.tool_view.human._process(.02);protection.update()
	check(contacts==[702] and game.tool_view.contact_ready(702),"switching protection mid-swing preserves one authored contact")
	check(game.camera.global_transform==transform and game.tool_view.attack_profile()==profile,"aim, reach origin and attack profile stay unchanged")
	game.tool_view.cancel_attack();game.tool_view.equip(1);game.tool_view.human.animation_player.advance(0)
	if DisplayServer.get_name()!="headless":
		protection.set_enabled(false,false);var baseline:=await photo("open_off")
		protection.set_enabled(true,false);var protected:=await photo("open_on")
		results.open_difference=difference(baseline,protected)
		check(results.open_difference.mean_error<.001 and results.open_difference.changed_fraction<.004,"open-air protection preserves the authored appearance")
		sun.rotation_degrees=Vector3(-90,0,0);sun.shadow_enabled=true;sun.shadow_normal_bias=.1;sun.shadow_bias=.02
		var roof:=MeshInstance3D.new();var roof_mesh:=BoxMesh.new();roof_mesh.size=Vector3(4,.2,4);roof.mesh=roof_mesh
		game.add_child(roof);roof.position=Vector3(0,3.3,-1)
		protection.update()
		check(protection.shadows.mirrors.is_empty(),"a nearby shadow caster does not activate the optional shadow system")
		protection.set_shadows_enabled(true,false)
		protection.shadows.next_refresh=0;protection.update()
		check(protection.shadows.mirrors.has(roof.get_instance_id()),"nearby world geometry contributes shadow-only instances")
		var shaded:=await photo("sun_shadow_on")
		protection.set_shadows_enabled(false,false);var unshaded:=await photo("sun_shadow_off")
		results.sun_difference=difference(shaded,unshaded)
		check(results.sun_difference.changed_fraction>.005,"world roof casts an actual sun shadow onto protected hands and tool")
		check(not protection.shadows.active and not game.session_menu.first_person_shadows_toggle.button_pressed,"world-shadow toggle disables only the shadow contribution")
		check(protection.active and sun.shadow_enabled and roof.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_ON,"disabling hand shadows preserves protection and world shadows")
		protection.set_shadows_enabled(true,false);roof.free();protection.shadows.next_refresh=0;protection.update()
		await frames()
		check(protection.shadows.mirrors.is_empty(),"removed world geometry leaves no stale hand-shadow caster")
		sun.light_energy=0;environment.ambient_light_energy=.08
		var lamp:=OmniLight3D.new();lamp.position=Vector3(-1,2.4,.6);lamp.omni_range=5;lamp.light_energy=4;lamp.shadow_enabled=true;lamp.shadow_normal_bias=.05;game.add_child(lamp)
		var occluder:=MeshInstance3D.new();var occluder_mesh:=BoxMesh.new();occluder_mesh.size=Vector3(.7,.2,.7);occluder.mesh=occluder_mesh
		game.add_child(occluder);occluder.position=Vector3(-.35,1.8,-.05)
		await frames();protection.shadows.next_refresh=0;protection.update()
		var lamp_shaded:=await photo("lamp_shadow_on")
		protection.set_shadows_enabled(false,false);var lamp_unshaded:=await photo("lamp_shadow_off")
		results.lamp_difference=difference(lamp_shaded,lamp_unshaded)
		check(results.lamp_difference.changed_fraction>.003,"newly added world light and occluder affect the protected tool")
		check(lamp.layers&(1<<18),"dynamically spawned lights are visible to the hands camera")
		lamp.free();occluder.free();sun.light_energy=1;sun.shadow_enabled=false;sun.rotation_degrees=Vector3(-40,-25,0);environment.ambient_light_energy=.45
		protection.set_shadows_enabled(false,false)
		var wall:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(5,5,.12);wall.mesh=box
		var wall_material:=StandardMaterial3D.new();wall_material.albedo_color=Color("55534a");wall.material_override=wall_material
		game.camera.add_child(wall);wall.position=Vector3(0,0,-.25)
		protection.set_enabled(false,false);var blocked:=await photo("wall_off")
		protection.set_enabled(true,false);var visible:=await photo("wall_on")
		results.wall_difference=difference(blocked,visible)
		check(results.wall_difference.changed_fraction>.02,"hands and pickaxe stay visible against a very close wall")
		wall.free()
		for item in [0,2,3,4,5,6,406]:
			game.tool_view.equip(item)
			game.tool_view.human._play(game.tool_view.human._motion_clip("Idle"),false,0.0);game.tool_view.human.animation_player.advance(0);protection.update()
			await photo("tool_"+str(item))
			check(protection.active,"render protection remains active for tool "+str(item))
		game.tool_view.equip(1);game.tool_view.human.animation_player.advance(0);protection.update()
		RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
		RenderingServer.viewport_set_measure_render_time(protection.viewport.get_viewport_rid(),true)
		for mode in [false,true,false,true]:
			protection.set_enabled(mode,false);await frames(15)
			var values:Array=[]
			for sample in 45:
				await process_frame
				values.append({"main_gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()),"overlay_gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(protection.viewport.get_viewport_rid()) if mode else 0.0})
			results["gpu_"+str(results.size())]={"enabled":mode,"samples":values}
	var sync_started:=Time.get_ticks_usec()
	for sample in 300:protection.update()
	results.sync_mean_ms=(Time.get_ticks_usec()-sync_started)/300000.0
	print("VIEWMODEL_SYNC_MS ",results.sync_mean_ms)
	game.tool_view.equip(0);protection.update()
	check(game.tool_view.human.body_mesh.mesh==protection.meshes.UNARMED_BODY,"unarmed corrective body uses its matching split")
	for pair in protection.meshes.pairs:
		var matched:=true
		for shape in pair.channels.size():matched=matched and is_equal_approx(pair.arms.get_blend_shape_value(shape),pair.source.get_blend_shape_value(pair.channels[shape]))
		check(matched,"split arms retain all current corrective morphs: "+String(pair.source.name))
	game.player_view.active=true;game.tool_view.human.set_third_person(true);protection.update()
	check(not protection.active and not protection.canvas.visible and protection.viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED,"third person disables the extra rendering pass")
	check(game.tool_view.human.body_mesh.mesh==game.tool_view.human.unarmed_body_mesh,"third person restores the untouched full body mesh")
	game.player_view.active=false;game.tool_view.human.set_third_person(false);protection.update()
	game.world_vehicle.driving=true;protection.update();check(not protection.active,"driving does not overlay held items")
	game.world_vehicle.driving=false;game.tool_view.hide();protection.update();check(not protection.active,"hidden tools disable the extra pass")
	game.tool_view.show();game.loading_active=true;protection.update();check(not protection.active,"loading does not render floating hands")
	game.loading_active=false;protection.update();check(protection.active,"returning to play restores protection")
	var config_path:=folder.path_join("settings.cfg")
	game.temporary_world=false;protection.settings_path=config_path
	var config:=ConfigFile.new();config.set_value("camera","third_person",true);config.save(config_path)
	protection.set_enabled(false)
	protection.set_shadows_enabled(false)
	config.load(config_path)
	check(not config.get_value("camera","first_person_protection",true) and not config.get_value("camera","first_person_world_shadows",true) and config.get_value("camera","third_person",false),"both preferences persist without overwriting the third-person setting")
	check(not protection.active and game.camera.cull_mask&(1<<18) and game.tool_view.human.body_mesh.mesh==game.tool_view.human.unarmed_body_mesh,"off fully restores original depth and geometry")
	game.free();await frames(2)
	game=Fixture.new();game.config_path=config_path;game.temporary_world=false;root.add_child(game);await frames()
	check(not game.first_person_view.enabled and not game.first_person_view.shadows_enabled and not game.first_person_view.active,"reopening reloads both saved preferences")
	game.free();await frames(2)
	config.erase_section_key("camera","first_person_world_shadows");config.save(config_path)
	game=Fixture.new();game.config_path=config_path;game.temporary_world=false;root.add_child(game);await frames()
	check(not game.first_person_view.shadows_enabled,"older camera preferences without a shadow key use the new off default")
	game.first_person_view.set_shadows_enabled(true);game.free();await frames(2)
	game=Fixture.new();game.config_path=config_path;game.temporary_world=false;root.add_child(game);await frames()
	check(game.first_person_view.shadows_enabled,"an explicit optional-shadow preference still persists")
	game.free();await frames(2)
	results.checks=checks;results.failures=failures
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify(results,"  "))
	print("FIRST_PERSON_PROTECTION checks=",checks," failures=",failures);quit(1 if failures else 0)
