# SPDX-License-Identifier: 0BSD
extends VBoxContainer
var viewport:SubViewport
var actor:Node3D
var model_resource:PackedScene
var animation_player:AnimationPlayer
var picture:TextureRect
var active:=false
var renders:=0
var queued:=false

func _ready()->void:
	picture=TextureRect.new();picture.custom_minimum_size=Vector2(370,365);picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;picture.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(picture)
	var controls:=HBoxContainer.new();controls.alignment=BoxContainer.ALIGNMENT_CENTER;add_child(controls)
	for turn in [-1,1]:
		var button:=Button.new();button.text="↶" if turn<0 else "↷";button.tooltip_text="Rotate character";button.custom_minimum_size=Vector2(72,34);button.focus_mode=Control.FOCUS_NONE
		button.pressed.connect(rotate_view.bind(turn));controls.add_child(button)

func set_active(value:bool)->void:
	active=value
	if not value:
		if viewport!=null:viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
		return
	if viewport==null:build()
	request_render()

func build()->void:
	viewport=SubViewport.new();viewport.size=Vector2i(384,448);viewport.own_world_3d=true;viewport.transparent_bg=false;viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED;viewport.msaa_3d=Viewport.MSAA_2X;viewport.gui_disable_input=true;add_child(viewport)
	var stage:=Node3D.new();viewport.add_child(stage)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("122126")
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color("b7c8d4");environment.environment.ambient_light_energy=.65;environment.environment.tonemap_mode=Environment.TONE_MAPPER_FILMIC;stage.add_child(environment)
	var key:=DirectionalLight3D.new();key.rotation_degrees=Vector3(-35,-35,0);key.light_color=Color("fff0da");key.light_energy=1.15;key.shadow_enabled=false;stage.add_child(key)
	var rim:=DirectionalLight3D.new();rim.rotation_degrees=Vector3(-15,145,0);rim.light_color=Color("98bed0");rim.light_energy=.6;rim.shadow_enabled=false;stage.add_child(rim)
	model_resource=load("res://addons/characters/runtime/human_view.gd").MODEL
	actor=model_resource.instantiate();stage.add_child(actor);actor.position=Vector3.ZERO;actor.rotation.y=.25
	for mesh:MeshInstance3D in actor.find_children("*","MeshInstance3D",true,false):
		if String(mesh.name).to_lower().replace("_",".").begins_with("equipment."):mesh.hide()
	animation_player=actor.find_children("*","AnimationPlayer",true,false)[0]
	animation_player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for clip in animation_player.get_animation_list():
		if String(clip).get_slice("/",String(clip).get_slice_count("/")-1)=="Idle":animation_player.play(clip);break
	animation_player.advance(.25);animation_player.pause();actor.process_mode=Node.PROCESS_MODE_DISABLED
	var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=2.25;camera.position=Vector3(0,1.05,3.2);stage.add_child(camera);camera.look_at(Vector3(0,.93,0));camera.current=true
	picture.texture=viewport.get_texture()

func request_render()->void:
	if not active or viewport==null or queued:return
	queued=true;renders+=1;viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
	RenderingServer.frame_post_draw.connect(render_finished,CONNECT_ONE_SHOT)

func render_finished()->void:
	queued=false
	if viewport!=null:viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED

func rotate_view(direction:int)->void:
	if not active or actor==null:return
	actor.rotation.y+=float(direction)*PI/6.;request_render()
