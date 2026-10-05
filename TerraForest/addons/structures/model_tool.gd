extends Node3D
## Editor presentation/input glue. Native collections own placement and collision.
signal notice(text: String)
var active := false
var camera: Camera3D
var player: CharacterBody3D
var block_world: Node3D
var catalog: Array[Dictionary] = []
var selected := 0
var quarter_turns := 0
var preview := MeshInstance3D.new()
var panel := PanelContainer.new()
var caption := Label.new()
var choices: Array[Button] = []
var timer := 0.0
var preview_valid := false
var preview_material := StandardMaterial3D.new()
var history: RefCounted
var picked_collection: Node3D
var picked_id := 0
var transforming := false
var edit_available := false
var transform_controls := VBoxContainer.new()
var help := Label.new()
var gameplay := false
var paid_placement: Callable
var placement_failure := ""

func configure(view: Camera3D, actor: CharacterBody3D, entries: Array[Dictionary], ui: Node, blocks: Node3D = null) -> void:
	camera=view
	player=actor
	block_world=blocks
	catalog=entries
	history=ClassDB.instantiate("NativeStaticHistory")
	var collections: Array = []
	for entry in catalog:
		if not collections.has(entry.collection):
			collections.append(entry.collection)
	if not history.configure(collections,1024*1024,256):
		push_error("Could not configure native model edit history")
	preview_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	preview_material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	preview.material_override=preview_material
	preview.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(preview)
	preview.hide()
	ui.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.offset_left=-360
	panel.offset_top=-430
	panel.offset_right=-24
	panel.offset_bottom=-106
	var style := StyleBoxFlat.new()
	style.bg_color=Color(0.03,0.065,0.06,0.94)
	style.content_margin_left=16
	style.content_margin_right=16
	style.content_margin_top=12
	style.content_margin_bottom=12
	panel.add_theme_stylebox_override("panel",style)
	var content := VBoxContainer.new()
	panel.add_child(content)
	content.add_child(caption)
	for i in range(catalog.size()):
		var button := Button.new()
		button.text="%d  %s" % [i+1,catalog[i].title]
		button.focus_mode=Control.FOCUS_NONE
		button.pressed.connect(select.bind(i))
		content.add_child(button)
		choices.append(button)
	var selection_row := HBoxContainer.new()
	content.add_child(selection_row)
	tool_button(selection_row,"Select aimed (E)",pick)
	tool_button(selection_row,"Clear (Q)",clear_selection)
	content.add_child(transform_controls)
	var move_row := HBoxContainer.new()
	transform_controls.add_child(move_row)
	for axis in [Vector3.LEFT,Vector3.RIGHT,Vector3.DOWN,Vector3.UP,Vector3.FORWARD,Vector3.BACK]:
		var names := {Vector3.LEFT:"X−",Vector3.RIGHT:"X+",Vector3.DOWN:"Y−",Vector3.UP:"Y+",Vector3.FORWARD:"Z−",Vector3.BACK:"Z+"}
		tool_button(move_row,names[axis],transform_selected.bind(axis*0.5,0.0,1.0))
	var shape_row := HBoxContainer.new()
	transform_controls.add_child(shape_row)
	tool_button(shape_row,"Rotate 90°",transform_selected.bind(Vector3.ZERO,PI*0.5,1.0))
	tool_button(shape_row,"Scale −",transform_selected.bind(Vector3.ZERO,0.0,1.0/1.1))
	tool_button(shape_row,"Scale +",transform_selected.bind(Vector3.ZERO,0.0,1.1))
	transform_controls.hide()
	help.add_theme_font_size_override("font_size",13)
	content.add_child(help)
	panel.hide()
	select(0)

func select(index: int) -> void:
	if index<0 or index>=catalog.size():
		return
	clear_selection()
	selected=index
	preview.mesh=catalog[index].mesh
	for i in range(choices.size()):
		choices[i].modulate=Color("83d6b2") if i==selected else Color.WHITE
	timer=0

func set_active(value: bool) -> void:
	clear_selection()
	active=value and not catalog.is_empty() and is_instance_valid(camera) and is_instance_valid(player)
	panel.visible=active
	preview.hide()
	timer=0

func tool_button(row: Control, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text=text
	button.focus_mode=Control.FOCUS_NONE
	button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	button.pressed.connect(action)
	row.add_child(button)

func clear_selection() -> void:
	if is_instance_valid(picked_collection) and picked_collection.changed.is_connected(_selected_changed):
		picked_collection.changed.disconnect(_selected_changed)
	picked_collection=null
	picked_id=0
	transform_controls.hide()
	if not catalog.is_empty():
		preview.mesh=catalog[selected].mesh
	preview.hide()
	timer=0

func _selected_changed() -> void:
	# Loads, undo and external edits invalidate selection before an ID can be reused.
	if not transforming:
		clear_selection()

func pick() -> void:
	if not active or not edit_available:
		return
	clear_selection()
	var hit := ray()
	if not hit.is_empty():
		for entry in catalog:
			if hit.collider==entry.collection:
				var id: int = entry.collection.placement_for_body(hit.rid)
				if id>0:
					picked_collection=entry.collection
					picked_id=id
					preview.mesh=entry.mesh
					picked_collection.changed.connect(_selected_changed)
					transform_controls.show()
					refresh()
					notice.emit("Object selected · arrows move · R rotates" if gameplay else "Object selected · arrows move · R rotates · +/− scales")
					return
	notice.emit("Aim at a nearby placed model to select it")

func selected_transform() -> Dictionary:
	if not is_instance_valid(picked_collection) or picked_id<=0:
		return {}
	var p: PackedFloat32Array = picked_collection.get_instance(picked_id)
	if p.size()!=12:
		clear_selection()
		return {}
	var basis := Basis(Vector3(p[0],p[4],p[8]),Vector3(p[1],p[5],p[9]),Vector3(p[2],p[6],p[10]))
	return {"transform":picked_collection.global_transform*Transform3D(basis,Vector3(p[3],p[7],p[11]))}

func transform_selected(offset: Vector3, angle: float, factor: float) -> bool:
	if gameplay and factor!=1.0:
		notice.emit("Resizing objects is available in the free editor")
		return false
	if not active or not edit_available:
		return false
	var current := selected_transform()
	if current.is_empty():
		return false
	var t: Transform3D = current.transform
	t.origin+=offset
	t.basis=Basis(Vector3.UP,angle)*t.basis*factor
	var requested := records(t,picked_collection)
	var prior_barriers: int = history.stats().barriers
	transforming=true
	var accepted: bool = history.update(picked_collection,picked_id,requested,protection())
	transforming=false
	if not is_instance_valid(picked_collection) or history.stats().barriers!=prior_barriers:
		clear_selection()
	timer=0
	refresh()
	notice.emit(("Object transformed" if gameplay else "Object transformed · Ctrl+Z undoes") if accepted else "Transform blocked · move clear or check capacity")
	return accepted

func ray() -> Dictionary:
	if is_instance_valid(block_world):
		return block_world.raycast_scene(camera.global_position,camera.global_position-camera.global_basis.z*48,3,[player.get_rid()])
	var query := PhysicsRayQueryParameters3D.create(camera.global_position,camera.global_position-camera.global_basis.z*48,3)
	query.exclude=[player.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query)

func target() -> Dictionary:
	var hit := ray()
	if hit.is_empty() or hit.normal.y<0.65:
		return {}
	var entry: Dictionary = catalog[selected]
	var basis := Basis(Vector3.UP,quarter_turns*PI*0.5)*Basis.from_scale(entry.scale)
	var local_bounds: AABB = Transform3D(basis,Vector3.ZERO)*entry.mesh.get_aabb()
	var anchor: Vector3 = hit.position
	# Keep support height from the ray; grid snapping changes only horizontal axes.
	anchor.x=snappedf(anchor.x,0.5)
	anchor.z=snappedf(anchor.z,0.5)
	anchor.y-=local_bounds.position.y
	return {"transform":Transform3D(basis,anchor)}

func protection() -> AABB:
	return AABB(player.global_position+Vector3(-0.4,0,-0.4),Vector3(0.8,1.8,0.8))

func records(world_transform: Transform3D, collection: Node3D) -> PackedFloat32Array:
	var t := collection.global_transform.affine_inverse()*world_transform
	return PackedFloat32Array([t.basis.x.x,t.basis.y.x,t.basis.z.x,t.origin.x,t.basis.x.y,t.basis.y.y,t.basis.z.y,t.origin.y,t.basis.x.z,t.basis.y.z,t.basis.z.z,t.origin.z])

func refresh() -> void:
	preview_valid=false
	var status: Dictionary = history.stats()
	var selection := selected_transform()
	if not selection.is_empty():
		caption.text="OBJECT #%d · selected\nUndo %d · Redo %d" % [picked_id,status.undo_steps,status.redo_steps]
		help.text="Arrows X/Z · PgUp/Dn Y · Shift fine\nR Rotate · +/− Scale · Q Clear\nCtrl+Z Undo · Ctrl+Y Redo · M Blocks"
		if gameplay:
			caption.text="OBJECT #%d · selected" % picked_id
			help.text="Arrows X/Z · PgUp/Dn Y · Shift fine\nR Rotate · Q Clear · M Blocks\nNo resizing or undo/redo in gameplay"
		preview.global_transform=selection.transform
		preview_material.albedo_color=Color(1.0,0.72,0.2,0.35)
		preview.show()
		return
	help.text="E Select · R Rotate · RMB Place · LMB Remove\nCtrl+Z Undo · Ctrl+Y / Ctrl+Shift+Z Redo\nM Blocks · F5 Save · Esc Use buttons"
	var hit := target()
	caption.text="OBJECTS · %s · %d°\nUndo %d · Redo %d" % [catalog[selected].title,quarter_turns*90,status.undo_steps,status.redo_steps]
	if gameplay:
		caption.text="OBJECTS · %s · %d°\nCost: %s" % [catalog[selected].title,quarter_turns*90,catalog[selected].get("cost_label","Recipe unavailable")]
		help.text="E Select · R Rotate · RMB Place · LMB Remove\nNo removal refund · Undo/redo and resizing disabled\nM Blocks · F5 Save · Esc Use buttons"
	if hit.is_empty():
		preview.hide()
		return
	var collection: Node3D = catalog[selected].collection
	preview.global_transform=hit.transform
	preview_valid=collection.can_insert_instance(records(hit.transform,collection),protection())
	preview_material.albedo_color=Color(0.3,1.0,0.65,0.42) if preview_valid else Color(1,0.2,0.15,0.42)
	preview.show()

func edit(remove: bool) -> int:
	if not active or not edit_available:
		return 0
	if picked_id>0 and not remove:
		notice.emit("Q clears selection and returns to placement")
		return 0
	if remove:
		var hit := ray()
		if not hit.is_empty():
			for entry in catalog:
				var collection: Node3D = entry.collection
				if hit.collider==collection:
					var id: int = collection.placement_for_body(hit.rid)
					if id>0 and history.erase(collection,id):
						notice.emit("Object removed · F5 saves world")
						return id
		notice.emit("Aim at a nearby placed object to remove it")
		return 0
	var hit := target()
	if hit.is_empty():
		notice.emit("Aim at a nearby upward-facing surface")
		return 0
	var collection: Node3D = catalog[selected].collection
	var id: int = 0
	if gameplay:
		placement_failure="Gameplay placement unavailable"
		if paid_placement.is_valid(): id=paid_placement.call(history,collection,records(hit.transform,collection),protection(),catalog[selected].get("costs",PackedInt64Array()))
	else:
		id=history.insert(collection,records(hit.transform,collection),protection())
	notice.emit("%s placed · F5 saves world" % catalog[selected].title if id>0 else (placement_failure if gameplay else "Placement blocked · move clear or check capacity"))
	timer=0
	return id

func handle_input(event: InputEvent) -> bool:
	if not active:
		return false
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode==KEY_E:
			pick()
			return true
		if event.physical_keycode==KEY_Q:
			clear_selection()
			return true
		if event.physical_keycode>=KEY_1 and event.physical_keycode<KEY_1+catalog.size():
			select(event.physical_keycode-KEY_1)
			return true
		if event.physical_keycode==KEY_R:
			if picked_id>0:
				transform_selected(Vector3.ZERO,PI*0.5,1.0)
				return true
			quarter_turns=(quarter_turns+1)%4
			timer=0
			return true
		if picked_id>0:
			var directions := {KEY_LEFT:Vector3.LEFT,KEY_RIGHT:Vector3.RIGHT,KEY_UP:Vector3.FORWARD,KEY_DOWN:Vector3.BACK,KEY_PAGEUP:Vector3.UP,KEY_PAGEDOWN:Vector3.DOWN}
			if directions.has(event.physical_keycode):
				transform_selected(directions[event.physical_keycode]*(0.1 if event.shift_pressed else 0.5),0.0,1.0)
				return true
			if event.physical_keycode in [KEY_EQUAL,KEY_PLUS,KEY_KP_ADD,KEY_MINUS,KEY_KP_SUBTRACT]:
				transform_selected(Vector3.ZERO,0.0,1.0/1.1 if event.physical_keycode in [KEY_MINUS,KEY_KP_SUBTRACT] else 1.1)
				return true
		if (event.ctrl_pressed or event.meta_pressed) and event.physical_keycode in [KEY_Z,KEY_Y]:
			if gameplay:
				notice.emit("Object undo/redo is available in the free editor")
				return true
			var forward: bool = event.physical_keycode==KEY_Y or event.shift_pressed
			var accepted: bool = history.redo(protection()) if forward else history.undo(protection())
			notice.emit(("Object redo" if forward else "Object undo")+ (" · F5 saves world" if accepted else " unavailable · move clear or check history"))
			timer=0
			return true
		if event.physical_keycode in [KEY_P,KEY_T]:
			return true
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT] and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED:
		edit(event.button_index==MOUSE_BUTTON_LEFT)
		return true
	return false

func update(delta: float, available: bool) -> void:
	edit_available=available
	if not active or not available:
		preview.hide()
		return
	timer-=delta
	if timer<=0:
		timer=0.1
		refresh()

func _exit_tree() -> void:
	clear_selection()
	if is_instance_valid(panel):
		panel.queue_free()
