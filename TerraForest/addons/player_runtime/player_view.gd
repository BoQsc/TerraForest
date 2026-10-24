# SPDX-License-Identifier: 0BSD
extends Node
# Presentation only. The eye camera remains the existing aim/reach origin;
# Godot's native spring arm owns the collision sweep for the optional view.
var game:Node
var enabled:=false
var active:=false
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
	set_process(enabled)
	if not is_instance_valid(game) or third_camera==null:return
	game.session_menu.third_person_toggle.set_pressed_no_signal(enabled)
	update()
func _bind_view(view:Camera3D)->void:
	view.make_current()
	game.vegetation.camera=view;game.ecosystem.camera=view;game.ground_cover.camera=view
	var canopy:Node=game.get_node_or_null("CanopyShadows")
	if canopy!=null:canopy.camera=view
	game.water_camera.configure(view,game.lakes)
	if view==third_camera:view.environment=game.camera.environment
	game.water_camera.update()
func update()->void:
	var wanted:bool=enabled and not game.world_vehicle.driving
	if active!=wanted:
		active=wanted
		arm.process_mode=Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
		game.tool_view.human.set_third_person(active)
		if not active:game.tool_view.transform=Transform3D.IDENTITY
		_bind_view(third_camera if active else game.camera)
	if not active:return
	# Keep the single animated body upright at the feet while the eye pitches.
	game.tool_view.global_transform=game.player.global_transform*Transform3D(Basis.IDENTITY,Vector3(0,1.65,-.03))
	third_camera.fov=game.camera.fov;third_camera.far=game.camera.far
	third_camera.cull_mask=game.camera.cull_mask
	if arm.get_hit_length()<.8:third_camera.cull_mask&=~PLAYER_LAYER
	var eye:Vector3=game.camera.global_position
	var end:Vector3=eye-game.camera.global_basis.z*120
	var hit:Dictionary=game.structures.blocks.raycast_scene(eye,end,15|(1<<16)|(1<<18),[game.player.get_rid()])
	aim_point=hit.position if not hit.is_empty() else end
	if third_camera.global_position.distance_squared_to(aim_point)>.01:third_camera.look_at(aim_point,game.camera.global_basis.y)
func _process(_delta:float)->void:update()
