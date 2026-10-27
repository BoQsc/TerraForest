extends Node

const Meshes=preload("res://addons/player_runtime/first_person_meshes.gd")
var game:Node
var enabled:=true
var shadows_enabled:=false
var active:=false
var overlay_active:=false
var settings_path:="user://player_view.cfg"
var viewport:SubViewport
var camera:Camera3D
var canvas:CanvasLayer
var image:TextureRect
var meshes:RefCounted
var original_arm_mask:=0
var lights:Dictionary={}
var shadows=preload("res://addons/player_runtime/first_person_shadows.gd").new()

func prepare(world:Node)->void:
	game=world
	original_arm_mask=game.camera.cull_mask&Meshes.ARM_LAYER
	meshes=Meshes.new();meshes.prepare(game.tool_view)
	viewport=SubViewport.new();viewport.name="FirstPersonRender"
	viewport.transparent_bg=true;viewport.gui_disable_input=true;viewport.handle_input_locally=false
	viewport.audio_listener_enable_3d=false;viewport.audio_listener_enable_2d=false
	viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	viewport.use_occlusion_culling=false
	viewport.world_3d=game.get_world_3d();add_child(viewport)
	camera=Camera3D.new();camera.name="FirstPersonCamera";camera.cull_mask=Meshes.ARM_LAYER
	viewport.add_child(camera);camera.make_current()
	shadows.view=camera;shadows.lights=lights
	canvas=CanvasLayer.new();canvas.name="FirstPersonComposite";canvas.layer=0;add_child(canvas)
	image=TextureRect.new();image.name="HandsAndTool";image.mouse_filter=Control.MOUSE_FILTER_IGNORE
	image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;image.texture=viewport.get_texture()
	canvas.add_child(image);canvas.hide()
	var value:=true
	if can_persist():
		var config:=ConfigFile.new()
		if config.load(settings_path)==OK:
			value=bool(config.get_value("camera","first_person_protection",true))
			shadows_enabled=bool(config.get_value("camera","first_person_detailed_shadows",false))
	for light:Node in game.get_tree().root.find_children("*","Light3D",true,false):register_light(light.get_instance_id())
	game.get_tree().node_added.connect(node_added)
	set_enabled(value,false)
	RenderingServer.frame_pre_draw.connect(update)

func can_persist()->bool:
	return not settings_path.is_empty() and is_instance_valid(game) and not game.temporary_world and not ProjectSettings.get_setting("terraforest/offscreen_session",false)

func set_enabled(value:bool,persist:bool=true)->void:
	enabled=value
	if persist and can_persist():
		var config:=ConfigFile.new();config.load(settings_path)
		config.set_value("camera","first_person_protection",enabled);config.save(settings_path)
	if not is_instance_valid(game) or viewport==null:return
	game.session_menu.first_person_toggle.set_pressed_no_signal(enabled)
	game.session_menu.first_person_shadows_toggle.set_pressed_no_signal(shadows_enabled)
	game.session_menu.first_person_shadows_toggle.disabled=not enabled
	update()

func set_shadows_enabled(value:bool,persist:bool=true)->void:
	shadows_enabled=value
	if persist and can_persist():
		var config:=ConfigFile.new();config.load(settings_path)
		config.set_value("camera","first_person_detailed_shadows",shadows_enabled);config.save(settings_path)
	if is_instance_valid(game):game.session_menu.first_person_shadows_toggle.set_pressed_no_signal(value)
	update()

func node_added(node:Node)->void:
	if node is Light3D:register_light.call_deferred(node.get_instance_id())

func register_light(identity:int)->void:
	var node:=instance_from_id(identity) as Light3D
	if not is_instance_valid(node) or not node.is_inside_tree() or node.get_world_3d()!=viewport.world_3d:return
	if not (node.light_cull_mask&Meshes.BODY_LAYER):return
	if lights.has(identity):return
	lights[identity]={"node":weakref(node),"mask":node.layers&Meshes.ARM_LAYER,"cull":node.light_cull_mask&Meshes.ARM_LAYER}
	node.tree_exiting.connect(remove_light.bind(identity),CONNECT_ONE_SHOT)
	node.layers|=Meshes.ARM_LAYER
	node.light_cull_mask|=Meshes.ARM_LAYER

func remove_light(identity:int)->void:
	if not lights.has(identity):return
	var light:Light3D=lights[identity].node.get_ref()
	if is_instance_valid(light):
		light.layers=(light.layers&~Meshes.ARM_LAYER)|lights[identity].mask
		light.light_cull_mask=(light.light_cull_mask&~Meshes.ARM_LAYER)|lights[identity].cull
	lights.erase(identity)

func update()->void:
	if not is_instance_valid(game) or not is_instance_valid(game.tool_view):return
	var wanted:bool=enabled and game.camera.current and not game.player_view.active and not game.world_vehicle.driving and not game.loading_active and not game.shutdown_requested and game.tool_view.is_visible_in_tree()
	var overlay:bool=wanted and shadows_enabled
	meshes.set_overlay(overlay);meshes.depth.set_active(wanted and not overlay)
	if wanted!=active:
		active=wanted;meshes.set_active(active)
	if overlay!=overlay_active:
		overlay_active=overlay;canvas.visible=overlay
		game.camera.cull_mask=(game.camera.cull_mask&~Meshes.ARM_LAYER)|(0 if overlay else original_arm_mask)
		viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS if overlay else SubViewport.UPDATE_DISABLED
	shadows.set_active(overlay)
	if not active:return
	meshes.sync()
	var parent_view:Viewport=game.camera.get_viewport()
	var dimensions:=Vector2i(parent_view.get_visible_rect().size)
	if dimensions.x<2 or dimensions.y<2:return
	if viewport.size!=dimensions:viewport.size=dimensions;image.size=Vector2(dimensions)
	viewport.msaa_3d=parent_view.msaa_3d
	viewport.screen_space_aa=parent_view.screen_space_aa;viewport.use_debanding=parent_view.use_debanding
	camera.global_transform=game.camera.global_transform
	camera.projection=game.camera.projection;camera.fov=game.camera.fov;camera.size=game.camera.size
	camera.keep_aspect=game.camera.keep_aspect;camera.frustum_offset=game.camera.frustum_offset
	camera.h_offset=game.camera.h_offset;camera.v_offset=game.camera.v_offset
	camera.near=.015;camera.far=minf(game.camera.far,6.0)
	camera.environment=game.camera.environment;camera.attributes=game.camera.attributes
	shadows.refresh()
	shadows.sync_morphs()

func _exit_tree()->void:
	if RenderingServer.frame_pre_draw.is_connected(update):RenderingServer.frame_pre_draw.disconnect(update)
	if meshes!=null:meshes.dispose()
	shadows.dispose()
	if get_tree().node_added.is_connected(node_added):get_tree().node_added.disconnect(node_added)
	for entry:Dictionary in lights.values():
		var light:Light3D=entry.node.get_ref()
		if is_instance_valid(light):
			light.layers=(light.layers&~Meshes.ARM_LAYER)|entry.mask
			light.light_cull_mask=(light.light_cull_mask&~Meshes.ARM_LAYER)|entry.cull
	lights.clear()
	if is_instance_valid(game) and is_instance_valid(game.camera):game.camera.cull_mask=(game.camera.cull_mask&~Meshes.ARM_LAYER)|original_arm_mask
