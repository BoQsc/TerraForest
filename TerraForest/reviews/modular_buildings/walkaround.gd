extends "res://reviews/modular_buildings/viewer.gd"

var player: CharacterBody3D
var camera: Camera3D
var movement: RefCounted
var fly := false
var paused := false
var focused := true
var pause_panel: PanelContainer
var location_label: Label
var prompt: Label
var placards: Array[Dictionary] = []
var signs_ready := false
var focus_elapsed := 0.0
var last_grounded := Vector3(.5,.03,21)

func _ready() -> void:
	super()
	if ready_ok:select_view(1,0)

func placement_origin(design: Dictionary, side: int) -> Vector3i:
	return Vector3i(-13 if side==0 else 13,0,0 if design.title=="COTTAGE A" else -38)

func include_building(design: Dictionary, side: int) -> bool:
	return side==0 or design.decision=="approved_addition"

func _interface() -> void:
	DisplayServer.window_set_title("TerraForest | Building review | A0 B0 originals / B1 approved addition")
	_site()
	_player()
	_hud()
	structures.blocks.set_focus(Vector3(0,3,-18))
	structures.blocks.set_collision_radius(100)
	structures.blocks.flush_bakes()
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED

func _site() -> void:
	var cells: Dictionary={}
	for row in range(-24,22):
		for column in range(-2,3):cells[Vector3i(column,-1,row)]=192
	for index in 2:
		var plaza: int=14 if index==0 else -22
		for column in range(-24,25):
			for row in range(plaza-2,plaza+3):cells[Vector3i(column,-1,row)]=192
		for side in 2:
			if not include_building(designs[index],side):continue
			var origin:=placement_origin(designs[index],side)
			var start: int=8 if index==0 else -28
			for row in range(start,plaza+1):
				for column in range(origin.x-1,origin.x+2):cells[Vector3i(column,-1,row)]=192
			var identity: String=("A" if index==0 else "B")+str(side)
			var sign_cell:=origin+Vector3i(5 if side==0 else -5,0,11 if index==0 else 12)
			for column in [-2,1]:
				cells[sign_cell+Vector3i(column,0,0)]=37
			for column in range(-2,2):
				for height in [1,2]:cells[sign_cell+Vector3i(column,height,0)]=structures.blocks.encode_block(9,12,3)
			var color:=Color("8ce8c1") if side==0 else Color("ffd38a")
			var title: String="EXISTING COTTAGE" if index==0 else "EXISTING SHOP"
			if side==1:title="COTTAGE A / R1" if index==0 else "SHOP B / R1"
			var status: String="ORIGINAL / UNCHANGED" if side==0 else "APPROVED / ADDITION ONLY"
			var sign_center:=Vector3(sign_cell)+Vector3(0,2,1.015)
			_text(identity,sign_center+Vector3(0,.58,0),74,.006,color)
			_text(title,sign_center+Vector3(0,.06,0),44,.006,Color.WHITE)
			_text(status,sign_center+Vector3(0,-.42,0),29,.006,color)
			_text("E at door / walk inside",sign_center+Vector3(0,-.74,0),24,.006,Color("c7d3dc"))
			var roof_label:=_text(identity+" / "+("ORIGINAL" if side==0 else "APPROVED ADDITION"),Vector3(origin)+Vector3(.5,12.3 if index==0 else 14.3,8 if index==0 else 11),42,.016,color)
			roof_label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
			placards.append({"id":identity,"title":title,"status":status,"cell":sign_cell,"origin":origin,"design":index,"side":side})
	var records:=PackedInt32Array()
	for cell: Vector3i in cells:records.append_array(PackedInt32Array([cell.x,cell.y,cell.z,cells[cell]]))
	signs_ready=structures.blocks.set_cells(records)

func _text(text: String, position_value: Vector3, size: int, pixels: float, color: Color) -> Label3D:
	var label:=Label3D.new();label.text=text;label.font_size=size;label.pixel_size=pixels
	label.modulate=color;label.outline_modulate=Color("15212a");label.outline_size=10
	label.position=position_value;label.no_depth_test=false;add_child(label)
	return label

func _player() -> void:
	player=CharacterBody3D.new();player.name="ReviewPlayer";player.collision_mask=7;player.collision_layer=2
	player.floor_snap_length=.35;player.floor_max_angle=deg_to_rad(48);player.floor_constant_speed=true;player.safe_margin=.01
	var capsule:=CapsuleShape3D.new();capsule.radius=.34;capsule.height=1.8
	var collider:=CollisionShape3D.new();collider.shape=capsule;collider.position.y=.9;player.add_child(collider)
	add_child(player)
	camera=Camera3D.new();camera.position.y=1.65;camera.fov=78;camera.near=.05;camera.far=260;camera.current=true;player.add_child(camera)
	movement=ClassDB.instantiate("NativePlayerMovement")

func _hud() -> void:
	var canvas:=CanvasLayer.new();add_child(canvas)
	var panel:=PanelContainer.new();panel.position=Vector2(24,24);canvas.add_child(panel)
	var style:=StyleBoxFlat.new();style.bg_color=Color(.035,.055,.07,.88)
	style.content_margin_left=18;style.content_margin_right=18;style.content_margin_top=12;style.content_margin_bottom=12
	panel.add_theme_stylebox_override("panel",style)
	var column:=VBoxContainer.new();panel.add_child(column)
	column.add_child(_label("TERRAFOREST / BUILDING REVIEW R1",19,Color("8ce8c1")))
	location_label=_label("",17);column.add_child(location_label)
	column.add_child(_label("B1 approved as an addition. A1 rejected and removed. Originals retained.",15,Color("c6d2da")))
	prompt=_label("",18);prompt.position=Vector2(24,936);canvas.add_child(prompt)
	var help:=_label("WASD move / mouse look / Shift run / Space jump / E door\n1 cottages / 2 shops / 3 overview / F fly (Space up, Ctrl down) / Esc menu",17)
	var footer:=PanelContainer.new();footer.position=Vector2(24,980);footer.add_theme_stylebox_override("panel",style)
	canvas.add_child(footer);footer.add_child(help)
	var crosshair:=_label("+",22);crosshair.position=Vector2(954,524);canvas.add_child(crosshair)
	pause_panel=PanelContainer.new();pause_panel.position=Vector2(720,270);pause_panel.custom_minimum_size=Vector2(480,0)
	pause_panel.add_theme_stylebox_override("panel",style);canvas.add_child(pause_panel)
	var menu:=VBoxContainer.new();menu.add_theme_constant_override("separation",12);pause_panel.add_child(menu)
	menu.add_child(_label("REVIEW PAUSED",25))
	for entry in [["Resume",func():set_paused(false)],["Cottage / A0 original",func():select_view(0,0);set_paused(false)],
		["Shops / B0 and B1",func():select_view(1,0);set_paused(false)],["Whole scene / fly",func():overview();set_paused(false)],
		["Close review",func():get_tree().quit()]]:
		var button:=Button.new();button.text=entry[0];button.pressed.connect(entry[1]);menu.add_child(button)
	menu.add_child(_label("B1 / Shop B R1 is the only approved addition.\nA1 is rejected. A0 roof rework is still pending.",16,Color("ffd38a")))
	pause_panel.hide()

func select_view(design_index: int, _view_index: int, _from_tour: bool = false) -> void:
	current_design=design_index;fly=false;player.collision_mask=7
	var plaza:=Vector3(.5,.03,21 if design_index==0 else -15)
	set_pose(plaza,Vector3(.5,4,0 if design_index==0 else -38))
	last_grounded=plaza
	_update_location()

func set_pose(position_value: Vector3, look: Vector3) -> void:
	player.position=position_value;player.velocity=Vector3.ZERO
	var direction: Vector3=(look-camera.global_position).normalized()
	player.rotation.y=atan2(-direction.x,-direction.z)
	camera.rotation.x=asin(clampf(direction.y,-1,1))
	structures.set_model_focus(player.position)
	if location_label!=null:_update_location()

func overview() -> void:
	fly=true;player.collision_mask=0
	set_pose(Vector3(39,29,43),Vector3(0,2,-14))
	_update_location()

func set_paused(value: bool) -> void:
	paused=value;pause_panel.visible=value;player.velocity=Vector3.ZERO
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE if value or not focused else Input.MOUSE_MODE_CAPTURED

func _update_location() -> void:
	var row: String="A / A0 original cottage (roof rework pending)" if player.position.z> -15 else "B / B0 original shop, B1 approved addition"
	if fly and player.position.y>12:row="Whole site / A0 cottage / B0 original shop / B1 approved addition"
	location_label.text=row+(" / FLY (no collision)" if fly else " / WALK")

func walk_step(direction: Vector3, delta: float, sprint: bool = false, jump: bool = false) -> void:
	player.velocity=movement.walking_velocity(direction,player.velocity,delta,sprint,player.is_on_floor(),jump)
	movement.move_grounded(player,delta)
	if player.is_on_floor():last_grounded=player.position

func _physics_process(delta: float) -> void:
	if not ready_ok or paused or not focused:return
	var motion:=Vector3(float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),0,float(Input.is_physical_key_pressed(KEY_S))-float(Input.is_physical_key_pressed(KEY_W)))
	var direction: Vector3=player.basis*motion.normalized()
	if fly:
		direction=camera.global_basis*motion
		direction.y+=float(Input.is_physical_key_pressed(KEY_SPACE))-float(Input.is_physical_key_pressed(KEY_CTRL))
		player.position+=direction.normalized()*delta*(20 if Input.is_physical_key_pressed(KEY_SHIFT) else 10)
	else:
		walk_step(direction,delta,Input.is_physical_key_pressed(KEY_SHIFT),Input.is_physical_key_pressed(KEY_SPACE))
	if player.position.y< -5:select_view(current_design,0)
	focus_elapsed+=delta
	if focus_elapsed>=.12:
		focus_elapsed=0;structures.set_model_focus(player.position);_update_location()
		var target:=door_target()
		prompt.text="E / "+("Close door" if hinges.is_open(target.id) else "Open door") if not target.is_empty() else "Review scene only / buildings and signs are separate native blocks"

func door_target() -> Dictionary:
	var collection: Node3D=structures.model(preload("res://addons/structures/door_catalog.gd").KEY)
	var start: Vector3=camera.global_position
	var hit: Dictionary=structures.blocks.raycast_scene(start,start-camera.global_basis.z*3,7,[player.get_rid()],true)
	if hit.is_empty() or hit.collider!=collection:return {}
	var identity: int=collection.placement_for_body(hit.rid)
	return {"id":identity,"collection":collection} if identity>0 else {}

func interact() -> bool:
	var target:=door_target()
	if target.is_empty():return false
	var result: Dictionary=hinges.toggle(target.collection,target.id,AABB())
	prompt.text=result.get("reason","")
	return result.get("ok",false)

func _input(event: InputEvent) -> void:
	if ready_ok and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_ESCAPE:
		set_paused(not paused);get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not ready_ok:return
	if event is InputEventMouseMotion and not paused and focused and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED:
		player.rotation.y-=event.relative.x*.0025
		camera.rotation.x=clampf(camera.rotation.x-event.relative.y*.0025,-1.45,1.45)
	if event is InputEventKey and event.pressed and not event.echo:
		if paused or not focused:return
		match event.physical_keycode:
			KEY_1:select_view(0,0)
			KEY_2:select_view(1,0)
			KEY_3:overview()
			KEY_E:interact()
			KEY_F:
				fly=not fly;player.collision_mask=0 if fly else 7
				if not fly:player.position=last_grounded
				player.velocity=Vector3.ZERO;_update_location()

func _unhandled_key_input(_event: InputEvent) -> void:
	pass

func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		focused=false
		if player!=null:player.velocity=Vector3.ZERO
		Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	elif what==NOTIFICATION_WM_WINDOW_FOCUS_IN:
		focused=true
		if ready_ok and not paused:Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
