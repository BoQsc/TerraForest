# SPDX-License-Identifier: 0BSD
extends SceneTree
var folder:=""
func _initialize()->void:
	root.set_flag(Window.FLAG_NO_FOCUS,true)
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	ProjectSettings.set_setting("terraforest/pistol_trial_settings_path","")
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--review-output="):folder=argument.trim_prefix("--review-output=")
	run.call_deferred()
func photo(label:String)->void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(label+".png"))
func run()->void:
	if folder.is_empty():quit(1);return
	var stage:=Node3D.new();root.add_child(stage)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("27323c")
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.6
	stage.add_child(environment)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-40,-25,0);light.light_energy=1.2;stage.add_child(light)
	var floor:=StaticBody3D.new();stage.add_child(floor)
	var collider:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=Vector3(20,.2,20);collider.shape=shape;collider.position.y=-.1;floor.add_child(collider)
	var surface:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(20,20);surface.mesh=plane;floor.add_child(surface)
	var camera:=Camera3D.new();camera.near=.03;camera.position=Vector3(0,1.65,3.5);stage.add_child(camera);camera.make_current()
	var tools=preload("res://addons/player_runtime/tool_view.gd").new();camera.add_child(tools);tools.equip(9)
	var actor=preload("res://addons/characters/runtime/zombie.gd").new();stage.add_child(actor);actor.set_behavior(false)
	var effects=preload("res://addons/impact_effects/impact_effects.gd").new();stage.add_child(effects)
	var hud:=CanvasLayer.new();root.add_child(hud)
	var reticle=preload("res://addons/player_runtime/pistol_crosshair.gd").new();hud.add_child(reticle)
	var trial=preload("res://addons/player_runtime/pistol_trial.gd").new()
	for frame in 75:
		await process_frame
		tools.transform=trial.motion(1.0/60,Vector3(1,0,-3),true,1,false)
		reticle.update_state(1.0/60,true,false,3)
	await photo("pistol_idle")
	tools.human.rifle_action("HipFire");tools.human.flash_handgun();reticle.shot();reticle.confirmed_hit()
	actor.receive_hit("torso",10,Vector3(.1,1.4,0),Vector3(0,0,-2),false,"firearm")
	effects.firearm_contact({"kind":"zombie","pistol_splash":true,"position":Vector3(.1,1.4,.15),"normal":Vector3(0,0,1)})
	for frame in 5:
		await process_frame
		reticle.update_state(1.0/60,true,false,0)
	await photo("pistol_hit")
	for frame in 90:await process_frame
	tools.human.rifle_aiming=true
	for frame in 25:
		await process_frame
		tools.transform=trial.motion(1.0/60,Vector3.ZERO,true,0,true)
		reticle.update_state(1.0/60,true,true,0)
	await photo("pistol_aim")
	var menu=preload("res://addons/player_runtime/session_menu.gd").new()
	var panel:=PanelContainer.new();panel.position=Vector2(220,40);panel.size=Vector2(840,640);hud.add_child(panel)
	var style:=StyleBoxFlat.new();style.bg_color=Color("101d22")
	for side in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]:style.set_content_margin(side,24)
	panel.add_theme_stylebox_override("panel",style)
	var content:=VBoxContainer.new();content.add_theme_constant_override("separation",12);panel.add_child(content);trial.add_controls(menu,content)
	await photo("pistol_options")
	stage.free();hud.free();menu.free();await process_frame
	print("PISTOL_TRIAL_REVIEW failures=0");quit()
