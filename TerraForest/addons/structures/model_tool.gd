extends Node3D
## Editor presentation/input glue. Native collections own placement and collision.
signal notice(text: String)
var active := false
var camera: Camera3D
var player: CharacterBody3D
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

func configure(view: Camera3D, actor: CharacterBody3D, entries: Array[Dictionary], ui: Node) -> void:
	camera=view
	player=actor
	catalog=entries
	preview_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	preview_material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	preview.material_override=preview_material
	preview.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(preview)
	preview.hide()
	ui.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.offset_left=-360
	panel.offset_top=-280
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
	var help := Label.new()
	help.text="R Rotate · RMB Place · LMB Remove\nM Blocks · F5 Save · Esc Use buttons"
	help.add_theme_font_size_override("font_size",13)
	content.add_child(help)
	panel.hide()
	select(0)

func select(index: int) -> void:
	if index<0 or index>=catalog.size():
		return
	selected=index
	preview.mesh=catalog[index].mesh
	for i in range(choices.size()):
		choices[i].modulate=Color("83d6b2") if i==selected else Color.WHITE
	timer=0

func set_active(value: bool) -> void:
	active=value and not catalog.is_empty() and is_instance_valid(camera) and is_instance_valid(player)
	panel.visible=active
	preview.hide()
	timer=0

func ray() -> Dictionary:
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
	var hit := target()
	preview_valid=false
	caption.text="OBJECTS · %s · %d°" % [catalog[selected].title,quarter_turns*90]
	if hit.is_empty():
		preview.hide()
		return
	var collection: Node3D = catalog[selected].collection
	preview.global_transform=hit.transform
	preview_valid=collection.can_insert_instance(records(hit.transform,collection),protection())
	preview_material.albedo_color=Color(0.3,1.0,0.65,0.42) if preview_valid else Color(1,0.2,0.15,0.42)
	preview.show()

func edit(remove: bool) -> int:
	if not active:
		return 0
	if remove:
		var hit := ray()
		if not hit.is_empty():
			for entry in catalog:
				var collection: Node3D = entry.collection
				if hit.collider==collection:
					var id: int = collection.placement_for_body(hit.rid)
					if id>0 and collection.remove_instances(PackedInt64Array([id])):
						notice.emit("Object removed · F5 saves world")
						return id
		notice.emit("Aim at a nearby placed object to remove it")
		return 0
	var hit := target()
	if hit.is_empty():
		notice.emit("Aim at a nearby upward-facing surface")
		return 0
	var collection: Node3D = catalog[selected].collection
	var id: int = collection.insert_instance(records(hit.transform,collection),protection())
	notice.emit("%s placed · F5 saves world" % catalog[selected].title if id>0 else "Placement blocked · move clear or check capacity")
	timer=0
	return id

func handle_input(event: InputEvent) -> bool:
	if not active:
		return false
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode>=KEY_1 and event.physical_keycode<KEY_1+catalog.size():
			select(event.physical_keycode-KEY_1)
			return true
		if event.physical_keycode==KEY_R:
			quarter_turns=(quarter_turns+1)%4
			timer=0
			return true
		if (event.ctrl_pressed or event.meta_pressed) and event.physical_keycode in [KEY_Z,KEY_Y]:
			notice.emit("Object undo/redo is not available yet")
			return true
		if event.physical_keycode in [KEY_P,KEY_T]:
			return true
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT] and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED:
		edit(event.button_index==MOUSE_BUTTON_LEFT)
		return true
	return false

func update(delta: float, available: bool) -> void:
	if not active or not available:
		preview.hide()
		return
	timer-=delta
	if timer<=0:
		timer=0.1
		refresh()

func _exit_tree() -> void:
	if is_instance_valid(panel):
		panel.queue_free()
