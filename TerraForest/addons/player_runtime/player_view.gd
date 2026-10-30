# SPDX-License-Identifier: 0BSD
extends Node
# Presentation only. The eye camera remains the existing aim/reach origin;
# Godot's native spring arm owns the collision sweep for the optional view.
var game:Node
var enabled:=false
var active:=false
var overview:=false
var overview_distance:=32.0
var zoom_distance:=3.4
var orbit_yaw:=0.0
var orbit_pitch:=-0.85
var _bound_overview:=false
var _overview_environment:Environment
var _overview_fog_density:=0.0
var settings_path:="user://player_view.cfg"
var arm:SpringArm3D
var third_camera:Camera3D
var aim_point:=Vector3.ZERO
const PLAYER_LAYER:=1<<19
func _init()->void:set_process(false)
func prepare(world:Node)->void:
	game=world
	arm=SpringArm3D.new();arm.name="ThirdPersonBoom"
	# Sweep from the eye to the shoulder view, rather than starting an offset
	# sweep on the far side of a thin wall beside the player's shoulder.
	arm.rotation=Vector3(-atan2(.25,3.4),atan2(.6,3.4),0)
	arm.spring_length=3.4;arm.margin=.08;arm.collision_mask=15|(1<<16)|(1<<18)
	var sphere:=SphereShape3D.new();sphere.radius=.22;arm.shape=sphere
	game.camera.add_child(arm);arm.add_excluded_object(game.player.get_rid())
	third_camera=Camera3D.new();third_camera.name="ThirdPersonCamera";third_camera.near=.08;arm.add_child(third_camera)
	arm.process_mode=Node.PROCESS_MODE_DISABLED
	var value:=false
	if not settings_path.is_empty() and not ProjectSettings.get_setting("terraforest/offscreen_session",false):
		var config:=ConfigFile.new()
		if config.load(settings_path)==OK:value=bool(config.get_value("camera","third_person",false))
	set_enabled(value,false)
func set_enabled(value:bool,persist:bool=true)->void:
	enabled=value
	if persist and not settings_path.is_empty() and not ProjectSettings.get_setting("terraforest/offscreen_session",false):
		var config:=ConfigFile.new();config.load(settings_path)
		config.set_value("camera","third_person",enabled);config.save(settings_path)
	set_process(enabled or overview)
	if not is_instance_valid(game) or third_camera==null:return
	game.session_menu.third_person_toggle.set_pressed_no_signal(enabled)
	update()
func _bind_view(view:Camera3D)->void:
	view.make_current()
	game.vegetation.camera=view
	game.vegetation.collision_camera=game.camera
	game.ecosystem.camera=game.camera if overview else view
	game.ground_cover.camera=game.camera if overview else view
	game.ground_cover.boulder_camera=view
	game.vegetation.set_visual_distance(3500.0 if overview and view==third_camera else 0.0)
	var canopy:Node=game.get_node_or_null("CanopyShadows")
	if canopy!=null:canopy.camera=view
	game.water_camera.configure(view,game.lakes)
	if view==third_camera:
		view.environment=game.camera.environment
		if overview:
			var source:Environment=view.environment if view.environment!=null else game.get_world_3d().environment
			_overview_environment=source.duplicate() if source!=null else Environment.new()
			_overview_fog_density=_overview_environment.fog_density
			view.environment=_overview_environment
	game.water_camera.update()
func set_overview(value:bool)->void:
	if overview==value:return
	overview=value
	if value:
		orbit_yaw=game.player.global_rotation.y;zoom_distance=3.4
	game._clear_motion()
	set_process(enabled or overview)
	game.session_menu.overview_toggle.set_pressed_no_signal(value)
	game.terrain.schedule_timer=0.0
	update()

func consume(event:InputEvent)->bool:
	if not overview or not active or not game.app_focused or game.loading_active or game.shutdown_requested or game.session_menu.visible_ui() or game.player_hud.inventory_open or Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED:return false
	if event is InputEventMouseMotion:
		orbit_yaw-=event.relative.x*.0025
		orbit_pitch=clampf(orbit_pitch-event.relative.y*.0025,-1.48,-.3)
		return true
	if event is InputEventMouseButton:
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			overview_distance=clampf(overview_distance*(.8 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.25),3.4,1800)
		return true
	return event is InputEventKey and event.physical_keycode in [KEY_E,KEY_K,KEY_J,KEY_V,KEY_G]

func update(delta:float=0.0)->void:
	game.tool_view.human.crouched=game.crouched
	var wanted:bool=(enabled or overview) and not game.world_vehicle.driving
	if active!=wanted or _bound_overview!=overview:
		active=wanted
		_bound_overview=overview
		arm.process_mode=Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
		game.tool_view.human.set_third_person(active)
		if not active:game.tool_view.transform=Transform3D.IDENTITY
		_bind_view(third_camera if active else game.camera)
	if not active:
		game.terrain.render_view=Vector3.INF
		return
	# Keep the single animated body upright at the feet while the eye pitches.
	game.tool_view.global_transform=game.player.global_transform*Transform3D(Basis.IDENTITY,Vector3(0,1.65,-.03))
	third_camera.fov=game.camera.fov;third_camera.far=game.camera.far
	third_camera.cull_mask=game.camera.cull_mask
	if arm.get_hit_length()<.8:third_camera.cull_mask&=~PLAYER_LAYER
	if overview:
		zoom_distance=lerpf(zoom_distance,overview_distance,1.0-exp(-8.0*delta))
		if _overview_environment!=null:_overview_environment.fog_density=_overview_fog_density/maxf(1.0,zoom_distance/64.0)
		arm.spring_length=zoom_distance
		arm.global_rotation=Vector3(orbit_pitch,orbit_yaw,0)
		third_camera.rotation=Vector3.ZERO
		third_camera.far=maxf(3300,third_camera.global_position.distance_to(Vector3(1024,128,1024))+1600)
		game.terrain.render_view=third_camera.global_position
		game.terrain.render_projection_scale=clampf(third_camera.get_viewport().get_visible_rect().size.y/1080.0*tan(deg_to_rad(75.0)*.5)/tan(deg_to_rad(third_camera.fov)*.5),.25,2.0)
		return
	game.terrain.render_view=Vector3.INF
	arm.spring_length=3.4
	arm.rotation=Vector3(-atan2(.25,3.4),atan2(.6,3.4),0)
	var eye:Vector3=game.camera.global_position
	var end:Vector3=eye-game.camera.global_basis.z*120
	var hit:Dictionary=game.structures.blocks.raycast_scene(eye,end,15|(1<<16)|(1<<18),[game.player.get_rid()])
	aim_point=hit.position if not hit.is_empty() else end
	if third_camera.global_position.distance_squared_to(aim_point)>.01:third_camera.look_at(aim_point,game.camera.global_basis.y)
func _process(delta:float)->void:update(delta)
