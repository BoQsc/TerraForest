extends Node3D

const Recipes = preload("res://reviews/modular_buildings/recipes.gd")
const PAIR_OFFSET := 128
var structures: Node3D
var designs: Array[Dictionary] = []
var cameras: Array[Camera3D] = []
var hinges: RefCounted
var current_design := 0
var current_view := 0
var removed := false
var heading: Label
var details: Label
var removal_button: Button
var ready_ok := false
var placement_results: Array[Dictionary] = []
var viewports: Array[SubViewport] = []
var tour_generation := 0
var tour_button: Button
var candidate_label: Label
var review_revision := "R1"

func _ready() -> void:
	Engine.max_fps=60
	DisplayServer.window_set_title("TerraForest | Building review "+review_revision+" | originals unchanged")
	structures=preload("res://addons/structures/structures_world.gd").new()
	add_child(structures)
	if not structures.prepare(): return
	preload("res://addons/structures/material_startup.gd").prepare(structures.blocks)
	preload("res://addons/structures/furniture_catalog.gd").register(structures)
	preload("res://addons/structures/storage_catalog.gd").register(structures)
	preload("res://addons/structures/door_catalog.gd").register(structures)
	preload("res://addons/structures/window_catalog.gd").register(structures)
	designs=review_designs()
	var transaction: RefCounted=ClassDB.instantiate("NativePrefabPlacement")
	for design in designs:
		for side in 2:
			if not include_building(design,side):continue
			var asset: Resource=design.original if side==0 else design.candidate
			if asset==null: return
			var placed: Dictionary=transaction.place(structures.blocks,asset,placement_origin(design,side),0,structures.model_collections(),[])
			placement_results.append(placed)
			if not placed.get("ok",false): return
	structures.blocks.set_collision_radius(256)
	structures.blocks.set_focus(Vector3(64,4,-64))
	structures.blocks.flush_bakes()
	structures.set_model_focus(Vector3(64,4,-64))
	hinges=ClassDB.instantiate("NativeHingedDoors")
	_lighting()
	_interface()
	select_view(0,0)
	ready_ok=true

func review_designs() -> Array[Dictionary]:
	return Recipes.entries()

func placement_origin(design: Dictionary, side: int) -> Vector3i:
	return design.base+Vector3i(side*PAIR_OFFSET,0,0)

func include_building(_design: Dictionary, _side: int) -> bool:
	return true

func _lighting() -> void:
	var environment:=Environment.new()
	environment.background_mode=Environment.BG_COLOR
	environment.background_color=Color("b9cbd4")
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color=Color("e1e8f1")
	environment.ambient_light_energy=.7
	environment.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	environment.ssao_enabled=true
	var world_environment:=WorldEnvironment.new()
	world_environment.environment=environment;add_child(world_environment)
	var sun:=DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-48,-35,0);sun.light_energy=1.7;sun.shadow_enabled=true
	sun.directional_shadow_max_distance=120
	add_child(sun)
	var backdrop:=MeshInstance3D.new()
	var ground:=PlaneMesh.new();ground.size=Vector2(500,500)
	var material:=StandardMaterial3D.new();material.albedo_color=Color("707c75");material.roughness=1
	ground.material=material;backdrop.mesh=ground;backdrop.position.y=-.02;add_child(backdrop)
	var floor_body:=StaticBody3D.new();floor_body.collision_layer=1
	var shape:=BoxShape3D.new();shape.size=Vector3(300,.2,300)
	var collider:=CollisionShape3D.new();collider.shape=shape;collider.position=Vector3(64,-.1,-64)
	floor_body.add_child(collider);add_child(floor_body)

func _label(text: String, size: int, color: Color = Color.WHITE) -> Label:
	var label:=Label.new();label.text=text;label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",color)
	return label

func _interface() -> void:
	var canvas:=CanvasLayer.new();add_child(canvas)
	var backdrop:=ColorRect.new();backdrop.color=Color("111b22");backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);canvas.add_child(backdrop)
	var margin:=MarginContainer.new();margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+edge,24)
	canvas.add_child(margin)
	var column:=VBoxContainer.new();column.add_theme_constant_override("separation",12);margin.add_child(column)
	column.add_child(_label("T E R R A F O R E S T   /   ARCHITECTURE REVIEW   /   "+review_revision,18,Color("8fd5bd")))
	var toolbar:=HBoxContainer.new();toolbar.add_theme_constant_override("separation",12);column.add_child(toolbar)
	heading=_label("",28);heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL;toolbar.add_child(heading)
	for index in designs.size():
		var button:=Button.new();button.text=designs[index].title;button.pressed.connect(select_view.bind(index,0));toolbar.add_child(button)
	for index in 3:
		var button:=Button.new();button.text=["Exterior","Interior","Detail"][index]
		button.pressed.connect(func():select_view(current_design,index));toolbar.add_child(button)
	var pair:=HBoxContainer.new();pair.size_flags_vertical=Control.SIZE_EXPAND_FILL;pair.add_theme_constant_override("separation",16);column.add_child(pair)
	for side in 2:
		var section:=VBoxContainer.new();section.size_flags_horizontal=Control.SIZE_EXPAND_FILL;pair.add_child(section)
		var caption:=_label("EXISTING / UNCHANGED" if side==0 else "",19,Color("b7c6ce") if side==0 else Color("f1cb8f"))
		section.add_child(caption)
		if side==1:candidate_label=caption
		var holder:=SubViewportContainer.new();holder.stretch=true;holder.size_flags_vertical=Control.SIZE_EXPAND_FILL;section.add_child(holder)
		var viewport:=SubViewport.new();viewport.size=Vector2i(920,780);viewport.world_3d=get_world_3d();viewport.msaa_3d=Viewport.MSAA_4X
		viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;holder.add_child(viewport);viewports.append(viewport)
		var camera:=Camera3D.new();camera.fov=50;camera.near=.05;camera.far=90;camera.current=true
		viewport.add_child(camera);cameras.append(camera)
	details=_label("",18,Color("cdd8df"));column.add_child(details)
	var footer:=HBoxContainer.new();footer.add_theme_constant_override("separation",16);column.add_child(footer)
	tour_button=Button.new();tour_button.text="Play guided tour";tour_button.pressed.connect(guided_tour);footer.add_child(tour_button)
	removal_button=Button.new();removal_button.text="Remove ONE arch block";removal_button.pressed.connect(toggle_block);footer.add_child(removal_button)
	var doors:=Button.new();doors.text="Open / close doors";doors.pressed.connect(toggle_doors);footer.add_child(doors)
	var note:=_label("Review only. Originals and player saves untouched.",16,Color("9baeb9"))
	note.size_flags_horizontal=Control.SIZE_EXPAND_FILL;footer.add_child(note)
	var close:=Button.new();close.text="Close";close.pressed.connect(get_tree().quit);footer.add_child(close)

func select_view(design_index: int, view_index: int, from_tour: bool = false) -> void:
	if not from_tour:
		tour_generation+=1
		if tour_button!=null:tour_button.text="Play guided tour"
	if removed: toggle_block()
	current_design=design_index;current_view=view_index
	var design: Dictionary=designs[current_design]
	removal_button.text=design.get("remove_label","Remove ONE arch block")
	match design.decision:
		"rejected":candidate_label.text="REJECTED / ARCHIVED R1"
		"approved_addition":candidate_label.text="APPROVED / ADDITION ONLY"
		"approved_default":candidate_label.text=design.get("approval_label","APPROVED / COTTAGE DEFAULT")
		_:candidate_label.text="PROPOSAL / NOT APPROVED"
	heading.text=design.title+"  /  "+["EXTERIOR","INTERIOR","DETAIL"][current_view]
	details.text=design.details
	for side in 2:
		var origin:=Vector3(design.base)+Vector3(side*PAIR_OFFSET,0,0)
		cameras[side].fov=72 if current_view==1 else 50
		cameras[side].position=origin+(design.eye if current_view==0 else design.inside if current_view==1 else design.feature_eye)
		cameras[side].look_at(origin+(design.aim if current_view==0 else design.inside_aim if current_view==1 else design.feature_aim))
	structures.set_model_focus(Vector3(design.base)+Vector3(PAIR_OFFSET*.5,3,0))

func toggle_block() -> void:
	var design: Dictionary=designs[current_design]
	var removal_view: int=design.get("remove_view",2 if current_design==0 else 1)
	if not removed and current_view!=removal_view:select_view(current_design,removal_view)
	var local_cell: Vector3i=design.remove
	var target: Vector3i=local_cell+design.base+Vector3i(PAIR_OFFSET,0,0)
	var original: int=Recipes.cells_of(design.candidate)[local_cell]
	if structures.blocks.set_cells(PackedInt32Array([target.x,target.y,target.z,original if removed else 0])):
		removed=not removed
		removal_button.text="Restore that block" if removed else design.get("remove_label","Remove ONE arch block")

func guided_tour() -> void:
	tour_generation+=1
	var token:=tour_generation
	tour_button.text="Tour running / click any view to stop"
	for design_index in designs.size():
		for view_index in [0,2,1]:
			if token!=tour_generation:return
			select_view(design_index,view_index,true)
			await get_tree().create_timer(7.5).timeout
	if token==tour_generation:
		tour_button.text="Replay guided tour"

func toggle_doors() -> void:
	var collection: Node3D=structures.model(preload("res://addons/structures/door_catalog.gd").KEY)
	for identity in collection.get_ids(): hinges.toggle(collection,identity,AABB())

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.physical_keycode==KEY_ESCAPE: get_tree().quit()
