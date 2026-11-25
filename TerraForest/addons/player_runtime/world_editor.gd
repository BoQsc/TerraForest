# SPDX-License-Identifier: 0BSD
extends CanvasLayer

enum { DIG, FILL, ADD_WATER, REMOVE_WATER }
const BrushShapes := [3, 2, 1]
const Mouse := preload("res://addons/world_runtime/mouse_ownership.gd")
var game:Node
var camera:=Camera3D.new()
var canvas:=Control.new()
var panel:=PanelContainer.new()
var operation:=OptionButton.new()
var shape:=OptionButton.new()
var radius:=SpinBox.new()
var volume:=SpinBox.new()
var material:=OptionButton.new()
var status:=Label.new()
var pivot:=Vector3.ZERO
var distance:=48.0
var cursor:=Vector2.INF
var tap:=Vector2.INF
var tap_deadline_ms:=0
var tap_epoch:=-1
var tap_revision:=-1
var held:=false
var pan:=false
var last_water_point:=Vector3.INF
var last_water_pixel:=Vector2.INF
var previous:Dictionary
var previous_radius:=2.0
var cached_ray:Dictionary={}

func _ready()->void:
	layer=46
	hide()
	add_child(canvas)
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.gui_input.connect(_canvas_input)
	canvas.mouse_exited.connect(func():
		cursor=Vector2.INF
		if held:_end_stroke()
	)
	canvas.add_child(panel)
	panel.position=Vector2(16,16)
	var surface:=StyleBoxFlat.new()
	surface.bg_color=Color("#122424f5")
	surface.border_color=Color("#659c8a")
	surface.border_width_top=2
	for side in [SIDE_TOP,SIDE_BOTTOM,SIDE_LEFT,SIDE_RIGHT]:surface.set_content_margin(side,12)
	panel.add_theme_stylebox_override("panel",surface)
	var layout:=VBoxContainer.new()
	panel.add_child(layout)
	var title:=HBoxContainer.new()
	layout.add_child(title)
	var heading:=Label.new()
	heading.text="World editor"
	heading.add_theme_font_size_override("font_size",22)
	heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	title.add_child(heading)
	var exit_button:=Button.new()
	exit_button.text="Back to game"
	exit_button.pressed.connect(close)
	title.add_child(exit_button)
	var row:=HBoxContainer.new()
	layout.add_child(row)
	for item in ["Dig terrain","Fill terrain","Add water","Remove water"]:operation.add_item(item)
	for item in ["Sphere","Grid box","Voxel"]:shape.add_item(item)
	for item in ["Stone","Wood","Metal"]:material.add_item(item)
	radius.min_value=.5
	radius.max_value=64
	radius.step=.25
	radius.value=2
	radius.prefix="Radius "
	radius.suffix=" m"
	volume.min_value=.05
	volume.max_value=1
	volume.step=.05
	volume.value=1
	volume.suffix=" m³"
	volume.tooltip_text="Volume added per stamp"
	radius.tooltip_text="Brush radius in metres"
	for control in [operation,shape,radius,material,volume]:row.add_child(control)
	operation.item_selected.connect(_sync_controls)
	shape.item_selected.connect(_sync_controls)
	radius.value_changed.connect(func(_value:float):_end_stroke())
	volume.value_changed.connect(func(_value:float):_end_stroke())
	material.item_selected.connect(func(_value:int):_end_stroke())
	var navigation:=Label.new()
	navigation.text="Left drag to edit   ·   Middle drag to pan   ·   Wheel to zoom"
	layout.add_child(navigation)
	layout.add_child(status)
	game.lakes.interaction_finished.connect(func(message:String):
		if visible and operation.selected>=ADD_WATER:status.text=message)
	game.terrain.edit_published.connect(func(_latency_ms:float):
		if visible and operation.selected<=FILL:status.text="Terrain edit applied")
	camera.far=4000
	add_child(camera)

func open()->void:
	if visible:return
	game.session_menu.set_open(false)
	previous={"camera":game.get_viewport().get_camera_3d(),"tool":game.tool,"radius":game.radius,"material":game.material_id,
		"enabled":game.player_hud.enabled,"hud_layers":{},"tool_pose":game.tool_view.transform,
		"dev_input":game.session_menu.developer_hud.is_processing_input()}
	game._clear_motion()
	game.stroke_buffer.clear()
	for layer_node:CanvasLayer in [game.player_hud,game.help.get_parent(),game.session_menu.developer_hud,game.destination_guide]:
		previous.hud_layers[layer_node]=layer_node.visible
		layer_node.hide()
	game.session_menu.developer_hud.set_process_input(false)
	game.player_hud.enabled=false
	pivot=game.player.global_position
	game.player_view.editor_camera=camera
	game.tool_view.human.set_third_person(true)
	camera.fov=game.camera.fov
	camera.environment=game.camera.environment
	camera.cull_mask=game.camera.cull_mask
	_position_camera()
	game.player_view._bind_view(camera)
	game.terrain.schedule_timer=0
	show()
	Mouse.set_mode(game,Input.MOUSE_MODE_VISIBLE)
	_sync_controls()
	status.text="Aim at the world"

func close()->void:
	if not visible:return
	_end_stroke()
	hide()
	cursor=Vector2.INF
	pan=false
	game._cancel_edit_input()
	game.stroke_buffer.clear()
	game.pointer.hide()
	game.tool=previous.tool
	game.radius=previous.radius
	game.material_id=previous.material
	game.player_view.editor_camera=null
	game.tool_view.human.set_third_person(game.player_view.active)
	game.tool_view.transform=previous.tool_pose
	game.player_view._bind_view(previous.camera)
	game.player_view.update()
	game.terrain.schedule_timer=0
	for layer_node:CanvasLayer in previous.hud_layers:layer_node.visible=previous.hud_layers[layer_node]
	game.session_menu.developer_hud.set_process_input(previous.dev_input)
	game.player_hud.enabled=previous.enabled
	game._restore_gameplay_mouse()

func _sync_controls(_selected:int=-1)->void:
	_end_stroke()
	var terrain_mode:=operation.selected<=FILL
	shape.visible=terrain_mode
	volume.visible=operation.selected==ADD_WATER
	radius.visible=(terrain_mode and shape.selected!=2) or operation.selected==REMOVE_WATER
	if operation.selected==REMOVE_WATER and radius.max_value>16:previous_radius=radius.value
	var restore:=operation.selected!=REMOVE_WATER and radius.max_value==16
	radius.max_value=16 if operation.selected==REMOVE_WATER else 64
	if restore:radius.value=previous_radius
	material.visible=operation.selected==FILL
	cached_ray.clear()

func _end_stroke()->void:
	held=false
	tap=Vector2.INF
	last_water_point=Vector3.INF
	last_water_pixel=Vector2.INF
	game.stroke_valid=false
	game.last_capture_signature.clear()
	game.stroke_buffer.cancel_continuous()
	for i in range(game.preparing_stroke.size()-1,-1,-1):
		if game.preparing_stroke[i].sample.get("continuous",false):game.preparing_stroke.remove_at(i)
	game.terrain.set_brush_active(false)

func _position_camera()->void:
	camera.global_position=pivot+Vector3(0,.90,.43589)*distance
	camera.look_at(pivot,Vector3.UP)
	game.terrain.render_view=camera.global_position
	cached_ray.clear()

func _canvas_input(event:InputEvent)->void:
	if event is InputEventMouseMotion:
		if tap.is_finite() and event.position.distance_squared_to(tap)>4:tap=Vector2.INF
		cursor=event.position
		if pan:
			var scale_m:=2.0*distance*tan(deg_to_rad(camera.fov*.5))/maxf(1,canvas.size.y)
			pivot.x=clampf(pivot.x-event.relative.x*scale_m,0,2000)
			pivot.z=clampf(pivot.z-event.relative.y*scale_m/.90,0,2000)
			_position_camera()
	elif event is InputEventMouseButton:
		cursor=event.position
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if event.pressed and not pan:
					tap=cursor
					tap_deadline_ms=Time.get_ticks_msec()+2000
					tap_epoch=game.terrain.epoch
					tap_revision=game.terrain.native_revision
					held=true
				else:
					var pending_click:=tap
					_end_stroke()
					tap=pending_click
			MOUSE_BUTTON_MIDDLE:
				pan=event.pressed
				_end_stroke()
			MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_end_stroke()
					distance=clampf(distance*(.8 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.25),4,1800)
					_position_camera()

func _pick(pixel:Vector2,water_tool:bool)->Dictionary:
	var origin:=camera.project_ray_origin(pixel)
	var direction:=camera.project_ray_normal(pixel)
	if direction.y>=-.001:return {}
	# Clip the ray to the editable vertical domain before precise, local queries.
	var start:=origin+direction*maxf(0,(256-origin.y)/direction.y)
	var end:=origin+direction*minf(camera.far,(0-origin.y)/direction.y)
	if (end-start).dot(direction)<=0:return {}
	var query:=PhysicsRayQueryParameters3D.create(start,end,3,[game.player.get_rid()])
	var hit:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		var span:Vector3=(end-start).abs()
		hit=game._terrain_pick(start,end,clampi(ceili(span.x+span.y+span.z)+4,256,8192))
	# Until the ground or its authoring ray is ready, a nearer occluder is
	# unknown. This also keeps the decorative horizon outside the edit domain.
	if hit.is_empty() or not water_tool:return hit
	var limit:Vector3=hit.position
	var batch:int=game.lakes._published_mesh_batch_id
	if cached_ray.get("start")==start and cached_ray.get("end")==limit and cached_ray.get("batch")==batch:
		return cached_ray.hit
	# The native picker selects only published surface triangles. Narrow
	# segments keep work proportional to the ray length, including diagonals.
	var length_m:=start.distance_to(limit)
	var next:=start
	var result:Dictionary={}
	for i in ceili(length_m/4):
		var from:=next
		next=start+direction*minf((i+1)*4.0,length_m)
		var surface:Dictionary=game.lakes.water.raycast_surface(from,next)
		if surface.hit:
			result={"position":surface.point,"normal":surface.normal,"water":true}
			break
	if result.is_empty() and not hit.is_empty():
		result={"position":hit.position,"normal":hit.normal,"water":false}
	cached_ray={"start":start,"end":limit,"batch":batch,"hit":result}
	return result

func step(delta:float)->void:
	if not game.app_focused:
		_end_stroke()
		game.pointer.hide()
		return
	# A submitted stamp may still be preparing its footprint after release.
	# Service the same queue as the first-person tools even with the cursor on UI.
	if not game.preparing_stroke.is_empty() or not game.stroke_buffer.samples.is_empty():
		game._consume_stroke()
		if not game.last_stroke_rejection.is_empty():status.text=game.last_stroke_rejection
	game.cooldown=maxf(0,game.cooldown-delta)
	var click:=tap.is_finite()
	var pixel:=tap if click else cursor
	tap=Vector2.INF
	if click and (tap_epoch!=game.terrain.epoch or tap_revision!=game.terrain.native_revision):
		_end_stroke()
		status.text="Terrain changed under the cursor. Select it again."
		return
	if not pixel.is_finite() or pan or panel.get_global_rect().has_point(pixel):
		game.pointer.hide()
		return
	var water_tool:=operation.selected>=ADD_WATER
	var hit:=_pick(pixel,water_tool)
	if hit.is_empty() or (operation.selected==REMOVE_WATER and not hit.get("water",false)):
		game.stroke_valid=false
		game.pointer.hide()
		if click:
			var preparing:bool=hit.is_empty() and (not game.terrain_pick_request.is_empty() or not game.terrain_pick_cache.is_empty())
			if preparing and tap_epoch==game.terrain.epoch and tap_revision==game.terrain.native_revision and Time.get_ticks_msec()<tap_deadline_ms:
				tap=pixel
				status.text="Preparing terrain under the cursor"
			else:
				status.text="No editable surface at the cursor"
		return
	var point:Vector3=hit.position
	game.terrain.set_interaction_target(point)
	game.terrain.set_brush_active(held or click)
	if not water_tool:
		# Structures occlude terrain. A brush must never silently dig behind them.
		if hit.has("collider") and (int(hit.collider.collision_layer)&1)==0:
			game.pointer.hide()
			if click:status.text="A structure covers this terrain"
			return
		game.tool=BrushShapes[shape.selected]
		game.radius=radius.value
		game.material_id=material.selected+1
		if click:game.cooldown=0
		game._apply_brush_hit(hit,operation.selected==FILL,click or held,held and not click)
		if click:status.text=game.last_stroke_rejection if not game.last_stroke_rejection.is_empty() else "Editing terrain"
		return
	game.pointer.mesh=game.sphere_preview
	game.pointer.scale=Vector3.ONE*(2*radius.value if operation.selected==REMOVE_WATER else 1.0)
	game.pointer.position=point
	game.pointer.show()
	if not click and (not held or game.cooldown>0 or pixel.distance_squared_to(last_water_pixel)<4 or point.distance_squared_to(last_water_point)<.25):return
	if not click and not game.lakes._pending_dev.is_empty():return
	var remove:=operation.selected==REMOVE_WATER
	var target:Vector3=point if remove else point+hit.normal*.05
	var result:Dictionary=game.lakes.dev_brush(target,remove,radius.value,roundi(volume.value*1000000))
	status.text=result.reason
	if result.ok or result.pending:
		last_water_point=point
		last_water_pixel=pixel
		game.cooldown=.05

func _notification(what:int)->void:
	if what==NOTIFICATION_WM_WINDOW_FOCUS_OUT and visible and is_instance_valid(game):
		_end_stroke()
		pan=false
