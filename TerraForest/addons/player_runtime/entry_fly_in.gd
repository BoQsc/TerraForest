# SPDX-License-Identifier: 0BSD
extends RefCounted
# A disposable presentation camera. Physical focus, eye aim and saved pose stay put.
const DURATION:=3.0
const PLAYER_LAYER:=1<<19
var view:Node
var game:Node
var enabled:=true
var pending:=false
var active:=false
var elapsed:=0.0
var started_usec:=0
var camera:Camera3D
var start_offset:=Vector3.ZERO
var fog_density:=0.0
var overlay:CanvasLayer
var hidden:Array[Node]=[]
var held_buttons:=0
var starts:=0
var wake_pending:=false
var waking:=false
var wake_item:=0
var wake_returned:=false
var wake_starts:=0
const WAKEUP=preload("res://addons/characters/runtime/assets/Human.wakeup.res")

func prepare(owner_view:Node)->void:
	view=owner_view;game=view.game
	if not view.settings_path.is_empty() and not ProjectSettings.get_setting("terraforest/offscreen_session",false):
		var config:=ConfigFile.new()
		if config.load(view.settings_path)==OK:enabled=bool(config.get_value("camera","entry_fly_in",true))
	game.session_menu.entry_fly_in_toggle.set_pressed_no_signal(enabled)
	game.terrain.reload_started.connect(arm)
	arm()

func set_enabled(value:bool,persist:bool=true)->void:
	enabled=value
	if persist and not view.settings_path.is_empty() and not ProjectSettings.get_setting("terraforest/offscreen_session",false):
		var config:=ConfigFile.new();config.load(view.settings_path)
		config.set_value("camera","entry_fly_in",enabled);config.save(view.settings_path)
	game.session_menu.entry_fly_in_toggle.set_pressed_no_signal(enabled)
	if not enabled:
		if pending and not game.loading_active:game.loading_layer.hide()
		pending=wake_pending;finish()
	view.refresh_processing()

func arm()->void:
	finish()
	var args:=PackedStringArray(ProjectSettings.get_setting("terraforest/session_arguments",OS.get_cmdline_user_args()))
	# Tools and offscreen jobs retain their established camera, unless a check opts in.
	var diagnostic:bool=game.temporary_world or game.benchmark_enabled or ProjectSettings.get_setting("terraforest/offscreen_session",false)
	pending=(enabled and (not diagnostic or "--entry-fly-in" in args)) or (wake_pending and (not diagnostic or OS.get_cmdline_user_args().has("--wakeup-test")))
	view.refresh_processing()

func blocks_actions()->bool:return active or held_buttons!=0

func consume(event:InputEvent)->bool:
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:
		var bit:int=1<<event.button_index
		if not event.pressed and held_buttons&bit:
			held_buttons&=~bit;return true
		if active:
			if event.pressed:held_buttons|=bit
			return true
	if not active:return false
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode in [KEY_ESCAPE,KEY_TAB,KEY_M]:
			finish();return false # The ordinary UI owner receives its opening key.
		if event.physical_keycode==KEY_SPACE:finish()
	return event is InputEventKey or event is InputEventMouse

func _unavailable()->bool:
	return game.shutdown_requested or game.world_vehicle.driving or game.session_menu.visible_ui() or game.player_hud.inventory_open

func step(_delta:float)->void:
	if pending:
		if _unavailable():
			if not game.loading_active:game.loading_layer.hide()
			pending=false;view.refresh_processing();return
		if game.loading_active:return
		# The floor snap runs on the next physics tick after loading. Keep the
		# existing cover for that tick so first person never flashes before entry.
		if game.waiting_spawn or game.needs_floor_spawn:game.loading_layer.show();return
		game.loading_layer.hide()
		if not game.app_focused:return
		pending=false
		begin()
		view.refresh_processing()
		return
	if not active:return
	if _unavailable() or not game.app_focused or game.loading_active or (not enabled and not waking):
		if not game.app_focused:held_buttons=0
		finish();return
	if waking:
		elapsed=minf(5.0,elapsed+minf(_delta,.1))
		var human:Node=game.tool_view.human
		if elapsed<4.4:human.animation_player.seek(elapsed,true);human.animation_player.advance(0)
		else:
			if not wake_returned:
				return_wake_item();wake_returned=true
			human.animation_player.advance(minf(_delta,.1))
		if elapsed>=5.0:finish()
		return
	elapsed=minf(DURATION,(Time.get_ticks_usec()-started_usec)/1000000.0)
	if elapsed>=DURATION:finish();return
	present(elapsed/DURATION)

func begin()->bool:
	if game.loading_active or game.waiting_spawn or game.needs_floor_spawn or _unavailable():return false
	if wake_pending:return begin_wake()
	if not enabled:return false
	# Indoors/underground resumes go straight to the saved first-person view.
	var eye:Vector3=game.camera.global_position
	if game.lakes.depth_at(eye)>0:return false
	# Native authored-cell rays have a 256 m cap. Two bounded segments cover the
	# vertical world column without admitting any distant collision residency.
	for height:float in [0.0,240.0]:
		var roof:Dictionary=game.structures.blocks.raycast_scene(eye+Vector3.UP*height,eye+Vector3.UP*(height+240),15|(1<<18),[game.player.get_rid()])
		if not roof.is_empty():return false
	view.set_overview(false);view.set_enabled(false,false)
	game._clear_motion();game.pointer.hide()
	active=true;elapsed=0.0;started_usec=Time.get_ticks_usec();starts+=1
	for button:int in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:
		if Input.is_mouse_button_pressed(button):held_buttons|=1<<button
	var behind:Vector3=game.player.global_basis.z*600.0
	start_offset=Vector3(clampf(eye.x+behind.x,64,1984)-eye.x,1050,clampf(eye.z+behind.z,64,1984)-eye.z)
	camera=Camera3D.new();camera.name="WorldEntryCamera";camera.near=.08
	game.add_child(camera)
	camera.global_position=eye+start_offset
	camera.look_at(eye,game.player.global_basis.z if Vector2(start_offset.x,start_offset.z).length()<1.0 else Vector3.UP)
	var source:Environment=game.camera.environment if game.camera.environment!=null else game.get_world_3d().environment
	if source!=null:
		camera.environment=source.duplicate();fog_density=source.fog_density
	view._bind_view(camera)
	game.tool_view.human.set_third_person(true)
	for node:Node in [game.player_hud,game.help.get_parent(),game.destination_guide]:
		if node!=null and node.visible:hidden.append(node);node.hide()
	overlay=CanvasLayer.new();overlay.layer=39;game.add_child(overlay)
	var hint:=Label.new();hint.text="Entering world · Space to skip";hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	hint.mouse_filter=Control.MOUSE_FILTER_IGNORE;hint.add_theme_font_size_override("font_size",20)
	overlay.add_child(hint);hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint.offset_left=-240;hint.offset_right=240;hint.offset_top=-68;hint.offset_bottom=-34
	present(0.0);view.refresh_processing()
	return true

func begin_wake()->bool:
	view.set_overview(false);view.set_enabled(false,false)
	game._clear_motion();game.tool_view.cancel_attack()
	var human:Node=game.tool_view.human
	wake_item=game.player_hud.active_item;human.set_process(false);human.current=0
	game.tool_view.equip(0)
	if not human.animation_player.has_animation_library("wakeup"):human.animation_player.add_animation_library("wakeup",WAKEUP)
	human.animation_player.play("wakeup/FP_Wake_Confused_Review",0);human.animation_player.advance(0)
	active=true;waking=true;wake_pending=false;wake_returned=false;elapsed=0.0;wake_starts+=1
	game.terrain.changed_since_save=true;view.refresh_processing();return true

func arm_respawn()->void:
	wake_pending=true;arm()

func return_wake_item()->void:
	game.tool_view.equip(wake_item)
	var human:Node=game.tool_view.human
	human.active_clip=human._motion_clip("Idle");human.action_remaining=0.0
	human.animation_player.play(human.clips[human.active_clip],.6)

static func offset_at(start:Vector3,progress:float,backward:Vector3)->Vector3:
	var remaining:=1.0-clampf(progress,0.0,1.0)
	# A short shoulder approach keeps the actual player visible before the head
	# handoff, without carrying the high-altitude offset through nearby buildings.
	var shoulder:=4.0*smoothstep(.35,.65,progress)*(1.0-smoothstep(.72,1.0,progress))
	return start*pow(remaining,4)+backward*shoulder

func present(progress:float)->void:
	var eye:Vector3=game.camera.global_position
	var offset:=offset_at(start_offset,progress,game.player.global_basis.z)
	# Only query loaded near-player geometry; aerial rendering never requests physics.
	if offset.length()<48.0 and offset.length()>.25:
		var hit:Dictionary=game.structures.blocks.raycast_scene(eye,eye+offset,15|(1<<18),[game.player.get_rid()])
		if not hit.is_empty():finish();return
	var looking:=Basis.looking_at(-offset,game.player.global_basis.z if Vector2(offset.x,offset.z).length()<.001 else Vector3.UP)
	camera.global_transform=Transform3D(looking.slerp(game.camera.global_basis,smoothstep(.84,1.0,progress)),eye+offset)
	camera.fov=game.camera.fov;camera.far=maxf(3300,camera.global_position.distance_to(Vector3(1024,128,1024))+1600)
	camera.cull_mask=game.camera.cull_mask
	if offset.length()<.85:camera.cull_mask&=~PLAYER_LAYER
	if camera.environment!=null:camera.environment.fog_density=fog_density/maxf(1.0,offset.length()/64.0)
	game.tool_view.global_transform=game.player.global_transform*Transform3D(Basis.IDENTITY,Vector3(0,1.65,-.03))
	game.terrain.render_view=camera.global_position
	game.terrain.render_projection_scale=clampf(camera.get_viewport().get_visible_rect().size.y/1080.0*tan(deg_to_rad(75.0)*.5)/tan(deg_to_rad(camera.fov)*.5),.25,2.0)

func finish()->void:
	if not active:return
	if waking:
		if not wake_returned:return_wake_item()
		game.tool_view.human.set_process(true);waking=false
	active=false
	view._bind_view(game.camera)
	game.tool_view.human.set_third_person(false);game.tool_view.transform=Transform3D.IDENTITY
	game.terrain.render_view=Vector3.INF;game.terrain.render_projection_scale=1.0;game.terrain.schedule_timer=0.0
	game._clear_motion()
	for node:Node in hidden:if is_instance_valid(node):node.show()
	hidden.clear()
	if is_instance_valid(overlay):overlay.queue_free()
	if is_instance_valid(camera):camera.queue_free()
	overlay=null;camera=null
	view.refresh_processing()
